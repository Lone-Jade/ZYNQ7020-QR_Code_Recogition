# Build boundaries and delivery

Inspect actual source lists, top/module, packaged IP and build options. A modified source Tcl or HDL file does not update an existing generated design automatically. Compare maintained and imported/packaged copies before attributing a failure to new source.

For a processor/logic design, establish peripheral ownership, address map, clocks, resets, interrupt routing, memory and software domain. PS MIO and PL pins require different changes; a PS-only peripheral design may legitimately contain only the processing-system block. Derive assignments from current board evidence.

Treat design validation, implemented setup/hold timing, unconstrained paths, DRC, image creation and export contents as separate checks. Fix an unintended external port or an invalid crossing at its origin, not by downgrading checks. Tie reports to the run that produced the delivered image.

Generate platform/runtime inputs from the current hardware export. Inspect actual driver lookup mode, addresses, linker layout and ELF target ABI. New C translation units must enter the build; a more recent executable may still contain stale imported source. Keep necessary BSP/runtime patches repeatable and verify the final linked output after regeneration.

When a platform export is missing, inspect the first compiler/archiver/generator failure before changing export paths. Resolve executable availability in the server actually building it. Preserve an active GUI workspace and use a sibling generated workspace rather than deleting its lock or killing unrelated processes. Use short output paths when an observed path-length limit warrants them.

For cold start use initialization matching the hardware and the supported debugger/boot flow. Enumerate actual targets, distinguish true program returns from retained breakpoints, and configure required logic before application MMIO access. Do not flatten all revision variants of a generated initialization script into one sequence.

Deliver the accepted pair, candidate status, dependencies, evidence and recovery state. A later offline build is a newer candidate, not automatically a board-qualified continuation of an earlier test. Keep existing service/boot preferences and user restore scope.
