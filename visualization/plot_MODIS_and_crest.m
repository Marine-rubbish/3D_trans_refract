clc
clear

%% 读取系泊数据
mooring_dir = 'F:\research\月份挑内波数据';
mooring_name = '2020年内波时间_匹配结果_100km.xlsx';
mooring_name = fullfile(mooring_dir, mooring_name);
T = readtable(mooring_name);
% 筛除第四和第五列为NaN的行
T = T(~(isnan(T{:,4}) | isnan(T{:,5})), :);

%% 读取shp文件中的波峰线数据
shp_dir = 'F:\research\MODIS\shp_files';
shp_filelist = dir(fullfile(shp_dir, '*.shp'));

%% 提取所有波峰线
all_crest = {};
for k = 1:length(shp_filelist)
    shp_name = fullfile(shp_dir, shp_filelist(k).name);
    crestLines = shaperead(shp_name);
    for i = 1:length(crestLines)
        all_crest = [all_crest; {crestLines(i).X, crestLines(i).Y}];
    end
end

crest_filename = {};
crest_sensing_time = {};
crest_img_name = {};
% 输出每个波峰线对应的图像名称
for k = 1:length(shp_filelist)
    shp_name = fullfile(shp_dir, shp_filelist(k).name);
    crestLines = shaperead(shp_name);
    for i = 1:length(crestLines)
        crest_filename = [crest_filename; shp_filelist(k).name];
        crest_sensing_time = [crest_sensing_time; getTimeFromFilename(shp_filelist(k).name)];
        crest_img_name = [crest_img_name; shp_filelist(k).name(1:end-13) + ".tif"];
    end
end

% 寻找对应图像的完整路径
% 1. 获取所有候选图像文件的列表（Mosaic子目录和qkm父目录）
img_dir = 'F:\research\MODIS\Rad_Geo_Cor_img\qkm';
img_subdir = fullfile(img_dir, 'Mosaic');
raw_img_files = [dir(fullfile(img_dir, '*.tif')); dir(fullfile(img_subdir, '*.tif'))];

% 2. 建立 [日期 -> 文件全路径] 的映射 Map
%    假设关键是 "AYYYYDDD" (如 A2020090)
imgMap = containers.Map('KeyType', 'char', 'ValueType', 'char');

for k = 1:length(raw_img_files)
    fname = raw_img_files(k).name;
    folder = raw_img_files(k).folder;
    
    % 提取 AYYYYDDD 模式 (A + 4位年 + 3位日)
    pat = 'A(\d{7})'; 
    tokens = regexp(fname, pat, 'tokens', 'once');
    
    if ~isempty(tokens)
        keyDate = tokens{1}; % 结果如 '2020090'
        
        % 存入 Map (如果同一天有多幅图，后面覆盖前面，或按需做逻辑)
        imgMap(keyDate) = fullfile(folder, fname);
    end
end

% 3. 为每个波峰线寻找对应的图像
crest_img_fullname = cell(size(crest_img_name));

for i = 1:length(crest_img_name)
    % 从波峰线文件名/原推测图名中提取日期
    % 假设 crest_img_name{i} 里包含 "A2020090" 或类似结构
    % shp文件名通常形如：MOD02QKM.A2020090.0215...shp
    
    target_fname = crest_img_name{i};
    tokens = regexp(target_fname, 'A(\d{7})', 'tokens', 'once');
    
    if ~isempty(tokens) && isKey(imgMap, tokens{1})
        crest_img_fullname{i} = imgMap(tokens{1});
    else
        % 没匹配上时的 fallback（或保持为空）
        crest_img_fullname{i} = '';
        fprintf('未找到匹配图像: %s (日期码: %s)\n', target_fname, char(tokens));
    end
end

T = T(~isnan(T{:, "crestIdx"}), :);
T.sensing_time = crest_sensing_time(T{:, "crestIdx"}) + hours(8);

%% 筛选下标
T_idx = [729, 853, 109, 162, 284, 294, 335, 366, 467, 477, 480];
crests_idx = T{T_idx, "crestIdx"};

tar_sensing_time = [
    datetime('2020-05-06 05:40:00'), ...
    datetime('2020-06-20 03:40:00'), ...
    datetime('2020-07-28 03:00:00'), ...
    ]+hours(8);

crests_idx = [];
for i = 1:length(tar_sensing_time)
    time_diffs = abs(T.sensing_time - tar_sensing_time(i));
    [~, min_idx] = min(time_diffs);
    crests_idx = [crests_idx; T{min_idx, "crestIdx"}];
end

% crests_idx = [751, 756, 752, 757];    % 波列的波峰线
crests_idx = [1870];

