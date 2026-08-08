% simu_all_crests_trans_dir_pro.m
% 修复版：解决 K 值位置绘制偏差问题
% 核心修正：绘图反算时直接使用 cData.resLat/Lon，消除原始数据噪声导致的弧长误差

clc; clear; close all;

addpath(genpath('..\utils')); % 确保包含 reachMooringByTranslation 等函数

%% ==================== 参数设置 ====================
angle_tol = 90;       % 角度容差（度）
resample_res = 250;   % 波峰线重采样分辨率 (m)
lambda_dir = 0;       % 方向差权重
output_mat_name = 'matched_results_with_original.mat';

% 系泊点坐标
mooring_lat = 20.816666666666666;
mooring_lon = 115.76666666666667;

% 监测半径 (米)
MOORING_RADIUS = 100000; % 100km

day_delay = 3;

%% ==================== 数据读取 ====================
shp_dir = 'F:\research\MODIS\shp_files';
shp_filelist = dir(fullfile(shp_dir, '*.shp'));

% 读取系泊数据
mooring_dir = 'F:\research\月份挑内波数据';
mooring_name = '2020年内波时间与方向.xlsx'; 
T = readtable(fullfile(mooring_dir, mooring_name));

% 解析表格列
obs_modes = T{:, 1}; % Mode
st_times  = T{:, 2}; % Start Time
ed_times  = T{:, 3}; % End Time
obs_dirs  = T{:, 5}; % Direction

numCrests = 0;
for k = 1:length(shp_filelist)
    shp_name = fullfile(shp_dir, shp_filelist(k).name);
    S = shaperead(shp_name);
    numCrests = numCrests + length(S);
end

%% ==================== 主循环：计算与匹配 ====================
% 初始化存储容器
w = Inf(numCrests, size(T, 1));            
dir_diff_mat = Inf(numCrests, size(T, 1)); 

crestLen = zeros(numCrests, size(T, 1));
crestDir_arr = zeros(numCrests, 1);
crest_sensing_time = cell(numCrests, 1);
temp_crest_data = cell(numCrests, 1); 
signedPos_list = zeros(numCrests, 1);
isPass_list = zeros(numCrests, 1);

idxCrests = 0;
fprintf('开始处理 %d 个文件...\n', length(shp_filelist));

res = {};

