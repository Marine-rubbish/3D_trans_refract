function report = analyze_matching_sensitivity(deltaValues, config)
%ANALYZE_MATCHING_SENSITIVITY Re-match with path/local speed scenarios.
%
% This analysis keeps the current candidate geometry, time window, and
% unmatched cost fixed. Only the assumed relation between path-average
% speed and the event's local mooring speed changes:
%
%   c_path = (1 + delta) * c_mooring
%
% The result measures assignment sensitivity to that assumption. It does
% not estimate the physical error rate or prove that changed pairs improve.
%
% No files are written. All outputs are returned in REPORT.
%
% Examples
%   report = analyze_matching_sensitivity();
%   report = analyze_matching_sensitivity([-0.2 0 0.2]);
%   report = analyze_matching_sensitivity([], struct( ...
%       'dayWindow', 2, 'radiusMeters', 60000));

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(projectRoot, 'utils')));

if nargin < 1 || isempty(deltaValues)
    deltaValues = [-0.4 -0.2 -0.1 0 0.1 0.2 0.4];
end
if nargin < 2 || isempty(config)
    config = struct();
end

config = applyDefaults(config, projectRoot);
deltaValues = validateDeltaValues(deltaValues);
validateInputs(config);

events = readEvents(config.mooringPath);
crests = readCrests(config.shpDir, config.timeOffsetHours);

fprintf('Building fixed candidate set for %d crests and %d events...\n', ...
    height(crests), height(events));
[candidate, candidateStats] = buildCandidateSet(crests, events, config);

scenarioCount = numel(deltaValues);
assignments = zeros(height(events), scenarioCount);
scenarioPairs = cell(scenarioCount, 1);

delta = nan(scenarioCount, 1);
pairCount = zeros(scenarioCount, 1);
unmatchedEventCount = zeros(scenarioCount, 1);
zeroCostEdgeCount = zeros(scenarioCount, 1);
eventsWithMultipleZeroEdges = zeros(scenarioCount, 1);
totalAssignmentCost = nan(scenarioCount, 1);

for k = 1:scenarioCount
    delta(k) = deltaValues(k);
    weights = buildWeights(candidate, events.local_speed_mps, delta(k));
    [pairs, unmatchedCrests, unmatchedEvents] = ...
        matchpairs(weights, config.unmatchedCost);

    eventAssignment = zeros(height(events), 1);
    eventAssignment(pairs(:,2)) = pairs(:,1);
    assignments(:,k) = eventAssignment;
    scenarioPairs{k} = pairs;

    pairCount(k) = size(pairs, 1);
    unmatchedEventCount(k) = numel(unmatchedEvents);
    zeroMask = candidate.mask & abs(weights) <= config.tieTolerance;
    zeroCostEdgeCount(k) = nnz(zeroMask);
    eventsWithMultipleZeroEdges(k) = nnz(sum(zeroMask, 1) >= 2);
    pairLinearIdx = sub2ind(size(weights), pairs(:,1), pairs(:,2));
    totalAssignmentCost(k) = sum(weights(pairLinearIdx)) + ...
        config.unmatchedCost * ...
        (numel(unmatchedCrests) + numel(unmatchedEvents));
end

baselineIdx = find(abs(delta) <= eps, 1);
baseline = assignments(:,baselineIdx);

sameCount = zeros(scenarioCount, 1);
switchedCount = zeros(scenarioCount, 1);
droppedCount = zeros(scenarioCount, 1);
addedCount = zeros(scenarioCount, 1);
bothUnmatchedCount = zeros(scenarioCount, 1);
changeRate = nan(scenarioCount, 1);
switchRate = nan(scenarioCount, 1);
changeRows = cell(scenarioCount, 1);

for k = 1:scenarioCount
    current = assignments(:,k);
    same = baseline > 0 & current == baseline;
    switched = baseline > 0 & current > 0 & current ~= baseline;
    dropped = baseline > 0 & current == 0;
    added = baseline == 0 & current > 0;
    bothUnmatched = baseline == 0 & current == 0;

    sameCount(k) = nnz(same);
    switchedCount(k) = nnz(switched);
    droppedCount(k) = nnz(dropped);
    addedCount(k) = nnz(added);
    bothUnmatchedCount(k) = nnz(bothUnmatched);

    baselineMatched = sameCount(k) + switchedCount(k) + droppedCount(k);
    commonMatched = sameCount(k) + switchedCount(k);
    if baselineMatched > 0
        changeRate(k) = ...
            (switchedCount(k) + droppedCount(k)) / baselineMatched;
    end
    if commonMatched > 0
        switchRate(k) = switchedCount(k) / commonMatched;
    end

    changed = switched | dropped | added;
    changeRows{k} = table( ...
        events.event_id(changed), events.start_time(changed), ...
        events.mode(changed), repmat(delta(k), nnz(changed), 1), ...
        baseline(changed), current(changed), ...
        categoricalStatus(switched(changed), dropped(changed), added(changed)), ...
        'VariableNames', {'event_id','event_start_time','mode','delta', ...
        'baseline_crest_idx','scenario_crest_idx','status'});
