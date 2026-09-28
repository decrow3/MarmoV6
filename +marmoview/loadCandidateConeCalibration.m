function calibration = loadCandidateConeCalibration(calibrationSource,options)
% LOADCANDIDATECONECALIBRATION Load the marmoset candidate-cone contract.

if nargin < 2 || isempty(options)
    options = struct();
end
options = setDefault(options,'AllowDummy',false);
options = setDefault(options,'ExpectedMonitorIdentifier','');

[raw,sourceName] = readSource(calibrationSource);
raw = unwrapRuntime(raw);

calibration = struct();
calibration.SchemaVersion = requireField(raw, ...
    {'SchemaVersion','schema_version'},'schema version');
calibration.CandidateConePeaksNm = double(requireField(raw, ...
    {'CandidateConePeaksNm','CandidateConePeaks','candidate_cone_peaks_nm'}, ...
    'candidate cone peaks'));
calibration.CandidateRGBToCones = double(requireField(raw, ...
    {'CandidateRGBToCones','candidate_rgb_to_cones'}, ...
    'candidate RGB-to-cones matrix'));
calibration.BackgroundLinearRGB = double(requireField(raw, ...
    {'BackgroundLinearRGB','BackgroundRGB','background_linear_rgb'}, ...
    'background linear RGB'));
calibration.CandidateBackgroundExcitations = double(requireField(raw, ...
    {'CandidateBackgroundExcitations','candidate_background_excitations'}, ...
    'candidate background excitations'));
calibration.WavelengthsNm = double(requireField(raw, ...
    {'WavelengthsNm','WavelengthSamplingNm','Wavelengths', ...
    'wavelengths_nm','wavelength_sampling_nm'},'wavelength sampling'));
calibration.PrimarySpectra = double(requireField(raw, ...
    {'PrimarySpectra','MonitorPrimarySpectra','primary_spectra'}, ...
    'monitor primary spectra'));
calibration.GammaDeviceInput = normalizeGamma(requireField(raw, ...
    {'GammaDeviceInput','GammaForwardDeviceInput','InverseGammaDeviceOutput', ...
    'gamma_device_input'},'empirical gamma device samples'));
calibration.GammaLinearOutput = normalizeGamma(requireField(raw, ...
    {'GammaLinearOutput','GammaForwardLinearOutput','InverseGammaLinearInput', ...
    'gamma_linear_output'},'empirical gamma output samples'));
calibration.BitDepth = double(requireField(raw, ...
    {'BitDepth','bit_depth'},'framebuffer bit depth'));
calibration.GammaApplication = char(requireField(raw, ...
    {'GammaApplication','gamma_application'},'gamma-application policy'));
calibration.CalibrationChecksum = char(requireField(raw, ...
    {'CalibrationChecksum','CalibrationChecksumSHA256', ...
    'calibration_checksum','calibration_checksum_sha256'}, ...
    'calibration checksum'));
calibration.MonitorIdentifier = char(requireField(raw, ...
    {'MonitorIdentifier','monitor_identifier','MonitorTarget','monitor_target'}, ...
    'monitor identifier'));
calibration.CalibrationDate = char(requireField(raw, ...
    {'CalibrationDate','calibration_date'},'calibration date'));
calibration.CalibrationSource = sourceName;
calibration.IsDummyCalibration = detectDummy(raw,sourceName);

validateCalibration(calibration,options);
end


function [raw,sourceName] = readSource(source)
if isstruct(source)
    raw = source;
    sourceName = '<MATLAB struct>';
    return
end
sourceName = char(source);
if ~exist(sourceName,'file')
    error('loadCandidateConeCalibration:Missing', ...
        'Candidate-cone calibration not found: %s',sourceName);
end
[~,~,extension] = fileparts(sourceName);
if strcmpi(extension,'.json')
    raw = jsondecode(fileread(sourceName));
else
    raw = load(sourceName);
end
end


function raw = unwrapRuntime(raw)
if isfield(raw,'runtime')
    raw = raw.runtime;
elseif isfield(raw,'Runtime')
    raw = raw.Runtime;
end
if isfield(raw,'CandidateRuntime')
    candidate = raw.CandidateRuntime;
    metadata = raw;
    names = fieldnames(metadata);
    for ii = 1:numel(names)
        if ismember(names{ii},{'CandidateRuntime','Phenotypes'})
            continue
        end
        if ~isfield(candidate,names{ii})
            candidate.(names{ii}) = metadata.(names{ii});
        end
    end
    raw = candidate;
end
end


function value = requireField(source,names,label)
for ii = 1:numel(names)
    if isfield(source,names{ii}) && ~isempty(source.(names{ii}))
        value = source.(names{ii});
        return
    end
end
error('loadCandidateConeCalibration:MissingMetadata', ...
    'Calibration is missing %s.',label);
end


function curves = normalizeGamma(value)
if iscell(value)
    if numel(value) ~= 3
        error('loadCandidateConeCalibration:GammaShape', ...
            'Empirical gamma data must contain one curve per RGB primary.');
    end
    curves = reshape(cellfun(@(x) double(x(:)),value, ...
        'UniformOutput',false),1,3);
