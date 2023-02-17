% class instantiation for a steering wheel hooked up to a rotary encoder
% and arduino running ... .ino and spitting out an outout on the serial 

% This is an input class, should follow a similar structure to the
% eyetracker. Modifying the treadmill class

% Needs; init, startfile, closefile, unpause, pause, afterFrame, endtrial,
% getgaze-> change to getinput??

classdef steering_wheel_arduino < matlab.mixin.Copyable
    %******* basically is just a wrapper for a bunch of calls to the
    % arduino toolbox. based on code snippet from huklabBasics
    %     https://github.com/HukLab/huklabBasics/blob/584b5d277ba120b2e33e4f05c0657cacde67e1fa/%2Btreadmill/pmTread.m
    
    properties (SetAccess = public, GetAccess = public)
        arduinoUno % handle to the IOport 
        timeOpened double
        timeLastSample double
        scaleFactor double
        rewardMode char
        locationSpace double
        maxFrames double


        offset
        wheelPos
        trace
        rawtrace
        gain



    end
    
    properties (SetAccess = private, GetAccess = public)
        port
        baud
    end
    
    methods
        function self = steering_wheel_arduino(varargin) % h is the handle for the marmoview gui
            
            % initialise input parser
            ip = inputParser;
            ip.addParameter('port',[]);
            ip.addParameter('baud', 115200)
            ip.addParameter('scaleFactor', [])
            ip.addParameter('rewardMode', 'dist')
            ip.addParameter('maxFrames', 5e3)
            ip.addParameter('rewardDist', 94.25)
            ip.addParameter('rewardProb', 1)
            ip.parse(varargin{:});
            
            args = ip.Results;
            fields = fieldnames(args);
            for i = 1:numel(fields)
                self.(fields{i}) = args.(fields{i});
            end

            config=sprintf('BaudRate=%d ReceiveTimeout=.1', self.baud); %DTR=1 RTS=1 
        
            [self.arduinoUno, ~] = IOPort('OpenSerialPort', self.port, config);
            self.timeOpened = GetSecs();
            self.timeLastSample = self.timeOpened;
            
            self.frameCounter = 1;
            self.locationSpace = nan(self.maxFrames, 5); % time, timestamp, loc, locScale, rewardState
            
            self.nextReward = self.rewardDist;
        end
        
        
    end % methods
    
    methods (Access = public)

        function init(~,~)            
                config='BaudRate=115200 DTR=1 RTS=1 ReceiveTimeout=1'; % orig
                                
                % Open port
                oldverbo = IOPort('Verbosity',0); % don't abort on fail
                [h, errmsg]=IOPort('OpenSerialPort', self.wheel.port, config);   % Mac:'/dev/cu.usbserial' Linux:'/dev/ttyUSB0'
                
                % Reset IOPort verbosity
                IOPort('Verbosity', oldverbo);
                

                %TODO: Redo this for marmoview
%                 if h<0
%                     % if fails to open port, IOPort will return an invalid (-1) handle to signal the failure
%                     fprintf(2, '\n~!~\tUnable to open wheel com on port: %s\n\t%s\tWill attempt to continue with wheel disabled (p.trial.wheel.use=0)\n',p.trial.wheel.port, errmsg);
%                     p.trial.wheel.use = false;
%                     return
%                 end
                
                WaitSecs(0.1);
                if ~isempty(errmsg)
                    error('pds:wheel:setup', 'Failed to open serial Port with message:\n\t%s\n', errmsg);
                end
                self.arduinoUno = h;
                
                % Set initial values
                reset(self)
        end

        function startfile(~,~)
            % no file is saved for this arduio read, but maybe there should
            % be
        end
        
        function closefile(~)
        end
        
        function unpause(~)
            reset(self)
        end
        
        function pause(~)
        end
        
        function drop = afterFrame(~,varargin) %(~,currenttime,drop)
            %Reward based on only input, eg treadmill distance
            drop=varargin{2};
        end
        
        function starttrial(STARTCLOCK,STARTCLOCKTIME)
            reset(self)
        end

        function endtrial(~)
        end
        
        function [wheelPosRaw, timestamp] = readinput(self)

            % TREADMILL CODE IS SO MUCH NEATER -> test and use this?
