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
