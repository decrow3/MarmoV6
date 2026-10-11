classdef hyperplaid_static < stimuli.stimulus
% Full-field static Hartley Hyperplaid: sum of K gratings (no drift).
% Two draw modes:
%   drawMode='procedural'  -> CreateProceduralSineGrating (fast, exact).
%   drawMode='texture'     -> Precomputed per-atom MakeTexture (float mean-zero).
%
% NoiseHistory row layout (numeric):
%   [ t, K, fx(1:K), fy(1:K), phiSent(1:K), amp, idx(1:K) ]
% where:
%   t       : flip time you pass in (VBL or photodiode-aligned)
%   K       : components this frame (usually obj.K)
%   fx, fy  : cycles/deg of each atom
%   phiSent : phase actually sent (Hartley ⇒ -pi/4 or +3pi/4 when sign flip)
%   amp     : per-component amplitude (= contrast/sqrt(K))
%   idx     : integer indices into obj.bank (for reproducibility)

    properties
        % --- display ---
        winPtr
        screenRect
        pixPerDeg
        bgGrey = 127;                  % mean luminance (0..255)

        % --- design (Hartley only) ---
        K double = 6                   % components per frame
        contrast double = 0.4          % RMS target per frame (scaled internally)

        % --- timing ---
        frameRate double = 60
        updateEveryNFrames double      % e.g., ceil(frameRate / 5) for ~5 Hz holds

        % --- geometry ---
        position double = []           % center [x y] in pixels (unused for full-field)

        % --- state ---
        frameUpdate double = 0
        tex                       % procedural sine handle (procedural mode)
        dstDiagPix double   % <-- NEW: side length (pixels) = screen diagonal
        current                        % struct: idx, fx, fy, sf, ori, phiSent, amp

        % --- lattice / bank ---
        spatialFrequencies_cpd double = 3*2.^linspace(-1,1,5) % band selection
        hartleyKmax double = []         % integer-cycle radius (auto if empty)
        uniquePerFrame logical = true   % sample without replacement
        bank                            % struct array with fields: fx, fy, sf, th, ori, tex

        % --- draw mode ---
        drawMode char = 'procedural'    % 'procedural' | 'texture'
        usePowerOfTwo logical = false   % hint for MakeTexture speed
        floatPrecision int8 = 1         % 1=fp16, 2=fp32 for MakeTexture
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
            ip.addParameter('K', 6);
            ip.addParameter('contrast', 0.4);
            ip.addParameter('updateEveryNFrames', []);
            ip.addParameter('hartleyKmax', []);
            ip.addParameter('uniquePerFrame', true);
            ip.addParameter('drawMode','procedural'); % 'procedural'|'texture'
            ip.addParameter('usePowerOfTwo', false);
            ip.addParameter('floatPrecision', 1);     % 1=fp16, 2=fp32
            ip.parse(varargin{:});

            obj.screenRect             = ip.Results.screenRect;
            obj.pixPerDeg              = ip.Results.pixPerDeg;
            obj.frameRate              = ip.Results.frameRate;
            obj.spatialFrequencies_cpd = ip.Results.spatialFrequencies;
            obj.K                      = ip.Results.K;
            obj.contrast               = ip.Results.contrast;
            obj.hartleyKmax            = ip.Results.hartleyKmax;
            obj.uniquePerFrame         = ip.Results.uniquePerFrame;
            obj.drawMode               = ip.Results.drawMode;
            obj.usePowerOfTwo          = ip.Results.usePowerOfTwo;
            obj.floatPrecision         = int8(ip.Results.floatPrecision);

            if isempty(ip.Results.updateEveryNFrames)
                obj.updateEveryNFrames = ceil(obj.frameRate / 5);
            else
                obj.updateEveryNFrames = ip.Results.updateEveryNFrames;
            end

            % Build lattice bank and (optionally) precompute textures
            obj.bank = obj.buildBank();
            
            % PTB procedural sine with zero base color (we draw bg once)
            w = RectWidth(obj.screenRect);
            h = RectHeight(obj.screenRect);
            % --- NEW: diagonal-sized procedural texture so rotations never clip
            obj.dstDiagPix = ceil(hypot(w, h));    % Pythagoras; cover all orientations
            obj.tex = CreateProceduralSineGrating(obj.winPtr, obj.dstDiagPix, obj.dstDiagPix, [0 0 0 0]);
            %obj.texProc = CreateProceduralSineGrating(obj.winPtr, w, h, [0 0 0 0]);
        
        end

        function bank = buildBank(obj)
            % Integer-cycle lattice across full screen in degrees.
            Wdeg = RectWidth(obj.screenRect)  / obj.pixPerDeg;
            Hdeg = RectHeight(obj.screenRect) / obj.pixPerDeg;

            if isempty(obj.hartleyKmax)
                nxmax = floor(Wdeg * max(obj.spatialFrequencies_cpd));
                nymax = floor(Hdeg * max(obj.spatialFrequencies_cpd));
            else
                nxmax = obj.hartleyKmax;
                nymax = obj.hartleyKmax;
            end

            [NX, NY] = ndgrid(-nxmax:nxmax, -nymax:nymax);
            keep = ~(NX==0 & NY==0);        % drop DC
            NX = NX(keep); NY = NY(keep);

            fx = NX / Wdeg;                 % cycles/deg
            fy = NY / Hdeg;
            sf = hypot(fx, fy);
            th = atan2(fy, fx);

            % --- SF band with tolerance (important if user passes a single SF)
            sfmin = min(obj.spatialFrequencies_cpd);
            sfmax = max(obj.spatialFrequencies_cpd);
            % At least one lattice step in k-space:
            dF = 1 / min(Wdeg, Hdeg);           % cycles/deg
            pad = max(0.5*dF, 0.01*sfmax);      % also allow ~1% slack
            sfInBand = (sf >= (sfmin - pad)) & (sf <= (sfmax + pad));

            fx = fx(sfInBand); fy = fy(sfInBand); sf = sf(sfInBand); th = th(sfInBand);

            % Half-plane representative to avoid ±k redundancy
            keepHalf = (fx>0) | (fx==0 & fy>0);
            fx = fx(keepHalf); fy = fy(keepHalf); sf = sf(keepHalf); th = th(keepHalf);

            % Build bank; ensure 'tex' exists even if unused (procedural mode)
            bank = struct('fx', num2cell(fx), ...
                'fy', num2cell(fy), ...
                'sf', num2cell(sf), ...
                'th', num2cell(th), ...
                'ori', num2cell(rad2deg(mod(th, 2*pi))), ...
                'tex', []);
        end



        function beforeTrial(obj)
            obj.setRandomSeed();
            obj.frameUpdate = 0;
            obj.sampleComponents();
        end

        function reset(obj)
            % Rewind RNG to last seed; resample a frame
            obj.rng.reset();
            obj.frameUpdate = 0;
            obj.sampleComponents();
        end

        function [idx, fx, fy, phiSent] = sampleHartley(obj)
            % Draw K atoms; Hartley phase = -π/4 with random sign via +π.
            C = numel(obj.bank);
            if obj.uniquePerFrame
                idx = randperm(obj.rng, C, obj.K);
            else
                idx = randi(obj.rng, C, [1 obj.K]);
            end
            fx = arrayfun(@(k) obj.bank(k).fx, idx);
            fy = arrayfun(@(k) obj.bank(k).fy, idx);

            phiSent = -pi/4 * ones(1, obj.K);
            flips = randi(obj.rng, 2, [1 obj.K])*2 - 3; % {-1,+1}
            phiSent(flips<0) = phiSent(flips<0) + pi;   % fold sign into phase
        end

        function sampleComponents(obj)
            [idx, fx, fy, phiSent] = obj.sampleHartley();

            sf  = hypot(fx, fy);
            ori = rad2deg(mod(atan2(fy, fx), 2*pi));

            obj.current.idx     = idx;
            obj.current.fx      = fx;
            obj.current.fy      = fy;
            obj.current.sf      = sf;
            obj.current.ori     = ori;
            obj.current.phiSent = phiSent;
            obj.current.amp     = obj.contrast / sqrt(max(obj.K,1));

            obj.frameUpdate = obj.updateEveryNFrames;
        end


        function beforeFrame(obj)
            % Draw background ONCE
            Screen('FillRect', obj.winPtr, obj.bgGrey);

            % Additive blend for components
            Screen('BlendFunction', obj.winPtr, GL_ONE, GL_ONE);

            % Centered diagonal rect that fully covers the screen at any rotation
            cx = (obj.screenRect(1) + obj.screenRect(3))/2;
            cy = (obj.screenRect(2) + obj.screenRect(4))/2;
            disp(num2str([0 0 obj.dstDiagPix obj.dstDiagPix]))
            if isempty(obj.dstDiagPix)
                obj.dstDiagPix;
            end
            dstRect = CenterRectOnPoint([0 0 obj.dstDiagPix obj.dstDiagPix], cx, cy);

            for j = 1:obj.K
                angDeg = obj.current.ori(j);
                sf_cpp = obj.current.sf(j) / obj.pixPerDeg;   % cycles/pixel
                phi    = obj.current.phiSent(j);
                aux    = [phi, sf_cpp, obj.current.amp, 1];   % [phase, freq, contrast, aspect]

                % IMPORTANT: Do NOT pass kPsychDontDoRotation (we *want* rotation).
                % Also no specialFlags: letting PTB rotate the drawn quad is fine,
                % screen edges will crop naturally.
                Screen('DrawTexture', obj.winPtr, obj.tex, [], dstRect, 90-angDeg, [], [], [], [], [], aux);
            end

            % Restore normal alpha blending
            Screen('BlendFunction', obj.winPtr, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        end



        function afterFrame(obj)
            obj.frameUpdate = obj.frameUpdate - 1;
            if obj.frameUpdate <= 0
                obj.sampleComponents();
            end
        end

        function updateTextures(obj, varargin) %#ok<INUSD>
            % Nothing to precompute for procedural mode;
            % Texture mode precomputed in precomputeTextures().
        end

        function CloseUp(obj)
            if ~isempty(obj.texProc)
                Screen('Close', obj.texProc); obj.texProc = [];
            end
            if ~isempty(obj.bank)
                for i = 1:numel(obj.bank)
                    if ~isempty(obj.bank(i).tex)
                        Screen('Close', obj.bank(i).tex);
                        obj.bank(i).tex = [];
                    end
                end
            end
        end

        function I = getImage(obj, rect, binSize) %#ok<INUSL>
            % CPU renderer for the current frame; matches both draw modes under linear gamma.
            if nargin < 2 || isempty(rect),    rect = obj.screenRect; end
            if nargin < 3 || isempty(binSize), binSize = 1; end

            % sizes & center
            w = RectWidth(obj.screenRect);
            h = RectHeight(obj.screenRect);
            cx = (obj.screenRect(1) + obj.screenRect(3)) / 2;
            cy = (obj.screenRect(2) + obj.screenRect(4)) / 2;
            if ~isempty(obj.position)
                cx = obj.position(1);
                cy = obj.position(2);
            end

            % pixel grid: y increases downward (match PTB)
            [xPix, yPix] = meshgrid( (1:w) + obj.screenRect(1) - cx, ...
                (1:h)' + obj.screenRect(2) - cy );
            Xdeg =  xPix / obj.pixPerDeg;
            Ydeg =  yPix / obj.pixPerDeg;   % <- no minus

            % Build coordinates in *pixels* -> *degrees*; Y up
            Xdeg =  xPix / obj.pixPerDeg;
            Ydeg = yPix / obj.pixPerDeg;
            acc = zeros(h, w, 'double');

            for j = 1:obj.K

                % Map orientation to the same convention as DrawTexture rotation:
                ori_rad = deg2rad(90 - obj.current.ori(j));

                % freq in radians/deg
                w = 2*pi * obj.current.sf(j);

                % phase: shader got degrees, CPU uses radians:
                pha = deg2rad(rad2deg(obj.current.phiSent(j))); % effectively == obj.current.phiSent(j)

                % Project onto grating normal and use COS to match the working path:
                gx = (cos(ori_rad) * (w * Xdeg)) + (sin(ori_rad) * (w * Ydeg)) + pha;

                acc = acc + cos(gx);
             
            end

            % amplitude + background
            Ilin = (double(obj.bgGrey)/255) + obj.current.amp * acc;
            Ilin = min(max(Ilin, 0), 1);

            % crop
%             L = max(1, round(rect(1) - obj.screenRect(1) + 1));
%             T = max(1, round(rect(2) - obj.screenRect(2) + 1));
%             R = min(w, round(rect(3) - obj.screenRect(1)));
%             B = min(h, round(rect(4) - obj.screenRect(2)));
%             Ilin = Ilin(T:B, L:R);

            % optional downsample
            if binSize > 1
                Ilin = localBoxDownsample(Ilin, binSize);
            end

            I = uint8(round(Ilin * 255));
        end

        function row = currentLogRowNumeric(obj, whenTimestamp)
            % [ t, K, fx(1:K), fy(1:K), phiSent(1:K), amp, idx(1:K) ]
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
    [h,w] = size(A);
    hh = floor(h/s)*s; ww = floor(w/s)*s;
    if hh ~= h || ww ~= w, A = A(1:hh, 1:ww); end
    A = reshape(A, s, hh/s, s, ww/s);
    J = squeeze(mean(mean(A, 1), 3));
end
