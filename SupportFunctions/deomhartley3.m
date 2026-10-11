% Setup a small test window:
Screen('Preference','SkipSyncTests',1);
S = MarmoViewRigSettings;  % your rig helper
S.screenRect = [0 0 641 481];
A = marmoview.openScreen(S);

% Build a hyperplaid in PROCEDURAL mode (fast):
hp = stimuli.hyperplaid_static(A.window, ...
    'screenRect', S.screenRect, ...
    'pixPerDeg', S.pixPerDeg, ...
    'frameRate', 60, ...
    'spatialFrequencies', 2, ...
    'K', 6, ...
    'updateEveryNFrames',1,...
    'contrast', 0.4);


hp.beforeTrial();
hp.stimValue = 1;

for f = 1:10
    hp.beforeFrame();
    vbl = Screen('Flip', A.window);
    % Log numeric row:
    row = hp.currentLogRowNumeric(vbl);
    % store row as needed in your protocol...



    %
    % After a Screen('Flip'), capture the on-screen image:
    gpuFrame = mean(Screen('GetImage', A.window, S.screenRect, [], 0),3); % no float

    % CPU render the same frame:
    cpuFrame = hp.getImage(S.screenRect, 1); % your hyperplaid_static instance

    % Compare mean absolute error (on a linearized pipeline they should match up to rounding):
    mae = mean(abs(double(gpuFrame(:)) - double(cpuFrame(:))));
    fprintf('GPU/CPU MAE: %.3f (expected ~<= 1 LSB)\n', mae);

    hp.afterFrame(); %update
    %
    figure(2)
    subplot(221)
    imagesc(gpuFrame(:,:)); axis equal tight
    subplot(222)
    imagesc(cpuFrame(:,:)); axis equal tight
    subplot(223)
    imagesc(gpuFrame((240-10):(240+10),(320-10):(320+10))); axis equal tight
    subplot(224)
    imagesc(cpuFrame((240-10):(240+10),(320-10):(320+10))); axis equal tight
    colormap(gray)

    pause(1)
end



%%
n = 10; maes = zeros(1,n);
for k = 1:n
    [gpu,cpu] = grab_frames(hp,S);
    maes(k) = mean(abs(double(gpu(:)) - double(cpu(:))));
end
fprintf('GPU/CPU MAE (mean±sd): %.3f ± %.3f LSB\n', mean(maes), std(maes));


%%
% Force K=1, pick a specific atom
hp.K = 1;
hp.sampleComponents();
j = 1;  % only one

% Build four variants by toggling ±k (phase: −π/4 or −3π/4) and ±amp:
phases = [-pi/4, -3*pi/4,  pi/4,  3*pi/4];   % the four cas phases realizable
amps   = [ 1,      1,     -1,     -1     ] * (hp.contrast / sqrt(hp.K));

% CPU-only eval at center pixel (exactly centered grid!)
w = RectWidth(hp.screenRect); h = RectHeight(hp.screenRect);
cx = (w+1)/2; cy = (h+1)/2;
bg = 127;
for t = 1:4
    phi = phases(t); a = amps(t);
    center = bg + 255*(a * sin(phi));
    fprintf('phi=% .2f rad : center = %.2f LSB (bg=%d)\n', phi, center, bg);
end

%%
hp.K = 2;

% Pick one base atom index from the +k half-plane:
C = numel(hp.bank)/2;                   % base half
i = randi(C);
hp.current.idx = [i i];                 % same texture twice
hp.current.phase = [-pi/4 -pi/4];       % same phase family
hp.current.fx=[hp.current.fx hp.current.fx];
hp.current.fy=[hp.current.fy hp.current.fy];
hp.current.amp   = [ hp.contrast/sqrt(2), -hp.contrast/sqrt(2) ]; % equal & opposite
hp.frameUpdate = 1;

[gpu,cpu] = grab_frames(hp,S);
bg = 127;
dev = mean(abs(double(gpu(:))-bg));
fprintf('Cancel test: mean |dev| = %.3f LSB (want ~0)\n', dev);

%% RMS vs. K (tight-frame property ⇒ ~constant)
%Because each component has amp = contrast/√K and the sine RMS is 1/√2, the total RMS should be ≈ contrast/√2 (independent of K).
bg = 127;
Ks = [1 2 4 6 8 12];
for K = Ks
    hp.K = K; hp.sampleComponents();
    [gpu,~] = grab_frames(hp,S);
    r = rms_img(gpu, bg);
    r_theory = (hp.contrast/sqrt(2))*255;
    fprintf('K=%2d: RMS = %.2f LSB  (theory ~ %.2f)\n', K, r, r_theory);
end
%% Mean luminance stability
hp.K = 6;  n = 12; means = zeros(1,n);
for k=1:n
    hp.sampleComponents();
    [gpu,~] = grab_frames(hp,S);
    means(k) = mean_img(gpu);
