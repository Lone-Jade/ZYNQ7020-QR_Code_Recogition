---
name: streaming-data-path-verification
description: Design or verify streaming hardware when accepted transfers, packing, frame/packet boundaries, buffering or clock/reset crossings must preserve data. Use for RTL/FIFO/data-path changes, not as proof of physical timing or a universal stream protocol checker.
---

# Streaming Data Path Verification

Discover the actual producer/consumer contract: clocks/reset, widths, byte/pixel packing, sideband semantics, accepted-transfer condition, capacity and overflow/drop behavior. The source may be unstoppable while a downstream interface supports backpressure.

Read [stream verification](references/stream-verification.md). Advance state and reference sequences on accepted transfers. Hold a stalled valid item and its sidebands through final acceptance. Drive and sample away from simulation races. Check independent input/output sequences, not just equal totals.

Cover relevant first/last-item stalls, bubbles, consecutive frames, capacity boundaries, malformed input, abort/reset and restart. Use deterministic seeds and bounded timeouts. A change that suppresses overflow evidence or couples independent branches needs explicit justification and regression coverage.

Use separate protocol, payload and metadata/identity checks. A legal handshake can carry the wrong pixel, and a correct final output can hide an intermediate fault. Test expected recovery instead of silently resynchronizing bad markers.

For CDC, examine the real synchronization/FIFO structure, multibit coherence, reset release and implemented constraints. Simulation with several clock ratios is useful but does not establish metastability safety, implemented timing or physical losslessness.

The [helper profile](references/helper-profile.md) supplies a monitor, deterministic self-test and CSV checker for one-pixel/full-keep progressive video only. Adapt or replace it for other profiles, including generic packet TLAST and packed pixels. Return source/config/seed identities, actual coverage, first divergence and remaining implementation/target checks.

Read [scope and verification limits](references/provenance.md) when choosing checks or interpreting results.
