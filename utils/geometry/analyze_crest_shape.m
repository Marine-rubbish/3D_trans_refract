function [resLat, resLon, peakLat, peakLon, s_peak, L_total] = analyze_crest_shape(lat, lon, ds_res)
    % 输入：原始lat/lon, 重采样分辨率(m)
    % 输出：重采样后lat/lon, 凸起点lat/lon, 凸起点弧长, 总长
    
    % 1. 基础清洗 (去除NaN)
    good = isfinite(lat) & isfinite(lon);
    lat = lat(good); lon = lon(good);
    if length(lat) < 2
        resLat=lat; resLon=lon; peakLat=NaN; peakLon=NaN; s_peak=NaN; L_total=0; return; 
    end
    
    % 2. 投影到局部XY (m)
    R_earth = 6371000;
    lat0 = mean(lat); lon0 = mean(lon);
    x = R_earth * cosd(lat0) .* deg2rad(lon - lon0);
    y = R_earth * deg2rad(lat - lat0);
    
    % --- [核心修复] 去除重复点 ---
    % 计算相邻点之间的距离
    d_seg = hypot(diff(x), diff(y));
    % 仅保留距离大于微小阈值(1毫米)的点，避免重复或过近
    keep_mask = [true, d_seg > 1e-3]; 
    
    x = x(keep_mask);
    y = y(keep_mask);
    lat = lat(keep_mask);
    lon = lon(keep_mask);
    
    % 去重后再次检查点数
    if length(x) < 2
         resLat=lat; resLon=lon; peakLat=NaN; peakLon=NaN; s_peak=NaN; L_total=0; return; 
    end
    % ---------------------------
    
    % 3. 确保SW->NE排序 (假设x+y最小为SW)
    if (x(1)+y(1)) > (x(end)+y(end))
        x = flipud(x); y = flipud(y);
        lat = flipud(lat); lon = flipud(lon);
    end
    
    % 4. 计算累计弧长
    ds0 = hypot(diff(x), diff(y));
    s0 = [0, cumsum(ds0)];
    L_total = s0(end);
    
    % 防止 L_total 为 0
    if L_total < 1e-3
         resLat=lat; resLon=lon; peakLat=NaN; peakLon=NaN; s_peak=NaN; return; 
    end

    % 5. 重采样
    s_new = (0:ds_res:L_total)';
    if isempty(s_new), s_new = [0; L_total]; end
    
    % 这里的 s0 现在是严格单调递增的，interp1 不会再报错
    xr = interp1(s0, x, s_new, 'pchip');
    yr = interp1(s0, y, s_new, 'pchip');
    resLon = interp1(s0, lon, s_new, 'pchip'); 
    resLat = interp1(s0, lat, s_new, 'pchip'); 
    
    Ns = length(s_new);
    if Ns < 5
         peakLat=NaN; peakLon=NaN; s_peak=NaN; return;
    end
    
    % 6. 平滑
    smooth_win = max(3, round(20000/ds_res)); % 20km平滑
    xs = smoothdata(xr, 'movmean', smooth_win);
    ys = smoothdata(yr, 'movmean', smooth_win);
    
    % 7. 计算曲率 (三点外接圆法)
    kappa = nan(Ns, 1);
    x1 = xs(1:end-2); y1 = ys(1:end-2);
    x2 = xs(2:end-1); y2 = ys(2:end-1);
    x3 = xs(3:end);   y3 = ys(3:end);
    
    a = hypot(x2-x1, y2-y1);
    b = hypot(x3-x2, y3-y2);
    c = hypot(x3-x1, y3-y1);
    area2 = abs((x2-x1).*(y3-y1) - (y2-y1).*(x3-x1));
    
    k_mid = 2 * area2 ./ (a.*b.*c + eps);
    kappa(2:end-1) = k_mid;
    
    % 8. 寻找加权最大曲率点 (Peak)
    w_weight = sin(pi * (s_new/L_total)).^2;
    kappa_weighted = kappa .* w_weight;
    
    [~, idx_peak] = max(kappa_weighted, [], 'omitnan');
    
    if isempty(idx_peak) || isnan(kappa(idx_peak))
        idx_peak = round(Ns/2);
    end
    
    peakLat = resLat(idx_peak);
    peakLon = resLon(idx_peak);
    s_peak = s_new(idx_peak);
end