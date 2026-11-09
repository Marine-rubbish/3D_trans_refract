% simu_all_crests_trans_dir_mode_update.m
clc; clear; close all;

addpath(genpath('../utils')); % 确保包含 reachPointByTranslation 等函数

%% ==================== 参数设置 ====================
angle_tol = 90;     % 角度容差（度）
resample_res = 250; % 波峰线重采样分辨率 (m)
% lambda_dir = 0.02;  % 方向差权重系数，越大表示方向差在匹配中越重要
lambda_dir = 0;     % 默认不使用
output_mat_name = 'matched_results_with_capsules.mat';

if exist('intlinprog', 'file') ~= 2
    error(['全局有序分配需要 Optimization Toolbox 的 intlinprog。', ...
        '请先安装该工具箱，再运行生产批处理。']);
end

% Debug entry points. Keep disabled for the normal batch run.
DEBUG.plotKPoint = false;
DEBUG.targetCrestIdx = []; % e.g. 1388; [] means allow every crest when plotting is enabled

% 系泊点坐标
mooring_lat = 20.816666666666666;
mooring_lon = 115.76666666666667;

% 东沙坐标
dongsha_lat = 20.7;
dongsha_lon = 116.8;

% 波包几何参数与人工核查入口保持一致。分组只读取同景波锋几何，
% 不使用系泊事件，因此不会把待匹配结果反向泄漏到候选波包。
packet_config = struct( ...
    'mooringLat', mooring_lat, ...
    'mooringLon', mooring_lon, ...
    'packetDirectionToleranceDeg', 25, ...
    'packetMinOverlapMeters', 1000, ...
    'packetMinOverlapFraction', 0.5, ...
    'packetMinSeparationMeters', 250, ...
    'packetMaxNeighborGapMeters', 8000, ...
    'packetMaxSpanMeters', 40000);

day_delay = 3;

%% ==================== 数据读取 ====================
shp_dir = '../data/shp_files';
shp_filelist = dir(fullfile(shp_dir, '*.shp'));

% 读取系泊数据
mooring_dir = '../data/月份挑内波数据';
mooring_name = '2020年内波时间与方向.xlsx'; 
T = readtable(fullfile(mooring_dir, mooring_name));

obs_modes = T{:, 1}; % <--- 修改点1：从第1列读取 Mode (1或2)
st_times  = T{:, 2}; % 第2列是时间
ed_times  = T{:, 3};
obs_dirs  = T{:, 5}; % <--- 请确认第5列是方向(Degree)。如果是时间，请改为对应列号！

numCrests = 0;
for k = 1:length(shp_filelist)
    shp_name = fullfile(shp_dir, shp_filelist(k).name);
    numCrests = numCrests + length(shaperead(shp_name));
end

%% ==================== 主循环：计算与匹配 ====================
% 初始化存储容器
w = Inf(numCrests, size(T, 1));            % 速度差 (用于匹配权重)
dir_diff_mat = Inf(numCrests, size(T, 1)); % 方向差矩阵

crestLen = zeros(numCrests, size(T, 1));
crestDir_arr = NaN(numCrests, 1);
min_dis = zeros(numCrests, size(T, 1));
crest_sensing_time = cell(numCrests, 1);
temp_crest_data = cell(numCrests, 1); 
signedPos_list = zeros(size(crest_sensing_time));
isPass_list = zeros(size(crest_sensing_time));
crest_scene_id = zeros(numCrests, 1);
crest_raw_lat = cell(numCrests, 1);
crest_raw_lon = cell(numCrests, 1);

idxCrests = 0;
fprintf('开始处理 %d 个文件...\n', length(shp_filelist));

