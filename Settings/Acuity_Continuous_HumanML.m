function [S,P] = Acuity_Continuous_HumanML
% Human M-L balanced-dot pilot based on Acuity_Continuous.

[S,P] = Acuity_Continuous;

S.protocol = 'Acuity_Continuous_HumanML';
S.protocol_class = 'protocols.PR_Acuity_Continuous';
S.protocolTitle = 'Human M-L Acuity Track';

taskRoot = fileparts(fileparts(mfilename('fullpath')));
localManifest = fullfile(taskRoot,'SupportData','ConeCalibration', ...
    'human_T_558_530_420','manifest.json');
dummyManifest = fullfile('C:\Users\Declan\Documents\2026', ...
    'ConeColorMath','Dummy_DELL_P2419HC_proxy','exports', ...
    'human_T_558_530_420','manifest.json');
if isfield(S,'coneCalibrationFile') && exist(S.coneCalibrationFile,'file')
    % Prefer the calibration selected by the active rig.
elseif exist(localManifest,'file')
    S.coneCalibrationFile = localManifest;
else
    S.coneCalibrationFile = dummyManifest;
end
S.coneAxisLabel = 'M-L';
S.coneAxis = [-1 1 0]; % ConeMath human order is [L M S].
S.coneAxisScale = 1;
S.coneColor = marmoview.coneContrastColors( ...
    S.coneCalibrationFile,S.coneAxis,S.coneAxisScale);
S.coneCalibrationIsDummy = isfield(S.coneColor,'Warning') && ...
    contains(upper(char(S.coneColor.Warning)),'NOT FOR EXPERIMENTS');
if S.coneCalibrationIsDummy
    S.protocolTitle = 'DUMMY Human M-L Track';
end

% Feed linear RGB to the existing floating-point framebuffer and let the
% Psychtoolbox final-formatting stage perform per-primary gamma encoding.
if isfield(S.coneColor,'GammaExponent')
    S.gamma = S.coneColor.GammaExponent;
end
if isfield(S.coneColor,'InverseGamma')
    S.inverseGamma = S.coneColor.InverseGamma;
else
    error('Acuity_Continuous_HumanML:GammaMissing', ...
        'The cone calibration must include GammaExponent or InverseGamma.');
end

if max(abs(S.coneColor.BackgroundRGB255-mean(S.coneColor.BackgroundRGB255))) > 1e-9
    error('Acuity_Continuous_HumanML:NonGrayBackground', ...
        'This pilot expects an equal-RGB neutral background.');
end
P.bkgd = mean(S.coneColor.BackgroundRGB255);
S.bgColour = S.coneColor.BackgroundRGB255;

P.mode = 1;
P.balancedDots = 1;
P.dotContrast = 1;
P.normalizeDotRms = 0;
P.showEye = 0;
end
