function test_flow_following_metrics
% Synthetic perfect, random, delayed, and missing-eye metric tests.

frameRate = 60;
n = 300;
t = (0:n-1)'/frameRate;
target = [2*sin(2*pi*0.25*t) 1.5*cos(2*pi*0.25*t)];
flipTimes = t;
options = struct('MinimumValidEyeSamples',60, ...
    'MaximumLongFrameFraction',0.05,'MinimumDurationSeconds',1);

perfect = [t target target ones(n,1)];
perfectMetrics = marmoview.flowFollowingMetrics( ...
    perfect,flipTimes,frameRate,2,options);
assert(perfectMetrics.TrialValid);
assert(perfectMetrics.MedianGazeToFlowCentreDistanceDeg < 1e-10);
assert(perfectMetrics.BestCorrelation > 0.95);

stream = RandStream('mt19937ar','Seed',7);
randomEye = 3*randn(stream,n,2);
randomTrace = [t target randomEye ones(n,1)];
randomMetrics = marmoview.flowFollowingMetrics( ...
    randomTrace,flipTimes,frameRate,2,options);
assert(randomMetrics.MedianGazeToFlowCentreDistanceDeg > ...
    perfectMetrics.MedianGazeToFlowCentreDistanceDeg);
assert(randomMetrics.BestCorrelation < perfectMetrics.BestCorrelation);

delayFrames = 12;
delayedEye = [repmat(target(1,:),delayFrames,1);target(1:end-delayFrames,:)];
delayedTrace = [t target delayedEye ones(n,1)];
delayedMetrics = marmoview.flowFollowingMetrics( ...
    delayedTrace,flipTimes,frameRate,2,options);
assert(delayedMetrics.TrialValid);
assert(abs(delayedMetrics.BestCorrelationLagSeconds) >= ...
    (delayFrames-2)/frameRate);

missing = perfect;
missing(:,4:5) = NaN;
missing(:,6) = 0;
missingMetrics = marmoview.flowFollowingMetrics( ...
    missing,flipTimes,frameRate,2,options);
assert(~missingMetrics.TrialValid);
assert(any(strcmp(missingMetrics.InvalidReasons, ...
    'insufficient valid eye samples')));

fprintf('test_flow_following_metrics: all tests passed.\n');
end
