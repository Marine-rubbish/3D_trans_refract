function verify_review_event_crest_ground_truth
%VERIFY_REVIEW_EVENT_CREST_GROUND_TRUTH 事件中心人工标注器集成回归。
% 在项目根目录执行：
%   addpath('tests'); verify_review_event_crest_ground_truth;
%
% 测试使用临时 SHP、XLSX、MAT、CSV 和模拟输入，不读取或修改项目
% 中的真实人工参考集。

projectRoot = fileparts(fileparts(mfilename('fullpath')));
oldPath = path;
workDir = tempname(fullfile(projectRoot, 'TMP'));
mkdir(workDir);
responseKey = 'event_crest_review_response_queue';
hadResponse = isappdata(0, responseKey);
oldResponse = getappdata(0, responseKey);
evidenceKey = [responseKey '_evidence'];
hadEvidence = isappdata(0, evidenceKey);
oldEvidence = getappdata(0, evidenceKey);
cleanup = onCleanup(@() cleanupFixture( ...
    workDir, oldPath, responseKey, hadResponse, oldResponse, ...
    evidenceKey, hadEvidence, oldEvidence));
addpath(fullfile(projectRoot, 'visualization'));
addpath(genpath(fullfile(projectRoot, 'utils')));

shpDir = fullfile(workDir, 'shp');
mkdir(shpDir);
featureCount = 45;
features = repmat( ...
    struct('Geometry', 'Line', 'X', [], 'Y', []), ...
    featureCount, 1);
for i = 1:featureCount
    lon = 115.3 + 0.006*i;
    lat = 20.45 + 0.008*i;
    features(i).X = lon + [0,0.1,0.2];
    features(i).Y = lat + [0,0.1,0.2];
end
shpName = 'MOD02QKM.A2020128.0315.061.test_20200507.shp';
shapewrite(features, fullfile(shpDir, shpName));

% 文件名时间为 UTC 03:15，标注器统一加 8 h。
crestTime = datetime(2020,5,7,11,15,0);
eventStart = crestTime + hours([1;2]);
eventEnd = eventStart + minutes(5);
eventTable = table([1;1], eventStart, eventEnd, ...
    [1.2;1.3], [210;212], ...
    'VariableNames', {'Mode','StartTime','EndTime', ...
    'Speed','Direction'});
mooringPath = fullfile(workDir, 'events.xlsx');
writetable(eventTable, mooringPath);

data = struct();
data.crest_idx = 1;
data.mooring_time = eventStart(1);
data.crest_time = crestTime;
data.mode = 1;
matPath = fullfile(workDir, 'current.mat');
save(matPath, '-struct', 'data');

outputCsv = fullfile(workDir, 'reviews.csv');
config = struct( ...
    'matPath', matPath, ...
    'mooringPath', mooringPath, ...
    'shpDir', shpDir, ...
    'outputCsv', outputCsv, ...
    'figureVisible', 'off');

% 冲突确认使用临时 questdlg.m；Figure 点击和按钮由 timer 真正触发。
fid = fopen(fullfile(workDir, 'questdlg.m'), 'w');
assert(fid >= 0);
fprintf(fid, [ ...
    'function value = questdlg(varargin)\n', ...
    'value = ''仍然保存'';\n', ...
    'end\n']);
fclose(fid);
addpath(workDir, '-begin');

batchConfig = config;
batchConfig.interactive = false;
batch = review_event_crest_ground_truth(batchConfig);
assert(height(batch.events) == 2);
assert(height(batch.crests) == featureCount);
assert(height(batch.matches) == 1);
assert(numel(batch.units) == 2);
assert(all([batch.units.candidate_count] == featureCount));
assert(~isfile(outputCsv));
fprintf('通过：非交互库存模式不读写人工标签。\n');

% 事件 1 点击 C2 并确认，随后在事件 2 页面退出。
first = runReview(config, responseKey, ...
    ["click:1:2","confirm:1:2","quit:2"], true);
