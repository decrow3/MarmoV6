# Experimental calibration placeholder

- Place the actual monitor-specific `ConeMath2026_runtime.mat` (schema 2.2 or later) here.
- Place the spectroradiometer verification as `marmoset_spectral_verification.mat` (variable `measurements`); see the protocol README.
- Do not place dummy, proxy, or synthetic fixtures here.
- The runtime monitor identifier must match `S.monitor` for the active rig.
- `Settings/MarmosetConePhenotypeFlow.m` intentionally aborts until both files exist and pass validation.