for k = 1:length(shp_filelist)
    shp_name = fullfile(shp_dir, shp_filelist(k).name);
    shp_time = getTimeFromFilename(shp_name);
    shp_time = shp_time + hours(8); % UTC -> Local
    
    idx = st_times >= (shp_time - days(day_delay)) & ...
          st_times <= (shp_time + days(day_delay));
    current_mooring_indices = find(idx);
    
    crestLines = shaperead(shp_name);
    
    for i = 1:length(crestLines)
        global_idx = idxCrests + i;
        rawLat = crestLines(i).Y;
        rawLon = crestLines(i).X;

        % if global_idx ~= 751 && global_idx ~= 752 && global_idx ~= 756 && global_idx ~= 757
        %     continue;
        % end

        % if global_idx ~= 1388
        %     continue;
        % end

        res = [res; {rawLon, rawLat}];
        % continue;
        
        % 1. 计算传播方向 & 方向校正
        cDir = mod(90 - calcDirection(rawLat, rawLon), 360);
        if cDir > 45 && cDir < 180
            [dirDegOut, doFlip, ~] = maybeFlipCrestDir(rawLat, rawLon, mooring_lat, mooring_lon);
            if doFlip
                dirDeg = dirDegOut;
            end
        end

        if cDir >= 15 & cDir <= 165
            % if max(rawLat(~isnan(rawLat))) < 19.2 & max(rawLat(~isnan(rawLat))) < 114.5
            %     plot(rawLon, rawLat);
                continue;
            % end
        end

        rawLon = rawLon(:);
        rawLat = rawLat(:);

        % 2. 几何分析 (重采样 + 找最大曲率点)
        [resLat, resLon, peakLat, peakLon, s_peak, L_total] = analyze_crest_shape_orig(rawLat, rawLon, resample_res);
    
        cData.resLat = resLat; cData.resLon = resLon;
        cData.peakLat = peakLat; cData.peakLon = peakLon;
        cData.s_peak = s_peak; cData.L_total = L_total;
        temp_crest_data{global_idx} = cData;
    
        % 3. 调用传播函数 (传入 s_peak，启用“圈内找最近”逻辑)
        [isPass, ~, s_hit_meters, ~, ~, propLat, propLon] = reachMooringByTranslation( ...
            resLat, resLon, shp_time, ...
            mooring_lat, mooring_lon, [0.1 5.0], MOORING_RADIUS, s_peak);
        
        isPass_list(global_idx) = isPass;
    
        % 4. 分段归一化计算 K 值
        K_val = NaN;
        if ~isnan(s_hit_meters) && ~isnan(s_peak) && L_total > 0
            s_hit = max(0, min(s_hit_meters, L_total));
            
            if s_hit <= s_peak
                % SW段 (-1 ~ 0)
                if s_peak > 1e-3
                    K_val = (s_hit - s_peak) / s_peak;
                else
                    K_val = -1; 
                end
            else
                % NE段 (0 ~ 1)
                len_north = L_total - s_peak;
                if len_north > 1e-3
                    K_val = (s_hit - s_peak) / len_north;
                else
                    K_val = 1; 
                end
            end
        end
        
        signedPos_list(global_idx) = K_val;
        signedPos_Moor = K_val;

        % % 5. 绘图与可视化
        % figure(1); clf;
        % plot(rawLon, rawLat, 'b.-', 'DisplayName', 'Original'); 
        % hold on;
        % plot(mooring_lon, mooring_lat, 'ro', 'MarkerFaceColor', 'r'); 
        % 
        % % 绘制监测半径
        % [lat_circle, lon_circle] = scircle1(mooring_lat, mooring_lon, km2deg(MOORING_RADIUS/1000));
        % plot(lon_circle, lat_circle, 'r--', 'LineWidth', 1);
        % plot(propLon, propLat, '--');

        % --- 【修复版绘图逻辑】 ---
        % 使用重采样后的物理模型 cData 进行反算，确保位置与 K 值严格对应
        if ~isempty(cData.resLat) && ~isnan(signedPos_Moor)
            % A. 构建物理弧长轴
            num_pts = length(cData.resLat);
            if num_pts > 1
                s_axis = linspace(0, cData.L_total, num_pts)';

                % B. 根据 K 反推物理弧长 s_target
                s_p = cData.s_peak;
                L   = cData.L_total;
                s_target = 0;

                if signedPos_Moor <= 0
                    % 西南段 (-1 ~ 0): s = s_p * (K + 1)
                    s_target = s_p * (signedPos_Moor + 1);
                else
                    % 东北段 (0 ~ 1): s = s_p + K * (L - s_p)
                    s_target = s_p + signedPos_Moor * (L - s_p);
                end

                s_target = max(0, min(s_target, L));

                % C. 插值寻找经纬度 (在平滑曲线上插值)
                p_lat = interp1(s_axis, cData.resLat, s_target, 'linear');
                p_lon = interp1(s_axis, cData.resLon, s_target, 'linear');

                % % D. 绘制
                % plot(p_lon, p_lat, 'pentagram', ...
                %      'MarkerSize', 15, ...
                %      'MarkerEdgeColor', 'k', ...
                %      'MarkerFaceColor', 'g', ...
                %      'LineWidth', 1.5);
                % 
                % text(p_lon, p_lat, sprintf('  K=%.2f', signedPos_Moor), ...
                %      'Color', 'blue', 'FontSize', 12, 'FontWeight', 'bold');
            end
        end

        % title(sprintf('File: %d, Crest: %d, isPass: %d, K: %.4f', k, i, isPass, signedPos_Moor));
        % axis equal; grid on;
        % drawnow;
        
        % 6. 保存数据
        crestDir_arr(global_idx) = cDir;
        crest_sensing_time{global_idx} = shp_time;

        % % 5. 变量重命名与保存
        % crest_time    = shp_time;
        % crest_dir     = cDir;
        % crest_lon     = resLon;
        % crest_lat     = resLat;
        % peak_lon      = peakLon;
        % peak_lat      = peakLat;
        % K_mooring     = signedPos_Moor;
        % crest_len     = L_total;
        % crest_out_idx = global_idx;
        % 
        % out_name_1388 = 'crest_1388_detail.mat';
        % save(out_name_1388, 'crest_time', 'crest_dir', 'crest_lon', 'crest_lat', ...
        %      'peak_lon', 'peak_lat', 'K_mooring', 'crest_len', 'crest_out_idx');
        % 
        % fprintf('波峰线 1388 信息已保存至: %s\n', out_name_1388);
        % fprintf('K_mooring = %.4f\n', K_mooring);
        % return;
        
        for j = 1:length(current_mooring_indices)
            target_mooring_idx = current_mooring_indices(j);
            target_obs_dir = obs_dirs(target_mooring_idx);
            current_mode   = obs_modes(target_mooring_idx);

            % --- 方向筛选 ---
            d_diff = abs(cDir - target_obs_dir);
            if d_diff > 180, d_diff = 360 - d_diff; end

            if d_diff > angle_tol
                continue; 
            end

            % --- 传播检测 ---
            param_val = T{target_mooring_idx, 4}; % 假设第4列是速度相关参数
            [isPass, propSpeed, crest_min_dis] = isCrestPassMooring_bin(rawLat, rawLon, shp_time, ...
                current_mode, mooring_lat, mooring_lon, ...
                st_times(target_mooring_idx), ed_times(target_mooring_idx), ...
                60, 86400*10, 100000);
            
            if isPass
                % 这里使用占位符计算匹配权重，请根据需要恢复原有逻辑
                % 计算速度差
                if min(abs(propSpeed)) <= param_val && max(abs(propSpeed)) >= param_val
                    s_diff = 0;
                else
                    s_diff = min(abs(abs(propSpeed) - param_val));
                end
                
                w(global_idx, target_mooring_idx) = s_diff + lambda_dir * d_diff; 
                dir_diff_mat(global_idx, target_mooring_idx) = d_diff;
                crestLen(global_idx, target_mooring_idx) = cData.L_total;
            end
        end
    end
    idxCrests = idxCrests + length(crestLines);
