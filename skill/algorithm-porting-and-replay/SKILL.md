---
name: algorithm-porting-and-replay
description: Port or compare processing code using frozen inputs, explicit numeric/semantic stages and reproducible failure replay. Use for host/shared-C/target differences or regressions; same-input replay does not establish optical capture, physical I/O or another architecture's performance.
---

# Algorithm Porting and Failure Replay

Establish required input/output behavior, reference provenance, frozen cases and target resource constraints. Locate existing shared code and stage contracts. Preserve the accepted algorithm and golden outputs rather than replacing a detector or regenerating references to hide a mismatch.

Read [staged equivalence](references/staged-equivalence.md). Specify representation, bounds, rounding/overflow, coordinate/ordering/identity and explicit failure statuses. Declare exact or justified tolerant comparisons before evaluating a candidate; candidate-set semantics may need an independent adapter.

Freeze the input bytes, configuration, source/result identity and required intermediates. Reproduce the earliest divergence. A correct final payload may conceal module/arithmetic changes through error correction, while justified numeric differences need not imply semantic failure. Missing comparison work cannot count as equivalence.

Compile shared pure logic on the host, then separately establish target compiler/ABI, memory/stack, libraries, hardware input integrity and cache/ownership before interpreting target results. Host timing and structure size are not target evidence.

Use [helper formats](references/helper-formats.md) only when their explicit typed-array or bounded Gray8 schema matches the question. Existing project replay interfaces are also acceptable. No particular runner, test harness, model or bundle format is required by the method. Helpers do not execute candidate code or refresh golden outputs.

Compare equivalent baseline/candidate inputs and preserve failure cases. Bind target-specific runs to the actual executable and observations. Return sources/inputs, adapters and coverage, first divergent stage, changes/tradeoffs and what still requires actual acquisition or target execution.

Read [scope and verification limits](references/provenance.md) when choosing checks or interpreting results.
