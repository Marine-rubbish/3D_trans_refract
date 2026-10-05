function [isPass, propSpeed, crest_min_dis, details] = isCrestPassMooring_capsule_dir( ...
    crestLat, crestLon, crestTime, crestType, moorLat, moorLon, ...
    moorStTime, moorEdTime, teps, tlim, radius, directionResolution)
% isCrestPassMooring_capsule_dir 解析判断平移波峰线能否到达系泊点。
%
% 几何模型
%   函数名保留 capsule 是为了兼容现有调用；当前几何判定使用“横向走廊”。
%   radius 只限制波峰点相对系泊点的横向距离，不再同时扩张沿传播方向的
%   位移。对每条线段解析求出满足横向距离限制的线段参数，再转换为波峰沿
%   传播方向到达系泊点所需的有符号位移区间。整个过程不使用迭代搜索。
%
% 输入
%   crestLat, crestLon  波峰折线坐标（度），允许包含 NaN。
%   crestTime          遥感观测时间（datetime）。
%   crestType          模态编号；1 对应 [1,3] m/s，其他对应 [0.3,1.4] m/s。
%   moorLat, moorLon   系泊点坐标（度）。
%   moorStTime         系泊事件开始时间（datetime）。
%   moorEdTime         系泊事件结束时间（datetime）。
%   teps               保留的旧接口参数（秒）；解析法不依赖迭代精度。
%   tlim               相对 crestTime 的最大时间范围（秒）。
%   radius             允许的最大横向距离（米）。
%   directionResolution 可选；resolveCrestDirection 的返回结构。主匹配
%                       入口应传入同一结构，保证匹配与保存使用同一方向。
%
% 输出
%   isPass             几何可达，且横向最近点的传播位移与系泊时间方向
%                      一致时为 true。
%   propSpeed          施加 5 m/s 硬上限后的可行正速度包络 [vmin,vmax]
%                      （m/s）；后续匈牙利匹配继续使用该区间计算速度差。
%   crest_min_dis      在 dPhysical 位移范围内，波峰扫掠区域到系泊点的最短
%                      距离（米）。
%   details            诊断结构，保存方向、时间、位移和速度区间等中间结果。
%
% 符号约定
%   dt = mooringTime - crestTime。
%   d > 0 表示波峰沿 dirDeg 正向平移；d < 0 表示 crestTime 之前的位置。
%   正速度要求 d 与 dt 同号。
%
% 判定策略
%   在有限折线的连续线段上寻找横向距离系泊点最近的点。对仅位于遥感时间
%   之后的系泊事件，该点的 d 必须为正；对仅位于遥感时间之前的事件，该点
%   的 d 必须为负。最近点位于 d=0 或时间窗跨越遥感时刻时拒绝。
%   初始方向位于 30°–180° 时，必须通过 maybeFlipCrestDir 的翻转条件；
%   doFlip=false 时拒绝。可行速度与 (0,5] m/s 无交集时拒绝。
%   feasibleSpeedIntervals 只作为模态速度范围诊断，不参与 isPass。

isPass = false;
propSpeed = NaN;
crest_min_dis = inf;
details = defaultDetails();

%% 1. 默认值与输入合法性
if nargin < 11 || isempty(radius), radius = 0; end
if nargin < 10 || isempty(tlim), tlim = inf; end
if nargin < 9 || isempty(teps), teps = 0; end
if nargin < 12, directionResolution = []; end
details.searchToleranceSeconds = teps;
if ~isscalar(radius) || ~isfinite(radius) || radius < 0
    error('radius must be a finite nonnegative scalar in meters.');
end
if ~isscalar(tlim) || isnan(tlim) || tlim <= 0
    error('tlim must be a positive scalar in seconds.');
end

%% 2. 清理波峰坐标
% 经纬度必须成对有效；统一转换为列向量，避免输入行列方向影响后续矩阵运算。
good = isfinite(crestLat) & isfinite(crestLon);
lat = crestLat(good);
lon = crestLon(good);
lat = lat(:);
lon = lon(:);
if numel(lat) < 2
    details.reason = "invalid_crest";
    return;
end

