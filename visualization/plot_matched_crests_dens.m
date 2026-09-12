clc
clear

%% 准备shp文件中的波峰线数据
shp_dir = 'F:\research\MODIS\shp_files';
shp_filelist = dir(fullfile(shp_dir, '*.shp'));

%% 读取系泊数据
mooring_dir = 'F:\research\月份挑内波数据';
mooring_name = '2020年内波时间_匹配结果_100km.xlsx';
mooring_name = fullfile(mooring_dir, mooring_name);
T = readtable(mooring_name);
% 筛除第四以后为NaN的行
T = T(~any(isnan(T{:,4:10}), 2), :);

%% 

%% 读取shp文件
crest_lat_list = {};
crest_lon_list = {};
for k = 1:length(shp_filelist)
    shp_name = fullfile(shp_dir, shp_filelist(k).name);
    crestLines = shaperead(shp_name);
    for i = 1:length(crestLines)
        crestLon = crestLines(i).X;
        crestLat = crestLines(i).Y;
        crest_lat_list{end+1} = crestLat;
        crest_lon_list{end+1} = crestLon;
    end
end

% % 筛选数据
% crest_lon_list = crest_lon_list(T.crestIdx);
% crest_lat_list = crest_lat_list(T.crestIdx);

crest_lon_list = crest_lon_list(crest_idx_out);
crest_lat_list = crest_lat_list(crest_idx_out);

%% 从mat文件读取经纬度
% 筛选数据

for i = 1:length(crest_lat_list)
    crestLat = crest_lat_list{i};
    crestLon = crest_lon_list{i};
    cDir = mod(90 - calcDirection(crestLat, crestLon), 360);
    % if cDir >= 30 & cDir <= 150
        if max(crestLat(~isnan(crestLat))) < 19.2 & max(crestLon(~isnan(crestLon))) < 114.5
            plot(crestLon, crestLat);
            continue;
        end
    % end
end

%% 东沙与毛细经纬度
dongshaLon = 116.8;
dongshaLat = 20.71;

moorLon = 115.77536;
moorLat = 20.82578;

%% 读取波峰线并计算密度
% lon_bound = [110 122.5];
% lat_bound = [15 23.5];
lon_bound = [110.5 122.5];
lat_bound = [18 23.5];
% 定义经纬度的bin边界，例如分成100个bin
num_bins = 500;
lat_edges = linspace(lat_bound(1), lat_bound(2), num_bins+1);
lon_edges = linspace(lon_bound(1), lon_bound(2), num_bins+1);

% 计算bin中心便于绘图
lat_centers = (lat_edges(1:end-1) + lat_edges(2:end)) / 2;
lon_centers = (lon_edges(1:end-1) + lon_edges(2:end)) / 2;
counts = zeros(num_bins, num_bins);

for k = 1:length(crest_lat_list)
    lat_bin = discretize(crest_lat_list{k}, lat_edges);
    lon_bin = discretize(crest_lon_list{k}, lon_edges);
    rr = unique([lat_bin', lon_bin'], 'rows');
    rr(any(isnan(rr),2),:) = [];
    counts(rr(:,1), rr(:,2)) = counts(rr(:,1), rr(:,2)) + 1;
end
%% 绘制波峰线
figure('Units', 'normalized', 'OuterPosition', [0 0 1 1]);
% m_proj('cyl','lon',lon_bound,'lat',lat_bound);
m_proj('mercator', 'lon', lon_bound, 'lat', lat_bound);
hold on
axis equal

% 构造 colormap，直接用 counts 的最大值作为索引
max_count = max(counts(:));
cmap = jet(max_count);
for j = 1:length(crest_lat_list)
    lat = crest_lat_list{j};
    lon = crest_lon_list{j};
    lat = lat(~isnan(lat));
    lon = lon(~isnan(lon));
    % 获取每个点所在直方图bin的索引
    lon_idx = discretize(lon, lon_edges);
    lat_idx = discretize(lat, lat_edges);
    for k = 1:length(lat)-1
        if ~isnan(lat_idx(k)) && ~isnan(lon_idx(k)) && ~isnan(lat_idx(k+1)) && ~isnan(lon_idx(k+1))
            density = counts(lat_idx(k), lon_idx(k));
            if density == 0
                density = 1;
            end
            % 根据密度计算透明度（密度越大，线条越不透明）
            alpha_val = (max_count - density) / max_count;  % 范围[0,1]
            % 绘制线段，m_line内部自动处理经纬度转换
            h = m_line([lon(k) lon(k+1)], [lat(k) lat(k+1)], 'Color', cmap(density,:), 'LineWidth',1);
            % 给 line 添加 alpha 信息（仅在支持 RGBA 的 MATLAB 版本有效）
            if numel(h.Color) == 3
                h.Color = [h.Color, alpha_val];
            end
        end
    end
end

% ===== Dongsha Islands: red pentagram =====
m_plot(dongshaLon, dongshaLat, 'p', ...
    'MarkerSize', 22, ...
    'MarkerFaceColor', 'r', ...
    'MarkerEdgeColor', 'r', ...
    'LineWidth', 0.1);

% ===== Mooring: red dot =====
m_plot(moorLon, moorLat, 'o', ...
    'MarkerSize', 12, ...
    'MarkerFaceColor', 'r', ...
    'MarkerEdgeColor', 'r', ...
    'LineWidth', 1.0);

m_gshhs_h('patch',[0.8 0.8 0.8],'edgecolor','k');
m_grid('box','on','tickdir','in');

% 绘制图形后设置坐标轴字体
font_name = 'Times New Roman';
font_size = 16;
set(gca, 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', font_size);
set(findall(gca, 'Type', 'text'), 'FontName', font_name, 'FontWeight', 'bold', 'Fontsize', font_size);

% 调整 ylabel 的位置以向左移动q
xlabel('Longitude', 'Interpreter', 'tex', 'FontSize', 20, 'FontName', font_name, 'FontWeight', 'bold');
ylabel('Latitude', 'Interpreter', 'tex', 'FontSize', 20, 'FontName', font_name, 'FontWeight', 'bold');

% 1. 获取主图句柄
ax = gca;

% 2. 【关键】先把当前完美的坐标轴位置存到一个变量里
% 此时 m_proj 和 m_grid 已经画好了，位置是正确的
saved_ax_pos = get(ax, 'Position'); 

% 3. 生成 Colorbar 
% (注意：这一步执行后，MATLAB 会自作聪明地缩小 ax，先别管它)
clim([1, max_count]); 
colormap('jet');
cb = colorbar;
drawnow; % 必须刷新，让它先把图搞乱

% 4. 【暴力复原】直接把主图位置设回 saved_ax_pos
% 这一行代码会抵消 colorbar 对主图大小的所有影响
set(ax, 'Position', saved_ax_pos); 

% 5. 处理 Colorbar 的位置
cb_pos = get(cb, 'Position'); 

% 计算新位置：基于刚才保存的主图右边界 + 偏移量 (0.08)
% 这样 colorbar 绝对会在主图右边，而且不挨着
target_x = saved_ax_pos(1) + saved_ax_pos(3) + 0.015;

% 应用新位置 [新X, 原Y, 原宽, 原高]
% 我们只改 X，高度和宽度保持 MATLAB 默认生成的比例
set(cb, 'Position', [target_x, cb_pos(2), cb_pos(3), cb_pos(4)]);

% 保存图形
print('.\img\plot_matched_crest_density_855.png', '-dpng', '-r300');
