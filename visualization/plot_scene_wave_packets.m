function result = plot_scene_wave_packets(shpSelector, config)
%PLOT_SCENE_WAVE_PACKETS 绘制一张影像中的候选波包及组内头尾顺序。
%
% 默认用文件选择框选择一个 SHP：
%   result = plot_scene_wave_packets();
%
% 也可以传入完整路径、文件名或按文件名排序后的序号：
%   result = plot_scene_wave_packets('A2020104.0535.xxx.shp');
%   result = plot_scene_wave_packets(10);
%
% 图窗采用双视图：
%   左侧：整张影像中的全部波锋。同一候选波包使用同一种颜色，
%         未归包波锋使用灰色虚线。
%   右侧：逐个放大候选波包。标签 P2-R1 表示显示编号为 2 的波包中，
%         排在最前面的已观测波锋。R1 不等于已确认的物理头波。
%         R2 起额外显示 gap，表示与前一条波锋的最大间距。
%
% 手动翻页：
%   Enter 或 n：下一个波包；p：上一个波包；q：退出。
%
% 本函数只读取指定 SHP 并调用 group_scene_wave_packets，不运行系泊
% 速度匹配，也不修改历史匹配文件。波包颜色和编号仅用于检查算法分组。

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(projectRoot, 'utils')));

if nargin < 1
    shpSelector = [];
end
if nargin < 2 || isempty(config)
    config = struct();
end
config = applyDefaults(config, projectRoot);
shpPath = resolveShpPath(shpSelector, config.shpDir);

%% 读取该影像中的全部波锋
features = shaperead(shpPath);
if isempty(features)
    error('SHP 中没有波锋要素：%s', shpPath);
end

nCrests = numel(features);
crestIdx = (1:nCrests)';
sceneId = ones(nCrests, 1);
fileName = repmat(string(shpPath), nCrests, 1);
featureIndex = crestIdx;
latitude = arrayfun(@(x) x.Y(:), features, 'UniformOutput', false);
longitude = arrayfun(@(x) x.X(:), features, 'UniformOutput', false);
directionDeg = nan(nCrests, 1);
directionStatus = strings(nCrests, 1);

% 复用生产链路的统一方向解析函数，不在绘图脚本中复制翻转规则。
for i = 1:nCrests
    direction = resolveCrestDirection( ...
        latitude{i}, longitude{i}, config.mooringLat, config.mooringLon);
    directionStatus(i) = direction.reason;
    if direction.isValid
        directionDeg(i) = direction.dirDeg;
    end
end

crests = table(crestIdx, sceneId, fileName, featureIndex, latitude, ...
    longitude, directionDeg, directionStatus, ...
    'VariableNames', {'crest_idx','scene_id','file_name','feature_index', ...
    'latitude','longitude','direction_deg','direction_status'});

%% 调用被检查的波包分组函数
packets = group_scene_wave_packets(crests, config);
packetIds = unique(packets.packet_id(packets.packet_id > 0), 'stable');
nPackets = numel(packetIds);

% packet_id 使用组内最小 crest_idx，适合程序追踪但不便看图。
% display_packet_id 将本景的候选波包重新编号为 P1、P2、...。
displayPacketId = zeros(nCrests, 1);
for p = 1:nPackets
    displayPacketId(packets.packet_id == packetIds(p)) = p;
end
packets.display_packet_id = displayPacketId;

% 颜色只编码“算法认为属于哪个波包”。未归包统一使用灰色。
packetColors = lines(max(nPackets, 1));
ungroupedColor = [0.55, 0.55, 0.55];

%% 创建 C 布局：左侧整景，右侧逐包
hFig = figure( ...
    'Name', sprintf('Wave packets: %s', string(getFileName(shpPath))), ...
    'Color', 'w', ...
    'Visible', config.figureVisible, ...
    'Units', 'pixels', ...
    'Position', [80, 80, 1500, 760]);
layout = tiledlayout(hFig, 1, 2, ...
    'TileSpacing', 'compact', 'Padding', 'compact');
axOverview = nexttile(layout, 1);
axPacket = nexttile(layout, 2);

drawOverview(axOverview, crests, packets, packetColors, ...
    ungroupedColor, shpPath, config);

if nPackets == 0
    drawEmptyPacketPanel(axPacket, crests);
    fprintf('该 SHP 共 %d 条波锋，算法未识别出包含至少 2 条波锋的候选波包。\n', ...
        nCrests);
else
    browsePackets(hFig, axPacket, crests, packets, packetIds, ...
        packetColors, ungroupedColor, shpPath, config);
