classdef PR_GazeCalibRefine < protocols.protocol
  % Experimental protocol for refining gaze calibration on the fly.
  % Handles adaptive target placement near calibrated eye position.
  % Smooths eye velocity for saccade detection.
  % Progressive fixation hold shaping with grace period for momentary breaks.
  % Updates calibration parameters online.
  
  properties (Access = public)
    itiStart double = 0               % ITI start time
    states double                    % state transitions [state; time]
    stimXY double                   % stimulus positions (pixels)
    eyeXY double                    % eye positions (dva)
    eyePix0

    lastEyePos double               % last calibrated eye position (dva)
    eyeVelThresh double             % eye velocity threshold (deg/frame)
    rewardCount double = 0          % reward counter
    
    useFace logical = true          % use faces as targets

    fixHoldDuration double = 0.2    % current fixation hold duration (sec)
    maxFixHoldDuration double = 1.0 % max fixation hold duration (sec)

    refractoryDur double = 0.5      % refractory period between target shows (sec)
    stimDur double = 0.5            % stimulus display duration (sec)
    fixGraceDur double = 0.3        % fixation break grace duration (sec)
    trialDuration double = 5.0      % total trial duration (sec)
    stimPositionsPix_all=[]
    eyePositionsPix_all=[]
  end

  properties (Access = private)
    TrialIndexer                    % trial selection helper
    trialsList                     % trial list copy

    Faces                         % face stimuli
    hFix                          % fixation point stimulus
    hTarg                         % current target stimulus
    fixbreak_sound                % fix break sound
    fixbreak_sound_fs             % sound sample rate

    D = struct                    % data struct for stats
    saccadeDetected logical = false % flag for saccade detected
    
    eyeVelBuffer double = zeros(5,1) % buffer for smoothed eye velocity
    fixBreakStartTime double = NaN  % timestamp when fixation break started
  end

  methods (Access = public)
    function o = PR_GazeCalibRefine(winPtr, varargin)
      o = o@protocols.protocol(winPtr);
    end
    
    function initFunc(o,S,P)
      o.Faces = stimuli.gaussimages(o.winPtr,'bkgd',S.bgColour,'gray',false);
      o.Faces.loadimages('./SupportData/MarmosetFaceLibrary.mat');
      o.Faces.position = [0,0]*S.pixPerDeg + S.centerPix;
      o.Faces.radius = round(P.targRadius * S.pixPerDeg);
      o.Faces.imagenum = 1;

      o.hFix = stimuli.fixation(o.winPtr);
      sz = P.targRadius * S.pixPerDeg;
      o.hFix.cSize = sz;
      o.hFix.sSize = 2*sz;
      o.hFix.cColour = ones(1,3);
      o.hFix.sColour = repmat(255,1,3);
      o.hFix.position = [0,0]*S.pixPerDeg + S.centerPix;
      o.hFix.updateTextures();

      [y,fs] = audioread(['SupportData',filesep,'gunshot_sound.wav']);
      y = y(1:floor(length(y)/3), :);
      o.fixbreak_sound = y;
      o.fixbreak_sound_fs = fs;
    end

    function closeFunc(o)
      o.Faces.CloseUp();
      o.hFix.CloseUp();
    end

    function P = next_trial(o,S,P)
      o.S = S; o.P = P;
      o.Faces.imagenum = randi(length(o.Faces.tex));
      o.hFix.updateTextures();
      if o.P.useFace
        o.hTarg = o.Faces;
      else
        o.hTarg = o.hFix;
      end
      o.hTarg.position = S.centerPix; % initial target position
    end

    function [FP,TS] = prep_run_trial(o)
      FP(1).states = 1:3; FP(1).col = 'b';
      FP(2).states = 4; FP(2).col = 'g';
      TS = 1:2;

      o.state = 0;
      o.startTime = GetSecs;
      o.Iti = o.P.iti;

      %o.states = [o.states [o.state; o.startTime]];
      o.states = [0; o.startTime];
      o.stimXY = nan(2,1);
      o.eyeXY = nan(2,1);

      frameDuration = 1 / o.S.frameRate;
      o.eyeVelThresh = o.P.eyeVelThresh * frameDuration;

      o.lastEyePos = [0 0];
      o.saccadeDetected = false;
      o.eyeVelBuffer = zeros(5,1);

      o.fixHoldDuration = 0.2;
      o.fixBreakStartTime = NaN;
    end

    function keepgoing = continue_run_trial(o,~)
      keepgoing = o.state < 3;
    end

    function drop = state_and_screen_update(o, currentTime, x, y, varargin)
      % x,y are calibrated eye positions (dva)
      drop = false;

      % Smooth eye velocity over last 5 frames
      instantVel = hypot(x - o.lastEyePos(1), y - o.lastEyePos(2));
      o.eyeVelBuffer = [o.eyeVelBuffer(2:end); instantVel];
      smoothedVel = mean(o.eyeVelBuffer);

      TimeSinceLastState = currentTime - o.states(2,end);
      o.lastEyePos = [x y];
      switch o.state
        case 0
          if TimeSinceLastState > o.P.refractoryDur && smoothedVel < o.eyeVelThresh
            if rand() < o.P.probShow
              o.state = 1;
              o.states = [o.states [o.state; GetSecs]];
              %stimPosPix = o.S.centerPix + o.lastEyePos .* o.S.pixPerDeg;
              o.stimXY = [o.stimXY nan(2,1)];
              o.eyeXY = [o.eyeXY o.lastEyePos'];
              o.eyePix0 = []; %reset stim
              return
            end
          end

          case 1 %Draws the stimuli
          offsetMaxPix = 2.5.* o.S.pixPerDeg;
          offsetMinPix = 1.* o.S.pixPerDeg;           
          % When converting to pixels from dva  we need to 
          % flip y axis to match pixel coordinates (counts from the top)
          
          eyePix = o.S.centerPix + o.lastEyePos.*[1 -1] .* o.S.pixPerDeg;
          if isempty(o.eyePix0) % Fresh stim needs to be initialised
              o.eyePix0=eyePix;
              targetPos=eyePix+0.5*offsetMaxPix*randn(1,2);
          else %keep current location but update with jitter
              targetPos=o.hTarg.position; 
              %targetOffset=targetPos-eyePix0;
          end

          jitterPix = 0.1 * randn(1,2).* o.S.pixPerDeg;
          targetPos=targetPos + jitterPix;

          targetOffset=targetPos-o.eyePix0; %Distance 
          if norm(targetOffset) > offsetMaxPix
            targetOffset = (targetOffset / norm(targetOffset)) * offsetMaxPix;
          elseif norm(targetOffset) < offsetMinPix
            targetOffset = (targetOffset / norm(targetOffset)) * offsetMinPix;
          end

         targetPos = o.eyePix0 + targetOffset;
          o.hTarg.position = targetPos;
          o.hTarg.beforeFrame();

          if smoothedVel > o.eyeVelThresh %require a saccade to go into fix
            o.state = 2;
            o.states = [o.states [o.state; GetSecs]];
            o.stimXY = [o.stimXY targetPos'];
            o.eyeXY = [o.eyeXY o.lastEyePos'];
%             drop = true; %reward held fixations instead of saccades
            o.saccadeDetected = true;
            o.fixBreakStartTime = NaN; % reset break timer on saccade start
            return
          end

          if TimeSinceLastState > o.P.stimDur
            o.state = 0;
            o.states = [o.states [o.state; GetSecs]];
            o.stimXY = [o.stimXY nan(2,1)];
            o.eyeXY = [o.eyeXY o.lastEyePos'];
            return
          end

        case 2
          o.hTarg.beforeFrame();
          holdTime = TimeSinceLastState;
          distToTarget = norm(o.hTarg.position - (o.lastEyePos .* o.S.pixPerDeg + o.S.centerPix));

          if distToTarget < o.P.fixWinRadius * o.S.pixPerDeg
            % Fixation inside window: clear grace timer
            o.fixBreakStartTime = NaN;

            if holdTime >= o.fixHoldDuration
              drop = true;
              o.rewardCount = o.rewardCount + 1;
              o.fixHoldDuration = min(o.fixHoldDuration + 0.1, o.maxFixHoldDuration);

              o.state = 0;
              o.states = [o.states [o.state; GetSecs]];
              o.stimXY = [o.stimXY o.hTarg.position']; %hold stim location
              o.eyeXY = [o.eyeXY o.lastEyePos'];
              return
            end

          else
            % Fixation outside window: start or continue grace timer
            if isnan(o.fixBreakStartTime)
              o.fixBreakStartTime = GetSecs;
            else
              if (GetSecs - o.fixBreakStartTime) > o.P.fixGraceDur
                % Grace exceeded: abort fixation hold
                o.state = 0;
                o.states = [o.states [o.state; GetSecs]];
                o.stimXY = [o.stimXY nan(2,1)];
                o.eyeXY = [o.eyeXY o.lastEyePos'];
                o.fixBreakStartTime = NaN;
                return
              end
            end
          end

        case 3
          o.stimXY = [o.stimXY nan(2,1)];
          o.eyeXY = [o.eyeXY o.lastEyePos'];
          return
      end

      % Trial timeout
      if (currentTime - o.startTime) > o.P.trialDuration
        o.state = 3;
        o.states = [o.states [o.state; GetSecs]];
        o.stimXY = [o.stimXY nan(2,1)];
        o.eyeXY = [o.eyeXY o.lastEyePos'];
      end
    end

    function Iti = end_run_trial(o)
      Iti = o.Iti - (GetSecs - o.itiStart);
    end

    function plot_trace(o, handles)
      h = handles.EyeTrace;
      set(h,'NextPlot','Replace');
      eyeRad = handles.eyeTraceRadius;

      r = o.P.fixWinRadius;
      fixX = 0; fixY = 0;
      plot(h, fixX + r*cos(0:.01:2*pi), fixY + r*sin(0:.01:2*pi), '--k');
      set(h,'NextPlot','Add');

      state2Idx = find(o.states(1,:) == 2); 
      o.states(1,:)
      if ~isempty(state2Idx) && size(o.states,2) == size(o.stimXY,2)
        stimXYplot = o.stimXY(:,state2Idx);
        eyeXY0 = o.eyeXY(:,state2Idx-1);
        eyeXYvel = o.eyeXY(:,state2Idx) - eyeXY0;
        stimDVA = [1 -1]'.*(stimXYplot - o.S.centerPix') ./ o.S.pixPerDeg;

        plot(h, stimDVA(1,:), stimDVA(2,:), 'ok');
        quiver(h, eyeXY0(1,:), eyeXY0(2,:), eyeXYvel(1,:), eyeXYvel(2,:), 0);
      end

      axis(h, [-eyeRad eyeRad -eyeRad eyeRad]);

      %if isfield(handles, 'C')
        [cNew, dxNew, dyNew] = o.update_calibration(handles);
        handles.FC.update_eye_calib(cNew, dxNew, dyNew)
%         handles.C.c = cNew;
%         handles.C.dx = dxNew;
%         handles.C.dy = dyNew;
      %end
    end

    function [cNew, dxNew, dyNew] = update_calibration(o, handles)
      goodidx=(~isnan(o.stimXY(1,:))&(~isnan(o.eyeXY(1,:))));
      stimPositions = o.stimXY(:,goodidx);
      eyePositionsDVA = o.eyeXY(:,goodidx);

      if isempty(stimPositions) || isempty(eyePositionsDVA)
        cNew = handles.C.c;
        dxNew = handles.C.dx;
        dyNew = handles.C.dy;
        return
      end

      %Stim positions in degrees from pixels (why not keep it in pixels?) 
      stimDVA = [1 -1]'.*(stimPositions - o.S.centerPix') ./ o.S.pixPerDeg;
      eyePositionsPix = [1 -1]'.*(eyePositionsDVA.*o.S.pixPerDeg) + o.S.centerPix';

       o.stimPositionsPix_all=[o.stimPositionsPix_all stimPositions];
       o.eyePositionsPix_all=[o.eyePositionsPix_all eyePositionsPix];


      cOld = handles.C.c;
      dxOld = handles.C.dx;
      dyOld = handles.C.dy;

      EyeOffsetsPix = o.stimPositionsPix_all - o.eyePositionsPix_all;
      n_samples=size(o.stimPositionsPix_all,2);

      %Reg parameters, will be to be more seriously tuned for the real data
      midpoint=100;k=0.05;
      Weighting=1/(1+exp(-k*(n_samples-midpoint))); %logistic

      %Hopefully the error is decreasing as the calibration is refined
      %every trial
      cNewPix=cOld-Weighting*mean(EyeOffsetsPix,2)';

      %cNew = (cNewPix .* o.S.pixPerDeg).*[1 -1]' + o.S.centerPix; %Back into screen pix, flip y
      cNew = cNewPix;
      dxNew = dxOld;
      dyNew = dyOld;

      fprintf('Calibration updated: center=[%.3f, %.3f]\n', cNew(1), cNew(2));
    end

    function PR = end_plots(o,P,A)
      warning('off');
      PR = struct(o);
      warning('on');

      if o.error == 0
        o.D.error(A.j) = 0;
      else
        o.D.error(A.j) = o.error;
      end
    end
  end
end
