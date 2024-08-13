classdef PR_Acuity_Continuous < handle
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
       FrameCount double = 1;
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
  end
  
  methods (Access = public)
    function o = PR_Acuity_Continuous(winPtr)
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
           % nothing for this protocol
           
           % Spatial frequency sampling
           lx = log(P.minFreq):((log(P.maxFreq)-log(P.minFreq))/P.FreqNum):log(P.maxFreq);
           sf_sampling =  exp(lx); % [2 4 6 8 10 12]; 

            % Generate trials list
            o.trialsList = [];
            for zk = 1:size(sf_sampling,2)
                for k = 1:P.apertures   % do both choice directions
                   %**********
                    stimori = 90;  %always vertical
                    ango = (((k-1)/P.apertures)*2*pi) + (pi/4);
                    xpos = P.ecc * cos(ango);
                    ypos = P.ecc * sin(ango);
                    %*************
                    mjuice = 2 + floor(sf_sampling(zk)/2);  % give more juice for higher spatial freq
                    if (mjuice > P.rewardNumber)
                        mjuice = P.rewardNumber;
                    end
                    %*************
                    % storing list of trials, [Choice_xpos Choice_ypos  SpatFreq Phase Ori Juice_Amount] 
                    o.trialsList = [o.trialsList ; [xpos ypos sf_sampling(zk) 0  stimori mjuice]];
                    o.trialsList = [o.trialsList ; [xpos ypos sf_sampling(zk) 90 stimori mjuice]];
                end
            end           
    end
    
    function P = next_trial(o,S,P)
          %********************
          o.S = S;
          o.P = P;       
          %*******************

         %******* init Noise History with MaxDuration **************

          if P.runType == 1   % go through trials list    
                i = o.trialIndexer.getNextTrial(o.error);
                %****** update trial parameters for next trial
                P.choiceX = o.trialsList(i,1);
                P.choiceY = o.trialsList(i,2);
                P.xDeg = 0;% P.choiceX;  % detection task, choice is at target
                P.yDeg = 0;%P.choiceY;
                P.cpd = o.trialsList(i,3);  
                P.phase = o.trialsList(i,4);
                P.orientation = o.trialsList(i,5);
                P.rewardNumber = o.trialsList(i,6);
             


          % Generate a continous series of x, y target postions from white
          % gaussian velocities
            % Save random seed here? Already saved in P.rngbeforetrial
            vx=randn(1, o.MaxFrame-1).*o.P.speed./S.frameRate; %speed deg/s, rate frames/sec to deg/frame
            vy=randn(1, o.MaxFrame-1).*o.P.speed./S.frameRate;
            posx=zeros(1,o.MaxFrame);
            posy=zeros(1,o.MaxFrame);
            for ii=2:o.MaxFrame
                posx(ii)=posx(ii-1)+vx(ii-1);
                posy(ii)=posy(ii-1)+vy(ii-1);
            end

            P.targxvect=posx;
            P.targyvect=posy;

            % Clear any previous traces (already stored in PR)
            o.ProbeHistory = zeros(o.MaxFrame,5);  % time,x,y,sf,fixated
            o.Traces = zeros(o.MaxFrame,6);  % time,targx,targy,eyex,eyey, fixgood

               %******************
                o.P = P;  % set to most current

          end
          
          % Calculate this for pie slice windowing for choice
          o.stimTheta = atan2(P.choiceY,P.choiceX);
          switch P.mode
              case 0
                  % Make Gabor stimulus texture
                  o.hProbe.pixperdeg =S.pixPerDeg;
                  o.hProbe.position = [(S.centerPix(1) + round(P.xDeg*S.pixPerDeg)),(S.centerPix(2) - round(P.yDeg*S.pixPerDeg))];
                  o.hProbe.radius = round(P.radius*S.pixPerDeg);
                  o.hProbe.orientation = P.orientation; % vertical for the right
                  o.hProbe.phase = P.phase;
                  o.hProbe.cpd = P.cpd;
                  o.hProbe.range = P.range;
                  o.hProbe.square = logical(P.squareWave);
                  o.hProbe.bkgd = P.bkgd;
                  o.hProbe.updateTextures();
                  %******************************************
              case 1
                  %Optic flow
                  o.hProbe(1).position = [(S.centerPix(1) + round(P.xDeg*S.pixPerDeg)),(S.centerPix(2) - round(P.yDeg*S.pixPerDeg))];
                    o.hProbe(1).f= 0.100; %0.01
                    o.hProbe(1).depth= 10; %2
                    o.hProbe(1).size= (S.pixPerDeg/P.cpd)/2; %half a cycle (in pixels)
                    o.hProbe(1).vxyz= [0 0 -.1];
                    o.hProbe(1).nDots= 2500;
                    o.hProbe(1).transparent= 0.5000;
                    o.hProbe(1).pixperdeg= S.pixPerDeg;
                    o.hProbe(1).screenRect= S.screenRect;
                    o.hProbe(1).colour= [1 1 1];
                    o.hProbe(1).bkgd= 127;
                    o.hProbe(1).maxRadius= inf;
                    o.hProbe(1).lifetime= 30;
                    o.hProbe(1).Xtop=  S.screenRect(3);
                    o.hProbe(1).Xbot=  S.screenRect(1);
                    o.hProbe(1).Ytop=  S.screenRect(2);
                    o.hProbe(1).Ybot=  S.screenRect(4);
                    o.hProbe(1).beforeTrial();
          end
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
          o.FrameCount =1;
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
        o.ProbeHistory(o.FrameCount,1)=screenTime;
        keepgoing = 0;
        if (o.state < 9)
            keepgoing = 1;
        end
    end
   
    %******************** THIS IS THE BIG FUNCTION *************
    function drop = state_and_screen_update(o,currentTime,x,y,varargin)  
        drop = 0;
        %******* THIS PART CHANGES WITH EACH PROTOCOL ****************
        
        % POLAR COORDINATES FOR PIE SLICE METHOD, note three values of polT to
        % ensure atan2 discontinuity does not wreck shit
        polT = atan2(y,x)+[-2*pi 0 2*pi];
        polR = norm([x y]);

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
        dist=(x-targx).^2+(y-targy).^2;
       
        if ((o.state == 3) || (o.state == 4)) && dist < o.P.targWinRadius
            o.state = 3; % stay in/reenter state
            %Reward if followed stim for 1 second
            if ~o.error && o.rewardCount < o.P.rewardNumber && (currentTime-o.lastReward)>o.RewardDur
                   o.rewardCount = o.rewardCount + 1;
                   drop = 1;
                   o.lastReward=GetSecs;
            end
            
        elseif ((o.state == 3) || (o.state == 4)) && dist > o.P.targWinRadius
            o.state = 4; %enter grace period for lost target
            o.lostStart = GetSecs;
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
        o.hProbe.position = [(o.S.centerPix(1) + round(o.P.targxvect(o.FrameCount)*o.S.pixPerDeg)),(o.S.centerPix(2) - round(o.P.targyvect(o.FrameCount)*o.S.pixPerDeg))];
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
        
        targX =o.Traces(:,2);
        targY =o.Traces(:,3);
        eyeX =o.Traces(:,4);
        eyeY =o.Traces(:,5);

        plot(h,targX,targY,'k.')
        plot(h,eyeX(o.Traces(:,6)==1),eyeY(o.Traces(:,6)==1),'b.')
        plot(h,eyeX(o.Traces(:,6)~=1),eyeY(o.Traces(:,6)~=1),'r.')



        
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
        PR.cpd = P.cpd;
        %******* this is also where you could store Gabor Flash Info

        if o.FrameCount == 0
            PR.Traces = [];
            PR.ProbeHistory = [];
        else
            PR.Traces            = o.Traces(1:o.FrameCount,:);
            PR.ProbeHistory     = o.ProbeHistory(1:o.FrameCount,:);
        end
        
        
        %%%% Record some data %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %data across trials
        %Remove first 0.25s since fixation gives starting position for free
        o.Traces(1:round(0.25*o.S.frameRate),6)=0;
        targX =o.Traces(o.Traces(:,6)==1,2); targvX=diff(targX);
        targY =o.Traces(o.Traces(:,6)==1,3); targvY=diff(targY);
        eyeX =o.Traces(o.Traces(:,6)==1,4); 
        eyeY =o.Traces(o.Traces(:,6)==1,5); 
        
        % We are going to correlate spped rather than position, saccades are going to mess with that so 
        %smooth eyetraces over time with a 100ms filter before taking speed, to 
        eyevX=diff(smooth(eyeX,round(0.1*o.S.frameRate))); 
        eyevY=diff(smooth(eyeY,round(0.1*o.S.frameRate))); 
        nvalid=nnz(o.Traces(:,6)==1);
        % 
        % %+-1 second correlation window,
        % CCG=xcorr(eyevX+j*eyevY,targvX+j*targvY,o.S.frameRate);
        % CCG=smooth(CCG,5);
