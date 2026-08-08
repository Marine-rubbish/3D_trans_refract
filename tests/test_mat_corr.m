clc
clear

addpath(genpath('..\utils'));

%% 读取波峰线数据
shp_dir = 'F:\research\MODIS\shp_files';
shp_filelist = dir(fullfile(shp_dir, '*.shp'));

%% 提取所有波峰线
all_crest = {};
shp_time_list = {};
for k = 1:length(shp_filelist)
    shp_name = fullfile(shp_dir, shp_filelist(k).name);
    shp_time = getTimeFromFilename(shp_filelist(k).name) + hours(8); % 转为北京时间
    crestLines = shaperead(shp_name);
    for i = 1:length(crestLines)
        shp_time_list = [shp_time_list; shp_time];
        all_crest = [all_crest; {crestLines(i).X, crestLines(i).Y}];
    end
end

%% 读取匹配的mat
project_root = fileparts(fileparts(mfilename('fullpath')));
mat_dir = fullfile(project_root, 'data', 'matched_crests_params_855.mat');
load(mat_dir); % 加载变量 matched_crests_params_855

shp_time_list = shp_time_list(crest_idx_out);

% 如果需要，从加载的 struct 中提取变量
if ~exist('crest_time','var') && exist('matched_crests_params_855','var') && isstruct(matched_crests_params_855)
    if isfield(matched_crests_params_855,'crest_time');   crest_time = matched_crests_params_855.crest_time;   end
    if isfield(matched_crests_params_855,'mooring_time'); mooring_time = matched_crests_params_855.mooring_time; end
end

assert(exist('crest_time','var') && exist('mooring_time','var'), 'crest_time or mooring_time not found.')

% 确保为 datetime
if ~isa(crest_time,'datetime')
    try
        crest_time = datetime(crest_time,'ConvertFrom','datenum');
    catch
        crest_time = datetime(crest_time);
    end
end
if ~isa(mooring_time,'datetime')
    try
        mooring_time = datetime(mooring_time,'ConvertFrom','datenum');
    catch
        mooring_time = datetime(mooring_time);
    end
end

% 长度一致性检查
if numel(crest_time) ~= numel(mooring_time)
    error('crest_time and mooring_time must have the same length.')
end

% 计算绝对时间差（天）并查找超过 3 天的索引
diff_days = abs(days(crest_time - mooring_time));
idx = find(diff_days > 3);

if isempty(idx)
    disp('No pairs differ by more than 3 days.')
else
    fprintf('Found %d pairs with difference > 3 days:\n', numel(idx));
    for k = 1:numel(idx)
        i = idx(k);
        fprintf('Index %d: crest=%s, mooring=%s, diff=%.2f days\n', i, char(crest_time(i)), char(mooring_time(i)), diff_days(i));
    end
end

%% 系数设置
% 系泊点坐标
mooring_lat = 20.816666666666666;
mooring_lon = 115.76666666666667;

% 监测半径 (米)
MOORING_RADIUS = 100000; % 100km

day_delay = 3;

%% 画图
for i = 1:length(peak_lon)
    [isPass, ~, s_hit_meters, ~, ~, propLat, propLon] = reachMooringByTranslation( ...
        crest_lat{i}, crest_lon{i}, shp_time_list(i), ...
        mooring_lat, mooring_lon, [0.1 5.0], MOORING_RADIUS, 0);
    % figure;
    plot(crest_lon{i}, crest_lat{i})
    hold on
    plot(propLon, propLat)
    plot(mooring_lon, mooring_lat, 'ro', 'MarkerSize', 12, 'MarkerFaceColor', 'r');
    plot(peak_lon(i), peak_lat(i), 'pentagram', ...
                     'MarkerSize', 15, ...
                     'MarkerEdgeColor', 'k', ...
                     'MarkerFaceColor', 'g', ...
                     'LineWidth', 1.5);
    hold off;
    fprintf("ispass = %d, K_mooring = %.4f\n", isPass, K_mooring(i));
    drawnow;
    pause(2);
end

%% cmp with 808 mat
mat_dir_808 = fullfile(project_root, 'data', 'selected_crests_params_808.mat');
S808 = load(mat_dir_808);

% 兼容：mat 里可能是一个 struct 变量，也可能是散变量
fn = fieldnames(S808);
if numel(fn) == 1 && isstruct(S808.(fn{1}))
    P808 = S808.(fn{1});
