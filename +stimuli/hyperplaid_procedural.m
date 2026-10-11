classdef hyperplaid_procedural < stimuli.stimulus
% Full-field static Hartley Hyperplaid (K gratings/frame, no drift).
% Procedural (shader-backed) version using explicit OpenGL calls only.
%
% Drop-in replacement for hyperplaid_static:
% - Same constructor signature and public methods.
% - Same 'current' struct fields and logging row format.
% - Photometry: we draw mean-zero deviations additively on top of bgGrey,
%   matching the static path where precomputed textures were summed.

    properties
        % --- display ---
        winPtr
        screenRect
        pixPerDeg
        bgGrey = 0.5
        linearize = true

        % --- design ---
        maxSF double = 8
        spatialFrequencies_cpd double = 3 * 2.^linspace(-1,1,5)
        K double = 6
        contrast double = 0.4

        ns double = 6
        equalStride logical = false


        % --- timing ---
        frameRate double = 60
        updateEveryNFrames double = []

        % --- geometry ---
        position double = []
        diameter double = inf

        % --- Hartley lattice parameters ---
        useHartleyLattice logical = true
        hartleyKmax double = []
        FmaxX_cpd double = 8
        FmaxY_cpd double = 8
        strideKx double = 32
        strideKy double = 18

        uniquePerFrame logical = true
        bank
        texHandles
        bankReady logical = false

        % --- runtime state ---
        frameUpdate double = 0
        current

        % --- GL / Shader ---
        gl_inited logical = false
        shader
        GL_BLEND            = hex2dec('0BE2')
        GL_ONE              = 1
        GL_SRC_ALPHA        = hex2dec('0302')
        GL_ONE_MINUS_SRC_ALPHA = hex2dec('0303')
        GL_QUADS            = hex2dec('0007')
        offwin = []
        offRect = []

        % --- PTB color-range restore ---
        oldmaximumvalue
        oldclampcolors
        oldapplyToDoubleInputMakeTexture
    end

    methods
        function obj = hyperplaid_procedural(winPtr, varargin)
            obj = obj@stimuli.stimulus();
            obj.winPtr = winPtr;

            % Assume InitializeMatlabOpenGL was already called before window open
            [obj.oldmaximumvalue, obj.oldclampcolors, obj.oldapplyToDoubleInputMakeTexture] = ...
                Screen('ColorRange', winPtr, 1, 0);

            % ---- Parse args ----
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
            ip.addParameter('maxSF', obj.maxSF);
            ip.addParameter('uniquePerFrame', true);
            ip.addParameter('bgGrey', obj.bgGrey);
            ip.addParameter('linearize', true);
            ip.addParameter('ns', obj.ns);
            ip.addParameter('equalStride', obj.equalStride);
            ip.parse(varargin{:});

            obj.screenRect             = ip.Results.screenRect;
            obj.pixPerDeg              = ip.Results.pixPerDeg;
            obj.frameRate              = ip.Results.frameRate;
            obj.spatialFrequencies_cpd = ip.Results.spatialFrequencies;
            obj.K                      = ip.Results.K;
            obj.contrast               = ip.Results.contrast;
            obj.useHartleyLattice      = ip.Results.useHartleyLattice;
            obj.hartleyKmax            = ip.Results.hartleyKmax;
            obj.FmaxX_cpd              = ip.Results.maxSF;
            obj.FmaxY_cpd              = ip.Results.maxSF;
            obj.uniquePerFrame         = ip.Results.uniquePerFrame;
            obj.bgGrey                 = 0.5;
            obj.linearize              = ip.Results.linearize;
            obj.ns                     = ip.Results.ns;
            obj.equalStride            = ip.Results.equalStride;

            if isempty(ip.Results.updateEveryNFrames)
                obj.updateEveryNFrames = ceil(obj.frameRate/60);
            else
                obj.updateEveryNFrames = ip.Results.updateEveryNFrames;
            end

            obj.offRect = obj.screenRect;
            obj.offwin  = Screen('OpenOffscreenWindow', obj.winPtr, obj.bgGrey, obj.offRect,32);
