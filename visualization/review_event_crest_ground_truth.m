function result = review_event_crest_ground_truth(config)
%REVIEW_EVENT_CREST_GROUND_TRUTH 按系泊事件建立波锋人工参考集。
%
% 直接运行：
%   result = review_event_crest_ground_truth();
%
% 只做全量库存自检，不打开图窗、不读写人工标签：
%   result = review_event_crest_ground_truth(struct('interactive', false));
%
% 每个页面对应一个系泊事件，显示该事件前后 windowDays 天内的全部
% SHP 波锋。当前自动匹配波锋单独强调；未被自动结果使用的波锋按
% 事件前后分色，并标注 crest_idx、观测时间和相对时差。
%
% Figure 内操作：
%   点击波锋或输入 crest_idx 后点“查看”，刷新双最近点和速度诊断。
%   只有“确认对应”“无对应”“无法判断”等明确操作才会写入动作。
%   支持跳过、撤销和保存退出。
%
% 每次人工判断都会立即写入 CSV。再次运行时自动从第一个未标事件
% 继续。若输入 MAT、系泊表、SHP 目录或时间窗变化，旧 CSV 会保留，
% 新批次自动写入带 _run001 等后缀的文件。
%
% 本工具不修改自动匹配 MAT。输出是专家参考集，不是零误差真值。

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(projectRoot, 'utils')));

if nargin < 1 || isempty(config)
    config = struct();
end
config = applyDefaults(config, projectRoot);

fprintf('读取系泊事件：%s\n', config.mooringPath);
events = readEvents(config.mooringPath);

fprintf('按生产顺序重建 SHP 波锋目录：%s\n', config.shpDir);
crests = buildCrestReviewCatalog( ...
    config.shpDir, config.timeOffsetHours, true);

fprintf('读取当前自动匹配：%s\n', config.matPath);
matches = readAutomaticMatches(config.matPath, events, crests);
units = buildReviewUnits(events, crests, matches, config.windowDays);
dataSignature = buildDataSignature(config, events, crests, matches);
reviews = emptyReviews();

% 非交互模式只验证输入和全量事件队列，不读取或写入历史标签。
if ~config.interactive
    printInventory(events, crests, matches, units, config.windowDays);
    result = buildResult(config, events, crests, matches, units, ...
        reviews, dataSignature, [], false);
    return;
end

[reviews, config] = selectReviewSession( ...
    config, dataSignature, events, crests, units);
hFig = createReviewFigure(config);
undoHistory = zeros(0,1);
sessionSkipped = zeros(0,1);
quitRequested = false;

while isgraphics(hFig)
    current = findFirstPendingUnit( ...
        units, reviews, sessionSkipped);
    if isempty(current)
        break;
    end

    unit = units(current);
    drawReviewUnit(hFig, events, crests, matches, unit, ...
        reviews, sessionSkipped, config);
    drawnow;
    uiwait(hFig);
    if ~isgraphics(hFig)
        quitRequested = true;
        break;
    end

    action = getappdata(hFig, 'review_action');
    switch action.type
        case "confirmed_match"
            label = "confirmed_match";
            selectedCrestIdx = action.crest_idx;
        case "confirmed_no_match"
            label = "confirmed_no_match";
            selectedCrestIdx = NaN;
        case "uncertain"
            label = "uncertain";
            selectedCrestIdx = NaN;
        case "skip"
            if ~ismember(unit.event_id, sessionSkipped)
                sessionSkipped(end+1,1) = unit.event_id; %#ok<AGROW>
            end
            fprintf('本次会话跳过事件 %d。\n', unit.event_id);
            continue;
        case "undo"
            [reviews, undoneEventId] = undoLastReview( ...
                reviews, undoHistory);
            if isempty(undoneEventId)
                fprintf('没有可撤销的人工判断。\n');
            else
                if ~isempty(undoHistory)
                    undoHistory(end) = [];
                end
                saveReviews(reviews, config.outputCsv);
                fprintf('已撤销事件 %d 的人工判断。\n', ...
                    undoneEventId);
            end
            continue;
        case "quit"
            quitRequested = true;
            break;
        otherwise
            continue;
    end

    row = makeReviewRow(unit, events, crests, matches, ...
        selectedCrestIdx, label, config, dataSignature);
    reviews = appendReview(reviews, row);
    undoHistory(end+1,1) = unit.event_id; %#ok<AGROW>
    saveReviews(reviews, config.outputCsv);
    fprintf('已保存事件 %d：%s。\n', ...
        unit.event_id, describeReview(label, selectedCrestIdx));
end

printFinalSummary(units, reviews, sessionSkipped, quitRequested);
result = buildResult(config, events, crests, matches, units, ...
    reviews, dataSignature, hFig, quitRequested);
end

function config = applyDefaults(config, projectRoot)
%APPLYDEFAULTS 汇总数据入口、时间窗和输出设置。
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
    'mooringPath', fullfile(projectRoot, 'data', ...
        '月份挑内波数据', '2020年内波时间与方向.xlsx'), ...
    'shpDir', fullfile(projectRoot, 'data', 'shp_files'), ...
    'outputCsv', fullfile(projectRoot, 'diagnostics', ...
        'event_crest_ground_truth.csv'), ...
    'windowDays', 3, ...
    'timeOffsetHours', 8, ...
    'mooringLat', 20.816666666666666, ...
    'mooringLon', 115.76666666666667, ...
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
config.mooringPath = resolveProjectPath( ...
    config.mooringPath, projectRoot);
config.shpDir = resolveProjectPath(config.shpDir, projectRoot);
config.outputCsv = resolveProjectPath(config.outputCsv, projectRoot);

if ~isfile(config.matPath)
    error('自动匹配 MAT 不存在：%s', config.matPath);
end
if ~isfile(config.mooringPath)
    error('系泊事件表不存在：%s', config.mooringPath);
end
if ~isfolder(config.shpDir)
    error('SHP 目录不存在：%s', config.shpDir);
end
validateattributes(config.windowDays, {'numeric'}, ...
    {'scalar','finite','positive','real'});
validateattributes(config.timeOffsetHours, {'numeric'}, ...
    {'scalar','finite','real'});
validateattributes(config.mooringLat, {'numeric'}, ...
    {'scalar','finite','real'});
validateattributes(config.mooringLon, {'numeric'}, ...
    {'scalar','finite','real'});
validateattributes(config.interactive, {'logical'}, {'scalar'});
validateattributes(config.resumeReviews, {'logical'}, {'scalar'});
if ~ismember(string(config.figureVisible), ["on","off"])
    error('figureVisible 必须是 ''on'' 或 ''off''。');
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

function events = readEvents(mooringPath)
%READEVENTS 读取并验证系泊事件表的前五列。
source = readtable(mooringPath);
if width(source) < 5
    error('系泊事件表至少需要五列。');
end

eventId = (1:height(source))';
mode = double(source{:,1});
startTime = toEventDatetime(source{:,2});
endTime = toEventDatetime(source{:,3});
localSpeedMps = double(source{:,4});
directionDeg = double(source{:,5});

