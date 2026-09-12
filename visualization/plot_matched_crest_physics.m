clc; clear; close all;

%% Batch plot matched crest/mooring geometry for propagation sanity checks.
project_root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(project_root, 'utils')));

mat_patterns = { ...
    fullfile(project_root, 'data', 'matched_crests_params_*.mat'), ...
    fullfile(project_root, 'data', 'matched_results*.mat'), ...
    fullfile(project_root, 'src', 'matched_results*.mat') ...
};
mat_files = dir(fullfile(project_root, '__no_mat_file__'));
for pp = 1:numel(mat_patterns)
    mat_files = [mat_files; dir(mat_patterns{pp})]; %#ok<AGROW>
end

mooring_lat = 20.816666666666666;
mooring_lon = 115.76666666666667;
mooring_radius_km = 30;
lon_bound = [110, 122];
lat_bound = [18, 23];
plot_only_suspicious = false;
max_plots_per_mat = inf;

if isempty(mat_files)
    error('No mat files found. Edit mat_patterns at the top of this script.');
end

for f = 1:numel(mat_files)
    mat_path = fullfile(mat_files(f).folder, mat_files(f).name);
    P = loadMatchedStruct(mat_path);

    crest_lon = requireField(P, {'crest_lon'});
    crest_lat = requireField(P, {'crest_lat'});
    crest_time = toDatetime(requireField(P, {'crest_time'}));
    mooring_time = toDatetime(requireField(P, {'mooring_time'}));
    crest_dir = requireField(P, {'crest_dir', 'wave_dir', 'wave_direction', 'dir'});

    n = numel(crest_lon);
    if isfield(P, 'mode'), mode = P.mode; else, mode = nan(n,1); end
    if isfield(P, 'peak_lon'), peak_lon = P.peak_lon; else, peak_lon = nan(n,1); end
    if isfield(P, 'peak_lat'), peak_lat = P.peak_lat; else, peak_lat = nan(n,1); end

    [~, base_name] = fileparts(mat_files(f).name);
    save_dir = fullfile(project_root, 'diagnostics', 'physics_plots', base_name);
    if ~exist(save_dir, 'dir'), mkdir(save_dir); end

    hFig = figure('Units', 'pixels', 'Position', [80 80 1600 760], 'Visible', 'off', 'Color', 'w');
    plotted = 0;

    for i = 1:n
        lat = vectorFromCell(crest_lat, i);
        lon = vectorFromCell(crest_lon, i);
        cdir = crest_dir(i);
        dt_h = hours(mooring_time(i) - crest_time(i));
        [signed_m, cross_m, hit_lon, hit_lat] = signedAlongDistanceToCrest(lat, lon, mooring_lat, mooring_lon, cdir);
        sign_ok = sign(dt_h) == sign(signed_m);
        suspicious = abs(dt_h) >= 0.25 && abs(signed_m) >= 5000 && ~sign_ok;
        if plot_only_suspicious && ~suspicious
            continue;
        end
        if plotted >= max_plots_per_mat
            break;
        end
        plotted = plotted + 1;

        clf(hFig);
        ax = axes(hFig); %#ok<LAXES>
        hold(ax, 'on'); box(ax, 'on'); grid(ax, 'on');
        axis(ax, 'equal');
        xlim(ax, lon_bound); ylim(ax, lat_bound);

        plot(ax, lon, lat, 'k-', 'LineWidth', 3);
        plotCircleLonLat(ax, mooring_lon, mooring_lat, mooring_radius_km, 'r--', 2.2);
        plot(ax, mooring_lon, mooring_lat, 'ro', 'MarkerSize', 12, 'MarkerFaceColor', 'r', 'LineWidth', 1.5);

        pk_lon = valueAt(peak_lon, i);
        pk_lat = valueAt(peak_lat, i);
        if isfinite(pk_lon) && isfinite(pk_lat)
            plot(ax, pk_lon, pk_lat, 'ko', 'MarkerSize', 9, 'MarkerFaceColor', 'k');
        end
        if isfinite(hit_lon) && isfinite(hit_lat)
            plot(ax, hit_lon, hit_lat, 'p', 'MarkerSize', 18, 'MarkerEdgeColor', 'k', ...
                'MarkerFaceColor', [0 0.75 0], 'LineWidth', 1.2);
        end

        drawDirectionArrow(ax, mooring_lon, mooring_lat, cdir, 0.55);

        crest_len_km = crestLengthKm(lat, lon);
        status = 'OK';
        if suspicious, status = 'SUSPICIOUS'; end
        info = {
            sprintf('Sensing time (UTC): %s', datestr(crest_time(i), 'yyyy-mm-dd HH:MM:SS'))
            sprintf('Mooring time (UTC): %s', datestr(mooring_time(i), 'yyyy-mm-dd HH:MM:SS'))
            sprintf('Wave direction: %.4f deg', cdir)
            sprintf('Crest length: %.4f km', crest_len_km)
            sprintf('Mode: %g', valueAt(mode, i))
            sprintf('dt(moor-crest): %.2f h, along: %.2f km, cross: %.2f km, %s', dt_h, signed_m/1000, cross_m/1000, status)
        };
        text(ax, lon_bound(1)+0.45, lat_bound(2)-0.25, info, 'Color', 'b', ...
            'FontName', 'Times New Roman', 'FontWeight', 'bold', 'FontSize', 15, ...
            'VerticalAlignment', 'top');

        set(ax, 'FontName', 'Times New Roman', 'FontWeight', 'bold', 'FontSize', 13, ...
            'LineWidth', 1.2, 'TickDir', 'in');
        xlabel(ax, 'Longitude (^{\circ}E)', 'FontName', 'Times New Roman', 'FontWeight', 'bold', 'FontSize', 16);
        ylabel(ax, 'Latitude (^{\circ}N)', 'FontName', 'Times New Roman', 'FontWeight', 'bold', 'FontSize', 16);

        out_name = sprintf('%04d_%s_%s.png', i, status, datestr(crest_time(i), 'yyyymmdd_HHMMSS'));
        exportgraphics(hFig, fullfile(save_dir, out_name), 'Resolution', 220);
    end

    close(hFig);
    fprintf('Saved %d plots to %s\n', plotted, save_dir);
