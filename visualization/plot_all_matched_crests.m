function plot_all_matched_crests()
%PLOT_ALL_MATCHED_CRESTS 绘制所有匹配的波峰线（总览图或逐张详细图）
%   用法：直接运行 plot_all_matched_crests 即可，在文件顶部修改参数
%
%   示例：
%       plot_all_matched_crests    % 使用默认参数
%
clc; close all;

%% ==================== 用户可配置参数 ====================
project_root = fileparts(fileparts(mfilename('fullpath')));
if isempty(project_root) || ~isfolder(project_root), project_root = '.'; end

% 匹配结果文件（可替换为其他 .mat）
target_mat = fullfile(project_root, 'TMP', 'matched_results_with_capsules.mat');

% 指定要画的 global_crest_idx，用 [] 表示画全部
% 例如：target_crest_idx = [196, 300, 1223];
target_crest_idx = [];

% 绘图模式：
%   'overview' = 所有波峰线画在同一张总图上
%   'detail'   = 每条波峰线单独一张详细图（回车翻下一张，q 退出）
plot_mode = 'detail';

% 详细图模式下的最大绘图数量（避免一次性开几百张图）
max_detail_plots = inf;

% 详细图模式的翻页控制：
%   true  = 按回车翻下一张，输入 q 回车退出（推荐手动查看）
%   false = 自动每隔 pause_seconds 秒翻下一张
manual_page = true;
pause_seconds = 1.0;   % 仅当 manual_page = false 时生效

% 是否保存图片
save_figures = false;
save_dir = fullfile(project_root, 'diagnostics', 'all_matched_crest_plots');

%% 绘图范围
mooring_lat = 20.816666666666666;
mooring_lon = 115.76666666666667;
mooring_radius_km = 100;
lon_bound = [110, 122];
lat_bound = [18, 23];

%% ==================== 加载数据 ====================
if ~isfile(target_mat)
    error('匹配结果文件不存在: %s', target_mat);
end
fprintf('加载匹配结果: %s\n', target_mat);
S = load(target_mat);

crest_lon = requireField(S, {'crest_lon', 'out_crest_lon'});
crest_lat = requireField(S, {'crest_lat', 'out_crest_lat'});
peak_lon  = getFieldOr(S, {'peak_lon', 'out_peak_lon'}, []);
peak_lat  = getFieldOr(S, {'peak_lat', 'out_peak_lat'}, []);
mode_arr  = getFieldOr(S, {'mode', 'out_mode'}, []);
crest_time = getFieldOr(S, {'crest_time', 'out_crest_time'}, []);
mooring_time = getFieldOr(S, {'mooring_time', 'out_mooring_time'}, []);
crest_idx  = getFieldOr(S, {'crest_idx', 'out_crest_idx'}, []);
crest_dir  = getFieldOr(S, {'crest_dir', 'out_crest_dir', 'direction_deg'}, []);
dir_diff   = getFieldOr(S, {'dir_diff', 'out_dir_diff'}, []);
speed_diff = getFieldOr(S, {'speed_diff', 'out_speed_diff'}, []);
K_mooring  = getFieldOr(S, {'K_mooring', 'out_K_mooring'}, []);

n_total = length(crest_lon);

%% ==================== 筛选要画的行 ====================
if ~isempty(target_crest_idx) && ~isempty(crest_idx)
    [~, plot_rows, ~] = intersect(double(crest_idx(:)), target_crest_idx(:), 'stable');
    if isempty(plot_rows)
        fprintf('指定的 crest_idx={%s} 在文件中未找到匹配项。\n', ...
            num2str(target_crest_idx));
        return;
    end
    fprintf('筛选出 %d / %d 条匹配 (crest_idx=%s)\n', ...
        length(plot_rows), n_total, mat2str(target_crest_idx));
else
    plot_rows = (1:n_total)';
    fprintf('绘制全部 %d 条匹配\n', n_total);
