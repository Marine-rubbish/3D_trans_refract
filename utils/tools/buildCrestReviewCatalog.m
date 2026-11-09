function crests = buildCrestReviewCatalog( ...
    shpDir, timeOffsetHours, requireSensingTime)
%BUILDCRESTREVIEWCATALOG 按生产入口的 SHP 顺序重建全局波锋目录。
%
% crests = buildCrestReviewCatalog( ...
%     shpDir, timeOffsetHours, requireSensingTime)
%
% crest_idx 必须与生产脚本一致，因此这里保留 dir 返回顺序，不再单独
% 排序。sensing_time 从 SHP 文件名解析，并加上统一的时区偏移。不需要
% 时间的旧核查工具可保留默认 false，无法解析时得到 NaT。

if nargin < 2 || isempty(timeOffsetHours)
    timeOffsetHours = 8;
end
if nargin < 3 || isempty(requireSensingTime)
    requireSensingTime = false;
end
if ~isfolder(shpDir)
    error('SHP 目录不存在：%s', shpDir);
end
validateattributes(timeOffsetHours, {'numeric'}, ...
    {'scalar','finite','real'});
validateattributes(requireSensingTime, {'logical'}, {'scalar'});

files = dir(fullfile(shpDir, '*.shp'));
if isempty(files)
    error('目录中没有 SHP 文件：%s', shpDir);
end

crestIdx = zeros(0,1);
sceneId = zeros(0,1);
sceneFile = strings(0,1);
fileName = strings(0,1);
featureIndex = zeros(0,1);
sensingTime = NaT(0,1);
latitude = cell(0,1);
longitude = cell(0,1);

next = 0;
for k = 1:numel(files)
    shpPath = fullfile(files(k).folder, files(k).name);
    % 标注只读取几何。部分历史 SHP 没有 DBF，shaperead 会为每个文件
    % 重复输出属性缺失警告；用 evalc 收起这些不影响几何的提示。
    evalc('features = shaperead(shpPath);');
    count = numel(features);
    rows = next + (1:count);
    try
        fileTime = getTimeFromFilename(shpPath) + ...
            hours(timeOffsetHours);
    catch exception
        if requireSensingTime
            error('无法从 SHP 文件名解析观测时间：%s\n%s', ...
                files(k).name, exception.message);
        end
        fileTime = NaT;
    end

    crestIdx(rows,1) = rows';
    sceneId(rows,1) = k;
    sceneFile(rows,1) = string(files(k).name);
    fileName(rows,1) = string(shpPath);
    featureIndex(rows,1) = (1:count)';
    sensingTime(rows,1) = repmat(fileTime, count, 1);

    for j = 1:count
        row = rows(j);
        latitude{row,1} = features(j).Y(:);
        longitude{row,1} = features(j).X(:);
    end
    next = next + count;
end

crests = table(crestIdx, sceneId, sceneFile, fileName, featureIndex, ...
    sensingTime, latitude, longitude, ...
    'VariableNames', {'crest_idx','scene_id','scene_file','file_name', ...
    'feature_index','sensing_time','latitude','longitude'});
end
