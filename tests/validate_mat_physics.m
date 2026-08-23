clc; clear;

%% 验证匹配的波峰/锚系对是否满足传播时间物理规律。
% 此处使用的规则：
%   dt = mooring_time - crest_time。
%   signed_along_m > 0 表示锚系沿波峰传播方向位于波峰前方。
%   物理上一致的配对应满足 sign(dt) == sign(signed_along_m)。

project_root = '.';
addpath(genpath(fullfile(project_root, 'utils')));

mat_patterns = { ...
    fullfile(project_root, 'data', '*crest_params*.mat'), ...
    fullfile(project_root, 'data', '*matched_results*.mat'), ...
    fullfile(project_root, 'src', 'matched_results*.mat') ...
};
mat_files = dir(fullfile(project_root, '__no_mat_file__'));
for pp = 1:numel(mat_patterns)
    mat_files = [mat_files; dir(mat_patterns{pp})]; %#ok<AGROW>
end

mooring_lat = 20.816666666666666;
mooring_lon = 115.76666666666667;
min_abs_dt_hours = 0.25;      % ignore almost-simultaneous pairs
min_abs_along_km = 5;         % ignore nearly-on-crest pairs
speed_range_mps = [0.1, 5.0]; % only used as an extra warning flag

if isempty(mat_files)
    error('No mat files found. Edit mat_patterns at the top of this script.');
end

allRows = table();

for f = 1:numel(mat_files)
    mat_path = fullfile(mat_files(f).folder, mat_files(f).name);
    fprintf('Checking %s\n', mat_path);
    P = loadMatchedStruct(mat_path);

    crest_lon = requireField(P, {'crest_lon'});
    crest_lat = requireField(P, {'crest_lat'});
    crest_time = toDatetime(requireField(P, {'crest_time'}));
    mooring_time = toDatetime(requireField(P, {'mooring_time'}));
    crest_dir = requireField(P, {'crest_dir', 'wave_dir', 'wave_direction', 'dir'});

    n = numel(crest_lon);
    if numel(crest_time) ~= n || numel(mooring_time) ~= n || numel(crest_dir) ~= n
        error('Length mismatch in %s', mat_files(f).name);
    end

    if isfield(P, 'mode'), mode = P.mode; else, mode = nan(n,1); end
    if isfield(P, 'crest_idx'), crest_idx = P.crest_idx; elseif isfield(P, 'crest_idx_out'), crest_idx = P.crest_idx_out; else, crest_idx = (1:n)'; end
    if isfield(P, 'K_mooring'), K_mooring = P.K_mooring; else, K_mooring = nan(n,1); end

    source_mat = strings(n,1);
    row_id = nan(n,1);
    crest_idx_col = nan(n,1);
    mode_col = nan(n,1);
    direction_deg = nan(n,1);
    dt_hours = nan(n,1);
    signed_along_km = nan(n,1);
    cross_track_km = nan(n,1);
    implied_speed_mps = nan(n,1);
    sign_ok = false(n,1);
    speed_ok = false(n,1);
    suspicious = false(n,1);
    K_col = nan(n,1);

    for i = 1:n
        lat = vectorFromCell(crest_lat, i);
        lon = vectorFromCell(crest_lon, i);
        cdir = crest_dir(i);
        dt_h = hours(mooring_time(i) - crest_time(i));
        [signed_m, cross_m] = signedAlongDistanceToCrest(lat, lon, mooring_lat, mooring_lon, cdir);

        source_mat(i) = string(mat_files(f).name);
        row_id(i) = i;
        crest_idx_col(i) = valueAt(crest_idx, i);
        mode_col(i) = valueAt(mode, i);
        direction_deg(i) = cdir;
        dt_hours(i) = dt_h;
        signed_along_km(i) = signed_m / 1000;
        cross_track_km(i) = cross_m / 1000;
        if abs(dt_h) > 0
            implied_speed_mps(i) = abs(signed_m) / abs(dt_h * 3600);
        end
        sign_ok(i) = sign(dt_h) == sign(signed_m);
        speed_ok(i) = implied_speed_mps(i) >= speed_range_mps(1) && implied_speed_mps(i) <= speed_range_mps(2);
        suspicious(i) = abs(dt_h) >= min_abs_dt_hours && abs(signed_m) >= min_abs_along_km*1000 && ~sign_ok(i);
        K_col(i) = valueAt(K_mooring, i);
    end

    T = table(source_mat, row_id, crest_idx_col, mode_col, crest_time(:), mooring_time(:), ...
        direction_deg, dt_hours, signed_along_km, cross_track_km, implied_speed_mps, ...
        sign_ok, speed_ok, suspicious, K_col, ...
        'VariableNames', {'source_mat','row','crest_idx','mode','crest_time','mooring_time', ...
        'direction_deg','dt_hours','signed_along_km','cross_track_km','implied_speed_mps', ...
        'sign_ok','speed_ok','suspicious','K_mooring'});
    allRows = [allRows; T]; %#ok<AGROW>
