# Optional engineering capabilities

Discover capabilities through available metadata or explicitly provided skill files. The suite catalog is a convenience, not a runtime dependency. Keep the current user's scope and authorization when passing work to a specialist.

| Concrete need | Optional skill |
|---|---|
| Hardware/software build, matching artifacts and takeover | hardware-build-and-handoff |
| Concrete Vivado design/export -> Vitis platform/BSP -> application/ELF workflow | vivado-vitis-flow |
| Producer/consumer ABI or memory reservation change | ps-pl-interface-contract |
| Shared memory ownership, DMA or asynchronous cleanup | shared-buffer-lifecycle |
| Algorithm port, numeric comparison or frozen failure replay | algorithm-porting-and-replay |
| Linux environment/capabilities or staged deployment | linux-runtime-and-release |
| Camera/HDMI functional diagnosis | camera-hdmi-diagnosis |
| Streaming RTL verification | streaming-data-path-verification |
| Network frame transport | network-streaming-diagnosis |
| Result identity, queues and display publication | result-association-and-publication |

Load only what the current boundary requires. If none is installed, the general skill remains usable: inspect the source, make the smallest justified change, run available checks and report the missing specialized evidence. Do not fabricate invocation support or install packages automatically. Specialist procedures return their results directly and do not route back to the general layer.
