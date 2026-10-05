function result = resolveCrestDirection(crestLat, crestLon, moorLat, moorLon)
%RESOLVECRESTDIRECTION 统一解析一条波锋的最终传播方向。
%
% 输入：
%   crestLat, crestLon  波锋折线经纬度（度），允许包含 NaN。
%   moorLat, moorLon    系泊点经纬度（度）。
%
% 输出 result：
%   isValid             是否允许该波锋进入候选匹配。
%   initialDirDeg       calcDirection 给出的初始导航角。
%   dirDeg              完成必要翻转后的最终导航角。
%   flipRequired        初始方向是否位于 30°–180° 翻转区间。
%   doFlip              maybeFlipCrestDir 是否允许翻转。
%   flipStats           maybeFlipCrestDir 的几何诊断。
%   reason              pass、invalid_crest 或
%                       direction_flip_required_but_rejected。
%
% 传播方向属于波锋自身属性，应在读取每条波锋时只解析一次。匹配、
% 保存和可视化必须使用 result.dirDeg，不能各自复制阈值和翻转逻辑。

result = struct( ...
    'isValid', false, ...
    'initialDirDeg', NaN, ...
    'dirDeg', NaN, ...
    'flipRequired', false, ...
    'doFlip', NaN, ...
    'flipStats', struct(), ...
    'reason', "invalid_crest");

good = isfinite(crestLat) & isfinite(crestLon);
lat = crestLat(good);
lon = crestLon(good);
lat = lat(:);
lon = lon(:);
if numel(lat) < 2
    return;
end

initialDirDeg = mod(90-calcDirection(lat, lon), 360);
result.initialDirDeg = initialDirDeg;
result.dirDeg = initialDirDeg;

if initialDirDeg > 0 && initialDirDeg < 180
    result.flipRequired = true;
    [dirDegOut, doFlip, flipStats] = ...
        maybeFlipCrestDir(lat, lon, moorLat, moorLon);
    result.doFlip = doFlip;
    result.flipStats = flipStats;
    if ~doFlip
        result.reason = "direction_flip_required_but_rejected";
        return;
    end
    result.dirDeg = dirDegOut;
end

result.isValid = true;
result.reason = "pass";
end
