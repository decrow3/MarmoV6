%% Hartley lattice geometry comparison (portrait layout)
Wdeg = 51.34; 
Hdeg = 28.88; 
Sfmax = 8;  % cpd range for modern lattices

figure('Color','w','Position',[100 100 850 1600]);
th = linspace(0,2*pi,512);

%% === Row 1: Moosavi lattice (±14 integer samples) ===
kx = -14:14; 
ky = -14:14; 
[KXg,KYg] = meshgrid(kx,ky);

subplot(4,2,1);
scatter(KXg(:), KYg(:), 4, 'k','filled');
hold on; plot(14*cos(th),14*sin(th),'r--','LineWidth',0.5);
axis equal tight; box on;
xlabel('cycles / screen width'); ylabel('cycles / screen height');
title('Moosavi lattice (±14 integer samples)');

[KXg,KYg] = meshgrid(kx/Wdeg, ky/Hdeg);
subplot(4,2,2);
scatter(KXg(:), KYg(:), 4,'k','filled');
hold on; plot(Sfmax*cos(th), Sfmax*sin(th),'r--','LineWidth',0.5);
axis equal tight; box on;
xlabel('f_x (cpd)'); ylabel('f_y (cpd)');
title(sprintf('±14 → %.2f×%.2f cpd box',14/Wdeg,14/Hdeg));

%% === Row 2: Full integer lattice up to 8 cpd ===
Kx_max = floor(Wdeg*Sfmax);
Ky_max = floor(Hdeg*Sfmax);
kx = -Kx_max:Kx_max;
ky = -Ky_max:Ky_max;
[KXg,KYg] = meshgrid(kx,ky);

subplot(4,2,3);
scatter(KXg(:), KYg(:), 1,'k','filled');
hold on; plot(Wdeg*Sfmax*cos(th), Hdeg*Sfmax*sin(th),'r--','LineWidth',0.3);
axis equal tight; box on;
xlabel('cycles / screen width'); ylabel('cycles / screen height');
title(sprintf('Full integer lattice ±%.1f cpd → %dx%d (%d atoms)', ...
              Sfmax,numel(kx),numel(ky),numel(KXg(:))));

[KXg,KYg] = meshgrid(kx/Wdeg, ky/Hdeg);
subplot(4,2,4);
scatter(KXg(:), KYg(:), 1,'k','filled');
hold on; plot(Sfmax*cos(th), Sfmax*sin(th),'r--','LineWidth',0.3);
axis equal tight; box on;
xlabel('f_x (cpd)'); ylabel('f_y (cpd)');
title('Full integer lattice up to 8 cpd');

%% === Row 3: Isotropic strided lattice ===
ns_stride = 25;
[sx,sy,info] = pickHartleyStridesFromNs(Wdeg,Hdeg,Sfmax,Sfmax,ns_stride, ...
    'equalStride',true,'FmaxRadial',Sfmax);

[KXg,KYg] = meshgrid(info.KX_screen, info.KY_screen);
subplot(4,2,5);
scatter(KXg(:), KYg(:), 3,'k','filled');
hold on; plot(Wdeg*Sfmax*cos(th), Hdeg*Sfmax*sin(th),'r--','LineWidth',0.3);
axis equal tight; box on;
xlabel('cycles / screen width'); ylabel('cycles / screen height');
title(sprintf('ns=%d, %dx%d→ isotropic strides (sx=%d, sy=%d), n=%d', ...
    info.ns, info.nx, info.ny, info.sx, info.sy, numel(KXg(:))));

[KXg,KYg] = meshgrid(info.KX_cpd, info.KY_cpd);
subplot(4,2,6);
scatter(KXg(:), KYg(:), 3,'k','filled');
hold on; plot(Sfmax*cos(th), Sfmax*sin(th),'r--','LineWidth',0.3);
axis equal tight; box on;
xlabel('f_x (cpd)'); ylabel('f_y (cpd)');
title(sprintf('Δf_x=%.3f, Δf_y=%.3f cpd', info.fx_step, info.fy_step));

