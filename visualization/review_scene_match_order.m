function result = review_scene_match_order(config)
%REVIEW_SCENE_MATCH_ORDER 逐景核查已有匹配在候选波包内是否保持到站顺序。
%
% 直接运行：
%   result = review_scene_match_order();
%
% 常用自定义：
%   config = struct();
%   config.matPath = fullfile('TMP', 'matched_results_with_capsules.mat');
%   config.outputCsv = fullfile('diagnostics', 'my_order_reviews.csv');
%   result = review_scene_match_order(config);
%
% 每次显示一张影像中的一个候选波包：
%   左侧：该影像的全部波锋和自动分组。
%   右侧：当前波包。实线是已有匹配，虚线是同包但未匹配的波锋。
%   下方：按空间顺序列出的到站时刻、速度差和自动倒序对数。
%
% 命令行输入：
%   N = 正常；D = 乱序；U = 无法判断；Z = 撤销上一条；Q = 保存并退出。
%
% 每个判断都会立即写入 CSV。历史记录只用于同批数据断点续查：
% 数据变化或旧 CSV 无法读取时，自动使用带 _run001 等后缀的新文件，
% 保留旧文件。config.resumeReviews=false 可强制开启全新一轮核查。
% 只有一条已匹配波锋的单元无法检验先后关系，程序会自动记录为
% single_match，并从乱序率分母中排除。
%
% 本工具只读取已有匹配，不修改 MAT 中的分配结果。旧 MAT 只保存了
% 系泊事件的起始时刻，因此这里的到站顺序统一使用 mooring_time。

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(projectRoot, 'utils')));

if nargin < 1 || isempty(config)
    config = struct();
end
config = applyDefaults(config, projectRoot);

fprintf('读取匹配结果：%s\n', config.matPath);
matchData = loadMatchData(config.matPath);

fprintf('重建 SHP 波锋目录并计算候选波包...\n');
[crests, packets] = buildCrestCatalog(config);
matches = buildMatchTable(matchData, crests);
validateMatchMapping(matches, crests, config.coordinateToleranceMeters);

packets.display_packet_id = assignDisplayPacketIds(packets);
units = buildReviewUnits(crests, packets, matches, config);
reviews = emptyReviews();

% 批量自检只依赖当前 MAT 和 SHP，不读取历史标签，也不写任何文件。
if ~config.interactive
    result = buildResult(config, crests, packets, matches, units, reviews, ...
        table(), [], false);
    printInventory(units);
    return;
end

[reviews, config] = selectReviewSession(units, config);
[reviews, addedSingles] = addSingleMatchRows( ...
    reviews, units, config.matPath);
if addedSingles > 0
    [summary, reviews] = saveReviewFiles(reviews, units, config);
    fprintf('已自动登记 %d 个只有一条匹配的单元。\n', addedSingles);
else
    summary = buildSceneSummary(units, reviews, config.matPath);
end

hFig = createReviewFigure(config);
undoHistory = strings(0, 2);
quitRequested = false;

while isgraphics(hFig)
    current = findFirstPendingUnit(units, reviews, config.matPath);
    if isempty(current)
        break;
    end

    unit = units(current);
    drawReviewUnit(hFig, crests, packets, matches, unit, ...
        reviews, config);
    drawnow;

    response = lower(strtrim(input( ...
        '判断 N=正常，D=乱序，U=无法判断，Z=撤销，Q=保存退出：', 's')));
    if isempty(response)
        continue;
    end

    switch response(1)
        case 'n'
            label = "normal";
        case 'd'
            label = "disordered";
        case 'u'
            label = "uncertain";
        case 'z'
            [reviews, undoneKey, undoneScene] = undoLastManualReview( ...
                reviews, config.matPath, undoHistory);
            if strlength(undoneKey) == 0
                fprintf('没有可撤销的人工判断。\n');
            else
                if ~isempty(undoHistory)
                    undoHistory(end, :) = [];
                end
                [summary, reviews] = saveReviewFiles(reviews, units, config);
                fprintf('已撤销：%s / %s。\n', undoneScene, undoneKey);
            end
            continue;
        case 'q'
            quitRequested = true;
            break;
        otherwise
            fprintf('无效输入。请使用 N、D、U、Z 或 Q。\n');
            continue;
    end

    if response(1) == 'q'
        break;
    end

    row = makeReviewRow(unit, config.matPath, label);
    reviews = appendReview(reviews, row);
    undoHistory(end+1, :) = [string(unit.scene_file), string(unit.packet_key)]; %#ok<AGROW>
    [summary, reviews] = saveReviewFiles(reviews, units, config);
end

if isempty(summary)
    summary = buildSceneSummary(units, reviews, config.matPath);
end
printFinalSummary(units, reviews, config.matPath, quitRequested);

result = buildResult(config, crests, packets, matches, units, reviews, ...
    summary, hFig, quitRequested);
end

function config = applyDefaults(config, projectRoot)
%APPLYDEFAULTS 汇总输入、分组和输出参数。
latestMat = fullfile(projectRoot, 'src', ...
    'matched_results_with_capsules.mat');
legacyMat = fullfile(projectRoot, 'TMP', ...
    'matched_results_with_capsules.mat');
if isfile(latestMat)
    defaultMat = latestMat;
else
    defaultMat = legacyMat;
end

defaults = struct( ...
    'matPath', defaultMat, ...
    'shpDir', fullfile(projectRoot, 'data', 'shp_files'), ...
    'outputCsv', fullfile(projectRoot, 'diagnostics', ...
        'scene_match_order_reviews.csv'), ...
    'summaryCsv', fullfile(projectRoot, 'diagnostics', ...
        'scene_match_order_scene_summary.csv'), ...
    'mooringLat', 20.816666666666666, ...
    'mooringLon', 115.76666666666667, ...
    'packetDirectionToleranceDeg', 25, ...
    'packetMinOverlapMeters', 1000, ...
    'packetMinOverlapFraction', 0.5, ...
    'packetMinSeparationMeters', 250, ...
    'packetMaxNeighborGapMeters', 8000, ...
    'packetMaxSpanMeters', 40000, ...
    'coordinateToleranceMeters', 1500, ...
    'figureVisible', 'on', ...
    'interactive', true, ...
    'resumeReviews', true);

