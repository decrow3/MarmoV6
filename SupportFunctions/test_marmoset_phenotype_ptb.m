function report = test_marmoset_phenotype_ptb(calibrationSource,screenNumber,monitorIdentifier)
% TEST_MARMOSET_PHENOTYPE_PTB Operator-run framebuffer integration test.

if nargin < 2 || isempty(screenNumber)
    screenNumber = max(Screen('Screens'));
end
if nargin < 3 || isempty(monitorIdentifier)
    error('test_marmoset_phenotype_ptb:MonitorRequired', ...
        'Provide the active rig monitor identifier explicitly.');
end
bank = marmoview.marmosetPhenotypeConditionBank(calibrationSource,struct( ...
    'ExpectedMonitorIdentifier',monitorIdentifier,'ContrastLevels',1));
if ~strcmpi(bank.Conditions(1).GammaApplication,'software-encoded')
    error('test_marmoset_phenotype_ptb:GammaPolicy', ...
        'This integration test currently requires software-encoded gamma.');
end

PsychDefaultSetup(0);
PsychImaging('PrepareConfiguration');
PsychImaging('AddTask','General','FloatingPoint32BitIfPossible', ...
    'disableDithering',1);
background = bank.Conditions(1).BackgroundFramebufferRGB255;
[window,rect] = PsychImaging('OpenWindow',screenNumber,background);
cleanup = onCleanup(@() sca);
Screen(window,'BlendFunction',GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);
centres = [rect(3)/3 2*rect(3)/3;rect(4)/2 rect(4)/2];

template = struct('ConditionID','','RequestedNegativeRGB255',[], ...
    'RequestedPositiveRGB255',[],'CapturedNegativeRGB255',[], ...
    'CapturedPositiveRGB255',[],'MaximumCaptureError',NaN, ...
    'FlipTimestamp',NaN);
report = repmat(template,numel(bank.Conditions),1);
for ii = 1:numel(bank.Conditions)
    condition = bank.Conditions(ii);
    colours = [condition.NegativeFramebufferRGB255(:), ...
        condition.PositiveFramebufferRGB255(:)];
    rgba = [colours;255 255];
    Screen('FillRect',window,background);
    Screen('DrawDots',window,centres,80,rgba,[0 0],0);
    image = Screen('GetImage',window,rect,'backBuffer');
    negative = double(reshape(image(round(centres(2,1)), ...
        round(centres(1,1)),1:3),1,3));
    positive = double(reshape(image(round(centres(2,2)), ...
        round(centres(1,2)),1:3),1,3));
    captureError = max(abs([negative-colours(:,1)'; ...
        positive-colours(:,2)']),[],'all');
    if captureError > 2
        error('test_marmoset_phenotype_ptb:FramebufferMismatch', ...
            'Condition %s capture error is %.3f codes.', ...
            condition.ConditionID,captureError);
    end
    report(ii).ConditionID = condition.ConditionID;
    report(ii).RequestedNegativeRGB255 = colours(:,1)';
    report(ii).RequestedPositiveRGB255 = colours(:,2)';
    report(ii).CapturedNegativeRGB255 = negative;
    report(ii).CapturedPositiveRGB255 = positive;
    report(ii).MaximumCaptureError = captureError;
    report(ii).FlipTimestamp = Screen('Flip',window);
    WaitSecs(0.25);
end
clear cleanup
fprintf('test_marmoset_phenotype_ptb: all framebuffer checks passed.\n');
end
