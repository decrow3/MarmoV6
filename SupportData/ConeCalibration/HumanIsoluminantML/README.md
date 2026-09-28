# Human isoluminant M-L calibration

- Place the measured human `ConeMath2026_results.mat` export here.
- Required additions are `PhotopicLuminanceRGB`, its stated CIE 1931 convention,
  empirical gamma curves, bit depth, and gamma-application policy.
- `Acuity_Continuous_HumanML_Isoluminant` intentionally refuses to start when
  this calibration is absent, incomplete, proxy-derived, or marked dummy.
- The existing `Acuity_Continuous_HumanML` remains the historical S-silent but
  luminance-unconstrained pilot.
- For a laptop-only proxy test, run
  `build_proxy_human_isoluminant_calibration` once. The laptop rig explicitly
  opts into that generated proxy file and the protocol title is prefixed
  `PROXY`.
- Select `Acuity_Continuous_HumanML_Isoluminant_Proxy` in MarmoV6 to bypass
  rig-settings path ambiguity while retaining an explicit proxy-only warning.