%% 画图
lon_bound = [115.5 117];
lat_bound = [20, 22];
font_size = 14;
text_color = 'b';

for l = 1:size(crests_idx, 2)
    if (l == 1)
        figure('Units', 'normalized', 'OuterPosition', [0 0 1 1]);
    
        % 指定影像文件路径
        img_name = crest_img_fullname{crests_idx(l)};
        
        % 读取影像数据
        [img, ref] = readgeoraster(img_name);
        geoshow(uint8(img), ref)
        
        % 普通经纬度图
        hold on
        % plot(115.76666666666667, 20.816666666666666, 'ro', 'MarkerSize', 16, 'MarkerFaceColor', 'r');
        % theta = linspace(0, 2*pi, 360);
        % range_circle = km2deg(30) * ones(size(theta));
        % azimuth_circle = rad2deg(theta);
        % [lat_circle, lon_circle] = reckon(20.816666666666666, 115.76666666666667, range_circle, azimuth_circle);
    end
    % plot(lon_circle, lat_circle, '--', 'LineWidth', 4, 'Color', [255, 0, 0]/255);
    
    % 绘制波峰线，可根据需要调整线型和颜色
    % lon = wave_train_coord{:, 1};
    % lat = wave_train_coord{:, 2};
    lon = all_crest{crests_idx(l), 1};
    lat = all_crest{crests_idx(l), 2};
    % plot(lon, lat, 'LineWidth', 2, 'Color', 'g');
    hold on;
    
    % text(min(lon), min(lat) - 0.1, 'Sensing', 'HorizontalAlignment', 'center',...
    %     'FontSize', font_size, 'Color', 'w');
    % text(min(lon), min(lat) - 0.3, 'Crest', 'HorizontalAlignment', 'center',...
    %     'FontSize', font_size, 'Color', 'w');
        
    xlim(lon_bound);
    ylim(lat_bound);
       
    
    % plot(prop_lon, prop_lat, 'LineWidth', 2, 'Color', 'g');
    % text(min(prop_lon), min(prop_lat) - 0.1, tname{tidx}, 'HorizontalAlignment', 'center', ...
    %     'FontSize', 24, 'Color', 'y');
    % plot(prop_lon, prop_lat, 'LineWidth', 4, 'Color', 'g');
    % text(min(prop_lon), min(prop_lat) - 0.1, tname{tidx}, 'HorizontalAlignment', 'center', ...
    %     'FontSize', 24, 'Color', 'g');
    
    set(gca, 'TickLabelInterpreter', 'tex');
    xtick_val = lon_bound(1):1:lon_bound(2);
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
    
    % % 设置坐标轴横纵比例
    % pos = get(gca, 'Position');
    % set(gca, 'Position', [pos(1)+0.1 pos(2) pos(3)-0.2 pos(4)]);
    
    % 绘制图形后设置坐标轴字体
    font_name = 'Times New Roman';
    font_size = 20;
    set(gca, 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', font_size);
    set(findall(gca, 'Type', 'text'), 'FontName', font_name, 'FontWeight', 'bold', 'Fontsize', 24);
    xlabel('Longitude', 'Interpreter', 'tex', 'FontSize', 24);
    ylabel('Latitude', 'Interpreter', 'tex', 'FontSize', 24);
    set(gca, 'LooseInset', get(gca, 'TightInset'));
    ;
end
% print(gcf, 'wave_train_crest.jpg', '-djpeg', '-r600');
%% 测试
lon_bound = [115 118];
lat_bound = [20, 22];
adj_img = adjust_brightness_contrast(img, 0.5, 0.8);
geoshow(adj_img, ref);
xlim(lon_bound);
ylim(lat_bound);
hold on
plot(lon, lat, 'LineWidth', 1, 'Color', 'y');


%% 辅助函数
function adjusted_img = adjust_brightness_contrast(img, brightness_factor, contrast_factor)
    % Adjust brightness and contrast of a true-color (RGB) image
    % img: input RGB image (uint8)
    % brightness_factor: factor to adjust brightness (e.g., 0.1 for slight increase, -0.1 for decrease)
    % contrast_factor: factor to adjust contrast (e.g., 1.2 for increase, 0.8 for decrease)
    
    % Convert to double for processing
    img_double = double(img) / 255.0;
    
    % Adjust brightness by adding the factor
    img_double = img_double + brightness_factor;
    
    % Adjust contrast by multiplying
    img_double = img_double * contrast_factor;
    
    % Clip values to [0, 1]
    img_double = max(0, min(1, img_double));
    
    % Convert back to uint8
    adjusted_img = uint8(img_double * 255);
end