end
fprintf('Mean luminance: %.2f ± %.2f LSB (bg=%d)\n', mean(means), std(means), 127);

%% FFT peak matches bank (K=1)
hp.K = 1; hp.sampleComponents();
[gp,~] = grab_frames(hp,S);
I = double(gp) - 127;

% 2D FFT & peak:
F = fftshift(abs(fft2(I)));
[~,imax] = max(F(:)); [py,px] = ind2sub(size(F), imax);

% Convert fft bin to cycles/deg:
[h,w] = size(I);
% frequency grid in cycles/pixel:
fx_pp = (px - (w+1)/2) / w;  fy_pp = (py - (h+1)/2) / h;
% cycles/deg:
fx_cpd = fx_pp * (S.pixPerDeg);  fy_cpd = fy_pp * (S.pixPerDeg);

% Chosen component from bank:
idx = hp.current.idx(1);
fprintf('FFT peak (%.3f, %.3f) c/deg vs bank (%.3f, %.3f)\n', ...
        fx_cpd, fy_cpd, hp.current.fx(1), hp.current.fy(1));

%% −k partner integrity
C = numel(hp.bank)/2;
ii = randi(C, [1 10]);
ok = true;
for i = ii
    j = hp.bank(i).opp;
    ok = ok & (abs(hp.bank(j).fx + hp.bank(i).fx) < 1e-12) ...
           & (abs(hp.bank(j).fy + hp.bank(i).fy) < 1e-12) ...
           & (hp.bank(j).opp == i);
end
assert(ok, 'Opposite -k not a perfect negation or pairing failed.');
disp('opp mapping OK.');

%% Shift-vs-phase (CPU check) A spatial shift (Δx,Δy) deg should add phase 2π(fxΔx+fyΔy).
hp.K = 1; hp.sampleComponents();
% Render baseline CPU:
I0 = double(hp.getImage(S.screenRect,1)) - 127;

% Simulate “phase added” image via CPU formula:
w = RectWidth(hp.screenRect); h = RectHeight(hp.screenRect);
[xPix,yPix] = meshgrid((1:w)-(w+1)/2, (1:h)-(h+1)/2);
Xdeg =  xPix / hp.pixPerDeg;  Ydeg = -yPix / hp.pixPerDeg;

fx = hp.current.fx(1); fy = hp.current.fy(1);
phi = hp.current.phase(1);   amp = hp.current.amp(1);

% Pick a small spatial shift:
dx_deg = 1/hp.pixPerDeg; dy_deg = 0;  % shift by 1 px to the right
Ishift = 127 + 255*amp * sin(2*pi*(fx*(Xdeg-dx_deg) + fy*(Ydeg-dy_deg)) + phi);

% Equivalent “phase add”:
dphi = 2*pi*(fx*dx_deg + fy*dy_deg);
Iphi  = 127 + 255*amp * sin(2*pi*(fx*Xdeg + fy*Ydeg) + phi + dphi);

fprintf('shift-vs-phase MAE: %.3f LSB\n', mean(abs(Ishift(:)-Iphi(:))));



