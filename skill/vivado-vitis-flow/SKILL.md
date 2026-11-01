---
name: vivado-vitis-flow
description: Create, rebuild or troubleshoot a Vivado-to-Vitis embedded workflow, including IP made from RTL, C/C++ HLS or MATLAB code generation, then hardware export, platform/BSP, application and ELF. Use for concrete IP/build steps; preserve accepted hardware for compatible application-only changes.
---

# Vivado to Vitis Embedded Workflow

Inspect the repository and current milestone before generating a new project. Locate maintained RTL or C/C++/MATLAB design functions, test benches, generation directives/configuration, Tcl/XDC, packaged IP, hardware exports, platform/application scripts, source imports, build logs and the accepted delivery. Record actual tool releases, host, target part/processor, execution mode and source revision including dirty state. Do not assume a board, release, operating system, model or execution harness.

Use the affected segment of this chain:

`RTL or C/C++/MATLAB -> validated generated RTL/IP -> Vivado design + constraints -> implemented hardware -> hardware export -> platform/domain/BSP -> application -> target ELF -> optional target execution or boot package`

Read [flow and checkpoints](references/flow-and-checkpoints.md) for the affected stage or a new project. Read [toolchain adapters](references/toolchain-adapters.md) only to select the installed interface or diagnose a matching environment failure.

When making IP from a high-level design, read [C/C++ and MATLAB to IP](references/high-level-ip-generation.md). Use native C/C++ HLS, supported MATLAB-to-HLS code generation, or MATLAB-to-HDL/IP as appropriate to the user's chosen source and installed tools. Establish a synthesizable design function and frozen reference tests; verify semantics, generated interfaces, synthesis results, applicable RTL equivalence, packaged-IP identity and integration. Ordinary generated C is not automatically synthesizable, and MATLAB input is not sent directly to a C/C++ HLS compiler.

For concrete generation/optimization methods, optionally read [C-to-IP construction patterns](references/c-to-ip-project-lessons.md). Preserve dependent evaluation order, reuse validated local data and reduce redundant load/launch transactions where the job contract permits. Select pipeline, storage and batching changes using actual equivalence, resource and timing evidence. Derive loop counts, numeric types and pipeline II from the selected design and measured constraints. This capability implements an already chosen function as IP; do not substitute a PS/PL partition analysis for the requested C-to-HDL work.

## Build the smallest valid chain

1. Establish the actual hardware contract: part, processor/domain, memory, peripheral ownership, clocks/resets, AXI connections, address ranges, interrupts and pin constraints. Keep these as project inputs. A PS-only design need not add unused PL ports or custom IP.
2. When hardware changes, create/update the maintained IP through the selected RTL or high-level generation route. Keep generated HDL, interface metadata and packaged copies bound to its source, directives, target and tests. Regenerate the required design/wrapper and constraints, then validate/simulate the changed boundary. HLS scheduling estimates do not replace Vivado synthesis/implementation; inspect run status, DRC, setup/hold timing and unconstrained paths before qualifying a programmable image.
3. Export hardware in the form required by this target and release. Record whether the export contains a programmable image; a metadata-only export can support platform generation but cannot program the logic. Bind export, image and implementation evidence instead of relying on filenames or timestamps.
4. Select a supported Vitis interface discovered in the installed release or existing working scripts. Create/update the platform using the matching export and real processor/domain, generate/build its required runtime/BSP, then build the application against that platform. Verify source import, generated address/driver definitions, library/ABI selection and linker layout.
5. Inspect the target ELF with available matching tools: architecture/class, entry point, loadable segments and memory ranges, required symbols and build identity as applicable. Existence and a recognizable header alone do not prove a runnable application. Compare the final linked code with the intended source and platform.

For a compatible application-only edit, retain qualified hardware and rebuild only the affected software. Hardware-map or processor/domain changes require the corresponding platform and consumer review. Linux userspace/driver/boot integration needs the actual Linux interfaces; do not substitute a standalone BSP application for it.

## Troubleshoot without losing the baseline

Preserve the first failing command, its full environment and raw error before interpreting a later missing export. Distinguish packaging/import errors, implementation failures, platform generation, compiler/archiver/linker failures and launch problems. Inspect the executable and PATH seen by the process doing the build, not just the interactive shell.

Use a sibling candidate workspace or supported incremental regeneration. Do not remove an active GUI lock, kill unrelated processes, delete the only workspace or apply a global toolchain patch to make a retry convenient. A fixed endpoint, reduced parallelism or extra tool paths is a bounded experiment justified by an observed failure, not a default requirement.

## Verify and deliver the requested result

When target access is requested and available, identify the actual target, use matching initialization and supported load order, establish required logic before dependent MMIO, and verify the expected UART/functional observation. Distinguish transient debugger loading from persistent boot media. Boot-image packaging or service changes remain separate scope decisions.

Return exact executed rebuild commands, source/configuration and artifact identities, affected checks and failures, current accepted versus candidate state, and run/stop/recovery instructions relevant to the request. Mark missing tools, Linux compatibility, physical operation and target behavior untested when they were not exercised. An offline review can still deliver useful scripts and interface findings without claiming a build.

This is the concrete toolchain workflow. The suite's broader build/handoff capability covers delivery and acceptance across toolchains; this package is self-contained and does not invoke other skills or require their helpers. See [scope and verification limits](references/provenance.md) when choosing checks or interpreting results.