end

%% ==================== 匈牙利算法匹配 ====================
valid_idx = find(~all(isinf(w), 2));
w_vaild = w(valid_idx, :);
[M, ~, ~] = matchpairs(w, 10000000);
num_matches = size(M, 1);

%% ==================== 结果提取与保存 (指定波峰线参数) ====================
% 说明：提取并保存 mode, mooring_time, crest_time, crest_dir, crest_lon, crest_lat, 
%             peak_lon, peak_lat, K_mooring, crest_len
idxCrests = 0;
for k = 1:length(shp_filelist)
    shp_name = fullfile(shp_dir, shp_filelist(k).name);
    crestLines = shaperead(shp_name);
    for i = 1:length(crestLines)
        global_idx = idxCrests + i;
        shp_time = getTimeFromFilename(shp_name);
        shp_time = shp_time + hours(8); % UTC -> Local
        crest_sensing_time{global_idx} = shp_time;
        
        global_idx = idxCrests + i;
        rawLat = crestLines(i).Y;
        rawLon = crestLines(i).X;

        % 1. 计算传播方向 & 方向校正
        cDir = mod(90 - calcDirection(rawLat, rawLon), 360);
        crestDir_arr(global_idx) = cDir;
    end
    idxCrests = idxCrests + length(crestLines);
end

%% 
% 1. 匈牙利算法匹配结果 M = [crest_idx, mooring_idx]
% 由于主循环中已经过滤了 global_idx (只计算了 751, 752, 756, 757)，
% w 矩阵中只有这几行有效，matchpairs 会自动匹配这些行。
num_matches = size(M, 1);

% 2. 初始化变量 (使用要求的变量名)
mode         = zeros(num_matches, 1);
mooring_time = NaT(num_matches, 1);
crest_time   = NaT(num_matches, 1);
crest_dir    = zeros(num_matches, 1);
crest_lon    = cell(num_matches, 1); % 使用 cell 存储，因为波峰线长度可能不同
crest_lat    = cell(num_matches, 1);
peak_lon     = zeros(num_matches, 1);
peak_lat     = zeros(num_matches, 1);
K_mooring    = zeros(num_matches, 1);
crest_len    = zeros(num_matches, 1);
crest_idx_out = zeros(num_matches, 1); % 额外保存索引，方便核对

fprintf('正在提取 %d 条匹配波峰线的详细参数...\n', num_matches);

