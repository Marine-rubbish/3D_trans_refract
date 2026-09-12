function len = calcCrestLenPro(lat, lon)
    % 计算波峰线长度（m），支持 NaN 分段
    % 使用 WGS84 椭球测地线距离

    % 找出每一段的有效索引（按 NaN 分割）
    isn = isnan(lat) | isnan(lon);
    idx = find(~isn);

    if numel(idx) < 2
        len = 0;
        return;
    end

    % 将连续段分开累计
    len = 0;
    wgs84 = wgs84Ellipsoid('meter');

    % 找到所有连续区间
    breaks = [0; find(diff(idx) > 1); numel(idx)];
    for k = 1:numel(breaks)-1
        seg = idx(breaks(k)+1 : breaks(k+1));
        if numel(seg) < 2, continue; end

        latSeg = lat(seg);
        lonSeg = lon(seg);

        % 向量化累加相邻点距离
        d = distance(latSeg(1:end-1), lonSeg(1:end-1), ...
                     latSeg(2:end),   lonSeg(2:end), wgs84);
        len = len + sum(d, 'omitnan');
    end
end