for k = 1:length(shp_filelist)
    shp_name = fullfile(shp_dir, shp_filelist(k).name);
    shp_time = getTimeFromFilename(shp_name);
    shp_time = shp_time + hours(8); 
    
    idx = st_times >= (shp_time - days(day_delay)) & ...
          st_times <= (shp_time + days(day_delay));
    current_mooring_indices = find(idx);
    
    crestLines = shaperead(shp_name);
    
    for i = 1:length(crestLines)
        global_idx = idxCrests + i;
        rawLat = crestLines(i).Y;
        rawLon = crestLines(i).X;

        % 保存波包分组需要的原始几何。无效方向仍保留在目录中，但由于
        % direction_deg 为 NaN，group_scene_wave_packets 会将其排除。
        crest_scene_id(global_idx) = k;
        crest_raw_lat{global_idx} = rawLat(:);
        crest_raw_lon{global_idx} = rawLon(:);
        
        % 1. 统一解析传播方向。匹配、结果保存和可视化共用该方向。
        directionResolution = resolveCrestDirection( ...
            rawLat, rawLon, mooring_lat, mooring_lon);
        if ~directionResolution.isValid
            % 需要翻转但 doFlip=false 的波锋不进入任何候选事件。
            continue;
        end
        cDir = directionResolution.dirDeg;

        % if cDir >= 15 & cDir <= 165
        %     % if max(rawLat(~isnan(rawLat))) < 19.2 & max(rawLat(~isnan(rawLat))) < 114.5
        %     %     plot(rawLon, rawLat);
        %         continue;
        %     % end
        % end

        % cData = buildCrestData(rawLat, rawLon, resample_res);
        % temp_crest_data{global_idx} = cData;
        % K_val = signedPositionFromArcLength(cData.s_peak, cData.L_total);
        % isPassK = true;
        % propLatK = NaN;
        % propLonK = NaN;
        % isPass_list(global_idx) = isPassK;
        % signedPos_list(global_idx) = K_val;
        % signedPos_Moor = K_val;

        % if shouldPlotDebugCrest(DEBUG, global_idx)
        %     plotCrestKDebug(rawLat, rawLon, cData, mooring_lat, mooring_lon, ...
        %         signedPos_Moor, propLatK, propLonK);
        %     fprintf("isPass: %d, Pos: %d\n", isPassK, signedPos_Moor);
        % end

        crestDir_arr(global_idx) = cDir;
        crest_sensing_time{global_idx} = shp_time;

        % Keep the original flow: refresh cData before candidate matching.
        cData = buildCrestData(rawLat, rawLon, resample_res);
        temp_crest_data{global_idx} = cData;

        for j = 1:length(current_mooring_indices)
            target_mooring_idx = current_mooring_indices(j);
            target_obs_dir = obs_dirs(target_mooring_idx);
            current_mode   = obs_modes(target_mooring_idx);

            % --- 方向筛选 ---
            d_diff = abs(cDir - target_obs_dir);
            if d_diff > 180, d_diff = 360 - d_diff; end

            % if d_diff > angle_tol
            %     continue; 
            % end

            % --- 传播检测 ---
            param_val = T{target_mooring_idx, 4}; % 假设第4列是速度相关参数
            [isPass, propSpeed, crest_min_dis] = isCrestPassMooring_capsule_dir(rawLat, rawLon, shp_time, ...
                current_mode, mooring_lat, mooring_lon, ...
                st_times(target_mooring_idx), ed_times(target_mooring_idx), ...
                60, 86400*10, 100000, directionResolution);

            if isPass
                % 最近波段的可行速度区间必须覆盖本站 KdV 波速。
                % 区间外候选保持 Inf，避免巨大未匹配代价强制保留
                % 明显不一致的有限速度差配对。
                if min(abs(propSpeed)) <= param_val && max(abs(propSpeed)) >= param_val
                    s_diff = 0;
                else
                    s_diff = min(abs(abs(propSpeed) - param_val));
                end

                % % --- 东沙检测 ---
                % [isPass_Dongsha, ~, signedPos_DS, ~, ~, ~, ~] = reachPointAlongPropDir( ...
                %     rawLat, rawLon, shp_time, dongsha_lat, dongsha_lon, [1 1.1], 0);

                % 记录匹配信息
                w(global_idx, target_mooring_idx) = s_diff;        % 速度差存入 w
                dir_diff_mat(global_idx, target_mooring_idx) = d_diff; % [新增] 方向差存入矩阵

                crestLen(global_idx, target_mooring_idx) = calcCrestLen(rawLat, rawLon);
                min_dis(global_idx, target_mooring_idx) = crest_min_dis;
            end
        end
    end
    idxCrests = idxCrests + length(crestLines);
end

%% ==================== 波包有序全局匹配 ====================
% packet_rank=1 表示传播方向上最靠前的已提取波锋。求解器允许包内
% 波锋或事件缺口，但禁止靠前波锋对应到更晚的系泊事件。
crest_catalog = table((1:numCrests)', crest_scene_id, ...
    crest_raw_lat, crest_raw_lon, crestDir_arr, ...
    'VariableNames', {'crest_idx', 'scene_id', 'latitude', ...
    'longitude', 'direction_deg'});
packet_catalog = group_scene_wave_packets(crest_catalog, packet_config);

[M, matching_diagnostics] = matchpairs_ordered_packets( ...
    w, 10000000, packet_catalog.packet_id, ...
    packet_catalog.packet_rank, st_times);
num_matches = size(M, 1);

