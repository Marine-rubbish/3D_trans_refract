function packets = group_scene_wave_packets(crests, config)
%GROUP_SCENE_WAVE_PACKETS 把同一张影像内几何关系相近的波锋组成候选波包。
%
% 输入 crests 是入口读取的波锋表，config.packet* 是分组参数。
% 本函数只看遥感波锋的几何，不读取系泊事件或其观测方向。
% 同景、方向接近、横向覆盖重叠且保持前后关系的波锋才尝试归为一组。
%
% 输出 packets 与 crests 逐行对应：
%   packet_id：波包编号；0 表示没有确定分组，仍可参加速度匹配。
%   packet_rank：沿传播方向从前到后的序号。1 是图中已提取波锋里
%                最靠前的一条，不证明物理上的头波已经被观测到。
%   observed_packet_size：本组已提取的条数，不是实际波包的完整波数。
%   max_gap_to_previous_m：与同包前一条波锋在重叠区内的最大间距，
%                          单位米；组内第一条为 NaN。
%   packet_status：分组结果或未分组原因，供输出表检查。
%
% 允许缺少中间波；不要求把同一波包的所有波锋补齐。
% 分组阈值是可调整的几何启发式条件，不能解释成真实波包概率。

n = height(crests);
packetId = zeros(n,1); rank = nan(n,1); sizeCol = ones(n,1);
maxGapToPrevious = nan(n,1);
status = repmat("singleton_no_group", n,1);
eligible = false(n,1);
% 有内部断口的多段折线先不归包，避免把不同分支拼成一条完整波锋。
% 末尾常见的 NaN 只是 SHP 终止符，不算内部断口。
for i = 1:n
    lat = crests.latitude{i}(:); lon = crests.longitude{i}(:);
    good = isfinite(lat) & isfinite(lon);
    if ~any(good) || ~isfinite(crests.direction_deg(i))
        status(i) = "invalid_geometry"; continue;
    end
    first = find(good,1); last = find(good,1,'last');
    eligible(i) = all(good(first:last)) && nnz(good) >= 2;
    if ~eligible(i), status(i) = "multipart_unresolved"; end
end
scenes = unique(crests.scene_id, 'stable');
for s = 1:numel(scenes)
    idx = find(crests.scene_id == scenes(s) & eligible);
    m = numel(idx);
    if m < 2, continue; end
    precedes = false(m,m);
    separation = inf(m,m);
    % precedes(a,b)=true 表示 a 在传播方向上领先 b。
    % separation 保存两条波锋重叠部分的最大沿程间距，单位米。
    for a = 1:m
        for b = a+1:m
            [order, gap] = compareFronts(crests(idx(a),:), crests(idx(b),:), config);
            if order == 0, continue; end
            separation(a,b) = gap; separation(b,a) = gap;
            precedes(a,b) = order > 0;
            precedes(b,a) = order < 0;
        end
    end
    [aa,bb] = find(triu(separation <= config.packetMaxNeighborGapMeters,1));
    gaps = separation(sub2ind([m,m],aa,bb));
    % 从距离近的波锋对开始合组；不是把整张图上所有线都当同一波包。
    edges = sortrows([gaps,aa,bb], [1,2,3]);
    labels = (1:m)';
    for e = 1:size(edges,1)
        la = labels(edges(e,2)); lb = labels(edges(e,3));
        if la == lb, continue; end
        members = find(labels == la | labels == lb);
        pairMask = triu(true(numel(members),numel(members)),1);
        sep = separation(members,members);
        % 合组前检查组内每一对，防止 A 接近 B、B 接近 C 就把互相
        % 交叉或远离的 A、C 也合在一起。组的总跨度受单独参数限制。
        if any(sep(pairMask) > config.packetMaxSpanMeters), continue; end
        before = precedes(members,members);
        incoming = sum(before,1);
        % 每条波锋前面有几条波锋？合法的完整顺序必须恰好为 0,...,m-1。
        % 若出现 A 在 B 前、B 在 C 前、C 又在 A 前，则拒绝这次合组。
        if ~isequal(sort(incoming), 0:numel(members)-1), continue; end
        labels(members) = min(la,lb);
    end
    for label = unique(labels)'
        members = find(labels == label);
        if numel(members) < 2, continue; end
        globalRows = idx(members);
        % 用组内最小原始波锋编号作波包 ID，保证重复运行时编号稳定。
        packetId(globalRows) = min(crests.crest_idx(globalRows));
        localRank = sum(precedes(members,members),1)' + 1;
        rank(globalRows) = localRank;
        sizeCol(globalRows) = numel(members);
        status(globalRows) = "geometric_packet_candidate";

        % 保存相邻波锋的实际分组间距，便于在图上直接检查阈值是否合理。
        [~, order] = sort(localRank);
        for k = 2:numel(order)
            previousLocal = members(order(k-1));
            currentLocal = members(order(k));
            currentGlobal = globalRows(order(k));
            maxGapToPrevious(currentGlobal) = ...
                separation(previousLocal, currentLocal);
        end
    end
