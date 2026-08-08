clc
clear

%% 读取系泊数据
mooring_dir = 'F:\research\月份挑内波数据';
mooring_name = '2020年内波时间_匹配结果_100km_双向限制波向.xlsx';
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
        fname = shp_filelist(k).name;
        base = fname(1:end-4); % Remove .shp
        underscore_pos = find(base == '_', 1, 'last');
        if ~isempty(underscore_pos)
            img_base = base(1:underscore_pos-1);
        else
            img_base = base;
        end
        crest_img_name = [crest_img_name; img_base + ".tif"];
    end
end

% 寻找对应图像的完整路径
crest_img_fullname = cell(size(crest_img_name));
img_dir = 'F:\research\MODIS\Rad_Geo_Cor_img\qkm';
img_subdir = 'F:\research\MODIS\Rad_Geo_Cor_img\qkm\Mosaic';
for i = 1:length(crest_img_name)
    if(exist(fullfile(img_dir, crest_img_name{i}), 'file'))
        crest_img_fullname{i} = fullfile(img_dir, crest_img_name{i});
    elseif (exist(fullfile(img_subdir, crest_img_name{i}), 'file'))
        crest_img_fullname{i} = fullfile(img_subdir, crest_img_name{i});
    else
        crest_img_fullname{i} = '';
    end
end

% T = T(~isnan(T{:, "crestIdx"}), :);
% T.sensing_time = crest_sensing_time(T{:, "crestIdx"}) + hours(8);

%% 筛选下标
% T_idx = [729, 853, 109, 162, 284, 294, 335, 366, 467, 477, 480];
% crests_idx = T{T_idx, "crestIdx"};

% fake
% tar_sensing_time = [
%     datetime('2020-05-06 05:40:00'), ...
%     datetime('2020-06-20 03:40:00'), ...
%     datetime('2020-07-28 03:00:00'), ...
%     ]+hours(8);
% 
% crests_idx = [];
% for i = 1:length(tar_sensing_time)
%     time_diffs = abs(T.sensing_time - tar_sensing_time(i));
%     [~, min_idx] = min(time_diffs);
%     crests_idx = [crests_idx; T{min_idx, "crestIdx"}];
% end

% crests_idx = [1110, 1870, 757]';
% crests_idx = [2026, 1882, 2070, 1362, 752]';
% crests_idx = [2026, 1882, 2070, 1573, 752]';
% crests_idx = [2026, 1882, 2070, 1388, 752]';
% crests_idx = [2026];
crests_idx = [1388];



%% 获取传播过去的经纬度
signedPosList = zeros(size(crests_idx));
for i = 1:size(crests_idx, 1)
    if i == 4
        ;
    end
    crest_idx = crests_idx(i);
    crestLat = all_crest{crest_idx, 2}';
    crestLon = all_crest{crest_idx, 1}';
    dirDeg = mod(90 - calcDirection(crestLat, crestLon), 360);
    
    % 设置传播速度范围
    c_bound = [1, 3]; % m/s
    
    % 系泊点位置
    moorLat = 20.816666666666666;
    moorLon = 115.76666666666667;
    
    % 波峰线观测时间
    crestTime = T.sensing_time(T{:, "crestIdx"} == crest_idx);
    
    % 半径
    radius = 0; % meters
    
    [isPass, ~, signedPos, ~, ~, propLat, propLon] = ...
        reachMooringByTranslation(crestLat, crestLon, crestTime, moorLat, moorLon, c_bound, radius);
    signedPosList(i) = signedPos;
    
    % 保存传播后的经纬度
    prop_coords{i, 1} = propLon;
    prop_coords{i, 2} = propLat;
end

crest_coords = all_crest(crests_idx, :);
for i = 1:size(crest_coords, 1)
    crestLat = crest_coords{i, 2}';
    crestLon = crest_coords{i,1}';
    crest_coords{i, 1} = crestLon(~isnan(crestLon));
    crest_coords{i, 2} = crestLat(~isnan(crestLat));
end

crest_bulge = getBulge(crest_coords);
prop_bulge = getBulge(prop_coords);

%% 测试
for i = 1:length(all_crest)
    l = calcCrestLen(all_crest{i, 2}, all_crest{i, 1});
    if l > 54840 & l < 54850
        ;
    end
end

%% 画图
% full range
% lon_bound = [110 122.5];
% lat_bound = [18.5, 22.5];

% normal
lon_bound = [115 116.5];
lat_bound = [20, 22];
font_size = 14;
text_color = 'b';

