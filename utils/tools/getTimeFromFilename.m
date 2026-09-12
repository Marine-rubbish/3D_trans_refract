function t = getTimeFromFilename(shp_name)
    % 从文件名中提取时间信息
    day_tokens = regexp(shp_name, '(?:A|_A)(\d{4})(\d{3})(?=\.|_)', 'tokens');
    year = str2double(day_tokens{1}{1});
    day = str2double(day_tokens{1}{2});
    dateStr = dayOfYearToDate(year, day);
    
    time_tokens = regexp(shp_name, '\.(\d{2})(\d{2})\.', 'tokens');
    h = str2double(time_tokens{1}{1});
    m = str2double(time_tokens{1}{2});
    t = datetime(dateStr, 'InputFormat', 'yyyy-MM-dd') + hours(h) + minutes(m);
end

function dateStr = dayOfYearToDate(year, day)
    % 将年份和一年中的第几天转换为日期字符串
    dateStr = datetime(year, 1, 1) + days(day - 1);
    dateStr = datestr(dateStr, 'yyyy-mm-dd');
end