assert(height(first.reviews) == 1);
assert(first.reviews.event_id == 1);
assert(first.reviews.human_label == "confirmed_match");
assert(first.reviews.selected_crest_idx == 2);
assert(first.reviews.selected_was_unmatched);
assert(isfile(outputCsv));
evidence = getappdata(0, evidenceKey);
assert(evidence.crest_idx == 2);
assert(strcmp(evidence.input_text, '2'));
assert(evidence.sensing_time == crestTime);
assert(any(contains(evidence.diagnostic_text, ...
    "遥感时间: 2020-05-07 11:15:00")));
assert(isfinite(evidence.diagnostic.geometricDistanceMeters));
assert(isfinite(evidence.diagnostic.propagationPointLat));
assert(evidence.overlay_count >= 4);
axesList = getappdata(first.figure, 'review_axes');
panelText = findobj(axesList(2), 'Type', 'Text', ...
    'FontName', 'Courier New');
assert(isscalar(panelText));
panelLines = splitlines(string(panelText.String));
header = find(panelLines == "当前时间窗 crest_idx", 1);
assert(~isempty(header));
wrappedLines = panelLines(header+1:end);
assert(numel(wrappedLines) > 1);
assert(all(strlength(wrappedLines) <= 48));
close(first.figure);
fprintf('通过：点击波锋会填入编号并绘制双最近点诊断。\n');
fprintf('通过：图内确认后立即写入 CSV。\n');
fprintf('通过：长 crest_idx 列表按侧栏宽度自动换行。\n');

resumed = runReview(config, responseKey, "quit:2");
assert(height(resumed.reviews) == 1);
assert(strcmp(resumed.config.outputCsv, outputCsv));
fprintf('通过：相同数据从首个未标事件断点续查。\n');

% 事件 2 手动输入 C2 会触发跨事件冲突；对话框确认后允许保存。
conflicted = runReview(config, responseKey, ...
    ["view:2:2","confirm:2:2"]);
assert(height(conflicted.reviews) == 2);
assert(all(conflicted.reviews.human_label == "confirmed_match"));
assert(all(conflicted.reviews.selected_crest_idx == 2));
assert(numel(unique(conflicted.reviews.event_id)) == 2);
fprintf('通过：手动输入、查看和冲突确认都在 Figure 内完成。\n');

loaded = readtable(outputCsv, 'TextType', 'string');
assert(height(loaded) == 2);
assert(all(loaded.selected_crest_idx == 2));

controlConfig = config;
controlConfig.outputCsv = fullfile(workDir, 'control_reviews.csv');
controlsResult = runReview(controlConfig, responseKey, ...
    ["no_match:1","undo:2","uncertain:1","skip:2"]);
assert(height(controlsResult.reviews) == 1);
assert(controlsResult.reviews.event_id == 1);
assert(controlsResult.reviews.human_label == "uncertain");
fprintf('通过：无对应、撤销、无法判断和跳过按钮保持原语义。\n');
fprintf('全部 Figure 标注集成场景通过。\n');
end

function result = runReview(config, responseKey, responses, keepFigure)
if nargin < 4
    keepFigure = false;
end
setappdata(0, responseKey, string(responses(:)));
driver = timer( ...
    'ExecutionMode', 'fixedSpacing', ...
    'Period', 0.15, ...
    'StartDelay', 0.1, ...
    'TimerFcn', @(~,~) driveReviewFigure(responseKey), ...
    'ErrorFcn', @reportDriverError);
driverCleanup = onCleanup(@() stopAndDeleteTimer(driver));
start(driver);
result = review_event_crest_ground_truth(config);
if isgraphics(result.figure) && ~keepFigure
    close(result.figure);
end
end

function driveReviewFigure(responseKey)
queue = getappdata(0, responseKey);
if isempty(queue)
    return;
