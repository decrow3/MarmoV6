classdef hyperplaid_static < stimuli.stimulus
% Full-field static Hartley Hyperplaid (K gratings/frame, no drift).
% Pixel-accurate: each lattice atom is pre-rendered to a texture with
% known [fx, fy] in cycles/deg. No per-draw rotations are used.
%
% Per-frame log row (numeric):
%   [ t, K, fx(1:K), fy(1:K), phiSent(1:K), amp, idx(1:K) ]
%
% Analysis tip (gaze correction per frame):
%   phi_ret = phiSent + 2*pi*(fx*dx + fy*dy);  z = amp .* exp(1i*phi_ret);

    properties
        % --- display ---
        winPtr
        screenRect
        pixPerDeg
        bgGrey = 127;                 % mean luminance (0..255)
        linearize = true              % assume linear CLUT (CPU/GPU parity)

        % --- design ---
        spatialFrequencies_cpd double = 3 * 2.^linspace(-1,1,5)  % rings (limits the bank)
        K double = 6                   % components per frame
        contrast double = 0.4          % RMS target; per-component amp = contrast/sqrt(K)

        % --- timing ---
        frameRate double = 60
        updateEveryNFrames double = [] % default: ceil(frameRate/5) ~5 Hz

        % --- geometry (full-field; aperture only used by getImage) ---
        position double = []           % [x y] center in px (unused here)
        diameter double = inf          % inf = full-field (no aperture)

        % --- Hartley bank / selection ---
        useHartleyLattice logical = true
        hartleyKmax double = []        % integer-cycle radius (auto if empty)
        uniquePerFrame logical = true  % sample without replacement (recommended)
        bank                           % struct array (fx, fy, sf, th, ori)
        texHandles                     % int32 array of texture handles (parallel to bank)
        bankReady logical = false

        % --- runtime state ---
        frameUpdate double = 0
        current                         % struct: idx, fx, fy, sf, ori, phiSent, amp
        rng                              % RandStream
    end

    methods
        function obj = hyperplaid_static(winPtr, varargin)
            obj = obj@stimuli.stimulus();
            obj.winPtr = winPtr;

            ip = inputParser();
            ip.addParameter('screenRect', []);
            ip.addParameter('pixPerDeg', 60);
            ip.addParameter('frameRate', 60);
            ip.addParameter('spatialFrequencies', obj.spatialFrequencies_cpd);
            ip.addParameter('K', obj.K);
            ip.addParameter('contrast', obj.contrast);
            ip.addParameter('updateEveryNFrames', []);
            ip.addParameter('useHartleyLattice', true);
            ip.addParameter('hartleyKmax', []);
            ip.addParameter('uniquePerFrame', true);
            ip.addParameter('bgGrey', obj.bgGrey);
            ip.addParameter('linearize', true);

            ip.parse(varargin{:});

            obj.screenRect             = ip.Results.screenRect;
            obj.pixPerDeg              = ip.Results.pixPerDeg;
            obj.frameRate              = ip.Results.frameRate;
            obj.spatialFrequencies_cpd = ip.Results.spatialFrequencies;
            obj.K                      = ip.Results.K;
            obj.contrast               = ip.Results.contrast;
            obj.useHartleyLattice      = ip.Results.useHartleyLattice;
            obj.hartleyKmax            = ip.Results.hartleyKmax;
            obj.uniquePerFrame         = ip.Results.uniquePerFrame;
            obj.bgGrey                 = ip.Results.bgGrey;
            obj.linearize              = ip.Results.linearize;

            if isempty(ip.Results.updateEveryNFrames)
                obj.updateEveryNFrames = ceil(obj.frameRate/5); % ~5 Hz holds
            else
                obj.updateEveryNFrames = ip.Results.updateEveryNFrames;
            end

            % RNG (inherits seeding policy from base if you prefer)
            obj.rng = RandStream('mt19937ar','Seed', sum(100*clock));

            % Build bank + textures now (full-field textures; no per-draw rotation)
            obj.bank = obj.buildBank();
            obj.texHandles = obj.buildTextures();  % parallel to bank struct
            obj.bankReady = true;
        end

        function bank = buildBank(obj)
            % Full-field lattice: integer cycles that fit the window in deg.
            Wdeg = RectWidth(obj.screenRect)/obj.pixPerDeg;
            Hdeg = RectHeight(obj.screenRect)/obj.pixPerDeg;

            if isempty(obj.hartleyKmax)
                nxmax = floor(Wdeg * max(obj.spatialFrequencies_cpd));
                nymax = floor(Hdeg * max(obj.spatialFrequencies_cpd));
            else
                nxmax = obj.hartleyKmax;
                nymax = obj.hartleyKmax;
            end

            [NX, NY] = ndgrid(-nxmax:nxmax, -nymax:nymax);
            keep = ~(NX==0 & NY==0);       % drop DC
            NX = NX(keep); NY = NY(keep);

            fx = NX / Wdeg;                % cycles/deg
            fy = NY / Hdeg;
            sf = hypot(fx, fy);
            th = atan2(fy, fx);

            % Keep band-limited atoms
            sfInBand = sf >= min(obj.spatialFrequencies_cpd) & sf <= max(obj.spatialFrequencies_cpd);
            fx = fx(sfInBand); fy = fy(sfInBand); sf = sf(sfInBand); th = th(sfInBand);

            % Half-plane (avoid ±k redundancy)
            keepHalf = (fx>0) | (fx==0 & fy>0);
            fx = fx(keepHalf); fy = fy(keepHalf); sf = sf(keepHalf); th = th(keepHalf);

            bank = struct('fx', num2cell(fx), ...
                          'fy', num2cell(fy), ...
                          'sf', num2cell(sf), ...
                          'th', num2cell(th), ...
                          'ori', num2cell(rad2deg(mod(th, 2*pi))));
        end

        function texHandles = buildTextures(obj)
            % Precompute an 8-bit luminance texture for each Hartley atom:
            % I(x,y) = bg + sin(2π (fx X + fy Y) - π/4)
            % We store as uint8; blending is additive in beforeFrame().
            w = RectWidth(obj.screenRect);
            h = RectHeight(obj.screenRect);

            % Pixel grid in degrees (y up)
            cx = (obj.screenRect(1) + obj.screenRect(3)) / 2;
            cy = (obj.screenRect(2) + obj.screenRect(4)) / 2;
            [xPix, yPix] = meshgrid( (1:w) + obj.screenRect(1) - cx, ...
                                     (1:h)' + obj.screenRect(2) - cy );
            Xdeg =  xPix / obj.pixPerDeg;
            Ydeg = -yPix / obj.pixPerDeg;

            nC = numel(obj.bank);
            texHandles = zeros(1, nC, 'int32');

            % unit-contrast, mean-zero sine-cas texture; we’ll scale per frame via blending
            for c = 1:nC
                fx = obj.bank(c).fx; fy = obj.bank(c).fy;
                phase = 2*pi*(fx.*Xdeg + fy.*Ydeg) - pi/4;  % Hartley cas
                % Make a unit-amplitude sine image in linear space, add bg later by FillRect
                Ilin = sin(phase);                          % in [-1,1]
                % Map to 8-bit with zero-mean around 0: we’ll draw bg once per frame.
                % To use additive blending cleanly, convert [-1,1] to [0,255] around 127:
                Iu8 = uint8(round(127 + 127 * Ilin));       % display-space values
                texHandles(c) = Screen('MakeTexture', obj.winPtr, Iu8, 0, 0);
            end
        end

        function beforeTrial(obj)
            obj.setRandomSeed();
            obj.frameUpdate = 0;
            if ~obj.bankReady
                obj.bank = obj.buildBank();
                obj.texHandles = obj.buildTextures();
                obj.bankReady = true;
            end
            obj.sampleComponents(); % prime first frame
        end

        function reset(obj)
            obj.rng.reset();
            obj.frameUpdate = 0;
            obj.sampleComponents();
        end

        function sampleComponents(obj)
            % Draw K lattice atoms (indices into bank); Hartley phase = -π/4
            C = numel(obj.bank);
            if obj.uniquePerFrame
                idx = randperm(obj.rng, C, obj.K);
            else
                idx = randi(obj.rng, C, [1 obj.K]);
            end

            fx  = arrayfun(@(i) obj.bank(i).fx, idx);
            fy  = arrayfun(@(i) obj.bank(i).fy, idx);
            sf  = hypot(fx, fy);
            ori = rad2deg(mod(atan2(fy, fx), 2*pi));

            % Hartley “cas” has fixed phase -π/4. We keep phiSent for logging
            % and for potential probe manipulations later (currently fixed).
            phiSent = -pi/4 * ones(1, obj.K);

            obj.current.idx     = idx;
            obj.current.fx      = fx;
            obj.current.fy      = fy;
            obj.current.sf      = sf;
            obj.current.ori     = ori;
            obj.current.phiSent = phiSent;
            obj.current.amp     = obj.contrast / sqrt(max(obj.K,1)); % per component

            obj.frameUpdate = obj.updateEveryNFrames;
        end

        function beforeFrame(obj)
            % 1) Draw background ONCE (mean gray)
            Screen('FillRect', obj.winPtr, obj.bgGrey);

            % 2) Additive blend for components
            Screen('BlendFunction', obj.winPtr, GL_ONE, GL_ONE);

            % We stored each atom as uint8 around 127. To achieve desired per-component
            % amplitude, we draw with a color gain that scales about the deviation from bg.
            % A convenient trick: draw textures with a normalized modulation:
            %   drawColor = [scale scale scale 1], where scale maps 127±127*sin(.) to bg ± amp
            %
            % If the texture is in [0,255], its deviation from 127 is rescaled by:
            %   desiredPeak = amp * 255
            %   scale = desiredPeak / 127
            %
            % Then additive blending over a bg-filled frame yields the correct contrast.
            desiredPeak = obj.current.amp * 255;
            scale = desiredPeak / 127;

            rect = obj.screenRect;
            for j = 1:obj.K
                tj = obj.texHandles(obj.current.idx(j));
                % PTB modulate color per-draw; use same factor for RGB:
                Screen('DrawTexture', obj.winPtr, tj, [], rect, 0, [], [], ...
                       [scale scale scale 1]);  % no rotation, full-field
            end

            % 3) Restore normal alpha blending
            Screen('BlendFunction', obj.winPtr, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        end

        function afterFrame(obj)
            obj.frameUpdate = obj.frameUpdate - 1;
            if obj.frameUpdate <= 0
                obj.sampleComponents();
            end
        end

        function updateTextures(obj, varargin) %#ok<INUSD>
            % If you change spatialFrequencies_cpd or window size at runtime,
            % call buildBank/buildTextures again. Here we assume fixed.
        end

        function CloseUp(obj)
            if ~isempty(obj.texHandles)
                for k = 1:numel(obj.texHandles)
                    if obj.texHandles(k) > 0
                        Screen('Close', obj.texHandles(k));
                    end
                end
            end
            obj.texHandles = [];
            obj.bankReady = false;
        end

        function I = getImage(obj, rect, binSize) %#ok<INUSD>
        % CPU renderer matching the sum of K Hartley atoms for current frame.
        % Returns uint8 image of size rect (default: full screenRect).
            if nargin < 2 || isempty(rect),    rect = obj.screenRect; end
            if nargin < 3 || isempty(binSize), binSize = 1; end

            w = RectWidth(obj.screenRect);
            h = RectHeight(obj.screenRect);
            cx = (obj.screenRect(1) + obj.screenRect(3)) / 2;
            cy = (obj.screenRect(2) + obj.screenRect(4)) / 2;

            [xPix, yPix] = meshgrid( (1:w) + obj.screenRect(1) - cx, ...
                                     (1:h)' + obj.screenRect(2) - cy );
            Xdeg =  xPix / obj.pixPerDeg;
            Ydeg = -yPix / obj.pixPerDeg;

            acc = zeros(h, w, 'double');
            for j = 1:obj.K
                fx = obj.current.fx(j); fy = obj.current.fy(j);
                phi = obj.current.phiSent(j);   % -pi/4
                phase = 2*pi*(fx.*Xdeg + fy.*Ydeg) + phi;
                acc = acc + sin(phase);
            end

            % Map to display space around bg, with the same amplitude as drawing:
            Ilin = (double(obj.bgGrey)/255) + (obj.current.amp) * acc;  % bg once
            Ilin = min(max(Ilin, 0), 1);

            % Crop to rect
            L = max(1, round(rect(1) - obj.screenRect(1) + 1));
            T = max(1, round(rect(2) - obj.screenRect(2) + 1));
            R = min(w, round(rect(3) - obj.screenRect(1)));
            B = min(h, round(rect(4) - obj.screenRect(2)));
            Ilin = Ilin(T:B, L:R);

            % Optional box-averaging
            if binSize > 1
                Ilin = localBoxDownsample(Ilin, binSize);
            end

            I = uint8(round(Ilin * 255));
        end

        function row = currentLogRowNumeric(obj, whenTimestamp)
        % Build the numeric log row:
        %   [ t, K, fx(1:K), fy(1:K), phiSent(1:K), amp, idx(1:K) ]
            if nargin<2, whenTimestamp = NaN; end
            t   = double(whenTimestamp);
            K   = double(obj.K);
            fx  = double(obj.current.fx(:)).';
            fy  = double(obj.current.fy(:)).';
            ph  = double(obj.current.phiSent(:)).';
            amp = double(obj.current.amp);
            idx = double(obj.current.idx(:)).';
            row = [t, K, fx, fy, ph, amp, idx];
        end
    end
end

function J = localBoxDownsample(A, s)
% Box-average downsample by integer factor s (no toolboxes).
    [h,w] = size(A);
    hh = floor(h/s)*s; ww = floor(w/s)*s;
    if hh ~= h || ww ~= w
        A = A(1:hh, 1:ww);
    end
    A = reshape(A, s, hh/s, s, ww/s);
    J = squeeze(mean(mean(A, 1), 3));
end
