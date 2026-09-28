# Marmoset cone-phenotype flow (two-field rivalry)

## Status

- Infrastructure is implemented in anticipation of a real monitor calibration.
- No synthetic or Dell proxy calibration is accepted by the experimental settings.
- The experiment is not validated for phenotype identification.

## Design

- Each trial shows two contraction (converging) optic-flow fields at once.
- Each field's flow centre follows its own low-pass random walk from a pre-generated pair bank.
  - Walks start on opposite sides of the fixation point, equidistant from the starting gaze.
  - They stay at least 4 deg apart and have near-zero velocity correlation.
- The two fields are matched in contrast, so an animal that sees both should divide its gaze between them.
- If one field is silent for the animal's cones, the other field should dominate.
- The stimulus always runs for its full duration.
  - Leaving both centres never ends the trial.
  - "Not seen" is recorded as a valid choice of neither field.
- Reward is non-differential: cumulative following of either centre earns reward.
  - The first `OnsetExclusionSeconds` (0.3 s) are neither rewarded nor scored.

## Conditions

- `null543`, `null556`, `null563`
  - Silence the named candidate pigment and the 423-nm S pigment.
  - Scaled so the largest non-silenced ML Weber contrast equals `MatchedContrast`.
- `achromatic_scale_s`: the background scaled by `1 +/- s*MatchedContrast`, the same Weber contrast in every cone.
- `catch`: both dot polarities equal the background, so the field is invisible.
- Null conditions are receptor-null in the pigment model, not isoluminant.

## Pair types

- `null-null` (diagnostic): each pair of nulls.
- `null-catch`, `achromatic-catch` (detection): the field against an invisible field.
- `catch-catch` (baseline): measures chance following.
- `null-achromatic` (optional): each null against the matched achromatic field.
- Every pair gets the identical set of (trajectory pair, walk assignment) combinations.
- No pair or pair type occurs more than twice in a row.
- Catch-catch trials are spread evenly through the session.
- The order is reproducible from `RandomSeed`.

## Background and contrast

- Pigment-null RGB directions do not depend on the background, but their Weber contrast does.
- `BackgroundMode = 'optimized'` searches for the background that maximizes the contrast all three nulls can share, subject to:
  - A luminance floor (`MinimumBackgroundLuminanceCdM2`).
  - Channel bounds of 0.1 to 0.9, keeping gamma in its well-measured range.
  - Quantized leakage within 80% of both tolerances.
  - Headroom for the achromatic field.
- On the 2018 LG 24UD58 calibration at 8 bits:

  | Background | Matched contrast | Luminance |
  |---|---|---|
  | Grey 0.5 | 6.8% | 109 cd/m2 |
  | Optimized | 12.9% | 60 cd/m2 |

- Rod trade-off:
  - A low-green background is rod-poor, so the nulls give large rod Weber contrasts. On the LG calibration: null556 -32%, null563 +24%, null543 -14%.
  - Rods are not silenced by any three-primary null.
  - Keep the luminance floor high enough for rod saturation at the animal's pupil size.
  - Every condition reports `RealizedRodContrast`.

## Calibration requirements

- Run `ConeMath2026()` (schema 2.2 or later) with the actual stimulus monitor calibration.
- The runtime must contain:
  - Candidate cone order `[563 556 543 423]` and the `4 x 3` `CandidateRGBToCones`.
  - The pigment model (`NomogramModel`) and rod row.
  - Absolute luminance, monitor spectra, and empirical gamma.
  - Monitor identifier, calibration date, checksum, bit depth, and gamma policy.
- Copy `ConeMath2026_runtime.mat` to `SupportData/ConeCalibration/MarmosetCandidateCones/`.
  - Or set `S.marmosetCandidateCalibrationFile` in the rig settings.
- The calibration monitor identifier must exactly match `S.monitor`.
- The calibration must be at most `MaximumCalibrationAgeDays` (365) old.

## Spectral verification

- `RequireSpectralVerification = true` by default.
- The calculated leakage only checks the RGB model; spectroradiometer measurements check the whole display chain:
  - gamma
  - quantization
  - channel additivity
  - spectral stability
- Procedure:
  1. Build the condition bank (run the settings with `RequireSpectralVerification = false`, or call `marmoview.marmosetPhenotypeConditionBank`).
  2. `patches = marmoview.marmosetVerificationPatches(S.marmosetConditionBank)`.
  3. Display each patch's device codes as a large field and measure its spectral radiance.
  4. Save a struct array `measurements` with fields `DeviceCodes`, `WavelengthsNm`, `Radiance` to `SupportData/ConeCalibration/MarmosetCandidateCones/marmoset_spectral_verification.mat`.
- Startup then recomputes pigment contrasts from the measured spectra.
- It aborts if any null's measured silent-pigment leakage exceeds 1% absolute or 20% of the measured signal.

## Startup

