function [allResults, differences, summary] = compare_all_crests_pass_methods(maxCrests, crestTypes)
%COMPARE_ALL_CRESTS_PASS_METHODS Compare ternary and analytic geometry.
%
% Each remote-sensing crest is tested once per requested mode. Mooring event
% times and observed directions are intentionally excluded so that the result
% only measures whether the translated crest can enter the mooring radius.
%
% Examples:
%   [allResults, differences, summary] = ...
%       compare_all_crests_pass_methods(500, [1 2]);
%   [allResults, differences, summary] = ...
%       compare_all_crests_pass_methods();

if nargin < 1 || isempty(maxCrests)
    maxCrests = inf;
end
if nargin < 2 || isempty(crestTypes)
    crestTypes = [1 2];
end
if ~isscalar(maxCrests) || maxCrests <= 0
    error('maxCrests must be a positive scalar or inf.');
end
crestTypes = unique(crestTypes(:)', 'stable');
if any(~ismember(crestTypes, [1 2]))
    error('crestTypes can only contain mode 1 and/or mode 2.');
end

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(projectRoot, 'utils')));

shpDir = 'F:\research\MODIS\shp_files';
moorLat = 20.816666666666666;
moorLon = 115.76666666666667;
teps = 60;
tlim = 86400 * 10;
radius = 100000;

if ~isfolder(shpDir)
    error('Shapefile directory not found: %s', shpDir);
end
shpFiles = dir(fullfile(shpDir, '*.shp'));
if isempty(shpFiles)
    error('No shapefiles found under %s.', shpDir);
end

sourceFile = strings(0,1);
localCrestIndex = zeros(0,1);
globalCrestIndexOut = zeros(0,1);
crestTimeOut = NaT(0,1);
modeOut = zeros(0,1);
directionDeg = zeros(0,1);
pointCount = zeros(0,1);
legacySegmentCountOut = zeros(0,1);
allSegmentCountOut = zeros(0,1);
oldIsPass = false(0,1);
capsuleLegacySegmentsPass = false(0,1);
capsuleAllSegmentsPass = false(0,1);
oldMinDistanceM = zeros(0,1);
capsuleLegacyMinDistanceM = zeros(0,1);
capsuleAllMinDistanceM = zeros(0,1);
sameSearchSegments = false(0,1);
sameAllSegments = false(0,1);
lastSegmentChanged = false(0,1);
boundaryMarginM = zeros(0,1);
differenceType = strings(0,1);

processedCrests = 0;
globalOffset = 0;
stopRequested = false;

