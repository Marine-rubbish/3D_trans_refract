% test_analyze_crest_shape.m
% 逐个画出波峰线经过 analyze_crest_shape 处理后的结果
% 用法：运行后按回车看下一个波峰线，输入 q 退出

clc; clear; close all;

project_root = '.';
addpath(genpath(fullfile(project_root, 'utils')));

%% ========== 参数设置 ==========
shp_dir = 'F:\research\MODIS\shp_files';
resample_res = 250;          % 和 simu_all_crests_trans_dir_pro.m 保持一致
max_crests_to_plot = 200;    % 最多画多少条（避免太多）
start_from_crest = 1783;        % 从第几条波峰开始看
plot_pause_mode = true;      % true=按回车逐条看; false=一次画完

%% ========== 读取所有 shp 文件 ==========
shp_filelist = dir(fullfile(shp_dir, '*.shp'));
if isempty(shp_filelist)
    error('没有找到 shp 文件，请检查 shp_dir 路径: %s', shp_dir);
end

fprintf('共找到 %d 个 shp 文件\n', length(shp_filelist));

% 把所有波峰线收集起来
all_lat = {};
all_lon = {};
all_src = {};

for k = 1:length(shp_filelist)
    shp_name = fullfile(shp_dir, shp_filelist(k).name);
    crestLines = shaperead(shp_name);
    for i = 1:length(crestLines)
        all_lat{end+1} = crestLines(i).Y;
        all_lon{end+1} = crestLines(i).X;
        all_src{end+1} = sprintf('%s #%d', shp_filelist(k).name, i);
    end
end

num_crests = length(all_lat);
fprintf('总共收集到 %d 条波峰线\n', num_crests);

%% ========== 逐条画图 ==========
fig = figure('Position', [100 100 1100 750]);

