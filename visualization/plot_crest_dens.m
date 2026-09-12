clc
clear

%% % 读取深度数据（注释部分保持不变）
lon_bound = [110 122.5];
lat_bound = [18.5 22.5];

%% 准备波峰线
shp_dir = 'F:\research\MODIS\shp_files';
shp_filelist = dir(fullfile(shp_dir, '*.shp'));
crest_lat_list = {};
crest_lon_list = {};

%% 读取波峰线并统计波峰线密度
num_bins = 500;
lat_edges = linspace(lat_bound(1), lat_bound(2), num_bins+1);
lon_edges = linspace(lon_bound(1), lon_bound(2), num_bins+1);

% 计算 bin 中心便于绘图
lat_centers = (lat_edges(1:end-1) + lat_edges(2:end)) / 2;
lon_centers = (lon_edges(1:end-1) + lon_edges(2:end)) / 2;
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
        rr(any(isnan(rr),2), :) = [];
        for j = 1:size(rr,1)
            counts(rr(j,1), rr(j,2)) = counts(rr(j,1), rr(j,2)) + 1;
        end
    end
end

%% 绘制波峰线（线条颜色与密度对应）
figure('Units', 'normalized', 'OuterPosition', [0 0 1 1]);
hold on;
axis equal
xlim(lon_bound)
ylim(lat_bound)

% 设置 colormap，以 counts 的最大值作为索引
max_count = max(counts(:));
cmap = jet(max_count);

m_proj('cyl','lon',lon_bound,'lat',lat_bound);
m_gshhs_h('save', 'coastdata.mat');
load coastdata.mat
for i = 1:length(land)
    % 检查经纬度是否有交集
    if max(land(i).X) < lon_bound(1) || min(land(i).X) > lon_bound(2) || ...
       max(land(i).Y) < lat_bound(1) || min(land(i).Y) > lat_bound(2)
        continue;
    end
    patch(land(i).X, land(i).Y, [0.8 0.8 0.8], 'EdgeColor','none');
end

% 绘制每条波峰线
for j = 1:length(crest_lat_list)
    lat = crest_lat_list{j};
    lon = crest_lon_list{j};
    % 清除 NaN 值
    valid = ~isnan(lat) & ~isnan(lon);
    lat = lat(valid);
    lon = lon(valid);
    if length(lat) < 2
        continue;
    end
    % 计算直方图 bin 索引
    lat_idx = discretize(lat, lat_edges);
    lon_idx = discretize(lon, lon_edges);
    for k = 1:length(lat)-1
        if isnan(lat_idx(k)) || isnan(lon_idx(k)) || isnan(lat_idx(k+1)) || isnan(lon_idx(k+1))
            continue;
        end
        density = counts(lat_idx(k), lon_idx(k));
        if density == 0
            density = 1;
        end
        % 计算透明度（密度越大，线条越不透明）
        alpha_val = (max_count - density)/max_count;  % 范围 [0,1]
        % 绘制线段。注意：标准 line/plot 不直接支持透明度，MATLAB R2014b 及以后的版本可通过 Color 属性的 RGBA 直接设定
        h = line([lon(k) lon(k+1)], [lat(k) lat(k+1)], 'LineWidth', 1);
        col = cmap(density,:);
        if numel(col)==3
            % 设定颜色加透明度（仅在支持 RGBA 的 MATLAB 版本有效）
            h.Color = [col, alpha_val];
        else
            h.Color = col;
        end
    end
end

% 绘制陆地：同样读取 landareas 数据并过滤区域
land = shaperead('landareas.shp','UseGeoCoords',false);
for i = 1:length(land)
    if max(land(i).X) < lon_bound(1) || min(land(i).X) > lon_bound(2) || ...
       max(land(i).Y) < lat_bound(1) || min(land(i).Y) > lat_bound(2)
        continue;
    end
    patch(land(i).X, land(i).Y, [0.8 0.8 0.8], 'EdgeColor','k');
end

% 设置 colorbar 及坐标相关参数
clim([1, max_count]);
colormap('jet');
colorbar;

font_name = 'Times New Roman';
font_size = 16;
set(gca, 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', font_size);
set(findall(gca, 'Type', 'text'), 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', font_size);
ylabel('Latitude (\circ N)', 'Interpreter', 'tex', 'FontSize', font_size, ...
    'FontName', font_name, 'FontWeight', 'bold');
xticklabels({});
yt = get(gca, 'YTick');
set(gca, 'YTickLabel', arrayfun(@num2str, yt, 'UniformOutput', false));

% 保存图形
% print('..\..\img\plot_crest_density.png', '-dpng', '-r300');
