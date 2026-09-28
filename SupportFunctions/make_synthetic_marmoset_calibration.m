function calibration = make_synthetic_marmoset_calibration
% MAKE_SYNTHETIC_MARMOSET_CALIBRATION Mathematical-test fixture only.

calibration = struct();
calibration.SchemaVersion = 'SYNTHETIC-TEST-1.0';
calibration.CandidateConePeaksNm = [563 556 543 423];
calibration.CandidateRGBToCones = [ ...
    1.20 0.40 0.10
    1.00 0.70 0.12
    0.78 1.00 0.14
    0.08 0.18 1.20];
calibration.BackgroundLinearRGB = [0.5 0.5 0.5];
calibration.CandidateBackgroundExcitations = ...
    calibration.CandidateRGBToCones*calibration.BackgroundLinearRGB(:);
calibration.WavelengthsNm = (400:10:700)';
calibration.PrimarySpectra = repmat(linspace(0,1,31)',1,3);
device = linspace(0,1,4097)';
calibration.GammaDeviceInput = {device device device};
calibration.GammaLinearOutput = {device.^2.2 device.^2.2 device.^2.2};
calibration.BitDepth = 16;
calibration.GammaApplication = 'software-encoded';
calibration.CalibrationChecksumSHA256 = ...
    'SYNTHETIC_TEST_FIXTURE_NOT_AN_EXPERIMENTAL_CALIBRATION';
calibration.MonitorIdentifier = 'SYNTHETIC_TEST_MONITOR';
calibration.CalibrationDate = '2000-01-01';
calibration.IsDummyCalibration = false;
end
