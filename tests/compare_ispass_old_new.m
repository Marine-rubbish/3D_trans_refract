function [differenceTable, summary] = compare_ispass_old_new(maxPairs)
% Compare old ternary-search and new analytic capsule isPass decisions.
%
% Examples:
%   [differences, summary] = compare_ispass_old_new(500); % quick check
%   [differences, summary] = compare_ispass_old_new();    % all candidates

if nargin < 1 || isempty(maxPairs)
    maxPairs = inf;
end
if ~isscalar(maxPairs) || maxPairs <= 0
    error('maxPairs must be a positive scalar or inf.');
end

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(projectRoot, 'utils')));

shpDir = 'F:\research\MODIS\shp_files';
mooringDir = 'F:\research\月份挑内波数据';
mooringName = '2020年内波时间与方向.xlsx';

angleTol = 90;
dayDelay = 3;
teps = 60;
tlim = 86400 * 10;
radius = 100000;

if ~isfolder(shpDir)
    error('Shapefile directory not found: %s', shpDir);
end
mooringPath = fullfile(mooringDir, mooringName);
if ~isfile(mooringPath)
    error('Mooring table not found: %s', mooringPath);
end

T = readtable(mooringPath);
obsModes = T{:, 1};
stTimes = T{:, 2};
edTimes = T{:, 3};
obsDirs = T{:, 5};
shpFiles = dir(fullfile(shpDir, '*.shp'));

sourceFile = strings(0,1);
crestIndex = zeros(0,1);
mooringIndex = zeros(0,1);
crestTimeOut = NaT(0,1);
moorStartOut = NaT(0,1);
moorEndOut = NaT(0,1);
modeOut = zeros(0,1);
directionDeg = zeros(0,1);
directionDiff = zeros(0,1);
oldIsPassOut = false(0,1);
newIsPassOut = false(0,1);
oldSpeedOut = strings(0,1);
newSpeedOut = strings(0,1);
oldMinDistance = zeros(0,1);
newMinDistance = zeros(0,1);
newReason = strings(0,1);

testedPairs = 0;
oldPassCount = 0;
newPassCount = 0;
globalCrestIndex = 0;
stopRequested = false;

for k = 1:numel(shpFiles)
    shpPath = fullfile(shpDir, shpFiles(k).name);
    shpTime = getTimeFromFilename(shpPath) + hours(8);
    candidateMoorings = find(stTimes >= shpTime-days(dayDelay) & ...
        stTimes <= shpTime+days(dayDelay));
    crestLines = shaperead(shpPath);

    for i = 1:numel(crestLines)
        currentCrestIndex = globalCrestIndex + i;
        rawLat = crestLines(i).Y;
        rawLon = crestLines(i).X;

        cDir = mod(90-calcDirection(rawLat, rawLon), 360);
        if cDir > 45 && cDir < 180
            [dirDegOut, doFlip, ~] = maybeFlipCrestDir( ...
                rawLat, rawLon, 20.816666666666666, 115.76666666666667);
            if doFlip
                cDir = dirDegOut;
            end
        end

        for j = 1:numel(candidateMoorings)
            if testedPairs >= maxPairs
                stopRequested = true;
                break;
            end

            mIdx = candidateMoorings(j);
            dDiff = abs(cDir-obsDirs(mIdx));
            if dDiff > 180, dDiff = 360-dDiff; end
            if dDiff > angleTol
                continue;
            end

            testedPairs = testedPairs + 1;
            [oldPass, oldSpeed, oldMinDis] = isCrestPassMooring_bin_dir( ...
                rawLat, rawLon, shpTime, obsModes(mIdx), ...
                20.816666666666666, 115.76666666666667, ...
                stTimes(mIdx), edTimes(mIdx), teps, tlim, radius);
            [newPass, newSpeed, newMinDis, details] = ...
                isCrestPassMooring_capsule_dir( ...
                rawLat, rawLon, shpTime, obsModes(mIdx), ...
                20.816666666666666, 115.76666666666667, ...
                stTimes(mIdx), edTimes(mIdx), teps, tlim, radius);

            oldPassCount = oldPassCount + logical(oldPass);
            newPassCount = newPassCount + logical(newPass);

            if logical(oldPass) ~= logical(newPass)
                sourceFile(end+1,1) = string(shpFiles(k).name); %#ok<AGROW>
                crestIndex(end+1,1) = currentCrestIndex; %#ok<AGROW>
                mooringIndex(end+1,1) = mIdx; %#ok<AGROW>
                crestTimeOut(end+1,1) = shpTime; %#ok<AGROW>
                moorStartOut(end+1,1) = stTimes(mIdx); %#ok<AGROW>
                moorEndOut(end+1,1) = edTimes(mIdx); %#ok<AGROW>
                modeOut(end+1,1) = obsModes(mIdx); %#ok<AGROW>
                directionDeg(end+1,1) = cDir; %#ok<AGROW>
                directionDiff(end+1,1) = dDiff; %#ok<AGROW>
                oldIsPassOut(end+1,1) = logical(oldPass); %#ok<AGROW>
                newIsPassOut(end+1,1) = logical(newPass); %#ok<AGROW>
                oldSpeedOut(end+1,1) = numericSummary(oldSpeed); %#ok<AGROW>
                newSpeedOut(end+1,1) = numericSummary(newSpeed); %#ok<AGROW>
                oldMinDistance(end+1,1) = oldMinDis; %#ok<AGROW>
                newMinDistance(end+1,1) = newMinDis; %#ok<AGROW>
                newReason(end+1,1) = details.reason; %#ok<AGROW>
            end

            if mod(testedPairs, 1000) == 0
                fprintf('Compared %d candidate pairs; differences: %d\n', ...
                    testedPairs, numel(oldIsPassOut));
            end
        end

        if stopRequested, break; end
    end

    globalCrestIndex = globalCrestIndex + numel(crestLines);
    if stopRequested, break; end
end

differenceTable = table(sourceFile, crestIndex, mooringIndex, ...
    crestTimeOut, moorStartOut, moorEndOut, modeOut, directionDeg, ...
    directionDiff, oldIsPassOut, newIsPassOut, oldSpeedOut, newSpeedOut, ...
    oldMinDistance, newMinDistance, newReason, ...
    'VariableNames', {'source_file','crest_idx','mooring_idx', ...
    'crest_time','mooring_start','mooring_end','mode','direction_deg', ...
    'direction_diff_deg','old_isPass','new_isPass','old_speed_mps', ...
    'new_speed_mps','old_min_distance_m','new_min_distance_m','new_reason'});

differenceCount = height(differenceTable);
oldOnlyCount = nnz(differenceTable.old_isPass & ~differenceTable.new_isPass);
newOnlyCount = nnz(~differenceTable.old_isPass & differenceTable.new_isPass);
summary = table(testedPairs, oldPassCount, newPassCount, differenceCount, ...
    oldOnlyCount, newOnlyCount, ...
    'VariableNames', {'tested_pairs','old_pass','new_pass','differences', ...
    'old_only','new_only'});

disp(summary);
if differenceCount > 0
    disp(differenceTable(1:min(30, differenceCount), :));
end
end

function text = numericSummary(value)
if isempty(value)
    text = "[]";
elseif all(isnan(value), 'all')
    text = "NaN";
else
    text = string(mat2str(value, 5));
end
end
