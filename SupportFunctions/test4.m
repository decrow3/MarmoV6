%FAILED, DON'T USE!

%% open Screen
S = MarmoViewRigSettings;
S.screenRect = [0 0 600 600];
A = marmoview.openScreen(S);
win=A.window;
winRect=A.screenRect;
w = RectWidth(winRect); h = RectHeight(winRect);
% 
for ii=1:8
    for jj=1:12
    phase_rad = (ii-1)*pi/4;  
    orientation_deg = (jj-1)*30;

%% Params
pixPerDeg = 60;               % your rig’s ppd
bgGrey    = 127;              % mean
contrast  = 0.5;              % amplitude on shader (0..1)
sf_cpd    = 0.66;                % spatial freq in cycles/deg. perfect line up at 2.5 cycle/deg, at 60ppd with a 8.3x10 deg window. ei width is periodic



%% Texture on gpu

% --- Make an oversize procedural sine to cover any rotation ---
maxdim   = ceil(hypot(w,h));                     % diagonal
baseRGBA = [0 0 0 0];                            % zero base (we draw bg once)
tex = CreateProceduralSineGrating(win, maxdim, maxdim, baseRGBA);

[x0,y0] =RectCenter(winRect);

% Place the giant texture centered, but crop to the window:
sourceRect=[0 0 maxdim maxdim];
dstRect = CenterRectOnPointd([0 0 maxdim maxdim], x0,y0);


% --- Draw GPU grating ---
Screen('FillRect', win, bgGrey);
[oldSrc, oldDst] = Screen('BlendFunction', win, GL_ONE, GL_ONE);
sf_cpp = sf_cpd / pixPerDeg;                     % cycles / pixel
aux    = [(phase_rad)*180/pi, sf_cpp, contrast, 1];
rot    = 90-orientation_deg; %90-                  % PTB convention

% Screen('DrawTexture', o.winPtr, o.tex, [], rect, 90-o.orientation, [], [], [], [], [], [o.phase, freq, o.transparent, 0]);
Screen('DrawTexture', win, tex, sourceRect, dstRect, rot, [], [], [], [], [], aux);
Screen('BlendFunction', win, oldSrc, oldDst);
vbl = Screen('Flip', win);

% --- Grab GPU image for comparison ---
I_gpu = Screen('GetImage', win, winRect, [], 0); % 1 = float [0 1.0], 0 = uint

%% CPU renderer with identical conventions
% use values from our openGL shaders
twopi = 2.0 * 3.141592654;
deg2rad_ = 3.141592654 / 180.0;
phase_deg=phase_rad/deg2rad_;
% 

[cx, cy] = RectCenter(winRect);

% --- Make an oversize procedural sine to cover any rotation ---
maxdim   = ceil(hypot(w,h));
[xPix, yPix] = meshgrid( (1:maxdim), (1:maxdim)); %Large unrotated square

Xdeg =  xPix / pixPerDeg;
Ydeg =  yPix / pixPerDeg;   %

cropRect = CenterRectOnPointd([0 0 w h], maxdim/2,maxdim/2);

% this gives us our window for what's plotted onscreen
Xdeg=Xdeg(cropRect(2):cropRect(4)-1,cropRect(1):cropRect(3)-1);
Ydeg=Ydeg(cropRect(2):cropRect(4)-1,cropRect(1):cropRect(3)-1);

%Wavevector from rotation rule: theta = (90 - ori)*rad
theta = deg2rad_*(90 - orientation_deg);
fx = sf_cpd * cos(theta);   % cycles/deg
fy = sf_cpd * sin(theta);   % cycles/deg

% Shader uses sine: sin(2π (fx*X + fy*Y) + phase)
 phase = 2*pi*(fx.*Xdeg + fy.*Ydeg) + phase_rad; %when
 
acc = sin(phase);
% 
I_cpu_lin = (bgGrey/255) + contrast * acc;  % draw bg once + additive amp
I_cpu_lin = min(max(I_cpu_lin,0),1);
I_cpu     = uint8(round(255 * I_cpu_lin));

%I_cpu = cpuSineLikePTB(winRect, maxdim, orientation_deg, phase_deg, sf_cpd/pixPerDeg, bgGrey, contrast);


