function outputPath = export_closest_direction_matches_mat(reportPath, outputPath)
%EXPORT_CLOSEST_DIRECTION_MATCHES_MAT 将最新分配结果导出为可视化兼容 MAT。

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(projectRoot, 'utils')));

if nargin < 1 || isempty(reportPath)
    reportPath = fullfile(projectRoot, 'tmp', ...
        'closest_direction_recheck.mat');
end
if nargin < 2 || isempty(outputPath)
    outputPath = fullfile(projectRoot, 'tmp', ...
        'matched_results_with_capsules_848.mat');
end

loaded = load(reportPath);
assert(isfield(loaded, 'report'), 'Missing report in %s.', reportPath);
report = loaded.report;
scenarioIndex = report.baseline_delta_index;
pairs = report.scenario_pairs{scenarioIndex};
assert(size(pairs, 2) == 2, 'scenario_pairs must contain [crest,event].');

n = size(pairs, 1);
mode = nan(n, 1);
mooring_time = NaT(n, 1);
crest_time = NaT(n, 1);
crest_idx = nan(n, 1);
event_idx = nan(n, 1);
crest_dir = nan(n, 1);
crest_lon = cell(n, 1);
crest_lat = cell(n, 1);
peak_lon = nan(n, 1);
peak_lat = nan(n, 1);
K_mooring = nan(n, 1);
kdv_speed = nan(n, 1);
speed_diff = nan(n, 1);
dir_diff = nan(n, 1);
closest_along_m = nan(n, 1);
closest_cross_m = nan(n, 1);
closest_point_lon = nan(n, 1);
closest_point_lat = nan(n, 1);
closest_direction_status = nan(n, 1);

shapeCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
for i = 1:n
    cIdx = pairs(i, 1);
    eIdx = pairs(i, 2);
    catalogRow = report.crest_catalog( ...
        report.crest_catalog.crest_idx == cIdx, :);
    assert(height(catalogRow) == 1, ...
        'Expected one catalog row for crest %d.', cIdx);

    fileName = char(catalogRow.file_name);
    if isKey(shapeCache, fileName)
        features = shapeCache(fileName);
    else
        shapePath = fullfile(report.config.shpDir, fileName);
        assert(isfile(shapePath), 'Missing SHP file: %s', shapePath);
        evalc('features = shaperead(shapePath);');
        shapeCache(fileName) = features;
    end
    feature = features(catalogRow.feature_index);
    rawLat = feature.Y;
    rawLon = feature.X;

    [resLat, resLon, pLat, pLon, sPeak, totalLength] = ...
        analyze_crest_shape_orig(rawLat, rawLon, 250);
    assert(~isempty(resLat) && ~isempty(resLon), ...
        'Failed to resample crest %d.', cIdx);

    event = report.events(eIdx, :);
    [isPass, propSpeed, ~, details] = ...
        isCrestPassMooring_capsule_dir( ...
        rawLat, rawLon, catalogRow.sensing_time, event.mode, ...
        report.config.mooringLat, report.config.mooringLon, ...
        event.start_time, event.end_time, ...
        report.config.searchToleranceSeconds, ...
        report.config.timeLimitSeconds, report.config.radiusMeters);
    physicsValid = isPass && (details.closestDirectionStatus == 1 || ...
        details.directOverlap);
    assert(physicsValid, ...
        'Assigned pair crest=%d event=%d failed current physics.', ...
        cIdx, eIdx);

    targetSpeed = event.local_speed_mps;
    speedRange = sort(abs(propSpeed));
    if targetSpeed >= speedRange(1) && targetSpeed <= speedRange(end)
        speedDifference = 0;
    else
        speedDifference = min(abs(speedRange-targetSpeed));
    end

    directionDifference = abs(details.dirDeg-event.direction_deg);
    if directionDifference > 180
        directionDifference = 360-directionDifference;
    end

    [kPass, ~, sHit] = reachMooringByTranslation( ...
        resLat, resLon, catalogRow.sensing_time, ...
        report.config.mooringLat, report.config.mooringLon, ...
        [0.1 5.0], report.config.radiusMeters);
    if kPass && isfinite(sHit) && totalLength > 0
        sHit = max(0, min(sHit, totalLength));
        if sHit <= sPeak
            K = (sHit-sPeak) / max(sPeak, 1e-3);
        else
            K = (sHit-sPeak) / max(totalLength-sPeak, 1e-3);
        end
    else
        K = NaN;
    end

    [pointLat, pointLon] = closestPointLatLon( ...
        rawLat, rawLon, details.closestSegment, ...
        details.closestSegmentParameter);

    mode(i) = event.mode;
    mooring_time(i) = event.start_time;
    crest_time(i) = catalogRow.sensing_time;
    crest_idx(i) = cIdx;
    event_idx(i) = eIdx;
    crest_dir(i) = details.dirDeg;
    crest_lon{i} = resLon;
    crest_lat{i} = resLat;
    peak_lon(i) = pLon;
    peak_lat(i) = pLat;
    K_mooring(i) = K;
    kdv_speed(i) = targetSpeed;
    speed_diff(i) = speedDifference;
    dir_diff(i) = directionDifference;
    closest_along_m(i) = details.closestAlongDisplacementMeters;
    closest_cross_m(i) = details.closestSignedCrossTrackMeters;
    closest_point_lon(i) = pointLon;
    closest_point_lat(i) = pointLat;
    closest_direction_status(i) = details.closestDirectionStatus;
end

[mooring_time, order] = sort(mooring_time);
mode = mode(order);
crest_time = crest_time(order);
crest_idx = crest_idx(order);
event_idx = event_idx(order);
crest_dir = crest_dir(order);
crest_lon = crest_lon(order);
crest_lat = crest_lat(order);
peak_lon = peak_lon(order);
peak_lat = peak_lat(order);
K_mooring = K_mooring(order);
kdv_speed = kdv_speed(order);
speed_diff = speed_diff(order);
dir_diff = dir_diff(order);
closest_along_m = closest_along_m(order);
closest_cross_m = closest_cross_m(order);
closest_point_lon = closest_point_lon(order);
closest_point_lat = closest_point_lat(order);
closest_direction_status = closest_direction_status(order);

[outDir, ~, ~] = fileparts(outputPath);
if ~isempty(outDir) && ~isfolder(outDir)
    mkdir(outDir);
end
save(outputPath, 'mode', 'mooring_time', 'crest_time', 'crest_idx', ...
    'event_idx', 'crest_dir', 'crest_lon', 'crest_lat', ...
    'peak_lon', 'peak_lat', 'K_mooring', 'kdv_speed', 'speed_diff', ...
    'dir_diff', 'closest_along_m', 'closest_cross_m', ...
    'closest_point_lon', 'closest_point_lat', ...
    'closest_direction_status');

fprintf('Wrote %s (%d matched pairs)\n', outputPath, n);
end

function [pointLat, pointLon] = closestPointLatLon( ...
        rawLat, rawLon, segmentIndex, segmentParameter)
good = isfinite(rawLat) & isfinite(rawLon);
lat = rawLat(good);
lon = rawLon(good);
lat = lat(:);
lon = lon(:);
assert(segmentIndex >= 1 && segmentIndex < numel(lat), ...
    'Invalid closest segment index.');
t = max(0, min(1, segmentParameter));
pointLat = lat(segmentIndex) + t*(lat(segmentIndex+1)-lat(segmentIndex));
pointLon = lon(segmentIndex) + t*(lon(segmentIndex+1)-lon(segmentIndex));
end