end

summary = table(delta, pairCount, unmatchedEventCount, sameCount, ...
    switchedCount, droppedCount, addedCount, bothUnmatchedCount, ...
    changeRate, switchRate, zeroCostEdgeCount, ...
    eventsWithMultipleZeroEdges, totalAssignmentCost);

report = struct();
report.config = config;
report.summary = summary;
report.changes = vertcat(changeRows{:});
report.assignments = assignments;
report.delta_values = delta;
report.baseline_delta_index = baselineIdx;
report.candidate_stats = candidateStats;
report.events = events;
report.crest_catalog = crests(:, {'crest_idx','file_name', ...
    'feature_index','sensing_time'});
report.scenario_pairs = scenarioPairs;
report.interpretation = [ ...
    "changeRate is the fraction of baseline-matched events that switch " + ...
    "or become unmatched."; ...
    "switchRate excludes events that become unmatched."; ...
    "Changed assignments are not verified corrections without " + ...
    "independent correspondence labels."];

fprintf('\nPath/local speed sensitivity\n');
disp(summary);
end

function config = applyDefaults(config, projectRoot)
defaults = struct( ...
    'shpDir', fullfile(projectRoot, 'data', 'shp_files'), ...
    'mooringPath', fullfile(projectRoot, 'data', ...
        '月份挑内波数据', '2020年内波时间与方向.xlsx'), ...
    'mooringLat', 20.816666666666666, ...
    'mooringLon', 115.76666666666667, ...
    'dayWindow', 3, ...
    'timeOffsetHours', 8, ...
    'searchToleranceSeconds', 60, ...
    'timeLimitSeconds', 86400 * 10, ...
    'radiusMeters', 100000, ...
    'unmatchedCost', 10000000, ...
    'tieTolerance', 1e-12);

names = fieldnames(defaults);
for k = 1:numel(names)
    name = names{k};
    if ~isfield(config, name) || isempty(config.(name))
        config.(name) = defaults.(name);
    end
end
end

function deltaValues = validateDeltaValues(deltaValues)
deltaValues = double(deltaValues(:));
if isempty(deltaValues) || any(~isfinite(deltaValues)) || ...
        any(deltaValues <= -1)
    error('deltaValues must be finite and greater than -1.');
end
if ~any(abs(deltaValues) <= eps)
    deltaValues = [0; deltaValues];
end
deltaValues = unique(deltaValues, 'stable');
end

function validateInputs(config)
if ~isfolder(config.shpDir)
    error('Shapefile directory not found: %s', config.shpDir);
end
if ~isfile(config.mooringPath)
    error('Mooring table not found: %s', config.mooringPath);
end
if ~isscalar(config.unmatchedCost) || ...
        ~isfinite(config.unmatchedCost) || config.unmatchedCost <= 0
    error('unmatchedCost must be a finite positive scalar.');
end
end

function events = readEvents(mooringPath)
source = readtable(mooringPath);
if width(source) < 5
    error('Mooring table must contain at least five columns.');
end

eventId = (1:height(source))';
mode = double(source{:,1});
startTime = toDatetime(source{:,2});
endTime = toDatetime(source{:,3});
localSpeedMps = double(source{:,4});
directionDeg = double(source{:,5});

valid = ismember(mode, [1 2]) & isfinite(localSpeedMps) & ...
    localSpeedMps > 0 & ~isnat(startTime) & ~isnat(endTime) & ...
    endTime >= startTime;
if ~all(valid)
    bad = eventId(~valid);
    error('Invalid mooring event rows: %s', ...
        strjoin(string(bad(1:min(20,numel(bad)))), ', '));
end

events = table(eventId, mode, startTime, endTime, ...
    localSpeedMps, directionDeg, ...
    'VariableNames', {'event_id','mode','start_time','end_time', ...
    'local_speed_mps','direction_deg'});
