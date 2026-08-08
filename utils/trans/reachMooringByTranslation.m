function [isPass, passTime, s_hit_meters, dPass, tRange, propLat, propLon] = reachMooringByTranslation( ...
    crestLat, crestLon, crestTime, moorLat, moorLon, cBound, radius, s_peak_input)
% 修改说明：
% 1. 优先进行 0 半径 (直接命中) 检测。
% 2. 如果存在直接命中 (投影距离 ≈ 0)，直接锁定该几何交点为 s_hit，跳过圈内搜索。
% 3. 如果没有直接命中，则退回原有的半径搜索逻辑 (找离 s_peak 最近的点)。

% --- 初始化 ---
isPass = false;
passTime = NaT;
s_hit_meters = NaN; 
dPass = NaN;
tRange = [NaN NaN];
propLat = NaN;
propLon = NaN;

% --- 检查输入 ---
if nargin < 8, s_peak_input = NaN; end 
if nargin < 7 || isempty(radius), radius = 0; end
if nargin < 6 || numel(cBound) ~= 2, error('cBound error'); end
vmin = cBound(1); vmax = cBound(2);

dirDeg = mod(90 - calcDirection(crestLat, crestLon), 360);
m = ~isnan(crestLat) & ~isnan(crestLon);
lat = crestLat(m); lon = crestLon(m);
if numel(lat) < 2, return; end

% --- 投影到局部米坐标 ---
lat0 = mean(lat); lon0 = mean(lon);
[x, y]   = ll2local(lat, lon, lat0, lon0);
[qx, qy] = ll2local(moorLat, moorLon, lat0, lon0);

% --- 强制排序 SW(-1) -> NE(+1) ---
score1 = lat(1);
scoreN = lat(end);
if score1 > scoreN
    x = flipud(x(:)); y = flipud(y(:));
else
    x = x(:); y = y(:);
end

% --- 计算弧长 ---
dist_seg = hypot(x(2:end)-x(1:end-1), y(2:end)-y(1:end-1));
cumLen = [0; cumsum(dist_seg)];
L = cumLen(end);
if L <= 0, return; end

% --- 传播向量 ---
uE = sind(dirDeg); uN = cosd(dirDeg);
uu = hypot(uE, uN);
if uu == 0, return; end
u = [uE/uu; uN/uu]; 

% =========================================================================
% 步骤 1: 确定平移距离 (寻找最佳切入时刻)
% =========================================================================
% 获取正向(F)和反向(B)的投影结果，包括几何交点位置 s_at_min
[distF, s_F, dTrans_F] = getProjectedHit(qx, qy, u, x, y, cumLen);
[distB, s_B, dTrans_B] = getProjectedHit(qx, qy, -u, x, y, cumLen);

% 定义“直接命中”的判定阈值 (米)
DIRECT_HIT_TOL = 1e-3; 

is_direct_hit = false;
chosen_dir = 0;

% --- 【新增】0 半径判定逻辑 ---
if distF <= DIRECT_HIT_TOL || distB <= DIRECT_HIT_TOL
    is_direct_hit = true;
    
    % 决策：哪个方向是直接命中？
    % 如果两边都命中(理论上几何体是一样的)，优先选位移小的
    if distF <= DIRECT_HIT_TOL && distB > DIRECT_HIT_TOL
        chosen_dir = 1;
    elseif distB <= DIRECT_HIT_TOL && distF > DIRECT_HIT_TOL
        chosen_dir = -1;
    else
        % 两边都命中，选位移绝对值小的
        if abs(dTrans_F) <= abs(dTrans_B)
            chosen_dir = 1;
        else
            chosen_dir = -1;
        end
    end
else
    % --- 原有逻辑：基于半径判定 ---
    hitF = distF <= radius;
    hitB = distB <= radius;
    
    if hitF && ~hitB
        chosen_dir = 1;
    elseif ~hitF && hitB
        chosen_dir = -1;
    elseif hitF && hitB
        if abs(dTrans_F) <= abs(dTrans_B), chosen_dir = 1; else, chosen_dir = -1; end
    else
        % Miss -> 保底选最近
        if distF <= distB, chosen_dir = 1; else, chosen_dir = -1; end
    end
end

