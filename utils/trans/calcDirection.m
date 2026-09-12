function direction = calcDirection(lat, lon)
    % 计算波峰线的传播方向 以正东方向为0度，逆时针增加
    % lat, lon: 波峰线的经纬度坐标

    % 结合弧线的凹凸性判断方向
    lon = lon(~isnan(lon));
    lat = lat(~isnan(lat));
    % if length(lat) <= 5
    %     direction = -1;
    % end
    % % 按照x坐标从大到小 y坐标从大到小排序
    % [coordsX, idx] = sort(lon, 'ascend');
    % coordsY = sort(lat, 'ascend');
    % 计算中间点
    idx_mid = floor((length(lon)+1)/2);
    % x_mid = median(coordsX);
    % [~, idx_mid] = min(abs(lon - x_mid));
    % y_mid = lat(idx_mid);
    x_mid = lon(idx_mid);
    y_mid = lat(idx_mid);
    % 计算凹凸性：判断中点相对于直线的偏移
    [x_start, st_idx] = min(lon([1, end]));
    if st_idx == 2
        y_start = lat(end);
        x_end = lon(1);
        y_end = lat(1);
    else
        y_start = lat(1);
        x_end = lon(end);
        y_end = lat(end);
    end
    % 计算斜率
    slope = (y_end - y_start) / (x_end - x_start);
    % 期望中点
    x_expected = (x_end + x_start) / 2;
    y_expected = slope * (x_expected - x_start) + y_start;
    % 计算中点与预期中点的叉积
    cross_product = (x_mid - x_expected) * (y_end - y_start) - (y_mid - y_expected) * (x_end - x_start);
    % 计算方向角（弧度转度）
    angle = rad2deg(atan2(y_end - y_start, x_end - x_start)) + 90;
    % 确保角度在0-360度之间
    angle = mod(angle + 360, 360);
    direction = angle;
    % plot_crest_direction(lon, lat, 0.05);
    % 实际中点与期望中点比较并调整方向
    if cross_product > 0
        direction = mod(direction + 180, 360);
    end
    % m_plot(x_mid, y_mid, 'ro');
    % m_plot([x_start, x_expected, x_end], [y_start, y_expected, y_end], 'bo');
end
