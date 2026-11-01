# Ownership, visibility and recovery

Describe who may write each image/descriptor/metadata item, how completion is observed, when a reader owns a stable view and what releases it. Include epoch/configuration/generation across boot/reset and ring reuse. Inspect failed submit, failed user-copy and cancellation paths as well as the happy path. Atomic counters do not by themselves prove lifetime correctness.

## Standalone

Use actual memory attributes and BSP APIs. CPU input must become visible before an external consumer; stale CPU cache must not mask externally written output or write it back later. Publish descriptor fields before the commit signal required by the protocol. For finite transfers, require the necessary producer validity, transfer completion and drain before reading outputs. Reserve full extents including padding and cache lines.

## Linux

Pair allocation/mapping/release with the correct device and lifetime, including outstanding VMAs, readers, work and callbacks. Check streaming mapping direction and CPU/device ownership synchronization; coherency and ordering remain distinct. Consult the matching kernel's [DMA mapping guide](https://docs.kernel.org/core-api/dma-api-howto.html) and [DMAengine client responsibilities](https://docs.kernel.org/driver-api/dmaengine/client.html), plus the actual provider/custom-master drain implementation.

Do not hold a lock needed by the worker you wait to stop. Confirm supported termination/drain and callback synchronization before resource release. A custom bus master can need more proof than a channel API. Preserve the platform's quarantine/reboot recovery when drain is unconfirmed. Avoid MMIO to a slave while reset makes it unavailable.

## Bounded evidence

Use known patterns and per-slot tokens at submit/commit/acquire/read/release. Distinguish missing notification, stale completion, actual bus stall and synthetic injection. Capture the first bad transition without per-pixel logging that changes the workload. Triple buffering, slot probes and content-change heuristics are not automatic ownership protocols.
