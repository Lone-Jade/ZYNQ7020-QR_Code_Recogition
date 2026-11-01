---
name: network-streaming-diagnosis
description: Diagnose link, host capture, framed transport and overloaded network processing while preserving complete input/result identity. Use for missing packets, incomplete frames or queue-induced loss in Linux or standalone paths; do not switch protocols before localizing the failing boundary.
---

# Network Streaming Diagnosis

Identify intended endpoints, active program/configuration, actual connected interfaces, transport direction and the existing protocol. Start capture before stimulus and verify the host tool/environment and bind address/port.

Read [network boundaries](references/network-boundaries.md). Separate program startup, physical link/negotiation, addressing/routes, packet capture, socket delivery, framing and processing. A printed IP, identified PHY, listening service or absent ARP entry alone does not establish the whole path.

For hardware-backed networking inspect the actual MAC/PHY/BSP/driver and generated configuration. Make required patches reproducible and verify the final linked/loaded implementation after regeneration. Discover target-specific registers and installed APIs rather than using a memorized board recipe.

Validate frame schema/length/index, duplicate handling, complete packet set and integrity before admitting work. Protect processing buffers until release. Carry source/run identity to returned results and count stale/incomplete/overload outcomes separately.

Use observed queue service, burst arrival and processing intervals to choose bounded drain, pacing or admission changes. Preserve scheduling fairness and actual send-rate measurements. Check MTU, buffer lifetime, allocator/descriptor availability and receive/cleanup progress before claiming zero-copy is safe or abandoning a working transport.

Verify a small transaction, fault boundaries and the requested representative load. Report actual offered/admitted/completed/correct work, integrity and latency, with clock/window definitions. Scope host network changes and restore temporary experiment state as required; do not alter unrelated interfaces or disable protections globally.

Read [scope and verification limits](references/provenance.md) when choosing checks or interpreting results.
