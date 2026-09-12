clc; clear; close all;

%% ================= 配置区域 =================
% 1. 设置 Shapefile 文件夹路径
shp_dir = 'F:\research\MODIS\shp_files';

% 2. 设置系泊点坐标
mooring_lat = 20.816666666666666;
mooring_lon = 115.76666666666667;

% 3. 筛选角度范围 (只测试 DirIn 在此范围内的线)
target_angle_range = [45, 215]; 

% 4. 绘图暂停时间 (秒)，设为 0 则需按键继续
pause_time = 0; 

%% ================= 初始化 =================
addpath(genpath('..\utils')); % 尝试添加 utils 路径
if ~exist(shp_dir, 'dir')
    error('文件夹不存在: %s', shp_dir);
end

files = dir(fullfile(shp_dir, '*.shp'));
fprintf('找到 %d 个 shapefile 文件，开始测试...\n', length(files));

% 创建图形窗口
hFig = figure('Color', 'w', 'Position', [100, 100, 1400, 600], 'Name', 'Flip Direction Test');

count_processed = 0;
count_flipped = 0;

%% ================= 主循环 =================
for k = 1:length(files)
    filepath = fullfile(files(k).folder, files(k).name);
    try
        lines = shaperead(filepath);
    catch
        warning('无法读取文件: %s', files(k).name);
        continue;
    end
    
    shp_time = getTimeFromFilename(files(k).name); % 尝试从文件名获取时间用于标题，如果没有可忽略
    
    for i = 1:length(lines)
        lat = lines(i).Y;
        lon = lines(i).X;
        
        % % 剔除 NaN
        % m = ~isnan(lat) & ~isnan(lon);
        % lat = lat(m); lon = lon(m);
        
        if numel(lat) < 3, continue; end
        
        % 1. 计算原始方向 (DirIn)
        % 注意：这里为了筛选，必须先算一遍 DirIn。
        % 假设 calcDirection 返回的是数学角度(0=East, 90=North)，转为方位角
        try
            raw_angle = calcDirection(lat, lon);
            dirDegIn = mod(90 - raw_angle, 360);
        catch
            continue; % 如果算不出方向跳过
        end
        
        % 2. 筛选条件：只处理 45 ~ 215 度
        if dirDegIn < target_angle_range(1) || dirDegIn > target_angle_range(2)
            continue;
        end

        m = ~isnan(lat) & ~isnan(lon);
        lat = lat(m); lon = lon(m);
        
        count_processed = count_processed + 1;
        
        % 3. 调用测试函数
        [dirDegOut, doFlip, stats] = maybeFlipCrestDir(lat, lon, mooring_lat, mooring_lon);
        
        if doFlip, count_flipped = count_flipped + 1; end
        
        % ================= 绘图展示 =================
        clf(hFig);
        
        % --- 左图：地图视图 ---
        subplot(1, 2, 1); hold on; axis equal; grid on; box on;
        
        % 画波峰线
        plot(lon, lat, 'k.-', 'LineWidth', 1.5, 'DisplayName', 'Crest Line');
        % 画起点(绿色)和终点(黑色)以辅助判断原始走向
        plot(lon(1), lat(1), 'go', 'MarkerFaceColor', 'g', 'DisplayName', 'Start Idx');
        plot(lon(end), lat(end), 'ks', 'MarkerFaceColor', 'k', 'MarkerSize', 4, 'DisplayName', 'End Idx');
        
        % 画系泊点
        % plot(mooring_lon, mooring_lat, 'rp', 'MarkerFaceColor', 'r', 'MarkerSize', 12, 'DisplayName', 'Mooring');
        
        % 画原始方向 (蓝色虚线箭头)
        midIdx = floor(length(lon)/2);
        quiver_len = 0.05; % 箭头长度(度)
        u_in = sind(dirDegIn) * quiver_len;
        v_in = cosd(dirDegIn) * quiver_len;
        quiver(lon(midIdx), lat(midIdx), u_in, v_in, 0, 'b--', 'LineWidth', 1.5, 'MaxHeadSize', 0.5, 'DisplayName', sprintf('Dir In: %.1f', dirDegIn));
        
        % 画输出方向 (红色实线箭头)
        u_out = sind(dirDegOut) * quiver_len;
        v_out = cosd(dirDegOut) * quiver_len;
        color_out = 'r';
        if ~doFlip, color_out = 'm'; end % 如果没翻转，用紫色显示以便区分
        quiver(lon(midIdx), lat(midIdx), u_out, v_out, 0, [color_out '-'], 'LineWidth', 2, 'MaxHeadSize', 0.5, 'DisplayName', sprintf('Dir Out: %.1f', dirDegOut));
        
        % 连接中点和系泊点的视线（辅助线）
        plot([lon(midIdx), mooring_lon], [lat(midIdx), mooring_lat], 'Color', [0.5 0.5 0.5 0.3], 'LineStyle', ':', 'DisplayName', 'Line of Sight');
        
        xlabel('Longitude'); ylabel('Latitude');
        title(sprintf('File: %s (Idx: %d)', files(k).name, i), 'Interpreter', 'none');
        legend('Location', 'best');
        
        % --- 右图：统计信息 ---
        subplot(1, 2, 2); 
        axis off;
        
        % 构造显示文本
        resultStr = 'NO FLIP';
        colorStr = 'blue';
        if doFlip
            resultStr = 'FLIPPED (180)';
            colorStr = 'red';
        end
        
        infoList = {
            sprintf('\\bf\\fontsize{14}\\color{%s}Result: %s', colorStr, resultStr),
            '',
            '--- Input Info ---',
            sprintf('Dir In (Clockwise from North): %.1f^o', dirDegIn),
            sprintf('Bearing to Mooring: %.1f^o', stats.bearingToMoor),
            sprintf('Angle Diff (|DirIn - Bearing|): %.1f^o', stats.angDiff),
            sprintf('(Flip condition: Straight AND AngDiff > 90)'),
            '',
            '--- Straightness Stats ---',
            sprintf('Is Straight?: %d', stats.isStraight),
            sprintf('Straightness (0-1): %.4f (Thresh: 0.92)', stats.straightness),
            sprintf('Median Turn: %.1f^o (Thresh: 15)', stats.medianTurnDeg),
            sprintf('Max Turn: %.1f^o', stats.maxTurnDeg),
            sprintf('P80 Turn: %.1f^o (Thresh: 35)', stats.p80TurnDeg),
        };
        
        text(0.1, 0.5, infoList, 'Interpreter', 'tex', 'FontSize', 12, 'VerticalAlignment', 'middle');
        title('Decision Statistics');
        
        % 暂停
        if pause_time > 0
            pause(pause_time);
        else
            fprintf('Press any key to continue...\n');
            pause;
        end
    end
end

fprintf('测试结束。共处理 %d 条，翻转 %d 条。\n', count_processed, count_flipped);

%% 辅助函数 (如果没有在路径中)
function dt = getTimeFromFilename(fname)
    % 简单的占位函数，防止报错
    dt = NaT;
    pat = 'A(\d{7}\.\d{4})';
    tokens = regexp(fname, pat, 'tokens');
    if ~isempty(tokens)
        % 解析MODIS文件名逻辑...
    end
end