%            Screen('ColorRange', obj.offwin, 1, 0);  % <--- Disable clamping here too

            % ---- Choose strides ----
            Wdeg = (obj.screenRect(3)-obj.screenRect(1)) / obj.pixPerDeg;
            Hdeg = (obj.screenRect(4)-obj.screenRect(2)) / obj.pixPerDeg;
            [sx, sy, info] = pickHartleyStridesFromNs(Wdeg, Hdeg, obj.FmaxX_cpd, ...
                obj.FmaxY_cpd, obj.ns, 'equalStride', obj.equalStride);
            obj.strideKx = sx; obj.strideKy = sy;
            fprintf('Strides picked: sx=%d, sy=%d, nx=%d, ny=%d, N=%d, fx_step=%.3f, fy_step=%.3f\n', ...
                    sx, sy, info.nx, info.ny, info.N_total, info.fx_step, info.fy_step);

            obj.bank = obj.buildBank();
            obj.initGLAndShader();
            obj.bankReady = true;
        end

        function bank = buildBank(obj)
            Wdeg = RectWidth(obj.screenRect)/obj.pixPerDeg;
            Hdeg = RectHeight(obj.screenRect)/obj.pixPerDeg;

            Kx_max = floor(Wdeg * obj.FmaxX_cpd);
            Ky_max = floor(Hdeg * obj.FmaxY_cpd);
            kx_vals = -Kx_max:obj.strideKx:Kx_max;
            ky_vals = -Ky_max:obj.strideKy:Ky_max;
            [KX, KY] = ndgrid(kx_vals, ky_vals);
            KX = KX(:); KY = KY(:);
            keep = ~(KX==0 & KY==0);
            KX = KX(keep); KY = KY(keep);
            keepHalf = (KX > 0) | (KX==0 & KY > 0);
            KXh = KX(keepHalf); KYh = KY(keepHalf);
            KXp = [KXh ; -KXh];
            KYp = [KYh ; -KYh];
            fx = KXp / Wdeg; fy = KYp / Hdeg;
            sf = hypot(fx, fy); th = atan2(fy, fx);
            nH = numel(KXh); opp = [(nH+1):(2*nH), 1:nH]';
            bank = struct('fx', num2cell(fx), ...
                          'fy', num2cell(fy), ...
                          'kx', num2cell(KXp), ...
                          'ky', num2cell(KYp), ...
                          'sf', num2cell(sf), ...
                          'th', num2cell(th), ...
                          'ori', num2cell(rad2deg(mod(th, 2*pi))), ...
                          'opp', num2cell(opp));
        end

        function initGLAndShader(obj)
            if ~obj.gl_inited
                PsychDefaultSetup(2);
                obj.gl_inited = true;
            end
            [scriptPath, ~, ~] = fileparts(mfilename('fullpath'));
            if isempty(scriptPath), scriptPath = pwd; end
            obj.shader.vertFile = fullfile(scriptPath, 'Hyperplaid_Procedural.vert');
            obj.shader.fragFile = fullfile(scriptPath, 'Hyperplaid_Procedural.frag');

            % --- Vertex shader: fixed-function compatible ---
            fv = fopen(obj.shader.vertFile, 'w');
            fprintf(fv, [
                'varying vec2 uv;\n' ...
                'void main(void) {\n' ...
                '  vec2 pos = gl_Vertex.xy;\n' ...
                '  uv = pos * 0.5;  // now uv ∈ [−0.5, +0.5];\n' ... %uv = 0.5 * (pos + 1.0);\n' ...
                '  gl_Position = vec4(pos, 0.0, 1.0);\n' ...
                '}\n']);
            fclose(fv);

            % --- Fragment shader: mean-zero deviation ---
            ff = fopen(obj.shader.fragFile, 'w');
            fprintf(ff, [
                'uniform float kx;\n' ...
                'uniform float ky;\n' ...
                'uniform float signVal;\n' ...
                'uniform float amplitude;\n' ...
                'varying vec2 uv;\n' ...
                'const float PI = 3.1415926535;\n' ...
                'void main(void) {\n' ...
                '  float phase = 2.0 * PI * (kx * uv.x + ky * uv.y);\n' ...
                '  float cas = (cos(phase) + sin(phase)) * 0.7071067811865476;\n' ...
                '  float dev = amplitude * signVal * cas;\n' ...
                '  gl_FragColor = vec4(dev, dev, dev, 1.0);\n' ...
                '}\n']);
            fclose(ff);

            obj.shader.program = LoadGLSLProgramFromFiles({obj.shader.vertFile, obj.shader.fragFile});
            if obj.shader.program <= 0
                error('Failed to compile/link Hyperplaid shaders.');
            end
            glUseProgram(obj.shader.program);
            obj.shader.loc_kx   = glGetUniformLocation(obj.shader.program, 'kx');
            obj.shader.loc_ky   = glGetUniformLocation(obj.shader.program, 'ky');
            obj.shader.loc_sign = glGetUniformLocation(obj.shader.program, 'signVal');
            obj.shader.loc_amp  = glGetUniformLocation(obj.shader.program, 'amplitude');
            glUseProgram(0);
        end

        function beforeTrial(obj)
            obj.setRandomSeed();
            obj.frameUpdate = 0;
            if ~obj.bankReady
                obj.bank = obj.buildBank();
                obj.initGLAndShader();
                obj.bankReady = true;
            end
            obj.sampleComponents();
        end

        function reset(obj)
            obj.rng.reset();
            obj.frameUpdate = 0;
            obj.sampleComponents();
        end

        function sampleComponents(obj)
            C = numel(obj.bank)/2;
            if obj.uniquePerFrame
                baseIdx = randperm(obj.rng, C, obj.K);
            else
                baseIdx = randi(obj.rng, C, [1 obj.K]);
            end
            flip_K = rand(obj.rng, 1, obj.K) > 0.5;
            Idx = baseIdx;
            Idx(flip_K) = arrayfun(@(i) obj.bank(i).opp, baseIdx(flip_K));
            fx = arrayfun(@(i) obj.bank(i).fx, Idx);
            fy = arrayfun(@(i) obj.bank(i).fy, Idx);
            kx = arrayfun(@(i) obj.bank(i).kx, Idx);
            ky = arrayfun(@(i) obj.bank(i).ky, Idx);
            flip_amp = rand(obj.rng,1,obj.K) > 0.5;
            signA    = 1 - 2*double(flip_amp);
            sf  = hypot(fx, fy);
            ori = rad2deg(mod(atan2(fy, fx), 2*pi));
            obj.current.idx   = Idx;
            obj.current.fx    = fx;
            obj.current.fy    = fy;
            obj.current.kx    = kx;
            obj.current.ky    = ky;
            obj.current.sf    = sf;
            obj.current.ori   = ori;
            obj.current.phase = pi/4 * ones(1, obj.K);
            obj.current.amp   = double(signA) * obj.contrast / sqrt(max(obj.K,1));
            obj.frameUpdate = obj.updateEveryNFrames;
        end

        function beforeFrame(obj)
            % Draw directly into onscreen window (no offscreen FBO)
            % Equivalent additive accumulation on unclamped main framebuffer.

            % --- 1. Enter PTB's OpenGL context ---
            Screen('BeginOpenGL', obj.winPtr);

            % --- 2. Prepare viewport and clear to mid-gray ---
            glViewport(0, 0, RectWidth(obj.screenRect), RectHeight(obj.screenRect));
            glClearColor(obj.bgGrey, obj.bgGrey, obj.bgGrey, 1.0);
            glClear(hex2dec('00004000'));  % GL_COLOR_BUFFER_BIT

            % --- 3. Set additive blending for mean-zero deviations ---
            glEnable(obj.GL_BLEND);
            glBlendEquation(hex2dec('8006'));  % GL_FUNC_ADD
            glBlendFunc(obj.GL_ONE, obj.GL_ONE);  % additive: out = src + dst

            % --- 4. Use the compiled shader ---
            glUseProgram(obj.shader.program);

            for j = 1:obj.K
                ampMag = abs(obj.current.amp(j));
                sgn    = sign(obj.current.amp(j));
                if sgn == 0, sgn = 1; end  % safety

                % Pass uniforms
                glUniform1f(obj.shader.loc_kx,   obj.current.kx(j));
                glUniform1f(obj.shader.loc_ky,   obj.current.ky(j));
                glUniform1f(obj.shader.loc_sign, sgn);
                glUniform1f(obj.shader.loc_amp,  ampMag);

                % Full-screen quad in clip space (-1 to +1)
                glBegin(obj.GL_QUADS);
                glVertex2f(-1, -1);
                glVertex2f( 1, -1);
                glVertex2f( 1,  1);
                glVertex2f(-1,  1);
                glEnd;
            end

            % --- 5. Reset GL state for PTB ---
            glUseProgram(0);
            glDisable(obj.GL_BLEND);
            glFinish;
            Screen('EndOpenGL', obj.winPtr);

            % --- 6. Nothing else to draw, ready for Screen('Flip') ---
        end

        function afterFrame(obj)
            obj.frameUpdate = obj.frameUpdate - 1;
            if obj.frameUpdate <= 0
                obj.sampleComponents();
            end
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
            if isstruct(obj.shader)
                if isfield(obj.shader,'program') && obj.shader.program > 0
                    try Screen('Close', obj.shader.program); catch, end
                end
                if isfield(obj.shader,'vertFile') && exist(obj.shader.vertFile,'file'), delete(obj.shader.vertFile); end
                if isfield(obj.shader,'fragFile') && exist(obj.shader.fragFile,'file'), delete(obj.shader.fragFile); end
            end
            obj.shader = [];
            if ~isempty(obj.offwin) && obj.offwin>0
                Screen('Close', obj.offwin);
                obj.offwin = [];
            end
            Screen('ColorRange', obj.winPtr, obj.oldmaximumvalue, obj.oldclampcolors, obj.oldapplyToDoubleInputMakeTexture);
        end

        function I = getImage(obj, rect, binSize)
            if nargin < 2 || isempty(rect),    rect = obj.screenRect; end
            if nargin < 3 || isempty(binSize), binSize = 1; end
            w = RectWidth(obj.screenRect);
            h = RectHeight(obj.screenRect);
            [xPix, yPix] = meshgrid((1:w) - (w+1)/2, (1:h) - (h+1)/2);
            Xdeg =  xPix / obj.pixPerDeg;
            Ydeg = -yPix / obj.pixPerDeg;
            acc = zeros(h, w, 'double');
            for j = 1:obj.K
                fx  = obj.current.fx(j); fy = obj.current.fy(j);
                phi = obj.current.phase(j);
                acc = acc + sin(2*pi*(fx.*Xdeg + fy.*Ydeg) + phi) * (obj.current.amp(j));
            end
            Ilin = obj.bgGrey + acc;
            Ilin = min(max(Ilin, 0), 1);
            L = max(1, round(rect(1) - obj.screenRect(1) + 1));
            T = max(1, round(rect(2) - obj.screenRect(2) + 1));
            R = min(w, round(rect(3) - obj.screenRect(1)));
            B = min(h, round(rect(4) - obj.screenRect(2)));
            Ilin = Ilin(T:B, L:R);
            if binSize > 1
                Ilin = localBoxDownsample(Ilin, binSize);
            end
            I = uint8(round(Ilin * 255));
        end

        function row = currentLogRowNumeric(obj, whenTimestamp)
            if nargin<2, whenTimestamp = NaN; end
            t   = double(whenTimestamp);
            K   = double(obj.K);
            fx  = double(obj.current.fx(:)).';
            fy  = double(obj.current.fy(:)).';
            amp = double(obj.current.amp);
            idx = double(obj.current.idx(:)).';
            row = [t, K, fx, fy, amp, idx];
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


