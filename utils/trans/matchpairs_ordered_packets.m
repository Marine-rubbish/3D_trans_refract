function [matchings, diagnostics] = matchpairs_ordered_packets( ...
    costMatrix, unmatchedCost, packetId, packetRank, eventTimes, solverOptions)
%MATCHPAIRS_ORDERED_PACKETS 在全局一对一分配中约束波包到站顺序。
%
% [matchings, diagnostics] = matchpairs_ordered_packets( ...
%     costMatrix, unmatchedCost, packetId, packetRank, eventTimes)
%
% 输入：
%   costMatrix   - 行是波锋、列是系泊事件，有限值表示候选边。
%   unmatchedCost- 与 matchpairs 相同的单个未匹配代价，仅用于计算
%                  无顺序约束的旧算法基线。
%   packetId     - 每条波锋所属波包；0 表示不施加顺序约束。
%   packetRank   - 波包内从传播前方到后方的序号，1 表示最靠前。
%   eventTimes   - 每个系泊事件的到站时间。
%   solverOptions- 可选的 intlinprog 配置；默认关闭输出并要求零最优间隙。
%
% 输出 matchings 与 matchpairs 一致，每行是 [波锋行号, 事件列号]。
%
% 求解分两阶段进行：
%   1. 最大化匹配数量；
%   2. 固定最大匹配数量，最小化总速度差。
%
% 不预先枚举全部倒序边对。每次求解后只检查当前整数解，把其中
% “前方波锋匹配到更晚事件”的冲突加入 x_a+x_b<=1，再重新求解。
% 当当前最优解不再违反顺序时，它同时也是完整约束模型的全局最优解。

if nargin < 6
    solverOptions = [];
end

[crestCount, eventCount] = size(costMatrix);
validateInputs(costMatrix, unmatchedCost, packetId, packetRank, ...
    eventTimes, crestCount, eventCount);

packetId = packetId(:);
packetRank = packetRank(:);
timeOrder = normalizeEventTimes(eventTimes);

% 严格沿用现有候选矩阵：每一个有限速度差都是可选边，Inf 表示禁边。
candidateMask = isfinite(costMatrix);
[edgeCrest, edgeEvent] = find(candidateMask);
edgeCost = costMatrix(candidateMask);
edgeCount = numel(edgeCost);

baseline = matchpairs(costMatrix, unmatchedCost);

if edgeCount == 0
    matchings = zeros(0, 2);
    diagnostics = makeDiagnostics(costMatrix, baseline, ...
        matchings, 0, 0, 0, 0, 0, 0, packetId);
    return;
end

if exist('intlinprog', 'file') ~= 2
    error('matchpairs_ordered_packets:MissingOptimizationToolbox', ...
        ['全局有序分配需要 Optimization Toolbox 的 intlinprog。', ...
         '当前 MATLAB 未安装该求解器，未降级为近似贪心结果。']);
end

if isempty(solverOptions)
    % 两阶段都要求证明全局最优；不能用默认相对间隙提前接受近似解。
    solverOptions = optimoptions('intlinprog', ...
        'Display', 'off', ...
        'RelativeGapTolerance', 0, ...
        'AbsoluteGapTolerance', 0);
end

edgeIndex = (1:edgeCount)';
assignmentRows = [edgeCrest; crestCount + edgeEvent];
assignmentCols = [edgeIndex; edgeIndex];
assignmentA = sparse(assignmentRows, assignmentCols, 1, ...
    crestCount + eventCount, edgeCount);
assignmentB = ones(crestCount + eventCount, 1);

integerVariables = edgeIndex;
lowerBound = zeros(edgeCount, 1);
upperBound = ones(edgeCount, 1);
orderCuts = zeros(0, 2);

% 第一阶段只优化基数。负号把“最大化选中边数”转换为 intlinprog
% 接受的最小化目标。
[stage1X, orderCuts, stage1SolveCount, stage1ExitFlag] = ...
    solveWithLazyOrderCuts(-ones(edgeCount, 1), ...
    assignmentA, assignmentB, [], [], integerVariables, ...
    lowerBound, upperBound, solverOptions, edgeCrest, edgeEvent, ...
    packetId, packetRank, timeOrder, orderCuts, "最大匹配数");
maximumMatchCount = nnz(stage1X > 0.5);

% 第二阶段用等式固定最大匹配数量，只在这些解中比较速度差。
cardinalityA = sparse(1, 1:edgeCount, 1, 1, edgeCount);
[stage2X, orderCuts, stage2SolveCount, stage2ExitFlag] = ...
    solveWithLazyOrderCuts(edgeCost, assignmentA, assignmentB, ...
    cardinalityA, maximumMatchCount, integerVariables, ...
    lowerBound, upperBound, solverOptions, edgeCrest, edgeEvent, ...
    packetId, packetRank, timeOrder, orderCuts, "最小总速度差");

selectedEdges = find(stage2X > 0.5);
matchings = sortrows([edgeCrest(selectedEdges), edgeEvent(selectedEdges)], ...
    [1, 2]);

remainingInversions = findSelectedInversions(selectedEdges, ...
    edgeCrest, edgeEvent, packetId, packetRank, timeOrder);