%% === Row 4: Biologically inspired log-radial lattice ===
optsLog = struct('Rmin',0.5,'Rmax',Sfmax,'nR',6,'nTheta',16);
[sx,sy,info] = pickHartleyStridesFromNs(Wdeg,Hdeg,Sfmax,Sfmax,ns_stride, ...
    'equalStride',true,'FmaxRadial',Sfmax,'logRadial',optsLog);

[KXg,KYg] = meshgrid(info.KX_screen, info.KY_screen);
subplot(4,2,7);
scatter(KXg(:), KYg(:), 3,'k','filled');
hold on; plot(Wdeg*Sfmax*cos(th), Hdeg*Sfmax*sin(th),'r--','LineWidth',0.3);
axis equal tight; box on;
xlabel('cycles / screen width'); ylabel('cycles / screen height');
title(sprintf('ns=%d, %dx%d log-radial (sx=%d, sy=%d)', ...
    info.ns, info.nx, info.ny, info.sx, info.sy));

[KXg,KYg] = meshgrid(info.KX_cpd, info.KY_cpd);
subplot(4,2,8);
scatter(KXg(:), KYg(:), 3,'k','filled');
hold on; plot(Sfmax*cos(th), Sfmax*sin(th),'r--','LineWidth',0.3);
if ~isempty(info.logCoords)
    plot(info.logCoords(:,1), info.logCoords(:,2), ...
         'bo','MarkerSize',4,'MarkerFaceColor','b');
end
axis equal tight; box on;
xlabel('f_x (cpd)'); ylabel('f_y (cpd)');
title(sprintf('Biological log-radial (Nlog=%d)', info.N_log));

sgtitle('Hartley Lattice Geometry: Moosavi → Full → Strided → Log-Radial', ...
    'FontWeight','bold');

%% ------------------------------------------------------------------------
function [sx, sy, info] = pickHartleyStridesFromNs(Wdeg,Hdeg,FmaxX,FmaxY,ns,varargin)
% pickHartleyStridesFromNs — scalar-only version (robust)
% -------------------------------------------------------
% Determine integer lattice strides (sx, sy) for the Hartley frequency basis.
% Simplified and hardened version for single ns input.

p = inputParser;
addParameter(p,'equalStride',false,@islogical);
addParameter(p,'FmaxRadial',[],@(x) isempty(x)||isscalar(x));
addParameter(p,'logRadial',[],@(x) isempty(x)||isstruct(x));
parse(p,varargin{:});
opt = p.Results;

% --- Round ns, enforce odd and sane bounds ---
if ~isfinite(ns) || ns<=0, ns = Inf; end
if isfinite(ns)
    if mod(ns,2)==0, ns = ns + 1; end
    ns = max(3, ns); % enforce minimal 3x3
end

% --- Integer frequency caps ---
Kx_max = floor(Wdeg * FmaxX);
Ky_max = floor(Hdeg * FmaxY);
fprintf('Hartley lattice: W=%.2f°, H=%.2f°, Fmax=%.2f cpd\n', Wdeg,Hdeg,FmaxX);

if isinf(ns) || ns >= (2*Kx_max+1) || ns >= (2*Ky_max+1)
    sx = 1; sy = 1; mode = 'full';