end

function crests = readCrests(shpDir, timeOffsetHours)
files = dir(fullfile(shpDir, '*.shp'));
if isempty(files)
    error('No SHP files found in %s.', shpDir);
end
[~, order] = sort(string({files.name}));
files = files(order);

crestIdx = zeros(0,1);
fileName = strings(0,1);
featureIndex = zeros(0,1);
sensingTime = NaT(0,1);
latitude = cell(0,1);
longitude = cell(0,1);

globalIdx = 0;
for k = 1:numel(files)
    shpPath = fullfile(files(k).folder, files(k).name);
    evalc('features = shaperead(shpPath);');
    fileTime = getTimeFromFilename(shpPath) + hours(timeOffsetHours);
    n = numel(features);
    rows = globalIdx + (1:n);

    crestIdx(rows,1) = rows';
    fileName(rows,1) = string(files(k).name);
    featureIndex(rows,1) = (1:n)';
    sensingTime(rows,1) = repmat(fileTime, n, 1);
    latitude(rows,1) = arrayfun(@(x) x.Y, features, ...
        'UniformOutput', false);
    longitude(rows,1) = arrayfun(@(x) x.X, features, ...
        'UniformOutput', false);

    globalIdx = globalIdx + n;
    if mod(k, 25) == 0 || k == numel(files)
        fprintf('  Read %d / %d SHP files, %d crests.\n', ...
            k, numel(files), globalIdx);
    end
end

crests = table(crestIdx, fileName, featureIndex, sensingTime, ...
    latitude, longitude, ...
    'VariableNames', {'crest_idx','file_name','feature_index', ...
    'sensing_time','latitude','longitude'});
end

function [candidate, stats] = buildCandidateSet(crests, events, config)
nCrests = height(crests);
nEvents = height(events);
mask = false(nCrests, nEvents);
speedLo = nan(nCrests, nEvents);
speedHi = nan(nCrests, nEvents);

evaluatedPairs = 0;
for i = 1:nCrests
    crestTime = crests.sensing_time(i);
    eventRows = find(events.start_time >= ...
        crestTime - days(config.dayWindow) & ...
        events.start_time <= crestTime + days(config.dayWindow));

    for p = 1:numel(eventRows)
        j = eventRows(p);
        [isPass, propSpeed] = isCrestPassMooring_capsule_dir( ...
            crests.latitude{i}, crests.longitude{i}, crestTime, ...
            events.mode(j), config.mooringLat, config.mooringLon, ...
            events.start_time(j), events.end_time(j), ...
            config.searchToleranceSeconds, config.timeLimitSeconds, ...
            config.radiusMeters);
        evaluatedPairs = evaluatedPairs + 1;

        if isPass
            lo = min(abs(propSpeed));
            hi = max(abs(propSpeed));
            if isfinite(lo) && ~isnan(hi) && lo <= hi
                mask(i,j) = true;
                speedLo(i,j) = lo;
                speedHi(i,j) = hi;
            end
        end
    end

    if mod(i, 100) == 0 || i == nCrests
        fprintf('  Evaluated crest %d / %d; candidates: %d.\n', ...
            i, nCrests, nnz(mask));
    end
end

candidate = struct('mask', mask, 'speed_lo_mps', speedLo, ...
    'speed_hi_mps', speedHi);
stats = table(nCrests, nEvents, evaluatedPairs, nnz(mask), ...
    nnz(any(mask,2)), nnz(any(mask,1)), ...
    'VariableNames', {'crest_count','event_count','evaluated_pairs', ...
    'candidate_edges','crests_with_candidates','events_with_candidates'});
end

function weights = buildWeights(candidate, localSpeedMps, delta)
target = (1 + delta) .* localSpeedMps(:)';
weights = max(candidate.speed_lo_mps - target, 0);
weights = max(weights, target - candidate.speed_hi_mps);
weights(~candidate.mask) = Inf;
end

function status = categoricalStatus(switched, dropped, added)
status = strings(numel(switched), 1);
status(switched) = "switched";
status(dropped) = "dropped";
status(added) = "added";
status = categorical(status, ["switched","dropped","added"]);
end

function value = toDatetime(value)
if isa(value, 'datetime')
    value = value(:);
elseif isnumeric(value)
    value = datetime(value(:), 'ConvertFrom', 'excel');
else
    value = datetime(value(:));
end
end
