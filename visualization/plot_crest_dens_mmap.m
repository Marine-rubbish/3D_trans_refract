% 用 mmap 绘制波峰线密度地图
clc
clear

% %% 读取深度数据
% dep_dir = 'F:\research\GEBCO';
% dep_filename = 'gebco_2024_n23.0_s18.0_w109.5_e123.0.nc';
% dep_filename = fullfile(dep_dir, dep_filename);
% % ncdisp(dep_filename)
% dep_lat = ncread(dep_filename, 'lat');
% dep_lon = ncread(dep_filename, 'lon');
% dep = ncread(dep_filename, 'elevation');
% 
lon_bound = [110.5 122.5];
lat_bound = [18 23.5];
% dep_lat_idx = dep_lat >= lat_bound(1) & dep_lat <= lat_bound(2);
% dep_lon_idx = dep_lon >= lon_bound(1) & dep_lon <= lon_bound(2);
% dep_lat = dep_lat(dep_lat_idx);
% dep_lon = dep_lon(dep_lon_idx);
% dep_lat = dep_lat(1:10:end);
% dep_lon = dep_lon(1:10:end);
% [dep_lon, dep_lat] = meshgrid(dep_lon, dep_lat);
% dep = dep(dep_lon_idx, dep_lat_idx);
% dep = dep(1:10:end, 1:10:end);
% dep = dep';

%% 东沙与毛细经纬度
dongshaLon = 116.8;
dongshaLat = 20.71;

moorLon = 115.77536;
moorLat = 20.82578;

%% 准备波峰线
shp_dir = 'F:\research\MODIS\shp_files';
shp_filelist = dir(fullfile(shp_dir, '*.shp'));
crest_lat_list = {};
crest_lon_list = {};


%% 读取波峰线并统计波峰线密度
num_bins = 500;
lat_edges = linspace(lat_bound(1), lat_bound(2), num_bins+1);
lon_edges = linspace(lon_bound(1), lon_bound(2), num_bins+1);

% 计算bin中心便于绘图
lat_centers = (lat_edges(1:end-1) + lat_edges(2:end)) / 2;
lon_centers = (lon_edges(1:end-1) + lon_edges(2)) / 2;
counts = zeros(num_bins, num_bins);

for k = 1:length(shp_filelist)
    shp_name = fullfile(shp_dir, shp_filelist(k).name);
    crestLines = shaperead(shp_name);
    for i = 1:length(crestLines)
        crestLon = crestLines(i).X;
        crestLat = crestLines(i).Y;
        crest_lat_list{end+1} = crestLat;
        crest_lon_list{end+1} = crestLon;
        lat_bin = discretize(crestLat, lat_edges);
        lon_bin = discretize(crestLon, lon_edges);
        rr = unique([lat_bin', lon_bin'], 'rows');
        rr(any(isnan(rr),2),:) = [];
        counts(rr(:,1), rr(:,2)) = counts(rr(:,1), rr(:,2)) + 1;
    end
end

%% 绘制二维直方图(密度图)---使用 m_map
figure;
% m_proj 构造投影，此处使用正方形投影（等距圆柱投影）
m_proj('cyl','lon',lon_bound,'lat',lat_bound);
% 用 m_pcolor 绘制直方图，注意 pcolor 会少一行一列，因此采用全矩阵扩展
lon_edges_mesh = linspace(lon_bound(1), lon_bound(2), num_bins+1);
lat_edges_mesh = linspace(lat_bound(1), lat_bound(2), num_bins+1);
m_pcolor(lon_edges_mesh, lat_edges_mesh, [counts, counts(:,end); counts(end,:), counts(end,end)]);
shading flat
m_coast('patch',[0.8 0.8 0.8],'edgecolor','none');
m_grid('box','fancy','tickdir','out');
colorbar
title('波峰线空间密度二维直方图');

%% 绘制波峰线---使用 m_map
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
print('..\..\img\plot_crest_density.png', '-dpng', '-r300');

