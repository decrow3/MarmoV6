%% Open screen (test settings)
Screen('Preference','SkipSyncTests', 1);
AssertOpenGL;
bg = 127;
[win, winRect] = Screen('OpenWindow', max(Screen('Screens')), bg);
HideCursor(win);

% Geometry & units
pixPerDeg = 60;
W = RectWidth(winRect);
H = RectHeight(winRect);
diagPix = W;%ceil(hypot(W,H));  % big square so any rotation would still cover
texRect = CenterRectOnPointd([0 0 diagPix diagPix], W/2, H/2);

% Stim parameters: vertical bars = sinusoid along X only
sf_cpd  = 0.5;              % cycles/deg
freq_cpp= sf_cpd / pixPerDeg;   % cycles/pixel
phase   = pi/2;                % radians
contrast= 0.4;              % per-component amplitude (K=1)

% Create procedural sine with zero base (we draw bg once)
tex = CreateProceduralSineGrating(win, diagPix, diagPix, [0 0 0 0]);

% --- GPU draw (ground truth) ---
% 1) draw background once
Screen('FillRect', win, bg);

% 2) additive blending for the sinusoid
Screen('BlendFunction', obj.winPtr, GL_ONE, GL_ONE);

% rotationAngle = 0  => horizontal carrier (varies along X) => vertical bars
aux = [phase, freq_cpp, contrast, 1];
Screen('DrawTexture', win, tex, [], texRect, 0, [], [], [], [], [], aux);

% restore blending
Screen('BlendFunction', win, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

% Flip and grab image
vbl = Screen('Flip', win);
gpuImg = Screen('GetImage', win);  % uint8 RGB

% Convert to luminance plane for comparison
gpuLum = gpuImg(:,:,1);

% --- CPU renderer for the same frame ---
% Build pixel grid in *degrees* with y up
[xPix, yPix] = meshgrid( (1:W) - W/2, (1:H)' - H/2 );
Xdeg =  xPix / pixPerDeg;
% Ydeg = -yPix / pixPerDeg;   % not needed for vertical bars

% Sine varies only along X; PTB shader uses sine as well
twopi = 2*pi;
acc   = sin( twopi*sf_cpd*Xdeg + phase +pi/2);

% Add background once, amplitude = contrast (K=1)
Ilin  = (bg/255) + contrast * acc;
Ilin  = min(max(Ilin,0),1);
cpuLum = uint8(round(Ilin*255));

%%
subplot(221)
imagesc(gpuLum(:,:)); axis equal tight
subplot(222)
imagesc(cpuLum(:,:)); axis equal tight
subplot(223)
imagesc(gpuLum((240-40):(240+40),(320-40):(320+40))); axis equal tight
subplot(224)
imagesc(cpuLum((240-40):(240+40),(320-40):(320+40))); axis equal tight
colormap(gray)

%%

% --- Compare ---
mae = mean(abs(double(cpuLum(:)) - double(gpuLum(:))));
fprintf('Vertical full-field: MAE = %.4f (expect ~0)\n', mae);


% Show CPU image for sanity (optional)
% texCPU = Screen('MakeTexture', win, repmat(cpuLum,[1 1 3]));
% Screen('DrawTexture', win, texCPU, [], winRect);
% Screen('Flip', win); KbStrokeWait;

% Cleanup
Screen('Close', tex);
% Screen('Close', texCPU);
sca;