end

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

function [signed_m, cross_m, hit_lon, hit_lat] = signedAlongDistanceToCrest(lat, lon, moor_lat, moor_lon, nav_dir_deg)
    good = isfinite(lat) & isfinite(lon);
    lat = lat(good); lon = lon(good);
    if numel(lat) < 1 || ~isfinite(nav_dir_deg)
        signed_m = NaN; cross_m = NaN; hit_lon = NaN; hit_lat = NaN; return;
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
    hit_lon = lon(idx);
    hit_lat = lat(idx);
end

function L_km = crestLengthKm(lat, lon)
    good = isfinite(lat) & isfinite(lon);
    lat = lat(good); lon = lon(good);
    if numel(lat) < 2, L_km = NaN; return; end
    R = 6371;
    dlat = deg2rad(diff(lat));
    dlon = deg2rad(diff(lon));
    a = sin(dlat/2).^2 + cosd(lat(1:end-1)) .* cosd(lat(2:end)) .* sin(dlon/2).^2;
    L_km = sum(2 * R * asin(sqrt(a)), 'omitnan');
end

function plotCircleLonLat(ax, lon0, lat0, radius_km, style, lw)
    R = 6371;
    th = linspace(0, 2*pi, 361);
    d = radius_km / R;
    lat = asind(sind(lat0).*cos(d) + cosd(lat0).*sin(d).*cos(th));
    lon = lon0 + atan2d(sin(th).*sin(d).*cosd(lat0), cos(d)-sind(lat0).*sind(lat));
    plot(ax, lon, lat, style, 'LineWidth', lw);
end

function drawDirectionArrow(ax, lon0, lat0, nav_dir_deg, len_deg)
    dx = len_deg * sind(nav_dir_deg);
    dy = len_deg * cosd(nav_dir_deg);
    quiver(ax, lon0, lat0, dx, dy, 0, 'Color', [0.1 0.35 0.9], 'LineWidth', 2, 'MaxHeadSize', 0.8);
end


