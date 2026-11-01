# Exclusive-consumer trace adapter

`scripts/check_exclusive_dma_trace.py` retains the Ubuntu format-1 checker. Supply a JSON object with exactly `format:1`, boolean `complete`, and nonempty `events`. Use `--help` for the CLI. The model is exclusive-consumer and format-specific, not an assumed live driver API.

Slot events include alloc/free; arm; confirmed complete; acquire/read/release by lease; private snapshot/read_snapshot; timeout; confirmed quiesce; quarantine. Arm/completion/lease operations carry the specified identity tuple `epoch,frame,config,generation`; snapshot reads use snapshot identity. The helper rejects unknown fields, stale/reused tokens, illegal ownership and unsafe free. A complete trace can retain explicitly quarantined storage; it cannot pretend this is freed.

Exit 0 means a complete supplied lifecycle satisfies this model; 1 means violations; 2 means unsupported/malformed input; 3 means a valid but explicitly incomplete trace with no observed violation. An incomplete observation is not a completed-lifecycle pass. This does not inspect kernel/BSP code, cache operations, real locks, multiple consumers or hardware drain. Use actual source/observations to construct the trace; never invent absent fields to get a pass. Preserve the source trace and adapter identity when exporting a normalized one.
