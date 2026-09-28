# Marmoset cone-phenotype flow

## Status

- Infrastructure is implemented in anticipation of a real monitor calibration.
- No synthetic or Dell proxy calibration is accepted by the experimental settings.
- The experiment is not validated for phenotype identification.

## Calibration requirements

- Run `ConeMath2026()` with the actual stimulus monitor calibration.
- The runtime must use schema `ConeMath2026-2.0` or later and contain:
  - Candidate cone order `[563 556 543 423]`.
  - A `4 x 3` `CandidateRGBToCones` matrix.
  - Background RGB and candidate-cone excitations.
  - Monitor spectra and wavelength sampling.
  - Empirical forward- and inverse-gamma samples.
  - Monitor identifier, calibration date, checksum, bit depth, and gamma policy.
- Copy `ConeMath2026_runtime.mat` to:
  - `SupportData/ConeCalibration/MarmosetCandidateCones/`
- Set the rig field `S.marmosetCandidateCalibrationFile` if a different location is used.
- The calibration monitor identifier must exactly match the active rig monitor identifier.

## Startup

- Select `MarmosetConePhenotypeFlow` in MarmoV6.
- Startup aborts when calibration is missing, dummy/proxy-labelled, malformed, or monitor-mismatched.
- The initial implementation accepts empirical `software-encoded` gamma only.
- MarmoV6 disables its legacy PTB power-law correction for this protocol, preventing double gamma correction.

## Conditions

- `null543`: silences the 543-nm candidate pigment and 423-nm S pigment.
- `null556`: silences the 556-nm candidate pigment and 423-nm S pigment.
- `null563`: silences the 563-nm candidate pigment and 423-nm S pigment.
- `achromatic`: equal candidate-cone modulation about the calibrated background.
- `catch`: both dot polarities equal the calibrated background.
- Null conditions are receptor-null, not necessarily isoluminant.

## Trial design

- Positive and negative dot counts are equal for even dot counts.
- An odd dot count adds one background-coloured dot.
- Dot polarity is assigned before placement and preserved during cached replacement.
- Conditions reuse a deterministic bank of bounded, low-pass random-walk flow-centre trajectories.
- Trajectories start on the fixation point. The first `OnsetExclusionSeconds` (default 0.3 s) of each stimulus are not rewarded, cannot trigger a lost-target abort, and are excluded from the saved following metrics.
- Trial order is reproducible and prohibits three consecutive repetitions of one condition.
- Catch trials are inserted throughout the session.

## Abort conditions

- Missing required calibration metadata.
- Dummy, proxy, or not-for-experiments calibration label.
- Monitor mismatch.
- Ambiguous or unsupported gamma policy.
- Out-of-gamut endpoint.
- Requested silent constraints fail.
- Realized silent-cone leakage exceeds the configured tolerance.

## Saved data

- Raw MarmoV6 files are written to `Output/`.
- Each trial stores the complete condition, requested and realized RGB values, device codes, candidate-cone contrasts, trajectory, eye trace, flip timing, random seed, calibration identity, and validity result.
- Historical reconstruction does not depend on the current settings file.

## Analysis

- Run:

```matlab
result = analyzeMarmosetConePhenotypeFlow('Output/session_filez.mat');
```

- The analysis reports per-condition behavior, bootstrap intervals, six phenotype-hypothesis scores, classification stability, and `unclassified` when confidence is inadequate.
- Genotype must remain hidden from this analysis and be compared only in a separate validation report.

## Tests

```matlab
addpath('SupportFunctions');
test_marmoset_cone_phenotype_suite;
```

- From the ConeMath folder, also run `test_ConeMath2026`.
- Before animal use, run the Psychtoolbox framebuffer test on the actual rig:

```matlab
report = test_marmoset_phenotype_ptb(calibrationFile,screenNumber,monitorIdentifier);
```

- Verify framebuffer values, gamma application, clipping, polarity balance, and flip timing before animal use.
