function [S,P] = MarmosetConePhenotypeFlow
% MARMOSETCONEPHENOTYPEFLOW Calibrated candidate-pigment null experiment.

S = MarmoViewRigSettings;
S.MarmoViewVersion = '6';
S.protocol = 'MarmosetConePhenotypeFlow';
S.protocol_class = 'protocols.PR_MarmosetConePhenotypeFlow';
S.protocolTitle = 'Marmoset Cone Null Flow';
S.TimeSensitive = 1:5;

taskRoot = fileparts(fileparts(mfilename('fullpath')));
defaultCalibration = fullfile(taskRoot,'SupportData','ConeCalibration', ...
    'MarmosetCandidateCones','ConeMath2026_runtime.mat');
if isfield(S,'marmosetCandidateCalibrationFile') && ...
        ~isempty(S.marmosetCandidateCalibrationFile)
    calibrationFile = S.marmosetCandidateCalibrationFile;
else
    calibrationFile = defaultCalibration;
end
if ~exist(calibrationFile,'file')
    error('MarmosetConePhenotypeFlow:CalibrationUnavailable', ...
        ['Experimental candidate-cone calibration is unavailable. Expected: ' ...
        '%s. Dummy calibration fallback is prohibited.'],calibrationFile);
end

% Fixed experimental configuration: retained in S and saved with every file.
S.marmosetConfig = struct();
S.marmosetConfig.CalibrationFile = calibrationFile;
S.marmosetConfig.ExpectedMonitorIdentifier = S.monitor;
S.marmosetConfig.ContrastLevels = 1;
S.marmosetConfig.RepeatsPerCondition = 12;
S.marmosetConfig.TrialDurationSeconds = 5;
S.marmosetConfig.DotSizeDeg = 0.10;
S.marmosetConfig.DotCount = 2500;
S.marmosetConfig.FlowExpansionSpeed = 0.10;
S.marmosetConfig.FlowCentreSpeedDegPerSecond = 8;
S.marmosetConfig.DotLifetimeFrames = 30;
S.marmosetConfig.FlowCentreMaximumEccentricityDeg = 4;
S.marmosetConfig.FlowCentreFilterTimeConstantSeconds = 0.25;
S.marmosetConfig.TrajectoryCount = 6;
S.marmosetConfig.MinimumDotSeparationDeg = 0.25;
S.marmosetConfig.DotPlacementAttempts = 50;
S.marmosetConfig.SilentLeakageTolerance = 0.005;
S.marmosetConfig.RandomSeed = 260829;
S.marmosetConfig.AchromaticContrast = 0.20;
S.marmosetConfig.CatchTrialFraction = 0.10;
S.marmosetConfig.MaximumLongFrameFraction = 0.05;
S.marmosetConfig.MinimumValidEyeSamples = round(S.frameRate);
S.marmosetConfig.MinimumAnalysisDurationSeconds = 1;
% Gaze starts on the flow centre; this interval is not rewarded, cannot
% lose the target, and is excluded from the saved following metrics.
S.marmosetConfig.OnsetExclusionSeconds = 0.30;

bankOptions = struct( ...
    'ContrastLevels',S.marmosetConfig.ContrastLevels, ...
    'AchromaticContrast',S.marmosetConfig.AchromaticContrast, ...
    'SilentLeakageTolerance',S.marmosetConfig.SilentLeakageTolerance, ...
    'ExpectedMonitorIdentifier',S.marmosetConfig.ExpectedMonitorIdentifier);
S.marmosetConditionBank = marmoview.marmosetPhenotypeConditionBank( ...
    calibrationFile,bankOptions);
S.marmosetConfig.CalibrationChecksum = ...
    S.marmosetConditionBank.CalibrationChecksum;
S.marmosetConfig.PhotopicBackgroundLinearRGB = ...
    S.marmosetConditionBank.Conditions(1).BackgroundLinearRGB;

trajectoryOptions = struct( ...
    'FrameRate',S.frameRate, ...
    'StimulusDuration',S.marmosetConfig.TrialDurationSeconds, ...
    'TrajectoryCount',S.marmosetConfig.TrajectoryCount, ...
    'RandomSeed',S.marmosetConfig.RandomSeed, ...
    'SpeedDegPerSecond',S.marmosetConfig.FlowCentreSpeedDegPerSecond, ...
    'MaximumEccentricityDeg', ...
        S.marmosetConfig.FlowCentreMaximumEccentricityDeg, ...
    'FilterTimeConstantSeconds', ...
        S.marmosetConfig.FlowCentreFilterTimeConstantSeconds);
S.marmosetTrajectoryBank = ...
    marmoview.makeMarmosetFlowTrajectoryBank(trajectoryOptions);

