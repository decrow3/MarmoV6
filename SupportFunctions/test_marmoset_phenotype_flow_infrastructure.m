function test_marmoset_phenotype_flow_infrastructure
% No-display tests for trajectories, balancing, persistence, and randomization.

fixture = make_synthetic_marmoset_calibration;
bank = marmoview.marmosetPhenotypeConditionBank(fixture,struct( ...
    'ExpectedMonitorIdentifier','SYNTHETIC_TEST_MONITOR', ...
    'ContrastLevels',[0.25 0.5 1], ...
    'AchromaticContrast',0.2));

trajectoryOptions = struct('FrameRate',60,'StimulusDuration',2, ...
    'TrajectoryCount',3,'RandomSeed',42,'SpeedDegPerSecond',5, ...
    'MaximumEccentricityDeg',3,'FilterTimeConstantSeconds',0.25);
trajectoriesA = marmoview.makeMarmosetFlowTrajectoryBank(trajectoryOptions);
trajectoriesB = marmoview.makeMarmosetFlowTrajectoryBank(trajectoryOptions);
assert(isequal(trajectoriesA.XDeg,trajectoriesB.XDeg));
assert(isequal(trajectoriesA.YDeg,trajectoriesB.YDeg));
assert(max(hypot(trajectoriesA.XDeg,trajectoriesA.YDeg),[],'all') <= 3+1e-12);

planOptions = struct('RepeatsPerCondition',12,'TrajectoryCount',3, ...
    'RandomSeed',99,'RewardAmount',2,'CatchTrialFraction',0.1);
planA = marmoview.makeMarmosetPhenotypeTrialPlan(bank,planOptions);
planB = marmoview.makeMarmosetPhenotypeTrialPlan(bank,planOptions);
assert(isequal(planA.Rows,planB.Rows));

ids = {bank.Conditions.ConditionID};
catchIndex = find(strcmp(ids,'catch'));
diagnosticIndices = find(startsWith(ids,'null'));
for conditionIndex = diagnosticIndices
    selected = planA.Rows(:,1) == conditionIndex;
    assert(nnz(selected) == 12);
    counts = accumarray(planA.Rows(selected,3),1,[3 1]);
    assert(isequal(counts,[4;4;4]));
end
assert(any(planA.Rows(:,1) == catchIndex));
conditionSequence = planA.Rows(:,1);
assert(~any(conditionSequence(1:end-2) == conditionSequence(2:end-1) & ...
    conditionSequence(2:end-1) == conditionSequence(3:end)));

stimulus = stimuli.opticflow(0);
stimulus.position = [50 50];
stimulus.screenRect = [0 0 100 100];
stimulus.Xbot = 0;
stimulus.Xtop = 100;
stimulus.Ytop = 0;
stimulus.Ybot = 100;
stimulus.maxRadius = inf;
stimulus.centerDecay = false;
stimulus.balancedDots = true;
stimulus.polarityColours = [40 210;70 190;100 170];
stimulus.neutralColour = [125;125;125];
stimulus.nDots = 100;
stimulus.beforeTrial();
assert(nnz(stimulus.dotPolarity < 0) == 50);
assert(nnz(stimulus.dotPolarity > 0) == 50);
assert(nnz(stimulus.dotPolarity == 0) == 0);
stimulus.nDots = 101;
stimulus.beforeTrial();
assert(nnz(stimulus.dotPolarity < 0) == 50);
assert(nnz(stimulus.dotPolarity > 0) == 50);
assert(nnz(stimulus.dotPolarity == 0) == 1);

saved = struct('ConditionBank',bank,'TrajectoryBank',trajectoriesA, ...
    'TrialPlan',planA);
filename = [tempname '.mat'];
cleanup = onCleanup(@() deleteIfPresent(filename));
save(filename,'saved');
reloaded = load(filename,'saved');
assert(isequaln(saved,reloaded.saved));
clear cleanup

fprintf('test_marmoset_phenotype_flow_infrastructure: all tests passed.\n');
end


function deleteIfPresent(filename)
if exist(filename,'file')
    delete(filename);
end
end