%% 3. 确定传播方向
% 方向统一由 resolveCrestDirection 解析。主入口会把读取波锋时得到的
% 同一结果传入；其他旧调用未传入时，也调用统一函数，不复制规则。
if isempty(directionResolution)
    directionResolution = resolveCrestDirection( ...
        lat, lon, moorLat, moorLon);
elseif ~isstruct(directionResolution) || ...
        ~all(isfield(directionResolution, ...
        {'isValid','initialDirDeg','dirDeg','flipRequired', ...
         'doFlip','flipStats','reason'}))
    error('directionResolution must come from resolveCrestDirection.');
end
details.initialDirDeg = directionResolution.initialDirDeg;
details.dirDeg = directionResolution.dirDeg;
details.directionFlipRequired = directionResolution.flipRequired;
details.directionFlipAccepted = directionResolution.doFlip;
details.directionFlipStats = directionResolution.flipStats;
if ~directionResolution.isValid
    details.reason = directionResolution.reason;
    return;
end
dirDeg = directionResolution.dirDeg;
details.dirDeg = dirDeg;

%% 4. 根据模态设置参考速度范围
% cBound 同时用于构造 dPhysical，并用于计算 details.speedIntervals。
maxPropagationSpeedMps = 5;
details.maxPropagationSpeedMps = maxPropagationSpeedMps;
if crestType == 1
    cBound = [1, 3];
else
    cBound = [0.3, 1.4];
end
details.speedBounds = cBound;

%% 5. 将系泊绝对时间转换为相对遥感时间
% dtLo/dtHi 单位为秒，并裁剪到 [-tlim,tlim]。负时间表示系泊事件早于
% 遥感观测时间，正时间表示系泊事件晚于遥感观测时间。
dt = sort([seconds(moorStTime - crestTime), seconds(moorEdTime - crestTime)]);
dtLo = max(dt(1), -abs(tlim));
dtHi = min(dt(2),  abs(tlim));
details.timeRangeSeconds = [dtLo, dtHi];
if any(~isfinite(dt)) || dtLo > dtHi
    details.reason = "time_outside_limit";
    return;
end
timeDirection = classifyTimeDirection(dtLo, dtHi);
details.timeDirection = timeDirection;

%% 6. 转到局部米制平面坐标
% x 指向东，y 指向北。u 是传播方向单位向量：
%   u = [east_component; north_component]。
lat0 = mean(lat);
lon0 = mean(lon);
[x, y] = ll2local(lat, lon, lat0, lon0);
[qx, qy] = ll2local(moorLat, moorLon, lat0, lon0);
q = [qx; qy];
u = [sind(dirDeg); cosd(dirDeg)];
u = u / norm(u);

%% 7. 时间窗口和模态速度对应的有符号位移包络
% 对 d = c*dt 的四个端点组合取最小值和最大值。该范围只用于计算
% crest_min_dis；横向走廊产生的 dInterval 本身不受此范围裁剪。
products = [cBound(1)*dtLo, cBound(1)*dtHi, ...
            cBound(2)*dtLo, cBound(2)*dtHi];
dPhysical = [min(products), max(products)];
details.physicalDisplacementRangeMeters = dPhysical;

allDIntervals = zeros(0, 2);
directionalDIntervals = zeros(0, 2);
rawSpeedIntervals = zeros(0, 2);
limitedSpeedIntervals = zeros(0, 2);
feasibleSpeedIntervals = zeros(0, 2);
hitSegments = zeros(0, 1);
ambiguousSegments = zeros(0, 1);
closestCrossTrackMeters = inf;
closestSignedCrossTrackMeters = NaN;
closestAlongDisplacementMeters = NaN;
closestSegment = NaN;
closestSegmentParameter = NaN;