function [sx, sy, infoAll] = pickHartleyStridesFromNs(Wdeg,Hdeg,FmaxX,FmaxY,ns,varargin)
% pickHartleyStridesFromNs
% ------------------------------------------------------------
% Determine integer lattice strides (sx, sy) for the Hartley frequency basis,
% optionally apply a radial cutoff and/or generate log-spaced radial samples
% snapped to the integer lattice.
%
% INPUTS
%   Wdeg,Hdeg   : Screen width / height (deg)
%   FmaxX,FmaxY : Max spatial-frequency limits (cycles/deg)
%   ns          : Approx lattice samples per axis
%                 - finite → coarse grid of ~ns × ns
%                 - Inf    → full integer lattice (stride = 1)
%
% OPTIONAL PARAMETERS
%   'equalStride' (logical, default=false)
%   'FmaxRadial' (scalar, optional) – circular cutoff in cpd
%   'compareNs'  (vector) – sweep these ns values for diagnostics
%   'logRadial'  (struct) – generate log-spaced radial rings snapped to grid
%        fields: .Rmin, .Rmax (cpd), .nR (number of rings, default 6)
%                .nTheta (angles per ring, default 12)
%
% OUTPUTS
%   sx, sy   : chosen strides
%   infoAll  : struct array of lattice metadata for each ns tested
%
% EXAMPLE
%   [sx,sy,info] = pickHartleyStridesFromNs(51.3,28.9,8,8,[Inf 25],'equalStride',true,...
%                     'FmaxRadial',8,'logRadial',struct('Rmin',0.5,'Rmax',8,'nR',6,'nTheta',16));
%
% AUTHOR
%   2025 Declan & GPT-5 lab utilities, UCLA Huk Lab

