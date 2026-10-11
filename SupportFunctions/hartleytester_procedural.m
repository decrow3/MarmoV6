function hartleytester_procedural
% Full diagnostic + validation for hyperplaid_procedural.
% Also compares against hyperplaid_static if available.
%
% Requirements:
%   - Psychtoolbox (AssertOpenGL, InitializeMatlabOpenGL)
%   - stimuli.hyperplaid_procedural (your updated class)
%   - stimuli.hyperplaid_static (optional — for cross-checks)

%% --------- Boot ---------
try
    AssertOpenGL;
    InitializeMatlabOpenGL;                              % must be BEFORE any window opens
    Screen('Preference','SkipSyncTests', 1);
    Screen('Preference','Verbosity', 4);
    Screen('Preference','VisualDebugLevel', 1);

    % (Optional) Float imaging path – not required for onscreen direct rendering
    % PsychImaging('PrepareConfiguration');
    % PsychImaging('AddTask', 'General', 'FloatingPoint32BitIfPossible');
    % [win, rect] = PsychImaging('OpenWindow', max(Screen('Screens')), 0.5);

    [win, rect] = Screen('OpenWindow', max(Screen('Screens')), 0.5);
    Screen('ColorRange', win, 1, 0);                    % unclamped [linear 0..1] math on the onscreen window
    drawnow;

    % MarmoView-ish rig params (customize these to your rig)
    S.screenRect = rect;
    S.pixPerDeg  = 60;

    fprintf('PTB-INFO: Window opened %dx%d, unclamped color range.\n', RectWidth(rect), RectHeight(rect));

    %% --------- Create stimuli (procedural + optional static) ----------
    K_default  = 6;
    contrast   = 0.4;
    spFreq_cpd = 2;     % small test set

    hp = stimuli.hyperplaid_procedural(win, ...
        'screenRect', rect, ...
        'pixPerDeg',  S.pixPerDeg, ...
        'frameRate',  60, ...
        'spatialFrequencies', spFreq_cpd, ...
        'K',          K_default, ...
        'updateEveryNFrames', 1, ...
        'contrast',   contrast);

    haveStatic = (exist('stimuli.hyperplaid_static', 'class') == 8);
    if haveStatic
        hs = stimuli.hyperplaid_static(win, ...
            'screenRect', rect, ...
            'pixPerDeg',  S.pixPerDeg, ...
            'frameRate',  60, ...
            'spatialFrequencies', spFreq_cpd, ...
            'K',          K_default, ...
            'updateEveryNFrames', 1, ...
            'contrast',   contrast);
        fprintf('Static class found — will run cross-checks.\n');
    else
        fprintf('Static class NOT found — skipping static-vs-procedural tests.\n');
    end

    %% --------- Core bring-up: 3 frames, MAE vs CPU ----------
    hp.beforeTrial(); hp.stimValue = 1;
    for f = 1:3
        [gpuF, cpuF] = draw_and_grab_proc(hp, win, rect);
        mae = mean(abs(gpuF(:) - cpuF(:)));
        fprintf('GPU/CPU MAE: %.4f (expected ~<= 1 LSB)\n', mae);
    end

    %% --------- Multi-grab stability ----------
    n = 10; maes = zeros(1,n);
    for k = 1:n
        [gpu8, cpu8] = draw_and_grab_proc(hp, win, rect, 'uint8');
        maes(k) = mean(abs(double(gpu8(:)) - double(cpu8(:))));
    end
    fprintf('GPU/CPU MAE (mean±sd): %.3f ± %.3f LSB\n', mean(maes), std(maes));

    %% --------- Canonical center luminance checks (K=1, phase family) ----------
    hp.K = 1; hp.sampleComponents();
    bg = 127;
    phases = [ pi/4,  3*pi/4, -pi/4, -3*pi/4];     % cas family
    amps   = [ 1,       1,      -1,     -1    ] * (hp.contrast / sqrt(hp.K));
    w = RectWidth(hp.screenRect); h = RectHeight(hp.screenRect);
    cx = (w+1)/2; cy = (h+1)/2; %#ok<NASGU>  % included for parity; center is grid-aligned
    for t = 1:4
        phi = phases(t); a = amps(t);
        center = bg + 255*(a * sin(phi));
        fprintf('phi=% .2f rad : center = %.2f LSB (bg=%d)\n', phi, center, bg);
    end

    %% --------- Cancel test: equal & opposite should vanish ----------
    fprintf('--- Cancel test (procedural) ---\n');
    hp.K = 2; hp.sampleComponents();
    % Force same k twice:
    C = numel(hp.bank)/2;
    i = randi(C);
    fx = hp.bank(i).fx; fy = hp.bank(i).fy; kx = hp.bank(i).kx; ky = hp.bank(i).ky;
    hp.current.fx = [fx fx]; hp.current.fy = [fy fy];
    hp.current.kx = [kx kx]; hp.current.ky = [ky ky];
    hp.current.phase = [pi/4 pi/4];
    hp.current.amp = [ +hp.contrast/sqrt(2), -hp.contrast/sqrt(2) ];
    gpu8 = draw_and_grab_proc(hp, win, rect, 'uint8');
    dev = mean(abs(double(gpu8(:)) - bg));
    fprintf('Cancel test: mean |dev| = %.3f LSB (want ~0)\n', dev);

    %% --------- RMS vs K (tight-frame property) ----------
    fprintf('--- RMS vs K ---\n');
    Ks = [1 2 4 6 8 12];
    for K = Ks
        hp.K = K; hp.sampleComponents();
        gpu8 = draw_and_grab_proc(hp, win, rect, 'uint8');
        r  = rms_img(gpu8, bg);
        r_theory = (hp.contrast / sqrt(2)) * 255;
        fprintf('K=%2d: RMS = %.2f LSB  (theory ~ %.2f)\n', K, r, r_theory);
    end

    %% --------- Mean luminance stability ----------
    fprintf('--- Mean luminance stability (K=6, N=12) ---\n');
    hp.K = 6; n = 12; means = zeros(1,n);
    for k=1:n
        hp.sampleComponents();
        gpu8 = draw_and_grab_proc(hp, win, rect, 'uint8');
        means(k) = mean(gpu8(:));
    end
    fprintf('Mean luminance: %.2f ± %.2f LSB (bg=%d)\n', mean(means), std(means), bg);

    %% --------- Gram matrix (orthonormality) on the CPU basis ----------
    fprintf('\n--- Orthonormality check (Gram matrix) ---\n');
    [G, offdiag_mean, offdiag_max, diag_mean, diag_std] = gram_check(hp);
    fprintf('Mean |offdiag| = %.2e   (want ~<1e-12)\n', offdiag_mean);
    fprintf('Max  |offdiag| = %.2e\n', offdiag_max);
    fprintf('Diag range: %.6f ± %.6f\n', diag_mean, diag_std);

    %% --------- Tight-frame flatness (sum of squares) on CPU basis ----------
    fprintf('\n--- Tight-frame flatness (sum of squares) ---\n');
    flatness = tightframe_flatness(hp);
    fprintf('Flatness ratio std/mean = %.2e (want ~0)\n', flatness);

    %% --------- FFT / k-location checks (K=1, then multi-K) ----------
    fprintf('\n--- FFT peak tests ---\n');
    hp.K = 1; hp.sampleComponents();
    gpu8 = draw_and_grab_proc(hp, win, rect, 'uint8');
    dev = double(gpu8)/255 - hp.bgGrey;
    [fx_hat, fy_hat] = fft_peak_in_cpd(dev, hp.pixPerDeg);
    fx_log = hp.current.fx(1); fy_log = hp.current.fy(1);
    d = min([hypot(fx_hat-fx_log, fy_hat-fy_log), hypot(fx_hat+fx_log, fy_hat+fy_log), ...
             hypot(fx_hat-fx_log, fy_hat+fy_log), hypot(fx_hat+fx_log, fy_hat-fy_log)]);
    fprintf('FFT peak (%.3f, %.3f) c/deg vs bank ±(%.3f, %.3f) — Δ=%.3g\n', fx_hat, fy_hat, fx_log, fy_log, d);

    % Multi-K
    hp.K = min(6, numel(hp.bank)); hp.sampleComponents();
    gpu8 = draw_and_grab_proc(hp, win, rect, 'uint8');
    [matched, unmatched] = fft_match_multiK(gpu8, hp);
    fprintf('Multi-K FFT: matched %d/%d peaks within tol (unmatched=%d)\n', matched, 2*hp.K, unmatched);

    %% --------- Shift-vs-phase test (procedural) ----------
    fprintf('\n--- Shift-vs-phase (procedural phase advance) ---\n');
    dx_px = 7;  dy_px = -5;
    pd = hp.pixPerDeg;
    hp.K = 1; hp.sampleComponents();
    gpu0 = draw_and_grab_proc(hp, win, rect, 'uint8');
    dev0 = double(gpu0)/255 - hp.bgGrey;
    fx = hp.current.fx(1); fy = hp.current.fy(1);
    dphi = 2*pi*( -fx*(dx_px/pd) + fy*(dy_px/pd) );  % image row-down convention
    phi0 = hp.current.phase(1);
    hp.current.phase(1) = phi0 + dphi;
    gpuS = draw_and_grab_proc(hp, win, rect, 'uint8');
    devS = double(gpuS)/255 - hp.bgGrey;

    % CPU predictions
    [pred0, predS] = cpu_shift_predict(hp, dx_px, dy_px);
    mae0 = mean(abs(dev0(:) - pred0(:))) * 255;
    maeS = mean(abs(devS(:) - predS(:))) * 255;
    fprintf('Shift-vs-phase MAE: base=%.3f LSB, shifted=%.3f LSB\n', mae0, maeS);

    %% --------- Static vs Procedural (if available) ----------
    if haveStatic
        fprintf('\n=== Static vs Procedural cross-checks ===\n');
        hs.beforeTrial(); hp.beforeTrial();

        % A) Same K=1 atoms — compare displayed frames
        Ktest = 3;
        for t = 1:Ktest
            % Align parameters (pick one atom from procedural and copy to static)
            hp.K = 1; hp.sampleComponents();
            fx = hp.current.fx(1); fy = hp.current.fy(1);
            kx = hp.current.kx(1); ky = hp.current.ky(1);
            amp= hp.current.amp(1);
            hp.current.phase(1) = pi/4;          % cas convention
            % Static path: select same atom & amp if API permits; otherwise just draw
            if isfield(hs, 'setExplicitComponents')
                hs.setExplicitComponents(fx, fy, kx, ky, amp);  % hypothetical helper
            else
                % Fallback: let static choose its own, we just compare statistics
            end

            % Draw procedural
            gpuP = draw_and_grab_proc(hp, win, rect, 'uint8');

            % Draw static
            gpuS = draw_and_grab_static(hs, win, rect, 'uint8');

            % Compare
            maePS = mean(abs(double(gpuP(:)) - double(gpuS(:))));
            fprintf('Static vs Procedural (K=1) MAE: %.3f LSB\n', maePS);
        end

        % B) Random multi-K frames — match only global stats (RMS, mean)
        for t = 1:3
            hp.K = K_default; hp.sampleComponents();
            hs.K = K_default; if ismethod(hs,'sampleComponents'), hs.sampleComponents(); end
            gpuP = draw_and_grab_proc(hp, win, rect, 'uint8');
            gpuS = draw_and_grab_static(hs, win, rect, 'uint8');
            mP = mean(gpuP(:)); mS = mean(gpuS(:));
            rP = rms_img(gpuP, bg); rS = rms_img(gpuS, bg);
            fprintf('Static vs Procedural: mean %.2f/%.2f LSB, RMS %.2f/%.2f LSB\n', mP, mS, rP, rS);
        end
    end

    %% --------- Done ---------
    fprintf('\nAll tests complete.\n');
    ListenChar(0);
    Screen('CloseAll');

