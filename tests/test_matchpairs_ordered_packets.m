function tests = test_matchpairs_ordered_packets
%TEST_MATCHPAIRS_ORDERED_PACKETS 验证全局一对一、波包顺序和缺口行为。
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(projectRoot, 'utils')));
assumeTrue(testCase, exist('intlinprog', 'file') == 2, ...
    '测试需要 Optimization Toolbox 的 intlinprog。');
end

function testGlobalReassignmentReleasesOccupiedEvents(testCase)
% 无顺序约束时，最低代价解为 1->2、2->1、3->3，前两条发生倒序。
% 有序解必须同时重排第三条未归包波锋，不能冻结原来的事件归属。
cost = Inf(3, 3);
cost(1, 2) = 0;
cost(1, 1) = 2;
cost(2, 1) = 0;
cost(2, 3) = 2;
cost(3, 3) = 0;
cost(3, 2) = 2;
packetId = [7; 7; 0];
packetRank = [1; 2; NaN];
eventTimes = datetime(2020, 1, 1) + hours(1:3);

[matching, diagnostics] = matchpairs_ordered_packets( ...
    cost, 100, packetId, packetRank, eventTimes);

verifyEqual(testCase, matching, [1, 1; 2, 3; 3, 2]);
verifyEqual(testCase, diagnostics.match_count, 3);
verifyEqual(testCase, diagnostics.changed_event_assignment_count, 3);
verifyGreaterThan(testCase, diagnostics.order_cut_count, 0);
verifyOneToOneAndOrdered(testCase, matching, packetId, ...
    packetRank, eventTimes);
end

function testAlreadyOrderedMatchesAreRetained(testCase)
cost = Inf(3, 3);
cost(1, 1) = 0.1;
cost(2, 2) = 0.2;
cost(3, 3) = 0.3;
packetId = [11; 11; 11];
packetRank = [1; 2; 3];
eventTimes = [10; 20; 30];

[matching, diagnostics] = matchpairs_ordered_packets( ...
    cost, 100, packetId, packetRank, eventTimes);

verifyEqual(testCase, matching, [1, 1; 2, 2; 3, 3]);
verifyEqual(testCase, diagnostics.changed_event_assignment_count, 0);
verifyOneToOneAndOrdered(testCase, matching, packetId, ...
    packetRank, eventTimes);
end

function testMissingCrestsAndEventsAreAllowed(testCase)
% 波包第 2 条波锋没有候选，事件 2 和 4 也没有被使用；其余顺序仍合法。
cost = Inf(4, 5);
cost(1, 1) = 0.1;
cost(3, 3) = 0.1;
cost(4, 5) = 0.1;
packetId = [21; 21; 21; 21];
packetRank = [1; 2; 3; 4];
eventTimes = [1; 2; 3; 4; 5];

[matching, diagnostics] = matchpairs_ordered_packets( ...
    cost, 100, packetId, packetRank, eventTimes);

verifyEqual(testCase, matching, [1, 1; 3, 3; 4, 5]);
verifyEqual(testCase, diagnostics.match_count, 3);
verifyEqual(testCase, diagnostics.unmatched_crest_count, 1);
verifyEqual(testCase, diagnostics.unmatched_event_count, 2);
verifyOneToOneAndOrdered(testCase, matching, packetId, ...
    packetRank, eventTimes);
end

function testUngroupedCrestsAreNotOrderConstrained(testCase)
% 两条未归包波锋可以采用交叉时间顺序，求解器不替它们虚构波序。
cost = [2, 0; 0, 2];
packetId = [0; 0];
packetRank = [NaN; NaN];
eventTimes = [1; 2];

[matching, diagnostics] = matchpairs_ordered_packets( ...
    cost, 100, packetId, packetRank, eventTimes);

verifyEqual(testCase, matching, [1, 2; 2, 1]);
verifyEqual(testCase, diagnostics.order_cut_count, 0);
verifyOneToOneAndOrdered(testCase, matching, packetId, ...
    packetRank, eventTimes);
end

function testCardinalityIsOptimizedBeforeCost(testCase)
% 单取 1->2 的代价最低，但两阶段目标必须先保留两条可行匹配。
cost = Inf(2, 2);
cost(1, 1) = 9;
cost(1, 2) = 0;
cost(2, 2) = 9;
packetId = [31; 31];
packetRank = [1; 2];
eventTimes = [1; 2];

[matching, diagnostics] = matchpairs_ordered_packets( ...
    cost, 100, packetId, packetRank, eventTimes);

verifyEqual(testCase, matching, [1, 1; 2, 2]);
verifyEqual(testCase, diagnostics.match_count, 2);
verifyEqual(testCase, diagnostics.total_cost, 18, 'AbsTol', 1e-12);
verifyOneToOneAndOrdered(testCase, matching, packetId, ...
    packetRank, eventTimes);
end

function verifyOneToOneAndOrdered(testCase, matching, packetId, ...
    packetRank, eventTimes)
%VERIFYONETOONEANDORDERED 对每个合成结果复查一对一和包内时间单调性。
verifyEqual(testCase, numel(unique(matching(:, 1))), size(matching, 1));
verifyEqual(testCase, numel(unique(matching(:, 2))), size(matching, 1));

matchedPackets = packetId(matching(:, 1));
ids = unique(matchedPackets(matchedPackets > 0));
for i = 1:numel(ids)
    rows = find(matchedPackets == ids(i));
    [~, order] = sort(packetRank(matching(rows, 1)));
    orderedEvents = matching(rows(order), 2);
    arrivals = eventTimes(orderedEvents);
    if isdatetime(arrivals)
        differences = seconds(diff(arrivals));
    else
        differences = diff(arrivals);
    end
    verifyTrue(testCase, all(differences >= 0));
end
end
