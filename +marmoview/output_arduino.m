% Code for sending arduino timing signals high and low, would be nice to
% also keep track of state of bits and read from the arduino

classdef output_arduino < matlab.mixin.Copyable
    %******* basically is just a wrapper for a bunch of calls to the
    % arduino toolbox.
    
    % MarmoviewArduinoTTLs_1_1, connecting an arduino at 2,000,000 baud 
    % eg write '14,1110/n' <-- no spaces. 
    % 
    % Value before comma gets written into available bits ignoring others
    % For example '7,1111' writes the states '0111' (7 in binary) but
    %'7,1110' writes to '111x' leaving the last bit in same state as it was
    % previously. This can be very confusing, useful for sending fewest
    % characters as possible for fast signals. 
    % 
    % 20000000 baud at 10bits per character, 200,000 characters/sec. 8
    % characters at 0.005ms is 0.04ms, but doubtful arduino can actually
    % respond that fast. 

    % By printing the loop time on the arduino you get ~176,000 polling
    % loops per second, this drops to ~130,000 polling loops per second
    % when receiving and setting a signal. So a single send may take the
    % equalent of 43000 loops at 176000Hz, or 0.2443 seconds.
    % Variable, but up to .5s delay

    %Use the Photodiode signal for 'real' syncing
    
    properties (SetAccess = public, GetAccess = public)
        arduinoUno % handle to the IOport 
        timeOpened double
        timeLastSample double
        scaleFactor double
        rewardMode char
        locationSpace double
        maxFrames double 
        rewardDist
        rewardProb
        UseAsEyeTracker logical

        StartTimings %Holds the output hardware times for trial starts
        EndTimings %Holds the output hardware times for trial endings

        offset
        wheelPos
        wheelPosRaw
    end
    
    properties (SetAccess = private, GetAccess = public)
        port
        baud
        nextReward
        frameCounter double 
    end
    
    methods
        function self = output_arduino(varargin) % h is the handle for the marmoview gui
            
            % initialise input parser
            ip = inputParser;
            ip.addParameter('port',[]);
            ip.addParameter('baud', 2000000)
            ip.addParameter('scaleFactor', [])
            ip.addParameter('rewardMode', 'dist')
            ip.addParameter('maxFrames', 5e3)
            ip.addParameter('rewardDist', 94.25./15)
            ip.addParameter('rewardProb', 1)
            ip.addParameter('UseAsEyeTracker',false,@islogical); % default false
            ip.parse(varargin{:});
            
            args = ip.Results;
            fields = fieldnames(args);
            for i = 1:numel(fields)
                self.(fields{i}) = args.(fields{i});
            end

            config=sprintf('BaudRate=%d ReceiveTimeout=0.1', self.baud); %DTR=1 RTS=1 
        
            [self.arduinoUno, ~] = IOPort('OpenSerialPort', self.port, config);
            self.timeOpened = GetSecs();
            self.timeLastSample = self.timeOpened;
            
            self.frameCounter = 1;
%             self.locationSpace = nan(self.maxFrames, 5); % time, timestamp, loc, locScale, rewardState
%             
%             self.nextReward = self.rewardDist;
        end
        
        
    end % methods
    
    methods (Access = public)
        
        function out = afterFrame(self, currentTime, rewardState)
            
            self.frameCounter = self.frameCounter + 1;
        end 

        function startfile(self,~)
        end    
        
        function closefile(self,~)
        end        
        
        function init(self,~)
        end

        function readinput(self,~)
        end

        function starttrial(self,STARTCLOCK,STARTCLOCKTIME)
            % Set first bit high
            bitmask='0001';
            value=1;
            datastring = sprintf([num2str(value,'%02.f') ',' bitmask newline]);
            t(1)=GetSecs;
            [nwritten, when, errmsg, prewritetime, postwritetime, lastchecktime] = IOPort('Write', self.arduinoUno, datastring, 1);
            t(2)=GetSecs;   

            StartTimings=[mean(t) when diff(t)];   
        end

        function endtrial(self,ENDCLOCK,ENDCLOCKTIME)
           % Set first bit low
            bitmask='0001';
            value=0;
            datastring = sprintf([num2str(value,'%02.f') ',' bitmask newline]);
            t(1)=GetSecs;
            [nwritten, when, errmsg, prewritetime, postwritetime, lastchecktime] = IOPort('Write', self.arduinoUno, datastring, 1);
            t(2)=GetSecs;   

            EndTimings=[mean(t) when diff(t)];
        end

        function unpause(self,~)
        end
        
        function pause(~)
        end
        
        function timings=flipBit(self,bit,value)
            %pds.datapixx.flipBitVideoSync    flip a bit at the next VSync
            % no longer flips on VideoSync -> slows everything down

            bitmask=dec2bin(2^(bit-1));
            datastring = sprintf([num2str(value,'%02.f') ',' bitmask newline]);
            t(1)=GetSecs;
            [nwritten, when, errmsg, prewritetime, postwritetime, lastchecktime] = IOPort('Write', self.arduinoUno, datastring, 1);
            t(2)=GetSecs;   
    

            timings=[mean(t) when diff(t)];
        end

        function reset(self)
            %IOPort('Write', self.arduinoUno, 'reset');
            self.nextReward = self.rewardDist;
            self.frameCounter = 1;
            self.locationSpace(:) = nan;
            IOPort('Flush', self.arduinoUno);
        end
        
        function close(self)
            if ~isempty(self.arduinoUno)
                IOPort('Close', self.arduinoUno)
                self.arduinoUno = [];
            end
        end
    end % private methods
    
    methods (Static)
       
        
    end
    
end % classdef