valid_count = 0;
for k = 1:num_matches
    cIdx = M(k, 1); % 波峰线全局索引 (Global Index)
    mIdx = M(k, 2); % 锚系数据索引
    
    % 获取缓存的波峰线几何数据
    % 注意：因为主循环跳过了其他波峰线，只有被计算过的 cIdx 才有数据
    if cIdx > length(temp_crest_data) || isempty(temp_crest_data{cIdx})
        continue;
    end
    
    valid_count = valid_count + 1;
    cData = temp_crest_data{cIdx}; 
    
    % --- 提取参数 ---
    
    % 1. mode: 匹配锚系观测内波对应模态 (1或2)
    mode(valid_count) = obs_modes(mIdx);
    
    % 2. mooring_time: 匹配到的锚系观测内波开始时间
    mooring_time(valid_count) = st_times(mIdx);
    
    % 3. crest_time: 匹配对应波峰线 sensing 时间
    crest_time(valid_count) = crest_sensing_time{cIdx};
    
    % 4. crest_dir: 匹配对应波峰线传播方向
    crest_dir(valid_count) = crestDir_arr(cIdx);
    
    % 5 & 6. crest_lon / crest_lat: 匹配对应波峰线经纬度（重采样为250m分辨率）
    crest_lon{valid_count} = cData.resLon;
    crest_lat{valid_count} = cData.resLat;
    
    % 7 & 8. peak_lon / peak_lat: 波峰线计算出的曲率凸起点坐标
    peak_lon(valid_count) = cData.peakLon;
    peak_lat(valid_count) = cData.peakLat;
    
    % 9. K_mooring: 波峰线经过锚系点的系数 [-1(南), 0(曲率凸起点), 1(北)]
    K_mooring(valid_count) = signedPos_list(cIdx);
    
    % 10. crest_len: 波峰线长度
    crest_len(valid_count) = cData.L_total;
    
    crest_idx_out(valid_count) = cIdx;
end

% 截断未使用的预分配空间
if valid_count < num_matches
    mode         = mode(1:valid_count);
    mooring_time = mooring_time(1:valid_count);
    crest_time   = crest_time(1:valid_count);
    crest_dir    = crest_dir(1:valid_count);
    crest_lon    = crest_lon(1:valid_count);
    crest_lat    = crest_lat(1:valid_count);
    peak_lon     = peak_lon(1:valid_count);
    peak_lat     = peak_lat(1:valid_count);
    K_mooring    = K_mooring(1:valid_count);
    crest_len    = crest_len(1:valid_count);
    crest_idx_out = crest_idx_out(1:valid_count);
end

% --- 按锚系时间排序 ---
[mooring_time, sort_idx] = sort(mooring_time);

mode       = mode(sort_idx);
crest_time = crest_time(sort_idx);
crest_dir  = crest_dir(sort_idx);
crest_lon  = crest_lon(sort_idx);
crest_lat  = crest_lat(sort_idx);
peak_lon   = peak_lon(sort_idx);
peak_lat   = peak_lat(sort_idx);
K_mooring  = K_mooring(sort_idx);
crest_len  = crest_len(sort_idx);
crest_idx_out = crest_idx_out(sort_idx);

% --- 保存到 MAT 文件 ---
output_filename = 'matched_crests_params_855.mat';
save(output_filename, ...
    'mode', 'mooring_time', 'crest_time', 'crest_dir', ...
    'crest_lon', 'crest_lat', 'peak_lon', 'peak_lat', ...
    'K_mooring', 'crest_len', 'crest_idx_out');

fprintf('提取完成！已保存 %d 条波峰线的参数至 %s\n', valid_count, output_filename);
% 显示部分结果以供检查
disp('提取结果预览 (Top 5):');
T_preview = table(crest_idx_out, mode, mooring_time, K_mooring, crest_len, 'VariableNames', {'Index', 'Mode', 'MooringTime', 'K', 'Length'});
disp(head(T_preview, 5));

%% 数据检验

%% ==================== 结果提取与保存 (添加版) ====================
% 假设 M 是匈牙利算法匹配后的索引矩阵 [crest_idx, mooring_idx]
num_matches = size(M, 1);

% 1. 初始化变量
save_mode         = zeros(num_matches, 1);
save_mooring_time = NaT(num_matches, 1);
save_crest_time   = NaT(num_matches, 1);
save_crest_dir    = zeros(num_matches, 1);
save_crest_lon    = cell(num_matches, 1); % 使用 cell 存储不同长度的数组
save_crest_lat    = cell(num_matches, 1);
save_peak_lon     = zeros(num_matches, 1);
save_peak_lat     = zeros(num_matches, 1);
save_K_mooring    = zeros(num_matches, 1);
save_crest_len    = zeros(num_matches, 1);