end

%% ==================== 开始绘图 ====================
if save_figures && ~exist(save_dir, 'dir')
    mkdir(save_dir);
end

switch lower(plot_mode)
    case 'overview'
        plotOverview();
    case 'detail'
        plotDetailOneByOne();
    otherwise
        error('未知 plot_mode: %s，可选 ''overview'' 或 ''detail''', plot_mode);
end

fprintf('全部绘图完成。\n');

%%======================================================================
%% 嵌套函数：总览图 —— 所有波峰线画在同一张图
%%======================================================================
    function plotOverview()
        hFig = figure('Units', 'pixels', 'Position', [80 80 1600 880], 'Color', 'w');
        ax = axes(hFig); hold(ax, 'on'); box(ax, 'on'); grid(ax, 'on');
        axis(ax, 'equal');
        xlim(ax, lon_bound); ylim(ax, lat_bound);

        % 系泊点和匹配半径
        plotCircleLonLat(ax, mooring_lon, mooring_lat, mooring_radius_km, 'r--', 2.2);
        h_moor = plot(ax, mooring_lon, mooring_lat, 'rp', 'MarkerSize', 14, ...
            'MarkerFaceColor', 'r', 'LineWidth', 1.5, 'DisplayName', 'Mooring');

        h_m1 = gobjects(0); h_m2 = gobjects(0); h_peak = gobjects(0);
        drawn_modes = [];
        peak_drawn = false;

        for jj = 1:length(plot_rows)
            row = plot_rows(jj);
            lat = vectorFromCell(crest_lat, row);
            lon = vectorFromCell(crest_lon, row);
            valid = isfinite(lat) & isfinite(lon);
            lat = lat(valid); lon = lon(valid);
            if isempty(lat), continue; end

            cur_mode = NaN;
            if ~isempty(mode_arr) && row <= length(mode_arr)
                cur_mode = double(mode_arr(row));
            end

            if cur_mode == 1
                c_color = [0, 0.45, 0.9];
                c_style = '-';
                if ~ismember(1, drawn_modes)
                    h_m1 = plot(nan, nan, '-', 'Color', c_color, 'LineWidth', 2.5);
                    drawn_modes(end+1) = 1;
                end
            elseif cur_mode == 2
                c_color = [0.75, 0.1, 0.75];
                c_style = '-';
                if ~ismember(2, drawn_modes)
                    h_m2 = plot(nan, nan, '-', 'Color', c_color, 'LineWidth', 2.5);
                    drawn_modes(end+1) = 2;
                end
            else
                c_color = [0.35 0.35 0.35];
                c_style = '-';
            end

            plot(ax, lon, lat, c_style, 'Color', c_color, 'LineWidth', 1.2);

            % 画曲率峰点
            if ~isempty(peak_lon) && ~isempty(peak_lat) ...
                    && row <= length(peak_lon) && row <= length(peak_lat)
                pk_lon = peak_lon(row);
                pk_lat = peak_lat(row);
                if isfinite(pk_lon) && isfinite(pk_lat)
                    plot(ax, pk_lon, pk_lat, 'o', 'Color', c_color, ...
                        'MarkerSize', 6, 'MarkerFaceColor', c_color);
                    if ~peak_drawn
                        h_peak = plot(nan, nan, 'ko', 'MarkerSize', 7, 'MarkerFaceColor', 'k');
                        peak_drawn = true;
                    end
                end
            end

            % 画方向箭头（从波峰线中点或 peak）
            if ~isempty(crest_dir) && row <= length(crest_dir) && isfinite(crest_dir(row))
                if ~isempty(peak_lon) && isfinite(peak_lon(row))
                    arrow_lon = peak_lon(row);
                    arrow_lat = peak_lat(row);
                else
                    mid = max(1, floor(length(lon)/2));
                    arrow_lon = lon(mid);
                    arrow_lat = lat(mid);
                end
                drawDirectionArrow(ax, arrow_lon, arrow_lat, crest_dir(row), 0.35);
            end
        end

        % 图例
        h_leg = [h_moor];
        leg_labels = {'Mooring'};
        if ~isempty(h_m1), h_leg(end+1)=h_m1; leg_labels{end+1}='Mode 1 Crest'; end
        if ~isempty(h_m2), h_leg(end+1)=h_m2; leg_labels{end+1}='Mode 2 Crest'; end
        if ~isempty(h_peak), h_leg(end+1)=h_peak; leg_labels{end+1}='Curvature Peak'; end
        legend(ax, h_leg, leg_labels, 'Location', 'southeast', ...
            'FontName', 'Times New Roman', 'FontSize', 13, 'Box', 'on');

        % 统计信息面板
        n_m1 = 0; n_m2 = 0; n_unknown = 0;
        for jj = 1:length(plot_rows)
            row = plot_rows(jj);
            if ~isempty(mode_arr) && row <= length(mode_arr)
                m = double(mode_arr(row));
                if m==1, n_m1=n_m1+1; elseif m==2, n_m2=n_m2+1; else, n_unknown=n_unknown+1; end
            else
                n_unknown = n_unknown + 1;
            end
        end
        info_panel = {
            sprintf('Matched crests: %d (Mode1: %d, Mode2: %d, Other: %d)', ...
                length(plot_rows), n_m1, n_m2, n_unknown)
            sprintf('Source: %s', stripPath(target_mat))
            sprintf('Mooring: (%.4fN, %.4fE), radius: %d km', ...
                mooring_lat, mooring_lon, mooring_radius_km)
        };
        text(ax, lon_bound(1) + 0.3, lat_bound(2) - 0.18, info_panel, ...
            'Color', [0.05 0.05 0.55], 'FontName', 'Times New Roman', ...
            'FontWeight', 'bold', 'FontSize', 14, 'VerticalAlignment', 'top', ...
            'Interpreter', 'none', 'BackgroundColor', [0.98 0.98 1]);

        set(ax, 'FontName', 'Times New Roman', 'FontWeight', 'bold', ...
            'FontSize', 13, 'LineWidth', 1.2, 'TickDir', 'in');
        xlabel(ax, 'Longitude (^{\circ}E)', 'FontName', 'Times New Roman', ...
            'FontWeight', 'bold', 'FontSize', 16);
        ylabel(ax, 'Latitude (^{\circ}N)', 'FontName', 'Times New Roman', ...
            'FontWeight', 'bold', 'FontSize', 16);
        title(ax, sprintf('Overview of All Matched Crests (N = %d)', length(plot_rows)), ...
            'Color', [0 0.3 0.7], 'FontWeight', 'bold', 'FontSize', 17);

        drawnow;
        if save_figures
            out_name = sprintf('overview_%s.png', strrep(stripPath(target_mat),'.mat',''));
            exportgraphics(hFig, fullfile(save_dir, out_name), 'Resolution', 220);
            fprintf('总览图已保存: %s\n', fullfile(save_dir, out_name));
        end
    end

