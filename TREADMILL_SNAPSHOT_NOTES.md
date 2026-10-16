# Treadmill snapshot implementation note

The `origin/Treadmill_July2026` snapshot (`ab7aa96`) is the authoritative
starting point for treadmill-rig stimulus work in this branch.

The later `codex/hyperplaid-wip` commit (`14f4f64`) is useful historical and
exploratory work, but it is not a wholesale upgrade path for the treadmill
rig. Differences must be reviewed and transferred deliberately.

Scientific equivalence with the July treadmill implementation takes
precedence over newer commit timestamps. In particular, noise type 14 and
`stimuli.hartleyplaid_procedural` remain the reference Hartley implementation;
the random-phase Fourier stimulus is added separately as noise type 15.

## Integration into consolidated (2026-10-16)

The Fourier and spiral changes from `e7e4f55` and `e4c83b0` were
cherry-picked into `consolidate-rig-branches-2026`. The July snapshot above
describes their source lineage, not the base of the consolidated branch.
The older treadmill snapshot was not merged wholesale: consolidation already
contains deliberately reconciled rig code.

The integration retains consolidated rig selection, cone-color gamma handling,
and dummy calibration, and adds the required OpenGL initialization. The Hartley
stimulus class and three inherited Hartley presets match the treadmill source.

The separate `codex/hyperplaid-wip` checkpoint remains unintegrated. It includes
experimental Hyperplaid implementations, alternate shaders, demos, and changes
to the older Hyperplaid preset; it is not a dependency of the spiral stimulus.
Standalone ConeColorMath and exported update folders are not versioned by this
repository.
