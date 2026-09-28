function test_analyze_marmoset_cone_phenotype_flow
% Synthetic blinded-response test for initial six-hypothesis analysis.

taskRoot = fileparts(fileparts(mfilename('fullpath')));
analysisPath = fullfile(taskRoot,'Analysis');
addpath(analysisPath);
cleanup = onCleanup(@() rmpath(analysisPath));
fixture = make_synthetic_marmoset_calibration;
bank = marmoview.marmosetPhenotypeConditionBank(fixture,struct( ...
    'ExpectedMonitorIdentifier','SYNTHETIC_TEST_MONITOR', ...
    'ContrastLevels',1));

stream = RandStream('mt19937ar','Seed',21);
D = cell(50,1);
cursor = 0;
for conditionIndex = 1:numel(bank.Conditions)
    condition = bank.Conditions(conditionIndex);
    if strcmp(condition.ConditionID,'null543_scale_1') || ...
            strcmp(condition.ConditionID,'catch')
        expectedResponse = 0.05;
    else
        expectedResponse = 0.8;
    end
    for repeat = 1:10
        cursor = cursor+1;
        pr = struct();
        pr.conditionID = condition.ConditionID;
        pr.conditionType = condition.ConditionType;
        pr.nullPeakNm = condition.NullPeakNm;
        pr.trialValid = true;
        pr.meanEyeVelocityProjectionTowardCentre = ...
            expectedResponse+0.03*randn(stream);
        pr.medianGazeToFlowCentreDistanceDeg = 1-0.5*expectedResponse;
        pr.responseLatencySeconds = 1-0.5*expectedResponse;
        pr.validEyeSampleCount = 100;
        pr.fractionInsideCentreWindow = expectedResponse;
        pr.Traces = zeros(100,6);
        pr.realizedCandidateConeContrast = condition.RealizedConeContrast;
        D{cursor} = struct('PR',pr);
    end
end
D = D(1:cursor);
D{1}.PR.trialValid = false;

result = analyzeMarmosetConePhenotypeFlow(D,struct( ...
    'BootstrapIterations',100,'RandomSeed',11, ...
    'MinimumValidTrials',20,'MinimumClassificationConfidence',0.5));
assert(result.ValidTrialCount == numel(D)-1);
assert(contains(result.RuleBasedInterpretation,'543 dichromat'));
assert(strcmp(result.PhenotypeModel.BestPhenotype,'D_543'));
assert(~strcmp(result.Classification,'unclassified'));

clear cleanup
fprintf('test_analyze_marmoset_cone_phenotype_flow: all tests passed.\n');
end