%         plot(-o.S.frameRate:o.S.frameRate,abs(CCG))
%         max(abs(CCG))

%vector from eye position to target
eyetargX=(targX-eyeX);
eyetargY=(targY-eyeY);

% angle b/n direction of target and direction of eye velocities,
% cos(theta)=(a.b)/(|a||b|)
proj=nanmean((eyevX.*eyetargX(2:end)+eyevY.*eyetargY(2:end))./(sqrt(eyevX.^2+eyevY.^2).*sqrt(eyetargX(2:end).^2+eyetargY(2:end).^2)));

%Cross corr between vector to center, and vector speed
CCG=xcorr(eyevX+j*eyevY,eyetargX(2:end)+j*eyetargY(2:end),240);

        o.D.ccg(A.j,:)=CCG;
        o.D.proj(A.j,:)=proj;
        o.D.nvalid(A.j)=nvalid;
        o.D.error(A.j) = o.error;
        o.D.xDeg(A.j) = P.xDeg;
        o.D.yDeg(A.j) = P.yDeg;
        o.D.x(A.j) = P.choiceX; 
        o.D.y(A.j) = P.choiceY; 
        o.D.cpd(A.j) = P.cpd;
        

        %%%% Plot results %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


        %Also want to plot mean distance to help correct calibration
        offX=targX-eyeX;
        offY=targY-eyeY;
        plot(A.DataPlot1,0,0,'kx');
        plot(A.DataPlot1,offX,offY,'b.');
        
        set(A.DataPlot1,'DataAspectRatio',[1 1 1],'XLim',[-o.targWinRadius o.targWinRadius],'YLim',[-o.targWinRadius o.targWinRadius]);
        title(A.DataPlot1,'Eye-target (calib) error ');
