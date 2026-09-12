function report = compare_matched_result_sets(newMatPath, oldMatPath, runPhysicsRecheck)
%COMPARE_MATCHED_RESULT_SETS Compare two final crest/mooring match MAT files.
%
% The fast comparison aligns rows by mooring start time and mode, then
% reports retained assignments, changed assignments, missing events, new
% events, and turnover in the selected crest set.
%
% Examples
%   report = compare_matched_result_sets();
%   report = compare_matched_result_sets([], [], true);
%   report = compare_matched_result_sets(newMatPath, oldMatPath, false);
%
% Setting runPhysicsRecheck=true additionally reloads the original SHP
% crests and mooring Excel file from F: and tests every old pair with the
% current isCrestPassMooring_capsule_dir implementation. This is slower.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
if nargin < 1 || isempty(newMatPath)
    newMatPath = fullfile(projectRoot, 'TMP', ...
        'matched_results_with_capsules.mat');
end
if nargin < 2 || isempty(oldMatPath)
    oldMatPath = fullfile(projectRoot, 'data', ...
        'matched_crests_params_855.mat');
end
if nargin < 3 || isempty(runPhysicsRecheck)
    runPhysicsRecheck = false;
end
if ~isscalar(runPhysicsRecheck)
    error('runPhysicsRecheck must be a scalar logical value.');
end
runPhysicsRecheck = logical(runPhysicsRecheck);

newResults = loadResultSet(newMatPath, {'crest_idx', 'crest_idx_out'});
oldResults = loadResultSet(oldMatPath, {'crest_idx_out', 'crest_idx'});

[common, oldOnly, newOnly, summary] = compareResultSets( ...
    newResults, oldResults);

report = struct();
report.new_mat = string(newResults.path);
report.old_mat = string(oldResults.path);
report.summary = summary;
report.common = common;
report.changed = common(~common.same_assignment, :);
report.old_only = oldOnly;
report.new_only = newOnly;
report.old_pair_recheck = table();
report.old_pair_recheck_summary = table();

fprintf('\nMatched-result comparison\n');
fprintf('  New: %s\n', newResults.path);
fprintf('  Old: %s\n\n', oldResults.path);
disp(summary);

if runPhysicsRecheck
    addpath(genpath(fullfile(projectRoot, 'utils')));
    [pairCheck, reasonSummary] = recheckOldPairs(oldResults);
    report.old_pair_recheck = pairCheck;
    report.old_pair_recheck_summary = reasonSummary;

    fprintf('\nOld-pair physical recheck with current method\n');
    fprintf('  Still pass: %d / %d (%.2f%%)\n', ...
        nnz(pairCheck.is_pass), height(pairCheck), ...
        100 * mean(pairCheck.is_pass));
    disp(reasonSummary);
end
end

function result = loadResultSet(matPath, crestIndexFields)
matPath = char(matPath);
if ~isfile(matPath)
    error('MAT file not found: %s', matPath);
end

loaded = load(matPath);
names = fieldnames(loaded);
if isscalar(names) && isstruct(loaded.(names{1}))
    loaded = loaded.(names{1});
end

result = struct();
result.path = matPath;
result.mode = double(requireField(loaded, {'mode'}));
result.mooringTime = toDatetime(requireField(loaded, {'mooring_time'}));
result.crestTime = toDatetime(requireField(loaded, {'crest_time'}));
result.crestIdx = double(requireField(loaded, crestIndexFields));
result.crestDir = double(requireField(loaded, {'crest_dir'}));
result.peakLat = double(requireField(loaded, {'peak_lat'}));
result.peakLon = double(requireField(loaded, {'peak_lon'}));

result.mode = result.mode(:);
result.mooringTime = result.mooringTime(:);
result.crestTime = result.crestTime(:);
result.crestIdx = result.crestIdx(:);
result.crestDir = result.crestDir(:);
result.peakLat = result.peakLat(:);
result.peakLon = result.peakLon(:);
result.n = numel(result.mode);

fields = {'mooringTime','crestTime','crestIdx','crestDir','peakLat','peakLon'};
for k = 1:numel(fields)
    if numel(result.(fields{k})) ~= result.n
        error('Length mismatch for %s in %s.', fields{k}, matPath);
    end
end

result.eventKey = eventKey(result.mooringTime, result.mode);
if any(~isfinite(result.eventKey), 'all')
    error('Invalid mooring time or mode in %s.', matPath);
end
if size(unique(result.eventKey, 'rows'), 1) ~= result.n
    error('Mooring time + mode is not unique in %s.', matPath);
end
end

function [common, oldOnly, newOnly, summary] = compareResultSets(new, old)
[oldFound, newLocation] = ismember(old.eventKey, new.eventKey, 'rows');
[newFound, ~] = ismember(new.eventKey, old.eventKey, 'rows');

