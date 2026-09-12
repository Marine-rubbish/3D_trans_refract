function [dirDegOut, doFlip, stats] = maybeFlipCrestDir(crestLat, crestLon, moorLat, moorLon)
% 仅对“近似直线”的波峰线，若传播方向背离系泊点，则翻转180度
% dirDegIn/Out: 正北顺时针角度(0~360)

% 1) 清理 NaN
dirDegIn = mod(90 - calcDirection(crestLat, crestLon), 360);
m = ~isnan(crestLat) & ~isnan(crestLon);
lat = crestLat(m); lon = crestLon(m);
if numel(lat) < 3
    dirDegOut = dirDegIn; doFlip = false;
    stats = struct('medianTurnDeg',NaN,'maxTurnDeg',NaN,'isStraight',false,'bearingToMoor',NaN,'angDiff',NaN);
    return;
end

% 2) 用局部投影到平面（足够小区域时可用）
lat0 = mean(lat); lon0 = mean(lon);
x = (lon - lon0) .* cosd(lat0) * 111320; % m
y = (lat - lat0) * 110540;              % m

% 3) 计算每段航向角（北顺时针）
dx = diff(x); dy = diff(y);
segOk = hypot(dx,dy) > 0;
dx = dx(segOk); dy = dy(segOk);
if numel(dx) < 2
    dirDegOut = dirDegIn; doFlip = false;
    stats = struct('medianTurnDeg',NaN,'maxTurnDeg',NaN,'isStraight',false,'bearingToMoor',NaN,'angDiff',NaN);
    return;
end

segDir = mod(atan2d(dx, dy), 360); % atan2d(East, North) => 北顺时针
dturn = abs(wrapTo180(diff(segDir))); % 相邻段转角（-180~180取绝对值）

medianTurnDeg = median(dturn);
maxTurnDeg = max(dturn);

% 新增：直线度（端点距 / 折线总长），越接近1越直
segLen = hypot(diff(x), diff(y));
totalLen = sum(segLen);
end2end = hypot(x(end) - x(1), y(end) - y(1));
straightness = end2end / max(totalLen, eps);

% 用分位数代替 max，避免被单个拐点“误伤”
p80TurnDeg = prctile(dturn, 80);

% 推荐阈值（可按数据再调）
medianThresh = 15;      % 原来10，放宽
p90Thresh    = 35;      % 90%拐点都要比较小
straightThresh = 0.92;  % 端点距占总长>0.92认为整体直

isStraight = (straightness > straightThresh) && ...
             (medianTurnDeg < medianThresh) && ...
             (p80TurnDeg < p90Thresh);

% 4) 仅对直线型：判断是否背离系泊点
% 用波峰线“中点”到系泊点的方位角做参考（也可以换成最近点）
midIdx = round(numel(lat)/2);
bearingToMoor = azimuth(lat(midIdx), lon(midIdx), moorLat, moorLon); % Mapping Toolbox: 北顺时针
bearingToMoor = mod(bearingToMoor, 360);

angDiff = abs(wrapTo180(dirDegIn - bearingToMoor)); % 与系泊点方向的夹角

% doFlip = isStraight && (angDiff > 90);

doFlip = isStraight;

dirDegOut = dirDegIn;
if doFlip
    dirDegOut = mod(dirDegIn + 180, 360);
end

stats = struct('medianTurnDeg',medianTurnDeg,'maxTurnDeg',maxTurnDeg,'p80TurnDeg',p80TurnDeg, ...
               'straightness',straightness,'isStraight',isStraight, ...
               'bearingToMoor',bearingToMoor,'angDiff',angDiff);
end