else
    m = (ns-1)/2;
    sx_lo = max(1, ceil(Kx_max/(m+1)));
    sx_hi = max(sx_lo, floor(Kx_max/m));
    sy_lo = max(1, ceil(Ky_max/(m+1)));
    sy_hi = max(sy_lo, floor(Ky_max/m));

    if sx_lo>sx_hi || sy_lo>sy_hi
        warning('ns=%d exceeded aspect ratio constraints; adjusting.',ns);
        m = max(1, m-1);
        sx_lo = max(1, ceil(Kx_max/(m+1)));
        sx_hi = max(sx_lo, floor(Kx_max/m));
        sy_lo = max(1, ceil(Ky_max/(m+1)));
        sy_hi = max(sy_lo, floor(Ky_max/m));
    end

    sxCand = sx_lo:sx_hi;
    syCand = sy_lo:sy_hi;
    bestErr = Inf;
    for sx_ = sxCand
        for sy_ = syCand
            err = abs(log((sx_/Wdeg)/(sy_/Hdeg)));
            if err < bestErr
                bestErr = err; sx = sx_; sy = sy_;
            end
        end
    end
    mode = 'sampled';
end

% --- Optional equal stride refinement ---
if opt.equalStride && strcmp(mode,'sampled')
    dfx_tgt = 2*FmaxX/(ns-1);
    dfy_tgt = 2*FmaxY/(ns-1);
    step_cpd = min(dfx_tgt, dfy_tgt);
    sx_try = round(step_cpd * Wdeg);
    sy_try = round(step_cpd * Hdeg);
    bestErr = Inf;
    for sx_ = max(1,sx_try-1):sx_try+1
        for sy_ = max(1,sy_try-1):sy_try+1
            err = abs(log((sx_/Wdeg)/(sy_/Hdeg)));
            if err < bestErr
                bestErr = err; sx = sx_; sy = sy_;
            end
        end
    end
    mode = [mode '_equal'];
end

% --- Derived quantities ---
fx_step = sx/Wdeg; fy_step = sy/Hdeg;
nx = 2*floor(Kx_max/sx) + 1;
ny = 2*floor(Ky_max/sy) + 1;
kx = (-floor(nx/2):floor(nx/2))*sx;
ky = (-floor(ny/2):floor(ny/2))*sy;

% --- Optional radial mask ---
if ~isempty(opt.FmaxRadial)
    [KX,KY] = meshgrid(kx/Wdeg, ky/Hdeg);
    mask = hypot(KX,KY) <= opt.FmaxRadial;
    N_disk = nnz(mask) - 1;
else
    N_disk = NaN;
end

% --- Optional log-radial coordinates ---
coords = [];
N_log = NaN;
if ~isempty(opt.logRadial)
    lr = opt.logRadial;
    if ~isfield(lr,'nR'), lr.nR=6; end
    if ~isfield(lr,'nTheta'), lr.nTheta=12; end
    rhoTarget = logspace(log10(lr.Rmin),log10(lr.Rmax),lr.nR);
    theta = linspace(0,pi,lr.nTheta);
    for r = rhoTarget
        for t = theta
            fx = r*cos(t); fy = r*sin(t);
            kx_snap = round(fx*Wdeg); ky_snap = round(fy*Hdeg);
            if (kx_snap==0 && ky_snap==0), continue; end
            fx_hat = kx_snap/Wdeg; fy_hat = ky_snap/Hdeg;
            rho_hat = hypot(fx_hat, fy_hat);
            if rho_hat>lr.Rmax || rho_hat<lr.Rmin, continue; end
            if (ky_snap<0)||(ky_snap==0&&kx_snap<=0), continue; end
            coords(end+1,:)=[fx_hat,fy_hat,rho_hat,atan2(fy_hat,fx_hat)];
        end
    end
    coords = unique(round(coords,6),'rows');
    N_log = size(coords,1);
end

% --- Pack info ---
info = struct('ns',ns,'mode',mode,'sx',sx,'sy',sy, ...
    'fx_step',fx_step,'fy_step',fy_step,'nx',nx,'ny',ny, ...
    'N_total',nx*ny-1,'N_disk',N_disk, ...
    'Kx_max',Kx_max,'Ky_max',Ky_max, ...
    'KX_screen',kx,'KY_screen',ky, ...
    'KX_cpd',kx/Wdeg,'KY_cpd',ky/Hdeg, ...
    'logCoords',coords,'N_log',N_log);
end
