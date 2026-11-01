---
name: linux-runtime-and-release
description: Integrate or diagnose an application/peripheral on an existing Linux system and prepare a compatible staged release with recovery evidence. Use for host/target ABI, runtime/backend capabilities, drivers/services or deployment state; not a mandatory full-image rebuild for ordinary edits.
---

# Linux Runtime and Release

Establish host versus target, current kernel/runtime/library identities, build/sysroot/ABI, service policy and the requested change. Inspect actual executable/module/device-tree/loaded package state. Previous conversations and files on a boot partition do not establish what is running now.

Read [runtime capability decisions](references/runtime-capabilities.md) for environment, backend or peripheral questions; read [staged release](references/staged-release.md) only when release work is requested. Preserve the existing system and choose the smallest affected boundary.

A package import, metadata parse, MMIO access, allocation and real DMA are independent capability levels. Use supported device addresses and cache/lifetime contracts, not object addresses or an assumed backend. Resolve APIs for the installed release; version-specific references are evidence to consult, not guaranteed support.

Build against a compatible target SDK/sysroot and headers. Keep userspace, driver/UAPI, DT/hardware and boot changes distinguishable. Retain working PS/system configuration when importing logic from a standalone design. An embedded ELF, metadata file, DT overlay and Linux driver are different artifacts.

For releases preserve a qualified baseline, stage and verify inputs before activation, and keep explicit recovery/state receipts. Respect service manual/autostart preferences. Do not unload/free/reset an active DMA path after a timeout without supported quiescence evidence.

The optional `scripts/verify_release_files.py --root DIR --manifest JSON` checks a strict format-1 regular-file hash list only. It rejects duplicate keys, traversal/drive paths and links below root; root itself is explicitly resolved. Exit 0/1/2 means listed-file match / file failure / malformed input. It never proves ABI, filesystem integrity, boot success or live configuration.

Return host-labeled reproduction, observed capabilities, package identities, changes, final known state, recovery and untested target/physical boundaries. Do not operate live services, boot media or a board solely to complete an offline review.

Read [scope and verification limits](references/provenance.md) when choosing checks or interpreting results.
