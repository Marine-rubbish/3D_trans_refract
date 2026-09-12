function outputPath = export_matched_crests_animation_html(matPath, outputPath)
%EXPORT_MATCHED_CRESTS_ANIMATION_HTML Build a self-contained crest animation.
%   The matched speed is inferred consistently with validate_mat_physics:
%   speed = abs(along-track distance) / abs(mooring_time - crest_time).

projectRoot = fileparts(fileparts(mfilename('fullpath')));
if nargin < 1 || isempty(matPath)
    matPath = fullfile(projectRoot, 'TMP', 'matched_results_with_capsules.mat');
end
if nargin < 2 || isempty(outputPath)
    outputPath = fullfile(projectRoot, 'visualization', 'matched_crests_animation.html');
end

S = load(matPath);
required = {'crest_lon','crest_lat','crest_time','mooring_time','crest_dir'};
for k = 1:numel(required)
    assert(isfield(S, required{k}), 'Missing field: %s', required{k});
end

n = numel(S.crest_lon);
crestIdx = fieldOr(S, 'crest_idx', (1:n)');
mode = fieldOr(S, 'mode', nan(n,1));
speedDiff = fieldOr(S, 'speed_diff', nan(n,1));
dirDiff = fieldOr(S, 'dir_diff', nan(n,1));
kMooring = fieldOr(S, 'K_mooring', nan(n,1));
peakLon = fieldOr(S, 'peak_lon', nan(n,1));
peakLat = fieldOr(S, 'peak_lat', nan(n,1));
moorLat = 20.816666666666666;
moorLon = 115.76666666666667;
R = 6371000;

emptyCrest = struct('row', 0, 'id', 0, 'mode', 0, 'dir', 0, ...
    'dtHours', 0, 'alongKm', 0, 'crossKm', 0, 'speed', 0, ...
    'speedDiff', 0, 'dirDiff', 0, 'k', 0, 'signOK', false, ...
    'crestTime', '', 'mooringTime', '', 'peakLon', 0, 'peakLat', 0, ...
    'hitLon', 0, 'hitLat', 0, 'lon', [], 'lat', [], 'dLon', 0, 'dLat', 0);
crests = repmat(emptyCrest, n, 1);
speeds = nan(n,1);
dtHoursAll = nan(n,1);
pointCount = 0;

for i = 1:n
    lon = vectorAt(S.crest_lon, i);
    lat = vectorAt(S.crest_lat, i);
    good = isfinite(lon) & isfinite(lat);
    lon = lon(good); lat = lat(good);
    [lon, lat] = thinLine(lon, lat, 90);

    direction = double(S.crest_dir(i));
    dtHours = hours(S.mooring_time(i) - S.crest_time(i));
    [alongM, crossM, closestIdx] = signedAlongDistance(lat, lon, moorLat, moorLon, direction);
    speed = abs(alongM) / max(abs(dtHours) * 3600, eps);
    if ~isfinite(speed) || abs(dtHours) < eps
        speed = NaN;
    end

    meanLat = mean([lat(:); moorLat], 'omitnan');
    dNorth = alongM * cosd(direction);
    dEast = alongM * sind(direction);
    dLat = rad2deg(dNorth / R);
    dLon = rad2deg(dEast / (R * cosd(meanLat)));

    crests(i).row = i;
    crests(i).id = scalarAt(crestIdx, i);
    crests(i).mode = scalarAt(mode, i);
    crests(i).dir = direction;
    crests(i).dtHours = dtHours;
    crests(i).alongKm = alongM / 1000;
    crests(i).crossKm = crossM / 1000;
    crests(i).speed = speed;
    crests(i).speedDiff = scalarAt(speedDiff, i);
    crests(i).dirDiff = scalarAt(dirDiff, i);
    crests(i).k = scalarAt(kMooring, i);
    crests(i).signOK = sign(dtHours) == sign(alongM);
    crests(i).crestTime = dateText(S.crest_time(i));
    crests(i).mooringTime = dateText(S.mooring_time(i));
    crests(i).peakLon = scalarAt(peakLon, i);
    crests(i).peakLat = scalarAt(peakLat, i);
    if isfinite(closestIdx)
        crests(i).hitLon = lon(closestIdx) + dLon;
        crests(i).hitLat = lat(closestIdx) + dLat;
    else
        crests(i).hitLon = NaN;
        crests(i).hitLat = NaN;
    end
    crests(i).lon = round(lon(:)' * 1e6) / 1e6;
    crests(i).lat = round(lat(:)' * 1e6) / 1e6;
    crests(i).dLon = dLon;
    crests(i).dLat = dLat;
    speeds(i) = speed;
    dtHoursAll(i) = dtHours;
    pointCount = pointCount + numel(lon);
end

finiteSpeeds = speeds(isfinite(speeds));
payload = struct();
payload.meta = struct('source', strrep(matPath, '\', '/'), ...
    'generated', char(datetime('now'), 'yyyy-MM-dd HH:mm:ss'), ...
    'speedDefinition', 'abs(along-track distance) / abs(mooring_time - crest_time)', ...
    'animationDefinition', 'normalized per crest: 0 = sensed position, 1 = matched mooring-time position');
payload.map = struct('bounds', [110 122 18 23], ...
    'mooring', struct('lon', moorLon, 'lat', moorLat, 'radiusKm', 100));
payload.stats = struct('count', n, 'points', pointCount, ...
    'mode1', nnz(mode == 1), 'mode2', nnz(mode == 2), ...
    'medianSpeed', median(finiteSpeeds, 'omitnan'), ...
    'p90Speed', prctile(finiteSpeeds, 90), ...
    'medianAbsDtHours', median(abs(dtHoursAll), 'omitnan'), ...
    'signMismatch', nnz(~[crests.signOK]));
payload.crests = crests;

templatePath = fullfile(fileparts(mfilename('fullpath')), ...
    'matched_crests_animation_template.html');
assert(isfile(templatePath), 'Template not found: %s', templatePath);
template = fileread(templatePath);
json = jsonencode(payload);
assert(contains(template, '__CREST_DATA_JSON__'), 'Data placeholder missing.');
html = strrep(template, '__CREST_DATA_JSON__', json);

[outDir, ~, ~] = fileparts(outputPath);
if ~isempty(outDir) && ~isfolder(outDir), mkdir(outDir); end
fid = fopen(outputPath, 'w', 'n', 'UTF-8');
assert(fid >= 0, 'Cannot open output: %s', outputPath);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, html, 'char');
fprintf('Wrote %s (%d crests, %d retained points)\n', outputPath, n, pointCount);
end

function value = fieldOr(S, name, fallback)
if isfield(S, name), value = S.(name); else, value = fallback; end
end

function value = vectorAt(array, i)
if iscell(array), value = array{i}; else, value = array(i,:); end
value = double(value(:));
end

function value = scalarAt(array, i)
if iscell(array), value = array{i}; else, value = array(i); end
value = double(value);
end

function [lon, lat] = thinLine(lon, lat, maxPoints)
if numel(lon) > maxPoints
    keep = unique(round(linspace(1, numel(lon), maxPoints)));
    lon = lon(keep); lat = lat(keep);
end
end

function text = dateText(value)
try
    text = char(value, 'yyyy-MM-dd HH:mm:ss');
catch
    text = datestr(value, 'yyyy-mm-dd HH:MM:SS');
end
end

function [signedM, crossM, closestIdx] = signedAlongDistance(lat, lon, moorLat, moorLon, direction)
if isempty(lat) || ~isfinite(direction)
    signedM = NaN; crossM = NaN; closestIdx = NaN; return;
end
R = 6371000;
lat0 = mean([lat(:); moorLat], 'omitnan');
lon0 = mean([lon(:); moorLon], 'omitnan');
x = R * cosd(lat0) .* deg2rad(lon - lon0);
y = R .* deg2rad(lat - lat0);
xm = R * cosd(lat0) * deg2rad(moorLon - lon0);
ym = R * deg2rad(moorLat - lat0);
u = [sind(direction), cosd(direction)];
dx = xm - x; dy = ym - y;
along = dx .* u(1) + dy .* u(2);
cross = -dx .* u(2) + dy .* u(1);
[~, idx] = min(abs(cross));
signedM = along(idx); crossM = cross(idx);
closestIdx = idx;
end
