%% open Screen
Screen('Preference', 'SkipSyncTests', 1); %For testing only
S = MarmoViewRigSettings;
S.screenRect = [0 0 600 500];
A = marmoview.openScreen(S);


%%
%Just get wedges working
ringwedges=stimuli.ringwedges(A.window);
       ringwedges.stim='wedge';
       ringwedges.wedgeWidth=1;
       ringwedges.nAng=1;
       ringwedges.innerRad=0.1;
       ringwedges.stimSize=5;

       ringwedges.stimCtr=[0,0];
       ringwedges.srcRect=S.screenRect;
       ringwedges.destRect=S.screenRect;
       ringwedges.pos=[0,0];
       ringwedges.motionSteps=5;
       ringwedges.nRad=5;
       ringwedges.period =1;
       ringwedges.tf =2;
       ringwedges.sparsity = 0;
       ringwedges.contrast = 80;
       ringwedges.texnum   = 1;
       ringwedges.barwidth  = round(2*S.pixPerDeg);
       ringwedges.pxradius   = round(2*S.pixPerDeg);
       %ringwedges.prefori   = P.prefori;
       ringwedges.pixPerDeg = S.pixPerDeg;
       ringwedges.displayctr=S.centerPix;

% %Intervals for increments of phase of polar angle of center of wedges
phinc       = pi/6;%pi/24;
wedgewidth  = phinc;%1.5*phinc;
nAng        = 2*pi/wedgewidth;
fixRadius = .5;

% Starting phases, clockwise from leftward=0, pi/2 (5pi/2) = up, pi= right, 3*pi/2 down
% Left hemisphere
%Phases  = 3*pi/2:phinc:
Phases  = 3*pi/2+phinc/2:phinc:2*pi-phinc/2;% left lower visual field for right hemi V1-V2 

   wedgeWidth=phinc;
    subwedperwed=1;% subwedges are offcentered by .5
    
    
    ringwedges.wedgeWidth = subwedperwed;       %number of sub-wedges in a wedge  
    ringwedges.nAng = subwedperwed*2*pi/(wedgeWidth);%42;%12;        % number of sub-wedges in a circle *2    
   
    ringwedges.stimSize = 20; % Radius in visual angle
    ringwedges.innerRad = fixRadius; 
    ringwedges.nRad = 12;%24;            % number of sub-rings in a circle * 2
    ringwedges.nBar = 5;             % number of bars in the square * 2

    switch ringwedges.stim
        case 'full-field'
            ringwedges.tf = 8;               %Hz
            ringwedges.stimPeriod = 1.5;
            ringwedges.period = 30; % 24 sec (32 frames at .75 s TR)
            ringwedges.nCycles = 6; % 24 x 6 = 180 (3 min) 240 frames at .75 s TR
        case 'bar'
            ringwedges.tf = 12;               %Hz
            ringwedges.period = 15;          %seconds in entire cycle as in both orientations
            ringwedges.nCycles = size(ringwedges.orientationSequences,1);%11; % 8 orientations and 4 blanks 15x12 = 180 (3 min) 240 frames at .75 s TR
        otherwise
            ringwedges.tf = 8;               %Hz
            ringwedges.period = 100;          %seconds in entire cycle as in both orientations
            ringwedges.nCycles = 1; % 18x12 = 216 (3.6 min) 288 volumes at .75 s TR
    end
    


    ringwedges.ringWidth = 1;        %number of sub-rings in a ring (has to be odd)
    ringwedges.barWidth = .8;
    ringwedges.fixSize = 10;         %fixation point size
    ringwedges.junkFrames = 8;             %junk before stimulus in seconds
    ringwedges.meriThick = 1/10;     %what proportion of circle is a wedge for the meridian 
    ringwedges.meriStart= 'horizontal'; %which to start with: horizontal or vertical

    ringwedges.motionSteps = 8;

    switch ringwedges.stim
        case 'ring'
            ringwedges.startPhase = .5*ringwedges.ringWidth/ringwedges.nRad;
        case 'wedge'
            ringwedges.startPhase = .25*pi;%.25; %.5*ringwedges.wedgeWidth/ringwedges.nAng; %.25 - 
        case 'meridian' 
            if ringwedges.meriStart=='horizontal' %#ok<STCMP>
                ringwedges.startPhase = .5;
            else
                ringwedges.startPhase = 0;
            end
        otherwise
            ringwedges.nOrientations = 8;
            ringwedges.startPhase = 0;
    end

    ringwedges.pos = [0 0]';
    ringwedges.stimCtr = [0 0 0];[960, 540, 0]; 
    ncopies = 1;
    ringwedges.isi = 0; % blank interstimulus interval between each matrix module
    stimModuleDur = .3/ncopies;
    
%Initialise but should be updated by cond matrix
    ringwedges.startPhase=0;
    ringwedges.reverse=0;
    


%
ringwedges.makeTex();
ringwedges.beforeTrial()
ringwedges.stimValue = 1;
ringwedges.beforeFrame()
Screen('Flip', A.window)
%%
dotflow=stimuli.opticflow(A.window);

%Position is relative to top left
dotflow.position= [(S.screenRect(3)+S.screenRect(1))/2 (S.screenRect(4)+S.screenRect(2))/2];
dotflow.f= 0.0100;
dotflow.depth= 2;
dotflow.size= 3;
dotflow.vxyz= [0 0 .1];
dotflow.nDots= 500;
dotflow.transparent= 0.5000;
dotflow.pixperdeg= S.pixPerDeg;
dotflow.screenRect= A.screenRect;
dotflow.colour= [1 1 1];
dotflow.bkgd= 127;
dotflow.maxRadius= inf;
dotflow.Xtop=  A.screenRect(3);
dotflow.Xbot=  A.screenRect(1);
dotflow.Ytop=  A.screenRect(2);
dotflow.Ybot=  A.screenRect(4);

%%
dotflow.beforeTrial()
dotflow.stimValue = 1;
dotflow.beforeFrame()


Screen('Flip', A.window)
%%
for i = 1:1000
    dotflow.position =  [(S.screenRect(3)+S.screenRect(1))/2 (S.screenRect(4)+S.screenRect(2))/2] + [cosd(i) sind(i)]*15;

    dotflow.beforeFrame()
    Screen('Flip', A.window);
    dotflow.afterFrame()
    %dotflow.x(1)
    pause(0.01)

end


%% Grating/mouse interaction

grat = stimuli.grating(A.window);

grat.position = A.screenRect(3:4)/2;
grat.screenRect = A.screenRect;
grat.pixPerDeg = S.pixPerDeg;

grat.cpd = 2;
grat.radius = 100; % in pixels (also note, this is the diameter, I think)
grat.orientation = 90; % in degrees
grat.phase = 0;

grat.range = 127; % color range
grat.square = false; % if you want a hard aperture
grat.gauss = true;
grat.ring = true;
grat.bkgd = S.bgColour;
grat.transparent = 0.5; % effectively Michelson contrast / 2 -- again, worth checking

grat.updateTextures()
grat.stimValue = 1;
grat.beforeFrame()


Screen('Flip', A.window)


%% interact with mouse input
[x0,y0] = GetMouse();

for i = 1:1000
%     grat.position = grat.position + randn(1,2)*2;
    [x,y] = GetMouse();
    grat.phase = grat.phase + (x - x0);
    x0 = x;
    grat.beforeFrame()
    Screen('Flip', A.window)
end

