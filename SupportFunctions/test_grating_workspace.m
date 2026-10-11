

%% open Screen
S = MarmoViewRigSettings;
S.screenRect = [0 0 601 501];
A = marmoview.openScreen(S);

%%

grat = stimuli.grating_procedural(A.window);

grat.position = A.screenRect(3:4)/2;
grat.screenRect = A.screenRect;
grat.pixPerDeg = S.pixPerDeg;

grat.cpd = 2;
grat.radius = 100; % in pixels (also note, this is the diameter, I think)
grat.radius = Inf; % fullscreen

grat.orientation = 90; % in degrees
grat.phase = 0;

grat.range = 127; % color range
grat.square = false; % if you want a hard aperture
grat.gauss = true;
grat.bkgd = S.bgColour;
grat.transparent = 0.5; % effectively Michelson contrast / 2 -- again, worth checking

grat.updateTextures()
grat.stimValue = 1;
grat.beforeFrame()


Screen('Flip', A.window)


%% interact with mouse input
% [x0,y0] = GetMouse();
% 
% for i = 1:1000
% %     grat.position = grat.position + randn(1,2)*2;
%     [x,y] = GetMouse();
%     grat.phase = grat.phase + (x - x0);
%     x0 = x;
%     grat.beforeFrame()
%     Screen('Flip', A.window)
% end

%% test cpu reconstruction
I = grat.getImage(A.screenRect, 1);
I2=round(I-1);


I1 = Screen('GetImage', A.window, A.screenRect);
I1 = mean(I1, 3);
figure(1); clf;
subplot(1,3,1)
imagesc(I2)
subplot(1,3,2)
imagesc(I1)
subplot(1,3,3)
imagesc(I1 - I2, [-10 10])


subplot(121)
hist(round(I2(:)))
subplot(122)
hist(round(I1(:)))

%% Grating phase was zero so if this was a centered grating with origin at 
% the center, the exact screen center should be grey, but its not... phase
% is messy, cropping and rotations make it tricky