- Select `MarmosetConePhenotypeFlow` in MarmoV6.
- Startup aborts when:
  - The calibration is missing, dummy/proxy-labelled, malformed, too old, or monitor-mismatched.
  - The pigment model does not reproduce the exported matrix.
  - No background meets the luminance floor with acceptable quantized leakage.
  - Spectral verification is missing or fails.
  - The walk region plus following window exceeds the screen.
- Only empirical `software-encoded` gamma is accepted; `openScreen` then adds no Psychtoolbox gamma stage.
- Dots are square (`DotType 0`) and drawn with blending off, so every dot pixel is exactly a calibrated colour.
  - Anti-aliased edges blended in gamma-encoded space left the null axis (0.7-1.2% leakage).

## Abort conditions

- Missing required calibration metadata.
- Dummy, proxy, or not-for-experiments calibration label.
- Monitor mismatch, or a calibration older than the configured limit.
- Ambiguous or unsupported gamma policy.
- Out-of-gamut endpoint or achromatic field.
- Requested silent constraints fail.
- Realized silent-pigment leakage exceeds 0.005 absolute or 10% of the realized signal.
- Spectral verification missing or failed.

## Validity and scoring

- A sample is valid when the eye position is finite and, if the tracker reports pupil size, the pupil is finite and positive.
  - Trackers without pupil data (e.g., DDPI) fall back to position only.
- A trial is invalid for:
  - Too few valid samples, or a tracker gap longer than 0.3 s.
  - More than 5% long frames.
  - A calibration change.
  - No valid pre-stimulus fixation.
- Invalid trials are excluded; they are never scored as unseen.
- Choice: follow A, follow B, or neither. A field is chosen when gaze is within `FollowWindowRadiusDeg` of its centre, nearer it than the other centre, for at least 25% of the analysis interval and 10 percentage points more than the other field.
- Saved per trial (`D.PR.rivalryMetrics`):
  - Per-field distances, window fractions, and pursuit gain.
  - Joint velocity gains.
  - Velocity cross-correlation (positive lag: eye trails the centre).
  - Pre- versus post-stimulus distance, measured against the gaze position held at fixation.
  - Response latency, relative to a stationary eye.
  - Preference index and frame timing.

## Saved data

- Raw MarmoV6 files are written to `Output/`.
- Each trial stores:
  - Both field conditions in full (RGB endpoints, device codes, requested and realized cone and rod contrasts).
  - Pair and trajectory indices, both centre trajectories, per-frame eye, pupil, and flip times.
  - Seeds, the dot blend state actually used, polarity counts, and calibration identity.
- Historical reconstruction does not depend on the current settings file.

## Analysis

```matlab
result = analyzeMarmosetConePhenotypeFlow('Output/session_file.mat');
```

- Per-pair choice probabilities and per-condition convergence/detection probabilities, with bootstrap CIs.
- Rule-based reading from null-vs-catch detection relative to catch-catch chance.
- Observer model: a multinomial logit (follow A / follow B / neither) for all six phenotypes.
  - Dichromats: the field's contrast in their single ML cone.
  - Trichromats: `sqrt(lum^2 + kappa*opp^2)`, with luminance weight `w` and chromatic gain `kappa` as nuisance parameters.
  - All phenotypes: saturating transducer (`c50`), plus session-drift and eye-quality terms on "neither".
- Output: posterior per phenotype, bootstrap stability, compatible phenotypes, and `unclassified` when confidence, stability, or trial count is inadequate.
- Genotype is never an input.
- Compare with genotype only afterwards: `validateMarmosetPhenotypeCalls(callsTable,genotypeTable)`.

## Interpretation limits

- A 543/563 trichromat whose following is luminance-driven sees null556 as a mostly chromatic (near-isoluminant) stimulus.
  - It can look like a 556 dichromat.
  - The analysis reports `unclassified` when both fit.
  - Phenotype-specific opponent axes (not yet implemented) are needed to separate them.
- Silence depends on the assumed pigment peaks, optical density, and prereceptoral filtering.
  - A +/-2 nm peak error leaks 1.0-2.3% into the "silent" pigment, versus a 12.9% signal.
  - `ModelRobustness` reports this per condition.
  - `NullSweepOffsetsNm` (e.g., `[-2 0 2]`) adds nulls around each peak so the behavioural minimum can be located.
- Males are expected to be dichromats; use sex as a sanity check in the validation report, not in the fit.

## Tests

```matlab
addpath('SupportFunctions');
test_marmoset_cone_phenotype_suite;   % all no-display tests
```

- The suite includes a simulated session that drives the real protocol with stubbed `Screen`/`GetSecs`.
- From the ConeMath folder, also run `test_ConeMath2026`.
- Before animal use, on the rig:

```matlab
report = test_marmoset_phenotype_ptb;   % uses the experiment settings
```

- This opens the display through `openScreen`, runs each pair type through the protocol, and checks:
  - The hardware gamma table is identity.
  - Back- and front-buffer pixels are exactly the calibrated colours.
  - Both polarities of every visible field are displayed.
  - Flip timing.