fprintf('正在提取 %d 条匹配波峰线的详细参数...\n', num_matches);

for k = 1:num_matches
    cIdx = M(k, 1); % 波峰线索引
    mIdx = M(k, 2); % 锚系数据索引
    
    % 获取缓存的波峰线几何数据
    cData = temp_crest_data{cIdx}; 
    
    % --- 提取要求的参数 ---
    
    % 1. mode: 匹配模态 (1或2)
    save_mode(k) = obs_modes(mIdx);
    
    % 2. mooring_time: 锚系观测开始时间
    save_mooring_time(k) = st_times(mIdx);
    
    % 3. crest_time: 卫星成像时间
    save_crest_time(k) = crest_sensing_time{cIdx};
    
    % 4. crest_dir: 传播方向
    save_crest_dir(k) = crestDir_arr(cIdx);
    
    % 5 & 6. crest_lon/lat: 重采样后的经纬度 (250m分辨率)
    save_crest_lon{k} = cData.resLon;
    save_crest_lat{k} = cData.resLat;
    
    % 7 & 8. peak_lon/lat: 曲率凸起点坐标
    save_peak_lon(k) = cData.peakLon;
    save_peak_lat(k) = cData.peakLat;
    
    % 9. K_mooring: 相对位置系数 [-1, 0, 1]
    % 直接取主循环中计算好的值 (signedPos_list 存储了 K 值)
    save_K_mooring(k) = signedPos_list(cIdx);
    
    % 10. crest_len: 波峰线长度 (米)
    save_crest_len(k) = cData.L_total;
end

% --- 按锚系时间排序 ---
[save_mooring_time, sort_idx] = sort(save_mooring_time);

% 同步调整所有变量顺序
save_mode       = save_mode(sort_idx);
save_crest_time = save_crest_time(sort_idx);
save_crest_dir  = save_crest_dir(sort_idx);
save_crest_lon  = save_crest_lon(sort_idx);
save_crest_lat  = save_crest_lat(sort_idx);
save_peak_lon   = save_peak_lon(sort_idx);
save_peak_lat   = save_peak_lat(sort_idx);
save_K_mooring  = save_K_mooring(sort_idx);
save_crest_len  = save_crest_len(sort_idx);

% --- 保存到 MAT 文件 ---
output_filename = 'matched_crest_params.mat';
save(output_filename, ...
    'mode', 'mooring_time', 'crest_time', 'crest_dir', ...
    'crest_lon', 'crest_lat', 'peak_lon', 'peak_lat', ...
    'save_K_mooring', 'save_crest_len');

fprintf('所有参数已保存至 %s\n', output_filename);