fprintf(['全局有序匹配完成：%d 对，改配事件 %d 个，未配波锋 %d 条，', ...
    '未配事件 %d 个，顺序约束 %d 条，总速度差 %.6g。\n'], ...
    matching_diagnostics.match_count, ...
    matching_diagnostics.changed_event_assignment_count, ...
    matching_diagnostics.unmatched_crest_count, ...
    matching_diagnostics.unmatched_event_count, ...
    matching_diagnostics.order_cut_count, ...
    matching_diagnostics.total_cost);

%% ==================== 结果提取 ====================
out_mooring_time = NaT(num_matches, 1);
out_crest_time   = NaT(num_matches, 1);
out_crest_dir    = NaN(num_matches, 1);
out_crest_lon    = cell(num_matches, 1);
out_crest_lat    = cell(num_matches, 1);
out_peak_lon     = NaN(num_matches, 1);
out_peak_lat     = NaN(num_matches, 1);
out_K_mooring    = NaN(num_matches, 1);
out_mode         = NaN(num_matches, 1);
out_kdv_speed    = NaN(num_matches, 1);
out_speed_diff   = NaN(num_matches, 1);
out_dir_diff     = NaN(num_matches, 1); % [新增] 初始化方向差数组
out_crest_idx    = M(:, 1);
out_crest_len    = NaN(num_matches, 1);
out_packet_id    = packet_catalog.packet_id(M(:, 1));
out_packet_rank  = packet_catalog.packet_rank(M(:, 1));

fprintf('匹配完成，共 %d 对。正在提取结果...\n', num_matches);

for k = 1:num_matches
    cIdx = M(k, 1); mIdx = M(k, 2); 
    cData = temp_crest_data{cIdx};
    
    % 1. 基础信息
    out_mooring_time(k) = st_times(mIdx);
    out_mode(k)         = obs_modes(mIdx);
    out_kdv_speed(k)    = T{mIdx, 4}; % 本站 KdV 波速 (m/s)
    
    % [新增] 提取差值
    out_speed_diff(k)   = w(cIdx, mIdx) - lambda_dir * dir_diff_mat(cIdx, mIdx);          % 速度差
    out_dir_diff(k)     = dir_diff_mat(cIdx, mIdx); % 方向差
    out_crest_len(k)    = crestLen(cIdx, mIdx);
    
    out_crest_time(k)   = crest_sensing_time{cIdx};
    out_crest_dir(k)    = crestDir_arr(cIdx);
    
    % 2. 空间坐标
    out_crest_lon{k}    = cData.resLon;
    out_crest_lat{k}    = cData.resLat;
    out_peak_lon(k)     = cData.peakLon;
    out_peak_lat(k)     = cData.peakLat;
    
    % 3. 计算 K_mooring
    [isPass, ~, s_hit_meters, ~, ~, ~, ~] = reachMooringByTranslation( ...
        cData.resLat, cData.resLon, out_crest_time(k), ...
        mooring_lat, mooring_lon, [0.1 5.0], 100000); 
    
    if isPass && isfinite(s_hit_meters)
        s_hit = max(0, min(s_hit_meters, cData.L_total));
        if s_hit <= cData.s_peak
            if cData.s_peak > 1e-3
                K = (s_hit - cData.s_peak) / cData.s_peak;
            else
                K = -1;
            end
        else
            len_north = max(cData.L_total - cData.s_peak, 1e-3);
            K = (s_hit - cData.s_peak) / len_north; 
        end
        out_K_mooring(k) = K;
    else
        out_K_mooring(k) = NaN; 
    end
end

%% ==================== 排序 (按时间) ====================
[mooring_time, sort_idx] = sort(out_mooring_time);

% 同步调整所有变量
mode         = out_mode(sort_idx);
kdv_speed    = out_kdv_speed(sort_idx);
speed_diff   = out_speed_diff(sort_idx);
dir_diff     = out_dir_diff(sort_idx); % [新增] 同步排序
crest_time   = out_crest_time(sort_idx);
crest_dir    = out_crest_dir(sort_idx);
crest_lon    = out_crest_lon(sort_idx);
crest_lat    = out_crest_lat(sort_idx);
peak_lon     = out_peak_lon(sort_idx);
peak_lat     = out_peak_lat(sort_idx);
K_mooring    = out_K_mooring(sort_idx);
crest_idx    = out_crest_idx(sort_idx);
packet_id    = out_packet_id(sort_idx);
packet_rank  = out_packet_rank(sort_idx);

%% ==================== 保存结果 (MAT + XLSX) ====================
% 1. 保存 MAT
mat_name = 'match_res_90deg_15_165.mat';
save(output_mat_name, 'mode', 'mooring_time', 'speed_diff', 'dir_diff', ...
    'crest_time', 'crest_dir', 'crest_lon', 'crest_lat', 'peak_lon', ...
    'peak_lat', 'K_mooring', 'crest_idx', 'packet_id', 'packet_rank', ...
    'matching_diagnostics', 'kdv_speed');