else
    P808 = S808;
end

% ---- 从 808 中提取关键变量（字段名做兼容）----
if isstruct(P808)
    if isfield(P808,'crest_idx_out')
        crest_idx_out_808 = P808.crest_idx_out;
    elseif isfield(P808,'crest_idx')
        crest_idx_out_808 = P808.crest_idx;
    else
        error('808 mat does not contain crest_idx_out / crest_idx.');
    end

    if isfield(P808,'K_mooring'),  K_mooring_808 = P808.K_mooring;  else, error('808 mat missing K_mooring.'); end
    if isfield(P808,'crest_lat'),  crest_lat_808 = P808.crest_lat;  else, error('808 mat missing crest_lat.'); end
    if isfield(P808,'crest_lon'),  crest_lon_808 = P808.crest_lon;  else, error('808 mat missing crest_lon.'); end
    if isfield(P808,'peak_lat'),   peak_lat_808  = P808.peak_lat;   else, error('808 mat missing peak_lat.'); end
    if isfield(P808,'peak_lon'),   peak_lon_808  = P808.peak_lon;   else, error('808 mat missing peak_lon.'); end
else
    error('Unexpected content in 808 mat.');
end

% ---- 与 855（当前工作区变量）按 crest_idx_out 对齐 ----
[common_idx, ia855, ia808] = intersect(crest_idx_out(:), crest_idx_out_808(:), 'stable');
fprintf('Common crest_idx_out count = %d\n', numel(common_idx));
if isempty(common_idx)
    warning('No common indices between 855 crest_idx_out and 808 crest_idx_out.');
else
    % 峰值点差异（球面距离，米）
    R = 6371000;
    hav_m = @(lat1,lon1,lat2,lon2) 2*R*asin( ...
        sqrt( sin(deg2rad((lat2-lat1)/2)).^2 + cosd(lat1).*cosd(lat2).*sin(deg2rad((lon2-lon1)/2)).^2 ) );

    K855 = K_mooring(ia855);
    K808 = K_mooring_808(ia808);
    dK   = K855 - K808;

    peakDist_m = hav_m(peak_lat(ia855), peak_lon(ia855), peak_lat_808(ia808), peak_lon_808(ia808));

    % crest 线形差异：重采样后逐点距离（均值/最大值）
    N = 200;
    crestMeanDist_m = nan(numel(common_idx),1);
    crestMaxDist_m  = nan(numel(common_idx),1);

    for t = 1:numel(common_idx)
        latA = crest_lat{ia855(t)}(:); lonA = crest_lon{ia855(t)}(:);
        latB = crest_lat_808{ia808(t)}(:); lonB = crest_lon_808{ia808(t)}(:);

        goodA = isfinite(latA) & isfinite(lonA);
        goodB = isfinite(latB) & isfinite(lonB);
        latA = latA(goodA); lonA = lonA(goodA);
        latB = latB(goodB); lonB = lonB(goodB);

        if numel(latA) < 2 || numel(latB) < 2
            continue;
        end

        % 用分段球面距离构造弧长参数，并按 0..1 归一化重采样
        dsA = hav_m(latA(1:end-1), lonA(1:end-1), latA(2:end), lonA(2:end));
        dsB = hav_m(latB(1:end-1), lonB(1:end-1), latB(2:end), lonB(2:end));
        sA = [0; cumsum(dsA)];  sB = [0; cumsum(dsB)];

        if sA(end) <= 0 || sB(end) <= 0
            continue;
        end

        uA = sA / sA(end);
        uB = sB / sB(end);
        uq = linspace(0,1,N)';

        latAi = interp1(uA, latA, uq, 'linear', 'extrap');
        lonAi = interp1(uA, lonA, uq, 'linear', 'extrap');
        latBi = interp1(uB, latB, uq, 'linear', 'extrap');
        lonBi = interp1(uB, lonB, uq, 'linear', 'extrap');

        d_m = hav_m(latAi, lonAi, latBi, lonBi);
        crestMeanDist_m(t) = mean(d_m, 'omitnan');
        crestMaxDist_m(t)  = max(d_m, [], 'omitnan');
    end

    T = table(common_idx, K855(:), K808(:), dK(:), peakDist_m(:), crestMeanDist_m, crestMaxDist_m, ...
        'VariableNames', {'crest_idx_out','K_mooring_855','K_mooring_808','dK','peakDist_m','crestMeanDist_m','crestMaxDist_m'});

    disp(T);

    figure;
    tiledlayout(1,2,'Padding','compact','TileSpacing','compact');

    nexttile;
    scatter(K808, K855, 25, peakDist_m, 'filled'); colorbar;
    xlabel('K\_mooring (808)'); ylabel('K\_mooring (855)'); grid on;
    title('K\_mooring 对比（颜色=峰值点距离 m）');

    nexttile;
    histogram(dK, 30); grid on;
    xlabel('K\_mooring(855) - K\_mooring(808)'); ylabel('count');
    title('dK 分布');