unknown = setdiff(fieldnames(config), fieldnames(defaults));
if ~isempty(unknown)
    error('未知配置字段：%s', strjoin(string(unknown), ', '));
end
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(config, names{i}) || isempty(config.(names{i}))
        config.(names{i}) = defaults.(names{i});
    end
end

config.matPath = resolveProjectPath(config.matPath, projectRoot);
config.shpDir = resolveProjectPath(config.shpDir, projectRoot);
config.outputCsv = resolveProjectPath(config.outputCsv, projectRoot);
config.summaryCsv = resolveProjectPath(config.summaryCsv, projectRoot);

if ~isfile(config.matPath)
    error('匹配结果文件不存在：%s', config.matPath);
end
if ~isfolder(config.shpDir)
    error('SHP 目录不存在：%s', config.shpDir);
end
validateattributes(config.coordinateToleranceMeters, {'numeric'}, ...
    {'scalar','finite','positive'});
validateattributes(config.interactive, {'logical'}, {'scalar'});
validateattributes(config.resumeReviews, {'logical'}, {'scalar'});
if ~ismember(string(config.figureVisible), ["on","off"])
    error('figureVisible 必须是 ''on'' 或 ''off''。');
end

packetFields = { ...
    'packetDirectionToleranceDeg', 'packetMinOverlapMeters', ...
    'packetMinOverlapFraction', 'packetMinSeparationMeters', ...
    'packetMaxNeighborGapMeters', 'packetMaxSpanMeters'};
for i = 1:numel(packetFields)
    validateattributes(config.(packetFields{i}), {'numeric'}, ...
        {'scalar','finite','positive'});
end
if config.packetDirectionToleranceDeg >= 90
    error('packetDirectionToleranceDeg 必须小于 90°。');
end
if config.packetMinOverlapFraction > 1
    error('packetMinOverlapFraction 不能大于 1。');
end
if config.packetMaxSpanMeters < config.packetMaxNeighborGapMeters
    error('packetMaxSpanMeters 不能小于 packetMaxNeighborGapMeters。');
end
end

function path = resolveProjectPath(path, projectRoot)
%RESOLVEPROJECTPATH 相对路径统一按项目根目录解析。
path = char(string(path));
if ~isAbsolutePath(path)
    path = fullfile(projectRoot, path);
end
if isfile(path) || isfolder(path)
    [ok, attributes] = fileattrib(path);
    if ok
        path = attributes.Name;
    end
end
end

function tf = isAbsolutePath(path)
%ISABSOLUTEPATH 同时兼容 Unix 和 Windows 绝对路径。
tf = startsWith(path, filesep) || ...
    ~isempty(regexp(path, '^[A-Za-z]:[\\/]', 'once'));
end

function data = loadMatchData(matPath)
%LOADMATCHDATA 加载旧版和新版结果共有的核查字段。
data = load(matPath);
required = {'crest_idx','crest_lon','crest_lat','crest_time', ...
    'mooring_time','speed_diff','mode'};
missing = required(~isfieldMany(data, required));
if ~isempty(missing)
    error('MAT 缺少必需字段：%s', strjoin(string(missing), ', '));
end
end

function mask = isfieldMany(value, names)
%ISFIELDMANY 对一组字段名执行 isfield。
mask = false(size(names));
for i = 1:numel(names)
    mask(i) = isfield(value, names{i});
end
end

function [crests, packets] = buildCrestCatalog(config)
%BUILDCRESTCATALOG 按生产入口的 dir 顺序重建全局 crest_idx。
crests = buildCrestReviewCatalog(config.shpDir, 8);
directionDeg = nan(height(crests),1);
directionStatus = strings(height(crests),1);
for row = 1:height(crests)
    direction = resolveCrestDirection( ...
        crests.latitude{row}, crests.longitude{row}, ...
        config.mooringLat, config.mooringLon);
    directionStatus(row) = direction.reason;
    if direction.isValid
        directionDeg(row) = direction.dirDeg;
    end
end
crests.direction_deg = directionDeg;
crests.direction_status = directionStatus;
packets = group_scene_wave_packets(crests, config);
end

function matches = buildMatchTable(data, crests)
%BUILDMATCHTABLE 把 MAT 数组整理成逐匹配表，并关联到原始波锋目录。
n = numel(data.crest_idx);
fields = {'crest_lon','crest_lat','crest_time','mooring_time', ...
    'speed_diff','mode'};
for i = 1:numel(fields)
    if numel(data.(fields{i})) ~= n
        error('MAT 字段 %s 的长度与 crest_idx 不一致。', fields{i});
    end
end

crestIdx = double(data.crest_idx(:));
if any(~isfinite(crestIdx) | crestIdx < 1 | crestIdx ~= round(crestIdx))
    error('MAT 中的 crest_idx 必须是正整数。');
end
if numel(unique(crestIdx)) ~= n
    error('MAT 中存在重复 crest_idx，无法建立一对一核查单元。');
end

[found, catalogRow] = ismember(crestIdx, crests.crest_idx);
if ~all(found)
    error('有 %d 个 crest_idx 超出当前 SHP 目录范围。', nnz(~found));
end

