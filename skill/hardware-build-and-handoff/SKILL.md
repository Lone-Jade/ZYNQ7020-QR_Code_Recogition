---
name: hardware-build-and-handoff
description: Build or take over a hardware/software project whose generated design, interface, runtime artifacts and acceptance evidence must match. Use for hardware-dependent builds and delivery; ordinary software edits do not require a hardware rebuild or release ceremony.
---

# Hardware Build and Handoff

Identify the requested baseline, authoritative source, actual target/toolchain, generated inputs and intended execution mode. Resolve installed tool versions and supported APIs instead of assuming a particular vendor release, host shell or board.

Read [build and handoff decisions](references/build-and-handoff.md) for the affected boundary. Separate source generation, synthesis/implementation, timing/DRC, hardware export, platform/runtime libraries, application build and deployment. A file's existence or timestamp does not qualify the complete chain.

For hardware/interface changes inspect the real design/top, packaged IP copy, clocks/resets, addresses and constraints. Check that exported metadata and generated software inputs describe that design. For compatible application-only changes retain qualified hardware and rebuild only the affected dependencies.

Diagnose the first failing command in its actual process environment. On a Windows tool server, launcher PATH, encoding, occupied workspace, imported source copies or tool process state can differ from the shell. Workarounds such as an explicit endpoint or bounded concurrency are conditional experiments, not defaults for every release.

Bind source revision plus dirty state, configuration, artifact hashes and matching reports. Keep the accepted baseline and use an isolated candidate output. Distinguish a target description without a programmable image, a generated image with failed timing, a host executable and actual target execution.

For takeover provide build/run/stop/recovery entries inspected in this project, current versus historical/live state and untested boundaries. Persistent boot media and a transient debugger download are different deliverables; perform only authorized operations on an identified target.

Optional [helper formats](references/helpers.md) cover file-manifest verification and one legacy programmable-system handoff adapter. They cannot prove timing, ABI compatibility, runtime behavior or deployment success. They are not dependencies of the general build method.

Read [scope and verification limits](references/provenance.md) when choosing checks or interpreting results.