%% 8. 逐线段执行解析横向走廊求交
% 与旧函数不同，这里遍历 1:numel(x)-1，因此最后一条线段也参与判断。
for i = 1:numel(x)-1
    a = [x(i); y(i)];
    b = [x(i+1); y(i+1)];

    % 在连续线段上解析求横向距离最小点。若不同线段的最小横向距离在
    % 数值误差内相同，则取 |d| 更小者，减少折线点存储顺序的影响。
    [segmentCrossTrack, segmentSignedCrossTrack, segmentAlong, segmentT] = ...
        closestCrossTrackPoint(q, u, a, b);
    if isBetterClosestPoint(segmentCrossTrack, segmentAlong, ...
            closestCrossTrackMeters, closestAlongDisplacementMeters)
        closestCrossTrackMeters = segmentCrossTrack;
        closestSignedCrossTrackMeters = segmentSignedCrossTrack;
        closestAlongDisplacementMeters = segmentAlong;
        closestSegment = i;
        closestSegmentParameter = segmentT;
    end

    % 线段在 dPhysical 范围内平移后扫出平行四边形。计算系泊点到该
    % 扫掠区域的精确最短距离，并在所有线段之间取全局最小值。
    segmentMinDis = pointToSweptSegmentDistance(q, a, b, u, ...
        dPhysical(1), dPhysical(2));
    crest_min_dis = min(crest_min_dis, segmentMinDis);

    % 找出线段中横向距离不超过 radius 的部分，并将其沿传播方向的位置
    % 转换为有符号位移区间。radius 不会扩大该区间的前后边界。
    dInterval = segmentCrossTrackInterval(q, u, a, b, radius);
    if any(~isfinite(dInterval))
        continue;
    end
    allDIntervals(end+1, :) = dInterval; %#ok<AGROW>

    % 逐线段方向分类继续用于构造原有速度包络，但它不能单独决定
    % isPass。最终还必须通过整条折线横向最近点的方向硬筛选。
    directionStatus = classifyDisplacementInterval(dInterval, timeDirection);
    if directionStatus == 0
        ambiguousSegments(end+1, 1) = i; %#ok<AGROW>
        continue;
    elseif directionStatus < 0
        continue;
    end
    directionalDIntervals(end+1, :) = dInterval; %#ok<AGROW>

    % rawIntervals 保留未限速诊断；limitedIntervals 是进入匹配的实际区间。
    rawIntervals = speedIntervalsFor(dInterval, [dtLo, dtHi], [0, inf]);
    limitedIntervals = speedIntervalsFor(dInterval, [dtLo, dtHi], ...
        [0, maxPropagationSpeedMps]);
    boundedIntervals = speedIntervalsFor(dInterval, [dtLo, dtHi], cBound);
    rawSpeedIntervals = [rawSpeedIntervals; rawIntervals]; %#ok<AGROW>
    limitedSpeedIntervals = [limitedSpeedIntervals; limitedIntervals]; %#ok<AGROW>
    feasibleSpeedIntervals = [feasibleSpeedIntervals; boundedIntervals]; %#ok<AGROW>
    if ~isempty(rawIntervals)
        hitSegments(end+1, 1) = i; %#ok<AGROW>
    end
end

%% 9. 合并各线段产生的重叠区间，形成统一诊断结果
details.displacementIntervalsMeters = mergeIntervals(allDIntervals);
details.directionalDisplacementIntervalsMeters = mergeIntervals(directionalDIntervals);
details.rawSpeedIntervals = mergeIntervals(rawSpeedIntervals);
details.limitedSpeedIntervals = mergeIntervals(limitedSpeedIntervals);
details.speedIntervals = mergeIntervals(feasibleSpeedIntervals);
details.hitSegments = unique(hitSegments, 'stable');
details.ambiguousSegments = unique(ambiguousSegments, 'stable');
details.closestCrossTrackMeters = closestCrossTrackMeters;
details.closestSignedCrossTrackMeters = closestSignedCrossTrackMeters;
details.closestAlongDisplacementMeters = closestAlongDisplacementMeters;
details.closestSegment = closestSegment;
details.closestSegmentParameter = closestSegmentParameter;
details.closestDirectionStatus = classifySignedDisplacement( ...
    closestAlongDisplacementMeters, timeDirection);

%% 10. isPass 判定
% 几何上完全无法进入 radius 时，无条件拒绝。
if isempty(allDIntervals)
    details.reason = "cross_track_outside_radius";
    return;
end

% 时间窗跨越遥感时刻时，无法为整段时间指定唯一的传播前后方向。
if timeDirection == 0
    details.reason = "time_window_crosses_sensing_time";
    return;
end

