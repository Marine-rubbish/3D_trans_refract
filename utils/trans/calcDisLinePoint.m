function dist = calcDisLinePoint(lat_line, lon_line, lat_point, lon_point)
    % Calculate the distance between a line and a point
    % 
    % Args:
    %     lat_line: Latitude of the line
    %     lon_line: Longitude of the line
    %     lat_point: Latitude of the point
    %     lon_point: Longitude of the point
    % 
    % Returns:
    %     None
    % 
    % Example:
    %     calcDisLinePoint(20.816666666666666, 115.76666666666667, 20.816666666666666, 115.76666666666667)
    %
    
    % Calculate the distance between a line and a point
    % 把线段两个端点组成向量（假设lat_line和lon_line均为长度为2的数组）
    if length(lon_line) <= 1
        fprintf("lon_line %f", lon_line);
    end
    A = [lat_line(1), lon_line(1)];
    B = [lat_line(2), lon_line(2)];
    P = [lat_point, lon_point];

    % 计算从A指向B和从A指向P的向量
    v = B - A;
    w = P - A;

    % 计算投影因子
    t = dot(w, v) / dot(v, v);

    % 计算垂足坐标
    foot = A + t * v;

    % 判断垂足是否在线段上
    if t >= 0 && t <= 1
        % fprintf('垂足在线段上\n');
        % 计算点到线段的垂直距离
        dist = distance(P(1), P(2), foot(1), foot(2));
    else
        % fprintf('垂足不在线段上\n');
        % 如果不在线上，取距离最近端点的距离
        if t < 0
            dist = distance(P(1), P(2), A(1), A(2));
        else
            dist = distance(P(1), P(2), B(1), B(2));
        end
    end
end
