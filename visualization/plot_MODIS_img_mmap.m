clc
clear

addpath(genpath('..'));
%% 读取 geotiff 影像数据
img_dir = 'F:\research\MODIS\Rad_Geo_Cor_img\qkm';
img_name = 'MOD02QKM.A2020128.0315.061.2020128131829_truecolor.tif';
img_name = fullfile(img_dir, img_name);
[img, ref] = readgeoraster(img_name);
sensing_time = getTimeFromFilename(img_name);
sensing_time = sensing_time + hours(8);     % 转为东8区时间

% 根据影像参考对象生成经纬度网格（注意：行列方向可能需要调整）
lon = linspace(ref.LongitudeLimits(1), ref.LongitudeLimits(2), size(img,2));
lat = linspace(ref.LatitudeLimits(1), ref.LatitudeLimits(2), size(img,1));
[Lon,Lat] = meshgrid(lon, lat);

%% 读取 shp 文件中的波峰线数据
shp_dir = 'F:\research\MODIS\shp_files';
shp_filelist = dir(fullfile(shp_dir, '*.shp'));
crest_lat_list = {};
crest_lon_list = {};
for k = 1:length(shp_filelist)
    shp_name = fullfile(shp_dir, shp_filelist(k).name);
    crestLines = shaperead(shp_name);
    for i = 1:length(crestLines)
        crest_lat_list{end+1} = crestLines(i).Y;
        crest_lon_list{end+1} = crestLines(i).X;
    end
end

%% 读取匹配excel
mooring_dir = 'F:\research\月份挑内波数据';
mooring_name = '2020年内波时间_匹配结果_100km.xlsx';
mooring_name = fullfile(mooring_dir, mooring_name);
T = readtable(mooring_name);
T = T(~any(isnan(T{:,4:10}), 2), :);

%% 模拟波峰线传播
crest_idx = 240;
crest_info = T(T{:,end} == crest_idx, :);
crest_lon = crest_lon_list{crest_idx};
crest_lat = crest_lat_list{crest_idx};
crest_len = crest_info{:, end - 1};
mooring_time = crest_info{:, 2};
prop_speed = crest_info{:, 4};
% 计算传播角度（单位：度）
crest_direction = mod(90 - calcDirection(crest_lon, crest_lat), 360);
[prop_lat, prop_lon] = calcPropagation(crest_lat, crest_lon, calcDirection(crest_lon, crest_lat) ...
    , seconds(mooring_time - sensing_time), prop_speed);

%% 参数设置
lon_bound = [110 122.5];
lat_bound = [18.5 22.5];
mooring_lon = 115.76666666666667;
mooring_lat = 20.816666666666666;

% 波峰中点
mid_lon = crest_lon_list{crest_idx}(1);
mid_lat = crest_lat_list{crest_idx}(1);
scale = 0.1;
dx_offset = scale * cosd(crest_direction);
dy_offset = scale * sind(crest_direction);
arrow_start_lon = mid_lon + dx_offset;
arrow_start_lat = mid_lat + dy_offset + 0.3;
arrow_end_lon = prop_lon(1) - dx_offset;
arrow_end_lat = prop_lat(1) - dy_offset + 0.3;
dx = arrow_end_lon - arrow_start_lon;
dy = arrow_end_lat - arrow_start_lat;

%% 使用 m_map 进行可视化
figure('Units', 'normalized', 'OuterPosition', [0 0 1 1]);
% 设置投影（这里采用墨卡托投影）
m_proj('Mercator', 'lon', lon_bound, 'lat', lat_bound);

% 绘制背景影像
% 使用 m_image 绘制时，需要提供经纬度网格
m_image(lon, lat, img);
set(gca, 'YDir','normal')
hold on

% 绘制系泊点和波峰线（利用 m_plot 进行绘制）
m_plot(mooring_lon, mooring_lat, 'ko', 'MarkerSize', 14, 'MarkerFaceColor', 'y', 'LineWidth', 1);
m_plot(crest_lon, crest_lat, 'r', 'LineWidth',2);
m_plot(crest_lon_list{241}, crest_lat_list{241}, 'r', 'LineWidth',2);
m_plot(crest_lon_list{251}, crest_lat_list{251}, 'r', 'LineWidth',2);
m_plot(prop_lon, prop_lat, 'r--', 'LineWidth',2);

% 绘制箭头（依赖 arrow 函数，如果未安装请替换为其它绘制方式）
arrow_start_point = [arrow_start_lon, arrow_start_lat];
arrow_end_point = [arrow_end_lon, arrow_end_lat];
arrow(arrow_start_point, arrow_end_point, ...
    'Length', 10, 'BaseAngle', 90, 'Width', 3, 'Color', 'r');

% 额外的箭头示例
arrow([116.9, 20.5], [117, 20], ...
    'Length', 4, 'BaseAngle', 90, 'Width', 2, 'Color', 'w', ...
    'TipAngle', 30);

% 添加文字
m_text(110.5, 22.3, strcat('Sensing time:', string(sensing_time)), 'Color', 'k', 'FontSize', 14);
m_text(110.5, 22.1, strcat('Propagating speed:', string(prop_speed), ' m/s'), 'Color', 'k', 'FontSize', 14);
m_text(110.5, 21.9, strcat('Crest length:', string(crest_len/1000), ' km'), 'Color', 'k', 'FontSize', 14);
m_text(110.5, 21.7, ['Azimuth: ', num2str(calcDirection(crest_lon,crest_lat)), '\circ'], 'Interpreter', 'tex', 'Color', 'k', 'FontSize', 14);
m_text(115, mooring_lat-0.1, 'Mooring', 'Color', 'y', 'FontSize', 14);
m_text(116.5, 19.9, 'Dongsha Atoll', 'Color', 'w', 'FontSize', 14);

% 绘制网格
m_grid('box', 'fancy', 'tickdir', 'in');
hold off

% 导出图像
print('..\..\img\MODIS_img.png', '-dpng', '-r300');

