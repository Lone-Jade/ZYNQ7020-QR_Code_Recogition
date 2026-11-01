# Existing-system integration

Inspect actual executable architecture/loader/libraries, kernel release/configuration, module compatibility, UAPI layout and hardware/DT mapping. A host-native build cannot replace target-specific execution. Use official documentation matching installed APIs when source/headers do not settle a version-sensitive detail.

For interpreter/notebook work, compare the actual interpreter, imported package path, native-library ABI and notebook kernel environment. Missing imports or host capture failures are not peripheral faults. Avoid exposing tokens/credentials in evidence. A fixed register backend can be a useful limited capability without supporting allocation or DMA.

For peripherals prefer existing Linux subsystems/APIs, or a justified UIO/custom driver contract. Do not port standalone MMIO/cache/BSP code into userspace unchanged. Identify the allocator, mapping/device address, dimensions, cache semantics and lifetime before a bounded known-pattern transfer. No suitable design or authority means that capability remains untested.

Inspect relevant link/address/route/listener/authentication for access problems and separate boot stage, root filesystem, display subsystem and physical output for black-screen problems. A listening port does not prove login; file hashes do not prove a filesystem warning repaired. Ordinary userspace edits do not imply a kernel or whole-image rebuild.

For programmable-logic reconfiguration, verify the platform's actual manager/bridge/region and driver ownership support. Static full-image operation can deliberately omit live reconfiguration; retain that boundary rather than claiming generic runtime support.
