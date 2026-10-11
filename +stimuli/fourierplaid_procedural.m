classdef fourierplaid_procedural < stimuli.hartleyplaid_procedural
% Random-phase Fourier hyperplaid on the existing Hartley frequency lattice.
%
% The inherited constructor, stride picker, and bank builder define exactly
% the same spectral lattice and coordinate sampler as noise type 14. This
% subclass changes only the component phase convention and renderer.

    properties
        schemaVersion = 'fourierplaid_v1'
        phaseConvention = 'cos(2*pi*(kx*u+ky*v)+phaseRad)'
        trialSeed = NaN
        trialInitialState = []
    end

    methods
        function obj = fourierplaid_procedural(winPtr, varargin)
            obj = obj@stimuli.hartleyplaid_procedural(winPtr, varargin{:});
        end

        function initGLAndShader(obj)
            if ~obj.gl_inited
                PsychDefaultSetup(2);
                obj.gl_inited = true;
            end

            [scriptPath, ~, ~] = fileparts(mfilename('fullpath'));
            if isempty(scriptPath), scriptPath = pwd; end
            obj.shader.vertFile = fullfile(scriptPath, 'fourierplaid_procedural.vert');
            obj.shader.fragFile = fullfile(scriptPath, 'fourierplaid_procedural.frag');
            if ~exist(obj.shader.vertFile, 'file') || ~exist(obj.shader.fragFile, 'file')
                error('The committed fourierplaid shader files are missing.');
            end

            obj.shader.program = LoadGLSLProgramFromFiles( ...
                {obj.shader.vertFile, obj.shader.fragFile});
            if obj.shader.program <= 0
                error('Failed to compile/link fourierplaid shaders.');
            end
            glUseProgram(obj.shader.program);
            obj.shader.loc_kx    = glGetUniformLocation(obj.shader.program, 'kx');
            obj.shader.loc_ky    = glGetUniformLocation(obj.shader.program, 'ky');
            obj.shader.loc_phase = glGetUniformLocation(obj.shader.program, 'phaseRad');
            obj.shader.loc_amp   = glGetUniformLocation(obj.shader.program, 'amplitude');
            glUseProgram(0);
        end

        function beforeTrial(obj)
            % One ordinary stream is used sequentially for all draws. The
            % explicit history, not an attempt at cross-condition matching,
            % is the source of truth for the displayed sequence.
            obj.setRandomSeed();
            obj.trialSeed = obj.rng.Seed;
            obj.trialInitialState = obj.rng.State;
            obj.frameUpdate = 0;
            if ~obj.bankReady
                obj.bank = obj.buildBank();
                obj.initGLAndShader();
                obj.bankReady = true;
            end
            obj.sampleComponents();
        end

        function sampleComponents(obj)
            nAxes = numel(obj.bank)/2;
            if obj.K > nAxes && obj.uniquePerFrame
                error('K exceeds the number of unique Fourier axes in the bank.');
            end
            if obj.uniquePerFrame
                baseIdx = randperm(obj.rng, nAxes, obj.K);
            else
                baseIdx = randi(obj.rng, nAxes, [1 obj.K]);
            end

            chooseOpposite = rand(obj.rng, 1, obj.K) > 0.5;
            idx = baseIdx;
            idx(chooseOpposite) = arrayfun( ...
                @(i) obj.bank(i).opp, baseIdx(chooseOpposite));

            fx = arrayfun(@(i) obj.bank(i).fx, idx);
            fy = arrayfun(@(i) obj.bank(i).fy, idx);
            kx = arrayfun(@(i) obj.bank(i).kx, idx);
            ky = arrayfun(@(i) obj.bank(i).ky, idx);

            obj.current.idx   = idx;
            obj.current.fx    = fx;
            obj.current.fy    = fy;
            obj.current.kx    = kx;
            obj.current.ky    = ky;
            obj.current.sf    = hypot(fx, fy);
            obj.current.ori   = rad2deg(mod(atan2(fy, fx), 2*pi));
            obj.current.phase = 2*pi*rand(obj.rng, 1, obj.K);
            obj.current.amp   = ones(1, obj.K) * ...
                obj.contrast / sqrt(max(obj.K, 1));
            obj.frameUpdate = obj.updateEveryNFrames;
        end

        function beforeFrame(obj)
            Screen('BeginOpenGL', obj.winPtr);
            glViewport(0, 0, RectWidth(obj.screenRect), RectHeight(obj.screenRect));
            glClearColor(obj.bgGrey, obj.bgGrey, obj.bgGrey, 1.0);
            glClear(hex2dec('00004000')); % GL_COLOR_BUFFER_BIT

            glEnable(obj.GL_BLEND);
            glBlendEquation(hex2dec('8006')); % GL_FUNC_ADD
            glBlendFunc(obj.GL_ONE, obj.GL_ONE);
            glUseProgram(obj.shader.program);

            for j = 1:obj.K
                glUniform1f(obj.shader.loc_kx, obj.current.kx(j));
                glUniform1f(obj.shader.loc_ky, obj.current.ky(j));
                glUniform1f(obj.shader.loc_phase, obj.current.phase(j));
                glUniform1f(obj.shader.loc_amp, obj.current.amp(j));
                glBegin(obj.GL_QUADS);
                glVertex2f(-1, -1);
                glVertex2f( 1, -1);
                glVertex2f( 1,  1);
                glVertex2f(-1,  1);
                glEnd;
            end

            glUseProgram(0);
            glDisable(obj.GL_BLEND);
            glFinish;
            Screen('EndOpenGL', obj.winPtr);
            Screen(obj.winPtr, 'BlendFunction', GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        end

        function I = getImage(obj, rect, binSize)
            if nargin < 2 || isempty(rect), rect = obj.screenRect; end
            if nargin < 3 || isempty(binSize), binSize = 1; end
            w = RectWidth(obj.screenRect);
            h = RectHeight(obj.screenRect);
            [xPix, yPix] = meshgrid((1:w)-(w+1)/2, (1:h)-(h+1)/2);
            Xdeg = xPix / obj.pixPerDeg;
            Ydeg = -yPix / obj.pixPerDeg;
            acc = zeros(h, w, 'double');
            for j = 1:obj.K
                theta = 2*pi*(obj.current.fx(j).*Xdeg + ...
                    obj.current.fy(j).*Ydeg) + obj.current.phase(j);
                acc = acc + obj.current.amp(j)*cos(theta);
            end
            Ilin = min(max(obj.bgGrey + acc, 0), 1);
            L = max(1, round(rect(1)-obj.screenRect(1)+1));
            T = max(1, round(rect(2)-obj.screenRect(2)+1));
            R = min(w, round(rect(3)-obj.screenRect(1)));
            B = min(h, round(rect(4)-obj.screenRect(2)));
            Ilin = Ilin(T:B, L:R);
            if binSize > 1
                hh = floor(size(Ilin,1)/binSize)*binSize;
                ww = floor(size(Ilin,2)/binSize)*binSize;
                Ilin = Ilin(1:hh,1:ww);
                Ilin = reshape(Ilin, binSize, hh/binSize, binSize, ww/binSize);
                Ilin = squeeze(mean(mean(Ilin,1),3));
            end
            I = uint8(round(Ilin*255));
        end

        function row = currentLogRowNumeric(obj, whenTimestamp)
            if nargin < 2, whenTimestamp = NaN; end
            row = [double(whenTimestamp), double(obj.K), ...
                double(obj.current.fx(:)).', double(obj.current.fy(:)).', ...
                double(obj.current.phase(:)).', double(obj.current.amp(:)).', ...
                double(obj.current.idx(:)).'];
        end

        function CloseUp(obj)
            % Shader sources are committed assets and must not be deleted.
            if ~isempty(obj.texHandles)
                for k = 1:numel(obj.texHandles)
                    if obj.texHandles(k) > 0
                        Screen('Close', obj.texHandles(k));
                    end
                end
            end
            obj.texHandles = [];
            obj.bankReady = false;
            if isstruct(obj.shader) && isfield(obj.shader, 'program') && ...
                    obj.shader.program > 0
                try Screen('Close', obj.shader.program); catch, end
            end
            obj.shader = [];
            try
                Screen('ColorRange', obj.winPtr, obj.oldmaximumvalue, ...
                    obj.oldclampcolors, obj.oldapplyToDoubleInputMakeTexture);
            catch
            end
        end
    end
end
