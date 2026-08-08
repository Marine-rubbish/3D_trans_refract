% simu_all_crests_trans_dir_mode_update.m
clc; clear; close all;

addpath(genpath('..\utils')); % 确保包含 reachPointByTranslation 等函数

%% ==================== 参数设置 ====================
angle_tol = 90; % 角度容差（度）
resample_res = 250; % 波峰线重采样分辨率 (m)
lambda_dir = 0.02;
lambda_dir = 0;
output_mat_name = 'matched_results_with_mode_90deg_15_165.mat';

% 系泊点坐标
mooring_lat = 20.816666666666666;
mooring_lon = 115.76666666666667;

% 东沙坐标
dongsha_lat = 20.7;
dongsha_lon = 116.8;

day_delay = 3;

%% ==================== 数据读取 ====================
shp_dir = 'F:\research\MODIS\shp_files';
shp_filelist = dir(fullfile(shp_dir, '*.shp'));

% 读取系泊数据
mooring_dir = 'F:\research\月份挑内波数据';
% 注意：请确保文件名与你实际的 Excel 文件名一致
mooring_name = '2020年内波时间与方向.xlsx'; 
T = readtable(fullfile(mooring_dir, mooring_name));

% --- 数据列解析 (根据你的 csv 修改) ---
% 假设列结构: [Mode, StartTime, Direction(或EndTime), Speed, ...]
% 你的 CSV 第一列 file_type 是 Mode
% 你的 CSV 第二列 Var2 是 Time
% !重要提示!: 请确认你的 Excel 第3列是“观测方向(度)”还是“结束时间”？
% 如果现在的第3列是时间，你需要确保代码读入的是方向列。
% 下面代码假设 T 的第 3 列是方向 (obs_dirs)。如果不是，请修改索引 T{:, 3}。

% 筛除无效行 (假设基于第4列和第5列判空，如果你的表结构变了，请调整这里)
% T = T(~(isnan(T{:,4}) | isnan(T{:,5})), :); 

obs_modes = T{:, 1}; % <--- 修改点1：从第1列读取 Mode (1或2)
st_times  = T{:, 2}; % 第2列是时间
ed_times  = T{:, 3};
obs_dirs  = T{:, 5}; % <--- 请确认第3列是方向(Degree)。如果是时间，请改为对应列号！

numCrests = 0;
for k = 1:length(shp_filelist)
    shp_name = fullfile(shp_dir, shp_filelist(k).name);
    numCrests = numCrests + length(shaperead(shp_name));
end

%% ==================== 主循环：计算与匹配 ====================
% 初始化存储容器
w = Inf(numCrests, size(T, 1));            % 速度差 (用于匹配权重)
dir_diff_mat = Inf(numCrests, size(T, 1)); % [新增] 方向差矩阵

