# Project layout and build checkpoints

Use an existing adequate layout. For a new project, a useful example is:

```text
project/
  config/target.*             part, board, clocks, addresses and runtime choices
  ip/<component>/            maintained HDL, packaging metadata and scripts
  high_level/<component>/    optional C/C++ or MATLAB design, tests and generation configuration
  sim/                       deterministic tests and expected data
  vivado/create_project.tcl
  vivado/build_hardware.tcl
  constraints/<target>.xdc
  software/app/              maintained C/C++ and linker inputs
  software/build_platform.*  interface chosen for the installed tools
  build/<candidate>/         isolated generated output
  docs/build-and-recovery.md
```

Paths derive from script/configuration location rather than the caller's current directory. Keep source, generated copies and outputs distinguishable. Respect the repository's existing artifact policy: generated caches/workspaces are usually excluded, while a qualified delivery may intentionally version matched images and reports. Never change ignore policy to discard an already accepted delivery.

## Hardware generation

- Accept handwritten RTL, HLS-generated RTL/IP, or supported MATLAB-generated HDL/IP. For a high-level route use [generation and equivalence checkpoints](high-level-ip-generation.md); record the design top, input types/bounds, test bench, directives, target part/clock and actual code-generation interface. A host application build is not IP generation.
- Package or refresh local IP only when the design needs it. Compare maintained and packaged sources, interfaces and register definitions. Check the actual IP-repository list loaded by the project.
- Create/update the block design and configure the real processor system. Establish AXI topology, clocks, reset polarity/synchronization, interrupt routing, address extents and external ports. Confirm PS pins versus PL pins before changing XDC.
- In a conventional block-design flow, inspect the installed Tcl help and existing scripts for operations such as `validate_bd_design`, target generation and wrapper creation. Use the supported sequence for that design; avoid duplicate wrappers or stale imported HDL.
- Use focused protocol/payload simulation before an expensive implementation where appropriate. Report source/top/configuration/seed identity, not just a screenshot of a passing run.
- Synthesis success, route completion, DRC, setup/hold constraints, unconstrained paths and programmable-image generation are separate observations. Do not downgrade an unexplained violation to qualify an image.

## Hardware export

The installed Vivado release and target determine the supported export form and flags. For a conventional flow that explicitly needs a bit-containing XSA, `write_hw_platform -include_bit` is a command to check against installed help; it is not a universal export template. AMD documents other export variants and interacting flags in [UG835 write_hw_platform](https://docs.amd.com/r/2022.2-English/ug835-vivado-tcl-commands/write_hw_platform). The linked release is a reference example, not the target version requirement.

Check the actual export contents and intended consumer. A metadata-only XSA is not automatically invalid for platform creation, but it cannot establish that a programmable image was delivered. Bind any separate image by identity to the export and implementation evidence. A ZIP member/hash inspection alone cannot prove timing, correct device selection, or semantic compatibility.

## Platform and BSP/runtime

Choose the installed Vitis interface before writing API calls. Resolve actual processor names from the export/platform, plus runtime OS/domain, architecture, address assumptions and required libraries. For a standalone application, generate/build the applicable BSP before linking the application; Linux and acceleration flows have different system/runtime inputs.

Record which export and configuration produced the platform. Inspect actual exported platform identity and generation logs. A final missing `.xpfm` after BSP failure is a consequence until the first error is understood. Do not create an empty placeholder, point at an unrelated old platform, or copy a generated header to hide the failure.

## Application and ELF

Confirm newly edited C/C++ files enter the real build, including source-copy/import behavior. Inspect generated peripheral lookup/address definitions rather than hard-coding a remembered macro; some drivers/releases select by address rather than an older device-ID convention.

Use the actual target compiler and ABI. Check linker memory regions, executable sections, stack/heap, shared data/descriptor reservations and externally accessed buffers. Inspect ELF loadable segments, entry, target machine/class, expected symbols and relevant source/build identity. A host executable or ARM ELF32 helper is not an adapter for every target.

## Execution and handoff

Use the target's supported initialization sequence and real processor selection. Depending on target and boot state, matching system initialization, reset, programmable logic and application loading require different ordering. Ensure logic is available before code accesses its MMIO; do not generalize one generated initialization script to every processor family.

Describe run evidence separately: host compilation, target linking, debugger download, UART progress, peripheral behavior and persistent boot. Deliver commands and artifacts for the requested boundary, accepted baseline/candidate status, source plus dirty state, measured checks, limitations and supported recovery. Avoid replacing a manual boot/service policy as a side effect of build work.
