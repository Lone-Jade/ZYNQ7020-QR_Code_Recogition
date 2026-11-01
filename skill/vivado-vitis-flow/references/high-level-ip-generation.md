# C/C++ and MATLAB to reusable IP

Use this workflow when the requested implementation is a high-level function turned into hardware. Preserve the selected algorithm and its required semantics; do not replace the work with advice about dividing PS and PL responsibilities.

## Choose a supported generation route

| Maintained design | Concrete route | Establish before generation |
|---|---|---|
| C/C++ function | Refactor to the installed HLS tool's synthesizable subset -> C simulation -> HLS synthesis -> applicable C/RTL co-simulation -> export Vivado-compatible RTL/IP | Top function, source/test files, compile options, directives/configuration, target part and clock, interfaces and bounded storage |
| MATLAB function with a supported HLS workflow | MATLAB reference/tests -> HDL Coder MATLAB-to-HLS generation of synthesizable C++ -> configured HLS simulation/synthesis/verification -> IP export | Installed products/licenses, supported function/type subset, generation target, data sizes/types and downstream tool compatibility |
| MATLAB function/model with a supported HDL workflow | HDL-compatible design -> HDL Coder HDL generation and verification -> supported IP-core packaging, or explicit Vivado packaging of generated RTL | Numeric conversion decisions, sample/latency/enable/reset behavior, supported interfaces, generated HDL and test bench |

The MathWorks [MATLAB-to-HLS example](https://www.mathworks.com/help/hdlcoder/ug/get-started-with-hls-ip-core-generation-workflow.html) illustrates generated synthesizable C++ followed by Vitis HLS and Vivado integration. The [workflow overview](https://www.mathworks.com/help/hdlcoder/ug/overview-of-workflows-in-hdl-workflow-advisor.html) distinguishes MATLAB-to-HDL and MATLAB-to-HLS choices. Use the installed release's supported products, devices and generation steps; do not copy the example board as a requirement. Ordinary MATLAB C code generation, a MEX result or a successful host executable alone establishes none of these hardware stages.

HLS is optional when RTL already meets the request. MATLAB is optional for native C/C++ HLS. If the selected generator is absent, complete available reference/interface/source work and report generation as unexecuted; do not install tools or claim synthesis to satisfy a checklist.

## Freeze the executable meaning

Keep an independent software/MATLAB reference and fixed input bytes, configuration and expected results. Specify dimensions, bounds, stride, packing/endianness, signedness, coordinate origin, numeric ranges and invalid-input behavior. Isolate a design top from host I/O, OS calls and runtime allocation; use bounded storage/control structures supported by the selected generator. Keep stimulus, file operations and result checks in the test bench unless intentionally implemented as hardware interfaces.

Preserve floating-point expression order, rounding, clipping, exceptional/domain handling, integer overflow and comparison/tie behavior that affect outputs or control. A MATLAB array layout or one-based index is not automatically the C layout or zero-based pixel coordinate. Fused operations, reassociation, narrowing, float-to-fixed conversion and fixed-point overflow modes can change decisions; make such changes explicit, justified and separately tested, rather than calling them mandatory HLS preparation. High-level simulation precision may differ from the synthesized operator model.

For dependent iterative logic, compare each score/state transition, acceptance decision and final state, not only an error-corrected final payload. Include ties, numeric limits, negative/boundary coordinates, invalid sizes and restart/multi-call behavior relevant to the actual design. Use meaningful comparison counts and frozen references; do not regenerate golden data from the candidate.

## Make the hardware contract explicit

Choose control, scalar/register, stream and memory interfaces to match the integration contract. For applicable AXI flows, confirm actual generated AXI-Lite offsets, pointer widths and alignment, AXI master depth/burst settings, or stream handshake/sideband behavior. Do not invent interface pragmas or a processor domain from an old example. A Vitis kernel object and a Vivado IP package have different intended integration flows; export the form actually consumed by this project.

Define reset/start/done/error behavior, status and result validity, memory extents, byte ordering and invocation identity. Distinguish loading data, preparing a job, running it and making results visible. A persistent local ROI/table or cached coefficient is reusable only under a validated identity/configuration and invalidation protocol. Repeated invocation, new input, reset, failed job and abort paths need tests, not just one successful call.

Buffers and descriptors must remain valid for all external accesses, including in-flight work after timeout. The current target's driver/BSP owns addresses, visibility and drain handling; HLS completion or an interrupt by itself does not establish all of these boundaries. Keep unsupported input status or a defined software fallback where required; do not silently clamp inputs or reduce candidate work to obtain a pass.

## Synthesize, optimize and verify distinct stages

Use the installed HLS CLI/component configuration or exported MATLAB workflow script. Discover exact commands locally; old script names are examples, not a required harness. AMD's [HLS guide](https://docs.amd.com/r/en-US/ug1399-vitis-hls) documents C simulation, scheduling/directives, interface generation, co-simulation and export; its current release is not a fixed prerequisite.

1. Run the reference and generator-specific high-level/C simulation on the declared corpus. Record differences at the earliest stage, including decisions and error paths.
2. Synthesize with the actual part/clock and explicit top. Read achieved II, latency ranges, memory-port/dependency constraints and LUT/FF/BRAM/DSP estimates. A requested `PIPELINE II` or loop trip-count annotation is not an achieved schedule or a validity bound.
3. Change one supported architecture factor at a time: storage/banking, legal pipelining/unrolling, operator sharing, dataflow/FIFO capacity, or load/compute organization. Honor dependencies and interface behavior. Do not suppress a real dependency or assume dataflow is safe without channel/deadlock evidence.
4. For repeated work, separate reusable input load from per-job data, and consider a bounded batch/control loop that preserves the required evaluation and acceptance order. This can reduce repeated transfers and launch/register traffic without duplicating a compute pipeline. Compare every transition to the reference after restructuring.
5. Run applicable generated-RTL verification: C/RTL co-simulation for HLS, and the selected HDL workflow's test bench/equivalence checks. Declare workload sizes, number of calls, states and error cases. Reduced-feature or reduced-length simulation does not qualify the untested full workload. A stalled simulation, deferred run or unsupported interface stays explicit.
6. Export the verified candidate RTL/IP with source/configuration/test/report hashes. Add the actual package and version to Vivado; refresh its catalog/instance and compare generated ports/register metadata. Keep generated HDL edits out of the maintained-source path unless they are an explicitly maintained artifact.
7. Validate integration clocks/resets, addresses, memory/stream connections, interrupts and constraints. Use actual Vivado implementation timing and joint resources to accept a candidate, then update the matching hardware export and affected Vitis software inputs. HLS estimates and co-simulation cannot qualify route timing, CDC or board behavior.

When measuring gains, separate kernel load/compute cycles, transfer/driver/launch/wait/release cost and complete-job time. Preserve equivalent work and correct results. Kernel II or a stage speedup does not establish a system frame rate. This measurement serves implementation acceptance; it does not expand the request into a new PS/PL partition study.

## Deliver reusable IP

Keep design/reference/test sources, data types and interface contract, generation configuration/directives, part/clock parameters, commands and tool identities, generated package identity, actual stage results and remaining coverage. State whether numeric equivalence, full-workload RTL, integrated timing and target operation were each established. The methods are self-contained and do not require another skill.