% 横向最近点落在波峰当前所在位置时，无法确定传播前后关系。
if details.closestDirectionStatus == 0
    details.reason = "closest_point_direction_ambiguous";
    return;
end

% 最近点的沿传播位移必须与系泊时间差同号。该判断是候选权值能否从
% Inf 变为有限值的唯一方向硬条件。
if details.closestDirectionStatus < 0
    details.reason = "closest_point_time_direction_mismatch";
    return;
end

% 最近点方向一致后，还必须存在不超过 5 m/s 的正速度。
if isempty(limitedSpeedIntervals)
    if isempty(rawSpeedIntervals)
        details.reason = "no_positive_speed_interval";
    else
        details.reason = "speed_above_5_mps";
    end
    return;
end

% 保留原始区间检查，防御退化输入。
if isempty(rawSpeedIntervals)
    details.reason = "no_positive_speed_interval";
    return;
end
% 模态速度交集只保留为诊断，不在此处拒绝；后续匈牙利匹配负责限速。
% if isempty(feasibleSpeedIntervals)
%     details.reason = "speed_outside_mode_bounds";
%     return;
% end

isPass = true;
propSpeed = [min(details.limitedSpeedIntervals(:,1)), ...
             max(details.limitedSpeedIntervals(:,2))];
details.reason = "pass";
end

function details = defaultDetails()
%DEFAULTDETAILS 构造固定字段的诊断结构，确保所有提前返回路径接口一致。
details = struct( ...
    'reason', "not_evaluated", ...
    'initialDirDeg', NaN, ...
    'dirDeg', NaN, ...
    'directionFlipRequired', false, ...
    'directionFlipAccepted', NaN, ...
    'directionFlipStats', struct(), ...
    'speedBounds', [NaN NaN], ...
    'maxPropagationSpeedMps', 5, ...
    'searchToleranceSeconds', NaN, ...
    'timeRangeSeconds', [NaN NaN], ...
    'timeDirection', NaN, ...
    'physicalDisplacementRangeMeters', [NaN NaN], ...
    'displacementIntervalsMeters', zeros(0,2), ...
    'directionalDisplacementIntervalsMeters', zeros(0,2), ...
    'rawSpeedIntervals', zeros(0,2), ...
    'limitedSpeedIntervals', zeros(0,2), ...
    'speedIntervals', zeros(0,2), ...
    'hitSegments', zeros(0,1), ...
    'ambiguousSegments', zeros(0,1), ...
    'closestCrossTrackMeters', inf, ...
    'closestSignedCrossTrackMeters', NaN, ...
    'closestAlongDisplacementMeters', NaN, ...
    'closestSegment', NaN, ...
    'closestSegmentParameter', NaN, ...
    'closestDirectionStatus', NaN);
end

function direction = classifyTimeDirection(dtLo, dtHi)
%CLASSIFYTIMEDIRECTION 判断系泊时间窗位于遥感时刻之前还是之后。
%   +1 表示未来时间窗，-1 表示历史时间窗，0 表示时间窗跨零或退化为零。
if dtLo >= 0 && dtHi > 0
    direction = 1;
elseif dtLo < 0 && dtHi <= 0
    direction = -1;
else
    direction = 0;
end
end

function status = classifyDisplacementInterval(dInterval, timeDirection)
%CLASSIFYDISPLACEMENTINTERVAL 严格检查位移区间是否位于正确时间方向一侧。
%   +1 表示整段方向正确，-1 表示整段方向相反，0 表示跨越零位移。
scale = max([1, abs(dInterval)]);
tol = 1e-12 * scale;
dLo = dInterval(1);
dHi = dInterval(2);

if timeDirection > 0
    if dLo > tol
        status = 1;
    elseif dHi <= tol
        status = -1;
    else
        status = 0;
    end
elseif timeDirection < 0
    if dHi < -tol
        status = 1;
    elseif dLo >= -tol
        status = -1;
    else
        status = 0;
    end
else
    status = 0;
end
end

function status = classifySignedDisplacement(d, timeDirection)
%CLASSIFYSIGNEDDISPLACEMENT 判断单点位移与时间方向是否一致。
%   +1 表示同号，-1 表示反号，0 表示时间跨零或位移接近零。
tol = 1e-12 * max(1, abs(d));
if timeDirection == 0 || ~isfinite(d) || abs(d) <= tol
    status = 0;
