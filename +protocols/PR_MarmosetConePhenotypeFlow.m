classdef PR_MarmosetConePhenotypeFlow < handle
  % Matlab class for running an experimental protocl
  %
  % The class constructor can be called with a range of arguments:
  %
  
  properties (Access = public), 
       Iti double = 1;            % default Iti duration
       startTime double = 0;      % trial start time
       fixStart double = 0;       % fix acquired time
       itiStart double = 0;       % start of ITI interval
       lostStart double = 0;
       lastReward double = 0;
       RewardDur double =1;       % threshold for time followed to get a reward 
       fixDur double = 0;         % fixation duration
       stimStart double = 0;      % start of Gabor probe stimulus
       responseStart double = 0;  % start of choice period
       responseEnd double = 0;    % end of response period
       showFix logical = true;    % trial start with fixation
       flashCounter double = 0;   % counts frames, used for fade in point cue?
       rewardCount double = 0;    % counter for reward drops
       RunFixBreakSound double = 0;       % variable to initiate fix break sound (only once)
       NeverBreakSoundTwice double = 0;   % other variable for fix break sound
       MaxFrame double = 6000;
       ProbeHistory =[]
       Traces =[]
       targWinRadius double = 5;
       FrameCount double = 0;
       mode double =1;
  end
      
  properties (Access = private)
    winPtr; % ptb window
    state double = 0;      % state counter
    error double = 0;      % error state in trial
    %*********
    S;      % copy of Settings struct (loaded per trial start)
    P;      % copy of Params struct (loaded per trial)
    trialsList;  % list of trial types to run in experiment
    trialIndexer = [];  % object to run trial order
    %********* stimulus structs for use
    stimTheta double = 0;  % direction of choice
    hFix;              % object for a fixation point
    hProbe = [];       % object for Gabor stimuli
