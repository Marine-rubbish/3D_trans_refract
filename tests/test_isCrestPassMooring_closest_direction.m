function tests = test_isCrestPassMooring_closest_direction
%TEST_ISCRESTPASSMOORING_CLOSEST_DIRECTION 验证横向最近点的时空方向规则。
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(projectRoot, 'utils')));
testCase.TestData.crestTime = datetime(2020, 1, 1, 0, 0, 0);
testCase.TestData.moorLat = 20;
testCase.TestData.moorLon = 115;
end

function testFutureEventMatchesPositiveClosestDisplacement(testCase)
lat = [19.9, 19.9];
lon = [114.9, 115.1];

[isPass, propSpeed, details] = runCandidate(testCase, lat, lon, [2, 3]);

verifyTrue(testCase, isPass);
verifyEqual(testCase, details.timeDirection, 1);
verifyEqual(testCase, details.closestDirectionStatus, 1);
verifyGreaterThan(testCase, details.closestAlongDisplacementMeters, 0);
verifyLessThan(testCase, details.closestCrossTrackMeters, 1e-6);
verifyEqual(testCase, details.closestSegmentParameter, 0.5, ...
    'AbsTol', 1e-12);
verifyTrue(testCase, all(propSpeed > 0));
verifyLessThanOrEqual(testCase, max(propSpeed), 5);
end

function testPastEventMatchesNegativeClosestDisplacement(testCase)
lat = [20.1, 20.1];
lon = [114.9, 115.1];

[isPass, propSpeed, details] = runCandidate(testCase, lat, lon, [-3, -2]);

verifyTrue(testCase, isPass);
verifyEqual(testCase, details.timeDirection, -1);
verifyEqual(testCase, details.closestDirectionStatus, 1);
verifyLessThan(testCase, details.closestAlongDisplacementMeters, 0);
verifyTrue(testCase, all(propSpeed > 0));
verifyLessThanOrEqual(testCase, max(propSpeed), 5);
end

function testTimeWindowCrossingSensingTimeIsRejected(testCase)
lat = [19.9, 19.9];
lon = [114.9, 115.1];

[isPass, ~, details] = runCandidate(testCase, lat, lon, [-1, 1]);

verifyFalse(testCase, isPass);
verifyEqual(testCase, details.timeDirection, 0);
verifyEqual(testCase, details.reason, "time_window_crosses_sensing_time");
end

function testClosestPointOnCurrentCrestIsAmbiguous(testCase)
lat = [20, 20];
lon = [114.9, 115.1];

[isPass, ~, details] = runCandidate(testCase, lat, lon, [1, 2]);

verifyFalse(testCase, isPass);
verifyEqual(testCase, details.closestDirectionStatus, 0);
verifyEqual(testCase, details.reason, "closest_point_direction_ambiguous");
verifyEqual(testCase, details.closestAlongDisplacementMeters, 0, ...
    'AbsTol', 1e-9);
end

function testMatchingClosestPointCanUseUnchangedSpeedEnvelope(testCase)
% 最近点位于跨零线段，但其他同向线段仍按原规则提供速度包络。
lat = [19.9, 20.1, 19.8, 19.9];
lon = [115.0, 115.1, 115.2, 115.5];

[isPass, propSpeed, details] = runCandidate(testCase, lat, lon, [2, 4]);

verifyTrue(testCase, isPass);
verifyEqual(testCase, details.closestSegment, 1);
verifyEqual(testCase, details.closestDirectionStatus, 1);
verifyTrue(testCase, any(details.ambiguousSegments == 1));
verifyNotEmpty(testCase, details.directionalDisplacementIntervalsMeters);
verifyTrue(testCase, all(propSpeed > 0));
end

function testNearestMismatchOverridesFarMatchingSegment(testCase)
% 第一段位于系泊点南侧，可为未来事件产生正速度；横向最近点位于北侧。
lat = [19.8, 19.8, 20.1, 19.8];
lon = [114.5, 114.9, 115.0, 115.5];

[isPass, ~, details] = runCandidate(testCase, lat, lon, [2, 4]);

verifyFalse(testCase, isPass);
verifyEqual(testCase, details.timeDirection, 1);
verifyEqual(testCase, details.closestDirectionStatus, -1);
verifyLessThan(testCase, details.closestAlongDisplacementMeters, 0);
verifyEqual(testCase, details.reason, ...
    "closest_point_time_direction_mismatch");
verifyNotEmpty(testCase, details.rawSpeedIntervals);
verifyTrue(testCase, any(details.hitSegments == 1));
end

function testSpeedAboveFiveMetersPerSecondIsRejected(testCase)
% 约 11 km 的位移在 0.25–0.5 h 内完成，最低速度仍超过 5 m/s。
lat = [19.9, 19.9];
lon = [114.9, 115.1];

[isPass, propSpeed, details] = runCandidate( ...
    testCase, lat, lon, [0.25, 0.5]);

verifyFalse(testCase, isPass);
verifyTrue(testCase, all(isnan(propSpeed)));
verifyNotEmpty(testCase, details.rawSpeedIntervals);
verifyEmpty(testCase, details.limitedSpeedIntervals);
verifyEqual(testCase, details.reason, "speed_above_5_mps");
end

function testRequiredFlipFailureIsRejected(testCase)
% 初始方向落在 30°–180°，但弯折程度超过 maybeFlipCrestDir 的直线阈值。
lat = [20.1, 20.05, 19.9];
lon = [114.95, 115.0, 115.05];

[isPass, propSpeed, details] = runCandidate(testCase, lat, lon, [1, 2]);

verifyFalse(testCase, isPass);
verifyTrue(testCase, all(isnan(propSpeed)));
verifyTrue(testCase, details.directionFlipRequired);
verifyFalse(testCase, details.directionFlipAccepted);
verifyEqual(testCase, details.reason, ...
    "direction_flip_required_but_rejected");
end

function testProvidedDirectionResolutionIsReused(testCase)
% 主入口解析一次后传入传播函数，最终方向及翻转诊断必须完全一致。
lat = [19.9, 19.9];
lon = [114.9, 115.1];
resolution = resolveCrestDirection(lat, lon, ...
    testCase.TestData.moorLat, testCase.TestData.moorLon);
t0 = testCase.TestData.crestTime;

[isPass, ~, ~, details] = isCrestPassMooring_capsule_dir( ...
    lat, lon, t0, 1, testCase.TestData.moorLat, ...
    testCase.TestData.moorLon, t0+hours(2), t0+hours(3), ...
    60, 10*86400, 100000, resolution);

verifyTrue(testCase, isPass);
verifyEqual(testCase, details.initialDirDeg, resolution.initialDirDeg);
verifyEqual(testCase, details.dirDeg, resolution.dirDeg);
verifyEqual(testCase, details.directionFlipRequired, ...
    resolution.flipRequired);
verifyEqual(testCase, details.directionFlipAccepted, resolution.doFlip);
end

function [isPass, propSpeed, details] = runCandidate(testCase, lat, lon, dtHours)
t0 = testCase.TestData.crestTime;
[isPass, propSpeed, ~, details] = isCrestPassMooring_capsule_dir( ...
    lat, lon, t0, 1, testCase.TestData.moorLat, ...
    testCase.TestData.moorLon, t0+hours(dtHours(1)), ...
    t0+hours(dtHours(2)), 60, 10*86400, 100000);
end