%%======================================================================
%% 嵌套函数：逐张详细图
%%======================================================================
    function plotDetailOneByOne()
        hFig = figure('Units', 'pixels', 'Position', [80 80 1600 760], 'Color', 'w');
        plotted = 0;

        for jj = 1:length(plot_rows)
            if plotted >= max_detail_plots || ~isgraphics(hFig), break; end
            row = plot_rows(jj);

            if crest_idx(jj) ~= 752
                continue;
            end

            lat = vectorFromCell(crest_lat, row);
            lon = vectorFromCell(crest_lon, row);
            valid = isfinite(lat) & isfinite(lon);
            lat = lat(valid); lon = lon(valid);
            if isempty(lat), continue; end

            cur_mode = NaN;
            if ~isempty(mode_arr) && row <= length(mode_arr)
                cur_mode = double(mode_arr(row));
            end

            cdir = NaN;
            if ~isempty(crest_dir) && row <= length(crest_dir)
                cdir = double(crest_dir(row));
            end

            [hit_lon, hit_lat] = projectionPoint(lat, lon, mooring_lat, mooring_lon, cdir);

            clf(hFig);
            ax = axes(hFig); hold(ax, 'on'); box(ax, 'on'); grid(ax, 'on');
            axis(ax, 'equal');
            xlim(ax, lon_bound); ylim(ax, lat_bound);

            if cur_mode == 1
                c_color = [0, 0.45, 0.9];
                mode_str = 'Mode-1';
            elseif cur_mode == 2
                c_color = [0.75, 0.1, 0.75];
                mode_str = 'Mode-2';
            else
                c_color = [0.2 0.2 0.2];
                mode_str = 'Unknown';
            end

            plot(ax, lon, lat, '-', 'Color', c_color, 'LineWidth', 3, ...
                'DisplayName', ['Remote-sensing crest (' mode_str ')']);
            plotCircleLonLat(ax, mooring_lon, mooring_lat, mooring_radius_km, 'r--', 2.2);
            plot(ax, mooring_lon, mooring_lat, 'rp', 'MarkerSize', 14, ...
                'MarkerFaceColor', 'r', 'LineWidth', 1.5, 'DisplayName', 'Mooring');

            if ~isempty(peak_lon) && ~isempty(peak_lat) ...
                    && row <= length(peak_lon) && row <= length(peak_lat)
                pk_lon = peak_lon(row);
                pk_lat = peak_lat(row);
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
                if isfinite(cdir)
                    drawDirectionArrow(ax, hit_lon, hit_lat, cdir, 0.65);
                end
            elseif isfinite(cdir)
                drawDirectionArrow(ax, mooring_lon, mooring_lat, cdir, 0.65);
            end

            info = {
                sprintf('Source: %s', stripPath(target_mat))
                sprintf('Row: %d / %d  |  crest_idx: %g', jj, length(plot_rows), ...
                    safeIdx(crest_idx, row))
                sprintf('Crest sensing time: %s', safeTimeStr(crest_time, row))
                sprintf('Mooring time:        %s', safeTimeStr(mooring_time, row))
                sprintf('Mode: %s  |  Direction: %.2f deg', mode_str, cdir)
                sprintf('Direction diff: %s deg  |  Speed diff: %s', ...
                    safeNumStr(dir_diff, row, '%.2f'), safeNumStr(speed_diff, row, '%.4f'))
                sprintf('K_mooring: %s', safeNumStr(K_mooring, row, '%.4f'))
            };

            text(ax, lon_bound(1) + 0.35, lat_bound(2) - 0.22, info, ...
                'Color', [0 0.2 0.7], 'FontName', 'Times New Roman', ...
                'FontWeight', 'bold', 'FontSize', 14, 'VerticalAlignment', 'top', ...
                'Interpreter', 'none');

            set(ax, 'FontName', 'Times New Roman', 'FontWeight', 'bold', ...
                'FontSize', 13, 'LineWidth', 1.2, 'TickDir', 'in');
            xlabel(ax, 'Longitude (^{\circ}E)', 'FontName', 'Times New Roman', ...
                'FontWeight', 'bold', 'FontSize', 16);
            ylabel(ax, 'Latitude (^{\circ}N)', 'FontName', 'Times New Roman', ...
                'FontWeight', 'bold', 'FontSize', 16);
            title(ax, sprintf('Matched Crest #%d  (crest_idx=%g, %s)', ...
                jj, safeIdx(crest_idx, row), mode_str), ...
                'Color', [0 0.35 0.1], 'FontWeight', 'bold', 'FontSize', 16);

            legend(ax, 'Location', 'southeast', 'FontName', 'Times New Roman', 'FontSize', 12);
            drawnow;
            plotted = plotted + 1;

            if save_figures
                out_name = sprintf('%04d_crest_%g.png', jj, safeIdx(crest_idx, row));
                exportgraphics(hFig, fullfile(save_dir, out_name), 'Resolution', 220);
            end

            % --- 翻页控制 ---
            is_last = (jj == length(plot_rows)) || (plotted >= max_detail_plots);
            if ~is_last
                if manual_page
                    if jj < length(plot_rows)
                        next_row = plot_rows(jj+1);
                        next_hint = sprintf('(下一张: crest_idx=%g)', safeIdx(crest_idx, next_row));
                    else
                        next_hint = '(已是最后一张)';
                    end
                    resp = input(sprintf('  第 %d/%d 张  |  回车 = 下一张 %s  |  q + 回车 = 退出: ', ...
                        jj, length(plot_rows), next_hint), 's');
                    if strcmpi(resp, 'q')
                        fprintf('用户手动退出。\n');
                        break;
                    end
                elseif pause_seconds > 0
                    pause(pause_seconds);
                end
            end
        end

        fprintf('显示了 %d 张详细图。\n', plotted);
    end