%     hChoice = [];      % object for Choice Gabor stimuli
    fixbreak_sound;    % audio of fix break sound
    fixbreak_sound_fs; % sampling rate of sound
    %****************
    D = struct;        % store PR data for end plot stats
    currentCondition = struct();
    currentTrialRow double = [];
    currentTrialIndex double = NaN;
    trialCalibrationChecksum char = '';
  end
  
  methods (Access = public)
    function o = PR_MarmosetConePhenotypeFlow(winPtr)
      o.winPtr = winPtr; 
      o.trialsList = [];
    end
    
    function state = get_state(o)
        state = o.state;
    end
    
    function initFunc(o,S,P)
 
         %********** Set-up for trial indexing (required) 
         cors = [0,4];  % count these errors as correct trials
         reps = [1,2];  % count these errors like aborts, repeat
         o.trialIndexer = marmoview.TrialIndexer(o.trialsList,P,cors,reps);
         o.error = 0;  

        o.MaxFrame = ceil(20*S.frameRate);
        o.ProbeHistory = zeros(o.MaxFrame,5);  % time,x,y,sf,fixated
        o.Traces = zeros(o.MaxFrame,6);  % time,targx,targy,eyex,eyey, fixgood
        o.targWinRadius =5;
        

         %********** Initialize Graphics Objects
         o.hFix = stimuli.fixation(o.winPtr);   % fixation stimulus
        switch P.mode
            case 0
                o.hProbe = stimuli.grating(o.winPtr);  % grating probe
            case 1
                o.hProbe = stimuli.opticflow(o.winPtr); % optic flow
        end

         %********* if stimuli remain constant on all trials, set-them up here

         % set fixation point properties
         sz = P.fixPointRadius*S.pixPerDeg;
         o.hFix.cSize = sz;
         o.hFix.sSize = 2*sz;
         o.hFix.cColour = ones(1,3); % black
         o.hFix.sColour = repmat(255,1,3); % white
         o.hFix.position = [0,0]*S.pixPerDeg + S.centerPix;
         o.hFix.updateTextures();


         %********** load in a fixation error sound ************
         [y,fs] = audioread(['SupportData',filesep,'gunshot_sound.wav']);
         y = y(1:floor(size(y,1)/3),:);  % shorten it, very long sound
         o.fixbreak_sound = y;
         o.fixbreak_sound_fs = fs;
         %*********************
    end
   
    function closeFunc(o),
        o.hFix.CloseUp();
        o.hProbe.CloseUp();
        
    end
   
    function generate_trialsList(o,S,P)
        if ~isfield(S,'marmosetTrialPlan') || ...
                ~isfield(S.marmosetTrialPlan,'Rows')
            error('PR_MarmosetConePhenotypeFlow:TrialPlan', ...
                'Settings are missing the fixed marmoset trial plan.');
        end
        o.trialsList = S.marmosetTrialPlan.Rows;
    end
    
    function P = next_trial(o,S,P)
          %********************
          o.S = S;
          o.P = P;       
          %*******************

         %******* init Noise History with MaxDuration **************

          i = o.trialIndexer.getNextTrial(o.error);
          row = o.trialsList(i,:);
          o.currentTrialIndex = i;
          o.currentTrialRow = row;
          P.conditionIndex = row(1);
          P.contrastLevelIndex = row(2);
          P.trajectoryIndex = row(3);
          P.repeatIndex = row(4);
          P.trialRandomSeed = row(5);
          P.rewardNumber = row(6);
          P.cpd = P.conditionIndex; % legacy plotting slot only
          P.choiceX = 0;
          P.choiceY = 0;
          P.xDeg = 0;
          P.yDeg = 0;

          o.currentCondition = S.marmosetConditionBank.Conditions(P.conditionIndex);
          o.trialCalibrationChecksum = S.marmosetConditionBank.CalibrationChecksum;
          if ~strcmp(o.currentCondition.CalibrationChecksum, ...
                  o.trialCalibrationChecksum)
              error('PR_MarmosetConePhenotypeFlow:CalibrationChanged', ...
                  'Condition calibration checksum changed before the trial.');
          end
          P.targxvect = S.marmosetTrajectoryBank.XDeg(P.trajectoryIndex,:);
          P.targyvect = S.marmosetTrajectoryBank.YDeg(P.trajectoryIndex,:);
          o.MaxFrame = numel(P.targxvect) + ceil(S.frameRate);

          % Clear traces from the preceding trial.
          o.ProbeHistory = zeros(o.MaxFrame,5);
          o.Traces = zeros(o.MaxFrame,6);
          o.targWinRadius = P.targWinRadius;
          o.P = P;
          
          o.stimTheta = 0;
          o.hProbe(1).position = S.centerPix;
                    o.hProbe(1).f= 0.100; %0.01
                    o.hProbe(1).depth= 10; %2
                    requestedDotDiameterPix = P.dotSizeDeg*S.pixPerDeg;
                    [minSmoothPointSize,maxSmoothPointSize] = ...
                        Screen('DrawDots',o.winPtr);
                    o.hProbe(1).size = min(max(requestedDotDiameterPix, ...
                        minSmoothPointSize),maxSmoothPointSize);
                    o.hProbe(1).vxyz= [0 0 -abs(P.flowExpansionSpeed)];
                    o.hProbe(1).nDots = max(1,round(P.nDots));
                    o.hProbe(1).transparent= 1;
                    o.hProbe(1).pixperdeg= S.pixPerDeg;
                    o.hProbe(1).screenRect= S.screenRect;
                    o.hProbe(1).bkgd = P.bkgd;
                    o.hProbe(1).balancedDots = true;
                    o.hProbe(1).dotContrast = 1;
                    o.hProbe(1).polarityColours = [ ...
                        o.currentCondition.NegativeFramebufferRGB255(:), ...
                        o.currentCondition.PositiveFramebufferRGB255(:)];
                    o.hProbe(1).neutralColour = ...
                        o.currentCondition.BackgroundFramebufferRGB255(:);
                    o.hProbe(1).minSeparationPix = ...
                        max(0,P.dotMinSeparation)*S.pixPerDeg;
                    o.hProbe(1).placementAttempts = ...
                        max(1,round(P.dotPlacementAttempts));
                    o.hProbe(1).maxRadius= inf;
                    o.hProbe(1).lifetime= max(1,round(P.dotLifetimeFrames));
                    o.hProbe(1).setCenterDecayProfile(P.centerDecayProfile);
                    o.hProbe(1).Xtop=  S.screenRect(3);
                    o.hProbe(1).Xbot=  S.screenRect(1);
                    o.hProbe(1).Ytop=  S.screenRect(2);
                    o.hProbe(1).Ybot=  S.screenRect(4);
                    o.hProbe(1).setRandomSeed(P.trialRandomSeed);
                    o.hProbe(1).beforeTrial();
          o.P = P;
    end
    
    function [FP,TS] = prep_run_trial(o)
        
          %********VARIABLES USED IN RUNNING TRIAL LOGISTICS
          o.fixDur = o.P.fixMin + ceil(1000*o.P.fixRan*rand)/1000;  % randomized fix duration
          % showFix is a flag to check whether to show the fixation spot or not while
          % it is flashing in state 0
          o.showFix = true;
          % flashCounter counts the frames to switch ShowFix off and on
          o.flashCounter = 0;
          % rewardCount counts the number of juice pulses, 1 delivered per frame
          o.rewardCount = 0;
          o.FrameCount = 0;
          %****** deliver sound on fix breaks
          o.RunFixBreakSound =0;
          o.NeverBreakSoundTwice = 0;  
          % Setup the state
          o.state = 0; % Showing the face
          o.error = 0; % Start with error as 0
          o.Iti = o.P.iti;   % set ITI interval from P struct stored in trial
          %******* Plot States Struct (show fix in blue for eye trace)
          % any special plotting of states, 
          % FP(1).states = 1:2; FP(1).col = 'b';
          % would show states 1,2 in blue for eye trace
          FP(1).states = 1:3;  %before fixation
          FP(1).col = 'b';
          FP(2).states = 4;  % fixation held
          FP(2).col = 'g';
          FP(3).states = 5;
          FP(3).col = 'r';
          %******* set which states are TimeSensitive, if [] then none
          TS = 1:5;  % all times during target presentation
          %********
          o.startTime = GetSecs;
    end
    
    function keepgoing = continue_run_trial(o,screenTime)
        if o.FrameCount > 0
            o.ProbeHistory(o.FrameCount,1) = screenTime;
        end
        keepgoing = 0;
        if (o.state < 9)
            keepgoing = 1;
        end
    end
   
    %******************** THIS IS THE BIG FUNCTION *************
    function drop = state_and_screen_update(o,currentTime,x,y,varargin)  
        drop = 0;
        %******* THIS PART CHANGES WITH EACH PROTOCOL ****************
        
        %%%%% STATE 0 -- GET INTO FIXATION WINDOW %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % If eye travels within the fixation window, move to state 1
        if o.state == 0 && norm([x y]) < o.P.initWinRadius
            o.state = 1; % Move to fixation grace
            o.fixStart = GetSecs;
        end

        % Trial expires if not started within the start duration
        if o.state == 0 && currentTime > o.startTime + o.P.startDur
            o.state = 8; % Move to iti -- inter-trial interval
            o.error = 1; % Error 1 is failure to initiate
            o.itiStart = GetSecs;
        end

        %%%%% STATE 1 -- GRACE PERIOD TO BE IN FIXATION WINDOW %%%%%%%%%%%%%%%%
        % A grace period is given before the eye must remain in fixation
        if o.state == 1 && currentTime > o.fixStart + o.P.fixGrace
            if norm([x y]) < o.P.initWinRadius
                o.state = 2; % Move to hold fixation
            else
                o.state = 8;
                o.error = 1; % Error 1 is failure to initiate
                o.itiStart = GetSecs;
            end
        end

        %%%%% STATE 2 -- HOLD FIXATION %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % If fixation is held for the fixation duration, move to state 3
        if o.state == 2 && currentTime > o.fixStart + o.fixDur
            o.state = 3; % Move to show stimulus
            %***** reward here for holding of fixation
            if (isfield(o.P,'rewardFix'))
                if (o.P.rewardFix)
                  drop = 1;
                end
            end
            %************************
            o.stimStart = GetSecs;
            o.lastReward = GetSecs;
        end

        % Eye must remain in the fixation window
        if o.state == 2 && norm([x y]) > o.P.fixWinRadius
            o.state = 8; % Move to iti -- inter-trial interval
            o.error = 2; % Error 2 is failure to hold fixation
            o.itiStart = GetSecs;
        end

        %%%% STATE 3, SHOWING STIMULUS. Reward if stays close for a while,
                %%%% end if moves too far from the target
        targx=(o.hProbe.position(1)-o.S.centerPix(1))/o.S.pixPerDeg;
        targy=-(o.hProbe.position(2)-o.S.centerPix(2))/o.S.pixPerDeg;
        distSquared = (x-targx).^2 + (y-targy).^2;

        % Gaze starts on the flow centre, so the onset interval neither
        % earns reward nor counts as losing the target.
        inOnsetExclusion = ((o.state == 3) || (o.state == 4)) && ...
            currentTime < o.stimStart + o.S.marmosetConfig.OnsetExclusionSeconds;

        if inOnsetExclusion
            o.state = 3;
            o.lastReward = currentTime; % reward timing starts after onset

        elseif ((o.state == 3) || (o.state == 4)) && distSquared <= o.P.targWinRadius.^2
            o.state = 3; % stay in/reenter state
            %Reward if followed stim for 1 second
            if ~o.error && o.rewardCount < o.P.rewardNumber && (currentTime-o.lastReward)>o.P.RewardDur
                   o.rewardCount = o.rewardCount + 1;
                   drop = 1;
                   o.lastReward=GetSecs;
            end

        elseif o.state == 3 && distSquared > o.P.targWinRadius.^2
            o.state = 4; %enter grace period for lost target
            o.lostStart = currentTime;
        end

        % Target is lost, and has continued to be lost (otherwise it would
        % have moved to state 3)
        if o.state == 4 && currentTime > o.lostStart + o.P.lostgrace
            o.state = 7; % Move to iti -- inter-trial interval
            o.error = 3; % Error 3 is lost target
            o.itiStart = GetSecs;
        end

        %Timeout
        if ((o.state == 3) || (o.state == 4)) && currentTime > o.stimStart + o.P.stimDur
            o.state = 7; % Move to iti -- inter-trial interval
            o.error = 0; % No error here
            o.itiStart = GetSecs;
        end


        %%%%% STATE 7 -- INTER-TRIAL INTERVAL %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Deliver rewards
        if o.state == 7 
            if ~o.error && o.rewardCount < o.P.rewardNumber
               if currentTime > o.itiStart + 0.2*o.rewardCount % deliver in 200 ms increments
                   o.rewardCount = o.rewardCount + 1;
                   drop = 1;
               end
            else
               o.state = 8;
            end
        end

        %******* fixation break feedback, but otherwise go to state 9
        if o.state == 8
               if currentTime > o.itiStart + 0.2   % enough time to flash fix break 
                  o.state = 9; 
                  if o.error 
                     o.Iti = o.P.iti + o.P.blank_iti;
                  end
               end
        end

        % STATE SPECIFIC DRAWS


        switch o.state
            case 0
                %******* flash fixation point to draw monkey to it
                if o.showFix
                    o.hFix.beforeFrame(1);
                end
                o.flashCounter = mod(o.flashCounter+1,o.P.flashFrameLength);
                if o.flashCounter == 0
                    o.showFix = ~o.showFix;
                end

            case 1
                % Bright fixation spot, prior to stimulus onset                    
                o.hFix.beforeFrame(1);

            case 2
                % Continue to show fixation for a hold period       
                o.hFix.beforeFrame(1);

            case {3,4}                
                %********* show stimulus if still appropriate
                if ( currentTime < o.stimStart + o.P.stimDur )
                    %Update to the next position of the probe
                    o.updatetarget(x,y,currentTime)
                end
                
                
            case 8
                if (o.error == 2) % broke fixation
                    o.hFix.beforeFrame(2);    
                    %once you have a sound object, put break fix here
                    o.RunFixBreakSound = 1;
                end
                % leave everything blank for a minimum ITI           
        end
        
        %******** if sound, do here
        if (o.RunFixBreakSound == 1) & (o.NeverBreakSoundTwice == 0)  
           sound(o.fixbreak_sound,o.fixbreak_sound_fs);
           o.NeverBreakSoundTwice = 1;
        end
        %**************************************************************
    end
    
    function updatetarget(o,xx,yy,currentTime)
        o.FrameCount = o.FrameCount + 1;     
        trajectoryFrame = min(o.FrameCount,numel(o.P.targxvect));

        %Store current position of targets and eyes, from previous frame
        %this should end up being the same as data stored in o.ProbeHistory
        o.Traces(o.FrameCount,1)=currentTime;
        targx=(o.hProbe.position(1)-o.S.centerPix(1))/o.S.pixPerDeg;
        targy=-(o.hProbe.position(2)-o.S.centerPix(2))/o.S.pixPerDeg;
        o.Traces(o.FrameCount,2)=targx;
        o.Traces(o.FrameCount,3)=targy;
        o.Traces(o.FrameCount,4)=xx;
        o.Traces(o.FrameCount,5)=yy;

        
        if o.state==3
            o.Traces(o.FrameCount,6) = 1;
        elseif o.state==4
            o.Traces(o.FrameCount,6) = 1; %0;%NO! Need to preserve time course/lags
        end

        %Update position for next frame
        o.hProbe.afterFrame();
        o.hProbe.position = [(o.S.centerPix(1) + round(o.P.targxvect(trajectoryFrame)*o.S.pixPerDeg)),(o.S.centerPix(2) - round(o.P.targyvect(trajectoryFrame)*o.S.pixPerDeg))];
        o.hProbe.beforeFrame();

         % NOTE: store screen time in "continue_run_trial" after flip, time
         % when stimuli actually appears
        o.ProbeHistory(o.FrameCount,2) = o.hProbe.position(1);  
        o.ProbeHistory(o.FrameCount,3) = o.hProbe.position(2); 

        switch o.P.mode
            case 0
                o.ProbeHistory(o.FrameCount,4) = o.hProbe.cpd; %SF
            case 1
                o.ProbeHistory(o.FrameCount,4) = o.hProbe.size; %size of dot
        end
        
        if o.state==3
            o.ProbeHistory(o.FrameCount,5) = 1;
        elseif o.state==4
            o.ProbeHistory(o.FrameCount,5) = 0;
        end
    end


    function Iti = end_run_trial(o)
        Iti = o.Iti - (GetSecs - o.itiStart); % returns generic Iti interval
    end
    
    function plot_trace(o,handles)
        % This function plots the eye trace from a trial in the EyeTracker
        % window of MarmoView.

        h = handles.EyeTrace;
        % Fixation window
        set(h,'NextPlot','Replace');
        r = o.P.fixWinRadius;
        plot(h,r*cos(0:.01:1*2*pi),r*sin(0:.01:1*2*pi),'--k');
        set(h,'NextPlot','Add');
        
        trialTraces = o.Traces(1:o.FrameCount,:);
        targX = trialTraces(:,2);
        targY = trialTraces(:,3);
        eyeX = trialTraces(:,4);
        eyeY = trialTraces(:,5);

        plot(h,targX,targY,'k.')
        plot(h,eyeX(trialTraces(:,6)==1),eyeY(trialTraces(:,6)==1),'b.')
        plot(h,eyeX(trialTraces(:,6)~=1),eyeY(trialTraces(:,6)~=1),'r.')



        
        eyeRad = handles.eyeTraceRadius;
        axis(h,[-eyeRad eyeRad -eyeRad eyeRad]);

