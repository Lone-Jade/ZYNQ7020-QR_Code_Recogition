# C-to-IP construction patterns

Use these patterns when implementing a scoring or search kernel as an IP block. They complement [generation checkpoints](high-level-ip-generation.md) and the [Vivado integration flow](flow-and-checkpoints.md); choose the arithmetic, loop counts and interfaces from the current design.

## Preserve arithmetic and dependent decisions

Freeze perspective mapping, feature-pixel reads, score accumulation, expression ordering, rounding and out-of-range behavior before reorganizing execution. Compare intermediate scores and each acceptance decision. Equal final QR payloads can conceal numeric changes through later error correction.

A dependent grid search must preserve its update sequence and strict acceptance rule, such as `score > best`, when that is the reference contract. Candidate evaluations cannot be treated as independent parallel trials when a previous result changes the next input. Precomputed coefficient bit patterns or a candidate-tree representation can preserve already rounded values; hardware-side updates are also valid when their arithmetic and state equivalence are established.

## Reuse data under an explicit transaction contract

Load reusable image data and feature tables into local storage when capacity and the job contract permit. Separate image loading from per-job feature/configuration preparation, then issue a bounded whole-job transaction to reduce repeated scalar register, launch and wait overhead.

Bind resident image, configuration and generation to each job. Invalidate the affected resident state after reset, failed loading or new input. Reject unsupported values explicitly. A software fallback must restore the defined initial state rather than accept a partially completed optimization.

## Select a qualified implementation

Read dependency, memory-port and operator scheduling reports before changing II or storage organization. A lower requested II can increase resource use or worsen routed timing. Compare actual synthesized and implemented results for the complete design, including setup/hold, DRC and resource limits.

Keep estimates and acceptance results separate. HLS resource estimates do not establish integrated resource fit, and a generated bitstream does not establish timing closure. Bind each report to its source, directives, target, clock and generated package.

## Separate equivalence coverage and performance scope

Distinguish native reference tests, HLS floating-point-model C simulation and C/RTL co-simulation. A reduced test that visits all dependent decisions with fewer feature cells has different coverage from a full-workload RTL test; report the actual reduction.

Measure input loading, preparation, driver transactions, compute and release over equivalent work. A scoring-stage speedup is not a whole-system FPS multiplier. Count actual comparison jobs: zero mismatches over zero jobs supplies no equivalence evidence. Preserve fallback, timeout and failure outcomes in both correctness and performance results.

These patterns support an already selected function-to-IP task. MATLAB routes still require the supported code generator, toolchain and their own numeric, RTL and integration checks.