if ~isempty(remainingInversions)
    error('matchpairs_ordered_packets:InternalOrderViolation', ...
        '求解结束后仍检测到 %d 个包内倒序约束。', ...
        size(remainingInversions, 1));
end

diagnostics = makeDiagnostics(costMatrix, baseline, ...
    matchings, sum(edgeCost(selectedEdges)), size(orderCuts, 1), ...
    stage1SolveCount, stage2SolveCount, stage1ExitFlag, ...
    stage2ExitFlag, packetId);
end

function validateInputs(costMatrix, unmatchedCost, packetId, packetRank, ...
    eventTimes, crestCount, eventCount)
%VALIDATEINPUTS 在建模前拒绝会让顺序含义不明确的输入。
if ~isnumeric(costMatrix) || ~isfloat(costMatrix) || ...
        ~isreal(costMatrix) || ~ismatrix(costMatrix) || ...
        any(isnan(costMatrix), 'all')
    error('matchpairs_ordered_packets:InvalidCostMatrix', ...
        'costMatrix 必须是允许 Inf、但不允许 NaN 的实数浮点矩阵。');
end
if ~isnumeric(unmatchedCost) || ~isscalar(unmatchedCost) || ...
        ~isreal(unmatchedCost) || ~isfinite(unmatchedCost) || ...
        unmatchedCost <= 0
    error('matchpairs_ordered_packets:InvalidUnmatchedCost', ...
        'unmatchedCost 必须是有限正数。');
end
if ~isnumeric(packetId) || ~isvector(packetId) || ...
        numel(packetId) ~= crestCount || ...
        any(~isfinite(packetId)) || any(packetId < 0) || ...
        any(packetId ~= fix(packetId))
    error('matchpairs_ordered_packets:InvalidPacketId', ...
        'packetId 必须与波锋行数一致，且为非负整数。');
end
if ~isnumeric(packetRank) || ~isvector(packetRank) || ...
        numel(packetRank) ~= crestCount
    error('matchpairs_ordered_packets:InvalidPacketRank', ...
        'packetRank 必须是与波锋行数一致的数值向量。');
end

packetId = packetId(:);
packetRank = packetRank(:);
grouped = packetId > 0;
if any(~isfinite(packetRank(grouped))) || ...
        any(packetRank(grouped) < 1) || ...
        any(packetRank(grouped) ~= fix(packetRank(grouped)))
    error('matchpairs_ordered_packets:InvalidPacketRank', ...
        '已归包波锋必须具有有限正整数 packetRank。');
end

ids = unique(packetId(grouped));
for i = 1:numel(ids)
    ranks = packetRank(packetId == ids(i));
    if numel(unique(ranks)) ~= numel(ranks)
        error('matchpairs_ordered_packets:DuplicatePacketRank', ...
            '波包 %d 内存在重复 packetRank。', ids(i));
    end
end

if ~(isdatetime(eventTimes) || isnumeric(eventTimes)) || ...
        ~isvector(eventTimes) || numel(eventTimes) ~= eventCount
    error('matchpairs_ordered_packets:InvalidEventTimes', ...
        'eventTimes 必须与事件列数一致，且为 datetime 或数值向量。');
end
if isdatetime(eventTimes)
    if any(isnat(eventTimes))
        error('matchpairs_ordered_packets:InvalidEventTimes', ...
            'eventTimes 不能包含 NaT。');
    end
elseif ~isreal(eventTimes) || any(~isfinite(eventTimes))
    error('matchpairs_ordered_packets:InvalidEventTimes', ...
        '数值 eventTimes 必须为有限实数。');
end
end

function timeOrder = normalizeEventTimes(eventTimes)
%NORMALIZEEVENTTIMES 只保留时间先后关系，避免时区或绝对纪元影响模型。
eventTimes = eventTimes(:);
if isdatetime(eventTimes)
    timeOrder = seconds(eventTimes - min(eventTimes));
else
    timeOrder = double(eventTimes);
end
end

function [solution, orderCuts, solveCount, exitFlag] = ...
    solveWithLazyOrderCuts(objective, assignmentA, assignmentB, ...
    equalityA, equalityB, integerVariables, lowerBound, upperBound, ...
    solverOptions, edgeCrest, edgeEvent, packetId, packetRank, ...
    timeOrder, orderCuts, stageName)
%SOLVEWITHLAZYORDERCUTS 反复加入当前整数解真正违反的倒序约束。
edgeCount = numel(objective);
solveCount = 0;

