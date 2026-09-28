function metrics = flowFollowingMetrics(traces,flipTimes,frameRate,windowRadius,options)
% FLOWFOLLOWINGMETRICS Compute saved pursuit/convergence metrics and validity.

if nargin < 5 || isempty(options)
    options = struct();
end
options = setDefault(options,'DiscardInitialSeconds',0.25);
options = setDefault(options,'MaximumLagSeconds',1);
options = setDefault(options,'MinimumValidEyeSamples',round(frameRate));
options = setDefault(options,'MaximumLongFrameFraction',0.05);
options = setDefault(options,'MinimumDurationSeconds',1);
options = setDefault(options,'CalibrationStable',true);

traces = double(traces);
if size(traces,2) < 6
    error('flowFollowingMetrics:TraceShape', ...
        'traces must contain time, target XY, eye XY, and validity columns.');
end
valid = traces(:,6) == 1 & all(isfinite(traces(:,2:5)),2);
discard = min(size(traces,1),round(options.DiscardInitialSeconds*frameRate));
valid(1:discard) = false;
target = traces(valid,2:3);
eye = traces(valid,4:5);
distance = hypot(target(:,1)-eye(:,1),target(:,2)-eye(:,2));

metrics = struct();
metrics.EyeValidityFlags = valid;
metrics.ValidEyeSampleCount = nnz(valid);
metrics.MedianGazeToFlowCentreDistanceDeg = median(distance,'omitnan');
metrics.FractionInsideCentreWindow = mean(distance <= windowRadius,'omitnan');
metrics.ResponseLatencySeconds = NaN;
inside = find(distance <= windowRadius,1,'first');
if ~isempty(inside)
    metrics.ResponseLatencySeconds = (inside-1)/frameRate;
end
baseline = min(numel(distance),max(1,round(0.25*frameRate)));
if numel(distance) > baseline
    metrics.PrePostDistanceChangeDeg = ...
        median(distance(baseline+1:end),'omitnan') - ...
        median(distance(1:baseline),'omitnan');
else
    metrics.PrePostDistanceChangeDeg = NaN;
end

metrics.MeanEyeVelocityProjectionTowardCentre = NaN;
metrics.EyeCentreCrossCorrelation = nan(1,2*round(options.MaximumLagSeconds*frameRate)+1);
metrics.BestCorrelation = NaN;
metrics.BestCorrelationLagSeconds = NaN;
if size(target,1) >= 4
    smoothFrames = max(1,round(0.1*frameRate));
    targetVelocity = diff(movmean(target,smoothFrames,1),1,1);
    eyeVelocity = diff(movmean(eye,smoothFrames,1),1,1);
    denominator = hypot(eyeVelocity(:,1),eyeVelocity(:,2)).* ...
        hypot(targetVelocity(:,1),targetVelocity(:,2));
    projection = sum(eyeVelocity.*targetVelocity,2)./denominator;
    metrics.MeanEyeVelocityProjectionTowardCentre = mean(projection,'omitnan');
    maximumLag = round(options.MaximumLagSeconds*frameRate);
    correlations = vectorCorrelation(eyeVelocity,targetVelocity,maximumLag);
    metrics.EyeCentreCrossCorrelation = correlations;
    if any(isfinite(correlations))
        [metrics.BestCorrelation,index] = max(correlations,[],'omitnan');
        metrics.BestCorrelationLagSeconds = (index-(maximumLag+1))/frameRate;
    end
end

flipTimes = double(flipTimes(:));
intervals = diff(flipTimes);
intervals = intervals(isfinite(intervals) & intervals > 0);
expectedInterval = 1/frameRate;
metrics.LongFrameCount = nnz(intervals > 1.5*expectedInterval);
metrics.LongFrameFraction = metrics.LongFrameCount/max(1,numel(intervals));
metrics.MeanFrameIntervalMs = 1000*mean(intervals,'omitnan');
metrics.MaxFrameIntervalMs = 1000*max(intervals,[],'omitnan');
metrics.ObservedDurationSeconds = size(traces,1)/frameRate;

reasons = {};
if metrics.ValidEyeSampleCount < options.MinimumValidEyeSamples
    reasons{end+1} = 'insufficient valid eye samples'; %#ok<AGROW>
end
if metrics.LongFrameFraction > options.MaximumLongFrameFraction
    reasons{end+1} = 'excessive frame drops'; %#ok<AGROW>
end
if metrics.ObservedDurationSeconds < options.MinimumDurationSeconds
    reasons{end+1} = 'trial too short'; %#ok<AGROW>
end
if ~options.CalibrationStable
    reasons{end+1} = 'calibration changed'; %#ok<AGROW>
end
metrics.TrialValid = isempty(reasons);
metrics.InvalidReasons = reasons;
end


function correlations = vectorCorrelation(first,second,maximumLag)
lags = -maximumLag:maximumLag;
correlations = nan(size(lags));
for ii = 1:numel(lags)
    lag = lags(ii);
    if lag >= 0
        a = first(1:end-lag,:);
        b = second(1+lag:end,:);
    else
        a = first(1-lag:end,:);
        b = second(1:end+lag,:);
    end
    if isempty(a) || isempty(b)
        continue
    end
    numerator = sum(a.*b,'all');
    denominator = sqrt(sum(a.^2,'all')*sum(b.^2,'all'));
    if denominator > 0
        correlations(ii) = numerator/denominator;
    end
end
end


function value = setDefault(value,name,defaultValue)
if ~isfield(value,name) || isempty(value.(name))
    value.(name) = defaultValue;
end
end