crestLen = zeros(numCrests, size(T, 1));
crestDir_arr = zeros(numCrests, 1);
min_dis = zeros(numCrests, size(T, 1));
crest_sensing_time = cell(numCrests, 1);
temp_crest_data = cell(numCrests, 1); 
signedPos_list = zeros(size(crest_sensing_time));
isPass_list = zeros(size(crest_sensing_time));

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
        
        % 1. 计算传播方向
        cDir = mod(90 - calcDirection(rawLat, rawLon), 360);
        if cDir > 45 & cDir < 180
            [dirDegOut, doFlip, ~] = maybeFlipCrestDir(rawLat, rawLon, mooring_lat, mooring_lon);
            if doFlip
                dirDeg = dirDegOut;
            end
        end

        % if cDir >= 15 & cDir <= 165
        %     % if max(rawLat(~isnan(rawLat))) < 19.2 & max(rawLat(~isnan(rawLat))) < 114.5
        %     %     plot(rawLon, rawLat);
        %         continue;
        %     % end
        % end

        [resLat, resLon, peakLat, peakLon, s_peak, L_total] = analyze_crest_shape(rawLat, rawLon, resample_res);
    
        % 存入 cData (后续还要用)
        cData.resLat = resLat; cData.resLon = resLon;
        cData.peakLat = peakLat; cData.peakLon = peakLon;
        cData.s_peak = s_peak; cData.L_total = L_total;
        temp_crest_data{global_idx} = cData;
    
        % 2. 调用传播函数 (传入 resLat, resLon 和 s_peak)
        % 注意：这里 radius 设为 100km (100000m)
        [isPass, ~, s_hit_meters, ~, ~, ~, ~] = reachMooringByTranslation( ...
            resLat, resLon, shp_time, ...
            mooring_lat, mooring_lon, [0.1 5.0], 100000, s_peak); % <--- 传入 s_peak
        
        isPass_list(global_idx) = isPass;
    
        % 3. 分段归一化计算 K 值
        K_val = NaN;
        if ~isnan(s_hit_meters) && ~isnan(s_peak) && L_total > 0
            s_hit = max(0, min(s_hit_meters, L_total));
            
            if s_hit <= s_peak
                % SW段 (-1 ~ 0)
                if s_peak > 1e-3
                    K_val = (s_hit - s_peak) / s_peak;
                else
                    K_val = -1; 
                end
            else
                % NE段 (0 ~ 1)
                len_north = L_total - s_peak;
                if len_north > 1e-3
                    K_val = (s_hit - s_peak) / len_north;
                else
                    K_val = 1; 
                end
            end
        end
        
        signedPos_list(global_idx) = K_val;
        signedPos_Moor = K_val;
        
        % % 绘图时的反算逻辑也需要微调，以匹配新的 K 定义
        % if ~isempty(t_lat)
        %      % ... (前面的排序和长度计算不变) ...
        % 
        %      % 反算 s_target (用于在图上标点)
        %      % 因为 K 是分段的，反算也要分段
        %      if signedPos_Moor <= 0
        %          % K in [-1, 0]: s = (K + 1) * s_peak? 
        %          % K = (s - s_p)/s_p => K*s_p = s - s_p => s = s_p(1+K)
        %          s_target_plot = s_peak_tmp * (1 + signedPos_Moor);
        %      else
        %          % K in [0, 1]: K = (s - s_p)/len_north => s = K*len_north + s_p
        %          s_target_plot = signedPos_Moor * (L_total_tmp - s_peak_tmp) + s_peak_tmp;
        %      end
        % 
        %      % ... (interp1 和 plot 逻辑不变，使用 s_target_plot) ...
        % end

        % 3. 计算 K_mooring

        plot(rawLon, rawLat, 'b.-'); % 绘制波峰线
        hold on
        plot(mooring_lon, mooring_lat, 'ro', 'MarkerFaceColor', 'r'); % 绘制系泊点
        theta = linspace(0, 2*pi, 360);
        range_circle = km2deg(30) * ones(size(theta));
        azimuth_circle = rad2deg(theta);
        [lat_circle, lon_circle] = reckon(20.816666666666666, 115.76666666666667, range_circle, azimuth_circle);
        plot(lon_circle, lat_circle, '--', 'LineWidth', 1, 'Color', [255, 0, 0]/255);
        plot(propLon, propLat, '--');

        % --- 【新增代码】计算并绘制 signedPos 点 ---
        % 1. 提取有效点
        valid_mask = ~isnan(rawLat) & ~isnan(rawLon);
        t_lat = rawLat(valid_mask); 
        t_lon = rawLon(valid_mask);
        
        if ~isempty(t_lat)
            % 2. 排序 (必须与 reachMooringByTranslation 内部逻辑严格一致)
            % 使用 lat+lon 综合判断 SW->NE，防止 U 型回转导致误判
            if (t_lat(1)) > (t_lat(end))
                t_lat = fliplr(t_lat);
                t_lon = fliplr(t_lon);
            end
            
            % 3. 【修正】去重 (仅去除相邻重复点，保护拓扑结构)
            % 千万不要用 unique(...,'rows')，那是会乱序的！
            d_seg_check = hypot(diff(t_lat), diff(t_lon));
            keep_mask = [true, d_seg_check > 1e-9]; % 保留距离大于0的点
            t_lat = t_lat(keep_mask);
            t_lon = t_lon(keep_mask);
            
            % 4. 计算可视化用的累计弧长 (Degree Space)
            d_seg = hypot(diff(t_lat), diff(t_lon));
            s_cum = [0, cumsum(d_seg)];
            L_vis_total = s_cum(end); % 可视化空间的总长
            
            % 5. 【核心逻辑】分段反算 s_target
            % 我们需要利用 analyze_crest_shape 算出的物理比例
            % s_peak_tmp 和 L_total_tmp 必须在前面已经计算好
            if exist('s_peak_tmp', 'var') && exist('L_total_tmp', 'var') && L_total_tmp > 0
                ratio_peak = s_peak_tmp / L_total_tmp;
            else
                ratio_peak = 0.5; % 兜底：如果没算曲率，假定在中间
            end
            
            % 将物理空间的峰值比例，映射到可视化空间的弧长上
            s_vis_peak = ratio_peak * L_vis_total;
            
            s_target = 0;
            if signedPos_Moor <= 0
                % 西南段 (-1 ~ 0) 反算: 
                % K = (s - s_p) / s_p  =>  s = (K + 1) * s_p
                s_target = (signedPos_Moor + 1) * s_vis_peak;
            else
                % 东北段 (0 ~ 1) 反算:
                % K = (s - s_p) / (L - s_p) => s = s_p + K * (L - s_p)
                s_target = s_vis_peak + signedPos_Moor * (L_vis_total - s_vis_peak);
            end
            
            % 边界保护
            s_target = max(0, min(s_target, L_vis_total));
            
            % 6. 插值得到经纬度
            p_lat = interp1(s_cum, t_lat, s_target, 'linear');
            p_lon = interp1(s_cum, t_lon, s_target, 'linear');
            
            % 7. 绘制该点 (绿色五角星)
            plot(p_lon, p_lat, 'pentagram', ...
                 'MarkerSize', 12, ...
                 'MarkerEdgeColor', 'k', ...
                 'MarkerFaceColor', 'g', ...
                 'LineWidth', 1.5);
             
            % 文字标签
            text(p_lon, p_lat, sprintf('  K=%.2f', signedPos_Moor), ...
                 'Color', 'blue', 'FontSize', 10, 'FontWeight', 'bold');
        end

        fprintf("isPass: %d, Pos: %d\n", isPass, signedPos_Moor);
        ;
        
        
        if isPass
            s_hit = (signedPos_Moor + 1) / 2 * cData.L_total;
            if s_hit <= cData.s_peak
                K = (s_hit - cData.s_peak) / cData.s_peak; 
            else
                len_north = max(cData.L_total - cData.s_peak, 1e-3);
                K = (s_hit - cData.s_peak) / len_north; 
            end
            out_K_mooring(k) = K;
        else
            out_K_mooring(k) = NaN; 
        end

        crestDir_arr(global_idx) = cDir;
        crest_sensing_time{global_idx} = shp_time;

        % 2. 几何分析
        [resLat, resLon, peakLat, peakLon, s_peak, L_total] = analyze_crest_shape(rawLat, rawLon, resample_res);
        cData.resLat = resLat; cData.resLon = resLon;
        cData.peakLat = peakLat; cData.peakLon = peakLon;
        cData.s_peak = s_peak; cData.L_total = L_total; 
        temp_crest_data{global_idx} = cData;

        for j = 1:length(current_mooring_indices)
            target_mooring_idx = current_mooring_indices(j);
            target_obs_dir = obs_dirs(target_mooring_idx);
            current_mode   = obs_modes(target_mooring_idx);

            % --- 方向筛选 ---
            d_diff = abs(cDir - target_obs_dir);
            if d_diff > 180, d_diff = 360 - d_diff; end

            if d_diff > angle_tol
                continue; 
            end

            % --- 传播检测 ---
            param_val = T{target_mooring_idx, 4}; % 假设第4列是速度相关参数
            [isPass, propSpeed, crest_min_dis] = isCrestPassMooring_bin_dir(rawLat, rawLon, shp_time, ...
                current_mode, mooring_lat, mooring_lon, ...
                st_times(target_mooring_idx), ed_times(target_mooring_idx), ...
                60, 86400*10, 100000);

            if isPass
                % 计算速度差
                if min(abs(propSpeed)) <= param_val && max(abs(propSpeed)) >= param_val
                    s_diff = 0;
                else
                    s_diff = min(abs(abs(propSpeed) - param_val));
                end

                % % --- 东沙检测 ---
                % [isPass_Dongsha, ~, signedPos_DS, ~, ~, ~, ~] = reachPointByTranslation( ...
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

%% ==================== 匈牙利算法匹配 ====================
valid_idx = find(~all(isinf(w), 2));
w_vaild = w(valid_idx, :);
[M, ~, ~] = matchpairs(w, 10000000);
num_matches = size(M, 1);

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
out_speed_diff   = NaN(num_matches, 1);
out_dir_diff     = NaN(num_matches, 1); % [新增] 初始化方向差数组
out_crest_idx    = M(:, 1);
out_crest_len    = NaN(num_matches, 1);

fprintf('匹配完成，共 %d 对。正在提取结果...\n', num_matches);

for k = 1:num_matches
    cIdx = M(k, 1); mIdx = M(k, 2); 
    cData = temp_crest_data{cIdx};
    
    % 1. 基础信息
    out_mooring_time(k) = st_times(mIdx);
    out_mode(k)         = obs_modes(mIdx);
    
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
    [isPass, ~, signedPos_Moor, ~, ~, ~, ~] = reachMooringByTranslation( ...
        cData.resLat, cData.resLon, out_crest_time(k), ...
        mooring_lat, mooring_lon, [0.1 5.0], 0); 
    
    if isPass
        s_hit = (signedPos_Moor + 1) / 2 * cData.L_total;
        if s_hit <= cData.s_peak
            K = (s_hit - cData.s_peak) / cData.s_peak; 
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

%% ==================== 保存结果 (MAT + XLSX) ====================
% 1. 保存 MAT
mat_name = 'match_res_90deg_15_165.mat';
save(output_mat_name, 'mode', 'mooring_time', 'speed_diff', 'dir_diff', ...
    'crest_time', 'crest_dir', 'crest_lon', 'crest_lat', 'peak_lon', 'peak_lat', 'K_mooring', 'crest_idx');

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