for k = 1:numel(shpFiles)
    shpPath = fullfile(shpDir, shpFiles(k).name);
    crestTime = getTimeFromFilename(shpPath) + hours(8);
    crestLines = shaperead(shpPath);

    for i = 1:numel(crestLines)
        if processedCrests >= maxCrests
            stopRequested = true;
            break;
        end
        processedCrests = processedCrests + 1;

        rawLat = crestLines(i).Y;
        rawLon = crestLines(i).X;
        good = isfinite(rawLat) & isfinite(rawLon);
        lat = rawLat(good);
        lon = rawLon(good);
        lat = lat(:);
        lon = lon(:);

        nSegments = max(numel(lat)-1, 0);
        % Match the old loop 1:length(rawLat)-2 while staying inside the
        % cleaned coordinate arrays. A trailing shapefile NaN usually makes
        % this equal to all valid segments.
        legacySegments = min(max(numel(rawLat)-2, 0), nSegments);
        cDir = crestDirectionLikeOld(rawLat, rawLon, moorLat, moorLon);

        if numel(lat) >= 2
            lat0 = mean(lat);
            lon0 = mean(lon);
            [x, y] = ll2local(lat, lon, lat0, lon0);
            [qx, qy] = ll2local(moorLat, moorLon, lat0, lon0);
            q = [qx; qy];
            u = [sind(cDir); cosd(cDir)];
            u = u / norm(u);
        else
            x = zeros(0,1);
            y = zeros(0,1);
            q = [NaN; NaN];
            u = [NaN; NaN];
        end

        for crestType = crestTypes
            cMin = minimumModeSpeed(crestType);
            dLimit = cMin * tlim;

            % The dummy event lies outside the ternary search interval. It
            % prevents the old east/west early return and keeps its while
            % loop controlled by interval width rather than mooring time.
            dummyStart = crestTime - seconds(2*tlim);
            dummyEnd = crestTime + seconds(2*tlim);
            [oldPass, ~, oldMinDis] = isCrestPassMooring_bin_dir( ...
                rawLat, rawLon, crestTime, crestType, moorLat, moorLon, ...
                dummyStart, dummyEnd, teps, tlim, radius);

            [capsuleLegacyPass, capsuleLegacyMin] = capsuleSweepPass( ...
                x, y, q, u, legacySegments, dLimit, radius);
            [capsuleAllPass, capsuleAllMin] = capsuleSweepPass( ...
                x, y, q, u, nSegments, dLimit, radius);

            row = numel(oldIsPass) + 1;
            sourceFile(row,1) = string(shpFiles(k).name);
            localCrestIndex(row,1) = i;
            globalCrestIndexOut(row,1) = globalOffset + i;
            crestTimeOut(row,1) = crestTime;
            modeOut(row,1) = crestType;
            directionDeg(row,1) = cDir;
            pointCount(row,1) = numel(lat);
            legacySegmentCountOut(row,1) = legacySegments;
            allSegmentCountOut(row,1) = nSegments;
            oldIsPass(row,1) = logical(oldPass);
            capsuleLegacySegmentsPass(row,1) = capsuleLegacyPass;
            capsuleAllSegmentsPass(row,1) = capsuleAllPass;
            oldMinDistanceM(row,1) = oldMinDis;
            capsuleLegacyMinDistanceM(row,1) = capsuleLegacyMin;
            capsuleAllMinDistanceM(row,1) = capsuleAllMin;
            sameSearchSegments(row,1) = logical(oldPass) == capsuleLegacyPass;
            sameAllSegments(row,1) = logical(oldPass) == capsuleAllPass;
            lastSegmentChanged(row,1) = capsuleLegacyPass ~= capsuleAllPass;
            boundaryMarginM(row,1) = abs(capsuleLegacyMin-radius);
            differenceType(row,1) = classifyDifference(logical(oldPass), capsuleAllPass);
        end

        if mod(processedCrests, 250) == 0
            fprintf('Processed %d crests.\n', processedCrests);
        end
    end

    globalOffset = globalOffset + numel(crestLines);
    if stopRequested, break; end
end

allResults = table(sourceFile, localCrestIndex, globalCrestIndexOut, ...
    crestTimeOut, modeOut, directionDeg, pointCount, ...
    legacySegmentCountOut, allSegmentCountOut, oldIsPass, ...
    capsuleLegacySegmentsPass, capsuleAllSegmentsPass, ...
    oldMinDistanceM, capsuleLegacyMinDistanceM, capsuleAllMinDistanceM, ...
    sameSearchSegments, sameAllSegments, lastSegmentChanged, ...
    boundaryMarginM, differenceType, ...
    'VariableNames', {'source_file','local_crest_idx','global_crest_idx', ...
    'crest_time','mode','direction_deg','point_count', ...
    'legacy_segment_count','all_segment_count','old_isPass', ...
    'capsule_legacy_segments_isPass','capsule_all_segments_isPass', ...
    'old_min_distance_m','capsule_legacy_min_distance_m', ...
    'capsule_all_min_distance_m','same_search_segments', ...
    'same_all_segments','last_segment_changed','boundary_margin_m', ...
    'difference_type'});

differences = allResults(~allResults.same_all_segments, :);
summary = buildSummary(allResults, crestTypes);

disp(summary);
if ~isempty(differences)
    disp(differences(1:min(30,height(differences)), :));
end
end

function cDir = crestDirectionLikeOld(lat, lon, moorLat, moorLon)
cDir = mod(90-calcDirection(lat, lon), 360);
if cDir > 45 && cDir < 180
    [dirDegOut, doFlip, ~] = maybeFlipCrestDir(lat, lon, moorLat, moorLon);
    if doFlip
        cDir = dirDegOut;
    end