valid = ismember(mode, [1 2]) & ~isnat(startTime) & ...
    ~isnat(endTime) & endTime >= startTime & ...
    isfinite(localSpeedMps) & localSpeedMps > 0 & ...
    isfinite(directionDeg);
if ~all(valid)
    bad = eventId(~valid);
    error('系泊事件表存在无效行：%s', ...
        strjoin(string(bad(1:min(20,numel(bad)))), ', '));
end
if numel(unique(startTime)) ~= numel(startTime)
    error('系泊事件起始时刻存在重复，无法稳定关联当前 MAT。');
end

events = table(eventId, mode, startTime, endTime, ...
    localSpeedMps, directionDeg, ...
    'VariableNames', {'event_id','mode','start_time','end_time', ...
    'local_speed_mps','direction_deg'});
end

function value = toEventDatetime(value)
%TOEVENTDATETIME 兼容 readtable 返回的 datetime、Excel 数值或文本。
if isdatetime(value)
    value = value(:);
elseif isnumeric(value)
    value = datetime(value(:), 'ConvertFrom', 'excel');
else
    value = datetime(string(value(:)));
end
end

function value = toMatDatetime(value)
%TOMATDATETIME 兼容 MAT 中的 datetime、datenum 或文本。
if isdatetime(value)
    value = value(:);
elseif isnumeric(value)
    value = datetime(value(:), 'ConvertFrom', 'datenum');
else
    value = datetime(string(value(:)));
end
end

function matches = readAutomaticMatches(matPath, events, crests)
%READAUTOMATICMATCHES 将当前自动结果映射回系泊事件编号。
data = load(matPath);
required = {'crest_idx','mooring_time','crest_time','mode'};
missing = required(~isfieldMany(data, required));
if ~isempty(missing)
    error('自动匹配 MAT 缺少字段：%s', ...
        strjoin(string(missing), ', '));
end

n = numel(data.crest_idx);
fields = {'mooring_time','crest_time','mode'};
for i = 1:numel(fields)
    if numel(data.(fields{i})) ~= n
        error('MAT 字段 %s 的长度与 crest_idx 不一致。', ...
            fields{i});
    end
end

crestIdx = double(data.crest_idx(:));
mooringTime = toMatDatetime(data.mooring_time);
crestTime = toMatDatetime(data.crest_time);
mode = double(data.mode(:));
if any(~isfinite(crestIdx) | crestIdx < 1 | ...
        crestIdx ~= round(crestIdx))
    error('MAT 中的 crest_idx 必须是正整数。');
end
if numel(unique(crestIdx)) ~= n
    error('MAT 中存在重复 crest_idx。');
end

[found, catalogRow] = ismember(crestIdx, crests.crest_idx);
if ~all(found)
    error('MAT 中有 %d 个 crest_idx 超出当前 SHP 目录。', ...
        nnz(~found));
end
crestTimeError = abs(seconds( ...
    crestTime - crests.sensing_time(catalogRow)));
if any(~isfinite(crestTimeError) | crestTimeError > 1)
    error('MAT 的 crest_idx 与当前 SHP 观测时刻不一致。');
end

eventId = nan(n,1);
for i = 1:n
    timeError = abs(seconds(events.start_time - mooringTime(i)));
    [minimum, row] = min(timeError);
    if isempty(row) || ~isfinite(minimum) || minimum > 1
        error('MAT 第 %d 条匹配无法关联到系泊事件表。', i);
    end
    if events.mode(row) ~= mode(i)
        error('MAT 第 %d 条匹配的模态与系泊事件表不一致。', i);
    end
    eventId(i) = events.event_id(row);
end
if numel(unique(eventId)) ~= n
    error('自动结果中同一系泊事件被重复匹配。');
end

matches = table((1:n)', crestIdx, catalogRow, eventId, ...
    mooringTime, crestTime, mode, ...
    'VariableNames', {'match_row','crest_idx','catalog_row', ...
    'event_id','mooring_time','crest_time','mode'});
end

function mask = isfieldMany(value, names)
%ISFIELDMANY 对一组字段名执行 isfield。
mask = false(size(names));
for i = 1:numel(names)
    mask(i) = isfield(value, names{i});
end
end

function units = buildReviewUnits(events, crests, matches, windowDays)
%BUILDREVIEWUNITS 为每个系泊事件建立前后固定时间窗的全部波锋清单。
template = struct( ...
    'event_id', NaN, ...
    'candidate_rows', [], ...
    'candidate_crest_indices', [], ...
    'candidate_count', 0, ...
    'unmatched_count', 0, ...
    'automatic_crest_idx', NaN);
units = repmat(template, height(events), 1);
globallyMatched = ismember(crests.crest_idx, matches.crest_idx);

for i = 1:height(events)
    delta = crests.sensing_time - events.start_time(i);
    rows = find(abs(delta) <= days(windowDays));
    if ~isempty(rows)
        [~, order] = sortrows( ...
            [posixtime(crests.sensing_time(rows)), ...
            crests.crest_idx(rows)], [1 2]);
        rows = rows(order);
    end

    matchRow = find(matches.event_id == events.event_id(i));
    autoCrest = NaN;
    if ~isempty(matchRow)
        autoCrest = matches.crest_idx(matchRow);
        if ~ismember(autoCrest, crests.crest_idx(rows))
            error(['事件 %d 的自动匹配波锋不在前后 %.1f 天范围内，' ...
                '请核对时间窗。'], events.event_id(i), windowDays);
        end
    end

    units(i).event_id = events.event_id(i);
    units(i).candidate_rows = rows(:);
    units(i).candidate_crest_indices = crests.crest_idx(rows);
    units(i).candidate_count = numel(rows);
    units(i).unmatched_count = nnz(~globallyMatched(rows));
    units(i).automatic_crest_idx = autoCrest;
end
end

function signature = buildDataSignature(config, events, crests, matches)
%BUILDDATASIGNATURE 生成断点续标所需的数据版本签名。
eventText = compose('%.0f|%.0f|%.6f|%.6f|%.12g|%.12g', ...
    events.event_id, events.mode, posixtime(events.start_time), ...
    posixtime(events.end_time), events.local_speed_mps, ...
    events.direction_deg);
crestText = compose('%.0f|%s|%.0f|%.6f', ...
    crests.crest_idx, crests.scene_file, crests.feature_index, ...
    posixtime(crests.sensing_time));
matchText = compose('%.0f|%.0f', ...
    matches.event_id, matches.crest_idx);

parts = [ ...
    "schema=event-crest-ground-truth-v1"; ...
    "window_days="+string(sprintf('%.12g', config.windowDays)); ...
    "time_offset_hours="+string(sprintf('%.12g', ...
        config.timeOffsetHours)); ...
    "mooring="+fileStamp(config.mooringPath); ...
    "match_mat="+fileStamp(config.matPath); ...
    "events="+stableChecksum(eventText); ...
    "crests="+stableChecksum(crestText); ...
    "matches="+stableChecksum(matchText)];
signature = strjoin(parts, ';');
end

function stamp = fileStamp(path)
%FILESTAMP 用路径、大小和修改时间描述输入文件版本。
info = dir(path);
if isempty(info)
    error('无法读取文件版本：%s', path);