end

%% 输出表用于回查原始 SHP 要素
result = struct();
result.shp_path = string(shpPath);
result.crests = crests;
result.packets = packets;
result.packet_count = nPackets;
result.grouped_crest_count = nnz(packets.packet_id > 0);
result.ungrouped_crest_count = nnz(packets.packet_id == 0);
result.figure = hFig;

summary = packets(:, {'crest_idx','scene_id','packet_id','packet_rank', ...
    'observed_packet_size','packet_status','display_packet_id'});
summary.feature_index = crests.feature_index;
summary.direction_deg = crests.direction_deg;
summary.direction_status = crests.direction_status;

fprintf('\nSHP：%s\n', shpPath);
fprintf('波锋总数：%d；候选波包：%d；已归包波锋：%d；未归包波锋：%d。\n', ...
    nCrests, nPackets, result.grouped_crest_count, ...
    result.ungrouped_crest_count);
disp(summary);
end

function config = applyDefaults(config, projectRoot)
%APPLYDEFAULTS 绘图和波包分组参数。
% packet* 参数与 group_scene_wave_packets 的输入一一对应。它们目前是
% 待目视核查的几何阈值，不代表已经验证的真实波包识别标准。
% 本项目优先避免误合并。当前默认相邻间距上限设为 8 km；
% 超过该值的波锋不会仅因同向、重叠而被串成同一个波包。
defaults = struct( ...
    'shpDir', fullfile(projectRoot, 'data', 'shp_files'), ...
    'mooringLat', 20.816666666666666, ...
    'mooringLon', 115.76666666666667, ...
    'packetDirectionToleranceDeg', 25, ...
    'packetMinOverlapMeters', 1000, ...
    'packetMinOverlapFraction', 0.5, ...
    'packetMinSeparationMeters', 250, ...
    'packetMaxNeighborGapMeters', 8000, ...
    'packetMaxSpanMeters', 40000, ...
    'manualPage', true, ...
    'pauseSeconds', 0.8, ...
    'showLabels', true, ...
    'showMooring', true, ...
    'saveFigures', false, ...
    'saveDir', fullfile(projectRoot, 'diagnostics', 'wave_packet_plots'), ...
    'figureVisible', 'on');

names = fieldnames(config);
if ~all(ismember(names, fieldnames(defaults)))
    unknown = names(~ismember(names, fieldnames(defaults)));
    error('未知配置字段：%s', strjoin(string(unknown), ', '));
end
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(config, names{i}) || isempty(config.(names{i}))
        config.(names{i}) = defaults.(names{i});
    end
end

validateattributes(config.packetDirectionToleranceDeg, {'numeric'}, ...
    {'scalar','finite','>=',0,'<',90});
validateattributes(config.packetMinOverlapMeters, {'numeric'}, ...
    {'scalar','finite','positive'});
validateattributes(config.packetMinOverlapFraction, {'numeric'}, ...
    {'scalar','finite','>',0,'<=',1});
validateattributes(config.packetMinSeparationMeters, {'numeric'}, ...
    {'scalar','finite','positive'});
validateattributes(config.packetMaxNeighborGapMeters, {'numeric'}, ...
    {'scalar','finite','positive'});
validateattributes(config.packetMaxSpanMeters, {'numeric'}, ...
    {'scalar','finite','positive'});
validateattributes(config.manualPage, {'logical'}, {'scalar'});
validateattributes(config.pauseSeconds, {'numeric'}, ...
    {'scalar','finite','nonnegative'});
validateattributes(config.showLabels, {'logical'}, {'scalar'});
validateattributes(config.showMooring, {'logical'}, {'scalar'});
validateattributes(config.saveFigures, {'logical'}, {'scalar'});
if config.packetMaxSpanMeters < config.packetMaxNeighborGapMeters
    error('packetMaxSpanMeters 不能小于 packetMaxNeighborGapMeters。');
end
if ~ismember(string(config.figureVisible), ["on","off"])
    error('figureVisible 必须是 ''on'' 或 ''off''。');
end
end

function shpPath = resolveShpPath(selector, shpDir)
%RESOLVESHPPATH 支持文件选择框、文件名、完整路径和排序后的文件序号。
files = dir(fullfile(shpDir, '*.shp'));
if isempty(files)
    error('目录中没有 SHP 文件：%s', shpDir);
end
[~, order] = sort(string({files.name}));
files = files(order);