oldRows = find(oldFound);
newRows = newLocation(oldFound);
sameCrestIdx = old.crestIdx(oldRows) == new.crestIdx(newRows);
sameCrestTime = old.crestTime(oldRows) == new.crestTime(newRows);
sameAssignment = sameCrestIdx & sameCrestTime;

peakDistanceKm = localDistanceKm( ...
    old.peakLat(oldRows), old.peakLon(oldRows), ...
    new.peakLat(newRows), new.peakLon(newRows));
crestTimeDifferenceHours = abs(hours( ...
    new.crestTime(newRows) - old.crestTime(oldRows)));
directionDifferenceDeg = circularDifference( ...
    new.crestDir(newRows), old.crestDir(oldRows));

common = table(oldRows, newRows, old.mooringTime(oldRows), ...
    old.mode(oldRows), old.crestIdx(oldRows), new.crestIdx(newRows), ...
    old.crestTime(oldRows), new.crestTime(newRows), ...
    old.crestDir(oldRows), new.crestDir(newRows), ...
    sameCrestIdx, sameCrestTime, sameAssignment, peakDistanceKm, ...
    crestTimeDifferenceHours, directionDifferenceDeg, ...
    'VariableNames', {'old_row','new_row','mooring_time','mode', ...
    'old_crest_idx','new_crest_idx','old_crest_time','new_crest_time', ...
    'old_direction_deg','new_direction_deg','same_crest_idx', ...
    'same_crest_time','same_assignment','peak_distance_km', ...
    'crest_time_difference_hours','direction_difference_deg'});

oldOnly = resultRows(old, find(~oldFound));
newOnly = resultRows(new, find(~newFound));

oldCrestKey = crestKey(old.crestTime, old.crestIdx);
newCrestKey = crestKey(new.crestTime, new.crestIdx);
oldCrestReused = ismember(oldCrestKey, newCrestKey, 'rows');
newCrestPreviouslyUsed = ismember(newCrestKey, oldCrestKey, 'rows');

changed = ~sameAssignment;
newPairs = new.n;
oldPairs = old.n;
commonMoorings = height(common);
oldOnlyMoorings = height(oldOnly);
newOnlyMoorings = height(newOnly);
sameAssignments = nnz(sameAssignment);
changedAssignments = nnz(changed);
oldCrestsReused = nnz(oldCrestReused);
oldCrestsNotReused = nnz(~oldCrestReused);
newCrestsNotInOld = nnz(~newCrestPreviouslyUsed);
changedPeakMedianKm = finiteMedian(peakDistanceKm(changed));
changedPeakP90Km = finitePercentile(peakDistanceKm(changed), 90);
changedTimeMedianHours = finiteMedian(crestTimeDifferenceHours(changed));
changedTimeP90Hours = finitePercentile(crestTimeDifferenceHours(changed), 90);
changedDirectionMedianDeg = finiteMedian(directionDifferenceDeg(changed));

summary = table(newPairs, oldPairs, commonMoorings, oldOnlyMoorings, ...
    newOnlyMoorings, sameAssignments, changedAssignments, ...
    oldCrestsReused, oldCrestsNotReused, newCrestsNotInOld, ...
    changedPeakMedianKm, changedPeakP90Km, changedTimeMedianHours, ...
    changedTimeP90Hours, changedDirectionMedianDeg, ...
    'VariableNames', {'new_pairs','old_pairs','common_moorings', ...
    'old_only_moorings','new_only_moorings','same_assignments', ...
    'changed_assignments','old_crests_reused','old_crests_not_reused', ...
    'new_crests_not_in_old','changed_peak_median_km', ...
    'changed_peak_p90_km','changed_time_median_hours', ...
    'changed_time_p90_hours','changed_direction_median_deg'});
end

function rows = resultRows(result, indices)
indices = indices(:);
rows = table(indices, result.mooringTime(indices), result.mode(indices), ...
    result.crestIdx(indices), result.crestTime(indices), ...
    result.crestDir(indices), result.peakLat(indices), ...
    result.peakLon(indices), ...
    'VariableNames', {'row','mooring_time','mode','crest_idx', ...
    'crest_time','direction_deg','peak_lat','peak_lon'});
end

function [pairCheck, reasonSummary] = recheckOldPairs(old)
shpDir = 'F:\research\MODIS\shp_files';
mooringPath = 'F:\research\月份挑内波数据\2020年内波时间与方向.xlsx';
moorLat = 20.816666666666666;
moorLon = 115.76666666666667;
teps = 60;
tlim = 86400 * 10;
radius = 100000;

if ~isfolder(shpDir)
    error('Shapefile directory not found: %s', shpDir);
end
if ~isfile(mooringPath)
    error('Mooring table not found: %s', mooringPath);
end

mooringTable = readtable(mooringPath);
obsModes = double(mooringTable{:,1});
startTimes = toDatetime(mooringTable{:,2});
endTimes = toDatetime(mooringTable{:,3});
sourceEventKey = eventKey(startTimes, obsModes);
[mooringFound, mooringIdx] = ismember( ...
    old.eventKey, sourceEventKey, 'rows');

