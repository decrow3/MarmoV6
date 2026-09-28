function bank = marmosetPhenotypeConditionBank(calibrationSource,options)
% MARMOSETPHENOTYPECONDITIONBANK Build diagnostic and control flow colours.

if nargin < 2 || isempty(options)
    options = struct();
end
options = setDefault(options,'ContrastLevels',1);
options = setDefault(options,'AchromaticContrast',0.2);
options = setDefault(options,'SilentLeakageTolerance',0.005);
options = setDefault(options,'ExpectedMonitorIdentifier','');

levels = double(options.ContrastLevels(:)');
if isempty(levels) || any(~isfinite(levels)) || any(levels < 0) || any(levels > 1)
    error('marmosetPhenotypeConditionBank:ContrastLevels', ...
        'ContrastLevels must contain values in [0,1].');
end
if ~isscalar(options.AchromaticContrast) || ...
        ~isfinite(options.AchromaticContrast) || ...
        options.AchromaticContrast <= 0 || options.AchromaticContrast >= 1
    error('marmosetPhenotypeConditionBank:AchromaticContrast', ...
        'AchromaticContrast must be a scalar strictly inside (0,1).');
end

loadOptions = struct('AllowDummy',false,'ExpectedMonitorIdentifier', ...
    options.ExpectedMonitorIdentifier);
calibration = marmoview.loadCandidateConeCalibration(calibrationSource,loadOptions);
nullOptions = struct('SilentLeakageTolerance',options.SilentLeakageTolerance, ...
    'ExpectedMonitorIdentifier',options.ExpectedMonitorIdentifier);

conditions = struct([]);
nullPeaks = [543 556 563];
for peak = nullPeaks
    for level = levels
        item = marmoview.marmosetPigmentNull( ...
            calibrationSource,peak,level,nullOptions);
        conditions = appendCondition(conditions,item);
    end
end
conditions = appendCondition(conditions,makeAchromatic(calibration, ...
    options.AchromaticContrast));
conditions = appendCondition(conditions,makeCatch(calibration));

bank = struct();
bank.SchemaVersion = 'MarmosetPhenotypeConditionBank-1.0';
bank.CalibrationSource = calibration.CalibrationSource;
bank.CalibrationChecksum = calibration.CalibrationChecksum;
bank.MonitorIdentifier = calibration.MonitorIdentifier;
bank.ConePeaksNm = calibration.CandidateConePeaksNm(:)';
bank.ContrastLevels = levels;
bank.AchromaticContrast = options.AchromaticContrast;
bank.SilentLeakageTolerance = options.SilentLeakageTolerance;
bank.Conditions = conditions;
end


function condition = makeAchromatic(calibration,contrast)
b = calibration.BackgroundLinearRGB(:);
direction = b;
positiveLimit = gamutLimit(b,direction);
negativeLimit = gamutLimit(b,-direction);
symmetricLimit = min(positiveLimit,negativeLimit);
amplitude = contrast*symmetricLimit;
negativeRGB = b-amplitude*direction;
positiveRGB = b+amplitude*direction;
condition = makeControl(calibration,'achromatic','achromatic', ...
    negativeRGB,positiveRGB,contrast,positiveLimit,negativeLimit,symmetricLimit);
end


function condition = makeCatch(calibration)
b = calibration.BackgroundLinearRGB(:);
condition = makeControl(calibration,'catch','catch',b,b,0,0,0,0);
end


function condition = makeControl(calibration,id,type,negativeRGB,positiveRGB, ...
        scale,positiveLimit,negativeLimit,symmetricLimit)
T = calibration.CandidateRGBToCones;
e0 = calibration.CandidateBackgroundExcitations(:);
backgroundDevice = marmoview.realizeCalibratedRGB(calibration, ...
    calibration.BackgroundLinearRGB(:)');
negativeDevice = marmoview.realizeCalibratedRGB(calibration,negativeRGB');
positiveDevice = marmoview.realizeCalibratedRGB(calibration,positiveRGB');
requested = [((T*negativeRGB)-e0)./e0,((T*positiveRGB)-e0)./e0]';
realizedE0 = T*backgroundDevice.RealizedLinearRGB(:);
realized = [((T*negativeDevice.RealizedLinearRGB(:))-realizedE0)./realizedE0, ...
    ((T*positiveDevice.RealizedLinearRGB(:))-realizedE0)./realizedE0]';

condition = marmoview.marmosetPigmentNullTemplate(calibration);
condition.ConditionID = id;
condition.ConditionType = type;
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
condition.RequestedConeContrast = requested;
condition.RealizedConeContrast = realized;
condition.MaximumSilentLeakage = 0;
condition.PositiveGamutLimit = positiveLimit;
condition.NegativeGamutLimit = negativeLimit;
condition.MaximumSymmetricAmplitude = symmetricLimit;
condition.AxisScale = scale;
condition.ValidationPass = true;
end


function conditions = appendCondition(conditions,item)
if isempty(conditions)
    conditions = item;
else
    conditions(end+1) = item; %#ok<AGROW>
end
end


function limit = gamutLimit(background,direction)
limits = inf(3,1);
positive = direction > 1e-14;
negative = direction < -1e-14;
limits(positive) = (1-background(positive))./direction(positive);
limits(negative) = background(negative)./(-direction(negative));
limit = min(limits);
end


function value = setDefault(value,name,defaultValue)
if ~isfield(value,name) || isempty(value.(name))
    value.(name) = defaultValue;
end
end
