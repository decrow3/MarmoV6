function [S,P] = BackImages

%%%%% NECESSARY VARIABLES FOR GUI %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% LOAD THE RIG SETTINGS, THESE HOLD CRUCIAL VARIABLES SPECIFIC TO THE RIG,
% IF A CHANGE IS MADE TO THE RIG, CHANGE THE RIG SETTINGS FUNCTION IN
% SUPPORT FUNCTIONS
S = MarmoViewRigSettings;

% NOTE THE MARMOVIEW VERSION USED FOR THIS SETTINGS FILE, IF AN ERROR, IT
% MIGHT BE A VERSION PROBLEM
S.MarmoViewVersion = '3';

% PARAMETER DESCRIBING TRIAL NUMBER TO STOP TASK
S.finish = 80;

% PROTOCOL PREFIXS
S.protocol = 'BackImages';
S.protocol_class = ['protocols.PR_',S.protocol];
S.ImageDirectory = 'NaturalImages';%'Backgrounds';  % default is Backgrounds directory
                                   % but you can easily choose another
                                   % and place it under SupportData
  
% Define Banner text to identify the experimental protocol
S.protocolTitle = 'Foraging full screen images';

%********** allow calibratin of eye position during running
P.InTrialCalib = 0;
S.InTrialCalib = 'Eye Calib in Trials';

%%%%% END OF NECESSARY VARIABLES %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% This settings is unnecessary because 'MarmoViewLastCalib.mat' is the GUI
% default to use, but because this is an exemplar protocol I decided to
% includee it if for some reason you don't want to use the last calibration
% values (e.g. subjects you are running have substantially different 
% horizontal or vertical gain). Place this calibration file in the
% 'SupportData' directory of MarmoView
S.calibFilename = 'MarmoViewLastCalib.mat';

% If using the gaze indicator, this sets a step value, intensity should be
% between 1 and 5, this is taking advantage of male color blindness to make
% it less obvious to the marmoset than us, but it will still be obvious if
% overwriting textures

%%%%% PARAMETERS -- VARIABLES FOR TASK, CAN CHANGE WHILE RUNNING %%%%%%%%%
% INCLUDES STIMULUS PARAMETERS, DURATIONS, FLAGS FOR TASK OPTIONS
% MUST BE SINGLE VALUE, NUMERIC -- NO STRINGS OR ARRAYS!
% THEY ALSO MUST INCLUDE DESCRIPTION OF THE VALUE IN THE SETTINGS ARRAY

% Stimulus settings
P.eyeRadius = 2.0;
S.eyeRadius = 'Gaze indicator radius (degrees):';
P.eyeIntensity = 20;
S.eyeIntensity = 'Indicator intensity:';
P.showEye = 0;
S.showEye = 'Show the gaze indicator? (0 or 1):';
P.bkgd = 127;
S.bkgd = 'Choose the background color (0-255):';
P.nImages = 104;
S.nImages = 'Number of images to load up';

P.useGrayScale = true;
S.useGrayScale = 'Are the images grayscale (true) or color (false):';

% Trial timing
P.imageDur = 10;
S.imageDur = 'Duration to display image (s):';
P.iti = 2;
S.iti = 'Duration of intertrial interval (s):';

% P.dontsync = 1;
% S.dontsync = 'async Frame Control';
    