%% gemini 改版
% max_count = max(counts(:));
% fprintf('最大密度值: %d\n', max_count);
% 
% % 3. 初始化绘图窗口 (参考代码布局逻辑)
% figure('Color','w','Position',[120 80 1400 720]); 
% hold on;
% 
% % 设置投影 (使用 Mercator 投影，参考代码风格)
% m_proj('mercator', 'lon', lon_bound, 'lat', lat_bound);
% 
% % 绘制高精度海岸线 (参考代码风格)
% % 如果没有安装 GSHHS 数据，请改回 m_coast('patch', ...)
% m_gshhs_h('patch', [0.8 0.8 0.8], 'edgecolor', 'k'); 
% 
% % 设置网格
% m_grid('box','on', 'tickdir','in', 'linestyle','-', 'gridcolor',[0.85 0.85 0.85], ...
%        'fontsize',12, 'fontname','Times New Roman');
% 
% % --- 关键：强制锁定坐标轴位置 ---
% ax = gca;
% ax.Units = 'normalized';
% % [left bottom width height] - 给右边留出空间放 colorbar
% set(ax, 'Position', [0.08 0.10 0.82 0.85], ...
%         'FontName', 'Times New Roman', 'FontSize', 12, 'FontWeight', 'bold');
% 
% ylabel('Latitude', 'FontSize', 14, 'FontWeight', 'bold', 'FontName', 'Times New Roman');
% xlabel('Longitude', 'FontSize', 14, 'FontWeight', 'bold', 'FontName', 'Times New Roman');
% 
% % 设置 Colormap
% cmap = jet(max_count); 
% colormap(cmap);
% caxis([1, max_count]); % 对应 counts 的范围
% 
% % 4. 绘制波峰线 (使用 Surface 高速绘图逻辑)
% fprintf('正在绘图...\n');
% 
% % 线宽
% crestLW = 1.0; 
% 
% for k = 1:length(crest_lat_list)
%     lon = crest_lon_list{k};
%     lat = crest_lat_list{k};
% 
%     % 去除 NaN
%     ok = ~isnan(lon) & ~isnan(lat);
%     lon = lon(ok);
%     lat = lat(ok);
% 
%     if length(lon) < 2
%         continue;
%     end
% 
%     % 核心步骤：获取当前线条上每个点的密度值 'val'
%     % 通过查找该点落在哪个 bin 来获取对应的 counts 值
%     lon_idx = discretize(lon, lon_edges);
%     lat_idx = discretize(lat, lat_edges);
% 
%     % 初始化该线条的颜色值数组
%     line_density_vals = nan(size(lon));
% 
%     for p = 1:length(lon)
%         if ~isnan(lon_idx(p)) && ~isnan(lat_idx(p))
%             line_density_vals(p) = counts(lat_idx(p), lon_idx(p));
%         end
%     end
% 
%     % 处理密度为0的情况 (避免绘图空白)
%     line_density_vals(line_density_vals == 0) = 1;
% 
%     % 投影坐标转换 (m_ll2xy)
%     [x, y] = m_ll2xy(lon, lat);
% 
%     % --- 使用 surface 绘制彩色线条 ---
%     % z轴设为0，通过 CData (第四个参数) 控制颜色
%     % 'EdgeColor','interp' 使得颜色在两点之间平滑过渡
%     surface([x; x], [y; y], zeros(2, length(x)), [line_density_vals; line_density_vals], ...
%         'FaceColor', 'none', ...
%         'EdgeColor', 'interp', ...
%         'LineWidth', crestLW);
% end
% 
% % 5. 添加标注点 (参考代码逻辑)
% % 东沙岛
% m_plot(dongshaLon, dongshaLat, 'p', ...
%     'MarkerSize', 18, ...
%     'MarkerFaceColor', 'r', ...
%     'MarkerEdgeColor', 'r', ...
%     'LineWidth', 1.0);
% 
% % 锚系点
% m_plot(moorLon, moorLat, 'o', ...
%     'MarkerSize', 10, ...
%     'MarkerFaceColor', 'r', ...
%     'MarkerEdgeColor', 'r', ...
%     'LineWidth', 1.0);
% 
% % 6. 设置 Colorbar (参考代码逻辑 - 绝对定位)
% cb = colorbar;
% 
% % 定义标签
% % cbLabel = 'Density (counts)';
% 
% % --- 关键：手动设置 Colorbar 位置 ---
% % [左下角X, 左下角Y, 宽度, 高度]
% % 这里的位置与上面 ax 的 Position (宽度0.82) 配合
% % 0.08(左边距) + 0.82(主图宽) + 0.015(间距) = 0.915
% set(cb, 'Units', 'normalized', ...
%         'Position', [0.94, 0.1, 0.015, 0.85], ...
%         'FontName', 'Times New Roman', 'FontSize', 12, 'FontWeight', 'bold');
% 
% % 设置 Colorbar 标签
% ylabel(cb, cbLabel, 'FontName', 'Times New Roman', 'FontSize', 12, 'FontWeight', 'bold');
% 
% % 强制刷新确保绘制完成
% drawnow;

