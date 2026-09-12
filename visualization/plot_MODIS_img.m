clc
clear

addpath(genpath('..'));
%% 读取 geotiff 影像数据
% 指定影像文件路径
img_dir = 'F:\research\MODIS\Rad_Geo_Cor_img\qkm';
img_name = 'MOD02QKM.A2020128.0315.061.2020128131829_truecolor.tif';
img_name = fullfile(img_dir, img_name);

% 读取影像数据
[img, ref] = readgeoraster(img_name);

% 读取影像时间
sensing_time = getTimeFromFilename(img_name);
sensing_time = sensing_time + hours(8);     % 转为东8区时间

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
% 筛除第四以后为NaN的行
T = T(~any(isnan(T{:,4:10}), 2), :);

%% 模拟波峰线传播
crest_idx = 240;
crest_info = T(T{:,end} == crest_idx, :);
crest_lon = crest_lon_list{crest_idx};
crest_lat = crest_lat_list{crest_idx};
crest_len = crest_info{:, end - 1};
mooring_time = crest_info{:, 2};
prop_speed = crest_info{:, 4};
% 计算传播角度
crest_direction = mod(90 - calcDirection(crest_lon, crest_lat), 360);
% 计算传播范围
[prop_lat, prop_lon] = calcPropagation(crest_lat, crest_lon, calcDirection(crest_lon, crest_lat) ...
    , seconds(mooring_time - sensing_time), prop_speed);


%% 参数设置
% lon_bound = [114 118];
% lat_bound = [19 22];
lon_bound = [110 122.5];
lat_bound = [18.5 22.5];
mooring_lon = 115.76666666666667;
mooring_lat = 20.816666666666666;

% 计算波峰线中点
mid_lon = crest_lon_list{crest_idx}(1);
mid_lat = crest_lat_list{crest_idx}(1);
% 根据传播角度和传播后的经纬度动态确定偏移量
scale = 0.1;  % 可调整的比例因子
dx_offset = scale * cosd(crest_direction);
dy_offset = scale * sind(crest_direction);
% 以波峰线中点为基准，通过偏移得到箭头起点，终点直接使用传播后的坐标
arrow_start_lon = mid_lon + dx_offset;
arrow_start_lat = mid_lat + dy_offset + 0.3;
arrow_end_lon = prop_lon(1) - dx_offset;
arrow_end_lat = prop_lat(1) - dy_offset + 0.3;
% 更新箭头方向向量
dx = arrow_end_lon - arrow_start_lon;
dy = arrow_end_lat - arrow_start_lat;

%% 可视化
figure('Units', 'normalized', 'OuterPosition', [0 0 1 1]);

% 绘制背景图
% worldmap(img, ref)
geoshow(img, ref)

% 绘制系泊点和波峰线
hold on
plot(mooring_lon, mooring_lat, 'ko', 'MarkerSize', 14, 'MarkerFaceColor', 'y', 'LineWidth', 1);
plot(crest_lon, crest_lat, 'LineWidth', 2, 'Color', 'r');
plot(crest_lon_list{241}, crest_lat_list{241}, 'LineWidth', 2, 'Color', 'r');
plot(crest_lon_list{251}, crest_lat_list{251}, 'LineWidth', 2, 'Color', 'r');
plot(prop_lon, prop_lat, 'LineWidth', 2, 'Color', 'r', 'LineStyle', '--');

% 用arrow绘制箭头
arrow_start_point = [arrow_start_lon, arrow_start_lat];
arrow_end_point = [arrow_end_lon, arrow_end_lat];
arrow(arrow_start_point, arrow_end_point, ...
    'Length', 10, 'BaseAngle', 90, 'Width', 3, 'Color', 'r');

arrow([116.9, 20.5], [117, 20], ...
    'Length', 4, 'BaseAngle', 90, 'Width', 2, 'Color', 'w', ...
    'TipAngle', 30);
hold off

% 文字设置
text(110.5, 22.3, strcat('Sensing time:', string(sensing_time)), 'Color', 'k');
% text(110.5, 22.1, strcat('Propagated time:', string(prop_time)), 'FontSize', 12, 'Color', 'k');
text(110.5, 22.1, strcat('Propagating speed:', string(prop_speed), ' m/s'), 'Color', 'k');
text(110.5, 21.9, strcat('Crest length:', string(crest_len / 1000), ' km'), 'Color', 'k');
text(110.5, 21.7, ['Azimuth: ', num2str(calcDirection(crest_lon,crest_lat)), '\circ'], 'Interpreter', 'tex', 'Color', 'k');

text(115, mooring_lat - 0.1, 'Mooring', 'Color', 'y');
text(116.5, 19.9, 'Dongsha Atoll', 'Color', 'w');

% 坐标轴设置
xlim(lon_bound);
ylim(lat_bound);
% lon_step = 0.5;
% xticks(lon_bound(1):lon_step:lon_bound(2))

% xlabel('Longitude(\circ E)', 'Interpreter', 'tex', 'FontSize', 12);
% set(gca, 'LooseInset', get(gca, 'TightInset'));
% 设置 y 轴刻度标签的解释器为 'tex'
set(gca, 'TickLabelInterpreter', 'tex');
xtick_val = lon_bound(1):2:lon_bound(2);
xticklabel_val = cell(size(xtick_val));
for i = 1:length(xtick_val)
    xticklabel_val{i} = [num2str(xtick_val(i)), '\circ E'];
end

ytick_val = lat_bound(1)+0.5:lat_bound(2)-0.5;
yticklabel_val = cell(size(ytick_val));
for i = 1:length(ytick_val)
    yticklabel_val{i} = [num2str(ytick_val(i)), '\circ N'];
end
xticks(xtick_val);
yticks(ytick_val);
xticklabels(xticklabel_val);
yticklabels(yticklabel_val);

% 绘制图形后设置坐标轴字体
font_name = 'Times New Roman';
font_size = 16;
set(gca, 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', font_size);
set(findall(gca, 'Type', 'text'), 'FontName', font_name, 'FontWeight', 'bold', 'Fontsize', font_size);
ylabel('Latitude', 'Interpreter', 'tex', 'FontSize', 20);
% xticklabels({});

print('..\..\img\MODIS_img.png', '-dpng', '-r300');