end
stamp = string(path) + "|" + string(info.bytes) + "|" + ...
    string(sprintf('%.12f', info.datenum));
end

function checksum = stableChecksum(lines)
%STABLECHECKSUM 计算可跨会话复现的轻量文本校验值。
prime = 4294967291;
state = 2166136261;
text = char(strjoin(string(lines(:)), newline));
for i = 1:numel(text)
    state = mod(state * 65599 + double(text(i)), prime);
end
checksum = string(sprintf('%010.0f', state));
end

function [reviews, config] = selectReviewSession( ...
    config, dataSignature, events, crests, units)
%SELECTREVIEWSESSION 只续用数据签名完整一致的人工标签。
baseOutput = config.outputCsv;
runIndex = 0;
while true
    if ~isfile(config.outputCsv)
        reviews = emptyReviews();
        break;
    end
    if config.resumeReviews
        try
            saved = loadReviews(config.outputCsv);
            verifyStoredReviews(saved, dataSignature, ...
                events, crests, units);
            reviews = saved;
            break;
        catch
            % 旧文件保留原位；数据变化或文件损坏时另开新批次。
        end
    end

    runIndex = runIndex + 1;
    config.outputCsv = addRunSuffix(baseOutput, runIndex);
end
if runIndex > 0
    fprintf('已保留原有记录，本轮使用独立文件。\n');
end
fprintf('人工参考集：%s\n', config.outputCsv);
end

function path = addRunSuffix(basePath, runIndex)
%ADDRUNSUFFIX 为新标注批次生成不覆盖旧文件的路径。
[folder, name, ext] = fileparts(basePath);
if isempty(ext)
    ext = '.csv';
end
path = fullfile(folder, ...
    sprintf('%s_run%03d%s', name, runIndex, ext));
end

function reviews = emptyReviews()
%EMPTYREVIEWS 定义人工参考集 CSV 的固定字段与类型。
names = {'dataset_signature','source_mooring','source_mat', ...
    'window_days','event_id','event_mode','event_start_time', ...
    'event_end_time','local_speed_mps','direction_deg', ...
    'candidate_crest_count','unmatched_crest_count', ...
    'automatic_crest_idx','human_label','selected_crest_idx', ...
    'selected_scene_file','selected_feature_index', ...
    'selected_sensing_time','selected_was_unmatched','reviewed_at'};
types = {'string','string','string','double','double','double', ...
    'string','string','double','double','double','double','double', ...
    'string','double','string','double','string','logical','string'};
reviews = table('Size', [0,numel(names)], ...
    'VariableTypes', types, 'VariableNames', names);
end

function reviews = loadReviews(path)
%LOADREVIEWS 读取历史 CSV，并恢复固定字段类型。
reviews = emptyReviews();
loaded = readtable(path, 'TextType', 'string');
required = reviews.Properties.VariableNames;
missing = setdiff(required, loaded.Properties.VariableNames);
if ~isempty(missing)
    error('历史人工参考集缺少字段：%s', ...
        strjoin(string(missing), ', '));
end
loaded = loaded(:, required);

stringFields = {'dataset_signature','source_mooring','source_mat', ...
    'event_start_time','event_end_time','human_label', ...
    'selected_scene_file','selected_sensing_time','reviewed_at'};
numericFields = {'window_days','event_id','event_mode', ...
    'local_speed_mps','direction_deg','candidate_crest_count', ...
    'unmatched_crest_count','automatic_crest_idx', ...
    'selected_crest_idx','selected_feature_index'};
for i = 1:numel(stringFields)
    values = string(loaded.(stringFields{i}));
    values(ismissing(values)) = "";
    loaded.(stringFields{i}) = values;
end
for i = 1:numel(numericFields)
    loaded.(numericFields{i}) = ...
        toNumericColumn(loaded.(numericFields{i}));
end
loaded.selected_was_unmatched = ...
    toLogicalColumn(loaded.selected_was_unmatched);
reviews = loaded;
end

function values = toNumericColumn(values)
%TONUMERICCOLUMN 把 readtable 推断出的文本数值恢复为 double。
if isnumeric(values)
    values = double(values);
else
    values = str2double(string(values));
end
values = values(:);
end

function values = toLogicalColumn(values)
%TOLOGICALCOLUMN 兼容 CSV 中的 0/1 和 true/false。
if islogical(values)
    values = values(:);
elseif isnumeric(values)
    values = logical(values(:));
else
    text = lower(string(values(:)));
    values = text == "true" | text == "1";
end
end

function verifyStoredReviews( ...
    reviews, dataSignature, events, crests, units)
%VERIFYSTOREDREVIEWS 确认历史标签仍对应同一数据和同一事件页面。
if isempty(reviews)
    return;
end
if any(reviews.dataset_signature ~= dataSignature)
    error('历史人工参考集的数据版本与当前输入不一致。');
end
if numel(unique(reviews.event_id)) ~= height(reviews)
    error('历史人工参考集中存在重复 event_id。');
end
validLabels = ["confirmed_match","confirmed_no_match","uncertain"];
if any(~ismember(reviews.human_label, validLabels))
    error('历史人工参考集包含无效标签。');
end

for i = 1:height(reviews)
    eventId = reviews.event_id(i);
    if ~isfinite(eventId) || eventId ~= round(eventId) || ...
            eventId < 1 || eventId > height(events)
        error('历史人工参考集包含无效 event_id。');
    end
    unit = units(eventId);
    sameEvent = reviews.event_mode(i) == events.mode(eventId) && ...
        reviews.event_start_time(i) == ...
        string(events.start_time(eventId), 'yyyy-MM-dd HH:mm:ss') && ...
        reviews.event_end_time(i) == ...
        string(events.end_time(eventId), 'yyyy-MM-dd HH:mm:ss') && ...
        reviews.candidate_crest_count(i) == unit.candidate_count && ...
        reviews.unmatched_crest_count(i) == unit.unmatched_count && ...
        isequaln(reviews.automatic_crest_idx(i), ...
        unit.automatic_crest_idx);
    if ~sameEvent
        error('事件 %d 的历史标签签名已失效。', eventId);
    end

    if reviews.human_label(i) == "confirmed_match"
        crestIdx = reviews.selected_crest_idx(i);
        if ~ismember(crestIdx, unit.candidate_crest_indices)
            error('事件 %d 的历史波锋不在当前时间窗。', eventId);
        end
        crestRow = find(crests.crest_idx == crestIdx, 1);
        sameCrest = reviews.selected_scene_file(i) == ...
            crests.scene_file(crestRow) && ...
            reviews.selected_feature_index(i) == ...
            crests.feature_index(crestRow) && ...
            reviews.selected_sensing_time(i) == ...
            string(crests.sensing_time(crestRow), ...
            'yyyy-MM-dd HH:mm:ss');
        if ~sameCrest
            error('事件 %d 的历史波锋签名已失效。', eventId);
        end
    elseif isfinite(reviews.selected_crest_idx(i))
        error('非匹配标签不应包含 selected_crest_idx。');
    end
end
end