% 


        % Dataplot3, fraction correct by cycles per degree
        % This plot only calculates the fraction correct for trials list cpds.
        cpds = unique(o.trialsList(:,3));
        ncpds = size(cpds,1);
        fcXcpd = zeros(1,ncpds);
        proj_all = zeros(1,ncpds);
        labels = cell(1,ncpds);
        CCG_all= zeros(o.S.frameRate*2+1,ncpds);
        for i = 1:ncpds
            cpd = cpds(i);

            % Combine CCGs, weight by nvalues so to not get thrown off by
            % outliers
            if ~isempty (o.D.nvalid(:,o.D.cpd == cpd))
                CCG_all(:,i)=sum(o.D.nvalid(:,o.D.cpd == cpd)*o.D.ccg(o.D.cpd == cpd,:),1);
                CCG_all(:,i)=CCG_all(:,i)./sum(o.D.nvalid(:,o.D.cpd == cpd));
                proj_all(:,i)=nanmean(o.D.proj(o.D.cpd == cpd,:),1);
            end

            % When active track is lost, a bunch of eyemovements are often
            % made during a recovery search, this generates correlations
            % over the entire CCG, need to remove baseline to get real peak
            % fcXcpd(i) = max(abs(CCG_all(o.S.frameRate:end,i)))-median(abs(CCG_all(:,i)));

            fcXcpd(i) = max(abs(CCG_all(o.S.frameRate:end,i)))-median(abs(CCG_all(:,i)));
            fcXcpd(i) = proj_all(i);
            labels{i} = num2str(round(cpd)); %num2str(round(10*cpd)/10);
        end
        
        %Plot most recent cpd presented
        i=find(cpds==P.cpd);
        plot(A.DataPlot2,(-o.S.frameRate:o.S.frameRate)./o.S.frameRate,abs(CCG_all(:,i)),'b',(-o.S.frameRate:o.S.frameRate)./o.S.frameRate,ones(length(CCG_all(:,i)),1)*median(abs(CCG_all(:,i))),'r-')
        title(A.DataPlot2,['CCG ' num2str(P.cpd)]);
        
        %legend(A.DataPlot2,num2str(cpds))


        bar(A.DataPlot3,1:ncpds,fcXcpd);
        title(A.DataPlot3,'By Cycles per Degree');
        ylabel(A.DataPlot3,'Max CCG');
        set(A.DataPlot3,'XTickLabel',labels);
%         if any(fcXcpd>1)
%             huh=1; % How can xcorr give values>1 here
%         end
        %if max(fcXcpd)>1
            axis(A.DataPlot3,[.25 ncpds+.75 0 max([max(fcXcpd) 0.1])]);
        % else
        %     axis(A.DataPlot3,[.25 ncpds+.75 0 1]);
        % end
    end
    
  end % methods
    
end % classdef
