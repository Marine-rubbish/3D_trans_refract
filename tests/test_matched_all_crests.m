%% 1. 加载匹配结果数据
% 确保文件名与上一步保存的一致
mat_file = 'matched_results_with_mode.mat'; 
if ~isfile(mat_file)
    error('未找到数据文件: %s，请先运行匹配脚本生成数据。', mat_file);
end
load(mat_file); % 加载变量: crest_lon, crest_lat, mode, peak_lon, peak_lat, mooring_time 等

%% 2. 参数设置
% 系泊点坐标
mooring_lat = 20.816666666666666;
mooring_lon = 115.76666666666667;
radius_km = 30;

% 绘图范围 (根据数据分布调整)
lon_bound = [110, 122.5];
lat_bound = [18, 23];

% 字体设置
font_name = 'Times New Roman';
font_size = 14;

%% 3. 初始化地图 (m_map)
figure('Units', 'normalized', 'OuterPosition', [0.1 0.1 0.8 0.8], 'Color', 'w');
m_proj('mercator', 'long', lon_bound, 'lat', lat_bound);

hold on;

%% 4. 绘制基础地理信息
% 绘制高分辨率海岸线 (需安装 GSHHS 数据包，如果没有改为 m_coast)
try
    m_gshhs_i('patch', [0.9 0.9 0.9], 'edgecolor', 'k');
catch
    m_coast('patch', [0.9 0.9 0.9], 'edgecolor', 'k');
end

% 绘制网格
m_grid('box', 'fancy', 'tickdir', 'in', 'linestyle', 'none', ...
       'fontsize', font_size, 'fontname', font_name, 'fontweight', 'bold');

%% 5. 绘制系泊点参考信息
% 计算 30km 半径圆圈
theta = linspace(0, 2*pi, 360);
range_circle = km2deg(radius_km) * ones(size(theta));
azimuth_circle = rad2deg(theta);
[lat_circle, lon_circle] = reckon(mooring_lat, mooring_lon, range_circle, azimuth_circle);

% 绘制圆圈和点
h_circle = m_plot(lon_circle, lat_circle, '--', 'LineWidth', 2, 'Color', 'r');
h_mooring = m_plot(mooring_lon, mooring_lat, 'rp', 'MarkerSize', 14, 'MarkerFaceColor', 'r');

%% 6. 循环绘制波峰线
num_matches = length(crest_lon);
h_m1 = []; % 图例句柄
h_m2 = [];

fprintf('正在绘制 %d 条匹配波峰线...\n', num_matches);

for i = 1:num_matches
    % 提取数据
    lons = crest_lon{i};
    lats = crest_lat{i};
    cur_mode = mode(i);
    p_lon = peak_lon(i);
    p_lat = peak_lat(i);
    
    % 设定颜色
    if cur_mode == 1
        c_style = 'b-';  % Mode 1 蓝实线
        c_color = 'b';
        lw = 1.5;
    elseif cur_mode == 2
        c_style = 'm-';  % Mode 2 品红实线
        c_color = 'm';
        lw = 1.5;
    else
        c_style = 'k-';
        c_color = 'k';
        lw = 1.0;
    end
    
    % 绘制波峰线
    h_line = m_plot(lons, lats, c_style, 'LineWidth', lw);
    
    % 绘制凸起点 (Peak)
    if ~isnan(p_lon)
        m_plot(p_lon, p_lat, '.', 'MarkerSize', 10, 'Color', c_color);
    end
    
    % 收集图例句柄 (只取第一个)
    if cur_mode == 1 && isempty(h_m1)
        h_m1 = h_line;
    elseif cur_mode == 2 && isempty(h_m2)
        h_m2 = h_line;
    end
end

%% 7. 完善图例与标题
legends = [h_mooring, h_circle];
leg_labels = {'Mooring', '30km Radius'};

if ~isempty(h_m1)
    legends(end+1) = h_m1;
    leg_labels{end+1} = 'Mode 1 Crest';
end
if ~isempty(h_m2)
    legends(end+1) = h_m2;
    leg_labels{end+1} = 'Mode 2 Crest';
end

legend(legends, leg_labels, 'Location', 'southeast', 'FontSize', 12, 'FontName', font_name);

title(['Matched Crests vs Mooring (N=', num2str(num_matches), ')'], ...
      'FontSize', 16, 'FontName', font_name, 'FontWeight', 'bold');

% 调整坐标轴标签字体
xlabel('Longitude', 'FontSize', 14, 'FontName', font_name, 'FontWeight', 'bold');
ylabel('Latitude', 'FontSize', 14, 'FontName', font_name, 'FontWeight', 'bold');

fprintf('绘图完成。\n');
