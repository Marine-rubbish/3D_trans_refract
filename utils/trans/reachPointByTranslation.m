% filepath: c:\Users\10335\Documents\code\research\SCS_IW_RS\3D_trans\utils\trans\reachPointByTranslation.m
function [isPass, passTime, signedPos, dPass, tRange, propLat, propLon] = reachPointByTranslation( ...
    crestLat, crestLon, crestTime, moorLat, moorLon, cBound, radius)
% 判断：折线沿 dirDeg(正北顺时针) 前向平移，是否能在半径 radius(m) 内经过系泊点
% 返回：
%   isPass    : 是否可达
%   passTime  : 最早通过时间（取 vmax=cBound(2)）
%   signedPos : 通过点在折线弧长上的位置分数[-1,1]（SW端=-1, NE端=+1）
%   dPass     : 最早可达所需平移距离(m)
%   tRange    : 该 dPass 对应的可行时间范围 [d/vmax, d/vmin] (s)
%   intersectLat : 传播后波峰线与系泊点交点的纬度
%   intersectLon : 传播后波峰线与系泊点交点的经度

% --- 初始化输出变量 ---
isPass = false;
passTime = NaT;
signedPos = NaN;
dPass = NaN;
tRange = [NaN NaN];
propLat = NaN;
propLon = NaN;

% --- defaults / checks ---
if nargin < 7 || isempty(radius), radius = 0; end
if nargin < 6 || numel(cBound) ~= 2
    error('cBound must be [vmin vmax].');
end
vmin = cBound(1); vmax = cBound(2);
if ~(vmin > 0 && vmax >= vmin)
    error('Invalid cBound: require 0 < vmin <= vmax.');
end

dirDeg = mod(90 - calcDirection(crestLat, crestLon), 360);
m = ~isnan(crestLat) & ~isnan(crestLon);
lat = crestLat(m); lon = crestLon(m);
if numel(lat) < 2
    isPass = false; passTime = NaT; signedPos = NaN; dPass = NaN; tRange = [NaN NaN]; intersectLat = NaN; intersectLon = NaN;
    return;
end

% % 如果已经经过系泊点 就不用在考虑了
% if min(crestLon) < moorLon | min(crestLat) < moorLat
%     isPass = false; passTime = NaT; signedPos = NaN; dPass = NaN; tRange = [NaN NaN]; intersectLat = NaN; intersectLon = NaN;
%     return;
% end

% --- local projection (meters) ---
lat0 = mean(lat); lon0 = mean(lon);
[x, y]   = ll2local(lat, lon, lat0, lon0);
[qx, qy] = ll2local(moorLat, moorLon, lat0, lon0);

% --- enforce SW(-1) -> NE(+1) orientation using endpoints ---
score1 = x(1) + y(1);
scoreN = x(end) + y(end);
if score1 > scoreN
    x = flipud(x(:)); y = flipud(y(:));
else
    x = x(:); y = y(:);
end

% --- arc length bookkeeping ---
segLen = hypot(diff(x), diff(y));
cumLen = [0; cumsum(segLen)];
L = cumLen(end);
if L <= 0
    isPass = false; passTime = NaT; signedPos = NaN; dPass = NaN; tRange = [NaN NaN]; intersectLat = NaN; intersectLon = NaN;
    return;
end

% --- propagation direction unit vector u (East, North) ---
uE = sind(dirDeg);
uN = cosd(dirDeg);
uu = hypot(uE, uN);
if uu == 0
    isPass = false; passTime = NaT; signedPos = NaN; dPass = NaN; tRange = [NaN NaN]; intersectLat = NaN; intersectLon = NaN;
    return;
end
uE = uE / uu; uN = uN / uu;

% u = [uE; uN]，先归一化
u = [uE; uN];
u = u / norm(u);

% 与 u 垂直的单位向量（左法向）
v = [-u(2); u(1)];