elseif sign(d) == timeDirection
    status = 1;
else
    status = -1;
end
end

function intervals = speedIntervalsFor(dInterval, tInterval, speedCap)
%SPEEDINTERVALSFOR 将传播距离区间和时间区间转换为正速度区间。
%
% 根据 c=d/dt：未来分支要求 d>0、dt>0；历史分支要求 d<0、dt<0。
% 两种情况下 c 均为正。最后与 speedCap 求交，并合并重叠结果。
dLo = dInterval(1);
dHi = dInterval(2);
tLo = tInterval(1);
tHi = tInterval(2);
tol = 1e-12;
intervals = zeros(0, 2);

% 通用退化情况：时间区间和位移区间同时包含 0 时，speedCap 中任意速度
% 在 t=0 都可行。严格方向筛选后，主流程通常不会进入该分支。
if dLo <= tol && dHi >= -tol && tLo <= tol && tHi >= -tol
    intervals(end+1, :) = speedCap;
end

% 未来分支：d>0 且 dt>0。
if dHi > tol && tHi > tol
    dMagLo = max(dLo, 0);
    dMagHi = dHi;
    tMagLo = max(tLo, 0);
    tMagHi = tHi;
    speedLo = dMagLo / tMagHi;
    if tMagLo <= tol
        speedHi = inf;
    else
        speedHi = dMagHi / tMagLo;
    end
    intervals = appendIntersection(intervals, [speedLo, speedHi], speedCap);
end

% 历史分支：d<0 且 dt<0，二者相除仍得到正速度。
if dLo < -tol && tLo < -tol
    dNegHi = min(dHi, 0);
    tNegHi = min(tHi, 0);
    dMagLo = -dNegHi;
    dMagHi = -dLo;
    tMagLo = -tNegHi;
    tMagHi = -tLo;
    speedLo = dMagLo / tMagHi;
    if tMagLo <= tol
        speedHi = inf;
    else
        speedHi = dMagHi / tMagLo;
    end
    intervals = appendIntersection(intervals, [speedLo, speedHi], speedCap);
end

intervals = mergeIntervals(intervals);
end

function intervals = appendIntersection(intervals, candidate, cap)
%APPENDINTERSECTION 将候选速度区间与允许范围求交后追加到列表。
lo = max(candidate(1), cap(1));
hi = min(candidate(2), cap(2));
if lo <= hi + 1e-12
    intervals(end+1, :) = [max(lo, 0), hi];
end
end

function interval = segmentCrossTrackInterval(q, u, a, b, radius)
%SEGMENTCROSSTRACKINTERVAL 求线段横向走廊对应的有符号传播位移区间。
%
% 令 p(t)=a+t*(b-a), 0<=t<=1。传播方向的单位法向量为 n，则
%   cross(t) = dot(q-p(t), n)
%   d(t)     = dot(q-p(t), u)
% cross(t) 和 d(t) 都是 t 的线性函数。先解析裁剪出满足
% abs(cross(t))<=radius 的 t 区间，再将其两个端点映射为 d 区间。
n = [-u(2); u(1)];
crossA = dot(q-a, n);
crossB = dot(q-b, n);
deltaCross = crossB - crossA;
scale = max([1, radius, abs(crossA), abs(crossB)]);
crossTol = 1e-12 * scale;
tTol = 1e-12;

if abs(deltaCross) <= crossTol
    if abs(crossA) > radius + crossTol
        interval = [NaN NaN];
        return;
    end
    tRange = [0, 1];
else
    roots = sort([(-radius-crossA)/deltaCross, ...
                   ( radius-crossA)/deltaCross]);
    tRange = [max(0, roots(1)), min(1, roots(2))];
    if tRange(1) > tRange(2) + tTol
        interval = [NaN NaN];
        return;
    end
    tRange = max(0, min(1, tRange));
end

alongA = dot(q-a, u);
alongB = dot(q-b, u);
deltaAlong = alongB - alongA;
dAtRange = alongA + tRange * deltaAlong;
interval = [min(dAtRange), max(dAtRange)];
end