crestTime = toDatetime(data.crest_time);
mooringTime = toDatetime(data.mooring_time);
speedDiff = double(data.speed_diff(:));
mode = double(data.mode(:));
crestLon = toColumnCells(data.crest_lon);
crestLat = toColumnCells(data.crest_lat);
matches = table((1:n)', crestIdx, catalogRow, crestTime, mooringTime, ...
    speedDiff, mode, crestLon, crestLat, ...
    'VariableNames', {'match_row','crest_idx','catalog_row','crest_time', ...
    'mooring_time','speed_diff','mode','saved_longitude','saved_latitude'});
end

function value = toDatetime(value)
%TODATETIME 兼容 datetime、datenum 和可解析文本。
if isdatetime(value)
    value = value(:);
elseif isnumeric(value)
    value = datetime(value(:), 'ConvertFrom', 'datenum');
else
    value = datetime(string(value(:)));
end
end

function cells = toColumnCells(value)
%TOCOLUMNCELLS 把坐标字段统一为列向量 cell。
if iscell(value)
    cells = value(:);
else
    cells = cell(size(value,1),1);
    for i = 1:size(value,1)
        cells{i} = value(i,:);
    end
end
end

function validateMatchMapping(matches, crests, toleranceMeters)
%VALIDATEMATCHMAPPING 用坐标签名确认全局编号仍对应同一条原始波锋。
errors = nan(height(matches),1);
for i = 1:height(matches)
    row = matches.catalog_row(i);
    rawLon = crests.longitude{row};
    rawLat = crests.latitude{row};
    savedLon = matches.saved_longitude{i};
    savedLat = matches.saved_latitude{i};
    errors(i) = coordinateSignatureError( ...
        rawLon, rawLat, savedLon, savedLat);
end

bad = ~isfinite(errors) | errors > toleranceMeters;
if any(bad)
    badRows = find(bad);
    count = min(numel(badRows), 8);
    details = strings(count,1);
    for i = 1:count
        row = badRows(i);
        details(i) = sprintf('crest_idx=%d, error=%.1f m', ...
            matches.crest_idx(row), errors(row));
    end
    error(['MAT 与当前 SHP 的 crest_idx 映射不一致，已停止核查。' ...
        '前 %d 条异常：%s'], count, strjoin(details, '；'));
end
fprintf('坐标映射核验通过：%d 条匹配，最大签名误差 %.1f m。\n', ...
    height(matches), max(errors));
end

function errorMeters = coordinateSignatureError(rawLon, rawLat, savedLon, savedLat)
%COORDINATESIGNATUREERROR 比较端点和经纬度包络，允许折线存储方向翻转。
raw = cleanCoordinates(rawLon, rawLat);
saved = cleanCoordinates(savedLon, savedLat);
if size(raw,1) < 2 || size(saved,1) < 2
    errorMeters = Inf;
    return;
end

lat0 = mean([raw(:,2); saved(:,2)]);
scale = [111320*cosd(lat0), 110540];
rawEnds = raw([1,end],:);
savedEnds = saved([1,end],:);
same = max(hypot( ...
    (rawEnds(:,1)-savedEnds(:,1))*scale(1), ...
    (rawEnds(:,2)-savedEnds(:,2))*scale(2)));
reverse = max(hypot( ...
    (rawEnds(:,1)-flipud(savedEnds(:,1)))*scale(1), ...
    (rawEnds(:,2)-flipud(savedEnds(:,2)))*scale(2)));
endpointError = min(same, reverse);

rawBounds = [min(raw,[],1); max(raw,[],1)];
savedBounds = [min(saved,[],1); max(saved,[],1)];
boundError = max(abs((rawBounds-savedBounds).*scale), [], 'all');
errorMeters = max(endpointError, boundError);
end

function coordinates = cleanCoordinates(lon, lat)
%CLEANCOORDINATES 删除坐标中的 NaN 和 Inf。
lon = lon(:);
lat = lat(:);
good = isfinite(lon) & isfinite(lat);
coordinates = [lon(good), lat(good)];
end

function displayIds = assignDisplayPacketIds(packets)
%ASSIGNDISPLAYPACKETIDS 在每张影像内把候选波包显示为 P1、P2、...。
displayIds = zeros(height(packets),1);
scenes = unique(packets.scene_id, 'stable');
for s = 1:numel(scenes)
    sceneRows = find(packets.scene_id == scenes(s));
    ids = unique(packets.packet_id(sceneRows));
    ids = ids(ids > 0);
    for p = 1:numel(ids)
        displayIds(sceneRows(packets.packet_id(sceneRows) == ids(p))) = p;
    end
end
end

function units = buildReviewUnits(crests, packets, matches, config)
%BUILDREVIEWUNITS 建立“影像 + 候选波包”的稳定核查队列。
template = struct( ...
    'scene_id', NaN, ...
    'scene_file', "", ...
    'packet_key', "", ...
    'packet_id', NaN, ...
    'display_packet_id', NaN, ...
    'all_catalog_rows', [], ...
    'match_rows', [], ...
    'matched_catalog_rows', [], ...
    'packet_ranks', [], ...
    'observed_packet_size', NaN, ...
    'matched_crest_count', NaN, ...
    'evaluable', false, ...
    'auto_inversion_count', NaN, ...
    'review_feature_indices', [], ...
    'review_crest_indices', [], ...
    'review_mooring_times', NaT(0,1), ...
    'review_speed_diffs', [], ...
    'group_config', "");
units = repmat(template, 0, 1);