%%======================================================================
%% 嵌套辅助函数（纯工具，不依赖外部变量的也可以放外面，这里统一嵌套）
%%======================================================================
end  % 主函数结束

%%======================================================================
%% 以下为局部子函数（local functions），不需要访问外层变量
%%======================================================================

function v = requireField(S, names)
    for k = 1:numel(names)
        if isfield(S, names{k})
            v = S.(names{k});
            return;
        end
    end
    error('缺少必需字段。尝试过: %s', strjoin(names, ', '));
end

function v = getFieldOr(S, names, default)
    for k = 1:numel(names)
        if isfield(S, names{k})
            v = S.(names{k});
            return;
        end
    end
    v = default;
end

function x = vectorFromCell(C, i)
    if iscell(C), x = C{i}; else, x = C(i,:); end
    x = x(:);
end

function val = safeIdx(arr, i)
    if isempty(arr) || i > length(arr)
        val = NaN;
        return;
    end
    t = arr(i);
    if isnumeric(t)
        if ~isfinite(t), val = NaN; else, val = double(t); end
    elseif isdatetime(t)
        val = datenum(t);
    else
        try
            val = double(t);
            if ~isfinite(val), val = NaN; end
        catch
            val = NaN;
        end
    end
end

function s = safeTimeStr(arr, i)
    if isempty(arr) || i > length(arr)
        s = 'N/A';
        return;
    end
    t = arr(i);
    try
        if isdatetime(t)
            if isNaT(t)
                s = 'N/A';
            else
                s = datestr(t, 'yyyy-mm-dd HH:MM:SS');
            end
        elseif isduration(t)
            s = char(t);
        elseif isnumeric(t)
            if ~isfinite(t)
                s = 'N/A';
            else
                s = datestr(t, 'yyyy-mm-dd HH:MM:SS');
            end
        else
            s = datestr(t, 'yyyy-mm-dd HH:MM:SS');
        end
    catch
        try
            s = char(t);
        catch
            s = 'N/A';
        end
    end
end

function s = safeNumStr(arr, i, fmt)
    if isempty(arr) || i > length(arr)
        s = 'N/A';
        return;
    end
    t = arr(i);
    try
        if isnumeric(t)
            if ~isfinite(t), s = 'N/A'; else, s = sprintf(fmt, double(t)); end
        elseif isdatetime(t) || isduration(t)
            s = char(t);
        else
            v = double(t);
            if ~isfinite(v), s = 'N/A'; else, s = sprintf(fmt, v); end
        end
    catch
        s = 'N/A';
    end
end

function name = stripPath(path_str)
    [~, name, ext] = fileparts(char(path_str));
    name = [name ext];
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