planOptions = struct( ...
    'RepeatsPerCondition',S.marmosetConfig.RepeatsPerCondition, ...
    'TrajectoryCount',S.marmosetConfig.TrajectoryCount, ...
    'RandomSeed',S.marmosetConfig.RandomSeed, ...
    'RewardAmount',3, ...
    'CatchTrialFraction',S.marmosetConfig.CatchTrialFraction);
S.marmosetTrialPlan = marmoview.makeMarmosetPhenotypeTrialPlan( ...
    S.marmosetConditionBank,planOptions);
S.finish = size(S.marmosetTrialPlan.Rows,1);

calibration = marmoview.loadCandidateConeCalibration(calibrationFile,struct( ...
    'ExpectedMonitorIdentifier',S.marmosetConfig.ExpectedMonitorIdentifier));
if ~strcmpi(calibration.GammaApplication,'software-encoded')
    error('MarmosetConePhenotypeFlow:GammaPolicy', ...
        ['The initial protocol requires software-encoded empirical gamma. ' ...
        'PTB gamma-LUT installation is not yet enabled.']);
end
S.gammaApplication = calibration.GammaApplication;
backgroundCondition = S.marmosetConditionBank.Conditions(1);
S.bgColour = backgroundCondition.BackgroundFramebufferRGB255;

% GUI-editable values remain numeric scalars.
P.RepeatUntilCorrect = 0;
S.RepeatUntilCorrect = 'Repeat incomplete trials? (0 or 1):';
P.PreserveTrialOrder = 1;
S.PreserveTrialOrder = 'Preserve constrained trial order (must remain 1):';
P.rewardNumber = 3;
S.rewardNumber = 'Maximum reward pulses:';
P.rewardFix = 0;
S.rewardFix = 'Reward fixation acquisition?';
P.runType = 1;
S.runType = 'Use fixed trial plan (must remain 1):';
P.mode = 1;
S.mode = 'Optic flow mode (must remain 1):';
P.bkgd = mean(S.bgColour);
S.bkgd = 'Legacy scalar background (fixed by calibration):';
P.nDots = S.marmosetConfig.DotCount;
S.nDots = 'Dot count:';
P.dotSizeDeg = S.marmosetConfig.DotSizeDeg;
S.dotSizeDeg = 'Dot diameter (deg):';
P.flowExpansionSpeed = S.marmosetConfig.FlowExpansionSpeed;
S.flowExpansionSpeed = 'Optic-flow expansion speed:';
P.dotLifetimeFrames = S.marmosetConfig.DotLifetimeFrames;
S.dotLifetimeFrames = 'Dot lifetime (frames):';
P.dotMinSeparation = S.marmosetConfig.MinimumDotSeparationDeg;
S.dotMinSeparation = 'Minimum same-polarity dot separation (deg):';
P.dotPlacementAttempts = S.marmosetConfig.DotPlacementAttempts;
S.dotPlacementAttempts = 'Dot-placement attempts:';
P.centerDecayProfile = 1;
S.centerDecayProfile = 'Centre cull: 0-off, 1-laser, 2-TDM:';
P.initWinRadius = 1;
S.initWinRadius = 'Enter-fixation window (deg):';
P.fixWinRadius = 2;
S.fixWinRadius = 'Fixation window (deg):';
P.targWinRadius = 3;
S.targWinRadius = 'Flow-centre following window (deg):';
P.fixPointRadius = 0.35;
S.fixPointRadius = 'Fixation point radius (deg):';
P.startDur = 4;
S.startDur = 'Time to acquire fixation (s):';
P.flashFrameLength = 30;
S.flashFrameLength = 'Fixation flash duration (frames):';
P.fixGrace = 0.05;
S.fixGrace = 'Fixation grace period (s):';
P.fixMin = 0.05;
S.fixMin = 'Minimum fixation duration (s):';
P.fixRan = 0.10;
S.fixRan = 'Additional random fixation duration (s):';
P.stimDur = S.marmosetConfig.TrialDurationSeconds;
S.stimDur = 'Stimulus duration (s):';
P.lostgrace = 0.25;
S.lostgrace = 'Lost-centre grace period (s):';
P.RewardDur = 1;
S.RewardDur = 'Following duration per reward (s):';
P.iti = 0.5;
S.iti = 'Inter-trial interval (s):';
P.blank_iti = 0.5;
S.blank_iti = 'Additional error interval (s):';
P.eyeRadius = 2.5;
S.eyeRadius = 'Gaze-indicator radius (deg):';
P.eyeIntensity = 40;
S.eyeIntensity = 'Gaze-indicator intensity:';
P.showEye = 0;
S.showEye = 'Show gaze indicator?';
end