matchedScenes = unique(crests.scene_id(matches.catalog_row), 'stable');
for s = 1:numel(matchedScenes)
    scene = matchedScenes(s);
    sceneMatchRows = find(crests.scene_id(matches.catalog_row) == scene);
    sceneCatalogRows = matches.catalog_row(sceneMatchRows);
    packetIds = packets.packet_id(sceneCatalogRows);

    groupedIds = unique(packetIds(packetIds > 0), 'stable');
    for p = 1:numel(groupedIds)
        packetId = groupedIds(p);
        allRows = find(packets.scene_id == scene & ...
            packets.packet_id == packetId);
        unitMatchRows = sceneMatchRows(ismember(sceneCatalogRows, allRows));
        units(end+1,1) = makeUnit(template, crests, packets, matches, ...
            allRows, unitMatchRows, "P"+string(packetId), packetId, config); %#ok<AGROW>
    end

    singletonMatchRows = sceneMatchRows(packetIds == 0);
    for p = 1:numel(singletonMatchRows)
        matchRow = singletonMatchRows(p);
        catalogRow = matches.catalog_row(matchRow);
        key = "S"+string(matches.crest_idx(matchRow));
        units(end+1,1) = makeUnit(template, crests, packets, matches, ...
            catalogRow, matchRow, key, 0, config); %#ok<AGROW>
    end
end

if isempty(units)
    error('当前 MAT 没有可核查的匹配。');
end

sortKey = zeros(numel(units),3);
for i = 1:numel(units)
    sortKey(i,:) = [units(i).scene_id, ...
        min(crests.feature_index(units(i).all_catalog_rows)), ...
        units(i).packet_id == 0];
end
[~, order] = sortrows(sortKey, [1,2,3]);
units = units(order);
end

function unit = makeUnit(template, crests, packets, matches, ...
    allRows, matchRows, key, packetId, config)
%MAKEUNIT 生成一个候选波包或未归包单条的核查元数据。
unit = template;
unit.scene_id = crests.scene_id(allRows(1));
unit.scene_file = crests.scene_file(allRows(1));
unit.packet_key = key;
unit.packet_id = packetId;
unit.display_packet_id = packets.display_packet_id(allRows(1));
unit.all_catalog_rows = allRows(:);
unit.match_rows = matchRows(:);
unit.matched_catalog_rows = matches.catalog_row(matchRows);

if packetId > 0
    ranks = packets.packet_rank(unit.matched_catalog_rows);
else
    ranks = ones(numel(matchRows),1);
end
[ranks, order] = sort(ranks);
unit.packet_ranks = ranks;
unit.match_rows = unit.match_rows(order);
unit.matched_catalog_rows = unit.matched_catalog_rows(order);
unit.observed_packet_size = numel(allRows);
unit.matched_crest_count = numel(matchRows);
unit.evaluable = numel(matchRows) >= 2;
unit.auto_inversion_count = countInversions( ...
    matches.mooring_time(unit.match_rows));
unit.review_feature_indices = ...
    crests.feature_index(unit.matched_catalog_rows);
unit.review_crest_indices = matches.crest_idx(unit.match_rows);
unit.review_mooring_times = matches.mooring_time(unit.match_rows);
unit.review_speed_diffs = matches.speed_diff(unit.match_rows);
unit.group_config = groupConfigSignature(config);
end

function count = countInversions(times)
%COUNTINVERSIONS 统计空间顺序靠前但到站时刻不早于后方波锋的成对冲突。
if numel(times) < 2
    count = NaN;
    return;
end
if any(isnat(times))
    count = NaN;
    return;
end
count = 0;
for i = 1:numel(times)-1
    for j = i+1:numel(times)
        count = count + (times(i) >= times(j));
    end
end
end

function signature = groupConfigSignature(config)
%GROUPCONFIGSIGNATURE 防止分组参数变化后误复用旧人工标签。
signature = sprintf(['dir=%.12g;overlap_m=%.12g;overlap_frac=%.12g;' ...
    'separation_m=%.12g;neighbor_gap_m=%.12g;span_m=%.12g'], ...
    config.packetDirectionToleranceDeg, config.packetMinOverlapMeters, ...
    config.packetMinOverlapFraction, config.packetMinSeparationMeters, ...
    config.packetMaxNeighborGapMeters, config.packetMaxSpanMeters);
end

function [reviews, config] = selectReviewSession(units, config)
%SELECTREVIEWSESSION 选择本轮记录；旧标签失效不阻断当前数据核查。
% 同名 MAT 被重新写入后，旧记录仍然保留；新的批次使用成对的 run
% 文件名。再次运行相同配置时会找到相符记录，继续该批未完成的核查。
baseOutput = config.outputCsv;
baseSummary = config.summaryCsv;
runIndex = 0;
while true
    outputExists = isfile(config.outputCsv);
    summaryExists = isfile(config.summaryCsv);
    if ~outputExists && ~summaryExists
        reviews = emptyReviews();
        break;
    end
    if config.resumeReviews && outputExists
        try
            saved = loadReviews(config.outputCsv);
            for i = 1:height(saved)
                unitIndex = find( ...
                    string({units.scene_file}) == saved.scene_file(i) & ...
                    string({units.packet_key}) == saved.packet_key(i));
                if saved.source_mat(i) ~= string(config.matPath) || ...
                        numel(unitIndex) ~= 1
                    error('历史记录不属于当前核查数据。');
                end
                verifyStoredSignature(saved(i,:), units(unitIndex));
            end
            reviews = saved;
            break;
        catch
            % 历史记录是可选的续查缓存。读取失败、缺少字段或数据变化
            % 都只使这份缓存失效；不能覆盖旧记录，也不能停止本轮。
        end
    end

    runIndex = runIndex + 1;
    [folder, name, ext] = fileparts(baseOutput);
    config.outputCsv = fullfile(folder, ...
        sprintf('%s_run%03d%s', name, runIndex, ext));
    [folder, name, ext] = fileparts(baseSummary);
    config.summaryCsv = fullfile(folder, ...
        sprintf('%s_run%03d%s', name, runIndex, ext));
end
if runIndex > 0
    fprintf('已保留原有记录，本轮使用独立文件。\n');
end
fprintf('核查记录：%s\n汇总记录：%s\n', ...
    config.outputCsv, config.summaryCsv);
end

