function [selCrestLines, selDates] = search_crest_by_coord(crestData, latRange, lonRange)
%SEARCH_CREST_BY_COORD  Find crest‐line segments and their dates within lat/lon bounds
%
%   [selCrestLines, selDates] = SEARCH_CREST_BY_COORD(crestData, latRange, lonRange)
%   crestData   : struct array with fields
%                    .Lat   (vector of latitudes for each crest line)
%                    .Lon   (vector of longitudes)
%                    .Date  (datetime or datenumber scalar)
%   latRange    : [minLat maxLat]
%   lonRange    : [minLon maxLon]
%
%   selCrestLines : cell array, each cell is an N×2 array [lat lon]
%   selDates      : array of datetime or datenumber, corresponding to each cell

    narginchk(3,3);
    validateattributes(crestData, {'struct'}, {'nonempty'});
    validateattributes(latRange, {'numeric'}, {'numel',2});
    validateattributes(lonRange, {'numeric'}, {'numel',2});

    selCrestLines = {};
    selDates      = [];

    for ii = 1:numel(crestData)
        lat = crestData(ii).Lat(:);
        lon = crestData(ii).Lon(:);
        if any( lat>=latRange(1) & lat<=latRange(2) & ...
                lon>=lonRange(1) & lon<=lonRange(2) )
            selCrestLines{end+1} = [lat lon]; %#ok<AGROW>
            selDates(end+1)      = crestData(ii).Date; %#ok<AGROW>
        end
    end

    % If none found, return empty outputs
    if isempty(selCrestLines)
        selDates = selDates([]); 
    end
end