end
packets = table(crests.crest_idx, crests.scene_id, packetId, rank, sizeCol, ...
    maxGapToPrevious, status, ...
    'VariableNames', {'crest_idx','scene_id','packet_id','packet_rank', ...
    'observed_packet_size','max_gap_to_previous_m','packet_status'});
end

function [order, gap] = compareFronts(a,b,config)
%COMPARE FRONTS 比较两条同景波锋，返回前后方向和最大沿程间距。
% order=1：a 领先 b；-1：b 领先 a；0：当前几何不足以建立顺序。
% 这里只比较两条遥感线的方向，以避免把相反传播分支归为一组。
order = 0; gap = inf;
da = a.direction_deg; db = b.direction_deg;
if abs(mod(da-db+180,360)-180) > config.packetDirectionToleranceDeg
    return;
end
dir = atan2d(sind(da)+sind(db), cosd(da)+cosd(db));
% 在共同传播方向上投影，两条线只比较共有的横向覆盖区间。
[va,ua] = profile(a,dir,config);
[vb,ub] = profile(b,dir,config);
if isempty(va) || isempty(vb), return; end
lo = max(va(1),vb(1)); hi = min(va(end),vb(end));
overlap = hi-lo;
if overlap < config.packetMinOverlapMeters || ...
        overlap / min(va(end)-va(1),vb(end)-vb(1)) < config.packetMinOverlapFraction
    return;
end
% 把两条折线在重叠区的所有顶点都作为检查点；顶点之间是线性的，
% 因此逐点检查沿程差的正负，可以排除重叠区内两条线交叉的情况。
knots = unique([lo;hi;va(va>lo & va<hi);vb(vb>lo & vb<hi)]);
diffAlong = interp1(va,ua,knots) - interp1(vb,ub,knots);
if all(diffAlong >= config.packetMinSeparationMeters)
    order = 1;
elseif all(diffAlong <= -config.packetMinSeparationMeters)
    order = -1;
else
    return;
end
gap = max(abs(diffAlong));
end

function [across,along] = profile(crest,dir,config)
%PROFILE 把波锋写成“横向位置 -> 沿程位置”的分段线性曲线。
% across 和 along 均以站点为原点，单位米；沿程正方向即传播方向。
lat = crest.latitude{1}(:); lon = crest.longitude{1}(:);
good = isfinite(lat) & isfinite(lon);
lat = lat(good); lon = lon(good);
x = (lon-config.mooringLon)*cosd(config.mooringLat)*111320;
y = (lat-config.mooringLat)*110540;
keep = [true;hypot(diff(x),diff(y)) > 1e-6];
x = x(keep); y = y(keep);
across = -x*cosd(dir) + y*sind(dir);
along = x*sind(dir) + y*cosd(dir);
if numel(across) < 2
    across = []; along = []; return;
end
if all(diff(across) < -1e-6)
    across = flipud(across); along = flipud(along);
elseif ~all(diff(across) > 1e-6)
    % 若同一横向位置有多个沿程位置，无法在这里确定唯一的前后次序。
    % 这种折返波锋本轮不归包，但不因此禁止它单独参加速度匹配。
    across = []; along = [];
end
end
