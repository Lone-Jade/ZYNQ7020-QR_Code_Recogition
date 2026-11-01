# Verify meaningful transfers

Trace packing, coordinates, frame identity and completion through each conversion/FIFO/branch. Compare configured geometry with actual producer output and consumer stride. Counting VALID alone double-counts stalled items. Distinct data per frame/pixel exposes drop-plus-duplicate faults that equal totals miss.

For AXI-Stream, use the installed interface contract and [Arm protocol reference](https://documentation-service.arm.com/static/64819f1516f0f201aa6b963c). The [AMD video profile](https://docs.amd.com/r/en-US/ug934_axi_videoIP/AXI4-Stream-Signaling-Interface) gives SOF/EOL semantics; these are not generic meanings for every packet stream. Multiple pixels and partial byte lanes need explicitly different accounting.

Hold READY low while an unstoppable camera source continues. Within declared capacity, check exact buffered data; beyond capacity, verify observable overflow and bounded frame recovery. Enlarging storage alone cannot prove all bursts are safe. Verify fork behavior under one stalled branch according to the intended coupling/drop contract.

For a new scanner or transform, compare a frozen input and intermediate output with an independent reference. Exercise bounds, reset mid-frame, empty/bad frame, repeated start, sideband latency and accepted totals. Keep malformed stimulus tests distinct from legal traffic; first verify the source/testbench is compliant.

For asynchronous domains, test rate/phase/reset relationships and inspect synchronizers, multi-bit transfers and FIFO pointers. Constrain real crossings narrowly with actual names and review reports. Clock grouping cannot replace functional correctness or turn a broad false path into evidence.
