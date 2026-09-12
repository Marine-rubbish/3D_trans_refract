clc; close all;

%% Plot only the pairs flagged by validate_mat_physics.m.
project_root = '.';
report_mat = fullfile(project_root, 'diagnostics', 'physics_validation_report.mat');

% Debug controls.
target_rows = [];       % Source MAT row numbers, e.g. [123 381]; [] plots all failures.
target_source_mat = ""; % Optional exact MAT filename when the report contains several MAT files.
max_plots = inf;
pause_seconds = 1;
save_figures = false;

% Plot settings. Keep the radius consistent with the matching workflow.
mooring_lat = 20.816666666666666;
mooring_lon = 115.76666666666667;
mooring_radius_km = 100;
lon_bound = [110, 122];
lat_bound = [18, 23];

if ~isfile(report_mat)
    error('Validation report not found: %s\nRun tests/validate_mat_physics.m first.', report_mat);
end

R = load(report_mat, 'allRows');
if ~isfield(R, 'allRows')
    error('Variable allRows is missing from %s.', report_mat);
end

badRows = R.allRows(R.allRows.suspicious, :);
if strlength(target_source_mat) > 0
    badRows = badRows(string(badRows.source_mat) == target_source_mat, :);
end
if ~isempty(target_rows)
    badRows = badRows(ismember(badRows.row, target_rows), :);
end

if isempty(badRows)
    fprintf('No suspicious rows match the current filters.\n');
    return;
end

fprintf('Plotting %d suspicious pairs.\n', min(height(badRows), max_plots));
hFig = figure('Units', 'pixels', 'Position', [80 80 1600 760], 'Color', 'w');
plotted = 0;

source_names = unique(string(badRows.source_mat), 'stable');
for f = 1:numel(source_names)
    source_name = source_names(f);
    source_rows = badRows(string(badRows.source_mat) == source_name, :);
    mat_path = findSourceMat(project_root, source_name);
    P = loadMatchedStruct(mat_path);

    crest_lon = requireField(P, {'crest_lon'});
    crest_lat = requireField(P, {'crest_lat'});
    if isfield(P, 'peak_lon'), peak_lon = P.peak_lon; else, peak_lon = []; end
    if isfield(P, 'peak_lat'), peak_lat = P.peak_lat; else, peak_lat = []; end

    [~, mat_base] = fileparts(mat_path);
    save_dir = fullfile(project_root, 'diagnostics', 'physics_failure_plots', mat_base);
    if save_figures && ~exist(save_dir, 'dir')
        mkdir(save_dir);
    end

    for j = 1:height(source_rows)
        if plotted >= max_plots || ~isgraphics(hFig)
            break;
        end

        row = round(source_rows.row(j));
        if row < 1 || row > numel(crest_lon)
            warning('Skipping row %d: outside %s bounds.', row, source_name);
            continue;
        end

        lat = vectorFromCell(crest_lat, row);
        lon = vectorFromCell(crest_lon, row);
        cdir = source_rows.direction_deg(j);
        [hit_lon, hit_lat] = projectionPoint(lat, lon, mooring_lat, mooring_lon, cdir);

        clf(hFig);
        ax = axes(hFig); %#ok<LAXES>
        hold(ax, 'on'); box(ax, 'on'); grid(ax, 'on');
        axis(ax, 'equal');
        xlim(ax, lon_bound); ylim(ax, lat_bound);

        plot(ax, lon, lat, 'k-', 'LineWidth', 3, 'DisplayName', 'Remote-sensing crest');
        plotCircleLonLat(ax, mooring_lon, mooring_lat, mooring_radius_km, 'r--', 2.2);
        plot(ax, mooring_lon, mooring_lat, 'ro', 'MarkerSize', 12, ...
            'MarkerFaceColor', 'r', 'LineWidth', 1.5, 'DisplayName', 'Mooring');

        if ~isempty(peak_lon) && ~isempty(peak_lat)
            pk_lon = valueAt(peak_lon, row);
            pk_lat = valueAt(peak_lat, row);
            if isfinite(pk_lon) && isfinite(pk_lat)
                plot(ax, pk_lon, pk_lat, 'ko', 'MarkerSize', 9, ...
                    'MarkerFaceColor', 'k', 'DisplayName', 'Curvature peak');
            end
        end

        if isfinite(hit_lon) && isfinite(hit_lat)
            plot(ax, hit_lon, hit_lat, 'p', 'MarkerSize', 18, ...
                'MarkerEdgeColor', 'k', 'MarkerFaceColor', [0 0.75 0], ...
                'LineWidth', 1.2, 'DisplayName', 'Projection point');
            plot(ax, [hit_lon, mooring_lon], [hit_lat, mooring_lat], '--', ...
                'Color', [0.45 0.45 0.45], 'LineWidth', 1.5, ...
                'DisplayName', 'Crest-to-mooring vector');
            drawDirectionArrow(ax, hit_lon, hit_lat, cdir, 0.65);
        else
            drawDirectionArrow(ax, mooring_lon, mooring_lat, cdir, 0.65);
        end

        dt_h = source_rows.dt_hours(j);
        along_km = source_rows.signed_along_km(j);
        cross_km = source_rows.cross_track_km(j);
        reason = failureReason(dt_h, along_km);
        info = {
            sprintf('Source: %s, row: %d, crest index: %g', source_name, row, source_rows.crest_idx(j))
            sprintf('Sensing time (UTC): %s', datestr(source_rows.crest_time(j), 'yyyy-mm-dd HH:MM:SS'))
            sprintf('Mooring time (UTC): %s', datestr(source_rows.mooring_time(j), 'yyyy-mm-dd HH:MM:SS'))
            sprintf('Wave direction: %.2f deg, mode: %g', cdir, source_rows.mode(j))
            sprintf('dt: %.2f h, along: %.2f km, cross: %.2f km', dt_h, along_km, cross_km)
            sprintf('Implied speed: %.3f m/s', source_rows.implied_speed_mps(j))
            reason
        };
        text(ax, lon_bound(1) + 0.35, lat_bound(2) - 0.20, info, ...
            'Color', [0 0.15 0.85], 'FontName', 'Times New Roman', ...
            'FontWeight', 'bold', 'FontSize', 14, 'VerticalAlignment', 'top', ...
            'Interpreter', 'none');

        set(ax, 'FontName', 'Times New Roman', 'FontWeight', 'bold', ...
            'FontSize', 13, 'LineWidth', 1.2, 'TickDir', 'in');
        xlabel(ax, 'Longitude (^{\circ}E)', 'FontName', 'Times New Roman', ...
            'FontWeight', 'bold', 'FontSize', 16);
        ylabel(ax, 'Latitude (^{\circ}N)', 'FontName', 'Times New Roman', ...
            'FontWeight', 'bold', 'FontSize', 16);
        title(ax, 'Physically inconsistent crest/mooring match', ...
            'Color', [0.75 0 0], 'FontWeight', 'bold');

        drawnow;
        plotted = plotted + 1;

        if save_figures
            out_name = sprintf('%04d_crest_%g.png', row, source_rows.crest_idx(j));
            exportgraphics(hFig, fullfile(save_dir, out_name), 'Resolution', 220);
        end
        if pause_seconds > 0
            pause(pause_seconds);
        end
    end

    if plotted >= max_plots || ~isgraphics(hFig)
        break;
    end