plot_range = start_from_crest : min(start_from_crest + max_crests_to_plot - 1, num_crests);
for n = plot_range
    if n < 162
        continue;
    end
    rawLat = all_lat{n};
    rawLon = all_lon{n};
    
    % 调用要测试的函数
    [resLat, resLon, peakLat, peakLon, s_peak, L_total] = ...
        analyze_crest_shape_orig(rawLat, rawLon, resample_res);
    
    % 计算曲率：与 analyze_crest_shape_orig 内部算法 100% 一致
    % 并验证 Peak 位置是否自洽
    kappa = []; kappa_s = []; obj = [];
    s_plot = []; w_weight = []; drop_mask = [];
    peak_self_idx = NaN; peak_match_flag = false;
    
    if ~isnan(peakLat)
        % ===== 以下完全复刻 analyze_crest_shape_orig 第 2~10 步 =====
        R_earth = 6371000;
        minNs_target = 60;
        smooth_km = 20;
        kappaSmooth_km = 10;
        dropEdgePct = 0.05;
        
        % 3. 数据预处理
        lat = rawLat(:); lon = rawLon(:);
        good = isfinite(lat) & isfinite(lon);
        lat = lat(good); lon = lon(good);
        
        % 4. 投影到局部平面坐标（米）
        lon0 = mean(lon);
        lat0 = mean(lat);
        x = R_earth * cosd(lat0) .* deg2rad(lon - lon0);
        y = R_earth * deg2rad(lat - lat0);
        
        % 去掉重复点
        ds_xy = hypot(diff(x), diff(y));
        keep  = [true; ds_xy > 1e-3];
        x = x(keep); y = y(keep);
        
        % 5. 算原始弧长
        ds0 = hypot(diff(x), diff(y));
        s0  = [0; cumsum(ds0)];
        L_self = s0(end);
        
        % 6. 自适应重采样
        ds = resample_res;
        Ns_est = floor(L_self / ds) + 1;
        if Ns_est < minNs_target
            ds = L_self / (minNs_target - 1);
        end
        s_new = (0:ds:L_self)';
        Ns = numel(s_new);
        
        % pchip 插值
        xr   = interp1(s0, x,   s_new, 'pchip');
        yr   = interp1(s0, y,   s_new, 'pchip');
        
        % 7. 几何大尺度平滑
        winG = max(5, round((smooth_km * 1000) / ds));
        if mod(winG, 2) == 0, winG = winG + 1; end
        winG = min(winG, Ns);
        xs = smoothdata(xr, 'movmean', winG);
        ys = smoothdata(yr, 'movmean', winG);
        
        % 8. 三点法算曲率
        kappa = nan(Ns, 1);
        x1 = xs(1:end-2); y1 = ys(1:end-2);
        x2 = xs(2:end-1); y2 = ys(2:end-1);
        x3 = xs(3:end);   y3 = ys(3:end);
        a = hypot(x2-x1, y2-y1);
        b = hypot(x3-x2, y3-y2);
        c = hypot(x3-x1, y3-y1);
        area2 = abs((x2-x1).*(y3-y1) - (y2-y1).*(x3-x1));
        denom = a.*b.*c;
        denom(denom < 1e-9) = NaN;
        k_mid = 2 * area2 ./ denom;
        kappa(2:end-1) = k_mid;
        if isnan(kappa(1)), kappa(1) = kappa(2); end
        if isnan(kappa(end)), kappa(end) = kappa(end-1); end
        
        % 9. 曲率再平滑（10km）
        winK = max(5, round((kappaSmooth_km * 1000) / ds));
        if mod(winK, 2) == 0, winK = winK + 1; end
        winK = min(winK, Ns);
        kappa_s = smoothdata(kappa, 'movmean', winK);
        
        % 10. 加权寻峰 + 硬剔除边缘 5%
        dropN = max(2, round(dropEdgePct * Ns));
        w_weight = sin(pi * (s_new / L_self)).^2;
        obj = kappa_s .* w_weight;
        drop_mask = false(Ns, 1);
        drop_mask(1:dropN) = true;
        drop_mask(end-dropN+1:end) = true;
        obj(drop_mask) = NaN;
        
        % 自己找 Peak 索引
        [~, peak_self_idx] = max(obj, [], 'omitnan');
        if isempty(peak_self_idx)
            peak_self_idx = round(Ns/2);
        end
        s_self_peak = s_new(peak_self_idx);
        
        % ===== 验证：自算 Peak vs orig 返回的 Peak 是否一致 =====
        % 找 orig 返回的 s_peak 对应到 s_new 的索引
        [~, peak_orig_idx] = min(abs(s_new - s_peak));
        peak_match_flag = (peak_self_idx == peak_orig_idx);
        peak_diff_idx = peak_self_idx - peak_orig_idx;
        peak_diff_m = s_self_peak - s_peak;
        if peak_match_flag
            fprintf('  ✓ Peak 自洽：索引 %d (s=%.0fm)\n', peak_self_idx, s_peak);
        else
            fprintf('  ⚠ Peak 错位：orig=%d(%.0fm) vs self=%d(%.0fm)，差 %d 点 / %.0fm\n', ...
                peak_orig_idx, s_peak, peak_self_idx, s_self_peak, peak_diff_idx, peak_diff_m);
        end
        s_plot = s_new / 1000;
    end
    
    % 画图：上半部分 地图视图，下半部分 曲率沿弧长分布
    clf(fig);
    
    % ----- 上图：地图 -----
    subplot(2,1,1);
    hold on; axis equal; grid on;
    
    % 1. 原始波峰线
    plot(rawLon, rawLat, 'k-', 'LineWidth', 2, 'DisplayName', '原始波峰线');
    
    % 2. 重采样点
    plot(resLon, resLat, 'b.', 'MarkerSize', 4, 'DisplayName', '重采样点');
    
    % 3. Peak 点
    if isfinite(peakLat)
        plot(peakLon, peakLat, 'ro', 'MarkerSize', 12, 'MarkerFaceColor', 'r', ...
            'DisplayName', sprintf('Peak (s_peak=%.0fm, L=%.0fm)', s_peak, L_total));
    else
        text(0.5, 0.5, 'Peak=NaN', 'Units', 'normalized', 'Color', 'r', ...
            'HorizontalAlignment', 'center');
    end
    
    legend('Location', 'best');
    xlabel('经度 (°E)');
    ylabel('纬度 (°N)');
    title(sprintf('波峰 #%d / %d  ——  %s', n, num_crests, all_src{n}), ...
        'FontWeight', 'bold');
    
    % ----- 下图：曲率分布（与 analyze_crest_shape_orig 内部一致）-----
    subplot(2,1,2);
    if ~isempty(kappa) && length(kappa) > 2
        hold on;
        
        % [0] 灰色底：标记首尾 5% 被硬剔除（dropEdge）的区域
        s_end = s_plot(end);
        drop_km = s_end * 0.05;
        xpatch_s = [0, drop_km, drop_km, 0];
        y_lim_ref = ylim;
        if isempty(y_lim_ref) || ~isfinite(y_lim_ref(1)), y_lim_ref = [0, 1]; end
        patch(xpatch_s, [y_lim_ref(1), y_lim_ref(1), y_lim_ref(2), y_lim_ref(2)], ...
            [0.92 0.92 0.92], 'EdgeColor', 'none', 'FaceAlpha', 0.8, ...
            'DisplayName', '首尾 5% 硬剔除 (dropEdge)');
        patch([s_end-drop_km, s_end, s_end, s_end-drop_km], ...
            [y_lim_ref(1), y_lim_ref(1), y_lim_ref(2), y_lim_ref(2)], ...
            [0.92 0.92 0.92], 'EdgeColor', 'none', 'FaceAlpha', 0.8);
        
        % [1] 左轴：原始曲率 + 10km 平滑后曲率
        yyaxis left;
        h1 = plot(s_plot, kappa, 'b-', 'LineWidth', 0.8, 'Color', [0.3 0.6 1.0], ...
            'DisplayName', '原始曲率 \kappa');
        h2 = plot(s_plot, kappa_s, 'b-', 'LineWidth', 2.2, ...
            'DisplayName', '曲率再平滑 \kappa_s (10km)');
        ylabel('曲率 (1/m)');
        
        % [2] 右轴：加权曲率 obj = \kappa_s .* w_weight（剔除首尾后）
        yyaxis right;
        h3 = plot(s_plot, obj, 'r-', 'LineWidth', 2.0, ...
            'DisplayName', '加权曲率 obj = \kappa_s·w');
        ylabel('加权曲率 (已剔除首尾 5%)');
        
        % [3] Peak 位置线
        if isfinite(s_peak)
            if peak_match_flag
                line_color = [0.85 0.1 0.1];
                line_label = sprintf('Peak ✓ 自洽 (s=%.1fkm)', s_peak/1000);
            else
                line_color = [0.85 0.1 0.1];
                line_label = sprintf('Peak (orig, s=%.1fkm)', s_peak/1000);
                % 如果错位，额外画绿色线标记自算 Peak
                s_plot_arr = s_plot(:);
                if peak_self_idx > 0 && peak_self_idx <= length(s_plot_arr)
                    s_self_km = s_plot_arr(peak_self_idx);
                    xline(s_self_km, 'g--', 'LineWidth', 1.8, ...
                        'Label', sprintf('Self Peak (s=%.1fkm)', s_self_km));
                end
            end
            xline(s_peak/1000, '--', 'Color', line_color, 'LineWidth', 2.0, 'Label', line_label);
        end
        
        xlabel('弧长 s (km)');
        legend([h1, h2, h3], 'Location', 'best');
        grid on;
    end
    
    drawnow;
    
    % 暂停等待用户操作
    if plot_pause_mode
        resp = input(sprintf('  [%d/%d] 按回车继续，输入 q 退出：', n, num_crests), 's');
        if strcmpi(resp, 'q')
            fprintf('已终止。\n');
            break;
        end
    end
end

fprintf('画图完成。\n');