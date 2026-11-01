---
name: ps-pl-interface-contract
description: Define or review the hardware/software ABI for registers, descriptors, shared buffers, completion and generation identity. Use for producer/consumer interface changes in standalone or Linux paths; matching names or sizes alone do not establish compatibility.
---

# Hardware/Software Interface Contract

Locate authoritative RTL, packaged/exported hardware, driver/BSP/UAPI, linked layout and consumers. Establish the target ABI and what changed. Keep host layout, supplied descriptions and observed target layout separate.

Read [interface review](references/interface-review.md). Record byte/bit widths, order, offset, alignment, register effects/reset, memory extents and transaction semantics. Define who publishes inputs, what completion establishes, and when every consumer releases storage. Version fields must help detect incompatibility rather than merely change a number.

Compare actual sources and generated/runtime inputs. A changed register meaning, W1C/read-clear effect, structure field order, ioctl argument or identity tuple can break a caller despite equal total size and an unchanged version. Verify layout with target compiler assertions or an explicitly serialized format; do not invent padding from host sizeof.

Map changed definitions to all producers/consumers and build/export dependencies. Avoid editing generated headers to disguise an address mismatch. Preserve the old qualified pair and require evidence for the new pair's compatibility and recovery.

Two [distinct helper formats](references/helper-formats.md) are available. Select by the real observations and question; do not silently convert one schema into the other. A static match or equal normalized description proves only those checks, not binary compatibility, live hardware or dynamic ownership.

Return the explicit contract, change-impact findings, checked source/artifact identities, gaps and affected compile/behavior tests. When observations are missing, state them; do not fabricate interface facts to satisfy a checker.

Read [scope and verification limits](references/provenance.md) when choosing checks or interpreting results.
