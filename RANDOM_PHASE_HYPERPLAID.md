# Random-phase hyperplaid (noise type 15)

This branch adds a sparse sum of six arbitrary-phase Fourier sinusoids
sampled from the existing Hartley frequency lattice. Noise type 14 and its
renderer are unchanged.

## Settings

- `Forage_RandomPhaseHyperplaid`
- `Forage_RandomPhaseHyperplaid_Dense`
- `Forage_RandomPhaseHyperplaid_Isotropic`

Each setting inherits the corresponding Hartley preset and changes only
`P.noisetype` to 15 and the display title.

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
