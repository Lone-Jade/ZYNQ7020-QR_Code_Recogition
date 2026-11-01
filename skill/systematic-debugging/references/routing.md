# Optional specialization

Discover available skills by capability using the current environment's inventory or an explicitly supplied package. A suite catalog can help, but is not required. Names below are recommended suite packages, not mandatory dependencies.

| Concrete boundary | Optional skill |
|---|---|
| Camera acquisition, physical display, HDMI modes or optical evidence | camera-hdmi-diagnosis |
| Linux startup, interpreter/backend, driver/service or deployed package | linux-runtime-and-release |
| Socket/link/framing, host capture or overloaded transport | network-streaming-diagnosis |
| RTL handshake, stream markers or FIFO behavior | streaming-data-path-verification |
| DMA ownership, leases, cache visibility or stop/drain | shared-buffer-lifecycle |
| Register, descriptor or producer/consumer ABI mismatch | ps-pl-interface-contract |
| Vivado implementation/export or Vitis platform/BSP/application build failure | vivado-vitis-flow |
| Decoded results missing, duplicated, stale or unacknowledged | result-association-and-publication |
| Frozen-input reproduction or algorithm-stage mismatch | algorithm-porting-and-replay |

Supply the specialist only the relevant symptom, baseline, raw inputs and constraints. Preserve the diagnostic evidence and review its output; do not treat a successful helper exit as proof of a broader claim. Specialists do not call the general skill back.

If a specialist is absent, continue with the core method and available source/docs. State the concrete gap that prevents a conclusion. Do not install skills, fabricate tool availability, or force an unrelated task through an embedded workflow.
