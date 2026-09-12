clc; clear; close all;

%% 1. 加载数据
mat_file = 'matched_results_with_mode.mat';
if ~isfile(mat_file)
    error('未找到数据文件: %s', mat_file);
end
load(mat_file); % 包含 crest_lon, crest_lat, mode, mooring_time, crest_time 等

%% 2. 设置保存路径与参数
save_dir = 'F:\research\img\bi_dir'; % 图片保存文件夹
if ~exist(save_dir, 'dir')
    mkdir(save_dir);
end

% 系泊点与范围
mooring_lat = 20.816666666666666;
mooring_lon = 115.76666666666667;
radius_km = 30;

% 绘图范围
lon_bound = [110, 122.5];
lat_bound = [18, 23];

% 字体
font_name = 'Times New Roman';
font_size = 14;

% 计算 30km 圆圈 (只需计算一次)
theta = linspace(0, 2*pi, 360);
[lat_circle, lon_circle] = reckon(mooring_lat, mooring_lon, km2deg(radius_km), rad2deg(theta));

%% 3. 循环绘图
num_matches = length(crest_lon);
fprintf('开始生成 %d 张图片...\n', num_matches);

% 使用不可见窗口绘图，速度更快且不干扰操作
hFig = figure('Units', 'pixels', 'Position', [100 100 1000 800], 'Visible', 'off', 'Color', 'w');

for i = 1:num_matches
    clf(hFig); % 清空画布
    
    % --- 3.1 初始化地图 ---
    m_proj('mercator', 'long', lon_bound, 'lat', lat_bound);
    hold on;
    
    % 绘制海岸线
    try
        m_gshhs_i('patch', [0.9 0.9 0.9], 'edgecolor', 'k');
    catch
        m_coast('patch', [0.9 0.9 0.9], 'edgecolor', 'k');
    end
    
    % 绘制网格
    m_grid('box', 'fancy', 'tickdir', 'in', 'linestyle', 'none', ...
           'fontsize', 12, 'fontname', font_name, 'fontweight', 'bold');
       
    % --- 3.2 绘制系泊点与圆圈 ---
    h_circle_plot = m_plot(lon_circle, lat_circle, '--', 'LineWidth', 2, 'Color', [0.8 0 0]);
    h_mooring_plot = m_plot(mooring_lon, mooring_lat, 'rp', 'MarkerSize', 15, 'MarkerFaceColor', 'r');
    
    % --- 3.3 绘制当前的波峰线 ---
    cur_lon = crest_lon{i};
    cur_lat = crest_lat{i};
    cur_mode = mode(i);
    cur_peak_lon = peak_lon(i);
    cur_peak_lat = peak_lat(i);
    
    % 颜色设置
    if cur_mode == 1
        c_style = 'b-'; c_color = 'b'; mode_str = 'Mode-1';
    elseif cur_mode == 2
        c_style = 'm-'; c_color = 'm'; mode_str = 'Mode-2';
    else
        c_style = 'k-'; c_color = 'k'; mode_str = 'Unknown';
    end
    
    % 画线
    h_line = m_plot(cur_lon, cur_lat, c_style, 'LineWidth', 2.5);
    
    % 画凸起点
    if ~isnan(cur_peak_lon)
        m_plot(cur_peak_lon, cur_peak_lat, '.', 'MarkerSize', 15, 'Color', c_color);
    end
    
    % --- 3.4 标题与标注 ---
    % 时间格式化
    t_crest_str = datestr(crest_time(i), 'yyyy-mm-dd HH:MM');
    t_moor_str  = datestr(mooring_time(i), 'yyyy-mm-dd HH:MM');
    
    title_str = {
        sprintf('Match #%d (%s)', i, mode_str),
        ['Crest Sensing: ', t_crest_str],
        ['Mooring Time:  ', t_moor_str]
    };
    
    title(title_str, 'FontSize', 16, 'FontName', font_name, 'FontWeight', 'bold');
    
    % 简单的图例
    legend([h_mooring_plot, h_circle_plot, h_line], ...
           {'Mooring', '30km Radius', ['Crest (' mode_str ')']}, ...
           'Location', 'southeast', 'FontSize', 12);
       
    xlabel('Longitude', 'FontSize', 14, 'FontName', font_name, 'FontWeight', 'bold');
    ylabel('Latitude', 'FontSize', 14, 'FontName', font_name, 'FontWeight', 'bold');
    
    % --- 3.5 保存图片 ---
    % 文件名：序号_模式_波峰时间.jpg
    filename_str = sprintf('%03d_%s_%s.jpg', i, mode_str, datestr(crest_time(i), 'yyyymmdd_HHMM'));
    full_path = fullfile(save_dir, filename_str);
    
    % 保存 (使用 exportgraphics 或 print)
    try
        exportgraphics(hFig, full_path, 'Resolution', 300);
    catch
        saveas(hFig, full_path);
    end
    
    fprintf('  已保存: %s\n', filename_str);
end

close(hFig);
fprintf('全部完成！图片保存在: %s\n', fullfile(pwd, save_dir));