subplot(1,3,2); imshow(I_cpu); title('CPU');


%%
% Given: w,h, maxdim = ceil(hypot(w,h))
%        phase_deg, sf_cpd, pixPerDeg, orientation_deg

% 1) Large unrotated square in *pixel* coords, origin top-left, centers at +0.5:
[Xpix, Ypix] = meshgrid( (0:maxdim-1)+0.5, (0:maxdim-1)+0.5 );

% 2) PTB’s rotation for gratings is rot = 90 - orientation_deg
rot = 90 - orientation_deg;

% 3) cycles per pixel (shader’s f_cpp):
f_cpp = (sf_cpd / pixPerDeg);

% 4) Project onto rotated axis that the shader uses:
Xprime =  cosd(rot) * Xpix + sind(rot) * Ypix;

% 5) Shader uses *sin* and phase in *degrees*:
phi = deg2rad(phase_deg);
acc = sin( 2*pi*f_cpp * Xprime + phi );

% 6) Same background & additive blend you use on GPU:
I_cpu_lin = (bgGrey/255) + contrast * acc;
I_cpu_lin = min(max(I_cpu_lin,0),1);
I_cpu2 = uint8(round(255 * I_cpu_lin));

% 7) Crop the same centered w×h window you draw on screen:
cropRect = CenterRectOnPointd([0 0 w h], maxdim/2, maxdim/2);
I_cpu = I_cpu2(cropRect(2):cropRect(4)-1, cropRect(1):cropRect(3)-1);
subplot(1,3,2); imshow(I_cpu2); title('CPU2');
%% Compare
diff   = double(I_gpu(:,:,1)) - double(I_cpu);   % compare luminance (all channels same)
mae(ii,jj)    = mean(abs(diff(:)));
mxabs(ii,jj) = max(abs(diff(:)));

fprintf('Dir = %.4f, Phase= %.4f,MAE = %.4f, MaxAbs = %.4f\n', orientation_deg, phase_rad, mae(ii,jj), mxabs(ii,jj));

%%
% Quick visual
figure(1); 
subplot(1,3,1); imshow(I_gpu(:,:,1)); title('GPU');
subplot(1,3,2); imshow(I_cpu); title('CPU');
subplot(1,3,3); imagesc(diff); axis image; colorbar; title('GPU - CPU');


%%
figure(2); 
subplot(221)
imagesc(I_gpu(:,:,1)); axis equal tight
subplot(222)
imagesc(I_cpu(:,:)); axis equal tight
subplot(223) %plot around center of screen, origin of x/y (deg)
imagesc(I_gpu((h/2-40):(h/2+40),(w/2-40):(w/2+40),1)); axis equal tight
subplot(224)
imagesc(I_cpu((h/2-40):(h/2+40),(w/2-40):(w/2+40))); axis equal tight
colormap(gray)
%% debug
% figure(3); 
% subplot(211)
% plot(I_gpu(240,:,1)); %axis equal tight
% title('GPU')
% subplot(212)
% plot(I_cpu(240,:)); %axis equal tight
% title('CPU')

%dir 90 plot
figure(4);subplot(121); plot(I_gpu(250,250:350,1));hold on;plot(I_cpu(250,250:350));hold off
%dir 0 plot
figure(4);subplot(122); plot(I_gpu(200:300,300,1));hold on;plot(I_cpu(200:300,300));hold off
%close all
    end
end


% Cleanup
Screen('Close', tex);
Screen('CloseAll');
% figure(4);subplot(121); plot(I_gpu(250,:,1));hold on;plot(I_cpu(250,:));hold off
% %dir 0 plot
% figure(4);subplot(122); plot(I_gpu(:,300,1));hold on;plot(I_cpu(:,300));hold off
% %central pixel
% I_gpu(Xdeg==0&Ydeg==0)
% fprintf('CenterPixelGPU= %.4f, CenterPixelCPU= %.4f', I_gpu(Xdeg==0&Ydeg==0), I_cpu(Xdeg==0&Ydeg==0));
%%
% figure(5);clf
% plot(I_gpu(:,300,1))
% hold on
% plot(I_cpu(:,300,1))
figure(5);clf
plot(I_gpu(301,:,1))
hold on
plot(I_cpu(301,:,1))