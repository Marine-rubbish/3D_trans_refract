function [lat2, lon2] = calcPropagation(lat1, lon1, theta_deg, time, speed)
    % 输入参数
    % lat1, lon1: 初始经纬度（度）
    % theta_deg: 方向角（度，正北顺时针）
    % time: 传播时间（秒）
    % speed: 速度（米/秒）
    % 返回值
    % lat2, lon2: 终点经纬度（度）
    lat1 = lat1(~isnan(lat1));
    lon1 = lon1(~isnan(lon1));
    
    R = 6371000; % 地球半径（米）
    d = speed * time; % 移动距离（米）
    
    % 角度转弧度
    theta_rad = deg2rad(theta_deg);
    lat1_rad = deg2rad(lat1);
    lon1_rad = deg2rad(lon1);
    
    % 计算纬度变化量
    delta_lat = d / R .* cos(theta_rad);
    
    % 计算经度变化量（考虑纬度对经度弧长的影响）
    delta_lon = d / R .* sin(theta_rad) ./ cos(lat1_rad);
    
    % 新经纬度
    lat2_rad = lat1_rad + delta_lat;
    lon2_rad = lon1_rad + delta_lon;
    
    % 弧度转角度
    lat2 = rad2deg(lat2_rad);
    lon2 = rad2deg(lon2_rad);
end