% ------------------ Parse options ------------------
p = inputParser;
addParameter(p,'equalStride',false,@islogical);
addParameter(p,'FmaxRadial',[],@(x) isempty(x)||isscalar(x));
addParameter(p,'compareNs',[],@(x) isnumeric(x));
addParameter(p,'logRadial',[],@(x) isstruct(x)||isempty(x));
parse(p,varargin{:});
opt = p.Results;

if isempty(opt.compareNs), nsList = ns; else, nsList = opt.compareNs(:)'; end

% ------------------ Integer frequency caps ------------------
Kx_max = floor(Wdeg*FmaxX);
Ky_max = floor(Hdeg*FmaxY);

fprintf('Hartley lattice diagnostics:\n');
fprintf('  Screen %.2f°×%.2f°, Fmax=%.2f×%.2f cpd\n',Wdeg,Hdeg,FmaxX,FmaxY);
fprintf('  Kx_max=%d, Ky_max=%d\n',Kx_max,Ky_max);

infoAll = struct([]);

for idx = 1:numel(nsList)
    ns = nsList(idx);

    % -------- Pick strides --------
    if isinf(ns)
        sx = 1; sy = 1; mode = 'full';
    else
        m = max(1,(ns-1)/2);
        sxCand = max(1,floor(Kx_max./m)):max(1,ceil(Kx_max./(m+1)));
        syCand = max(1,floor(Ky_max./m)):max(1,ceil(Ky_max./(m+1)));
        bestErr = Inf;
        for sx_ = sxCand
            for sy_ = syCand
                fx_step = sx_/Wdeg; fy_step = sy_/Hdeg;
                err = abs(log(fx_step/fy_step));
                if err<bestErr
                    bestErr=err; sx=sx_; sy=sy_;
                end
            end
        end
        mode = 'sampled';
    end

    % -------- Equal-stride enforcement --------
    if opt.equalStride
        step_cpd = min(sx/Wdeg, sy/Hdeg);
        sx = max(1,round(step_cpd*Wdeg));
        sy = max(1,round(step_cpd*Hdeg));
        mode = [mode '_equal'];
    end

    % -------- Derived grid --------
    fx_step = sx/Wdeg; fy_step = sy/Hdeg;
    nx = 2*floor(Kx_max/sx)+1;
    ny = 2*floor(Ky_max/sy)+1;
    N_total = nx*ny - 1;

    % -------- Apply radial cutoff --------
    kx = (-floor(nx/2):floor(nx/2))*sx;
    ky = (-floor(ny/2):floor(ny/2))*sy;
    [KX,KY] = meshgrid(kx/Wdeg, ky/Hdeg);
    R = sqrt(KX.^2 + KY.^2);
    if ~isempty(opt.FmaxRadial)
        mask = R <= opt.FmaxRadial;
        N_disk = nnz(mask) - 1;
    else
        mask = true(size(R));
        N_disk = NaN;
    end

    % -------- Optional log-radial snapped sampling --------
    if ~isempty(opt.logRadial)
        lr = opt.logRadial;
        if ~isfield(lr,'nR'), lr.nR=6; end
        if ~isfield(lr,'nTheta'), lr.nTheta=12; end
        rhoTarget = logspace(log10(lr.Rmin),log10(lr.Rmax),lr.nR);
        theta = linspace(0,pi,lr.nTheta);  % half-plane
        coords = [];
        uppergrace=10^(log10(lr.Rmax)+median(diff(log10(rhoTarget)))/2);
        for r = rhoTarget
            for t = theta
                fx = r*cos(t); fy = r*sin(t);
                kx_snap = round(fx*Wdeg); ky_snap = round(fy*Hdeg);
                fx_hat = kx_snap/Wdeg; fy_hat = ky_snap/Hdeg;
                rho_hat = sqrt(fx_hat^2 + fy_hat^2);
                th_hat = atan2(fy_hat,fx_hat);
                if (kx_snap==0 && ky_snap==0), continue; end
                if rho_hat<=uppergrace && rho_hat>=lr.Rmin
                    coords(end+1,:) = [fx_hat, fy_hat, rho_hat, th_hat]; %#ok<AGROW>
                end
            end
        end
        coords = unique(round(coords,6),'rows');  % dedupe
        N_log = size(coords,1);
    else
        coords = [];
        N_log = NaN;
    end

    % -------- Store --------
    infoAll{idx} = struct('sx',sx,'sy',sy,'mode',mode,...
        'fx_step',fx_step,'fy_step',fy_step,...
        'nx',nx,'ny',ny,'N_total',N_total,'N_disk',N_disk,...
        'logCoords',coords,'N_log',N_log);
end

% ------------------ Print summary ------------------
fprintf('\n%-8s %-4s %-4s %-6s %-6s %-6s %-6s %-8s %-8s %-8s\n',...
    'ns','sx','sy','nx','ny','Δfx','Δfy','Ntotal','Ndisk','Nlog');
for idx=1:numel(infoAll)
    a=infoAll{idx};
    fprintf('%-8g %-4d %-4d %-6d %-6d %-6.3f %-6.3f %-8d %-8.0f %-8.0f\n',...
        nsList(idx),a.sx,a.sy,a.nx,a.ny,a.fx_step,a.fy_step,...
        a.N_total,a.N_disk,a.N_log);
end
fprintf('\n');
end