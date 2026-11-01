# Measurement contracts

Define a metric as event/count, unit, interval, exclusions and evidence source. Distinguish requested load from actual offered load, successful output from total output, and deliberate admission drops from corruption or incorrect results.

For sequential nonoverlapping comparable windows, aggregate throughput as total completed work divided by total duration, not an unweighted mean of rates. Keep unlike denominators separate. Do not average p95/p99 values into a pooled percentile; use raw samples or retain each run's tail separately. Overlapping runs need their own accounting.

Separate stage service time from queueing and end-to-end latency. Host transfer/collection time is not necessarily algorithm time. A reciprocal stage time does not establish pipeline throughput under contention. State whether concurrent work, batching, caching or repeated inputs changed the workload.

Use counter deltas across a known window, accounting for wrap and reset. Establish clock units and cross-host alignment before deriving latency. Retain missing records, truncated traces and incomplete END/drain as coverage limits; an exported file can be complete while its diagnostic samples are incomplete.

Bind input and candidate identity before interpreting a comparison. A correctness guardrail may require full output, negative cases, duplicate behavior or per-entity coverage, not merely the number of successes. Preserve failures and report observations without claiming statistical significance from a few runs.

A diagnosis profile that logs every job, halts a CPU or dumps images can perturb the pipeline. Separate instrumentation-heavy diagnosis from representative-rate validation. A soft budget checked between work items does not preempt a long work item.
