# Identity is more than a label

Use complete content when equality is required, then separate entity/pass identity through temporal/spatial evidence. A short display label or hash can collide; equal content can appear at two locations or re-enter later. A fragmented tracker must not silently suppress the first valid business output.

Keep pixels, candidates, threshold/ROI, coordinates and result identity bound to a coherent source generation. Motion from another candidate does not prove the new location of an old decoded result. Reject stale geometry or explicitly downgrade its use rather than silently relabeling it as current.

Record proposed event, queue acceptance and commit separately. If several queues must accept atomically, define rollback or reservation; do not advance an output ID before the actual acceptance point. A retry preserves the uncommitted identity as the protocol requires. Capacity limits and drop/retention policy come from requirements and workload, not arbitrary historical constants.

OSD/display submission, consumption/acknowledgement and the physical screen are different evidence. A software function call proves only the call. Use the actual available acknowledgement and observation; do not fabricate one. Avoid writing overlays into data later used for recognition unless explicitly part of the design.

Test full queues, same-content separate targets, truncated labels, expired location, ID/time wrap, pause/end/reset/restart and partial failures. Preserve the prior valid baseline and distinguish synthetic replay from target timing/display effects.
