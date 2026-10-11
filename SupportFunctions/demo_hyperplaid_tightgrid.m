%function demo_hyperplaid_tightgrid()
% Tight-grid hyperplaid demo (no PTB). Rectangular Hartley sublattice, no disk.
% - Exact integer cycles across the field (tight within the reduced subspace)
% - 6 gratings per frame; random picks from a regular k-lattice
% - Hartley-style phase: cas equivalently via sin() with ±pi/4 (± adds the π flip)

% ----------------------- Rig / design params ----------------------------
Wdeg = 51.344;                  % field width (deg)  <-- set your screen
Hdeg = 28.881;                  % field height (deg) <-- set your screen
ppd  = 49.86;                   % pixels per deg     <-- set your screen

K       = 6;                    % components per frame
Fmax    = 8;                    % max |fx|,|fy| in cyc/deg (rectangular cap)
sx      = 30;                   % stride in kx (choose near W/H ratio)
sy      = 17;                   % stride in ky (sx/sy ≈ W/H ≈ 1.78 is good)
nFrames = 9;                    % how many example frames
contrast= 0.4;                  % per-frame RMS target (approx)
amp     = contrast / sqrt(K);   % per-component amplitude (energy normalize)

% ----------------------- Pixel grids in degrees -------------------------
nx = round(Wdeg*ppd); ny = round(Hdeg*ppd);
[xpix, ypix] = meshgrid( (1:nx) - (nx-1)/2, (1:ny) - (ny-1)/2 );
Xdeg =  xpix / ppd;
Ydeg = -ypix / ppd;             % y up

% ----------------------- Build tight sublattice --------------------------
% Integer indices: fx = kx/Wdeg, fy = ky/Hdeg
Kx_max = floor(Wdeg * Fmax);    % max integer cycles across width
Ky_max = floor(Hdeg * Fmax);    % max integer cycles across height

kx_vals = unique([ -Kx_max : sx : Kx_max ]);
ky_vals = unique([ -Ky_max : sy : Ky_max ]);

% Exclude (0,0) from the pool
[kx_grid, ky_grid] = ndgrid(kx_vals, ky_vals);
pool_k = [kx_grid(:), ky_grid(:)];
pool_k = pool_k(~(pool_k(:,1)==0 & pool_k(:,2)==0), :);

% Report pool size and effective spacings in cyc/deg
fx_step = 1/Wdeg; fy_step = 1/Hdeg;
fprintf('Pool size: %d k-vectors (tight subspace)\n', size(pool_k,1));
fprintf('fx step: %.5f c/deg  (kx stride %d => %.5f c/deg)\n', ...
        fx_step, sx, sx*fx_step);
fprintf('fy step: %.5f c/deg  (ky stride %d => %.5f c/deg)\n', ...
        fy_step, sy, sy*fy_step);

% ----------------------- Draw frames ------------------------------------
figure('Color','w','Name','Tight-Grid Hyperplaid'); colormap(gray);

rng(1); % reproducible demo
for f = 1:nFrames
    acc = zeros(ny,nx);

    % sample K distinct indices from the tight sublattice
    pick = randperm(size(pool_k,1), K);
    ksel = pool_k(pick, :);

    % Hartley-style phase: cas(θ)=cosθ+sinθ = sqrt(2)*sin(θ+π/4)
    % We'll use sin(· + φBase) with φBase in { -π/4, +3π/4 } (i.e., ± with π flip)
    sgn    = (rand(K,1)>0)*2 - 1;            % ±1
    phiBas = (-pi/4) + (sgn<0)*pi;            % -π/4 or -π/4+π

    % Accumulate components
    for j = 1:K
        kx = ksel(j,1);  ky = ksel(j,2);
        fx = kx / Wdeg;  fy = ky / Hdeg;      % cyc/deg, tight & rectangular
        acc = acc + sin( 2*pi*( fx.*Xdeg + fy.*Ydeg ) + phiBas(j) );
    end

    % Compose image (0..1) with approx RMS contrast
    I = 0.5 + amp * acc;
    I = uint8(255 * min(max(I,0),1));

    subplot(3,3,f); imagesc(I); axis image off;
    title(sprintf('Frame %d | K=%d', f, K));
end

% ----------------------- Notes ------------------------------------------
% • This is a rectangular cap (|fx|<=Fmax, |fy|<=Fmax) with even strides (sx,sy).
%   That keeps a *tight* (Parseval) structure in the reduced subspace:
%   exact reconstruction for any image synthesized from this pool.
% • Adjust (sx,sy) to set density; aim for sx/sy ≈ Wdeg/Hdeg for near-isotropic
%   sampling in cyc/deg. Larger strides → fewer k’s.
% • For experiments: log each component’s (kx,ky) and sign per frame. Gaze
%   correction is per-component via φ_gc = φ + 2π (kx/Wdeg, ky/Hdeg)·(Δx,Δy).
%end
