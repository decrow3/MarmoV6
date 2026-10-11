function validate_hyperplaid_procedural
% Minimal sanity test for hyperplaid_procedural
% Make sure InitializeMatlabOpenGL() was called *before* any window opens.

try
    % 1. Basic setup
    AssertOpenGL;
    InitializeMatlabOpenGL;                     % must be first
    Screen('Preference','SkipSyncTests',1);
    Screen('Preference','VisualDebugLevel',1);
    Screen('Preference','Verbosity',4);
    Screen('Preference','ConserveVRAM',0);

    % 2. Open window
    [win, rect] = Screen('OpenWindow', max(Screen('Screens')), 0.5);
    pixPerDeg = 60;

    % 3. Create procedural hyperplaid
    hp = stimuli.hyperplaid_procedural(win, ...
        'screenRect', rect, ...
        'pixPerDeg', pixPerDeg, ...
        'K', 3, ...
        'contrast', 0.4);

    hp.beforeTrial();
    hp.stimValue = 1;

    % 4. Draw single frame
    hp.beforeFrame();
    vbl = Screen('Flip', win);
    fprintf('Flip done at t=%.3f\n', vbl);

    % 5. Read back image (float)
    img = Screen('GetImage', win, rect, [], 1);
    m = mean(img(:));
    fprintf('GetImage succeeded. Mean intensity = %.4f\n', m);
    size(img)

    % 6. CPU vs GPU compare
    img_=mean(img,3);
    cpu = double(hp.getImage(rect,1))/255;
    size(cpu)
    mae = mean(abs(cpu(:) - img_(:)));
    fprintf('GPU/CPU MAE = %.4f (expected ~<= 0.01)\n', mae);

    % 7. Display briefly
    figure(1); clf;
    subplot(1,2,1); imagesc(img_); axis equal off; title('GPU (shader)');
    subplot(1,2,2); imagesc(cpu); axis equal off; title('CPU recon');
    colormap gray;
    drawnow;

    % 8. Cleanup
    hp.CloseUp();
    Screen('CloseAll');
    fprintf('Validation complete.\n');

catch ME
      Screen('CloseAll');
    rethrow(ME);
end