%         % Stimulus window
%         stimX = o.P.choiceX; 
%         stimY = o.P.choiceY; 
%         eyeRad = handles.eyeTraceRadius;
%         minR = o.P.stimWinMinRad;
%         maxR = o.P.stimWinMaxRad;
%         errT = o.P.stimWinTheta;
%         stimT = atan2(stimY,stimX);
% 
%         plot(h,[minR*cos(stimT+errT) maxR*cos(stimT+errT)],[minR*sin(stimT+errT) maxR*sin(stimT+errT)],'--k');
%         plot(h,[minR*cos(stimT-errT) maxR*cos(stimT-errT)],[minR*sin(stimT-errT) maxR*sin(stimT-errT)],'--k');
%         plot(h,minR*cos(stimT-errT:pi/100:stimT+errT),minR*sin(stimT-errT:pi/100:stimT+errT),'--k');
%         plot(h,maxR*cos(stimT-errT:pi/100:stimT+errT),maxR*sin(stimT-errT:pi/100:stimT+errT),'--k');
%         r = o.P.radius;
%         plot(h,stimX+r*cos(0:.01:1*2*pi),stimY+r*sin(0:.01:1*2*pi),'-k');
%         axis(h,[-eyeRad eyeRad -eyeRad eyeRad]);
    end
    
    function PR = end_plots(o,P,A)   %update D struct if passing back info
        
        %************* STORE DATA to PR
        PR = struct;
        PR.error = o.error;
        PR.fixDur = o.fixDur;
        PR.x = P.xDeg;
        PR.y = P.yDeg;
        PR.choiceX = P.choiceX;
        PR.choiceY = P.choiceY;
        % Retain cpd for backward compatibility, but treat dot diameter as
        % the physical independent variable for optic-flow trials.
        PR.cpd = P.cpd;
        PR.nominalCpd = NaN;
        if P.mode == 1
            PR.requestedDotDiameterPix = P.dotSizeDeg*o.S.pixPerDeg;
            PR.dotDiameterPix = o.hProbe.size;
            PR.dotDiameterDeg = o.hProbe.size/o.S.pixPerDeg;
            PR.dotDiameterWasClamped = abs(PR.dotDiameterPix - ...
                PR.requestedDotDiameterPix) > 10*eps(PR.dotDiameterPix);
            PR.effectiveDotCpd = o.S.pixPerDeg/(2*PR.dotDiameterPix);
            PR.conditionValue = PR.dotDiameterDeg;
            PR.conditionUnits = 'deg dot diameter';
            PR.nDots = o.hProbe.nDots;
            PR.balancedDots = o.hProbe.balancedDots;
            PR.dotContrast = o.hProbe.dotContrast;
            if isfield(P,'dotContrast')
                PR.dotContrastAtSmallestSize = P.dotContrast;
            end
            if isfield(P,'normalizeDotRms')
                PR.normalizeDotRms = logical(P.normalizeDotRms);
            end
            if isfield(P,'dotRmsExponent')
                PR.dotRmsExponent = P.dotRmsExponent;
            end
            PR.dotMinSeparationDeg = o.hProbe.minSeparationPix/o.S.pixPerDeg;
            PR.dotPlacementFallbacks = o.hProbe.placementFallbackCount;
            PR.dotPlacementCalls = o.hProbe.placementCalls;
            PR.dotPlacementCandidates = o.hProbe.placementCandidateCount;
            PR.dotPlacementDistanceChecks = o.hProbe.placementDistanceChecks;
            PR.dotPlacementTimeMs = 1000*o.hProbe.placementTimeSeconds;
            PR.dotCachedReplacementCount = o.hProbe.cachedReplacementCount;
            PR.dotReplacementMode = 'cached pre-trial layout';
            PR.stimulusFamily = 'broadband polarity-balanced dots';
            condition = o.currentCondition;
            PR.stimulusFamily = 'marmoset candidate-pigment null flow';
            PR.conditionBankSchemaVersion = ...
                o.S.marmosetConditionBank.SchemaVersion;
            PR.conditionIndex = P.conditionIndex;
            PR.conditionID = condition.ConditionID;
            PR.conditionType = condition.ConditionType;
            PR.nullPeakNm = condition.NullPeakNm;
            PR.axisScale = condition.AxisScale;
            PR.contrastLevelIndex = P.contrastLevelIndex;
            PR.trajectoryIndex = P.trajectoryIndex;
            PR.repeatIndex = P.repeatIndex;
            PR.trialRandomSeed = P.trialRandomSeed;
            PR.trialPlanIndex = o.currentTrialIndex;
            PR.trialPlanRow = o.currentTrialRow;
            PR.calibrationSource = condition.CalibrationSource;
            PR.calibrationChecksum = condition.CalibrationChecksum;
            PR.monitorIdentifier = condition.MonitorIdentifier;
            PR.gammaApplication = condition.GammaApplication;
            PR.candidateConePeaksNm = condition.ConePeaksNm;
            PR.candidateRGBToCones = condition.CandidateRGBToCones;
            PR.backgroundLinearRGB = condition.BackgroundLinearRGB;
            PR.negativeLinearRGB = condition.NegativeLinearRGB;
            PR.positiveLinearRGB = condition.PositiveLinearRGB;
            PR.realizedBackgroundLinearRGB = ...
                condition.RealizedBackgroundLinearRGB;
            PR.realizedNegativeLinearRGB = condition.RealizedNegativeLinearRGB;
            PR.realizedPositiveLinearRGB = condition.RealizedPositiveLinearRGB;
            PR.backgroundDeviceCodes = condition.BackgroundDeviceCodes;
            PR.negativeDeviceCodes = condition.NegativeDeviceCodes;
            PR.positiveDeviceCodes = condition.PositiveDeviceCodes;
            PR.backgroundFramebufferRGB255 = ...
                condition.BackgroundFramebufferRGB255;
            PR.negativeFramebufferRGB255 = ...
                condition.NegativeFramebufferRGB255;
            PR.positiveFramebufferRGB255 = ...
                condition.PositiveFramebufferRGB255;
            PR.requestedCandidateConeContrast = condition.RequestedConeContrast;
            PR.realizedCandidateConeContrast = condition.RealizedConeContrast;
            PR.silentConeIndices = condition.SilentConeIndices;
            PR.maximumSilentLeakage = condition.MaximumSilentLeakage;
            PR.conditionValidationPass = condition.ValidationPass;
            PR.dotNegativeCount = nnz(o.hProbe.dotPolarity < 0);
            PR.dotPositiveCount = nnz(o.hProbe.dotPolarity > 0);
            PR.dotNeutralCount = nnz(o.hProbe.dotPolarity == 0);
            PR.dotAlpha = 255;
            PR.blendingContract = 'opaque RGBA dots; calibrated RGB unchanged';
            PR.flowCentreXDeg = P.targxvect;
            PR.flowCentreYDeg = P.targyvect;

            frameIntervals = diff(o.ProbeHistory(1:o.FrameCount,1));
            frameIntervals = frameIntervals(isfinite(frameIntervals) & frameIntervals > 0);
            expectedInterval = 1/o.S.frameRate;
            PR.frameTimingThresholdMs = 1000*1.5*expectedInterval;
            PR.longFrameCount = nnz(frameIntervals > 1.5*expectedInterval);
            PR.longFrameFraction = PR.longFrameCount/max(1,numel(frameIntervals));
            if isempty(frameIntervals)
                PR.meanFrameIntervalMs = NaN;
                PR.maxFrameIntervalMs = NaN;
            else
                PR.meanFrameIntervalMs = 1000*mean(frameIntervals);
                PR.maxFrameIntervalMs = 1000*max(frameIntervals);
            end
        end
        %******* this is also where you could store Gabor Flash Info

        if o.FrameCount == 0
            PR.Traces = [];
            PR.ProbeHistory = [];
        else
            PR.Traces            = o.Traces(1:o.FrameCount,:);
            PR.ProbeHistory     = o.ProbeHistory(1:o.FrameCount,:);
        end
        
        
        %%%% Record some data %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Remove the onset interval because fixation supplies the starting
        % position. Keep failed/short trials, but do not analyze them.
        onsetExclusion = o.S.marmosetConfig.OnsetExclusionSeconds;
        PR.onsetExclusionSeconds = onsetExclusion;
        analysisTraces = o.Traces(1:o.FrameCount,:);
        discardFrames = min(round(onsetExclusion*o.S.frameRate),o.FrameCount);
        analysisTraces(1:discardFrames,6) = 0;
        valid = analysisTraces(:,6) == 1 & ...
            all(isfinite(analysisTraces(:,2:5)),2);
        targX = analysisTraces(valid,2);
        targY = analysisTraces(valid,3);
        eyeX = analysisTraces(valid,4);
        eyeY = analysisTraces(valid,5);
        nvalid = nnz(valid);
        maxLag = round(o.S.frameRate);
        CCG = nan(1,2*maxLag + 1);
        proj = NaN;

        if nvalid >= 3
            smoothFrames = max(1,min(nvalid,round(0.1*o.S.frameRate)));
            eyevX = diff(smooth(eyeX,smoothFrames));
            eyevY = diff(smooth(eyeY,smoothFrames));
            eyetargX = targX-eyeX;
            eyetargY = targY-eyeY;

            projection = (eyevX.*eyetargX(2:end) + eyevY.*eyetargY(2:end)) ./ ...
                (hypot(eyevX,eyevY).*hypot(eyetargX(2:end),eyetargY(2:end)));
            proj = mean(projection,'omitnan');
            CCG = xcorr(eyevX + 1i*eyevY, ...
                eyetargX(2:end) + 1i*eyetargY(2:end),maxLag).';
        end

        distances = hypot(targX-eyeX,targY-eyeY);
        PR.eyeValidityFlags = valid;
        PR.validEyeSampleCount = nvalid;
        PR.medianGazeToFlowCentreDistanceDeg = median(distances,'omitnan');
        PR.fractionInsideCentreWindow = mean(distances <= P.targWinRadius,'omitnan');
        PR.meanEyeVelocityProjectionTowardCentre = proj;
        PR.eyeCentreCrossCorrelation = CCG;
        if all(~isfinite(CCG))
            PR.bestCorrelation = NaN;
            PR.bestCorrelationLagSeconds = NaN;
        else
            [bestCorrelation,bestIndex] = max(abs(CCG),[],'omitnan');
            PR.bestCorrelation = bestCorrelation;
            PR.bestCorrelationLagSeconds = ...
                (bestIndex-(maxLag+1))/o.S.frameRate;
        end
        insideIndex = find(distances <= P.targWinRadius,1,'first');
        if isempty(insideIndex)
            PR.responseLatencySeconds = NaN;
        else
            PR.responseLatencySeconds = (insideIndex-1)/o.S.frameRate;
        end
        baselineCount = min(numel(distances),max(1,round(0.25*o.S.frameRate)));
        if isempty(distances)
            PR.prePostDistanceChangeDeg = NaN;
        else
            PR.prePostDistanceChangeDeg = median(distances(baselineCount+1:end), ...
                'omitnan')-median(distances(1:baselineCount),'omitnan');
        end
        observedDuration = o.FrameCount/o.S.frameRate;
        PR.observedStimulusDurationSeconds = observedDuration;
        invalidReasons = {};
        if nvalid < o.S.marmosetConfig.MinimumValidEyeSamples
            invalidReasons{end+1} = 'insufficient valid eye samples'; %#ok<AGROW>
        end
        if PR.longFrameFraction > o.S.marmosetConfig.MaximumLongFrameFraction
            invalidReasons{end+1} = 'excessive frame drops'; %#ok<AGROW>
        end
        if observedDuration < o.S.marmosetConfig.MinimumAnalysisDurationSeconds
            invalidReasons{end+1} = 'trial too short'; %#ok<AGROW>
        end
        if ~strcmp(o.trialCalibrationChecksum,condition.CalibrationChecksum)
            invalidReasons{end+1} = 'calibration changed'; %#ok<AGROW>
        end
        PR.trialValid = isempty(invalidReasons);
        PR.invalidReasons = invalidReasons;

        metricOptions = struct( ...
            'DiscardInitialSeconds',onsetExclusion, ...
            'MinimumValidEyeSamples', ...
                o.S.marmosetConfig.MinimumValidEyeSamples, ...
            'MaximumLongFrameFraction', ...
                o.S.marmosetConfig.MaximumLongFrameFraction, ...
            'MinimumDurationSeconds', ...
                o.S.marmosetConfig.MinimumAnalysisDurationSeconds, ...
            'CalibrationStable',strcmp(o.trialCalibrationChecksum, ...
                condition.CalibrationChecksum));
        flowMetrics = marmoview.flowFollowingMetrics( ...
            o.Traces(1:o.FrameCount,:), ...
            o.ProbeHistory(1:o.FrameCount,1),o.S.frameRate, ...
            P.targWinRadius,metricOptions);
        PR.flowFollowingMetrics = flowMetrics;
        PR.eyeValidityFlags = flowMetrics.EyeValidityFlags;
        PR.validEyeSampleCount = flowMetrics.ValidEyeSampleCount;
        PR.medianGazeToFlowCentreDistanceDeg = ...
            flowMetrics.MedianGazeToFlowCentreDistanceDeg;
        PR.prePostDistanceChangeDeg = flowMetrics.PrePostDistanceChangeDeg;
        PR.fractionInsideCentreWindow = flowMetrics.FractionInsideCentreWindow;
        PR.meanEyeVelocityProjectionTowardCentre = ...
            flowMetrics.MeanEyeVelocityProjectionTowardCentre;
        PR.eyeCentreCrossCorrelation = flowMetrics.EyeCentreCrossCorrelation;
        PR.bestCorrelation = flowMetrics.BestCorrelation;
        PR.bestCorrelationLagSeconds = flowMetrics.BestCorrelationLagSeconds;
        PR.responseLatencySeconds = flowMetrics.ResponseLatencySeconds;
        PR.trialValid = flowMetrics.TrialValid;
        PR.invalidReasons = flowMetrics.InvalidReasons;
        proj = flowMetrics.MeanEyeVelocityProjectionTowardCentre;
        CCG = flowMetrics.EyeCentreCrossCorrelation;

        o.D.ccg(A.j,:)=CCG;
        o.D.proj(A.j,:)=proj;
        o.D.nvalid(A.j)=nvalid;
        o.D.error(A.j) = o.error;
        o.D.xDeg(A.j) = P.xDeg;
        o.D.yDeg(A.j) = P.yDeg;
        o.D.x(A.j) = P.choiceX; 
        o.D.y(A.j) = P.choiceY; 
        o.D.cpd(A.j) = P.cpd;
        if P.mode == 1
            o.D.dotDiameterDeg(A.j) = o.hProbe.size/o.S.pixPerDeg;
            o.D.dotContrast(A.j) = o.hProbe.dotContrast;
            o.D.dotPlacementFallbacks(A.j) = o.hProbe.placementFallbackCount;
            o.D.dotPlacementTimeMs(A.j) = 1000*o.hProbe.placementTimeSeconds;
            o.D.dotPlacementDistanceChecks(A.j) = o.hProbe.placementDistanceChecks;
            o.D.dotCachedReplacementCount(A.j) = o.hProbe.cachedReplacementCount;
        end
        

        %%%% Plot results %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


        %Also want to plot mean distance to help correct calibration
        offX=targX-eyeX;
        offY=targY-eyeY;
        plot(A.DataPlot1,0,0,'kx');
        plot(A.DataPlot1,offX,offY,'b.');
        
        set(A.DataPlot1,'DataAspectRatio',[1 1 1],'XLim',[-o.targWinRadius o.targWinRadius],'YLim',[-o.targWinRadius o.targWinRadius]);
        title(A.DataPlot1,'Eye-target (calib) error ');
