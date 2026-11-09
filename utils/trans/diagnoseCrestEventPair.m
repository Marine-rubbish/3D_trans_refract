function diagnostic = diagnoseCrestEventPair( ...
    crestLat, crestLon, crestTime, crestType, ...
    moorLat, moorLon, moorStTime, moorEdTime, config)
%DIAGNOSECRESTEVENTPAIR 计算一条波锋与一个系泊事件的点击诊断。
%
% 几何最近点只表示折线到系泊点的直线最短距离。传播最近点和速度
% 完全复用 isCrestPassMooring_capsule_dir 的方向、位移和时间逻辑。

if nargin < 9 || isempty(config)
    config = struct();
end
config = applyDiagnosticDefaults(config);
diagnostic = defaultDiagnostic();

[geometryLat, geometryLon, geometryDistance] = ...
    geometricClosestPoint(crestLat, crestLon, moorLat, moorLon);
diagnostic.geometricPointLat = geometryLat;
diagnostic.geometricPointLon = geometryLon;
diagnostic.geometricDistanceMeters = geometryDistance;

[isPass, ~, sweptDistance, details] = ...
    isCrestPassMooring_capsule_dir( ...
    crestLat, crestLon, crestTime, crestType, ...
    moorLat, moorLon, moorStTime, moorEdTime, ...
    config.searchToleranceSeconds, config.timeLimitSeconds, ...
    config.radiusMeters, config.directionResolution);

diagnostic.isPass = isPass;
diagnostic.reason = details.reason;
diagnostic.directionDeg = details.dirDeg;
diagnostic.sweptDistanceMeters = sweptDistance;
diagnostic.crossTrackMeters = details.closestCrossTrackMeters;
diagnostic.signedCrossTrackMeters = ...
    details.closestSignedCrossTrackMeters;
diagnostic.alongDisplacementMeters = ...
    details.closestAlongDisplacementMeters;
diagnostic.timeRangeSeconds = details.timeRangeSeconds;
diagnostic.equivalentSpeedIntervalsMps = ...
    details.closestRawSpeedIntervals;
diagnostic.limitedSpeedIntervalsMps = ...
    details.closestLimitedSpeedIntervals;
diagnostic.speedAboveLimit = ...
    ~isempty(details.closestRawSpeedIntervals) && ...
    isempty(details.closestLimitedSpeedIntervals);
diagnostic.details = details;

[propagationLat, propagationLon] = propagationClosestPoint( ...
    crestLat, crestLon, details.closestSegment, ...
    details.closestSegmentParameter);
diagnostic.propagationPointLat = propagationLat;
diagnostic.propagationPointLon = propagationLon;

midTime = moorStTime + (moorEdTime-moorStTime)/2;
dtMid = seconds(midTime-crestTime);
diagnostic.midTimeSeconds = dtMid;
d = diagnostic.alongDisplacementMeters;
if isfinite(d) && isfinite(dtMid) && ...
        abs(d) > 1e-9 && abs(dtMid) > 1e-9 && sign(d) == sign(dtMid)
    diagnostic.equivalentSpeedMidMps = d/dtMid;
end
end

function config = applyDiagnosticDefaults(config)
%APPLYDIAGNOSTICDEFAULTS 统一点击诊断使用的传播参数。
defaults = struct( ...
    'searchToleranceSeconds', 60, ...
    'timeLimitSeconds', 86400*10, ...
    'radiusMeters', 100000, ...
    'directionResolution', []);
unknown = setdiff(fieldnames(config), fieldnames(defaults));
if ~isempty(unknown)
    error('未知诊断配置字段：%s', ...
        strjoin(string(unknown), ', '));
end
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(config, names{i}) || isempty(config.(names{i}))
        config.(names{i}) = defaults.(names{i});
    end
end
end

function diagnostic = defaultDiagnostic()
%DEFAULTDIAGNOSTIC 构造所有分支共有的固定诊断字段。
diagnostic = struct( ...
    'isPass', false, ...
    'reason', "not_evaluated", ...
    'directionDeg', NaN, ...
    'geometricPointLat', NaN, ...
    'geometricPointLon', NaN, ...
    'geometricDistanceMeters', inf, ...
    'propagationPointLat', NaN, ...
    'propagationPointLon', NaN, ...
    'crossTrackMeters', inf, ...
    'signedCrossTrackMeters', NaN, ...
    'alongDisplacementMeters', NaN, ...
    'timeRangeSeconds', [NaN NaN], ...
    'midTimeSeconds', NaN, ...
    'equivalentSpeedIntervalsMps', zeros(0,2), ...
    'limitedSpeedIntervalsMps', zeros(0,2), ...
    'equivalentSpeedMidMps', NaN, ...
    'speedAboveLimit', false, ...
    'sweptDistanceMeters', inf, ...
    'details', struct());
end

function [pointLat, pointLon, distanceMeters] = ...
    geometricClosestPoint(crestLat, crestLon, moorLat, moorLon)
%GEOMETRICCLOSESTPOINT 求有限折线到系泊点的直线最短点。
lat = crestLat(:);
lon = crestLon(:);
good = isfinite(lat) & isfinite(lon);
if nnz(good) < 2
    pointLat = NaN;
    pointLon = NaN;
    distanceMeters = inf;
    return;
end

lat0 = mean(lat(good));
lon0 = mean(lon(good));
[x, y] = ll2local(lat, lon, lat0, lon0);
[qx, qy] = ll2local(moorLat, moorLon, lat0, lon0);
q = [qx; qy];
bestPoint = [NaN; NaN];
distanceMeters = inf;

for i = 1:numel(lat)-1
    if ~good(i) || ~good(i+1)
        continue;
    end
    a = [x(i); y(i)];
    b = [x(i+1); y(i+1)];
    ab = b-a;
    denominator = dot(ab, ab);
    if denominator <= eps
        t = 0;
    else
        t = max(0, min(1, dot(q-a, ab)/denominator));
    end
    point = a+t*ab;
    candidateDistance = norm(q-point);
    if candidateDistance < distanceMeters
        distanceMeters = candidateDistance;
        bestPoint = point;
    end
end

if ~all(isfinite(bestPoint))
    pointLat = NaN;
    pointLon = NaN;
    distanceMeters = inf;
    return;
end
[pointLat, pointLon] = local2ll( ...
    bestPoint(1), bestPoint(2), lat0, lon0);
end

function [pointLat, pointLon] = propagationClosestPoint( ...
    crestLat, crestLon, segment, parameter)
%PROPAGATIONCLOSESTPOINT 用传播函数返回的线段和参数还原经纬度。
good = isfinite(crestLat) & isfinite(crestLon);
lat = crestLat(good);
lon = crestLon(good);
lat = lat(:);
lon = lon(:);
if ~isfinite(segment) || ~isfinite(parameter) || ...
        segment < 1 || segment >= numel(lat)
    pointLat = NaN;
    pointLon = NaN;
    return;
end
segment = round(segment);
parameter = max(0, min(1, parameter));
pointLat = lat(segment) + ...
    parameter*(lat(segment+1)-lat(segment));
pointLon = lon(segment) + ...
    parameter*(lon(segment+1)-lon(segment));
end

function [x, y] = ll2local(lat, lon, lat0, lon0)
%LL2LOCAL 使用与传播函数一致的局部米制近似。
x = (lon-lon0) .* cosd(lat0) * 111320;
y = (lat-lat0) * 110540;
end

function [lat, lon] = local2ll(x, y, lat0, lon0)
%LOCAL2LL 将局部米制坐标还原为经纬度。
lat = lat0 + y/110540;
lon = lon0 + x/(111320*cosd(lat0));
end