elseif isnumeric(value) && size(value,2) == 3
    curves = arrayfun(@(ii) double(value(:,ii)),1:3,'UniformOutput',false);
elseif isnumeric(value) && size(value,1) == 3
    curves = arrayfun(@(ii) double(value(ii,:))',1:3,'UniformOutput',false);
else
    error('loadCandidateConeCalibration:GammaShape', ...
        'Empirical gamma data must be an N-by-3 array or a three-cell array.');
end
end


function validateCalibration(calibration,options)
expectedPeaks = [563 556 543 423];
if ~isequal(calibration.CandidateConePeaksNm(:)',expectedPeaks)
    error('loadCandidateConeCalibration:ConeOrder', ...
        'Candidate cone rows must be ordered [563 556 543 423].');
end
if ~isequal(size(calibration.CandidateRGBToCones),[4 3]) || ...
        any(~isfinite(calibration.CandidateRGBToCones(:)))
    error('loadCandidateConeCalibration:MatrixShape', ...
        'CandidateRGBToCones must be a finite 4-by-3 matrix.');
end
background = calibration.BackgroundLinearRGB(:);
if numel(background) ~= 3 || any(~isfinite(background)) || ...
        any(background <= 0) || any(background >= 1)
    error('loadCandidateConeCalibration:Background', ...
        'BackgroundLinearRGB must contain three values strictly inside (0,1).');
end
expectedExcitation = calibration.CandidateRGBToCones*background;
providedExcitation = calibration.CandidateBackgroundExcitations(:);
if numel(providedExcitation) ~= 4 || any(providedExcitation <= 0) || ...
        max(abs(expectedExcitation-providedExcitation)) > ...
        1e-9*max(1,max(abs(expectedExcitation)))
    error('loadCandidateConeCalibration:BackgroundExcitation', ...
        'Candidate background excitations do not match T*background.');
end
if size(calibration.PrimarySpectra,2) ~= 3 || ...
        size(calibration.PrimarySpectra,1) ~= numel(calibration.WavelengthsNm)
    error('loadCandidateConeCalibration:SpectraShape', ...
        'PrimarySpectra must have one row per wavelength and three columns.');
end
if ~isscalar(calibration.BitDepth) || calibration.BitDepth < 1 || ...
        calibration.BitDepth ~= round(calibration.BitDepth)
    error('loadCandidateConeCalibration:BitDepth', ...
        'BitDepth must be a positive integer.');
end
validGammaPolicies = {'software-encoded','ptb-gamma-lut'};
if ~ismember(lower(calibration.GammaApplication),validGammaPolicies)
    error('loadCandidateConeCalibration:GammaPolicy', ...
        'GammaApplication must be software-encoded or ptb-gamma-lut.');
end
for channel = 1:3
    x = calibration.GammaDeviceInput{channel};
    y = calibration.GammaLinearOutput{channel};
    if numel(x) ~= numel(y) || numel(x) < 2 || ...
            any(~isfinite(x)) || any(~isfinite(y)) || ...
            any(diff(x) <= 0) || any(diff(y) < 0) || ...
            x(1) > 1e-9 || x(end) < 1-1e-9 || ...
            y(1) > 1e-6 || y(end) < 1-1e-6
        error('loadCandidateConeCalibration:GammaCurve', ...
            'Gamma curves must be finite, monotonic, and span zero to one.');
    end
end
if calibration.IsDummyCalibration && ~logical(options.AllowDummy)
    error('loadCandidateConeCalibration:DummyCalibration', ...
        'Dummy/proxy calibration is prohibited for marmoset conditions.');
end
expectedMonitor = char(options.ExpectedMonitorIdentifier);
if ~isempty(expectedMonitor) && ...
        ~strcmpi(strtrim(expectedMonitor),strtrim(calibration.MonitorIdentifier))
    error('loadCandidateConeCalibration:MonitorMismatch', ...
        'Calibration monitor "%s" does not match active rig "%s".', ...
        calibration.MonitorIdentifier,expectedMonitor);
end
end


function tf = detectDummy(raw,sourceName)
textFields = {'Warning','warning','CalibrationPurpose','calibration_purpose', ...
    'MonitorIdentifier','monitor_identifier','MonitorTarget','monitor_target'};
textValue = lower(sourceName);
for ii = 1:numel(textFields)
    if isfield(raw,textFields{ii})
        value = raw.(textFields{ii});
        if ischar(value) || (isstring(value) && isscalar(value))
            textValue = [textValue ' ' lower(char(value))]; %#ok<AGROW>
        end
    end
end
explicit = false;
if isfield(raw,'IsDummyCalibration')
    explicit = logical(raw.IsDummyCalibration);
elseif isfield(raw,'is_dummy_calibration')
    explicit = logical(raw.is_dummy_calibration);
end
tf = explicit || contains(textValue,'dummy') || ...
    contains(textValue,'proxy') || contains(textValue,'not for experiment');
end


function value = setDefault(value,name,defaultValue)
if ~isfield(value,name) || isempty(value.(name))
    value.(name) = defaultValue;
end
end