end

out_dir = fullfile(project_root, 'diagnostics');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
out_csv = fullfile(out_dir, 'physics_validation_report.csv');
out_mat = fullfile(out_dir, 'physics_validation_report.mat');
writetable(allRows, out_csv);
save(out_mat, 'allRows');

fprintf('\nTotal pairs: %d\n', height(allRows));
fprintf('Suspicious sign mismatches: %d\n', nnz(allRows.suspicious));
fprintf('Speed outside %.2f-%.2f m/s: %d\n', speed_range_mps(1), speed_range_mps(2), nnz(~allRows.speed_ok));
fprintf('Saved: %s\n', out_csv);

badRows = allRows(allRows.suspicious, :);
disp(badRows(1:min(30, height(badRows)), :));

%% Local functions
function P = loadMatchedStruct(mat_path)
    S = load(mat_path);
    names = fieldnames(S);
    if numel(names) == 1 && isstruct(S.(names{1}))
        P = S.(names{1});
    else
        P = S;
    end
end

function v = requireField(P, names)
    for k = 1:numel(names)
        if isfield(P, names{k})
            v = P.(names{k});
            return;
        end
    end
    error('Missing required field. Tried: %s', strjoin(names, ', '));
end

function x = vectorFromCell(C, i)
    if iscell(C), x = C{i}; else, x = C(i,:); end
    x = x(:);
end

function v = valueAt(x, i)
    if iscell(x), v = x{i}; else, v = x(i); end
end

function t = toDatetime(x)
    if isa(x, 'datetime')
        t = x(:);
    elseif isnumeric(x)
        t = datetime(x(:), 'ConvertFrom', 'datenum');
    elseif iscell(x)
        t = datetime(string(x(:)));
    else
        t = datetime(x(:));
    end
end

function [signed_m, cross_m] = signedAlongDistanceToCrest(lat, lon, moor_lat, moor_lon, nav_dir_deg)
    good = isfinite(lat) & isfinite(lon);
    lat = lat(good); lon = lon(good);
    if numel(lat) < 1 || ~isfinite(nav_dir_deg)
        signed_m = NaN; cross_m = NaN; return;
    end

    R = 6371000;
    lat0 = mean([lat(:); moor_lat], 'omitnan');
    lon0 = mean([lon(:); moor_lon], 'omitnan');
    x = R * cosd(lat0) .* deg2rad(lon - lon0);
    y = R * deg2rad(lat - lat0);
    xm = R * cosd(lat0) .* deg2rad(moor_lon - lon0);
    ym = R * deg2rad(moor_lat - lat0);

    u = [sind(nav_dir_deg), cosd(nav_dir_deg)];
    dx = xm - x;
    dy = ym - y;
    along = dx .* u(1) + dy .* u(2);
    cross = -dx .* u(2) + dy .* u(1);
    [~, idx] = min(abs(cross));
    signed_m = along(idx);
    cross_m = cross(idx);
end



