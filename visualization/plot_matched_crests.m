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

% 筛选数据
crest_lon_list = crest_lon_list(T.crestIdx);
crest_lat_list = crest_lat_list(T.crestIdx);

%% 读取波峰线并计算密度
lon_bound = [110 122.5];
lat_bound = [18.5 22.5];
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
% figure;
hold on
axis equal;
% 构造 colormap，不归一化，直接使用counts中的值作为索引
cmap = jet(max(counts, [], 'all'));
for j = 1:length(crest_lat_list)
    lat = crest_lat_list{j};
    lon = crest_lon_list{j};
    lat = lat(~isnan(lat));
    lon = lon(~isnan(lon));
    % 获取每个点所在的直方图bin的索引
    lon_idx = discretize(lon, lon_edges);
    lat_idx = discretize(lat, lat_edges);
    % 用line绘制每个折线段
    for k = 1:length(lat)-1
        if ~isnan(lat_idx(k)) && ~isnan(lon_idx(k)) && ~isnan(lat_idx(k+1)) && ~isnan(lon_idx(k+1))
            % 使用第一个点的密度，也可选择两点的平均
            density = counts(lat_idx(k), lon_idx(k));
            % 若density的值为0，则使用1来索引colormap，避免索引错误
            if density == 0
                density = 1;
            end
            % line([lon(k) lon(k+1)], [lat(k) lat(k+1)], 'Color', cmap(density,:), 'LineWidth',2);
            max_count = max(counts(:));
            alpha_val = (max_count - density) / max_count;
            h = line([lon(k) lon(k+1)], [lat(k) lat(k+1)], 'Color', cmap(density,:), 'LineWidth',1);
            h.Color = [h.Color, alpha_val];
        end
    end
end

colormap('jet');
colorbar;

xlim(lon_bound);
ylim(lat_bound);
clim([min(counts(:)), max(counts(:))]);

% 绘制图形后设置坐标轴字体
font_name = 'Time New Roman';
set(gca, 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', 12);
set(findall(gca, 'Type', 'text'), 'FontName', font_name, 'FontWeight', 'bold', 'Fontsize', 14);
xlabel('Longitude(\circ E)', 'Interpreter', 'tex', 'FontSize', 12);
ylabel('Latitude(\circ N)', 'Interpreter', 'tex', 'FontSize', 12);
hold off
box on
set(gca, 'LooseInset', get(gca, 'TightInset'));
print('..\..\img\plot_matched_crest_density.png', '-dpng', '-r300');