function reviews = loadReviews(path)
%LOADREVIEWS 读取历史核查结果，并恢复稳定字段类型。
reviews = emptyReviews();
if ~isfile(path)
    return;
end
loaded = readtable(path, 'TextType', 'string');
required = reviews.Properties.VariableNames;
missing = setdiff(required, loaded.Properties.VariableNames);
if ~isempty(missing)
    error('历史核查 CSV 缺少字段：%s', strjoin(string(missing), ', '));
end
loaded = loaded(:, required);

stringFields = {'source_mat','scene_file','packet_key','feature_indices', ...
    'matched_crest_indices','matched_packet_ranks','mooring_times', ...
    'speed_diffs_mps','group_config','human_label','reviewed_at'};
numericFields = {'scene_id','packet_id','display_packet_id', ...
    'observed_packet_size','matched_crest_count','auto_inversion_count'};
for i = 1:numel(stringFields)
    values = string(loaded.(stringFields{i}));
    values(ismissing(values)) = "";
    loaded.(stringFields{i}) = values;
end
for i = 1:numel(numericFields)
    loaded.(numericFields{i}) = toNumericColumn(loaded.(numericFields{i}));
end
loaded.evaluable = toLogicalColumn(loaded.evaluable);
reviews = loaded;

keys = reviews.source_mat + "|" + reviews.scene_file + "|" + ...
    reviews.packet_key;
if numel(unique(keys)) ~= height(reviews)
    error('历史核查 CSV 中存在重复单元，请先清理重复行：%s', path);
end
end

function reviews = emptyReviews()
%EMPTYREVIEWS 定义核查 CSV 的固定字段和类型。
names = {'source_mat','scene_id','scene_file','packet_key','packet_id', ...
    'display_packet_id','observed_packet_size','matched_crest_count', ...
    'evaluable','feature_indices','matched_crest_indices', ...
    'matched_packet_ranks','mooring_times','speed_diffs_mps', ...
    'auto_inversion_count','group_config','human_label','reviewed_at'};
types = {'string','double','string','string','double','double','double', ...
    'double','logical','string','string','string','string','string', ...
    'double','string','string','string'};
reviews = table('Size', [0,numel(names)], ...
    'VariableTypes', types, 'VariableNames', names);
end

function values = toNumericColumn(values)
%TONUMERICCOLUMN 把 readtable 可能推断成文本的数值列恢复为 double。
if isnumeric(values)
    values = double(values);
else
    values = str2double(string(values));
end
values = values(:);
end

function values = toLogicalColumn(values)
%TOLOGICALCOLUMN 兼容 CSV 中的 0/1、true/false 文本。
if islogical(values)
    values = values(:);
elseif isnumeric(values)
    values = logical(values(:));
else
    text = lower(string(values(:)));
    values = text == "true" | text == "1";
end
end

function [reviews, added] = addSingleMatchRows(reviews, units, sourceMat)
%ADDSINGLEMATCHROWS 自动登记没有先后关系可检验的单匹配单元。
added = 0;
for i = 1:numel(units)
    if units(i).evaluable
        continue;
    end
    existing = findReviewRow(reviews, sourceMat, ...
        units(i).scene_file, units(i).packet_key);
    if ~isempty(existing)
        verifyStoredSignature(reviews(existing,:), units(i));
        continue;
    end
    row = makeReviewRow(units(i), sourceMat, "single_match");
    reviews = appendReview(reviews, row);
    added = added + 1;
end
end

function row = makeReviewRow(unit, sourceMat, label)
%MAKEREVIEWROW 把当前显示内容固化为一行可追溯记录。
row = emptyReviews();
row(1,:) = { ...
    string(sourceMat), ...
    unit.scene_id, ...
    string(unit.scene_file), ...
    string(unit.packet_key), ...
    unit.packet_id, ...
    unit.display_packet_id, ...
    unit.observed_packet_size, ...
    unit.matched_crest_count, ...
    unit.evaluable, ...
    joinNumbers(unit.review_feature_indices, '%.0f'), ...
    joinNumbers(unit.review_crest_indices, '%.0f'), ...
    joinNumbers(unit.packet_ranks, '%.0f'), ...
    joinTimes(unit.review_mooring_times), ...
    joinNumbers(unit.review_speed_diffs, '%.12g'), ...
    unit.auto_inversion_count, ...
    string(unit.group_config), ...
    string(label), ...
    string(datetime('now'), 'yyyy-MM-dd HH:mm:ss')};
end

function values = joinNumbers(values, format)
%JOINNUMBERS 使用分号连接数值，避免与 CSV 字段分隔符混淆。
if isempty(values)
    values = "";
    return;
end
text = arrayfun(@(x) formatNumber(x, format), values(:), ...
    'UniformOutput', false);
values = string(strjoin(text, ';'));
end

function text = formatNumber(value, format)
%FORMATNUMBER 保留 NaN，便于追查缺失诊断。
if isfinite(value)
    text = sprintf(format, value);
else
    text = 'NaN';
end
end

function value = joinTimes(times)
%JOINTIMES 把 datetime 数组写成稳定、可读的文本。
if isempty(times)
    value = "";
    return;
end
text = strings(numel(times),1);
for i = 1:numel(times)
    text(i) = formatTime(times(i));
end
value = strjoin(text, ';');
end

function reviews = appendReview(reviews, row)
%APPENDREVIEW 添加新判断；同一稳定键只允许出现一次。
existing = findReviewRow(reviews, row.source_mat, ...
    row.scene_file, row.packet_key);
if ~isempty(existing)
    error('核查结果已存在，拒绝重复写入：%s / %s', ...
        row.scene_file, row.packet_key);
end
reviews = [reviews; row];
end