for l = 1:size(crests_idx, 1)
    figure('Units', 'normalized', 'OuterPosition', [0 0 1 1]);

    % 指定影像文件路径
    img_name = crest_img_fullname{crests_idx(l)};
    
    % 读取影像数据
    [img, ref] = readgeoraster(img_name);
    % if l ~= 3
    %     img = adjust_brightness_contrast(img, 0.6, 1);
    % end
    geoshow(uint8(img), ref)
    
    % 普通经纬度图
    hold on
    % plot(115.76666666666667, 20.816666666666666, 'ro', 'MarkerSize', 12, 'MarkerFaceColor', 'r');
    % theta = linspace(0, 2*pi, 360);
    % range_circle = km2deg(30) * ones(size(theta));
    % azimuth_circle = rad2deg(theta);
    % [lat_circle, lon_circle] = reckon(20.816666666666666, 115.76666666666667, range_circle, azimuth_circle);
    % plot(lon_circle, lat_circle, '--', 'LineWidth', 2, 'Color', [255, 0, 0]/255);
    
    % 绘制波峰线，可根据需要调整线型和颜色
    % lon = wave_train_coord{:, 1};
    % lat = wave_train_coord{:, 2};
    lon = all_crest{crests_idx(l), 1};
    lat = all_crest{crests_idx(l), 2};
    plot(lon, lat, 'LineWidth', 2.5, 'Color', 'g');
    
    % text(min(lon), min(lat) - 0.1, 'Sensing', 'HorizontalAlignment', 'center',...
    %     'FontSize', font_size, 'Color', 'w');
    % text(min(lon), min(lat) - 0.3, 'Crest', 'HorizontalAlignment', 'center',...
    %     'FontSize', font_size, 'Color', 'w');

    % if ~isnan(prop_coords{l, 1}) & ~isnan(prop_coords{l, 2})
    %     plot(prop_coords{l, 1}, prop_coords{l, 2}, 'LineWidth', 2.5, 'LineStyle', '--','Color', 'g');
    % end

    % if strcmp(crest_bulge(l).status, 'ok')
    %     plot(crest_bulge(l).lonK, crest_bulge(l).latK, 'p', 'MarkerSize', 12, ...
    %         'MarkerFaceColor','r','MarkerEdgeColor','k')
    % end
    % 
    % if strcmp(prop_bulge(l).status, 'ok')
    %     plot(prop_bulge(l).lonK, prop_bulge(l).latK, 'p', 'MarkerSize', 12, ...
    %         'MarkerFaceColor','r','MarkerEdgeColor','k')
    % end

        
    xlim(lon_bound);
    ylim(lat_bound);
       
    
    plot(prop_lon, prop_lat, 'LineWidth', 4, 'Color', 'g');
    % text(min(prop_lon), min(prop_lat) - 0.1, tname{tidx}, 'HorizontalAlignment', 'center', ...
    %     'FontSize', 24, 'Color', 'y');
    % plot(prop_lon, prop_lat, 'LineWidth', 4, 'Color', 'g');
    % text(min(prop_lon), min(prop_lat) - 0.1, tname{tidx}, 'HorizontalAlignment', 'center', ...
    %     'FontSize', 24, 'Color', 'g');
    
    set(gca, 'TickLabelInterpreter', 'tex');
    xtick_val = lon_bound(1):0.5:lon_bound(2);
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
    drawnow;
    % print(gcf, [num2str(l) +'.jpg'], '-djpeg', '-r1000');
    % close(gcf);
end

%% 测试
lon_bound = [115 118];
lat_bound = [20, 22];
adj_img = adjust_brightness_contrast(img, 0.6, 1);
geoshow(adj_img, ref);
xlim(lon_bound);
ylim(lat_bound);
% hold on
% plot(lon, lat, 'LineWidth', 1, 'Color', 'y');


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

function bulge = getBulge(prop_coords)

cfg = struct();
cfg.R_earth = 6371000;     % m

cfg.ds_resample_m = 1000;  % 最大重采样间距(默认1km)
cfg.ds_min_m      = 100;   % 最小重采样间距(避免过密)
cfg.minNs_target  = 60;    % 目标重采样点数（越大越稳，建议40~100）

cfg.smooth_km     = 20;    % 几何平滑尺度(km)，建议15~30
cfg.kappaSmooth_km= 10;    % 曲率再平滑尺度(km)，建议5~15

cfg.dropEdgePct   = 0.05;  % 首尾剔除比例（5%更稳）
cfg.minN_raw      = 6;     % 原始点数太少就跳过