%             % read from buffer, take last sample
%             msg = IOPort('Read', self.arduinoUno);
%             a = regexp(char(msg), 'time:(?<time>\d+),count:(?<count>\d+),', 'names');
%             if isempty(a)
% %                 disp('message was empty')
%                 count = nan;
%                 timestamp = nan;
%             else
% %                 timestamp = arrayfun(@(x) str2double(x.time), a(end));
% %                 count = arrayfun(@(x) str2double(x.count), a(end));
%                 count = str2double(a(end).count);
%                 timestamp = str2double(a(end).time);
%             end


            [data,when,err]=IOPort('Read', self.arduinoUno);
            
            % Receiving characters from arduino,
            if ~isempty(data) && length(data)>1
                Pos_cells=strsplit(char(data));
                if ~isempty(Pos_cells{end})&& data(end)==10
                    %Last message over serial completed with a new line (ASCII=10)
                    wheelPosRaw=str2double(Pos_cells{end});%-Offset;
                elseif length(Pos_cells)>1 && ~isempty(Pos_cells{end-1})
                    %Get the second last serial message if the last was cut off
                    wheelPosRaw=str2double(Pos_cells{end-1});
                else
                    %Else return empty (and keep previous value in frame update)
                    wheelPosRaw=[];
                end
            else
                %Else return empty (and keep previous value in frame update)
                wheelPosRaw=[];
            end
            timestamp=when;

            %Set handle value for future calls
            self.wheelPosRaw=wheelPosRaw;
            self.timestamp=timestamp;
        end

        function [wheelPos, timestamp] = getinput(self)
            %Call for pulling last value before frame update, this allows
            %us to ensure the inputs are only read once per frame and all
            %frame update codes are deterministic

            %If input call is down in readinput then we could just call the
            % handle directly, but this is here to accomodate additional 
            % gains/offsets at readtime

            % Passthrough from readinput()
            % wheelPos=self.wheelPosRaw;
            timestamp=self.timestamp;


            %get current position and store
            wheelPos0=self.wheelPos;
            Offset=self.Offset; 
            
            
            % Get current position data
            posRaw = self.wheelPosRaw;
        
            if ~isempty(posRaw)
                %Check for over/underflow
                if (posRaw-wheelPos0)>(2^31-2500)
                    posRaw=posRaw-(2^31-1);
                elseif (posRaw-wheelPos0)<-(2^31-2500)
                    posRaw=posRaw+(2^31-1);
                end
            end
            
           %disp(posRaw)
            
            %% "Raw" serial numbers to compare to track, incase it gets lost/bugs out               
            %Getpos returned empty so keep previous value in frame update
            if ~isempty(posRaw)
                  
                self.rawtrace = circshift(self.rawtrace,-1);
                self.rawtrace(end)=posRaw;
                
                wheelPos=posRaw-Offset;
                recent=median(self.rawtrace(end-2:end))-Offset;
            elseif isempty(posRaw) && isempty(wheelPos0)
                %THIS SHOULD NEVER HAPPEN
                wheelPos=0;
                dbstop
                %Do you really want to do this??
            else
                %Keep current value
                wheelPos=wheelPos0;
            end
                   
            %% Noise check, threshold for per frame difference
        %     % Noise check, if the value jumps more than a threshold ignore
        %     if abs(wheelPos-wheelPos0)>4*(-1000/40) && abs(wheelPos-recent)>5*(-1000/40)%&& nnz(p.trial.wheel.trace)>3
        %         %Keep current value
        %         wheelPos=wheelPos0;
        %     elseif abs(wheelPos-recent)>8*(-1000/40) && nnz(p.trial.wheel.rawtrace)>5*(-1000/40)
        %         %Lost the track
        %         wheelPos=recent;
        %     end
            
            %% Apply a transformation to the position to put it into nicer numbers
            %gain= 80;%gain = 10 bf Oct15 %used for a lot pre Sept21: 30; %p.wheel.gain maybe???
            wheelPos= wheelPos/1000 *self.gain;   
        
            %Update position
            self.wheelPos=wheelPos;
            %fprintf(2, '\nUpdating wheel position: %6.3f',p.trial.wheel.wheelPos);
            %TODO:Store a buffer line of previous positions, plot trace
            p.trial.wheel.lastcheck=0;
                
            %Update trace
            self.trace = circshift(self.trace,-1);
            %% Debug
            if numel(self.trace(end))~=numel(wheelPos)
                %Uh oh, something went wrong, probably Offset is empty
                dbstop
            end
            self.trace(end)=wheelPos;
            
        
            %% Drawing a graph for testing    
%                 if p.trial.wheel.testmode==1
%                     axes(p.trial.wheel.traceax);
%                     plot(p.trial.wheel.trace);
%                 end
                


        end
                
        function sendcommand(~,~,~)
        end

        function reset(self)
                 %% Zero out initial value
                Offset=pds.wheel.getPos(p);
                
                %% retry if null
                while isempty(Offset)
                    %This seems fraught, but should work most of the time
                    Offset=pds.wheel.getPos(p);
                end

                [Offset, ~] = readinput(self);%pds.wheel.getPos(p);
                
                self.Offset=Offset; 
                self.wheelPos=0; %initialise wheel position
                self.trace=zeros(1,100);
                self.rawtrace=zeros(1,100);
                
                %This was a debugging device
%                 if p.trial.wheel.testmode==1
%                     %Trace tracking figure
%                     
%                     p.trial.wheel.tracefig=figure(1);
%                     plot(p.trial.wheel.trace);
%                     p.trial.wheel.traceax=gca;
%                 end     
        end
        
        function close(self)
%                 if p.trial.wheel.use
%                     WheelPos = pds.wheel.getPos(p);
%                     p.trial.wheel.wheelPos = WheelPos;
%                     if p.trial.wheel.testmode==1
%                             clf(p.trial.wheel.tracefig);
%                     end
%                 end


            if ~isempty(self.arduinoUno)
                IOPort('Close', self.arduinoUno)
                self.arduinoUno = [];
            end
        end
    end % private methods
    
    methods (Static)
       
        
    end
    
end % classdef