function index = findReviewRow(reviews, sourceMat, sceneFile, packetKey)
%FINDREVIEWROW 用“来源 + 影像 + 波包”定位历史判断。
index = find(reviews.source_mat == string(sourceMat) & ...
    reviews.scene_file == string(sceneFile) & ...
    reviews.packet_key == string(packetKey));
end

function verifyStoredSignature(row, unit)
%VERIFYSTOREDSIGNATURE 只有核查内容一致才允许断点续查。
% 到站时刻必须参与比较：同一组波锋换配事件后，旧乱序标签会失效。
expectedCrests = joinNumbers(unit.review_crest_indices, '%.0f');
expectedRanks = joinNumbers(unit.packet_ranks, '%.0f');
if unit.evaluable
    validLabel = ismember(row.human_label, ...
        ["normal","disordered","uncertain"]);
else
    validLabel = row.human_label == "single_match";
end
same = row.matched_crest_indices == expectedCrests && ...
    row.matched_packet_ranks == expectedRanks && ...
    row.mooring_times == joinTimes(unit.review_mooring_times) && ...
    row.speed_diffs_mps == joinNumbers(unit.review_speed_diffs, '%.12g') && ...
    row.matched_crest_count == unit.matched_crest_count && ...
    row.evaluable == unit.evaluable && validLabel && ...
    isequaln(row.auto_inversion_count, unit.auto_inversion_count) && ...
    row.observed_packet_size == unit.observed_packet_size && ...
    row.group_config == unit.group_config;
if ~same
    error(['历史标签的数据签名与当前结果不一致：%s / %s。' ...
        '该文件不适用于当前数据的断点续查。'], ...
        unit.scene_file, unit.packet_key);
end
end

function [reviews, key, scene] = undoLastManualReview( ...
    reviews, sourceMat, undoHistory)
%UNDOLASTMANUALREVIEW 优先撤销本次会话上一条，不跨来源删除。
key = "";
scene = "";
if ~isempty(undoHistory)
    scene = undoHistory(end,1);
    key = undoHistory(end,2);
    index = findReviewRow(reviews, sourceMat, scene, key);
else
    manual = reviews.source_mat == string(sourceMat) & ...
        ismember(reviews.human_label, ...
        ["normal","disordered","uncertain"]);
    index = find(manual, 1, 'last');
    if ~isempty(index)
        scene = reviews.scene_file(index);
        key = reviews.packet_key(index);
    end
end
if isempty(index)
    key = "";
    scene = "";
    return;
end
reviews(index,:) = [];
end

function current = findFirstPendingUnit(units, reviews, sourceMat)
%FINDFIRSTPENDINGUNIT 跳过已完成项和自动登记的单匹配单元。
current = [];
for i = 1:numel(units)
    existing = findReviewRow(reviews, sourceMat, ...
        units(i).scene_file, units(i).packet_key);
    if ~isempty(existing)
        verifyStoredSignature(reviews(existing,:), units(i));
        continue;
    end
    if units(i).evaluable
        current = i;
        return;
    end
end
end

function [summary, reviews] = saveReviewFiles(reviews, units, config)
%SAVEREVIEWFILES 每次判断后同时刷新逐包结果和逐景汇总。
outputDir = fileparts(config.outputCsv);
if ~isempty(outputDir) && ~isfolder(outputDir)
    mkdir(outputDir);
end
summaryDir = fileparts(config.summaryCsv);
if ~isempty(summaryDir) && ~isfolder(summaryDir)
    mkdir(summaryDir);
end

writetable(reviews, config.outputCsv);
summary = buildSceneSummary(units, reviews, config.matPath);
writetable(summary, config.summaryCsv);
end

function summary = buildSceneSummary(units, reviews, sourceMat)
%BUILDSCENESUMMARY 汇总每张影像的人工判断和自动倒序提示。
names = {'source_mat','scene_id','scene_file','review_units', ...
    'single_match_units','evaluable_units','reviewed_evaluable', ...
    'pending_evaluable','normal','disordered','uncertain', ...
    'auto_inversion_units','disorder_rate'};
types = {'string','double','string','double','double','double','double', ...
    'double','double','double','double','double','double'};
summary = table('Size', [0,numel(names)], ...
    'VariableTypes', types, 'VariableNames', names);

sceneIds = unique([units.scene_id], 'stable');
for i = 1:numel(sceneIds)
    mask = [units.scene_id] == sceneIds(i);
    sceneUnits = units(mask);
    labels = strings(numel(sceneUnits),1);
    inversion = nan(numel(sceneUnits),1);
    for j = 1:numel(sceneUnits)
        index = findReviewRow(reviews, sourceMat, ...
            sceneUnits(j).scene_file, sceneUnits(j).packet_key);
        if ~isempty(index)
            labels(j) = reviews.human_label(index);
        end
        inversion(j) = sceneUnits(j).auto_inversion_count;
    end

    evaluable = [sceneUnits.evaluable]';
    normal = nnz(labels == "normal");
    disordered = nnz(labels == "disordered");
    denominator = normal + disordered;
    if denominator > 0
        rate = disordered / denominator;
    else
        rate = NaN;
    end
    summary(end+1,:) = { ...
        string(sourceMat), ...
        sceneIds(i), ...
        string(sceneUnits(1).scene_file), ...
        numel(sceneUnits), ...
        nnz(~evaluable), ...
        nnz(evaluable), ...
        nnz(evaluable & strlength(labels) > 0), ...
        nnz(evaluable & strlength(labels) == 0), ...
        normal, ...
        disordered, ...
        nnz(labels == "uncertain"), ...
        nnz(inversion > 0), ...
        rate}; %#ok<AGROW>
end
end

function hFig = createReviewFigure(config)
%CREATEREVIEWFIGURE 创建固定布局，翻页时不改变图窗尺寸。
hFig = figure( ...
    'Name', '逐景匹配顺序人工核查', ...
    'Color', 'w', ...
    'Visible', config.figureVisible, ...
    'Units', 'pixels', ...
    'Position', [60, 60, 1600, 900]);
