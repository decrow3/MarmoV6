function test_marmoset_pigment_null
% TEST_MARMOSET_PIGMENT_NULL No-display tests for candidate-pigment axes.

fixture = make_synthetic_marmoset_calibration;
loaded = marmoview.loadCandidateConeCalibration(fixture,struct( ...
    'ExpectedMonitorIdentifier','SYNTHETIC_TEST_MONITOR'));
assert(isequal(loaded.CandidateConePeaksNm,[563 556 543 423]));

for peak = [543 556 563]
    condition = marmoview.marmosetPigmentNull(fixture,peak,1,struct( ...
        'ExpectedMonitorIdentifier','SYNTHETIC_TEST_MONITOR', ...
        'SilentLeakageTolerance',0.005));
    silent = condition.SilentConeIndices;
    assert(max(abs(condition.RequestedConeContrast(:,silent)),[],'all') < 1e-10);
    assert(max(abs(condition.RealizedConeContrast(:,silent)),[],'all') < 0.005);
    assert(all(condition.NegativeLinearRGB >= 0 & condition.NegativeLinearRGB <= 1));
    assert(all(condition.PositiveLinearRGB >= 0 & condition.PositiveLinearRGB <= 1));
    assert(max(abs((condition.NegativeLinearRGB + ...
        condition.PositiveLinearRGB)/2-condition.BackgroundLinearRGB)) < 1e-12);
    modulated = setdiff(1:3,find(condition.ConePeaksNm == peak));
    assert(any(abs(condition.RequestedConeContrast(2,modulated)) > 0.01));
    longest = modulated(condition.ConePeaksNm(modulated) == ...
        max(condition.ConePeaksNm(modulated)));
    assert(condition.RequestedConeContrast(2,longest(1)) > 0);
    assert(condition.ValidationPass);
end

bank = marmoview.marmosetPhenotypeConditionBank(fixture,struct( ...
    'ExpectedMonitorIdentifier','SYNTHETIC_TEST_MONITOR', ...
    'ContrastLevels',1,'AchromaticContrast',0.2));
assert(numel(bank.Conditions) == 5);
ids = {bank.Conditions.ConditionID};
assert(all(ismember({'null543_scale_1','null556_scale_1', ...
    'null563_scale_1','achromatic','catch'},ids)));
catchCondition = bank.Conditions(strcmp(ids,'catch'));
assert(isequal(catchCondition.NegativeDeviceCodes, ...
    catchCondition.BackgroundDeviceCodes));
assert(isequal(catchCondition.PositiveDeviceCodes, ...
    catchCondition.BackgroundDeviceCodes));

assertThrows(@() marmoview.marmosetPigmentNull(fixture,530,1), ...
    'marmosetPigmentNull:NullPeak');
wrongOrder = fixture;
wrongOrder.CandidateConePeaksNm = [543 556 563 423];
assertThrows(@() marmoview.loadCandidateConeCalibration(wrongOrder), ...
    'loadCandidateConeCalibration:ConeOrder');
dummy = fixture;
dummy.IsDummyCalibration = true;
assertThrows(@() marmoview.loadCandidateConeCalibration(dummy), ...
    'loadCandidateConeCalibration:DummyCalibration');
assertThrows(@() marmoview.loadCandidateConeCalibration(fixture,struct( ...
    'ExpectedMonitorIdentifier','WRONG_MONITOR')), ...
    'loadCandidateConeCalibration:MonitorMismatch');
humanOnly = struct('ConePeaks',[558 530 420], ...
    'RGB_to_Cones',eye(3),'BackgroundRGB',[0.5 0.5 0.5]);
assertThrows(@() marmoview.marmosetPhenotypeConditionBank(humanOnly), ...
    'loadCandidateConeCalibration:MissingMetadata');

fprintf('test_marmoset_pigment_null: all tests passed.\n');
end


function assertThrows(callable,identifier)
threw = false;
try
    callable();
catch exception
    threw = strcmp(exception.identifier,identifier);
end
assert(threw,'Expected error %s.',identifier);
end