catch ME
    ListenChar(0);
    Screen('CloseAll');
    rethrow(ME);
end
end

%% ===================== Local helpers =====================

function [gpu, cpu] = draw_and_grab_proc(hp, winPtr, rect, mode)
    if nargin < 4, mode = 'float'; end
    % Defensive: resample if K changed elsewhere
    if ~isfield(hp,'current') || ~isfield(hp.current,'kx') || numel(hp.current.kx) < hp.K
        hp.sampleComponents();
    end
    hp.beforeFrame();
    vbl = Screen('Flip', winPtr); %#ok<NASGU>
    switch lower(mode)
        case 'float'
            gpu = mean(Screen('GetImage', winPtr, rect, [], 1), 3);  % [0..1]
            cpu = double(hp.getImage(rect, 1)) / 255;
        otherwise
            gpu = mean(Screen('GetImage', winPtr, rect, [], 0), 3);  % uint8
            cpu = hp.getImage(rect, 1);
    end
    hp.afterFrame();
end

function gpu = draw_and_grab_static(hs, winPtr, rect, mode)
    if nargin < 4, mode = 'uint8'; end
    if ismethod(hs,'beforeFrame'), hs.beforeFrame(); end
    vbl = Screen('Flip', winPtr); %#ok<NASGU>
    switch lower(mode)
        case 'float'
            gpu = mean(Screen('GetImage', winPtr, rect, [], 1), 3);
        otherwise
            gpu = mean(Screen('GetImage', winPtr, rect, [], 0), 3);
    end
    if ismethod(hs,'afterFrame'), hs.afterFrame(); end