% 不使用 TiledChartLayout.RowHeight。该属性并不存在，且不同 MATLAB
% 版本对 tiledlayout 跨格能力的支持不完全一致。归一化坐标能稳定
% 保留上方双图、下方顺序表的 3:1 高度关系。
axOverview = axes(hFig, 'Position', [0.055, 0.31, 0.43, 0.64]);
axPacket = axes(hFig, 'Position', [0.535, 0.31, 0.43, 0.64]);
axText = axes(hFig, 'Position', [0.055, 0.04, 0.91, 0.20]);
setappdata(hFig, 'review_axes', [axOverview, axPacket, axText]);
end

function drawReviewUnit(hFig, crests, packets, matches, unit, reviews, config)
%DRAWREVIEWUNIT 绘制当前整景、候选波包和到站顺序表。
axesList = getappdata(hFig, 'review_axes');
axOverview = axesList(1);
axPacket = axesList(2);
axText = axesList(3);

sceneRows = find(crests.scene_id == unit.scene_id);
colors = lines(max(packets.display_packet_id(sceneRows), [], 'omitnan') + 1);
if isempty(colors)
    colors = lines(1);
end

drawSceneOverview(axOverview, crests, packets, sceneRows, ...
    unit.all_catalog_rows, colors, config);
drawCurrentPacket(axPacket, crests, packets, matches, ...
    sceneRows, unit, colors, config);
drawOrderPanel(axText, crests, matches, unit, reviews, config);
end

function drawSceneOverview(ax, crests, packets, sceneRows, currentRows, colors, config)
%DRAWSCENEOVERVIEW 左侧整景：同包同色，当前单元加粗。
cla(ax);
hold(ax, 'on');
box(ax, 'on');
grid(ax, 'on');
gray = [0.60,0.60,0.60];

for j = 1:numel(sceneRows)
    row = sceneRows(j);
    displayId = packets.display_packet_id(row);
    if displayId > 0
        color = colors(displayId,:);
        style = '-';
        label = sprintf('P%d-R%d / F%d', displayId, ...
            packets.packet_rank(row), crests.feature_index(row));
    else
        color = gray;
        style = '--';
        label = sprintf('U-F%d', crests.feature_index(row));
    end
    if ismember(row, currentRows)
        width = 3.2;
    else
        width = 1.2;
    end
    plot(ax, crests.longitude{row}, crests.latitude{row}, style, ...
        'Color', color, 'LineWidth', width);
    labelCrest(ax, crests.longitude{row}, crests.latitude{row}, label, color);
end

plotMooringIfNear(ax, crests, sceneRows, config);
axis(ax, 'equal');
axis(ax, 'padded');
xlabel(ax, 'Longitude (deg)');
ylabel(ax, 'Latitude (deg)');
title(ax, sprintf('整景：%s', unitFileName(crests, sceneRows)), ...
    'Interpreter', 'none');
subtitle(ax, '同色表示自动归为同一候选波包；加粗线是当前核查单元');
end

function drawCurrentPacket(ax, crests, packets, matches, ...
    sceneRows, unit, colors, config)
%DRAWCURRENTPACKET 右侧突出当前单元，并标明匹配和未匹配成员。
cla(ax);
hold(ax, 'on');
box(ax, 'on');
grid(ax, 'on');

for j = 1:numel(sceneRows)
    row = sceneRows(j);
    plot(ax, crests.longitude{row}, crests.latitude{row}, '-', ...
        'Color', [0.88,0.88,0.88], 'LineWidth', 0.7);
end

if unit.display_packet_id > 0
    color = colors(unit.display_packet_id,:);
    packetTitle = sprintf('候选波包 P%d', unit.display_packet_id);
else
    color = [0.15,0.15,0.15];
    packetTitle = sprintf('未归包单条 %s', unit.packet_key);
end

for j = 1:numel(unit.all_catalog_rows)
    row = unit.all_catalog_rows(j);
    matchPosition = find(unit.matched_catalog_rows == row, 1);
    if isempty(matchPosition)
        style = '--';
        width = 1.8;
        rank = packetRankForRow(packets, row);
        label = sprintf('R%d / C%d / F%d / 未匹配', rank, ...
            crests.crest_idx(row), crests.feature_index(row));
    else
        style = '-';
        width = 3.4;
        matchRow = unit.match_rows(matchPosition);
        rank = unit.packet_ranks(matchPosition);
        label = sprintf('R%d / C%d / F%d / %s / dv=%.3g', ...
            rank, crests.crest_idx(row), crests.feature_index(row), ...
            formatTime(matches.mooring_time(matchRow)), ...
            matches.speed_diff(matchRow));
    end
    plot(ax, crests.longitude{row}, crests.latitude{row}, style, ...
        'Color', color, 'LineWidth', width);
    labelCrest(ax, crests.longitude{row}, crests.latitude{row}, label, color);
end

plotMooringIfNear(ax, crests, sceneRows, config);
axis(ax, 'equal');
axis(ax, 'padded');
xlabel(ax, 'Longitude (deg)');
ylabel(ax, 'Latitude (deg)');
title(ax, packetTitle);
subtitle(ax, sprintf('实线=%d 条已有匹配，虚线=同包未匹配；自动倒序对数=%s', ...
    unit.matched_crest_count, formatCount(unit.auto_inversion_count)));
end

function rank = packetRankForRow(packets, row)
%PACKETRANKFORROW 未归包单条在显示时使用 R1。
rank = packets.packet_rank(row);
if ~isfinite(rank)
    rank = 1;
end
end

function drawOrderPanel(ax, crests, matches, unit, reviews, config)
%DRAWORDERPANEL 下方按空间顺序列出匹配，供人工直接比较时刻。
cla(ax);
axis(ax, [0,1,0,1]);
axis(ax, 'off');