% 


        % Dataplot3, mean pursuit projection by inverse-size condition.
        cpds = unique(o.trialsList(:,1));
        ncpds = size(cpds,1);
        fcXcpd = zeros(1,ncpds);
        proj_all = zeros(1,ncpds);
        labels = cell(1,ncpds);
        maxLag = round(o.S.frameRate);
        CCG_all = nan(2*maxLag+1,ncpds);
        for i = 1:ncpds
            cpd = cpds(i);

            % Combine CCGs, weight by nvalues so to not get thrown off by
            % outliers
            trialMask = o.D.cpd == cpd & o.D.nvalid >= 3 & isfinite(o.D.proj);
            if any(trialMask)
                weights = o.D.nvalid(trialMask);
                CCG_all(:,i) = (weights*o.D.ccg(trialMask,:)./sum(weights)).';
                proj_all(i) = mean(o.D.proj(trialMask),'omitnan');
            else
                proj_all(i) = NaN;
            end

            fcXcpd(i) = proj_all(i);
            labels{i} = o.S.marmosetConditionBank.Conditions(cpd).ConditionID;
        end
        
        %Plot most recent cpd presented
        i=find(cpds==P.cpd);
        lagSeconds = (-maxLag:maxLag)./o.S.frameRate;
        plot(A.DataPlot2,lagSeconds,abs(CCG_all(:,i)),'b',lagSeconds,ones(length(CCG_all(:,i)),1)*median(abs(CCG_all(:,i)),'omitnan'),'r-')
        title(A.DataPlot2,sprintf('CCG: %s',o.currentCondition.ConditionID));
        
        %legend(A.DataPlot2,num2str(cpds))


        bar(A.DataPlot3,1:ncpds,fcXcpd);
        title(A.DataPlot3,'By cone-null condition');
        ylabel(A.DataPlot3,'Mean pursuit projection');
        xlabel(A.DataPlot3,'Condition');
        set(A.DataPlot3,'XTickLabel',labels);
%         if any(fcXcpd>1)
%             huh=1; % How can xcorr give values>1 here
%         end
        axis(A.DataPlot3,[.25 ncpds+.75 -1 1]);
    end
    
  end % methods
    
end % classdef
