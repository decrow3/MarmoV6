function realization = realizeCalibratedRGB(calibration,linearRGB)
% REALIZECALIBRATEDRGB Apply empirical inverse gamma and framebuffer quantization.

linearRGB = double(linearRGB);
if isvector(linearRGB)
    linearRGB = reshape(linearRGB,1,3);
end
if size(linearRGB,2) ~= 3 || any(~isfinite(linearRGB(:))) || ...
        any(linearRGB(:) < 0) || any(linearRGB(:) > 1)
    error('realizeCalibratedRGB:RGB', ...
        'linearRGB must be an in-gamut N-by-3 matrix.');
end

maximumCode = 2^calibration.BitDepth-1;
deviceInput = zeros(size(linearRGB));
for channel = 1:3
    measuredDevice = calibration.GammaDeviceInput{channel};
    measuredLinear = calibration.GammaLinearOutput{channel};
    [measuredLinear,uniqueIndex] = unique(measuredLinear,'stable');
    measuredDevice = measuredDevice(uniqueIndex);
    deviceInput(:,channel) = interp1(measuredLinear,measuredDevice, ...
        linearRGB(:,channel),'pchip');
end
if any(~isfinite(deviceInput(:))) || any(deviceInput(:) < -1e-9) || ...
        any(deviceInput(:) > 1+1e-9)
    error('realizeCalibratedRGB:InverseGamma', ...
        'Inverse-gamma interpolation produced an invalid device value.');
end
deviceInput = min(max(deviceInput,0),1);
deviceCodes = round(maximumCode*deviceInput);
quantizedDevice = deviceCodes/maximumCode;

realizedLinear = zeros(size(linearRGB));
for channel = 1:3
    realizedLinear(:,channel) = interp1( ...
        calibration.GammaDeviceInput{channel}, ...
        calibration.GammaLinearOutput{channel}, ...
        quantizedDevice(:,channel),'pchip');
end
realizedLinear = min(max(realizedLinear,0),1);

switch lower(calibration.GammaApplication)
    case 'software-encoded'
        framebufferRGB = quantizedDevice;
    case 'ptb-gamma-lut'
        framebufferRGB = linearRGB;
    otherwise
        error('realizeCalibratedRGB:GammaPolicy', ...
            'Unsupported gamma policy: %s',calibration.GammaApplication);
end

realization = struct();
realization.RequestedLinearRGB = linearRGB;
realization.InverseGammaDeviceInput = deviceInput;
realization.DeviceCodes = deviceCodes;
realization.QuantizedDeviceInput = quantizedDevice;
realization.FramebufferRGB255 = 255*framebufferRGB;
realization.RealizedLinearRGB = realizedLinear;
end