%% ==================== 辅助函数：曲率分析 ====================
function [resLat, resLon, peakLat, peakLon, s_peak, L_total] = analyze_crest_shape(lat, lon, ds_res)
    % 1. 基础清洗 & 强制列向量
    lat = lat(:); lon = lon(:); 
    good = isfinite(lat) & isfinite(lon);
    lat = lat(good); lon = lon(good);
    
    if length(lat) < 3
        resLat=lat; resLon=lon; peakLat=NaN; peakLon=NaN; s_peak=NaN; L_total=0; return; 
    end
    
    % 2. 投影到局部米制坐标
    R_earth = 6371000;
    lat0 = mean(lat); lon0 = mean(lon);
    x = R_earth * cosd(lat0) .* deg2rad(lon - lon0);
    y = R_earth * deg2rad(lat - lat0);
    
    % 去重
    d_seg = hypot(diff(x), diff(y));
    keep_mask = [true; d_seg > 1e-3]; 
    x = x(keep_mask); y = y(keep_mask);
    lat = lat(keep_mask); lon = lon(keep_mask);
    
    if length(x) < 3
         resLat=lat; resLon=lon; peakLat=NaN; peakLon=NaN; s_peak=NaN; L_total=0; return; 
    end
    
    % 强制 SW -> NE 排序
    if (y(1)) > (y(end))
        x = flipud(x); y = flipud(y);
        lat = flipud(lat); lon = flipud(lon);
    end
    
    % ==========================================================
    % Step 3. 极高密度线性重采样
    % ==========================================================
    ds0 = hypot(diff(x), diff(y));
    s0 = [0; cumsum(ds0)];
    L_original = s0(end);
    
    s_super = (0:10:L_original)'; 
    if isempty(s_super), s_super = [0; L_original]; end
    
    x_super = interp1(s0, x, s_super, 'linear');
    y_super = interp1(s0, y, s_super, 'linear');
    lon_super = interp1(s0, lon, s_super, 'linear');
    lat_super = interp1(s0, lat, s_super, 'linear');
    
    % ==========================================================
    % Step 4. 坐标高斯平滑 + 端点锚定
    % ==========================================================
    smooth_window_m = 5000; 
    win_pts = max(3, round(smooth_window_m / 10)); 
    
    x_smooth = smoothdata(x_super, 'gaussian', win_pts);
    y_smooth = smoothdata(y_super, 'gaussian', win_pts);
    lon_smooth = smoothdata(lon_super, 'gaussian', win_pts);
    lat_smooth = smoothdata(lat_super, 'gaussian', win_pts);
    
    x_smooth(1) = x_super(1); x_smooth(end) = x_super(end);
    y_smooth(1) = y_super(1); y_smooth(end) = y_super(end);
    lon_smooth(1) = lon_super(1); lon_smooth(end) = lon_super(end);
    lat_smooth(1) = lat_super(1); lat_smooth(end) = lat_super(end);
    
    % ==========================================================
    % Step 5. 最终重采样
    % ==========================================================
    d_smooth_steps = hypot(diff(x_smooth), diff(y_smooth));
    s_smooth_cum = [0; cumsum(d_smooth_steps)];
    L_total = s_smooth_cum(end); 
    
    s_final = (0:ds_res:L_total)';
    if isempty(s_final), s_final = [0; L_total]; end
    
    xr = interp1(s_smooth_cum, x_smooth, s_final, 'linear');
    yr = interp1(s_smooth_cum, y_smooth, s_final, 'linear');
    resLon = interp1(s_smooth_cum, lon_smooth, s_final, 'linear');
    resLat = interp1(s_smooth_cum, lat_smooth, s_final, 'linear');
    
    s_new = s_final;
    Ns = length(s_new);
    if Ns < 5
         peakLat=NaN; peakLon=NaN; s_peak=NaN; return;
    end
    
    % ==========================================================
    % Step 6. 计算带符号曲率 (Signed Curvature)
    % ==========================================================
    % 为了区分凹凸，必须计算有符号的行列式
    k_signed = nan(Ns, 1);
    
    x1 = xr(1:end-2); y1 = yr(1:end-2);
    x2 = xr(2:end-1); y2 = yr(2:end-1);
    x3 = xr(3:end);   y3 = yr(3:end);
    
    a = hypot(x2-x1, y2-y1);
    b = hypot(x3-x2, y3-y2);
    c = hypot(x3-x1, y3-y1);
    
    % 计算有符号面积 (2D Cross Product)
    % det > 0 表示向左转，det < 0 表示向右转
    det_val = (x2-x1).*(y3-y2) - (y2-y1).*(x3-x2);
    
    denom = a.*b.*c;
    denom(denom < 1e-6) = 1e-6; 
    
    % k_signed 包含了方向信息 (+/-)
    k_mid = 2 * det_val ./ denom;
    k_signed(2:end-1) = k_mid;
    
    % ==========================================================
    % Step 7. 【核心新增】凹凸性一致性筛选 (Convexity Consistency)
    % ==========================================================
    
    % 1. 判断整条线的“主弯曲方向” (Dominant Direction)
    % 通过对所有点的曲率求和，看整体是往哪边弯
    % (忽略 NaN)
    valid_k = k_signed(~isnan(k_signed));
    
    if isempty(valid_k)
        main_sign = 0;
    else
        % 投票法：看正曲率总和与负曲率总和谁大
        sum_pos = sum(valid_k(valid_k > 0));
        sum_neg = sum(valid_k(valid_k < 0));
        
        if abs(sum_pos) > abs(sum_neg)
            main_sign = 1;  % 整体向左弯 (凸)
        else
            main_sign = -1; % 整体向右弯 (凸)
        end
    end
    
    % 2. 过滤：只保留“凸”的曲率，剔除“凹”的曲率
    % 任何与主方向符号相反的点，其曲率强度视为 0 (或极小)
    kappa_mag = abs(k_signed); % 取绝对值用于找最大
    
    % 如果某点符号与主符号相反，且曲率不是微小噪声，则视为反向弯曲(凹)，剔除
    % (阈值 1e-6 防止处理直线噪声)
    bad_mask = (sign(k_signed) ~= main_sign) & (abs(k_signed) > 1e-6);
    kappa_mag(bad_mask) = 0; 
    
    % ==========================================================
    % Step 8. 寻找 Peak (含平直度检测)
    % ==========================================================
    chord_len = hypot(xr(end)-xr(1), yr(end)-yr(1));
    straightness = chord_len / L_total; 
    
    if straightness > 0.99
        sigma = 0.15; 
        s_norm = s_new / L_total;
        w_gaussian = exp(- (s_norm - 0.5).^2 / (2 * sigma^2));
    elseif straightness > 0.95
        sigma = 0.3;
        s_norm = s_new / L_total;
        w_gaussian = exp(- (s_norm - 0.5).^2 / (2 * sigma^2));
    else
        w_guassian = sin(pi * (s_new/L_total)).^2;
    end
    
    cut_idx = round(Ns * 0.1); 
    if cut_idx > 0 && cut_idx*2 < Ns
        w_gaussian(1:cut_idx) = 0;
        w_gaussian(end-cut_idx:end) = 0;
    end
    
    % 这里的 kappa_mag 已经是剔除了凹点的版本
    kappa_weighted = kappa_mag .* w_gaussian;
    
    [~, idx_peak] = max(kappa_weighted, [], 'omitnan');
    
    if isempty(idx_peak) || isnan(kappa_mag(idx_peak))
        idx_peak = round(Ns/2);
    end
    
    peakLat = resLat(idx_peak);
    peakLon = resLon(idx_peak);
    s_peak = s_new(idx_peak);
    
    plot(resLon, resLat)
    hold on
    plot(lon, lat)
    plot(peakLon, peakLat, 'pentagram', ...
                     'MarkerSize', 15, ...
                     'MarkerEdgeColor', 'k', ...
                     'MarkerFaceColor', 'g', ...
                     'LineWidth', 1.5);
    ;
