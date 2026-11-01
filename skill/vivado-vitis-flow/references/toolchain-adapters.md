# Select the real interface and diagnose matching failures

## Installed interface first

Inspect the existing working scripts, launchers, local help and installed API documentation. Tool releases and target flows differ. Reuse a compatible GUI/journal, Python client, or Tcl/XSCT path only when that installed release supports it. Do not select an interface solely from a remembered version number.

For a supported unified Python workflow, the useful sequence is client/workspace selection, platform creation from the real export and processor/domain, platform build, application creation/source import, then application build. Confirm exact argument names, supported domain selection and cleanup in installed help. Run with the vendor-provided launcher/environment where required; a general-purpose Python that cannot import the vendor module does not prove the project is broken.

AMD's [versioned scripting tutorial](https://github.com/Xilinx/Vitis-Tutorials/blob/2026.1/Embedded_Software/Feature_Tutorials/04-vitis_scripting_flows/README.md) illustrates the Python interface and workspace journal; use the matching release of that tutorial or installed journal for actual calls. The pinned example is not a minimum tool version or proof that another release supports the same API.

AMD's [platform creation reference](https://docs.amd.com/r/en-US/ug1701-vitis-accelerated-embedded/Creating-an-Embedded-Platform-XPFM) covers an embedded-platform context with domain/runtime inputs. Its acceleration/Linux-specific requirements must not be imposed on every standalone project.

For IP creation, discover the separate HLS or MATLAB generation interface as described in [high-level IP generation](high-level-ip-generation.md). Vitis application/platform APIs do not themselves synthesize C into hardware. Confirm installed generation products, supported language/features, licenses and compatible target/tool versions; missing MATLAB tools do not block an independent native C/C++ HLS route if that is the user's selected source.

## Conditional Windows lessons from the original skill

These adapters address Windows unified-client failure modes. Reproduce the actual symptom before using them and verify the installed release's supported interface.

| Observation | Bounded investigation and possible adaptation |
|---|---|
| Client fails decoding a server-port response | Inspect launcher/server output and installed API support. If endpoint discovery is the failing boundary and an explicit endpoint is supported, choose an available configurable local endpoint, retain the error and close the client using its actual lifecycle API. Do not require a fixed port on successful systems. |
| DTC/Lopper, compiler or archiver cannot be found | Inspect the exact failed executable and environment of the server/subprocess. Configure relevant installed paths or supported tool variables in the project launcher. A shell `where` result alone does not establish the server PATH. Never copy guessed installation paths. |
| BSP/CMake build intermittently fails under concurrency | Preserve the first failure; distinguish absent tools, file locks, path limits and genuine compile errors. A lower supported job count is a controlled diagnostic. Do not hard-code a job count or wrapper without checking the failing invocation. Prefer supported build options; use a project-local wrapper only when necessary and verify the actual invocation. |
| Platform export is absent | Read the first platform/BSP/compiler/archiver error before editing export paths. Verify any regenerated patch actually reaches the final linked/runtime inputs. |
| GUI workspace is occupied or generated state is inconsistent | Preserve the active workspace and create a sibling candidate, or use supported regeneration after tools release it. Remove generated output only when its resolved scope and disposability are established; do not remove locks or the only accepted baseline. |
| Shorter output path changes a Windows failure | Preserve failing path/log evidence and test a short candidate output path. This does not justify relocating maintained sources or all delivery files. |

On Linux, verify compatible SDK/sysroot, permissions and installed tooling separately. These lessons do not certify Linux-host builds, loaded drivers, device addresses, DMA lifetime or physical peripherals.
