function [isPass, propSpeed, crest_min_dis] = isCrestPassMooring_bin_dir(crestLat, crestLon, ...
    crestTime, crestType, moorLat, moorLon, moorStTime, moorEdTime, teps, tlim, radius)
% 通过二分法计算波峰线与系泊点最近距离并判断是否通过系泊点, 并限制波峰线的传播方向
% 输入参数
% crestLat, crestLon: 初始经纬度（度）
% crestTime, crestType: 波峰线时间，波峰线类型
% speed: 速度（m/s）
% moorLat, moorLon: 系泊点经纬度（度）
% moorStTime, moorEdTime: 系泊点观测到内波的起止时间（datetime）
% teps: 最小时间误差（s）
% tlim: 模拟时间范围（s）
% radius: 半径（m）不小于 c*teps

% 返回值
% isPass: 是否通过
% propSpeed: 最佳的通过速度
% crest_min_dis: 离系泊点的最小距离

% Compute the overall crest direction
dirDeg = mod(90 - calcDirection(crestLat, crestLon), 360);

if dirDeg > 45 & dirDeg < 180
    [dirDegOut, doFlip, ~] = maybeFlipCrestDir(crestLat, crestLon, moorLat, moorLon);
    if doFlip
        dirDeg = dirDegOut;
    end
end

% 针对不同内波设置速度
if crestType == 1
    c_bound = [1, 3];
else
    c_bound = [0.3, 1.4];
end

% 不考虑传播方向问题
% if crestTime < moorStTime
%     trans_dir = 1;
% elseif crestTime > moorEdTime
%     trans_dir = -1;
% else
%     isPass = true;
%     propSpeed = moorSpeed;
%     passTime = crestTime;
%     return;
% end
propSpeed = [];
crest_min_dis = inf;

% % 如果波峰线在系泊点东方向，且sensing time 比系泊点观测时间晚，
% % 则只能与sensing time 之后的系泊点观测事件匹配
% if (max(crestLon) > moorLon && (crestTime > moorEdTime)) | (max(crestLon) < moorLon && max(crestLat) > moorLat && (crestTime < moorStTime))
%     % | (max(crestLon) < moorLon && min(crestLat) < moorLat && (crestTime > moorEdTime))
%     isPass = false;
%     propSpeed = NaN;
%     crest_min_dis = NaN;
%     return;
% end

% 统计有多少个点位于系泊点的西侧 (经度 < 系泊经度)
count_west = sum(crestLon < moorLon);
total_pts = numel(crestLon);

% 如果超过 50% 的点在西侧，则判定整条线“在西边” (Downstream)
% 否则判定“在东边” (Upstream)
is_at_west = (count_west / total_pts) > 0.5;

% 逻辑剔除 (假设内波向西传播)：
% 1. 如果判定在西 (已经跑过头了)，但时间比观测开始还早 -> 说明观测开始前波就走了，没戏。
% 2. 如果判定在东 (还在还没到)，但时间比观测结束还晚 -> 说明观测结束了波还没来，没戏。
if (is_at_west && crestTime < moorStTime) || (~is_at_west && crestTime > moorEdTime)
    isPass = false;
    propSpeed = NaN;
    crest_min_dis = NaN;
    return;
end

% Loop over every point on the crest line
for i = 1:length(crestLat)-2
    lat0 = crestLat(i);
    lon0 = crestLon(i);
    lon1 = crestLon(i+1);
    lat1 = crestLat(i+1);

    % 按最低速度传播 判断能否传播到系泊点附近
    c = c_bound(1);
    % Propagate from this crest point with 10-minute time steps up to two days
    min_dis = inf;
    t_lr = -tlim; t_ur = tlim;

    % 二分法判断是否能传播到系泊点附近，并计算传播到系泊点附近的时间
    while abs(crestTime + t_lr - moorStTime) > seconds(teps)

        if abs(t_ur - t_lr) < teps
            break;
        end
        t_lmid = t_lr + (t_ur - t_lr)/3;
        t_rmid = t_ur - (t_ur - t_lr)/3;
        [latP_lmid, lonP_lmid] = calcPropagation([lat0, lat1], [lon0, lon1], dirDeg, t_lmid, c);
        [latP_rmid, lonP_rmid] = calcPropagation([lat0, lat1], [lon0, lon1], dirDeg, t_rmid, c);
        d_lmid = calcDisLinePoint(latP_lmid, lonP_lmid, moorLat, moorLon);
        d_rmid = calcDisLinePoint(latP_rmid, lonP_rmid, moorLat, moorLon);
        % Convert distance from degrees to meters
        distMeter_lmid = deg2km(d_lmid) * 1000;
        distMeter_rmid = deg2km(d_rmid) * 1000;
        min_dis = min([distMeter_lmid; distMeter_rmid; min_dis]);
        if distMeter_rmid <= distMeter_lmid
            t_lr = t_lmid;
        else
            t_ur = t_rmid;
        end
    end

    % 如果无法传播到系泊点附近
    if min_dis > radius
        continue;
    end
    crest_min_dis = min([crest_min_dis, min_dis], [], 'all');
    
    % 通过 传播距离 和 通过系泊点的时间 反算传播速度
    % arr_time = crestTime + second(t_lmid);
    prop_dis = t_lmid * c;
    prop_time_bound = [seconds(moorEdTime - crestTime), ...
        seconds(moorStTime - crestTime)];
    propSpeed = prop_dis ./ prop_time_bound;
end

% If at least one crest point passed the mooring, set flag and return the earliest time
if ~isempty(propSpeed) 
    isPass = true;
else
    isPass = false;
    propSpeed = NaN;
end