%%
% % Lock a single atom of your choice:
% i = 100;                          % pick an index in bank
% hp.K = 1;
% hp.current.idx     = i;
% hp.current.fx      = hp.bank(i).fx;
% hp.current.fy      = hp.bank(i).fy;
% hp.current.phiSent = pi/2;        % test phase
% hp.current.amp     = 0.2;
% hp.frameUpdate     = inf;         % <- prevents automatic resample
% 
% % Now draw without changing current:
% Screen('FillRect', hp.winPtr, hp.bgGrey);
% Screen('BlendFunction', hp.winPtr, GL_ONE, GL_ONE);
% hp.beforeFrame();                 % uses current.* as-is
% vbl = Screen('Flip', hp.winPtr); %#ok<NASGU>
% 
% 
% 
% %%
% % Pick one atom i:
% i = hp.current.idx(1);  % or set hp.current to that atom explicitly
% hp.K = 1; hp.current.idx = i;
% hp.current.fx = hp.bank(i).fx; hp.current.fy = hp.bank(i).fy;
% hp.current.amp = 0.2;
% 
% for phi = [pi/2, -pi/2, 0, pi]
%   hp.current.phiSent = phi;
%   Screen('FillRect', hp.winPtr, hp.bgGrey); Screen('BlendFunction', hp.winPtr, GL_ONE, GL_ONE);
%   hp.beforeFrame(); 
%   vbl = Screen('Flip', hp.winPtr); %#ok<NASGU>
%   G = mean(Screen('GetImage', hp.winPtr, hp.screenRect, [], 0),3);
%   pause(.1)
% 
%   [h,w] = deal(RectHeight(hp.screenRect), RectWidth(hp.screenRect));
%   c = [floor(h/2)+1, floor(w/2)+1];
%   fprintf('phi=%.2f: center = %.2f (bg=%d)\n', phi, G(c(1),c(2)), hp.bgGrey);
%   cpuFrame = hp.getImage(S.screenRect, 1); % your hyperplaid_static instance
%   fprintf('phi=%.2f: center for cpu = %.2f (bg=%d)\n', phi, cpuFrame(c(1),c(2)), hp.bgGrey);
% end
% 
% amp = hp.contrast / sqrt(hp.K);
% pred = hp.bgGrey - 255 * amp / sqrt(2);
% G = mean(Screen('GetImage', hp.winPtr, hp.screenRect, [], 0),3);
% [h,w] = size(G); c = [floor(h/2)+1, floor(w/2)+1];
% meas = double(G(c(1),c(2)));
% fprintf('Center: measured %.2f  predicted %.2f  (Δ=%.2f)\n', meas, pred, meas - pred);
% 
% 
% 
% %% interrogate the getimage for what is happening
% rect = hp.screenRect; 
% binSize = 1; 
% 
% w = RectWidth(hp.screenRect);
% h = RectHeight(hp.screenRect);
% cx = (hp.screenRect(1) + hp.screenRect(3)) / 2;
% cy = (hp.screenRect(2) + hp.screenRect(4)) / 2;
% 
% % [xPix, yPix] = meshgrid( (1:w) + hp.screenRect(1) - cx, ...
% %                          (1:h)' + hp.screenRect(2) - cy );
% [xpix, ypix] = meshgrid( (1:w) - (w+1)/2, ...
%                          (1:h) - (h+1)/2 );
% Xdeg =  xPix / hp.pixPerDeg;
% Ydeg = -yPix / hp.pixPerDeg;
% 
% acc = zeros(h, w, 'double');
% for j = 1:hp.K
%     fx = hp.current.fx(j); fy = hp.current.fy(j);
%     phi = hp.current.phiSent(j);
%     acc = acc + sin( 2*pi*(fx.*Xdeg + fy.*Ydeg) + phi );
% end
% 
% Ilin = (double(hp.bgGrey)/255) + (hp.current.amp) * acc;
% Ilin = min(max(Ilin, 0), 1);
% 
% L = max(1, round(rect(1) - hp.screenRect(1) + 1));
% T = max(1, round(rect(2) - hp.screenRect(2) + 1));
% R = min(w, round(rect(3) - hp.screenRect(1)));
% B = min(h, round(rect(4) - hp.screenRect(2)));
% Ilin = Ilin(T:B, L:R);
% 
% if binSize > 1
%     Ilin = localBoxDownsample(Ilin, binSize);
% end
% I = uint8(round(Ilin * 255));
% 
% 
% %%
% 
% hp.K = 2; hp.current.amp = 0.2;
% hp.current.idx = [i i];
% hp.current.fx  = [hp.bank(i).fx hp.bank(i).fx];
% hp.current.fy  = [hp.bank(i).fy hp.bank(i).fy];
% hp.current.phiSent = [0, pi];    % opposite phase
% 
% Screen('FillRect', hp.winPtr, hp.bgGrey); Screen('BlendFunction', hp.winPtr, GL_ONE, GL_ONE);
% hp.beforeFrame(); vbl = Screen('Flip', hp.winPtr);
% G = mean(Screen('GetImage', hp.winPtr, hp.screenRect, [], 0),3);
% fprintf('cancel test: mean dev = %.3f LSB\n', mean(abs(double(G(:))-hp.bgGrey)));
% 
% %%
% 
% Klist = [1 2 4 6 8];
% for K = Klist
%   hp.K = K; hp.sampleComponents();
%   rmsVals = zeros(1,50);
%   for t=1:50
%     hp.beforeFrame(); vbl = Screen('Flip', hp.winPtr);
%     G = mean(Screen('GetImage', hp.winPtr, hp.screenRect, [], 0),3);
%     dev = double(G) - hp.bgGrey;
%     rmsVals(t) = std(dev(:));   % LSB
%     hp.afterFrame();
%   end
%   fprintf('K=%d: mean RMS %.2f LSB, expected ~ %.2f LSB\n', K, mean(rmsVals), 255*hp.contrast);
% end
% 
% %%
% hp.K=1; hp.sampleComponents(); hp.current.phiSent=0; hp.beforeFrame(); Screen('Flip', hp.winPtr);
% G = mean(Screen('GetImage', hp.winPtr, hp.screenRect, [], 0),3);
% dev = double(G)-hp.bgGrey; [H,W] = size(dev);
% F = fftshift(fft2(dev));
% 
% % Find dominant bin:
% [~,lin] = max(abs(F(:)));
% [kv,ku] = ind2sub(size(F), lin);
% % Convert bins to cyc/deg
% ppd = hp.pixPerDeg; Wdeg=W/ppd; Hdeg=H/ppd;
% fx_est = (ku-(W/2+1))/Wdeg; fy_est = (kv-(H/2+1))/Hdeg;
% fprintf('FFT peak (%.3f, %.3f) c/deg vs bank (%.3f, %.3f)\n', fx_est, fy_est, hp.current.fx, hp.current.fy);
% 
% %%
% for K=[1 3 6 12]
%   hp.K=K; hp.sampleComponents();
%   hp.beforeFrame(); Screen('Flip', hp.winPtr);
%   G = mean(Screen('GetImage', hp.winPtr, hp.screenRect, [], 0),3);
%   fprintf('K=%2d mean = %.2f (bg=%d)\n', K, mean(G(:)), hp.bgGrey);
% end
% 
% %%
% hp.K=1; hp.sampleComponents(); hp.current.amp=0.2;
% fx=hp.current.fx; fy=hp.current.fy;
% 
% dx=0.25; dy=-0.125;              % deg
% dphi = 2*pi*(fx*dx + fy*dy);
% 
% % Frame A
% hp.current.phiSent = 0; hp.beforeFrame(); Screen('Flip', hp.winPtr);
% GA = mean(Screen('GetImage', hp.winPtr, hp.screenRect, [], 0),3);
% 
% % Frame B: same phi but shift image numerically by Δx,Δy:
% shiftPixX = round(dx*hp.pixPerDeg); shiftPixY = -round(dy*hp.pixPerDeg);
% GB = circshift(GA, [shiftPixY, shiftPixX]);
% 
% % Frame C: no spatial shift, but phase-advanced:
% hp.current.phiSent = dphi; hp.beforeFrame(); Screen('Flip', hp.winPtr);
% GC = mean(Screen('GetImage', hp.winPtr, hp.screenRect, [], 0),3);
% 
% fprintf('shift-vs-phase MAE: %.3f LSB\n', mean(abs(double(GB(:))-double(GC(:)))));
% 
% %%
% % Find an atom and its opposite
% [~,i] = max([hp.bank.sf]);   % pick a high sf atom
% fx = hp.bank(i).fx; fy = hp.bank(i).fy;
% j = find(abs([hp.bank.fx] + fx) < 1e-6 & abs([hp.bank.fy] + fy) < 1e-6, 1);
% 
% assert(~isempty(j),'Opposite -k not found in bank!');
% 
% % Render both at same φ and compare signals: they differ by a sign flip when φ differs by π.
% 
% %%
% fx = [hp.bank.fx]; fy = [hp.bank.fy];
% assert(numel(fx) == hp.ns^2 - 1);
% dFx = sort(unique(round(diff(sort(unique(fx))),3)));
% dFy = sort(unique(round(diff(sort(unique(fy))),3)));
% fprintf('Δfx unique ~ %s  |  Δfy unique ~ %s\n', mat2str(dFx), mat2str(dFy));




%%
% ori = 33; sf = 3.2; phi = 1.1; K = 1;
% hp.current.ori     = ori;
% hp.current.sf      = sf;
% hp.current.phiSent = phi;
% hp.current.amp     = 0.2;
% hp.K               = K;
%
% % GPU
% Screen('FillRect', hp.winPtr, hp.bgGrey);
% Screen('BlendFunction', hp.winPtr, GL_ONE, GL_ONE);
% aux = [phi, sf/hp.pixPerDeg, hp.current.amp, 1];
% Screen('DrawTexture', hp.winPtr, hp.tex, [], hp.screenRect, ori, [], [], [], [], [], aux);
% vbl = Screen('Flip', hp.winPtr); %#ok<NASGU>
% %gpu = Screen('GetImage', hp.winPtr, hp.screenRect);
% %%
% gpuFrame = mean(Screen('GetImage', hp.winPtr, hp.screenRect, [], 0),3); % no float
% % CPU
% cpuFrame = hp.getImage(hp.screenRect, 1);
%
% fprintf('MAE = %.4f\n', mean(abs(double(gpuFrame(:)) - double(cpuFrame(:)))) );



%% ------------------ helpers
function [gpu8,cpu8] = grab_frames(hp, S)
    % Draw once on GPU and grab image (LDR 8-bit), then CPU render
    hp.beforeFrame();
    vbl = Screen('Flip', hp.winPtr); %#ok<NASGU>
    gpu8 = mean(Screen('GetImage', hp.winPtr, S.screenRect, [], 0),3);
    cpu8 = hp.getImage(S.screenRect, 1);
    hp.afterFrame();
end

function rmsLSB = rms_img(I8, bg)
    D = double(I8) - bg;
    rmsLSB = sqrt(mean(D(:).^2));
end

function m = mean_img(I8), m = mean(I8(:)); end

