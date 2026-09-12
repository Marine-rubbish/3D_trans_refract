function [resLat, resLon, peakLat, peakLon, s_peak, L_total] = analyze_crest_shape_orig(lat, lon, ds_res)
% ANALYZE_CREST_SHAPE 分析波峰线几何形状并寻找凸起点
% 
% 输入:
%   lat, lon: 原始波峰线的经纬度数组
%   ds_res:   期望的重采样分辨率 (米)，例如 250 或 1000
%
% 输出:
%   resLat, resLon: 重采样并平滑后的经纬度
%   peakLat, peakLon: 识别出的凸起点坐标
%   s_peak: 凸起点对应的弧长 (米)
%   L_total: 波峰线总长度 (米)
%
% 算法逻辑来自 plot_curv.m:
%   1. 投影到局部平面坐标
%   2. 自适应重采样 (保证点数足够)
%   3. 几何大尺度平滑 (消除锯齿)
%   4. 三点外接圆法计算曲率 + 二次平滑
%   5. 加权曲率寻峰 (Sin^2 权重抑制端点)

    %% 1. 参数配置 (内部硬编码或根据需要改为输入参数)
    cfg.R_earth = 6371000;     % 地球半径 (m)
    cfg.minN_raw = 2;          % 原始点数下限
    cfg.minNs_target = 60;     % 目标重采样点数下限 (保证平滑窗口有效)
    
    % 平滑参数 (根据 plot_curv.m 的设置)
    cfg.smooth_km = 20;        % 几何平滑尺度 (km)
    cfg.kappaSmooth_km = 10;   % 曲率再平滑尺度 (km)
    cfg.dropEdgePct = 0.05;    % 首尾剔除比例

    %% 2. 初始化输出
    resLat = []; resLon = [];
    peakLat = NaN; peakLon = NaN;
    s_peak = NaN; L_total = 0;

    %% 3. 数据预处理
    lat = lat(:); lon = lon(:);
    good = isfinite(lat) & isfinite(lon);
    lat = lat(good); lon = lon(good);

    if numel(lat) < cfg.minN_raw
        return; % 点数过少
    end

    %% 4. 投影到局部平面坐标 (米)
    lon0 = mean(lon);
    lat0 = mean(lat);
    x = cfg.R_earth * cosd(lat0) .* deg2rad(lon - lon0);
    y = cfg.R_earth * deg2rad(lat - lat0);

    % 去掉重复点/零步长，确保弧长严格递增
    ds_xy = hypot(diff(x), diff(y));
    keep  = [true; ds_xy > 1e-3]; % 容差 1mm
    x = x(keep); y = y(keep);
    lon = lon(keep); lat = lat(keep);

    if numel(x) < cfg.minN_raw
        return;
    end

    %% 5. 统一点序为 SW -> NE
    % 与 reachMooringByTranslation 保持相同约定：低纬端作为弧长起点。
    % 必须在累计弧长和重采样之前翻转，确保 resLat/resLon、s_peak
    % 和 L_total 均使用同一个方向定义。
    if lat(1) > lat(end)
        x = flipud(x);
        y = flipud(y);
        lon = flipud(lon);
        lat = flipud(lat);
    end

    %% 6. 计算原始弧长
    ds0 = hypot(diff(x), diff(y));
    s0  = [0; cumsum(ds0)];
    L_total = s0(end);

    if L_total <= 0
        return;
    end

    %% 7. 自适应重采样
    % 逻辑：如果 total_length / ds_res 得到的点数太少，自动减小 ds
    ds = ds_res;
    Ns_est = floor(L_total / ds) + 1;
    
    if Ns_est < cfg.minNs_target
        % 强制保证至少有 minNs_target 个点，以便进行后续的平滑操作
        ds = L_total / (cfg.minNs_target - 1);
    end

    % 等弧长重采样
    s_new = (0:ds:L_total)';
    Ns = numel(s_new);
    
    if Ns < 12
        return; % 重采样后点数依然极少，无法计算
    end

    % 使用 pchip 插值 (保持形状单调性，避免 spline 的过冲)
    xr   = interp1(s0, x,   s_new, 'pchip');
    yr   = interp1(s0, y,   s_new, 'pchip');
    resLon = interp1(s0, lon, s_new, 'pchip');
    resLat = interp1(s0, lat, s_new, 'pchip');

    %% 8. 几何大尺度平滑 (Coordinate Smoothing)
    % 窗口大小自适应： smooth_km (m) / ds (m)
    winG = max(5, round((cfg.smooth_km * 1000) / ds));
    if mod(winG, 2) == 0, winG = winG + 1; end % 保证奇数窗口
    winG = min(winG, Ns);

    xs = smoothdata(xr, 'movmean', winG);
    ys = smoothdata(yr, 'movmean', winG);

    %% 9. 计算曲率 (三点外接圆法)
    kappa = nan(Ns, 1);
    
    x1 = xs(1:end-2); y1 = ys(1:end-2);
    x2 = xs(2:end-1); y2 = ys(2:end-1);
    x3 = xs(3:end);   y3 = ys(3:end);

    a = hypot(x2-x1, y2-y1);
    b = hypot(x3-x2, y3-y2);
    c = hypot(x3-x1, y3-y1);

    % 三角形面积 = 0.5 * |cross_product|
    % 2*Area = |(x2-x1)(y3-y1) - (y2-y1)(x3-x1)|
    area2 = abs((x2-x1).*(y3-y1) - (y2-y1).*(x3-x1));
    
    % Menger Curvature k = 4*Area / (a*b*c)
    denom = a.*b.*c;
    denom(denom < 1e-9) = NaN; % 防止除零
    k_mid = 2 * area2 ./ denom; 

    kappa(2:end-1) = k_mid;
    
    % 填充边界NaN (简单设为邻近值或0)
    if isnan(kappa(1)), kappa(1) = kappa(2); end
    if isnan(kappa(end)), kappa(end) = kappa(end-1); end

    %% 10. 曲率再平滑 (Curvature Smoothing)
    winK = max(5, round((cfg.kappaSmooth_km * 1000) / ds));
    if mod(winK, 2) == 0, winK = winK + 1; end
    winK = min(winK, Ns);
    
    kappa_s = smoothdata(kappa, 'movmean', winK);

    %% 11. 加权寻峰 (Weighted Peak Finding)
    % 剔除首尾比例
    dropN = max(2, round(cfg.dropEdgePct * Ns));
    
    % 权重函数：中间高，两头低 (sin^2)
    w_weight = sin(pi * (s_new / L_total)).^2;
    
    % 目标函数
    obj = kappa_s .* w_weight;

    % 强制边缘无效化
    obj(1:dropN) = NaN;
    obj(end-dropN+1:end) = NaN;

    % 寻找最大值
    [~, idxK] = max(obj, [], 'omitnan');

    if isempty(idxK)
        % 兜底：如果算不出，取几何中心
        idxK = round(Ns/2);
    end

    %% 12. 输出赋值
    peakLat = resLat(idxK);
    peakLon = resLon(idxK);
    s_peak  = s_new(idxK);

end
