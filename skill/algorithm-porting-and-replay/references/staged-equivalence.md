# Freeze semantics, then port

Define byte/channel order, dimensions/stride, intermediate arithmetic width, shifts/division, rounding, threshold polarity, saturation and index/capacity behavior. Keep the established algorithm's stage boundaries; matching an example output through another full-image detector does not verify the same implementation.

Separate preprocessing, candidates, geometry, sampled representation and final decoding/status. Full payload success can hide module differences. Candidate count alone is not set equivalence, and unspecified order is not a valid exact-order contract. Establish a justified matching rule rather than sorting away frame/coordinate errors or relaxing tolerance after a failure.

Negative cases require expected status/count and payload semantics. Empty output is not automatically success, and empty comparisons can be vacuous. Freeze mandatory, boundary and exploratory groups before scoring so scope does not silently shrink to successful inputs.

Keep shared kernels independent of MMIO/UART/DMA and make memory/scratch extents and failure behavior explicit. Host diagnostics/tests can expose arithmetic and algorithm errors; target ABI, alignment, stack, cache and actual stage timing still need target evidence. Inspect source imports and compiled identities.

For a failure bundle, preserve immutable pixels/configuration/identity and explicit provenance gaps. Choose only the minimum useful diagnostic evidence and budget. A file-input replay isolates software behavior on those bytes; it is not a camera test, bus-fault test or physical display reproduction.

Run candidate code only through an explicitly selected and authorized adapter with bounded timeout and defined output/status contract. Keep baseline/candidate results separate. A synthetic runner tests integration behavior, not a real decoder or target execution.