for k = 1:size(prop_coords, 1)
    lon = prop_coords{k, 1};
    lat = prop_coords{k, 2};

    if isnan(lon) & isnan(lat)
        bulge(k).status = 'skip';
        continue;
    end

    if numel(lon) < cfg.minN_raw
        bulge(k).status = 'skip: too few raw points';
        continue
    end

    % ---局地投影到x,y(m)---
    lon0 = mean(lon,'omitnan');
    lat0 = mean(lat,'omitnan');
    x = cfg.R_earth * cosd(lat0) .* deg2rad(lon - lon0);
    y = cfg.R_earth * deg2rad(lat - lat0);

    % ---去掉重复点/零步长，确保弧长严格递增---
    ds_xy = hypot(diff(x), diff(y));
    keep  = [true; ds_xy > 0];
    x = x(keep); y = y(keep);
    lon = lon(keep); lat = lat(keep);

    if numel(x) < cfg.minN_raw
        bulge(k).status = 'skip: too few unique points';
        continue
    end

    % ---弧长s0(m)---
    ds0 = hypot(diff(x), diff(y));
    s0  = [0; cumsum(ds0)];
    Lm  = s0(end);

    if ~isfinite(Lm) || Lm <= 0
        bulge(k).status = 'skip: invalid length';
        continue
    end

    % ---ds自适应：保证Ns>=minNs_target---
    ds = cfg.ds_resample_m;
    Ns_est = floor(Lm/ds) + 1;
    if Ns_est < cfg.minNs_target
        ds_try = Lm / (cfg.minNs_target - 1);
        ds = max(cfg.ds_min_m, min(cfg.ds_resample_m, ds_try));
    end

    % ---等弧长重采样---
    s  = (0:ds:Lm)';   % Ns×1
    Ns = numel(s);

    if Ns < 12
        bulge(k).status = 'skip: too few resampled points';
        continue
    end

    xr   = interp1(s0, x,   s, 'pchip');
    yr   = interp1(s0, y,   s, 'pchip');
    lonr = interp1(s0, lon, s, 'pchip');
    latr = interp1(s0, lat, s, 'pchip');

    % ---几何大尺度平滑---
    winG = max(5, round((cfg.smooth_km*1000)/ds));
    if mod(winG,2)==0, winG=winG+1; end
    winG = min(winG, Ns);

    xs = smoothdata(xr, 'movmean', winG);
    ys = smoothdata(yr, 'movmean', winG);

    % ---曲率：三点外接圆法（更稳）---
    kappa = nan(Ns,1);
    x1 = xs(1:end-2);  y1 = ys(1:end-2);
    x2 = xs(2:end-1);  y2 = ys(2:end-1);
    x3 = xs(3:end);    y3 = ys(3:end);

    a = hypot(x2-x1, y2-y1);
    b = hypot(x3-x2, y3-y2);
    c = hypot(x3-x1, y3-y1);

    % 三角形面积 = 0.5*|cross|
    area2 = abs( (x2-x1).*(y3-y1) - (y2-y1).*(x3-x1) ); % =2*Area
    k_mid = area2 ./ (a.*b.*c + eps);                   % = (2A)/(abc)
    k_mid = 2 * k_mid;                                  % = (4A)/(abc) = 1/R

    kappa(2:end-1) = k_mid;
    kappa(~isfinite(kappa)) = nan;

    % ---曲率再平滑（避免小拐角支配）---
    winK = max(5, round((cfg.kappaSmooth_km*1000)/ds));
    if mod(winK,2)==0, winK=winK+1; end
    winK = min(winK, Ns);
    kappa_s = smoothdata(kappa, 'movmean', winK);

    % ---端点剔除---
    dropN = max(2, round(cfg.dropEdgePct * Ns));
    idxRange = (1+dropN):(Ns-dropN);
    if numel(idxRange) < 6
        idxRange = 2:(Ns-1);
    end

    % ---关键：加权曲率选凸起点（强制远离端点）---
    % 权重w在中间最大，端点为0：w=sin(pi*s/L)^2
    w = sin(pi * (s/Lm)).^2;
    obj = kappa_s .* w;

    obj(1:dropN) = nan;
    obj(end-dropN+1:end) = nan;

    [objMax, idxK] = max(obj(idxRange), [], 'omitnan');
    idxK = idxRange(idxK);

    if ~isfinite(idxK) || ~isfinite(objMax)
        bulge(k).status = 'skip: no valid bulge';
        continue
    end

    % ---保存结果---
    bulge(k).lonK     = lonr(idxK);
    bulge(k).latK     = latr(idxK);
    bulge(k).s_km     = s(idxK)/1000;
    bulge(k).kappaMax = kappa_s(idxK);
    bulge(k).kappaObj = objMax;
    bulge(k).L_km     = Lm/1000;
    bulge(k).ds_m     = ds;
    bulge(k).Ns       = Ns;
    bulge(k).status   = 'ok';

    fprintf('Crest%d OK: L=%.2fkm, ds=%.0fm, Ns=%d, Bulge=(%.4f,%.4f), s=%.2fkm, kappa=%.3e\n', ...
        k, bulge(k).L_km, ds, Ns, bulge(k).lonK, bulge(k).latK, bulge(k).s_km, bulge(k).kappaMax);
end
end