% 提取最终的平移参数
if chosen_dir == 1
    final_dist = distF;
    final_trans = dTrans_F;
    dirSign = 1;
    s_direct = s_F; % 记录几何交点弧长
else
    final_dist = distB;
    final_trans = dTrans_B;
    dirSign = -1;
    s_direct = s_B; % 记录几何交点弧长
end

% 计算平移后的波峰线坐标
x_shifted = x + dirSign * final_trans * u(1);
y_shifted = y + dirSign * final_trans * u(2);

% =========================================================================
% 步骤 2: 确定最终命中点 s_hit_meters
% =========================================================================

if is_direct_hit
    % --- 情况 A: 直接命中 (0半径) ---
    isPass = true;
    s_hit_meters = s_direct; % 直接使用投影计算出的几何交点
    
    % 无需再进行圈内搜索，直接返回结果
    
else
    % --- 情况 B: 未直接命中，进行圈内搜索 ---
    
    % 计算平移后，波峰线上每个节点到系泊点的距离
    dists_to_mooring = hypot(x_shifted - qx, y_shifted - qy);
    
    % 找到所有在半径内的点
    in_circle_mask = dists_to_mooring <= (radius + 1e-3);
    
    if any(in_circle_mask)
        isPass = true;
        s_candidates = cumLen(in_circle_mask);
        
        if isnan(s_peak_input)
            % 如果没有 s_peak，退化为找最近点
            [~, min_idx] = min(dists_to_mooring(in_circle_mask));
            s_hit_meters = s_candidates(min_idx);
        else
            % 【原有逻辑】找离 s_peak 最近的点
            [min_diff, idx_closest] = min(abs(s_candidates - s_peak_input));
            s_hit_meters = s_candidates(idx_closest);
        end
    else
        % 完全 Miss
        isPass = false;
        s_hit_meters = s_direct; % 同样返回几何最近点作为保底
    end
end

% --- 填写输出 ---
dPass = final_trans;
tEarliest = dPass / vmax; 
tLatest   = dPass / vmin;
tRange = [tEarliest, tLatest];
passTime = crestTime + seconds(dirSign * tEarliest);

[propLat, propLon] = local2ll(x_shifted, y_shifted, lat0, lon0);

end

% ================= 辅助函数 =================
function [minDist, s_at_min, d_trans] = getProjectedHit(qx, qy, u_vec, x, y, cumLen)
    % 纯几何投影找点
    % 输出增加 s_at_min: 投影点在波峰线上的弧长
    
    v = [-u_vec(2); u_vec(1)];
    target_h = qx * v(1) + qy * v(2);
    best_h_dist = inf; best_idx = -1; best_t = 0;
    
    for i = 1:numel(x)-1
        h1 = x(i)*v(1) + y(i)*v(2); h2 = x(i+1)*v(1) + y(i+1)*v(2);
        h_min = min(h1, h2); h_max = max(h1, h2);
        dist = inf; t = 0;
        
        if target_h >= h_min && target_h <= h_max
            dist = 0; 
            if abs(h2 - h1) > 1e-9, t = (target_h - h1)/(h2 - h1); else, t=0; end
        else
            d1 = abs(target_h - h1); d2 = abs(target_h - h2);
            if d1 < d2, dist = d1; t = 0; else, dist = d2; t = 1; end
        end
        
        if dist < best_h_dist - 1e-9
            best_h_dist = dist; best_idx = i; best_t = t;
        end
    end
    minDist = best_h_dist;
    s_at_min = cumLen(best_idx) + best_t * (cumLen(best_idx+1) - cumLen(best_idx));
    Px = x(best_idx) + best_t * (x(best_idx+1) - x(best_idx));
    Py = y(best_idx) + best_t * (y(best_idx+1) - y(best_idx));
    d_trans = (qx - Px) * u_vec(1) + (qy - Py) * u_vec(2);
end

function [x, y] = ll2local(lat, lon, lat0, lon0)
x = (lon - lon0) .* cosd(lat0) * 111320; 
y = (lat - lat0) * 110540;              
end

function [lat, lon] = local2ll(x, y, lat0, lon0)
lon = lon0 + x / (cosd(lat0) * 111320);
lat = lat0 + y / 110540;
end