if isempty(selector)
    [name, folder] = uigetfile(fullfile(shpDir, '*.shp'), ...
        '选择一张影像对应的 SHP 文件');
    if isequal(name, 0)
        error('未选择 SHP 文件。');
    end
    shpPath = fullfile(folder, name);
elseif isnumeric(selector)
    validateattributes(selector, {'numeric'}, ...
        {'scalar','integer','>=',1,'<=',numel(files)});
    shpPath = fullfile(files(selector).folder, files(selector).name);
else
    selector = char(string(selector));
    if isfile(selector)
        shpPath = selector;
    else
        shpPath = fullfile(shpDir, selector);
    end
    if ~isfile(shpPath)
        error('SHP 文件不存在：%s', shpPath);
    end
end
end

function drawOverview(ax, crests, packets, colors, gray, shpPath, config)
%DRAWOVERVIEW 左侧整景图：同包同色，未归包使用灰色虚线。
cla(ax);
hold(ax, 'on');
box(ax, 'on');
grid(ax, 'on');

for i = 1:height(crests)
    displayId = packets.display_packet_id(i);
    if displayId == 0
        color = gray;
        style = '--';
        width = 1.2;
        label = sprintf('U-F%d', crests.feature_index(i));
    else
        color = colors(displayId, :);
        style = '-';
        width = 2.2;
        label = sprintf('P%d-R%d', displayId, packets.packet_rank(i));
    end
    plot(ax, crests.longitude{i}, crests.latitude{i}, style, ...
        'Color', color, 'LineWidth', width);
    if config.showLabels
        labelCrest(ax, crests.longitude{i}, crests.latitude{i}, label, color);
    end
end

plotMooringIfNear(ax, crests, config);
axis(ax, 'equal');
xlabel(ax, 'Longitude (deg)');
ylabel(ax, 'Latitude (deg)');
title(ax, sprintf('整景：%s', getFileName(shpPath)), ...
    'Interpreter', 'none');
subtitle(ax, sprintf('P=候选波包，R=已观测波锋顺序，U=未归包；共 %d 条波锋', ...
    height(crests)));
end

function browsePackets(hFig, ax, crests, packets, packetIds, ...
    colors, gray, shpPath, config)
%BROWSEPACKETS 右侧逐包查看。上下文线保留，避免脱离整景误判。
position = 1;
nPackets = numel(packetIds);
while isgraphics(hFig)
    packetId = packetIds(position);
    rows = find(packets.packet_id == packetId);
    [~, order] = sort(packets.packet_rank(rows));
    rows = rows(order);
    displayId = packets.display_packet_id(rows(1));
    drawPacket(ax, crests, packets, rows, displayId, ...
        colors(displayId, :), gray, config);
    drawnow;

    if config.saveFigures
        if ~isfolder(config.saveDir)
            mkdir(config.saveDir);
        end
        [~, base] = fileparts(shpPath);
        outputName = sprintf('%s_packet_P%02d.png', base, displayId);
        exportgraphics(hFig, fullfile(config.saveDir, outputName), ...
            'Resolution', 220);
    end

    if ~config.manualPage
        if position >= nPackets
            break;
        end
        pause(config.pauseSeconds);
        position = position + 1;
        continue;
    end

    response = input(sprintf( ...
        '波包 %d/%d：回车或 n=下一包，p=上一包，q=退出：', ...
        position, nPackets), 's');
    response = lower(strtrim(response));
    if strcmp(response, 'q')
        break;
    elseif strcmp(response, 'p')
        position = max(1, position - 1);
    else
        position = min(nPackets, position + 1);
    end
end
end

function drawPacket(ax, crests, packets, rows, displayId, color, gray, config)
%DRAWPACKET 右侧突出当前波包，整景其他波锋仅作为浅色背景。
cla(ax);
hold(ax, 'on');
box(ax, 'on');
grid(ax, 'on');

for i = 1:height(crests)
    plot(ax, crests.longitude{i}, crests.latitude{i}, '-', ...
        'Color', blendWithWhite(gray, 0.72), 'LineWidth', 0.8);
end
for k = 1:numel(rows)
    i = rows(k);
    plot(ax, crests.longitude{i}, crests.latitude{i}, '-', ...
        'Color', color, 'LineWidth', 3);
    if config.showLabels
        rank = packets.packet_rank(i);
        gap = packets.max_gap_to_previous_m(i);
        if rank > 1 && isfinite(gap)
            label = sprintf('P%d-R%d / F%d / gap %.2f km', displayId, ...
                rank, crests.feature_index(i), gap/1000);
        else
            label = sprintf('P%d-R%d / F%d', displayId, ...
                rank, crests.feature_index(i));
        end
        labelCrest(ax, crests.longitude{i}, crests.latitude{i}, label, color);
    end