function current = findFirstPendingUnit(units, reviews, sessionSkipped)
%FINDFIRSTPENDINGUNIT 返回首个未标且未在本次会话跳过的事件。
reviewed = reviews.event_id;
current = [];
for i = 1:numel(units)
    eventId = units(i).event_id;
    if ~ismember(eventId, reviewed) && ...
            ~ismember(eventId, sessionSkipped)
        current = i;
        return;
    end
end
end

function tf = confirmConflictingSelection( ...
    hFig, crestIdx, eventId, reviews, matches)
%CONFIRMCONFLICTINGSELECTION 同一波锋跨事件复用时给出明确警告。
manualConflict = reviews.event_id( ...
    reviews.human_label == "confirmed_match" & ...
    reviews.selected_crest_idx == crestIdx & ...
    reviews.event_id ~= eventId);
automaticConflict = matches.event_id( ...
    matches.crest_idx == crestIdx & matches.event_id ~= eventId);
conflicts = unique([manualConflict; automaticConflict]);
if isempty(conflicts)
    tf = true;
    return;
end

fprintf(['警告：波锋 %d 已关联到其他事件：%s。' ...
    '继续会形成跨事件冲突。\n'], ...
    crestIdx, strjoin(string(conflicts'), ', '));
message = sprintf(['波锋 %d 已关联到其他事件：%s。\n' ...
    '继续会形成跨事件冲突。'], ...
    crestIdx, strjoin(string(conflicts'), ', '));
response = questdlg(message, '波锋冲突', ...
    '仍然保存', '取消', '取消');
tf = strcmp(response, '仍然保存');
if ~tf && isgraphics(hFig)
    setReviewStatus(hFig, '已取消冲突配对。', false);
end
end

function row = makeReviewRow(unit, events, crests, matches, ...
    selectedCrestIdx, label, config, dataSignature)
%MAKEREVIEWROW 将当前事件页面和人工判断固化为可追溯记录。
eventId = unit.event_id;
selectedSceneFile = "";
selectedFeatureIndex = NaN;
selectedSensingTime = "";
selectedWasUnmatched = false;

if label == "confirmed_match"
    crestRow = find(crests.crest_idx == selectedCrestIdx, 1);
    selectedSceneFile = crests.scene_file(crestRow);
    selectedFeatureIndex = crests.feature_index(crestRow);
    selectedSensingTime = string( ...
        crests.sensing_time(crestRow), 'yyyy-MM-dd HH:mm:ss');
    selectedWasUnmatched = ~ismember(selectedCrestIdx, matches.crest_idx);
end

row = emptyReviews();
row(1,:) = { ...
    string(dataSignature), ...
    string(config.mooringPath), ...
    string(config.matPath), ...
    config.windowDays, ...
    eventId, ...
    events.mode(eventId), ...
    string(events.start_time(eventId), 'yyyy-MM-dd HH:mm:ss'), ...
    string(events.end_time(eventId), 'yyyy-MM-dd HH:mm:ss'), ...
    events.local_speed_mps(eventId), ...
    events.direction_deg(eventId), ...
    unit.candidate_count, ...
    unit.unmatched_count, ...
    unit.automatic_crest_idx, ...
    string(label), ...
    selectedCrestIdx, ...
    selectedSceneFile, ...
    selectedFeatureIndex, ...
    selectedSensingTime, ...
    selectedWasUnmatched, ...
    string(datetime('now'), 'yyyy-MM-dd HH:mm:ss')};
end

function reviews = appendReview(reviews, row)
%APPENDREVIEW 同一事件只允许存在一条人工判断。
if any(reviews.event_id == row.event_id)
    error('事件 %d 已存在人工判断，拒绝重复写入。', row.event_id);
end
reviews = [reviews; row];
end

function [reviews, eventId] = undoLastReview(reviews, undoHistory)
%UNDOLASTREVIEW 优先撤销本次会话上一条，否则撤销 CSV 最后一条。
eventId = [];
if isempty(reviews)
    return;
end
if ~isempty(undoHistory)
    target = undoHistory(end);
    index = find(reviews.event_id == target, 1);
else
    index = height(reviews);
end
if isempty(index)
    return;
end
eventId = reviews.event_id(index);
reviews(index,:) = [];
end

function saveReviews(reviews, outputCsv)
%SAVEREVIEWS 每次操作后立即刷新人工参考集 CSV。
outputDir = fileparts(outputCsv);
if ~isempty(outputDir) && ~isfolder(outputDir)
    mkdir(outputDir);
end
writetable(reviews, outputCsv);
end

function hFig = createReviewFigure(config)
%CREATEREVIEWFIGURE 创建地图、诊断面板和图内标注控件。
hFig = figure( ...
    'Name', '系泊事件与波锋人工参考集', ...
    'Tag', 'event-crest-review', ...
    'Color', 'w', ...
    'Visible', config.figureVisible, ...
    'Units', 'pixels', ...
    'Position', [40, 50, 1650, 920], ...
    'CloseRequestFcn', @onCloseReviewFigure);
axMap = axes(hFig, 'Position', [0.045, 0.07, 0.68, 0.88]);
axInfo = axes(hFig, 'Position', [0.75, 0.62, 0.23, 0.32]);
axDiagnostic = axes(hFig, 'Position', [0.75, 0.30, 0.23, 0.29]);
controlPanel = uipanel(hFig, ...
    'Title', '人工标注', ...
    'Units', 'normalized', ...
    'Position', [0.745, 0.035, 0.235, 0.23], ...
    'BackgroundColor', 'w');

uicontrol(controlPanel, 'Style', 'text', ...
    'String', 'crest_idx', ...
    'Units', 'normalized', ...
    'Position', [0.03,0.81,0.24,0.13], ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w', ...
    'FontWeight', 'bold');
controls.input = uicontrol(controlPanel, 'Style', 'edit', ...
    'Tag', 'crest-input', ...
    'Units', 'normalized', ...
    'Position', [0.27,0.80,0.43,0.16], ...
    'BackgroundColor', 'w', ...
    'FontSize', 10, ...
    'KeyPressFcn', @(~,event) onCrestInputKey(hFig, event));
controls.view = uicontrol(controlPanel, 'Style', 'pushbutton', ...
    'Tag', 'view-crest', 'String', '查看', ...
    'Units', 'normalized', ...
    'Position', [0.73,0.80,0.24,0.16], ...
    'Callback', @(~,~) onViewCrest(hFig));
controls.confirm = uicontrol(controlPanel, 'Style', 'pushbutton', ...
    'Tag', 'confirm-match', 'String', '确认对应', ...
    'Units', 'normalized', ...
    'Position', [0.03,0.59,0.45,0.16], ...
    'Callback', @(~,~) onConfirmMatch(hFig));
controls.noMatch = uicontrol(controlPanel, 'Style', 'pushbutton', ...
    'Tag', 'no-match', 'String', '无对应', ...
    'Units', 'normalized', ...
    'Position', [0.52,0.59,0.45,0.16], ...
    'Callback', @(~,~) resumeWithAction(hFig, ...
    struct('type',"confirmed_no_match",'crest_idx',NaN)));
controls.uncertain = uicontrol(controlPanel, 'Style', 'pushbutton', ...
    'Tag', 'uncertain', 'String', '无法判断', ...
    'Units', 'normalized', ...
    'Position', [0.03,0.38,0.45,0.16], ...
    'Callback', @(~,~) resumeWithAction(hFig, ...
    struct('type',"uncertain",'crest_idx',NaN)));
controls.skip = uicontrol(controlPanel, 'Style', 'pushbutton', ...
    'Tag', 'skip', 'String', '跳过', ...
    'Units', 'normalized', ...
    'Position', [0.52,0.38,0.45,0.16], ...
    'Callback', @(~,~) resumeWithAction(hFig, ...
    struct('type',"skip",'crest_idx',NaN)));
controls.undo = uicontrol(controlPanel, 'Style', 'pushbutton', ...
    'Tag', 'undo', 'String', '撤销', ...
    'Units', 'normalized', ...
    'Position', [0.03,0.17,0.45,0.16], ...
    'Callback', @(~,~) resumeWithAction(hFig, ...
    struct('type',"undo",'crest_idx',NaN)));
controls.quit = uicontrol(controlPanel, 'Style', 'pushbutton', ...
    'Tag', 'quit', 'String', '保存退出', ...
    'Units', 'normalized', ...
    'Position', [0.52,0.17,0.45,0.16], ...
    'Callback', @(~,~) resumeWithAction(hFig, ...
    struct('type',"quit",'crest_idx',NaN)));
controls.status = uicontrol(controlPanel, 'Style', 'text', ...
    'Tag', 'review-status', ...
    'String', '点击波锋或输入编号后查看。', ...
    'Units', 'normalized', ...
    'Position', [0.03,0.01,0.94,0.11], ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w', ...
    'ForegroundColor', [0.25,0.25,0.25], ...
    'FontSize', 9);

setappdata(hFig, 'review_axes', [axMap, axInfo, axDiagnostic]);
setappdata(hFig, 'review_controls', controls);
setappdata(hFig, 'review_action', emptyReviewAction());
end

function drawReviewUnit(hFig, events, crests, matches, unit, ...
    reviews, sessionSkipped, config)
%DRAWREVIEWUNIT 绘制一个系泊事件前后固定时间窗内的全部波锋。
axesList = getappdata(hFig, 'review_axes');
axMap = axesList(1);
axInfo = axesList(2);
axDiagnostic = axesList(3);
eventId = unit.event_id;
rows = unit.candidate_rows;
globallyMatched = ismember(crests.crest_idx, matches.crest_idx);
context = struct( ...
    'events', events, ...
    'crests', crests, ...
    'matches', matches, ...
    'unit', unit, ...
    'reviews', reviews, ...
    'config', config);
setappdata(hFig, 'review_context', context);
setappdata(hFig, 'review_action', emptyReviewAction());
setappdata(hFig, 'review_selection', struct());
setappdata(hFig, 'diagnostic_overlays', gobjects(0));

cla(axMap);
hold(axMap, 'on');
box(axMap, 'on');
grid(axMap, 'on');
lineHandles = gobjects(numel(rows),1);

for i = 1:numel(rows)
    row = rows(i);
    crestIdx = crests.crest_idx(row);
    deltaHours = hours( ...
        crests.sensing_time(row) - events.start_time(eventId));

    if crestIdx == unit.automatic_crest_idx
        color = [0.70,0.05,0.55];
        width = 3.6;
        label = sprintf('AUTO C%d | %s | %+0.1f h', ...
            crestIdx, formatShortTime(crests.sensing_time(row)), ...
            deltaHours);
    elseif ~globallyMatched(row)
        if deltaHours < 0
            color = [0.05,0.42,0.78];
        else
            color = [0.90,0.38,0.05];
        end
        width = 2.1;
        label = sprintf('C%d | %s | %+0.1f h', ...
            crestIdx, formatShortTime(crests.sensing_time(row)), ...
            deltaHours);
    else
        color = [0.76,0.76,0.76];
        width = 0.9;
        label = "";
    end

    lineHandles(i) = plot(axMap, ...
        crests.longitude{row}, crests.latitude{row}, '-', ...
        'Color', color, 'LineWidth', width, ...
        'Tag', 'crest-line', ...
        'UserData', crestIdx, ...
        'HitTest', 'on', ...
        'PickableParts', 'all', ...
        'ButtonDownFcn', @(~,~) selectCrestForReview( ...
        hFig, crestIdx));
    setappdata(lineHandles(i), 'base_line_width', width);
    if strlength(label) > 0
        labelCrest(axMap, crests.longitude{row}, ...
            crests.latitude{row}, label, color);
    end
end

plot(axMap, config.mooringLon, config.mooringLat, 'p', ...
    'Color', [0.10,0.10,0.10], ...
    'MarkerFaceColor', [0.95,0.15,0.15], ...
    'MarkerSize', 14, 'LineWidth', 1.5, ...
    'HitTest', 'off', 'PickableParts', 'none');
text(axMap, config.mooringLon, config.mooringLat, '  Mooring', ...
    'FontWeight', 'bold', 'Color', [0.10,0.10,0.10], ...
    'Interpreter', 'none', ...
    'HitTest', 'off', 'PickableParts', 'none');

axis(axMap, 'equal');
if isempty(rows)
    xlim(axMap, config.mooringLon + [-0.5,0.5]);
    ylim(axMap, config.mooringLat + [-0.5,0.5]);
else
    axis(axMap, 'padded');
end
xlabel(axMap, 'Longitude (deg)');
ylabel(axMap, 'Latitude (deg)');
title(axMap, sprintf('事件 %d / %d：%s，前后 %.1f 天全部波锋', ...
    eventId, height(events), ...
    formatTime(events.start_time(eventId)), config.windowDays), ...
    'Interpreter', 'none');
subtitle(axMap, ['蓝色=事件前未匹配，橙色=事件后未匹配，' ...
    '紫色=当前自动匹配，浅灰=已被其他事件使用']);

drawInfoPanel(axInfo, events, unit, reviews, ...
    sessionSkipped, config);
drawDiagnosticPanel(axDiagnostic, [], events, unit);
setappdata(hFig, 'crest_line_handles', lineHandles);
resetReviewControls(hFig, unit);
end

function drawInfoPanel(ax, events, unit, reviews, ...
    sessionSkipped, config)
%DRAWINFOPANEL 显示事件元数据、进度和当前候选编号。
cla(ax);
axis(ax, [0,1,0,1]);
axis(ax, 'off');
eventId = unit.event_id;
reviewedCount = height(reviews);

if isfinite(unit.automatic_crest_idx)
    autoText = sprintf('C%d', unit.automatic_crest_idx);
else
    autoText = '无';
end
candidateList = unit.candidate_crest_indices;
maxVisibleIndices = 24;
isTruncated = numel(candidateList) > maxVisibleIndices;
candidateList = candidateList( ...
    1:min(numel(candidateList), maxVisibleIndices));
listTokens = string(candidateList(:));
if isTruncated
    listTokens(end+1,1) = "...";
end
listLines = wrapTokensForAxes(ax, listTokens, 10);

lines = [ ...
    "系泊事件"; ...
    sprintf("event_id: %d", eventId); ...
    sprintf("Mode: %d", events.mode(eventId)); ...
    "Start: "+string(formatTime(events.start_time(eventId))); ...
    "End:   "+string(formatTime(events.end_time(eventId))); ...
    sprintf("KdV speed: %.4g m/s", ...
        events.local_speed_mps(eventId)); ...
    sprintf("Direction: %.2f deg", ...
        events.direction_deg(eventId)); ...
    ""; ...
    "当前页面"; ...
    sprintf("全部波锋: %d", unit.candidate_count); ...
    sprintf("未自动匹配: %d", unit.unmatched_count); ...
    "自动匹配: "+string(autoText); ...
    ""; ...
    sprintf("已标: %d / %d", reviewedCount, height(events)); ...
    sprintf("本次跳过: %d", numel(sessionSkipped)); ...
    ""; ...
    "当前时间窗 crest_idx"; ...
    listLines];

text(ax, 0, 0.99, strjoin(lines, newline), ...
    'VerticalAlignment', 'top', ...
    'FontName', 'Courier New', ...
    'FontSize', 9, ...
    'Interpreter', 'none', ...
    'Clipping', 'on');
[~, outputName, outputExt] = fileparts(config.outputCsv);
text(ax, 0, 0.01, ['CSV: ' outputName outputExt], ...
    'VerticalAlignment', 'bottom', ...
    'FontSize', 8, 'Color', [0.35,0.35,0.35], ...
    'Interpreter', 'none', 'Clipping', 'on');
end

function action = emptyReviewAction()
%EMPTYREVIEWACTION 返回尚未触发标注操作的状态。
action = struct('type', "", 'crest_idx', NaN);
end

function resetReviewControls(hFig, unit)
%RESETREVIEWCONTROLS 为新事件清空输入、选择和状态提示。
controls = getappdata(hFig, 'review_controls');
set(controls.input, 'String', '');
if unit.candidate_count > 0
    state = 'on';
    message = '点击波锋或输入编号后查看。';
else
    state = 'off';
    message = '当前时间窗没有波锋，可标记无对应或无法判断。';
end
set(controls.input, 'Enable', state);
set(controls.view, 'Enable', state);
set(controls.confirm, 'Enable', state);
set(controls.undo, 'Enable', ...
    onOff(~isempty(getappdata(hFig, 'review_context').reviews)));
set(controls.status, 'String', message, ...
    'ForegroundColor', [0.25,0.25,0.25]);
end

function value = onOff(tf)
%ONOFF 把逻辑值转换为 uicontrol 的 Enable 文本。
if tf
    value = 'on';
else
    value = 'off';
end
end

function onCrestInputKey(hFig, event)
%ONCRESTINPUTKEY 输入框按回车时执行查看，不直接提交。
if ismember(string(event.Key), ["return","enter"])
    onViewCrest(hFig);
end
end

function onViewCrest(hFig)
%ONVIEWCREST 根据输入框中的编号定位波锋并刷新诊断。
[isValid, crestIdx] = readCandidateInput(hFig);
if isValid
    selectCrestForReview(hFig, crestIdx);
end
end

function onConfirmMatch(hFig)
%ONCONFIRMMATCH 校验并确认当前输入框中的人工配对。
[isValid, crestIdx] = readCandidateInput(hFig);
if ~isValid
    return;
end
selection = getappdata(hFig, 'review_selection');
if ~isstruct(selection) || ~isfield(selection, 'crest_idx') || ...
        selection.crest_idx ~= crestIdx
    if ~selectCrestForReview(hFig, crestIdx)
        return;
    end
end

context = getappdata(hFig, 'review_context');
if ~confirmConflictingSelection(hFig, crestIdx, ...
        context.unit.event_id, context.reviews, context.matches)
    return;
end
resumeWithAction(hFig, ...
    struct('type',"confirmed_match",'crest_idx',crestIdx));
end

function [isValid, crestIdx] = readCandidateInput(hFig)
%READCANDIDATEINPUT 校验输入是否为当前事件中的整数 crest_idx。
isValid = false;
crestIdx = NaN;
if ~isgraphics(hFig)
    return;
end
controls = getappdata(hFig, 'review_controls');
context = getappdata(hFig, 'review_context');
textValue = strtrim(string(get(controls.input, 'String')));
value = str2double(textValue);
if strlength(textValue) == 0 || ~isfinite(value) || value ~= round(value)
    setReviewStatus(hFig, 'crest_idx 必须是整数。', false);
    return;
end
crestIdx = round(value);
if ~ismember(crestIdx, context.unit.candidate_crest_indices)
    setReviewStatus(hFig, sprintf( ...
        'C%d 不在当前事件前后 %.1f 天范围内。', ...
        crestIdx, context.config.windowDays), false);
    return;
end
isValid = true;
end

function succeeded = selectCrestForReview(hFig, crestIdx)
%SELECTCRESTFORREVIEW 选中波锋，计算诊断并刷新地图与信息面板。
succeeded = false;
if ~isgraphics(hFig)
    return;
end
context = getappdata(hFig, 'review_context');
candidatePosition = find( ...
    context.unit.candidate_crest_indices == crestIdx, 1);
if isempty(candidatePosition)
    setReviewStatus(hFig, sprintf( ...
        'C%d 不属于当前事件页面。', crestIdx), false);
    return;
end
catalogRow = context.unit.candidate_rows(candidatePosition);
eventId = context.unit.event_id;
controls = getappdata(hFig, 'review_controls');
set(controls.input, 'String', sprintf('%d', crestIdx));

try
    diagnostic = diagnoseCrestEventPair( ...
        context.crests.latitude{catalogRow}, ...
        context.crests.longitude{catalogRow}, ...
        context.crests.sensing_time(catalogRow), ...
        context.events.mode(eventId), ...
        context.config.mooringLat, context.config.mooringLon, ...
        context.events.start_time(eventId), ...
        context.events.end_time(eventId));
catch exception
    setReviewStatus(hFig, ...
        ['诊断失败：' exception.message], false);
    return;
end

selection = struct( ...
    'crest_idx', crestIdx, ...
    'catalog_row', catalogRow, ...
    'sensing_time', context.crests.sensing_time(catalogRow), ...
    'diagnostic', diagnostic);
setappdata(hFig, 'review_selection', selection);
highlightSelectedCrest(hFig, crestIdx, diagnostic);
axesList = getappdata(hFig, 'review_axes');
drawDiagnosticPanel(axesList(3), selection, ...
    context.events, context.unit);
setReviewStatus(hFig, sprintf( ...
    '已选择 C%d；只有“确认对应”会写入 CSV。', crestIdx), true);
succeeded = true;
end

function highlightSelectedCrest(hFig, crestIdx, diagnostic)
%HIGHLIGHTSELECTEDCREST 加粗选中波锋并绘制两个最近点。
lineHandles = getappdata(hFig, 'crest_line_handles');
for i = 1:numel(lineHandles)
    if ~isgraphics(lineHandles(i))
        continue;
    end
    baseWidth = getappdata(lineHandles(i), 'base_line_width');
    if lineHandles(i).UserData == crestIdx
        lineHandles(i).LineWidth = max(baseWidth+1.8, 4);
    else
        lineHandles(i).LineWidth = baseWidth;
    end
end

oldOverlays = getappdata(hFig, 'diagnostic_overlays');
delete(oldOverlays(isgraphics(oldOverlays)));
axesList = getappdata(hFig, 'review_axes');
axMap = axesList(1);
context = getappdata(hFig, 'review_context');
overlays = gobjects(0);

if isfinite(diagnostic.geometricPointLat) && ...
        isfinite(diagnostic.geometricPointLon)
    overlays(end+1) = plot(axMap, ...
        [context.config.mooringLon, diagnostic.geometricPointLon], ...
        [context.config.mooringLat, diagnostic.geometricPointLat], ...
        ':', 'Color', [0.00,0.60,0.72], 'LineWidth', 1.5, ...
        'HitTest', 'off', 'PickableParts', 'none');
    overlays(end+1) = plot(axMap, ...
        diagnostic.geometricPointLon, diagnostic.geometricPointLat, ...
        'o', 'Color', [0.00,0.45,0.58], ...
        'MarkerFaceColor', [0.25,0.85,0.92], ...
        'MarkerSize', 9, 'LineWidth', 1.5, ...
        'HitTest', 'off', 'PickableParts', 'none');
end

if isfinite(diagnostic.propagationPointLat) && ...
        isfinite(diagnostic.propagationPointLon)
    overlays(end+1) = plot(axMap, ...
        [context.config.mooringLon, diagnostic.propagationPointLon], ...
        [context.config.mooringLat, diagnostic.propagationPointLat], ...
        '--', 'Color', [0.58,0.18,0.72], 'LineWidth', 1.5, ...
        'HitTest', 'off', 'PickableParts', 'none');
    overlays(end+1) = plot(axMap, ...
        diagnostic.propagationPointLon, ...
        diagnostic.propagationPointLat, ...
        'd', 'Color', [0.43,0.08,0.56], ...
        'MarkerFaceColor', [0.78,0.40,0.88], ...
        'MarkerSize', 9, 'LineWidth', 1.5, ...
        'HitTest', 'off', 'PickableParts', 'none');
end
setappdata(hFig, 'diagnostic_overlays', overlays);
end

function drawDiagnosticPanel(ax, selection, events, unit)
%DRAWDIAGNOSTICPANEL 显示所选波锋的双最近点和速度诊断。
cla(ax);
axis(ax, [0,1,0,1]);
axis(ax, 'off');
if isempty(selection) || ~isstruct(selection) || ...
        ~isfield(selection, 'diagnostic')
    text(ax, 0, 0.98, ...
        ['波锋诊断' newline newline ...
        '点击波锋，或输入 crest_idx 后点“查看”。'], ...
        'VerticalAlignment', 'top', ...
        'FontSize', 10, 'Interpreter', 'none');
    return;
end

diagnostic = selection.diagnostic;
eventId = unit.event_id;
localSpeed = events.local_speed_mps(eventId);
speedDifference = speedDifferenceToIntervals( ...
    localSpeed, diagnostic.equivalentSpeedIntervalsMps);
if diagnostic.isPass
    passText = "通过";
    passColor = [0.05,0.48,0.20];
else
    passText = "拒绝";
    passColor = [0.75,0.12,0.10];
end

lines = [ ...
    sprintf("波锋诊断 C%d", selection.crest_idx); ...
    "遥感时间: "+string(formatTime(selection.sensing_time)); ...
    ""; ...
    "几何最近点"; ...
    "距离: "+formatDistance(diagnostic.geometricDistanceMeters); ...
    "位置: "+formatPoint(diagnostic.geometricPointLat, ...
    diagnostic.geometricPointLon); ...
    ""; ...
    "传播最近点"; ...
    "横向: "+formatDistance(diagnostic.crossTrackMeters); ...
    "沿程: "+formatSignedDistance( ...
    diagnostic.alongDisplacementMeters); ...
    "位置: "+formatPoint(diagnostic.propagationPointLat, ...
    diagnostic.propagationPointLon); ...
    sprintf("方向: %.2f deg", diagnostic.directionDeg); ...
    ""; ...
    "等效速度（仅使用传播最近点）"; ...
    "中间时刻: "+formatSpeed( ...
    diagnostic.equivalentSpeedMidMps); ...
    "时间窗区间: "+formatSpeedIntervals( ...
    diagnostic.equivalentSpeedIntervalsMps); ...
    sprintf("本站 KdV: %.3f m/s", localSpeed); ...
    "区间速度差: "+formatSpeed(speedDifference); ...
    ""; ...
    "当前物理规则: "+passText; ...
    "原因: "+reasonDescription(diagnostic.reason)];

text(ax, 0, 0.99, strjoin(lines, newline), ...
    'VerticalAlignment', 'top', ...
    'FontName', 'Courier New', ...
    'FontSize', 8.7, ...
    'Interpreter', 'none', ...
    'Clipping', 'on');
text(ax, 0.99, 0.99, passText, ...
    'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'top', ...
    'FontWeight', 'bold', 'FontSize', 10, ...
    'Color', passColor, 'Interpreter', 'none');
end

function value = speedDifferenceToIntervals(target, intervals)
%SPEEDDIFFERENCETOINTERVALS 计算目标速度到多个区间的最短距离。
value = NaN;
if ~isfinite(target) || isempty(intervals)
    return;
end
distances = max(intervals(:,1)-target, 0);
distances = max(distances, target-intervals(:,2));
value = min(distances);
end

function textValue = formatDistance(value)
%FORMATDISTANCE 使用米或千米显示无符号距离。
if ~isfinite(value)
    textValue = "N/A";
elseif value >= 1000
    textValue = string(sprintf('%.2f km', value/1000));
else
    textValue = string(sprintf('%.0f m', value));
end
end

function textValue = formatSignedDistance(value)
%FORMATSIGNEDDISTANCE 使用带符号的米或千米显示沿程位移。
if ~isfinite(value)
    textValue = "N/A";
elseif abs(value) >= 1000
    textValue = string(sprintf('%+.2f km', value/1000));
else
    textValue = string(sprintf('%+.0f m', value));
end
end

function textValue = formatPoint(lat, lon)
%FORMATPOINT 显示经纬度；无效点明确写为 N/A。
if ~isfinite(lat) || ~isfinite(lon)
    textValue = "N/A";
else
    textValue = string(sprintf('%.5f N, %.5f E', lat, lon));
end
end

function textValue = formatSpeed(value)
%FORMATSPEED 显示单个速度值。
if ~isfinite(value)
    textValue = "N/A";
else
    textValue = string(sprintf('%.3f m/s', value));
end
end

function textValue = formatSpeedIntervals(intervals)
%FORMATSPEEDINTERVALS 显示原始等效速度区间。
if isempty(intervals)
    textValue = "N/A";
    return;
end
parts = strings(size(intervals,1),1);
for i = 1:size(intervals,1)
    parts(i) = "["+formatSpeedBound(intervals(i,1))+"," + ...
        formatSpeedBound(intervals(i,2))+"]";
end
textValue = strjoin(parts, "; ");
end

function textValue = formatSpeedBound(value)
%FORMATSPEEDBOUND 速度区间端点允许为 Inf。
if isinf(value)
    textValue = "Inf";
elseif isnan(value)
    textValue = "NaN";
else
    textValue = string(sprintf('%.3f', value));
end
end

function textValue = reasonDescription(reason)
%REASONDESCRIPTION 把传播函数原因转换为简短中文。
switch string(reason)
    case "pass"
        textValue = "满足当前规则";
    case "invalid_crest"
        textValue = "波锋坐标无效";
    case "direction_flip_required_but_rejected"
        textValue = "方向翻转条件未通过";
    case "initial_direction_below_flip_threshold"
        textValue = "初始方向位于 0–45 deg，按规则拒配";
    case "cross_track_outside_radius"
        textValue = "横向距离超过走廊";
    case "time_window_crosses_sensing_time"
        textValue = "事件时间窗跨越遥感时刻";
    case "direct_spatiotemporal_overlap"
        textValue = "成像时波锋近站，直接匹配";
    case "closest_point_direction_ambiguous"
        textValue = "传播最近点方向不明确";
    case "closest_point_time_direction_mismatch"
        textValue = "沿程位移与时间方向相反";
    case "no_positive_speed_interval"
        textValue = "没有正的等效速度";
    case "speed_above_5_mps"
        textValue = "等效速度超过 5 m/s";
    case "time_outside_limit"
        textValue = "事件时间超出限制";
    otherwise
        textValue = string(reason);
end
end

function setReviewStatus(hFig, message, succeeded)
%SETREVIEWSTATUS 在 Figure 内显示操作结果。
if ~isgraphics(hFig)
    return;
end
controls = getappdata(hFig, 'review_controls');
if succeeded
    color = [0.05,0.42,0.18];
else
    color = [0.75,0.12,0.10];
end
set(controls.status, 'String', char(message), ...
    'ForegroundColor', color);
end

function resumeWithAction(hFig, action)
%RESUMEWITHACTION 写入图内动作并唤醒主事件循环。
if ~isgraphics(hFig)
    return;
end
setappdata(hFig, 'review_action', action);
uiresume(hFig);
end

function onCloseReviewFigure(hFig, ~)
%ONCLOSEREVIEWFIGURE 关闭窗口等同于保存退出。
if ~isgraphics(hFig)
    return;
end
setappdata(hFig, 'review_action', ...
    struct('type',"quit",'crest_idx',NaN));
try
    uiresume(hFig);
catch
    % Figure 可能不在等待状态，直接删除即可。
end
delete(hFig);
end

function lines = wrapTokensForAxes(ax, tokens, fontSize)
%WRAPTOKENSFORAXES 按侧栏当前像素宽度折行逗号分隔的短文本。
if isempty(tokens)
    lines = "(无)";
    return;
end

pixelPosition = getpixelposition(ax, true);
approximateCharacterWidth = max(6, 0.75 * fontSize);
maxCharacters = max(16, ...
    floor(pixelPosition(3) / approximateCharacterWidth) - 2);

lines = strings(0,1);
current = "";
for i = 1:numel(tokens)
    if i < numel(tokens) && tokens(i) ~= "..."
        piece = tokens(i) + ",";
    else
        piece = tokens(i);
    end

    if strlength(current) == 0
        candidate = piece;
    else
        candidate = current + " " + piece;
    end
    if strlength(candidate) <= maxCharacters || ...
            strlength(current) == 0
        current = candidate;
    else
        lines(end+1,1) = current; %#ok<AGROW>
        current = piece;
    end
end
lines(end+1,1) = current;
end

function labelCrest(ax, lon, lat, label, color)
%LABELCREST 在折线中间有效点旁标注波锋编号和相对时间。
good = isfinite(lon) & isfinite(lat);
indices = find(good);
if isempty(indices)
    return;
end
mid = indices(ceil(numel(indices)/2));
text(ax, lon(mid), lat(mid), [' ' char(label)], ...
    'Color', color, 'FontSize', 8.5, 'FontWeight', 'bold', ...
    'Interpreter', 'none', 'Clipping', 'on', ...
    'HitTest', 'off', 'PickableParts', 'none');
end

function value = formatTime(time)
%FORMATTIME 使用固定格式显示完整时间。
if isnat(time)
    value = 'NaT';
else
    value = char(time, 'yyyy-MM-dd HH:mm:ss');
end
end

function value = formatShortTime(time)
%FORMATSHORTTIME 使用紧凑格式显示波锋观测时间。
if isnat(time)
    value = 'NaT';
else
    value = char(time, 'MM-dd HH:mm');
end
end

function description = describeReview(label, selectedCrestIdx)
%DESCRIBEREVIEW 生成人工判断的命令行摘要。
switch label
    case "confirmed_match"
        description = sprintf('对应波锋 C%d', selectedCrestIdx);
    case "confirmed_no_match"
        description = '确认无对应波锋';
    otherwise
        description = '无法判断';
end
end

function printInventory(events, crests, matches, units, windowDays)
%PRINTINVENTORY 报告全量标注队列，不写任何文件。
counts = vertcat(units.candidate_count);
unmatched = vertcat(units.unmatched_count);
fprintf(['事件 %d 个，SHP 波锋 %d 条，当前自动匹配 %d 对。\n' ...
    '前后 %.1f 天候选边 %d 条；每事件候选数 min/median/max=' ...
    '%d/%.1f/%d；无候选事件 %d 个。\n' ...
    '其中当前未匹配候选边 %d 条。\n'], ...
    height(events), height(crests), height(matches), ...
    windowDays, sum(counts), min(counts), median(counts), max(counts), ...
    nnz(counts == 0), sum(unmatched));
end

function printFinalSummary( ...
    units, reviews, sessionSkipped, quitRequested)
%PRINTFINALSUMMARY 退出或完成后报告人工参考集进度。
matched = nnz(reviews.human_label == "confirmed_match");
noMatch = nnz(reviews.human_label == "confirmed_no_match");
uncertain = nnz(reviews.human_label == "uncertain");
pending = numel(units) - height(reviews);
if quitRequested
    state = '已保存并退出';
elseif pending == 0
    state = '全量标注已完成';
else
    state = '本次会话已结束';
end
fprintf(['\n%s。已标 %d/%d：对应 %d，无对应 %d，无法判断 %d；' ...
    '待标 %d，本次跳过 %d。\n'], ...
    state, height(reviews), numel(units), matched, noMatch, ...
    uncertain, pending, numel(sessionSkipped));
end

function result = buildResult(config, events, crests, matches, ...
    units, reviews, dataSignature, figureHandle, quitRequested)
%BUILDRESULT 返回可用于库存统计和后续分析的完整状态。
result = struct();
result.config = config;
result.events = events;
result.crests = crests;
result.matches = matches;
result.units = units;
result.reviews = reviews;
result.data_signature = dataSignature;
result.figure = figureHandle;
result.quit_requested = quitRequested;
end