end
figures = findall(0, 'Type', 'figure', ...
    'Tag', 'event-crest-review');
if isempty(figures)
    return;
end
hFig = figures(1);
if ~strcmp(get(hFig, 'WaitStatus'), 'waiting')
    return;
end
controls = getappdata(hFig, 'review_controls');
if isempty(controls) || ~isgraphics(controls.input)
    return;
end

command = queue(1);
parts = split(command, ':');
name = parts(1);
if numel(parts) > 1
    targetEventId = str2double(parts(2));
else
    targetEventId = NaN;
end
if numel(parts) > 2
    crestIdx = str2double(parts(3));
else
    crestIdx = NaN;
end
context = getappdata(hFig, 'review_context');
if isempty(context) || context.unit.event_id ~= targetEventId
    return;
end

switch name
    case "click"
        lines = findall(hFig, 'Type', 'line', 'Tag', 'crest-line');
        target = [];
        for i = 1:numel(lines)
            if lines(i).UserData == crestIdx
                target = lines(i);
                break;
            end
        end
        assert(~isempty(target), '未找到待点击波锋。');
        invokeCallback(target, 'ButtonDownFcn');
        captureEvidence(hFig, responseKey);
    case "view"
        set(controls.input, 'String', sprintf('%d', crestIdx));
        invokeCallback(controls.view, 'Callback');
        captureEvidence(hFig, responseKey);
    case "confirm"
        set(controls.input, 'String', sprintf('%d', crestIdx));
        invokeCallback(controls.confirm, 'Callback');
    case "no_match"
        invokeCallback(controls.noMatch, 'Callback');
    case "uncertain"
        invokeCallback(controls.uncertain, 'Callback');
    case "skip"
        invokeCallback(controls.skip, 'Callback');
    case "undo"
        invokeCallback(controls.undo, 'Callback');
    case "quit"
        invokeCallback(controls.quit, 'Callback');
    otherwise
        error('未知 Figure 测试命令：%s', name);
end
setappdata(0, responseKey, queue(2:end));
end

function reportDriverError(~, event)
fprintf(2, 'Figure 测试驱动失败：\n');
disp(event.Data);
end

function invokeCallback(handle, property)
callback = get(handle, property);
if isa(callback, 'function_handle')
    callback(handle, []);
elseif iscell(callback)
    callback{1}(handle, [], callback{2:end});
else
    error('控件回调不是可调用函数。');
end
end

function captureEvidence(hFig, responseKey)
selection = getappdata(hFig, 'review_selection');
controls = getappdata(hFig, 'review_controls');
overlays = getappdata(hFig, 'diagnostic_overlays');
axesList = getappdata(hFig, 'review_axes');
diagnosticText = findobj(axesList(3), 'Type', 'Text', ...
    'FontName', 'Courier New');
assert(isscalar(diagnosticText));
evidence = struct( ...
    'crest_idx', selection.crest_idx, ...
    'input_text', get(controls.input, 'String'), ...
    'sensing_time', selection.sensing_time, ...
    'diagnostic_text', string(diagnosticText.String), ...
    'diagnostic', selection.diagnostic, ...
    'overlay_count', nnz(isgraphics(overlays)));
setappdata(0, [responseKey '_evidence'], evidence);
end

function stopAndDeleteTimer(driver)
if isvalid(driver)
    stop(driver);
    delete(driver);
end
end

function cleanupFixture( ...
    workDir, oldPath, responseKey, hadResponse, oldResponse, ...
    evidenceKey, hadEvidence, oldEvidence)
path(oldPath);
if hadResponse
    setappdata(0, responseKey, oldResponse);
elseif isappdata(0, responseKey)
    rmappdata(0, responseKey);
end
if hadEvidence
    setappdata(0, evidenceKey, oldEvidence);
elseif isappdata(0, evidenceKey)
    rmappdata(0, evidenceKey);
end
if isfolder(workDir)
    rmdir(workDir, 's');
end
end