end
end

function cMin = minimumModeSpeed(crestType)
if crestType == 1
    cMin = 1;
else
    cMin = 0.3;
end
end

function [isPass, minDistance] = capsuleSweepPass(x, y, q, u, segmentCount, dLimit, radius)
isPass = false;
minDistance = inf;
if segmentCount < 1 || any(~isfinite(q)) || any(~isfinite(u))
    return;
end

for i = 1:segmentCount
    a = [x(i); y(i)];
    b = [x(i+1); y(i+1)];
    distance = pointToSweptSegmentDistance(q, a, b, u, -dLimit, dLimit);
    minDistance = min(minDistance, distance);
end
isPass = minDistance <= radius + 1e-6;
end

function distance = pointToSweptSegmentDistance(q, a, b, u, dLo, dHi)
% Segment AB swept over [dLo,dHi] forms a parallelogram.
aLo = a + dLo*u;
bLo = b + dLo*u;
bHi = b + dHi*u;
aHi = a + dHi*u;
polygon = [aLo, bLo, bHi, aHi];

[inside, onBoundary] = inpolygon(q(1), q(2), polygon(1,:), polygon(2,:));
if inside || onBoundary
    distance = 0;
    return;
end

distance = inf;
for k = 1:4
    next = mod(k,4) + 1;
    distance = min(distance, ...
        pointToSegmentDistance(q, polygon(:,k), polygon(:,next)));
end
end

function distance = pointToSegmentDistance(p, a, b)
ab = b-a;
denom = dot(ab,ab);
if denom <= eps
    distance = norm(p-a);
    return;
end
t = dot(p-a,ab) / denom;
t = max(0,min(1,t));
distance = norm(p-(a+t*ab));
end

function label = classifyDifference(oldPass, newPass)
if oldPass == newPass
    label = "same";
elseif oldPass
    label = "old_only";
else
    label = "capsule_only";
end
end

function summary = buildSummary(results, crestTypes)
labels = ["ALL"; "MODE_" + string(crestTypes(:))];
n = numel(labels);
checked = zeros(n,1);
oldPass = zeros(n,1);
capsuleLegacyPass = zeros(n,1);
capsuleAllPass = zeros(n,1);
algorithmDifferences = zeros(n,1);
allSegmentDifferences = zeros(n,1);
lastSegmentChanges = zeros(n,1);
oldOnly = zeros(n,1);
capsuleOnly = zeros(n,1);

for k = 1:n
    if k == 1
        mask = true(height(results),1);
    else
        mask = results.mode == crestTypes(k-1);
    end
    part = results(mask,:);
    checked(k) = height(part);
    oldPass(k) = nnz(part.old_isPass);
    capsuleLegacyPass(k) = nnz(part.capsule_legacy_segments_isPass);
    capsuleAllPass(k) = nnz(part.capsule_all_segments_isPass);
    algorithmDifferences(k) = nnz(~part.same_search_segments);
    allSegmentDifferences(k) = nnz(~part.same_all_segments);
    lastSegmentChanges(k) = nnz(part.last_segment_changed);
    oldOnly(k) = nnz(part.old_isPass & ~part.capsule_all_segments_isPass);
    capsuleOnly(k) = nnz(~part.old_isPass & part.capsule_all_segments_isPass);
end

summary = table(labels, checked, oldPass, capsuleLegacyPass, capsuleAllPass, ...
    algorithmDifferences, allSegmentDifferences, lastSegmentChanges, ...
    oldOnly, capsuleOnly, ...
    'VariableNames', {'group','checked','old_pass','capsule_legacy_pass', ...
    'capsule_all_pass','algorithm_differences','all_segment_differences', ...
    'last_segment_changes','old_only','capsule_only'});
end

function [x, y] = ll2local(lat, lon, lat0, lon0)
x = (lon-lon0) .* cosd(lat0) * 111320;
y = (lat-lat0) * 110540;
end