end

function r = rms_img(I8, bg)
    D = double(I8) - bg;
    r = sqrt(mean(D(:).^2));
end

function [G, off_mean, off_max, d_mean, d_std] = gram_check(hp)
    w = RectWidth(hp.screenRect);
    h = RectHeight(hp.screenRect);
    [Xdeg, Ydeg] = meshgrid((1:w)-(w+1)/2, (1:h)-(h+1)/2);
    Xdeg =  Xdeg / hp.pixPerDeg;
    Ydeg = -Ydeg / hp.pixPerDeg;
    nC = numel(hp.bank);
    atoms = zeros(h, w, nC);
    for i = 1:nC
        fx = hp.bank(i).fx; fy = hp.bank(i).fy;
        phi = (fx>0 || (fx==0 && fy>0)) * (pi/4) + (fx<0 || (fx==0 && fy<0)) * (-pi/4);
        atoms(:,:,i) = sin(2*pi*(fx*Xdeg + fy*Ydeg) + phi);
    end
    A = reshape(atoms, [], nC);
    G = (A.' * A) / numel(Xdeg);
    offdiag = G - diag(diag(G));
    off_mean = mean(abs(offdiag(:)));
    off_max  = max(abs(offdiag(:)));
    d_mean   = mean(diag(G));
    d_std    = std(diag(G));
end

function flatness = tightframe_flatness(hp)
    w = RectWidth(hp.screenRect);
    h = RectHeight(hp.screenRect);
    [Xdeg, Ydeg] = meshgrid((1:w)-(w+1)/2, (1:h)-(h+1)/2);
    Xdeg =  Xdeg / hp.pixPerDeg;
    Ydeg = -Ydeg / hp.pixPerDeg;
    nC = numel(hp.bank);
    S = zeros(h, w);
    for i = 1:nC
        fx = hp.bank(i).fx; fy = hp.bank(i).fy;
        phi = (fx>0 || (fx==0 && fy>0)) * (pi/4) + (fx<0 || (fx==0 && fy<0)) * (-pi/4);
        a = sin(2*pi*(fx*Xdeg + fy*Ydeg) + phi);
        S = S + a.^2;
    end
    flatness = std(S(:)) / mean(S(:));
    figure(99); imagesc(S); axis equal tight; colormap(gray);
    title(sprintf('Sum of squares across %d atoms (std/mean=%.2e)', nC, flatness));
    colorbar;
end

function [fx_hat, fy_hat] = fft_peak_in_cpd(dev, ppd)
    [h,w] = size(dev);
    F = fftshift(fft2(dev - mean(dev(:))));
    mag = abs(F);
    mag(round(h/2+1), round(w/2+1)) = 0; % zap DC
    [~,mx] = max(mag(:));
    [py, px] = ind2sub([h w], mx);
    Wdeg = w / ppd; Hdeg = h / ppd;
    Fx = (-floor(w/2):ceil(w/2)-1)/Wdeg;
    Fy = (-floor(h/2):ceil(h/2)-1)/Hdeg;
    fx_hat = Fx(px); fy_hat = Fy(py);
end

function [matched, unmatched] = fft_match_multiK(gpu8, hp)
    dev = double(gpu8)/255 - hp.bgGrey;
    [h,w] = size(dev); ppd = hp.pixPerDeg;
    Wdeg = w / ppd; Hdeg = h / ppd;
    Fx = (-floor(w/2):ceil(w/2)-1)/Wdeg;
    Fy = (-floor(h/2):ceil(h/2)-1)/Hdeg;
    F = fftshift(fft2(dev - mean(dev(:))));
    mag = abs(F); mag(round(h/2+1), round(w/2+1)) = 0;
    K = hp.K;
    [~, idxs] = maxk(mag(:), min(2*K, numel(mag)-1));
    [py, px] = ind2sub(size(mag), idxs);
    peaks = [Fx(px(:))', Fy(py(:))'];
    fx_log = hp.current.fx(:);
    fy_log = hp.current.fy(:);
    expected = [ fx_log,  fy_log;     % model (+,+)
                -fx_log, -fy_log;     % model (-,-)
                 fx_log, -fy_log;     % image (+,-)
                -fx_log,  fy_log];    % image (-,+)
    tol = 0.05; used = false(size(expected,1),1); miss = 0;
    for i = 1:size(peaks,1)
        d2 = hypot(peaks(i,1) - expected(:,1), peaks(i,2) - expected(:,2));
        d2(used) = inf;
        [m, j] = min(d2);
        miss = miss + (m > tol);
        if m <= tol, used(j) = true; end
    end
    matched = 2*K - miss; unmatched = miss;
end

function [pred0, predS] = cpu_shift_predict(hp, dx_px, dy_px)
    w = RectWidth(hp.screenRect);  h = RectHeight(hp.screenRect);
    [xPix, yPix] = meshgrid((1:w)-(w+1)/2, (1:h)-(h+1)/2);
    Xdeg =  xPix / hp.pixPerDeg;  Ydeg = -yPix / hp.pixPerDeg;
    fx = hp.current.fx(1); fy = hp.current.fy(1);
    a  = hp.current.amp(1);
    phi0 = hp.current.phase(1) - (2*pi*( -fx*(dx_px/hp.pixPerDeg) + fy*(dy_px/hp.pixPerDeg) )); % undo the shift
    pred0 = a * sin(2*pi*(fx*Xdeg + fy*Ydeg) + phi0);
    dphi  = 2*pi*( -fx*(dx_px/hp.pixPerDeg) + fy*(dy_px/hp.pixPerDeg) );
    predS = a * sin(2*pi*(fx*Xdeg + fy*Ydeg) + phi0 + dphi);
end