end

function [lat, lon] = scircle1(lat0, lon0, radius_deg)
    th = linspace(0, 2*pi, 100);
    [lat, lon] = reckon(lat0, lon0, radius_deg, rad2deg(th));
end

function [resLat, resLon, peakLat, peakLon, s_peak, L_total] = analyze_crest_shape_orig(lat, lon, ds_res)
% ANALYZE_CREST_SHAPE 分析波峰线几何形状并寻找凸起点
% 
% 输入:
%   lat, lon: 原始波峰线的经纬度数组
%   ds_res:   期望的重采样分辨率 (米)，例如 250 或 1000
%
% 输出:
%   resLat, resLon: 重采样并平滑后的经纬度
%   peakLat, peakLon: 识别出的凸起点坐标
%   s_peak: 凸起点对应的弧长 (米)
%   L_total: 波峰线总长度 (米)
%
% 算法逻辑来自 plot_curv.m:
%   1. 投影到局部平面坐标
%   2. 自适应重采样 (保证点数足够)
%   3. 几何大尺度平滑 (消除锯齿)
%   4. 三点外接圆法计算曲率 + 二次平滑
%   5. 加权曲率寻峰 (Sin^2 权重抑制端点)

    %% 1. 参数配置 (内部硬编码或根据需要改为输入参数)
    cfg.R_earth = 6371000;     % 地球半径 (m)
    cfg.minN_raw = 2;          % 原始点数下限
    cfg.minNs_target = 60;     % 目标重采样点数下限 (保证平滑窗口有效)
    
    % 平滑参数 (根据 plot_curv.m 的设置)
    cfg.smooth_km = 20;        % 几何平滑尺度 (km)
    cfg.kappaSmooth_km = 10;   % 曲率再平滑尺度 (km)
    cfg.dropEdgePct = 0.05;    % 首尾剔除比例

    %% 2. 初始化输出
    resLat = []; resLon = [];
    peakLat = NaN; peakLon = NaN;
    s_peak = NaN; L_total = 0;

    %% 3. 数据预处理
    lat = lat(:); lon = lon(:);
    good = isfinite(lat) & isfinite(lon);
    lat = lat(good); lon = lon(good);

    if numel(lat) < cfg.minN_raw
        return; % 点数过少
    end

    %% 4. 投影到局部平面坐标 (米)
    lon0 = mean(lon);
    lat0 = mean(lat);
    x = cfg.R_earth * cosd(lat0) .* deg2rad(lon - lon0);
    y = cfg.R_earth * deg2rad(lat - lat0);

    % 去掉重复点/零步长，确保弧长严格递增
    ds_xy = hypot(diff(x), diff(y));
    keep  = [true; ds_xy > 1e-3]; % 容差 1mm
    x = x(keep); y = y(keep);
    lon = lon(keep); lat = lat(keep);

    if numel(x) < cfg.minN_raw
        return;
    end

    %% 5. 计算原始弧长
    ds0 = hypot(diff(x), diff(y));
    s0  = [0; cumsum(ds0)];
    L_total = s0(end);

    if L_total <= 0
        return;
    end

    %% 6. 自适应重采样
    % 逻辑：如果 total_length / ds_res 得到的点数太少，自动减小 ds
    ds = ds_res;
    Ns_est = floor(L_total / ds) + 1;
    
    if Ns_est < cfg.minNs_target
        % 强制保证至少有 minNs_target 个点，以便进行后续的平滑操作
        ds = L_total / (cfg.minNs_target - 1);
    end

    % 等弧长重采样
    s_new = (0:ds:L_total)';
    Ns = numel(s_new);
    
    if Ns < 12
        return; % 重采样后点数依然极少，无法计算
    end

    % 使用 pchip 插值 (保持形状单调性，避免 spline 的过冲)
    xr   = interp1(s0, x,   s_new, 'pchip');
    yr   = interp1(s0, y,   s_new, 'pchip');
    resLon = interp1(s0, lon, s_new, 'pchip');
    resLat = interp1(s0, lat, s_new, 'pchip');

    %% 7. 几何大尺度平滑 (Coordinate Smoothing)
    % 窗口大小自适应： smooth_km (m) / ds (m)
    winG = max(5, round((cfg.smooth_km * 1000) / ds));
    if mod(winG, 2) == 0, winG = winG + 1; end % 保证奇数窗口
    winG = min(winG, Ns);

    xs = smoothdata(xr, 'movmean', winG);
    ys = smoothdata(yr, 'movmean', winG);

    %% 8. 计算曲率 (三点外接圆法)
    kappa = nan(Ns, 1);
    
    x1 = xs(1:end-2); y1 = ys(1:end-2);
    x2 = xs(2:end-1); y2 = ys(2:end-1);
    x3 = xs(3:end);   y3 = ys(3:end);

    a = hypot(x2-x1, y2-y1);
    b = hypot(x3-x2, y3-y2);
    c = hypot(x3-x1, y3-y1);

    % 三角形面积 = 0.5 * |cross_product|
    % 2*Area = |(x2-x1)(y3-y1) - (y2-y1)(x3-x1)|
    area2 = abs((x2-x1).*(y3-y1) - (y2-y1).*(x3-x1));
    
    % Menger Curvature k = 4*Area / (a*b*c)
    denom = a.*b.*c;
    denom(denom < 1e-9) = NaN; % 防止除零
    k_mid = 2 * area2 ./ denom; 

    kappa(2:end-1) = k_mid;
    
    % 填充边界NaN (简单设为邻近值或0)
    if isnan(kappa(1)), kappa(1) = kappa(2); end
    if isnan(kappa(end)), kappa(end) = kappa(end-1); end

    %% 9. 曲率再平滑 (Curvature Smoothing)
    winK = max(5, round((cfg.kappaSmooth_km * 1000) / ds));
    if mod(winK, 2) == 0, winK = winK + 1; end
    winK = min(winK, Ns);
    
    kappa_s = smoothdata(kappa, 'movmean', winK);

    %% 10. 加权寻峰 (Weighted Peak Finding)
    % 剔除首尾比例
    dropN = max(2, round(cfg.dropEdgePct * Ns));
    
    % 权重函数：中间高，两头低 (sin^2)
    w_weight = sin(pi * (s_new / L_total)).^2;
    
    % 目标函数
    obj = kappa_s .* w_weight;

    % 强制边缘无效化
    obj(1:dropN) = NaN;
    obj(end-dropN+1:end) = NaN;

    % 寻找最大值
    [~, idxK] = max(obj, [], 'omitnan');

    if isempty(idxK)
        % 兜底：如果算不出，取几何中心
        idxK = round(Ns/2);
    end

    %% 11. 输出赋值
    peakLat = resLat(idxK);
    peakLon = resLon(idxK);
    s_peak  = s_new(idxK);

end
