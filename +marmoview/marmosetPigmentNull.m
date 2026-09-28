function condition = marmosetPigmentNull(calibrationSource,nullPeakNm,axisScale,options)
% MARMOSETPIGMENTNULL Make an S- and candidate-pigment-silent RGB axis.

if nargin < 3 || isempty(axisScale)
    axisScale = 1;
end
if nargin < 4 || isempty(options)
    options = struct();
end
if ~isfield(options,'SilentLeakageTolerance')
    options.SilentLeakageTolerance = 0.005;
end
if ~isfield(options,'ExpectedMonitorIdentifier')
    options.ExpectedMonitorIdentifier = '';
end
if ~isscalar(axisScale) || ~isfinite(axisScale) || ...
        axisScale < 0 || axisScale > 1
    error('marmosetPigmentNull:AxisScale', ...
        'axisScale must be a finite scalar in [0,1].');
end
validNulls = [543 556 563];
if ~isscalar(nullPeakNm) || ~ismember(nullPeakNm,validNulls)
    error('marmosetPigmentNull:NullPeak', ...
        'nullPeakNm must be 543, 556, or 563.');
end

loadOptions = struct('AllowDummy',false,'ExpectedMonitorIdentifier', ...
    options.ExpectedMonitorIdentifier);
calibration = marmoview.loadCandidateConeCalibration(calibrationSource,loadOptions);
peaks = calibration.CandidateConePeaksNm(:)';
T = calibration.CandidateRGBToCones;
b = calibration.BackgroundLinearRGB(:);
e0 = calibration.CandidateBackgroundExcitations(:);
nullIndex = find(peaks == nullPeakNm,1);
sIndex = find(peaks == 423,1);
silentIndices = [sIndex nullIndex];
A = T(silentIndices,:);
tolerance = 1e-10*max(1,norm(A,'fro'));
if rank(A,tolerance) ~= 2
    error('marmosetPigmentNull:Rank', ...
        'The S-plus-target silent-constraint matrix must have rank two.');
end
d = null(A);
if size(d,2) ~= 1 || norm(A*d) > tolerance
    error('marmosetPigmentNull:Nullspace', ...
        'Silent constraints did not produce one valid RGB direction.');
end

unitContrast = (T*d)./e0;
mlIndices = find(peaks ~= 423 & peaks ~= nullPeakNm);
normalizer = max(abs(unitContrast(mlIndices)));
if ~isfinite(normalizer) || normalizer <= tolerance
    error('marmosetPigmentNull:NoModulation', ...
        'The null direction does not modulate a non-silenced ML pigment.');
end
d = d/normalizer;
unitContrast = (T*d)./e0;
signIndex = mlIndices(find(peaks(mlIndices) == max(peaks(mlIndices)),1));
if unitContrast(signIndex) < 0
    d = -d;
    unitContrast = -unitContrast;
end

positiveLimit = gamutLimit(b,d);
negativeLimit = gamutLimit(b,-d);
symmetricLimit = min(positiveLimit,negativeLimit);
amplitude = axisScale*symmetricLimit;
negativeRGB = cleanGamut(b-amplitude*d);
positiveRGB = cleanGamut(b+amplitude*d);
requestedContrast = [((T*negativeRGB)-e0)./e0, ...
    ((T*positiveRGB)-e0)./e0]';

backgroundDevice = marmoview.realizeCalibratedRGB(calibration,b');
negativeDevice = marmoview.realizeCalibratedRGB(calibration,negativeRGB');
positiveDevice = marmoview.realizeCalibratedRGB(calibration,positiveRGB');
realizedBackgroundExcitation = T*backgroundDevice.RealizedLinearRGB(:);
realizedContrast = [((T*negativeDevice.RealizedLinearRGB(:))- ...
    realizedBackgroundExcitation)./realizedBackgroundExcitation, ...
    ((T*positiveDevice.RealizedLinearRGB(:))- ...
    realizedBackgroundExcitation)./realizedBackgroundExcitation]';
maximumSilentLeakage = max(abs(realizedContrast(:,silentIndices)),[],'all');
leakageTolerance = options.SilentLeakageTolerance;
if maximumSilentLeakage > leakageTolerance
    error('marmosetPigmentNull:SilentLeakage', ...
        'Realized silent-cone leakage %.6g exceeds tolerance %.6g.', ...
        maximumSilentLeakage,leakageTolerance);
elseif maximumSilentLeakage > 0.002
    warning('marmosetPigmentNull:SilentLeakageWarning', ...
        'Realized silent-cone leakage is %.6g.',maximumSilentLeakage);
end

condition = baseCondition(calibration);
condition.ConditionID = sprintf('null%d_scale_%g',nullPeakNm,axisScale);
condition.ConditionType = 'pigment-null';
condition.NullPeakNm = nullPeakNm;
condition.NegativeLinearRGB = negativeRGB';
condition.PositiveLinearRGB = positiveRGB';
condition.BackgroundDeviceCodes = backgroundDevice.DeviceCodes;
condition.NegativeDeviceCodes = negativeDevice.DeviceCodes;
condition.PositiveDeviceCodes = positiveDevice.DeviceCodes;
condition.BackgroundFramebufferRGB255 = backgroundDevice.FramebufferRGB255;
condition.NegativeFramebufferRGB255 = negativeDevice.FramebufferRGB255;
condition.PositiveFramebufferRGB255 = positiveDevice.FramebufferRGB255;
condition.RealizedBackgroundLinearRGB = backgroundDevice.RealizedLinearRGB;
condition.RealizedNegativeLinearRGB = negativeDevice.RealizedLinearRGB;
condition.RealizedPositiveLinearRGB = positiveDevice.RealizedLinearRGB;
condition.RequestedConeContrast = requestedContrast;
condition.RealizedConeContrast = realizedContrast;
condition.SilentConeIndices = silentIndices;
condition.MaximumSilentLeakage = maximumSilentLeakage;
condition.PositiveGamutLimit = positiveLimit;
condition.NegativeGamutLimit = negativeLimit;
condition.MaximumSymmetricAmplitude = symmetricLimit;
condition.AxisScale = axisScale;
condition.ValidationPass = true;
condition.UnitRGBDirection = d';
condition.UnitCandidateConeContrast = unitContrast';
end


function condition = baseCondition(calibration)
condition = marmoview.marmosetPigmentNullTemplate(calibration);
end


function limit = gamutLimit(background,direction)
limits = inf(3,1);
positive = direction > 1e-14;
negative = direction < -1e-14;
limits(positive) = (1-background(positive))./direction(positive);
limits(negative) = background(negative)./(-direction(negative));
limit = min(limits);
if ~isfinite(limit) || limit < 0
    error('marmosetPigmentNull:Gamut', ...
        'No positive in-gamut amplitude exists for the null direction.');
end
end


function rgb = cleanGamut(rgb)
tolerance = 1e-10;
if any(rgb < -tolerance) || any(rgb > 1+tolerance)
    error('marmosetPigmentNull:Gamut','Calculated endpoint is outside gamut.');
end
rgb = min(max(rgb,0),1);
end
