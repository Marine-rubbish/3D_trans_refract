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
verifyFalse(testCase, details.directOverlap);
verifyGreaterThan(testCase, details.geometricDistanceMeters, ...
    details.directOverlapRadiusMeters);
verifyEqual(testCase, details.reason, "time_window_crosses_sensing_time");
end

function testTimeWindowCrossingNearCrestIsDirectMatch(testCase)
% 成像时波锋实际线距约 2.2 km，直接观测重合应覆盖跨时刻拒绝。
lat = [19.98, 19.98];
lon = [114.9, 115.1];

[isPass, propSpeed, details] = runCandidate( ...
    testCase, lat, lon, [-1, 1]);

verifyTrue(testCase, isPass);
verifyEqual(testCase, propSpeed, [0, 5], 'AbsTol', 1e-12);
verifyEqual(testCase, details.timeDirection, 0);
verifyEqual(testCase, details.closestDirectionStatus, 0);
verifyTrue(testCase, details.eventContainsSensingTime);
verifyTrue(testCase, details.directOverlap);
verifyLessThan(testCase, details.geometricDistanceMeters, ...
    details.directOverlapRadiusMeters);
verifyTrue(testCase, isfinite(details.closestSegment));
verifyTrue(testCase, isfinite(details.closestSegmentParameter));
verifyEqual(testCase, details.reason, ...
    "direct_spatiotemporal_overlap");
end

function testNearCrestOutsideEventUsesPropagationRule(testCase)
% 线距小于 5 km 不能单独触发直接匹配，事件还必须覆盖遥感时刻。
lat = [19.98, 19.98];
lon = [114.9, 115.1];

[isPass, propSpeed, details] = runCandidate( ...
    testCase, lat, lon, [2, 3]);

verifyTrue(testCase, isPass);
verifyTrue(testCase, all(propSpeed > 0));
verifyFalse(testCase, details.eventContainsSensingTime);
verifyFalse(testCase, details.directOverlap);
verifyEqual(testCase, details.reason, "pass");
end

function testDirectOverlapRadiusIsIndependent(testCase)
% 同一条近站波锋在阈值收紧到 1 km 后，不得继续直接通过。
lat = [19.98, 19.98];
lon = [114.9, 115.1];
t0 = testCase.TestData.crestTime;

[isPass, ~, ~, details] = isCrestPassMooring_capsule_dir( ...
    lat, lon, t0, 1, testCase.TestData.moorLat, ...
    testCase.TestData.moorLon, t0-hours(1), t0+hours(1), ...
    60, 10*86400, 100000, [], 1000);

verifyFalse(testCase, isPass);
verifyFalse(testCase, details.directOverlap);
verifyEqual(testCase, details.directOverlapRadiusMeters, 1000);
verifyGreaterThan(testCase, details.geometricDistanceMeters, 1000);
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

function testReturnedSpeedEnvelopeUsesClosestPointOnly(testCase)
% 两条横向可对准站点的波段距离不同；远端波段不得扩大返回速度区间。
lat = [19.95, 19.95, 19.7, 19.7];
lon = [114.9, 115.1, 115.1, 114.9];
directionResolution = resolveCrestDirection( ...
    [19.95, 19.95], [114.9, 115.1], ...
    testCase.TestData.moorLat, testCase.TestData.moorLon);
t0 = testCase.TestData.crestTime;

[isPass, propSpeed, ~, details] = isCrestPassMooring_capsule_dir( ...
    lat, lon, t0, 1, testCase.TestData.moorLat, ...
    testCase.TestData.moorLon, t0+hours(2), t0+hours(4), ...
    60, 10*86400, 100000, directionResolution);

verifyTrue(testCase, isPass);
verifyEqual(testCase, details.closestSegment, 1);
verifyEqual(testCase, details.closestDirectionStatus, 1);
verifyEqual(testCase, propSpeed, [ ...
    min(details.closestLimitedSpeedIntervals(:,1)), ...
    max(details.closestLimitedSpeedIntervals(:,2))], ...
    'AbsTol', 1e-12);
verifyGreaterThan(testCase, max(details.limitedSpeedIntervals(:,2)), ...
    max(propSpeed));
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
verifyEmpty(testCase, details.closestLimitedSpeedIntervals);
verifyEqual(testCase, details.reason, "speed_above_5_mps");
end

function testInitialDirectionBelowThresholdIsRejected(testCase)
% 初始方向约 36.9°，必须在传播计算前直接拒配。
lat = [20.15, 20.075, 20.0];
lon = [114.9, 115.0, 115.1];

resolution = resolveCrestDirection(lat, lon, ...
    testCase.TestData.moorLat, testCase.TestData.moorLon);

verifyFalse(testCase, resolution.isValid);
verifyGreaterThan(testCase, resolution.initialDirDeg, 0);
verifyLessThanOrEqual(testCase, resolution.initialDirDeg, 45);
verifyFalse(testCase, resolution.flipRequired);
verifyEqual(testCase, resolution.reason, ...
    "initial_direction_below_flip_threshold");
end

function testRequiredFlipFailureIsRejected(testCase)
% 初始方向落在 45°–180°，但弯折程度超过 maybeFlipCrestDir 的直线阈值。
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
