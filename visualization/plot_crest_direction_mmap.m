function plot_crest_direction_mmap(lon, lat, bound_size)
    % 绘制波峰线，并标出波峰线的传播方向
    % lon: 波峰线经度
    % lat: 波峰线纬度
    % bound_size: 绘图边界大小
    
    figure
    lon = lon(~isnan(lon));
    lat = lat(~isnan(lat));
    min_lon = min(lon, [], 'all') - bound_size; max_lon = max(lon, [], 'all') + bound_size;
    min_lat = min(lat, [], 'all') - bound_size; max_lat = max(lat, [], 'all') + bound_size;
    hold on
    m_proj('mercator', 'lon', [min_lon max_lon], 'lat', [min_lat max_lat]);
    m_grid('box', 'fancy', 'tickdir', 'in'); % 绘制网格
    m_plot(lon, lat, 'k', 'LineWidth', 1.5);
    hold on 
    % 计算中间点
    mid = floor((length(lon))/2);
    lon_mid = lon(mid);
    lat_mid = lat(mid);
    
    lon_start = lon(1);
    lat_start = lat(1);
    lon_end = lon(end);
    lat_end = lat(end);
    
    m_plot([lon_start, lon_end], [lat_start, lat_end], 'r--', 'LineWidth', 2);
    
    % 计算直线中点
    mid_line_lon = (lon_start + lon_end) / 2;
    mid_line_lat = (lat_start + lat_end) / 2;
    
    % 计算直线的垂直方向向量
    dx = lon_end - lon_start;
    dy = lat_end - lat_start;
    length_line = sqrt(dx^2 + dy^2);
    perp_dx = -dy / length_line;
    perp_dy = dx / length_line;
    
    % 计算到弧线的距离
    distance = sqrt((lon_mid - mid_line_lon)^2 + (lat_mid - mid_line_lat)^2);

    m_quiver(mid_line_lon, mid_line_lat, dx, dy, 0.2, 'k-', 'LineWidth', 1.5, 'MaxHeadSize', 2);
    
    % 绘制中垂线，箭头方向调转，长度为到弧线的距离
    m_quiver(mid_line_lon, mid_line_lat, -perp_dx * distance, -perp_dy * distance, 0, 'k-', 'LineWidth', 1.5, 'MaxHeadSize', 2);
    ;
end
