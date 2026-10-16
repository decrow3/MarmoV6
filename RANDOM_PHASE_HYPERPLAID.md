# Random-phase hyperplaid (noise type 15)

This branch adds a sparse sum of six arbitrary-phase Fourier sinusoids
sampled from the existing Hartley frequency lattice. Noise type 14 and its
renderer are unchanged.

## Settings

- `Forage_RandomPhaseHyperplaid`
- `Forage_RandomPhaseHyperplaid_Dense`
- `Forage_RandomPhaseHyperplaid_Isotropic`
- `Forage_RandomPhaseHyperplaid_Spiral`
- `Forage_RandomPhaseHyperplaid_Pminus1_4cpd_5648`
- `Forage_RandomPhaseHyperplaid_Pminus2_16cpd_2800`

Each setting inherits the corresponding Hartley preset and changes only
`P.noisetype` to 15 and the display title.

The spiral setting instead inherits the dense preset's task, contrast, and
timing parameters, then replaces its rectangular frequency bank. It lays out
golden-angle targets in physical `(fx,fy)` coordinates, independently snaps
each target to its nearest exact screen-periodic `(kx,ky)` coordinate, then
canonicalizes and deduplicates the physical axes. It never moves a target to
a more distant coordinate to enforce uniqueness. Six distinct physical axes
are sampled uniformly on every presentation; coordinate sign and continuous
phase are then randomized. It does not schedule or enrich closure relations.

`validate_fourier_spiral_bank` checks the canonicalization and antipodal
mapping without opening a Psychtoolbox window. On the July treadmill geometry
it checks canonical pairing, local snapping, deduplication, and exact requested
axis-count mode.

The spiral density is controlled by `P.hp_spiralDensityExponent`, interpreted
as the areal-density power `rho(r) proportional to r^p`. The default `p=-1`
reproduces the plotted bank. `p=0` gives uniform areal density, while `p=-2`
uses the logarithmic-radius special case (equal target count per octave).
For `p=-2`, `P.hp_spiralMinSF=0` automatically uses the smallest nonzero
screen-periodic frequency; a positive value supplies an explicit lower bound.

The two experiment presets use fixed continuous-proposal counts. Each proposal
is snapped independently and duplicate physical axes are simply discarded;
there is no nearest-unused reassignment, proposal expansion, or rank thinning.
On the July treadmill geometry this gives:

- Experiment 1: 6,000 proposals, `p=-1`, 0--4 c/deg, 5,648 physical axes, `K=6`.
- Experiment 2: 4,540 proposals, `p=-2`, lattice minimum--16 c/deg, 2,800 physical axes, `K=6`.

## Component convention and history

Every component is rendered as

`A*cos(2*pi*(kx*u + ky*v) + phaseRad)`

with positive `A = contrast/sqrt(K)` and `phaseRad` sampled uniformly from
`[0,2*pi)`. One ordinary RNG stream is used sequentially for frequency-axis
selection, coordinate-sign selection, and phase selection. There is no
attempt to synchronize streams with noise type 14.

The history schema is `fourierplaid_v1`:

`[time | K | fx(1:K) | fy(1:K) | phaseRad(1:K) | amplitude(1:K) | bankIndex(1:K)]`

The explicit history is the source of truth. The seed and pre-sampling RNG
state are also saved for diagnostic reproducibility.

## Amplitude check

`simulate_fourierplaid_contrast` performs an unclipped linear-framebuffer
simulation. A 500-frame check on 2026-10-11 gave these outside-`[0,1]`
fractions for random-phase Fourier versus the Hartley reference:

| Preset | Random phase | Hartley reference |
| --- | ---: | ---: |
| Standard, contrast 0.50 | 16.21% | 16.24% |
| Dense, contrast 0.30 | 1.48% | 1.48% |
| Isotropic, contrast 0.30 | 1.47% | 1.46% |

Thus `contrast/sqrt(K)` is not peak-bounded, but the issue is inherited and
not introduced by continuous phase. It is retained here for comparability.
There is no per-frame rescaling or explicit clipping in the stimulus code.
Any switch to a conservative global amplitude rule should be applied as a
separate, explicit scientific decision.

## Validation before recording

Run `validate_fourierplaid_gpu_cpu` on the treadmill display with a dedicated
`stimuli.fourierplaid_procedural` object. It tests an oblique component at
phases 0, pi/2, pi, and 3*pi/2 to expose shader/CPU phase-sign or y-axis
convention errors. This display-dependent test cannot be completed away from
the calibrated rig.

## Laptop validation (2026-10-16)

`test_fourierplaid_laptop` exercised the three spiral presets on the NVIDIA
RTX 3050 Ti laptop GPU using the configured 960-by-540 laptop window,
six components, and preset contrast 0.30. Four single-component phases and
one random six-component mixture per preset matched the quantized CPU
reconstruction within approximately 1/255 (RMSE about 0.00069).
The test uses an uncorrected floating-point framebuffer; it does not validate
monitor gamma or photometry. The real dummy tracker and window mouse readings
agreed with zero coordinate error in the final run. Calibration center was
[480 270], with dx=1 and dy=-1. This is a renderer/input smoke test, not a full
fixation/reward trial through the MarmoView GUI.

Psychtoolbox reported impossible beamposition timestamps and disabled its
high-precision timestamping. Sync tests were skipped for windowed development;
these results do not certify acquisition timing. Run the display-dependent
checks on the recording rig before acquiring data.

`test_eyeData_column_compatibility` verified identical output from the real
online eye importer for nine-column, ten-column, and mixed-width trials.
The extra column is ignored by that importer. Older calibration scripts that
concatenate complete eyeData matrices still require matching column counts
within the concatenated collection. The supplied August Hartley ferry package
contains stimulus code, not a recording-analysis loader, so it cannot establish
compatibility of an external Hartley analysis pipeline.

Set `HartleyStim = true` beside `RigName` in
`RigSettings/MarmoViewRigSettings.m` on Hartley or spiral stimulus days.
After selecting the rig, this initializes OpenGL and sets `S.bgColour = 0.5`.
The selected flag is also stored as `S.HartleyStim`. Its default is `false`,
which preserves the rig's ordinary background (127 for TDM, Laser, and laptop).
OpenGL also initializes in openScreen; the Hartley/Fourier constructor selects
normalized color range and bgGrey=0.5. Switch the flag off for other protocols.