maxCrestIdx = max(old.crestIdx);
if ~isfinite(maxCrestIdx) || maxCrestIdx < 1 || maxCrestIdx ~= fix(maxCrestIdx)
    error('Old MAT contains an invalid crest index.');
end
rawLat = cell(maxCrestIdx, 1);
rawLon = cell(maxCrestIdx, 1);
rawTime = NaT(maxCrestIdx, 1);
needed = unique(old.crestIdx);

shpFiles = dir(fullfile(shpDir, '*.shp'));
globalOffset = 0;
for k = 1:numel(shpFiles)
    shpPath = fullfile(shpDir, shpFiles(k).name);
    % Capture missing-DBF warnings; only the SHP geometry is needed here.
    evalc('crestLines = shaperead(shpPath);');
    globalIndices = globalOffset + (1:numel(crestLines));
    selected = find(ismember(globalIndices, needed));
    if ~isempty(selected)
        sensingTime = getTimeFromFilename(shpPath) + hours(8);
        for selectedIdx = 1:numel(selected)
            j = selected(selectedIdx);
            globalIdx = globalIndices(j);
            rawLat{globalIdx} = crestLines(j).Y;
            rawLon{globalIdx} = crestLines(j).X;
            rawTime(globalIdx) = sensingTime;
        end
    end
    globalOffset = globalOffset + numel(crestLines);
end

n = old.n;
isPass = false(n,1);
reason = strings(n,1);
sourceTimeMatches = false(n,1);
speedMinMps = nan(n,1);
speedMaxMps = nan(n,1);

for i = 1:n
    crestIdx = old.crestIdx(i);
    crestFound = crestIdx >= 1 && crestIdx <= numel(rawLat) && ...
        ~isempty(rawLat{crestIdx});
    if ~mooringFound(i)
        reason(i) = "mooring_not_found";
        continue;
    end
    if ~crestFound
        reason(i) = "crest_not_found";
        continue;
    end

    sourceTimeMatches(i) = rawTime(crestIdx) == old.crestTime(i);
    [isPass(i), propSpeed, ~, details] = ...
        isCrestPassMooring_capsule_dir( ...
        rawLat{crestIdx}, rawLon{crestIdx}, old.crestTime(i), ...
        old.mode(i), moorLat, moorLon, ...
        startTimes(mooringIdx(i)), endTimes(mooringIdx(i)), ...
        teps, tlim, radius);
    reason(i) = details.reason;
    if isPass(i) && ~isempty(propSpeed)
        speedMinMps(i) = min(propSpeed);
        speedMaxMps(i) = max(propSpeed);
    end
end

oldRow = (1:n)';
pairCheck = table(oldRow, old.mooringTime, old.mode, old.crestIdx, ...
    old.crestTime, sourceTimeMatches, isPass, reason, ...
    speedMinMps, speedMaxMps, ...
    'VariableNames', {'old_row','mooring_time','mode','crest_idx', ...
    'crest_time','source_time_matches','is_pass','reason', ...
    'speed_min_mps','speed_max_mps'});

[reasonLabel, ~, group] = unique(reason);
count = accumarray(group, 1);
reasonSummary = table(reasonLabel, count, ...
    'VariableNames', {'reason','count'});
end

function key = eventKey(mooringTime, mode)
key = [posixtime(mooringTime(:)), double(mode(:))];
end

function key = crestKey(crestTime, crestIdx)
key = [posixtime(crestTime(:)), double(crestIdx(:))];
end

function distanceKm = localDistanceKm(lat1, lon1, lat2, lon2)
meanLat = (lat1 + lat2) / 2;
dx = (lon2-lon1) .* cosd(meanLat) * 111.32;
dy = (lat2-lat1) * 110.54;
distanceKm = hypot(dx, dy);
end

function difference = circularDifference(a, b)
difference = abs(mod(a-b+180, 360)-180);
end

function value = finiteMedian(values)
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = median(values);
end
end

function value = finitePercentile(values, percentile)
values = sort(values(isfinite(values)));
if isempty(values)
    value = NaN;
    return;
end
position = 1 + (numel(values)-1) * percentile / 100;
lo = floor(position);
hi = ceil(position);
if lo == hi
    value = values(lo);
else
    value = values(lo) + (position-lo) * (values(hi)-values(lo));
end
end

function value = requireField(data, candidates)
for k = 1:numel(candidates)
    if isfield(data, candidates{k})
        value = data.(candidates{k});
        return;
    end
end
error('Missing required field. Tried: %s', strjoin(candidates, ', '));
end

function value = toDatetime(value)
if isa(value, 'datetime')
    value = value(:);
elseif isnumeric(value)
    value = datetime(value(:), 'ConvertFrom', 'datenum');
else
    value = datetime(value(:));
end
end