end

drawMeanDirection(ax, crests, rows, color);
plotMooringIfNear(ax, crests, config);
axis(ax, 'equal');
xlabel(ax, 'Longitude (deg)');
ylabel(ax, 'Latitude (deg)');
title(ax, sprintf('当前候选波包 P%d', displayId));
subtitle(ax, sprintf('%d 条已提取波锋；相邻间距上限 %.1f km', ...
    numel(rows), config.packetMaxNeighborGapMeters/1000));
end

function drawEmptyPacketPanel(ax, crests)
%DRAWEMPTYPACKETPANEL 没有识别到波包时仍展示整景范围和明确状态。
cla(ax);
hold(ax, 'on');
box(ax, 'on');
for i = 1:height(crests)
    plot(ax, crests.longitude{i}, crests.latitude{i}, '--', ...
        'Color', [0.65, 0.65, 0.65], 'LineWidth', 1);
end
axis(ax, 'equal');
grid(ax, 'on');
xlabel(ax, 'Longitude (deg)');
ylabel(ax, 'Latitude (deg)');
title(ax, '没有候选波包');
subtitle(ax, '当前参数下，没有至少两条波锋被归为同一组');
end

function labelCrest(ax, lon, lat, label, color)
%LABELCREST 在有效坐标的中间位置标注波包和波序。
good = isfinite(lon) & isfinite(lat);
indices = find(good);
if isempty(indices)
    return;
end
mid = indices(ceil(numel(indices) / 2));
text(ax, lon(mid), lat(mid), [' ' label], ...
    'Color', color, 'FontSize', 9, 'FontWeight', 'bold', ...
    'Interpreter', 'none', 'Clipping', 'on');
end

function drawMeanDirection(ax, crests, rows, color)
%DRAWMEANDIRECTION 使用组内方向的圆均值绘制一根传播方向箭头。
directions = crests.direction_deg(rows);
directions = directions(isfinite(directions));
if isempty(directions)
    return;
end
meanDirection = mod(atan2d(mean(sind(directions)), ...
    mean(cosd(directions))), 360);
[centerLon, centerLat] = packetCenter(crests, rows);

allLon = vertcatCells(crests.longitude(rows));
allLat = vertcatCells(crests.latitude(rows));
span = max([range(allLon), range(allLat)]);
if ~isfinite(span) || span <= 0
    span = 0.05;
end
arrowLength = 0.15 * span;
quiver(ax, centerLon, centerLat, ...
    arrowLength * sind(meanDirection), ...
    arrowLength * cosd(meanDirection), 0, ...
    'Color', color, 'LineWidth', 2, 'MaxHeadSize', 0.8);
end

function [centerLon, centerLat] = packetCenter(crests, rows)
%PACKETCENTER 取当前波包全部有效点的中位数作为箭头起点。
lon = vertcatCells(crests.longitude(rows));
lat = vertcatCells(crests.latitude(rows));
centerLon = median(lon);
centerLat = median(lat);
end

function values = vertcatCells(cells)
%VERTCATCELLS 合并坐标单元格并删除 NaN。
values = vertcat(cells{:});
values = values(isfinite(values));
end

function plotMooringIfNear(ax, crests, config)
%PLOTMOORINGIFNEAR 站点接近当前影像范围时才绘制，避免把坐标轴拉得过大。
if ~config.showMooring
    return;
end
lon = vertcatCells(crests.longitude);
lat = vertcatCells(crests.latitude);
if isempty(lon) || isempty(lat)
    return;
end
paddingLon = max(0.05, 0.1 * range(lon));
paddingLat = max(0.05, 0.1 * range(lat));
inside = config.mooringLon >= min(lon)-paddingLon && ...
    config.mooringLon <= max(lon)+paddingLon && ...
    config.mooringLat >= min(lat)-paddingLat && ...
    config.mooringLat <= max(lat)+paddingLat;
if inside
    plot(ax, config.mooringLon, config.mooringLat, 'rp', ...
        'MarkerFaceColor', 'r', 'MarkerSize', 12);
end
end

function mixed = blendWithWhite(color, whiteWeight)
%BLENDWITHWHITE 将背景线颜色向白色混合，突出右侧当前波包。
mixed = (1-whiteWeight) * color + whiteWeight * [1,1,1];
end

function name = getFileName(path)
%GETFILENAME 返回包含扩展名的文件名。
[~, stem, ext] = fileparts(path);
name = [stem ext];
end
