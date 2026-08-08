function len = calcCrestLen(lat, lon)
    % 计算波峰线的长度
    % lat: 波峰线的纬度坐标
    % lon: 波峰线的经度坐标
    % len: 波峰线的长度（单位:米）
    len = 0;
    for i = 1:length(lon)-2
        [arclen, ~] = distance(lat(i), lon(i), lat(i+1), lon(i+1));
        len = len + deg2km(arclen)*1000;
    end
end
