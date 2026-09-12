function plot_crest_direction(lon, lat, bound_size)
    % 绘制波峰线，并标出波峰线的传播方向（不使用 m_map）
    % lon: 波峰线经度
    % lat: 波峰线纬度
    % bound_size: 绘图边界大小

    figure;
    % 移除 NaN 值
    lon = lon(~isnan(lon));
    lat = lat(~isnan(lat));

    % 设置边界
    min_lon = min(lon, [], 'all') - bound_size;
    max_lon = max(lon, [], 'all') + bound_size;
    min_lat = min(lat, [], 'all') - bound_size;
    max_lat = max(lat, [], 'all') + bound_size;
    
    % 绘制波峰线
    plot(lon, lat, 'k', 'LineWidth', 1.5);
    hold on;
    axis([min_lon max_lon min_lat max_lat]);
    grid on;
    axis equal;

    % 计算中间点
    mid = floor(length(lon) / 2);
    lon_mid = lon(mid);
    lat_mid = lat(mid);
    
    % 计算凹凸性：判断中点相对于直线的偏移
    [lon_start, st_idx] = min(lon([1, end]));
    if st_idx == 2
        lat_start = lat(end);
        lon_end = lon(1);
        lat_end = lat(1);
    else
        lat_start = lat(1);
        lon_end = lon(end);
        lat_end = lat(end);
    end

    
    % 绘制首尾直连线
    plot([lon_start, lon_end], [lat_start, lat_end], 'r--', 'LineWidth', 2);

    % 添加首尾点标记
    plot(lon_start, lat_start, 'bo', 'MarkerSize', 8, 'MarkerFaceColor', 'b'); % 标记起点
    plot(lon_end, lat_end, 'bo', 'MarkerSize', 8, 'MarkerFaceColor', 'b');   % 标记终点

    % 添加起点和终点文字标注
    text(lon_start - 0.02, lat_start - 0.01, 'Start', 'FontSize', 12, 'Color', 'b');
    text(lon_end + 0.01, lat_end - 0.01, 'End', 'FontSize', 12, 'Color', 'b');
    
    % 计算直线中点
    mid_line_lon = (lon_start + lon_end) / 2;
    mid_line_lat = (lat_start + lat_end) / 2;
    
    % 计算直线方向向量和垂直方向向量
    dx = lon_end - lon_start;
    dy = lat_end - lat_start;
    length_line = sqrt(dx^2 + dy^2);
    perp_dx = dy / length_line;
    perp_dy = -dx / length_line;
    
    % 计算中点到直线的距离
    distance = sqrt((lon_mid - mid_line_lon)^2 + (lat_mid - mid_line_lat)^2);

    % 绘制传播方向箭头（直线方向）
    quiver(mid_line_lon, mid_line_lat, dx, dy, 0.25, 'k', 'LineWidth', 2, 'MaxHeadSize', 1.5);
    
    % 绘制中垂线箭头（垂直方向，箭头方向调转）
    quiver(mid_line_lon, mid_line_lat, -perp_dx * distance, -perp_dy * distance, 0, 'k', 'LineWidth', 2, 'MaxHeadSize', 1.5);

    % 绘制图形后设置坐标轴字体
    font_name = 'Times New Roman';
    font_size = 16;
    set(gca, 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', font_size);
    set(findall(gca, 'Type', 'text'), 'FontName', font_name, 'FontWeight', 'bold', 'Fontsize', font_size);
end