% 所有点相对系泊点的横向投影
P = [x(:)'; y(:)'];          % 2xN
Q = [qx; qy];                % 2x1
t = abs(v' * (P - Q));       % 1xN

minCrossTrack = min(t, [], 'omitnan');
if minCrossTrack > radius
    % 这条波峰线沿 u 平移永远不可能进入半径
end

% --- earliest hit: ray from mooring backward along u intersects polyline-capsule ---
dBest = inf;
localX = zeros(size(x));
localY = zeros(size(y));
for i = 1:numel(x)-1
    a = [x(i);   y(i)];
    b = [x(i+1); y(i+1)];
    sHit = earliestHitRayCapsule([qx; qy], [uE; uN], a, b, radius);
    if sHit < dBest
        dBest = sHit;
    end
end

if ~isfinite(dBest)
    isPass = false; passTime = NaT; signedPos = NaN; dPass = NaN; tRange = [NaN NaN]; intersectLat = NaN; intersectLon = NaN;
    return;
end

% --- compute position on polyline at pass (closest point on original polyline to q - d*u) ---
px = qx - dBest*uE;
py = qy - dBest*uN;
[~, s01] = pointToPolylineMinDistWithPos(px, py, x, y, cumLen); % s01 in [0,1]
signedPos = 2*s01 - 1;

% --- time: choose earliest feasible (use vmax) ---
dPass = dBest;
tEarliest = dPass / vmax;      % seconds
tLatest   = dPass / vmin;      % seconds
tRange = [tEarliest, tLatest];
passTime = crestTime + seconds(tEarliest);

isPass = true;
% 在最后赋值时覆盖
if isPass
    % --- compute propagated crest line coordinates ---
    xProp = x + dBest * uE;
    yProp = y + dBest * uN;
    % --- convert local coordinates back to Lat/Lon ---
    [propLat, propLon] = local2ll(xProp, yProp, lat0, lon0);
end
end

% ================= helpers =================

function [x, y] = ll2local(lat, lon, lat0, lon0)
% small-area equirectangular projection (meters)
x = (lon - lon0) .* cosd(lat0) * 111320; % East
y = (lat - lat0) * 110540;              % North
end

function [lat, lon] = local2ll(x, y, lat0, lon0)
lon = lon0 + x / (cosd(lat0) * 111320);
lat = lat0 + y / 110540;
end

function sHit = earliestHitRayCapsule(q, u, a, b, r)
% Ray: p(s) = q - s*u, s>=0
% Capsule: points within distance r of segment AB.
% Return earliest s>=0 with dist(p(s), segment)<=r; inf if none.
% q 为系泊点，u 为传播方向的单位向量，a为x，b为y，r为半径

% quick accept: already within capsule
if pointToSegmentDist(q(1), q(2), a(1), a(2), b(1), b(2)) <= r
    sHit = 0;
    return;
end

v = b - a;
len = hypot(v(1), v(2));
epsLen = 1e-12;

cands = [];

% endpoint circles
cands = [cands; rayCircleFirstHit(q, u, a, r)];
cands = [cands; rayCircleFirstHit(q, u, b, r)];

% side strip (if segment non-degenerate)
if len > epsLen
    tdir = v / len;
    n = [-tdir(2); tdir(1)];              % unit normal to segment line
    denom = dot(n, u);                    % n·u
    if abs(denom) > 1e-12
        w = q - a;
        % Solve n·(q - s*u - a) = +r  and  = -r
        s1 = (dot(n, w) - r) / denom;
        s2 = (dot(n, w) + r) / denom;
        cands = [cands; s1; s2];
    end
end

% filter candidates: s>=0 and actually inside capsule (with tiny tol)
tol = 1e-9;
best = inf;
for k = 1:numel(cands)
    s = cands(k);
    if ~isfinite(s) || s < 0
        continue;
    end
    p = q - s*u;
    d = pointToSegmentDist(p(1), p(2), a(1), a(2), b(1), b(2));
    if d <= r + tol
        best = min(best, s);
    end
end

sHit = best;
end

function s = rayCircleFirstHit(q, u, c, r)
% earliest s>=0 s.t. ||q - s*u - c|| = r ; return inf if no hit
w = q - c;
b = dot(u, w);                 % u·w
c0 = dot(w, w) - r*r;
disc = b*b - c0;               % since a=1 in s^2 -2b s + c0 = 0
if disc < 0
    s = inf;
    return;
end
sd = sqrt(disc);
s1 = b - sd;
s2 = b + sd;
% need s>=0, pick smallest nonnegative
s = inf;
if s1 >= 0, s = min(s, s1); end
if s2 >= 0, s = min(s, s2); end
end

function [dmin, s01] = pointToPolylineMinDistWithPos(px, py, x, y, cumLen)
% min distance from point to polyline + arclength position s01 in [0,1]
dmin = inf;
s01 = NaN;
L = cumLen(end);
for i = 1:numel(x)-1
    [d, t] = pointToSegmentDistWithT(px, py, x(i), y(i), x(i+1), y(i+1));
    if d < dmin
        dmin = d;
        si = cumLen(i) + t * (cumLen(i+1) - cumLen(i));
        s01 = si / max(L, eps);
    end
end
end

function d = pointToSegmentDist(px, py, x0, y0, x1, y1)
[d, ~] = pointToSegmentDistWithT(px, py, x0, y0, x1, y1);
end

function [d, t] = pointToSegmentDistWithT(px, py, x0, y0, x1, y1)
vx = x1 - x0; vy = y1 - y0;
wx = px - x0; wy = py - y0;
vv = vx*vx + vy*vy;
if vv <= 0
    t = 0;
    d = hypot(px - x0, py - y0);
    return;
end
t = (wx*vx + wy*vy) / vv;
t = max(0, min(1, t));
cx = x0 + t*vx; cy = y0 + t*vy;
d = hypot(px - cx, py - cy);
end