reviewed = nnz(reviews.source_mat == string(config.matPath) & ...
    ismember(reviews.human_label, ["normal","disordered","uncertain"]));
header = sprintf(['空间顺序 -> 到站时刻（使用 mooring_time）    ' ...
    '已人工判断 %d 个    当前自动倒序对数：%s'], ...
    reviewed, formatCount(unit.auto_inversion_count));
text(ax, 0.01, 0.92, header, ...
    'FontWeight', 'bold', 'FontSize', 11, ...
    'Interpreter', 'none', 'VerticalAlignment', 'top');

lines = strings(unit.matched_crest_count + 1, 1);
lines(1) = "Rank   crest_idx   feature   mooring_time          speed_diff";
for i = 1:unit.matched_crest_count
    matchRow = unit.match_rows(i);
    catalogRow = unit.matched_catalog_rows(i);
    lines(i+1) = sprintf('%-6d %-11d %-9d %-21s %.6g', ...
        unit.packet_ranks(i), ...
        crests.crest_idx(catalogRow), ...
        crests.feature_index(catalogRow), ...
        formatTime(matches.mooring_time(matchRow)), ...
        matches.speed_diff(matchRow));
end
text(ax, 0.01, 0.72, strjoin(lines, newline), ...
    'FontName', 'Courier New', 'FontSize', 10, ...
    'Interpreter', 'none', 'VerticalAlignment', 'top');

controls = ['N 正常    D 乱序    U 无法判断    ' ...
    'Z 撤销上一条    Q 保存并退出'];
text(ax, 0.99, 0.08, controls, ...
    'HorizontalAlignment', 'right', 'FontWeight', 'bold', ...
    'FontSize', 11, 'Interpreter', 'none');
end

function labelCrest(ax, lon, lat, label, color)
%LABELCREST 在折线中间的有效点旁标注核查信息。
good = isfinite(lon) & isfinite(lat);
indices = find(good);
if isempty(indices)
    return;
end
mid = indices(ceil(numel(indices)/2));
text(ax, lon(mid), lat(mid), [' ' label], ...
    'Color', color, 'FontSize', 8.5, 'FontWeight', 'bold', ...
    'Interpreter', 'none', 'Clipping', 'on');
end

function plotMooringIfNear(ax, crests, sceneRows, config)
%PLOTMOORINGIFNEAR 站点在整景附近时才绘制，避免拉伸坐标轴。
lon = vertcatFinite(crests.longitude(sceneRows));
lat = vertcatFinite(crests.latitude(sceneRows));
if isempty(lon) || isempty(lat)
    return;
end
paddingLon = max(0.05, 0.1*range(lon));
paddingLat = max(0.05, 0.1*range(lat));
inside = config.mooringLon >= min(lon)-paddingLon && ...
    config.mooringLon <= max(lon)+paddingLon && ...
    config.mooringLat >= min(lat)-paddingLat && ...
    config.mooringLat <= max(lat)+paddingLat;
if inside
    plot(ax, config.mooringLon, config.mooringLat, 'rp', ...
        'MarkerFaceColor', 'r', 'MarkerSize', 12);
end
end

function values = vertcatFinite(cells)
%VERTCATFINITE 合并坐标 cell 并删除非有限值。
values = vertcat(cells{:});
values = values(isfinite(values));
end

function name = unitFileName(crests, sceneRows)
%UNITFILENAME 返回当前影像文件名。
name = char(crests.scene_file(sceneRows(1)));
end

function value = formatTime(time)
%FORMATTIME 使用固定格式显示时间，缺失值明确标为 NaT。
if isnat(time)
    value = 'NaT';
else
    value = char(time, 'yyyy-MM-dd HH:mm:ss');
end
end

function value = formatCount(count)
%FORMATCOUNT 友好显示不可计算的倒序对数。
if isfinite(count)
    value = sprintf('%d', count);
else
    value = 'N/A';
end
end

function printInventory(units)
%PRINTINVENTORY 非交互模式仅报告核查队列规模。
evaluable = [units.evaluable];
fprintf('核查单元：%d；可检验顺序：%d；单匹配：%d。\n', ...
    numel(units), nnz(evaluable), nnz(~evaluable));
end

function printFinalSummary(units, reviews, sourceMat, quitRequested)
%PRINTFINALSUMMARY 退出或完成后打印当前人工核查统计。
labels = strings(numel(units),1);
for i = 1:numel(units)
    index = findReviewRow(reviews, sourceMat, ...
        units(i).scene_file, units(i).packet_key);
    if ~isempty(index)
        labels(i) = reviews.human_label(index);
    end
end
normal = nnz(labels == "normal");
disordered = nnz(labels == "disordered");
uncertain = nnz(labels == "uncertain");
single = nnz(labels == "single_match");
pending = nnz([units.evaluable]' & strlength(labels) == 0);
denominator = normal + disordered;
if denominator > 0
    rateText = sprintf('%.2f%%', 100*disordered/denominator);
else
    rateText = 'N/A';
end

if quitRequested
    state = '已中途退出';
else
    state = '本轮已完成';
end
fprintf(['\n%s。正常 %d，乱序 %d，无法判断 %d，单匹配 %d，' ...
    '待判断 %d，乱序率 %s。\n'], ...
    state, normal, disordered, uncertain, single, pending, rateText);
end

function result = buildResult(config, crests, packets, matches, units, ...
    reviews, summary, figureHandle, quitRequested)
%BUILDRESULT 返回可供后续统计或调试的完整核查状态。
result = struct();
result.config = config;
result.crests = crests;
result.packets = packets;
result.matches = matches;
result.units = units;
result.reviews = reviews;
result.scene_summary = summary;
result.figure = figureHandle;
result.quit_requested = quitRequested;
end
