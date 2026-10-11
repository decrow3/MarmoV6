%% Hartley lattice geometry comparison (portrait layout)
Wdeg = 51.34; 
Hdeg = 28.88; 
Sfmax = 8;  % maximum spatial frequency (cpd)

figure('Color','w','Position',[100 100 850 1600]);
th = linspace(0,2*pi,512);

%% === Row 1: Moosavi lattice (±14 integer samples) ===
kx = -14:14; 
ky = -14:14; 
[KXg,KYg] = meshgrid(kx,ky);

subplot(4,2,1);
scatter(KXg(:), KYg(:), 4, 'k','filled');
%hold on; plot(14*cos(th),14*sin(th),'r--','LineWidth',0.5);
axis equal tight; box on;
xlabel('cycles / screen width'); ylabel('cycles / screen height');
title(sprintf('1. ±14 integer lattice'));

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
title(sprintf('2. Full integer lattice ±%.1f cpd → %dx%d (%d atoms)', ...
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
[~,~,info] = pickHartleyStridesFromNs(Wdeg,Hdeg,Sfmax,Sfmax,ns_stride, ...
    'equalStride',true,'FmaxRadial',Sfmax);

[KXg,KYg] = meshgrid(info.KX_screen, info.KY_screen);
subplot(4,2,5);
scatter(KXg(:), KYg(:), 3,'k','filled');
hold on; plot(Wdeg*Sfmax*cos(th), Hdeg*Sfmax*sin(th),'r--','LineWidth',0.3);
axis equal tight; box on;
xlabel('cycles / screen width'); ylabel('cycles / screen height');
title(sprintf('3. Isotropic strides (sx=%d, sy=%d), %dx%d, n=%d', ...
      info.sx, info.sy, info.nx, info.ny,  numel(KXg(:))));

[KXg,KYg] = meshgrid(info.KX_cpd, info.KY_cpd);
subplot(4,2,6);
scatter(KXg(:), KYg(:), 3,'k','filled');
hold on; plot(Sfmax*cos(th), Sfmax*sin(th),'r--','LineWidth',0.3);
axis equal tight; box on;
xlabel('f_x (cpd)'); ylabel('f_y (cpd)');
title(sprintf('Δf_x=%.3f, Δf_y=%.3f cpd',info.fx_step,info.fy_step));

%% === Row 4: Biologically inspired log-radial lattice ===
optsLog = struct('Rmin',0.5,'Rmax',Sfmax,'nR',5,'nTheta',12);
[~,~,info] = pickHartleyStridesFromNs(Wdeg,Hdeg,Sfmax,Sfmax, ...
    ns_stride,'equalStride',true,'FmaxRadial',Sfmax,'logRadial',optsLog);

% --- Cycles per screen (plot only log-radial samples) ---
subplot(4,2,7);
if ~isempty(info.logCoords)
    scatter(Wdeg*info.logCoords(:,1), Hdeg*info.logCoords(:,2), ...
        6,'k','filled','MarkerFaceAlpha',0.8);
end
hold on; 
plot(Wdeg*Sfmax*cos(th), Hdeg*Sfmax*sin(th),'r--','LineWidth',0.3);
axis equal tight; box on;
xlabel('cycles / screen width'); ylabel('cycles / screen height');
title(sprintf('4. Log-radial lattice (ns=%d, n_θ=%d, n_r=%d, N=%d)', ...
    info.ns, optsLog.nTheta, optsLog.nR, info.N_log));

% --- Cycles per degree (cpd view) ---
subplot(4,2,8);
if ~isempty(info.logCoords)
    scatter(info.logCoords(:,1), info.logCoords(:,2), ...
        6,'k','filled','MarkerFaceAlpha',0.8);
end
hold on; 
plot(Sfmax*cos(th), Sfmax*sin(th),'r--','LineWidth',0.3);
axis equal tight; box on;
xlabel('f_x (cpd)'); ylabel('f_y (cpd)');
title(sprintf('Log-radial lattice (n_θ=%d, n_r=%d, %.1f–%.1f cpd)', ...
    optsLog.nTheta, optsLog.nR, optsLog.Rmin, optsLog.Rmax));




function [sx, sy, info] = pickHartleyStridesFromNs(Wdeg,Hdeg,FmaxX,FmaxY,ns,varargin)
% pickHartleyStridesFromNs  —  Simplified robust stride picker (single ns)
% ----------------------------------------------------------------------
% INPUTS
%   Wdeg,Hdeg   : screen width / height (deg)
%   FmaxX,FmaxY : band limits in cpd
%   ns          : target lattice samples per axis (including DC)
%
% OPTIONS
%   'equalStride' (default=false)
%   'FmaxRadial'  (optional cutoff in cpd)
%   'logRadial'   (optional struct with Rmin,Rmax,nR,nTheta)
%
% OUTPUT
%   sx, sy : integer strides (in screen pixels)
%   info   : struct with lattice metadata
%
% NOTES
%   - ns rounded to odd, min=3
%   - returns full lattice if ns exceeds available bandwidth
%
% AUTHOR
%   2025 Declan & GPT-5 Lab Utilities, UCLA Huk Lab
% ----------------------------------------------------------------------

p = inputParser;
addParameter(p,'equalStride',false,@islogical);
addParameter(p,'FmaxRadial',[],@(x) isempty(x)||isscalar(x));
addParameter(p,'logRadial',[],@(x) isempty(x)||isstruct(x));
parse(p,varargin{:});
opt = p.Results;

% ----- Normalize ns -----
if isinf(ns)
    ns_eff = Inf;
elseif ns < 3
    ns_eff = 3;
elseif mod(ns,2)==0
    ns_eff = ns+1;
else
    ns_eff = ns;
end

% ----- Frequency caps -----
Kx_max = floor(Wdeg * FmaxX);
Ky_max = floor(Hdeg * FmaxY);

if isinf(ns_eff)
    sx = 1; sy = 1; mode = 'full';
elseif ns_eff >= min(2*Kx_max+1, 2*Ky_max+1)
    sx = 1; sy = 1; mode = 'full';
else
    m = (ns_eff - 1)/2;
    sx_lo = max(1, ceil(Kx_max/(m+1)));
    sx_hi = max(sx_lo, floor(Kx_max/m));
    sy_lo = max(1, ceil(Ky_max/(m+1)));
    sy_hi = max(sy_lo, floor(Ky_max/m));
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

% ----- Equal-stride refinement -----
if opt.equalStride && strcmp(mode,'sampled')
    dfx_tgt = 2*FmaxX/(ns_eff-1);
    dfy_tgt = 2*FmaxY/(ns_eff-1);
    step_cpd = min(dfx_tgt, dfy_tgt);
    sx_try = round(step_cpd*Wdeg);
    sy_try = round(step_cpd*Hdeg);
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

% ----- Derived grid -----
fx_step = sx/Wdeg;
fy_step = sy/Hdeg;
nx = 2*floor(Kx_max/sx)+1;
ny = 2*floor(Ky_max/sy)+1;
N_total = nx*ny - 1;

kx = (-floor(nx/2):floor(nx/2))*sx;
ky = (-floor(ny/2):floor(ny/2))*sy;

% ----- Radial cutoff -----
if ~isempty(opt.FmaxRadial)
    [KX,KY] = meshgrid(kx/Wdeg, ky/Hdeg);
    R = sqrt(KX.^2 + KY.^2);
    N_disk = nnz(R<=opt.FmaxRadial)-1;
else
    N_disk = NaN;
end

% ----- Optional log-radial -----
coords = [];
N_log = NaN;
if ~isempty(opt.logRadial)
    lr = opt.logRadial;
    if ~isfield(lr,'nR'), lr.nR=6; end
    if ~isfield(lr,'nTheta'), lr.nTheta=12; end
    rhoTarget = logspace(log10(lr.Rmin),log10(lr.Rmax),lr.nR);
    theta = linspace(0,2*pi-(2*pi/lr.nTheta),lr.nTheta);  % full-plane coverage
    uppergrace = 10^(log10(lr.Rmax)+median(diff(log10(rhoTarget)))/2);
    for r = rhoTarget
        for t = theta
            fx = r*cos(t); fy = r*sin(t);
            kx_snap = round(fx*Wdeg); ky_snap = round(fy*Hdeg);
            fx_hat = kx_snap/Wdeg; fy_hat = ky_snap/Hdeg;
            rho_hat = hypot(fx_hat,fy_hat);
            if (kx_snap==0 && ky_snap==0), continue; end
            if rho_hat<lr.Rmin || rho_hat>uppergrace, continue; end
            %if (ky_snap<0)||(ky_snap==0 && kx_snap<=0), continue; end
            coords(end+1,:) = [fx_hat fy_hat rho_hat atan2(fy_hat,fx_hat)];
        end
    end
    coords = unique(round(coords,6),'rows');
    N_log = size(coords,1);
end

info = struct('ns',ns_eff,'mode',mode,'sx',sx,'sy',sy, ...
    'fx_step',fx_step,'fy_step',fy_step, ...
    'nx',nx,'ny',ny,'N_total',N_total,'N_disk',N_disk, ...
    'Kx_max',Kx_max,'Ky_max',Ky_max, ...
    'KX_screen',kx,'KY_screen',ky, ...
    'KX_cpd',kx/Wdeg,'KY_cpd',ky/Hdeg, ...
    'logCoords',coords,'N_log',N_log);
end
