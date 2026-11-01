---
name: shared-buffer-lifecycle
description: Review or repair asynchronous shared-buffer ownership, DMA visibility, leases, completion and stop/recovery in standalone or Linux systems. Use for torn snapshots, stale generations or unsafe reuse; a software trace is not real DMA qualification.
---

# Shared Buffer Lifecycle

Inspect the actual producer, consumers, driver/runtime, allocation/mapping API, memory attributes, descriptor layout and active code. Record an owner/state table with the token, synchronization, visibility and failure unwind for each transition.

Read [ownership and recovery](references/ownership-and-recovery.md), then the applicable platform section. Keep command acceptance, hardware completion, memory visibility, consumer release and safe reuse distinct. Index/slot equality is not generation identity or an indefinitely valid lease.

Pair image, metadata, candidate bank, ROI and result using a stable transaction identity. Prove the whole read/copy interval is protected. A private snapshot protects later consumers only if the source was coherent during copying. CRC over mixed bytes or one slot recheck after a full wrap does not establish source-frame integrity.

Reserve buffers against executable/stack/heap/descriptor extents and ensure dimensions/stride/cache alignment. Derive synchronization from actual writer/reader ownership; do not globally disable caches or substitute a virtual/Python address for a device address.

Stop new admissions before drain. Ensure lock order lets workers/callbacks finish. A timeout is not proof the device stopped; retain isolation/quarantine when quiescence is unproven. Do not free leased memory or unload/reset hardware through an unsupported sequence.

Use [optional exclusive trace checking](references/trace-format.md) to audit a supplied normalized single-consumer model. Check actual concurrency and APIs independently. Return supported invariants, changed transitions, affected failure/restart checks and unverified target behavior.

Read [scope and verification limits](references/provenance.md) when choosing checks or interpreting results.