% % 2. 保存 Excel
% fprintf('正在生成 Excel 表格...\n');
% crest_lon_str = cellfun(@(x) sprintf('%.4f, ', x(:)'), crest_lon, 'UniformOutput', false);
% crest_lat_str = cellfun(@(x) sprintf('%.4f, ', x(:)'), crest_lat, 'UniformOutput', false);
% 
% T_export = table(mode, mooring_time, speed_diff, dir_diff, crest_time, crest_dir, ...
%                  peak_lon, peak_lat, K_mooring, ...
%                  crest_lon_str, crest_lat_str, ...
%     'VariableNames', {'Mode', 'MooringTime', 'SpeedDiff', 'DirDiff', 'CrestTime', 'CrestDir', ...
%                       'PeakLon', 'PeakLat', 'K_Mooring', ...
%                       'CrestLon_Str', 'CrestLat_Str'});
% 
% output_xlsx_name = strrep(output_mat_name, '.mat', '.xlsx');
% writetable(T_export, output_xlsx_name);
% fprintf('结果已保存至 %s\n', output_xlsx_name);

%% 辅助函数
function cData = buildCrestData(rawLat, rawLon, resample_res)
    [resLat, resLon, peakLat, peakLon, s_peak, L_total] = ...
        analyze_crest_shape_orig(rawLat, rawLon, resample_res);
    s = crestArcLengthMeters(resLat, resLon);

    cData.resLat = resLat;
    cData.resLon = resLon;
    cData.peakLat = peakLat;
    cData.peakLon = peakLon;
    cData.s = s;
    cData.s_peak = s_peak;
    cData.L_total = L_total;
end


function s = crestArcLengthMeters(lat, lon)
    % 计算波峰线的累计弧长 (米)
    good = isfinite(lat) & isfinite(lon);
    lat = lat(good);
    lon = lon(good);
    if numel(lat) < 2
        s = zeros(size(lat));
        return;
    end
    R_earth = 6371000;
    lat0 = mean(lat);
    lon0 = mean(lon);
    x = R_earth * cosd(lat0) .* deg2rad(lon - lon0);
    y = R_earth * deg2rad(lat - lat0);
    s = [0; cumsum(hypot(diff(x), diff(y)))];
end

function K = signedPositionFromArcLength(s_hit_meters, L_total)
    K = 2 * s_hit_meters / L_total - 1;
end

function tf = shouldPlotDebugCrest(DEBUG, global_idx)
    tf = isfield(DEBUG, 'plotKPoint') && DEBUG.plotKPoint;
    if tf && isfield(DEBUG, 'targetCrestIdx') && ~isempty(DEBUG.targetCrestIdx)
        tf = any(DEBUG.targetCrestIdx == global_idx);
    end
end

function plotCrestKDebug(rawLat, rawLon, cData, mooring_lat, mooring_lon, signedPos_Moor, propLat, propLon)
    figure; hold on; axis equal;
    plot(rawLon, rawLat, 'k-', 'LineWidth', 1);
    plot(cData.resLon, cData.resLat, 'b.');
    plot(cData.peakLon, cData.peakLat, 'ro', 'MarkerFaceColor', 'r');
    if ~isnan(propLat) && ~isnan(propLon)
        plot(propLon, propLat, '--', 'LineWidth', 1.2);
    end
    plot(mooring_lon, mooring_lat, 'gp', 'MarkerFaceColor', 'g', 'MarkerSize', 12);

    [ptLon, ptLat] = pointFromSignedPosition(cData, signedPos_Moor);
    if ~isnan(ptLat) && ~isnan(ptLon)
        plot(ptLon, ptLat, 'mo', 'MarkerFaceColor', 'm', 'MarkerSize', 8);
    end
    title('Crest geometry and mooring signed position');
    legend({'raw', 'resampled', 'peak', 'translation', 'mooring', 'K point'}, 'Location', 'best');
end

function [ptLon, ptLat] = pointFromSignedPosition(cData, signed_pos)
    ptLon = NaN;
    ptLat = NaN;
    if isnan(signed_pos) || isempty(cData.s) || cData.L_total == 0
        return;
    end
    s_query = (signed_pos + 1) / 2 * cData.L_total;
    ptLon = interp1(cData.s, cData.resLon, s_query, 'linear', 'extrap');
    ptLat = interp1(cData.s, cData.resLat, s_query, 'linear', 'extrap');
end