function [absCross, signedCross, along, t] = closestCrossTrackPoint(q, u, a, b)
%CLOSESTCROSSTRACKPOINT 求有限线段上横向距离系泊点最近的连续点。
%
% 横向坐标 cross(t) 在线段参数 t 上为线性函数。若线段与传播方向平行，
% 整段横向距离相同，则在这些并列点中选择 |d| 最小者。
n = [-u(2); u(1)];
crossA = dot(q-a, n);
crossB = dot(q-b, n);
deltaCross = crossB - crossA;
alongA = dot(q-a, u);
alongB = dot(q-b, u);
deltaAlong = alongB - alongA;
crossTol = 1e-12 * max([1, abs(crossA), abs(crossB)]);

if abs(deltaCross) > crossTol
    t = max(0, min(1, -crossA/deltaCross));
elseif abs(deltaAlong) > 1e-12 * max([1, abs(alongA), abs(alongB)])
    t = max(0, min(1, -alongA/deltaAlong));
else
    t = 0;
end

signedCross = crossA + t*deltaCross;
along = alongA + t*deltaAlong;
absCross = abs(signedCross);
end

function better = isBetterClosestPoint(crossDistance, along, bestCross, bestAlong)
%ISBETTERCLOSESTPOINT 先比较横向距离，并以 |d| 作为并列判据。
if ~isfinite(bestCross)
    better = true;
    return;
end

crossTol = 1e-9 * max([1, crossDistance, bestCross]);
if crossDistance < bestCross-crossTol
    better = true;
elseif abs(crossDistance-bestCross) <= crossTol
    alongTol = 1e-9 * max([1, abs(along), abs(bestAlong)]);
    better = abs(along) < abs(bestAlong)-alongTol;
else
    better = false;
end
end

function distance = pointToSweptSegmentDistance(q, a, b, u, dLo, dHi)
% POINTTOSWEPTSEGMENTDISTANCE 点到有限位移扫掠区域的最短距离。
%
% 线段 AB 在 [dLo,dHi] 内平移后扫出一个平行四边形（退化时可能为
% 线段）。若 q 位于内部，距离为 0；否则取 q 到四条边的最短距离。
aLo = a + dLo*u;
bLo = b + dLo*u;
bHi = b + dHi*u;
aHi = a + dHi*u;
polygon = [aLo, bLo, bHi, aHi];

[inside, onBoundary] = inpolygon(q(1), q(2), polygon(1,:), polygon(2,:));
if inside || onBoundary
    distance = 0;
    return;
end

distance = inf;
for k = 1:4
    next = mod(k, 4) + 1;
    distance = min(distance, ...
        pointToSegmentDistance(q, polygon(:,k), polygon(:,next)));
end
end

function distance = pointToSegmentDistance(p, a, b)
%POINTTOSEGMENTDISTANCE 计算二维点 p 到有限线段 AB 的欧氏距离。
ab = b - a;
denom = dot(ab, ab);
if denom <= eps
    distance = norm(p-a);
    return;
end
t = dot(p-a, ab) / denom;
t = max(0, min(1, t));
closest = a + t*ab;
distance = norm(p-closest);
end

function merged = mergeIntervals(intervals)
%MERGEINTERVALS 合并相交或相邻区间，输入和输出均为 N-by-2。
if isempty(intervals)
    merged = zeros(0, 2);
    return;
end
intervals = intervals(all(isfinite(intervals) | isinf(intervals), 2), :);
if isempty(intervals)
    merged = zeros(0, 2);
    return;
end
intervals = sortrows(intervals, 1);
merged = intervals(1, :);
for k = 2:size(intervals, 1)
    if intervals(k,1) <= merged(end,2) + 1e-12
        merged(end,2) = max(merged(end,2), intervals(k,2));
    else
        merged(end+1, :) = intervals(k, :); %#ok<AGROW>
    end
end
end

function [x, y] = ll2local(lat, lon, lat0, lon0)
%LL2LOCAL 小范围等距矩形近似：经纬度（度）转换为局部东、北坐标（米）。
% 该近似适用于南海区域尺度的局部几何运算，不用于大圆航线计算。
x = (lon-lon0) .* cosd(lat0) * 111320;
y = (lat-lat0) * 110540;
end
