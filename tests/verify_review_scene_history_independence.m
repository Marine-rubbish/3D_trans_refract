function verify_review_scene_history_independence
%VERIFY_REVIEW_SCENE_HISTORY_INDEPENDENCE 核查入口的文件与续查集成回归。
% 在项目根目录执行：
%   addpath('tests'); verify_review_scene_history_independence;
% 所有 SHP、MAT、CSV 和模拟键盘输入均位于临时目录，退出时清理。
% 需要 Mapping Toolbox；不运行匹配优化器，不读取项目人工标签。

projectRoot = fileparts(fileparts(mfilename('fullpath')));
oldPath = path;
workDir = tempname(fullfile(projectRoot, 'TMP'));
mkdir(workDir);
responseKey = 'scene_order_verification_response';
hadResponse = isappdata(0, responseKey);
oldResponse = getappdata(0, responseKey);
cleanup = onCleanup(@() cleanupFixture( ...
    workDir, oldPath, responseKey, hadResponse, oldResponse));
addpath(fullfile(projectRoot, 'visualization'));
addpath(genpath(fullfile(projectRoot, 'utils')));

% 用极小的真实文件覆盖完整入口。三顶点直线的传播方向均为西向，
% 两线间距约 2 km，能够按默认参数构成一个两成员候选波包。
shpDir = fullfile(workDir, 'shp');
mkdir(shpDir);
features = repmat(struct('Geometry', 'Line', 'X', [], 'Y', []), 2, 1);
for i = 1:2
    features(i).X = repmat(115.8 + 0.02*(i-1), 1, 3);
    features(i).Y = [20.7, 20.8, 20.9];
end
shapewrite(features, fullfile(shpDir, 'scene.shp'));
data = struct();
data.crest_idx = [1;2];
data.crest_lon = {features(1).X(:); features(2).X(:)};
data.crest_lat = {features(1).Y(:); features(2).Y(:)};
data.crest_time = repmat(datetime(2020,5,7), 2, 1);
data.mooring_time = datetime(2020,5,7) + hours([1;2]);
data.speed_diff = [0;0];
data.mode = [1;1];
matPath = fullfile(workDir, 'current.mat');
save(matPath, '-struct', 'data');
config = struct('matPath', matPath, 'shpDir', shpDir, ...
    'outputCsv', fullfile(workDir, 'reviews.csv'), ...
    'summaryCsv', fullfile(workDir, 'summary.csv'), ...
    'figureVisible', 'off');

% 只替换测试进程中的 input：首次回答 N，其余场景回答 Q。
% 使用实际的核查入口与 CSV 读写，不复制被测续查算法。
fid = fopen(fullfile(workDir, 'input.m'), 'w');
assert(fid >= 0);
fprintf(fid, ['function value = input(varargin)\n', ...
    'value = getappdata(0, ''%s'');\nend\n'], responseKey);
fclose(fid);
addpath(workDir, '-begin');

fresh = runReview(config, responseKey, 'n');
assert(isscalar(fresh.units) && fresh.units.matched_crest_count == 2);
assert(height(fresh.reviews) == 1 && fresh.reviews.human_label == "normal");
assert(strcmp(fresh.config.outputCsv, config.outputCsv));
oldCsv = fileread(config.outputCsv);
oldSummary = fileread(config.summaryCsv);
fprintf('通过：没有历史也能开始核查并保存。\n');

resumed = runReview(config, responseKey, 'q');
assert(strcmp(resumed.config.outputCsv, config.outputCsv));
assert(height(resumed.reviews) == 1 && resumed.reviews.human_label == "normal");
fprintf('通过：相同数据继续原记录。\n');

% 模拟 P299：波锋与包序未变，只有到站时刻对调，旧标签不能续用。
data.mooring_time = flipud(data.mooring_time);
save(matPath, '-struct', 'data');
changed = runReview(config, responseKey, 'q');
assert(isempty(changed.reviews));
assert(endsWith(changed.config.outputCsv, 'reviews_run001.csv'));
assert(endsWith(changed.config.summaryCsv, 'summary_run001.csv'));
assert(strcmp(fileread(config.outputCsv), oldCsv));
assert(strcmp(fileread(config.summaryCsv), oldSummary));
fprintf('通过：仅时刻变化就另开记录，旧文件保持原样。\n');

saved = runReview(config, responseKey, 'd');
resumed = runReview(config, responseKey, 'q');
assert(strcmp(saved.config.outputCsv, resumed.config.outputCsv));
assert(resumed.reviews.human_label == "disordered");
fprintf('通过：默认入口能找到新批次记录并断点续查。\n');

% 模拟 P262：原来有两条匹配，现在只剩第一条，自动登记 single_match。
names = fieldnames(data);
for i = 1:numel(names)
    data.(names{i}) = data.(names{i})(1);
end
save(matPath, '-struct', 'data');
single = runReview(config, responseKey, 'q');
assert(endsWith(single.config.outputCsv, 'reviews_run002.csv'));
assert(height(single.reviews) == 1);
assert(single.reviews.human_label == "single_match");
assert(single.reviews.matched_crest_count == 1);
assert(strcmp(fileread(config.outputCsv), oldCsv));
fprintf('通过：多匹配变单匹配不报签名错误，自动登记本轮状态。\n');

config.resumeReviews = false;
forced = runReview(config, responseKey, 'q');
assert(endsWith(forced.config.outputCsv, 'reviews_run003.csv'));
assert(forced.reviews.human_label == "single_match");
fprintf('通过：关闭续查时强制开启新一轮。\n');

config.resumeReviews = true;
config.outputCsv = fullfile(workDir, 'broken.csv');
config.summaryCsv = fullfile(workDir, 'broken_summary.csv');
fid = fopen(config.outputCsv, 'w');
assert(fid >= 0);
fprintf(fid, 'unrelated_column\nbroken\n');
fclose(fid);
brokenCsv = fileread(config.outputCsv);
recovered = runReview(config, responseKey, 'q');
assert(endsWith(recovered.config.outputCsv, 'broken_run001.csv'));
assert(recovered.reviews.human_label == "single_match");
assert(strcmp(fileread(config.outputCsv), brokenCsv));
fprintf('通过：旧 CSV 不可用不会阻断当前核查。\n');

config.interactive = false;
beforeFiles = dir(fullfile(workDir, '*.csv'));
batch = review_scene_match_order(config);
afterFiles = dir(fullfile(workDir, '*.csv'));
assert(isempty(batch.reviews));
assert(strcmp(batch.config.outputCsv, config.outputCsv));
assert(isequal({beforeFiles.name}, {afterFiles.name}));
assert(strcmp(fileread(config.outputCsv), brokenCsv));
fprintf('通过：非交互检查不读取历史标签，也不写 CSV。\n');
fprintf('全部 8 个历史独立性场景通过。\n');
end

function result = runReview(config, responseKey, response)
setappdata(0, responseKey, response);
result = review_scene_match_order(config);
if isgraphics(result.figure)
    close(result.figure);
end
end

function cleanupFixture(workDir, oldPath, responseKey, hadResponse, oldResponse)
path(oldPath);
if hadResponse
    setappdata(0, responseKey, oldResponse);
elseif isappdata(0, responseKey)
    rmappdata(0, responseKey);
end
if isfolder(workDir)
    rmdir(workDir, 's');
end
end
