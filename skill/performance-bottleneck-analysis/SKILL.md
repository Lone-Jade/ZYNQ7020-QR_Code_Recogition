---
name: performance-bottleneck-analysis
description: Analyze a measured throughput, latency or resource shortfall and validate a bounded optimization while preserving required correctness. Use for applications, services and processing pipelines; not for inferring a speedup from build success or unrelated arithmetic.
---

# Performance Bottleneck Analysis

Establish the user's actual goal and correctness constraints, the measured workload, baseline/candidate identities and the acceptable decision boundary. Do not turn a historical best result into a new requirement. Use adequate existing evidence before proposing further measurement.

## Define comparable metrics

Map input generation, queues/transfers, processing and output to observable counters and clocks. Distinguish offered, admitted, completed, dropped and correct outcomes. Throughput, service time, end-to-end latency, tail latency and coverage are different metrics.

Read [measurement contracts](references/measurement-contracts.md) before aggregating rates or comparing runs. Check units, counter semantics and deltas, warm-up, windows, resets, missing events, sampling and instrumentation overhead. Zero errors with zero comparison work is not evidence of equivalence.

## Rank bottlenecks with evidence

Use measured stage times, queue/backpressure evidence and controlled bypass/replay to distinguish input, compute, memory, I/O, scheduling and output limits. A locally expensive stage is not automatically the end-to-end bottleneck. Summing overlapping stages or taking a reciprocal can create an invalid capacity estimate.

For the leading explanation propose a bounded experiment: the changed factor, matched workload and environment, observable measurements, acceptance rule, correctness guardrails and rollback. Preserve incomplete/invalid runs and state why they cannot support the intended claim. Do not discard valid difficult inputs because the candidate misses them.

## Compare and decide

Compare matching input/scene, package/configuration, instrumentation and valid windows. Report relevant subgroups as well as totals, workload/drop changes, sample counts and latency tails. Label unpaired observations and estimates. Retain the baseline when the candidate fails the applicable adoption criteria; missing criteria remain explicit rather than becoming an invented pass.

Return metric definitions and evidence, supported bottleneck hypotheses, the experiment or measured comparison, the adoption decision and remaining uncertainty. If testing is canceled, record the pending evidence without continuing automatically.

Read [camera/display/Linux measurements](references/camera-display-linux.md) only for those systems and [optional routing](references/routing.md) when a concrete mechanism needs deeper investigation. No model, device, software release, execution harness or specialist is a prerequisite for the core method.

Read [scope and verification limits](references/provenance.md) when choosing checks or interpreting results.