end

fprintf('Displayed %d suspicious pairs.\n', plotted);

%% Local functions
function mat_path = findSourceMat(project_root, source_name)
    hits = dir(fullfile(project_root, '**', char(source_name)));
    hits = hits(~[hits.isdir]);
    if isempty(hits)
        error('Cannot find source MAT %s under %s.', source_name, project_root);
    end
    if numel(hits) > 1
        warning('Multiple copies of %s found; using %s.', source_name, hits(1).folder);
    end
    mat_path = fullfile(hits(1).folder, hits(1).name);
end

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

function [hit_lon, hit_lat] = projectionPoint(lat, lon, moor_lat, moor_lon, nav_dir_deg)
    good = isfinite(lat) & isfinite(lon);
    lat = lat(good); lon = lon(good);
    if isempty(lat) || ~isfinite(nav_dir_deg)
        hit_lon = NaN; hit_lat = NaN;
        return;
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
    cross = -dx .* u(2) + dy .* u(1);
    [~, idx] = min(abs(cross));
    hit_lon = lon(idx);
    hit_lat = lat(idx);
end

function reason = failureReason(dt_h, along_km)
    if dt_h > 0 && along_km < 0
        reason = 'INVALID: mooring time is later, but mooring lies behind the crest.';
    elseif dt_h < 0 && along_km > 0
        reason = 'INVALID: mooring time is earlier, but mooring lies ahead of the crest.';
    else
        reason = 'INVALID: propagation-distance and time signs disagree.';
    end
end

function plotCircleLonLat(ax, lon0, lat0, radius_km, style, lw)
    R = 6371;
    th = linspace(0, 2*pi, 361);
    d = radius_km / R;
    lat = asind(sind(lat0).*cos(d) + cosd(lat0).*sin(d).*cos(th));
    lon = lon0 + atan2d(sin(th).*sin(d).*cosd(lat0), ...
        cos(d) - sind(lat0).*sind(lat));
    plot(ax, lon, lat, style, 'LineWidth', lw, 'DisplayName', 'Matching radius');
end

function drawDirectionArrow(ax, lon0, lat0, nav_dir_deg, len_deg)
    dx = len_deg * sind(nav_dir_deg);
    dy = len_deg * cosd(nav_dir_deg);
    quiver(ax, lon0, lat0, dx, dy, 0, 'Color', [0.1 0.35 0.9], ...
        'LineWidth', 2.2, 'MaxHeadSize', 0.8, 'DisplayName', 'Propagation direction');
end