end

%% 
function [resLat, resLon, peakLat, peakLon, s_peak, L_total] = analyze_crest_shape(lat, lon, ds_res)
    % 1. 基础清洗 & 强制列向量
    lat = lat(:); lon = lon(:); 
    good = isfinite(lat) & isfinite(lon);
    lat = lat(good); lon = lon(good);
    
    if length(lat) < 3
        resLat=lat; resLon=lon; peakLat=NaN; peakLon=NaN; s_peak=NaN; L_total=0; return; 
    end
    
    % 2. 投影到局部米制坐标
    R_earth = 6371000;
    lat0 = mean(lat); lon0 = mean(lon);
    x = R_earth * cosd(lat0) .* deg2rad(lon - lon0);
    y = R_earth * deg2rad(lat - lat0);
    
    % 去重
    d_seg = hypot(diff(x), diff(y));
    keep_mask = [true; d_seg > 1e-3]; 
    x = x(keep_mask); y = y(keep_mask);
    lat = lat(keep_mask); lon = lon(keep_mask);
    
    if length(x) < 3
         resLat=lat; resLon=lon; peakLat=NaN; peakLon=NaN; s_peak=NaN; L_total=0; return; 
    end
    
    % 强制 SW -> NE 排序
    if (y(1)) > (y(end))
        x = flipud(x); y = flipud(y);
        lat = flipud(lat); lon = flipud(lon);
    end
    
    % ==========================================================
    % Step 3. 极高密度线性重采样
    % ==========================================================
    ds0 = hypot(diff(x), diff(y));
    s0 = [0; cumsum(ds0)];
    L_original = s0(end);
    
    s_super = (0:10:L_original)'; 
    if isempty(s_super), s_super = [0; L_original]; end
    
    x_super = interp1(s0, x, s_super, 'linear');
    y_super = interp1(s0, y, s_super, 'linear');
    lon_super = interp1(s0, lon, s_super, 'linear');
    lat_super = interp1(s0, lat, s_super, 'linear');
    
    % ==========================================================
    % Step 4. 坐标高斯平滑 + 端点锚定
    % ==========================================================
    smooth_window_m = 5000; 
    win_pts = max(3, round(smooth_window_m / 10)); 
    
    x_smooth = smoothdata(x_super, 'gaussian', win_pts);
    y_smooth = smoothdata(y_super, 'gaussian', win_pts);
    lon_smooth = smoothdata(lon_super, 'gaussian', win_pts);
    lat_smooth = smoothdata(lat_super, 'gaussian', win_pts);
    
    x_smooth(1) = x_super(1); x_smooth(end) = x_super(end);
    y_smooth(1) = y_super(1); y_smooth(end) = y_super(end);
    lon_smooth(1) = lon_super(1); lon_smooth(end) = lon_super(end);
    lat_smooth(1) = lat_super(1); lat_smooth(end) = lat_super(end);
    
    % ==========================================================
    % Step 5. 最终重采样
    % ==========================================================
    d_smooth_steps = hypot(diff(x_smooth), diff(y_smooth));
    s_smooth_cum = [0; cumsum(d_smooth_steps)];
    L_total = s_smooth_cum(end); 
    
    s_final = (0:ds_res:L_total)';
    if isempty(s_final), s_final = [0; L_total]; end
    
    xr = interp1(s_smooth_cum, x_smooth, s_final, 'linear');
    yr = interp1(s_smooth_cum, y_smooth, s_final, 'linear');
    resLon = interp1(s_smooth_cum, lon_smooth, s_final, 'linear');
    resLat = interp1(s_smooth_cum, lat_smooth, s_final, 'linear');
    
    s_new = s_final;
    Ns = length(s_new);
    if Ns < 5
         peakLat=NaN; peakLon=NaN; s_peak=NaN; return;
    end
    
    % ==========================================================
    % Step 6. 计算带符号曲率 (Signed Curvature)
    % ==========================================================
    % 为了区分凹凸，必须计算有符号的行列式
    k_signed = nan(Ns, 1);
    
    x1 = xr(1:end-2); y1 = yr(1:end-2);
    x2 = xr(2:end-1); y2 = yr(2:end-1);
    x3 = xr(3:end);   y3 = yr(3:end);
    
    a = hypot(x2-x1, y2-y1);
    b = hypot(x3-x2, y3-y2);
    c = hypot(x3-x1, y3-y1);
    
    % 计算有符号面积 (2D Cross Product)
    % det > 0 表示向左转，det < 0 表示向右转
    det_val = (x2-x1).*(y3-y2) - (y2-y1).*(x3-x2);
    
    denom = a.*b.*c;
    denom(denom < 1e-6) = 1e-6; 
    
    % k_signed 包含了方向信息 (+/-)
    k_mid = 2 * det_val ./ denom;
    k_signed(2:end-1) = k_mid;
    
    % ==========================================================
    % Step 7. 【核心新增】凹凸性一致性筛选 (Convexity Consistency)
    % ==========================================================
    
    % 1. 判断整条线的“主弯曲方向” (Dominant Direction)
    % 通过对所有点的曲率求和，看整体是往哪边弯
    % (忽略 NaN)
    valid_k = k_signed(~isnan(k_signed));
    
    if isempty(valid_k)
        main_sign = 0;
    else
        % 投票法：看正曲率总和与负曲率总和谁大
        sum_pos = sum(valid_k(valid_k > 0));
        sum_neg = sum(valid_k(valid_k < 0));
        
        if abs(sum_pos) > abs(sum_neg)
            main_sign = 1;  % 整体向左弯 (凸)
        else
            main_sign = -1; % 整体向右弯 (凸)
        end
    end
    
    % 2. 过滤：只保留“凸”的曲率，剔除“凹”的曲率
    % 任何与主方向符号相反的点，其曲率强度视为 0 (或极小)
    kappa_mag = abs(k_signed); % 取绝对值用于找最大
    
    % 如果某点符号与主符号相反，且曲率不是微小噪声，则视为反向弯曲(凹)，剔除
    % (阈值 1e-6 防止处理直线噪声)
    bad_mask = (sign(k_signed) ~= main_sign) & (abs(k_signed) > 1e-6);
    kappa_mag(bad_mask) = 0; 
    
    % ==========================================================
    % Step 8. 寻找 Peak (含平直度检测)
    % ==========================================================
    chord_len = hypot(xr(end)-xr(1), yr(end)-yr(1));
    straightness = chord_len / L_total; 
    
    if straightness > 0.99
        sigma = 0.15; 
        s_norm = s_new / L_total;
        w_gaussian = exp(- (s_norm - 0.5).^2 / (2 * sigma^2));
    elseif straightness > 0.95
        sigma = 0.3;
        s_norm = s_new / L_total;
        w_gaussian = exp(- (s_norm - 0.5).^2 / (2 * sigma^2));
    else
        w_guassian = sin(pi * (s_new/L_total)).^2;
    end
    
    cut_idx = round(Ns * 0.1); 
    if cut_idx > 0 && cut_idx*2 < Ns
        w_gaussian(1:cut_idx) = 0;
        w_gaussian(end-cut_idx:end) = 0;
    end
    
    % 这里的 kappa_mag 已经是剔除了凹点的版本
    kappa_weighted = kappa_mag .* w_gaussian;
    
    [~, idx_peak] = max(kappa_weighted, [], 'omitnan');
    
    if isempty(idx_peak) || isnan(kappa_mag(idx_peak))
        idx_peak = round(Ns/2);
    end
    
    peakLat = resLat(idx_peak);
    peakLon = resLon(idx_peak);
    s_peak = s_new(idx_peak);
    
    plot(resLon, resLat)
    hold on
    plot(lon, lat)
    plot(peakLon, peakLat, 'pentagram', ...
                     'MarkerSize', 15, ...
                     'MarkerEdgeColor', 'k', ...
                     'MarkerFaceColor', 'g', ...
                     'LineWidth', 1.5);
    ;
end