while true
    orderA = makeOrderCutMatrix(orderCuts, edgeCount);
    inequalityA = [assignmentA; orderA];
    inequalityB = [assignmentB; ones(size(orderCuts, 1), 1)];

    [solution, ~, exitFlag] = intlinprog(objective, ...
        integerVariables, inequalityA, inequalityB, equalityA, ...
        equalityB, lowerBound, upperBound, solverOptions);
    solveCount = solveCount + 1;

    if exitFlag <= 0 || isempty(solution)
        error('matchpairs_ordered_packets:SolverFailed', ...
            'intlinprog 在“%s”阶段未证明最优，exitflag=%d。', ...
            stageName, exitFlag);
    end
    if any(abs(solution - round(solution)) > 1e-6)
        error('matchpairs_ordered_packets:NonIntegerSolution', ...
            'intlinprog 在“%s”阶段返回了非整数解。', stageName);
    end

    selectedEdges = find(solution > 0.5);
    violations = findSelectedInversions(selectedEdges, edgeCrest, ...
        edgeEvent, packetId, packetRank, timeOrder);
    if isempty(violations)
        return;
    end

    newCuts = setdiff(violations, orderCuts, 'rows', 'stable');
    if isempty(newCuts)
        error('matchpairs_ordered_packets:RepeatedOrderViolation', ...
            '“%s”阶段重复违反已经加入的倒序约束。', stageName);
    end
    orderCuts = unique([orderCuts; newCuts], 'rows', 'stable');
end
end

function orderA = makeOrderCutMatrix(orderCuts, edgeCount)
%MAKEORDERCUTMATRIX 每一行表示两个倒序候选边不能同时取 1。
cutCount = size(orderCuts, 1);
if cutCount == 0
    orderA = sparse(0, edgeCount);
    return;
end
rows = repelem((1:cutCount)', 2, 1);
cols = reshape(orderCuts.', [], 1);
orderA = sparse(rows, cols, 1, cutCount, edgeCount);
end

function violations = findSelectedInversions(selectedEdges, ...
    edgeCrest, edgeEvent, packetId, packetRank, timeOrder)
%FINDSELECTEDINVERSIONS 找出当前解中空间顺序与到站时间相反的边对。
violations = zeros(0, 2);
if numel(selectedEdges) < 2
    return;
end

selectedPackets = packetId(edgeCrest(selectedEdges));
ids = unique(selectedPackets(selectedPackets > 0));
for i = 1:numel(ids)
    packetEdges = selectedEdges(selectedPackets == ids(i));
    if numel(packetEdges) < 2
        continue;
    end

    ranks = packetRank(edgeCrest(packetEdges));
    [~, rankOrder] = sort(ranks);
    packetEdges = packetEdges(rankOrder);
    arrivalOrder = timeOrder(edgeEvent(packetEdges));

    for earlier = 1:numel(packetEdges)-1
        for later = earlier+1:numel(packetEdges)
            if arrivalOrder(earlier) > arrivalOrder(later)
                pair = sort([packetEdges(earlier), packetEdges(later)]);
                violations(end+1, :) = pair; %#ok<AGROW>
            end
        end
    end
end

if ~isempty(violations)
    violations = unique(violations, 'rows', 'stable');
end
end

function diagnostics = makeDiagnostics(costMatrix, baseline, matchings, ...
    totalCost, orderCutCount, stage1SolveCount, ...
    stage2SolveCount, stage1ExitFlag, stage2ExitFlag, packetId)
%MAKEDIAGNOSTICS 汇总可复核、不会随求解日志格式变化的确定性指标。
[crestCount, eventCount] = size(costMatrix);
candidateMask = isfinite(costMatrix);

baselineByEvent = zeros(eventCount, 1);
baselineByCrest = zeros(crestCount, 1);
if ~isempty(baseline)
    baselineByEvent(baseline(:, 2)) = baseline(:, 1);
    baselineByCrest(baseline(:, 1)) = baseline(:, 2);
end

orderedByEvent = zeros(eventCount, 1);
orderedByCrest = zeros(crestCount, 1);
if ~isempty(matchings)
    orderedByEvent(matchings(:, 2)) = matchings(:, 1);
    orderedByCrest(matchings(:, 1)) = matchings(:, 2);
end

baselineCost = 0;
if ~isempty(baseline)
    baselineLinear = sub2ind(size(costMatrix), ...
        baseline(:, 1), baseline(:, 2));
    baselineCost = sum(costMatrix(baselineLinear));
end

diagnostics = struct();
diagnostics.solver = "intlinprog_lazy_order_cuts";
diagnostics.candidate_edge_count = nnz(candidateMask);
diagnostics.constrained_packet_count = ...
    numel(unique(packetId(packetId > 0)));
diagnostics.baseline_match_count = size(baseline, 1);
diagnostics.match_count = size(matchings, 1);
diagnostics.changed_event_assignment_count = ...
    nnz(baselineByEvent ~= orderedByEvent);
diagnostics.changed_crest_assignment_count = ...
    nnz(baselineByCrest ~= orderedByCrest);
diagnostics.unmatched_crest_count = crestCount - size(matchings, 1);
diagnostics.unmatched_event_count = eventCount - size(matchings, 1);
diagnostics.baseline_total_cost = baselineCost;
diagnostics.total_cost = totalCost;
diagnostics.order_cut_count = orderCutCount;
diagnostics.stage1_solve_count = stage1SolveCount;
diagnostics.stage2_solve_count = stage2SolveCount;
diagnostics.stage1_exitflag = stage1ExitFlag;
diagnostics.stage2_exitflag = stage2ExitFlag;
diagnostics.remaining_inversion_count = 0;
end
