# Whole-grid HLS scoring interface

The kernel uses one `score_resident` call site and an II=2 sample pipeline.
The PS supplies rounded candidate coefficient bit patterns; the optimizer
visits their dependent decision tree and evaluates 81 scores per grid.

From the project root, run `python3 -B build/scripts/build_hls.py --stage all`
for native reference checks, C simulation, synthesis, IP export and reduced
C/RTL comparison. Outputs are written under `build/work/hls/` and
`build/reports/generated/hls/`. Reference HLS reports are retained under
`build/reports/hls-qualified/`.

HLS estimates and reduced co-simulation do not establish routed system timing,
full-feature hardware equivalence, or optical recognition accuracy. Rebuilt IP
requires the complete hardware qualification and board validation described in
the project README.

## Operations

| operation | behavior |
| --- | --- |
| 0 | Legacy combined ROI/feature load; original port order and job behavior |
| 1 | One score of the resident feature list; strict grid job after operation 5 |
| 2 | Invalidate ROI and grid, and publish hardware magic/ABI/capabilities |
| 3 | Load only packed binary ROI; retain until another ROI load/invalidation |
| 4 | Load feature list, then execute all 81 dependent optimizer evaluations |
| 5 | Load only feature list, for legacy per-score hardware comparison |

ROI identity is `(epoch,frame,config,roi_id,binary_generation)`. Operations 4/5
bind a new `job_id`. A wrong identity rejects before reading external memory.
Every call overwrites scalar outputs and publishes magic `0xAC04F003`, hardware
ABI 2 and capability bits `0x3f`. Drivers must check these before using v2 work.
All DMA access is read-only; result and optional trace are AXI-Lite outputs.

Operation 3 reads `stride_words*height` packed binary words from `memory`.
Operation 4 reads `cells` feature words from the start of `memory`, then accesses
the candidate tree at `tree_word_offset >= cells` (32-bit alignment suffices).
The tree is eight
1023-node heaps, 64 bits/node, low uint32 word first. Its 65,472 bytes stay in DDR.
The caller must hold the entire allocation until completion or proven HP drain.

For each coefficient, node 0 is the first negative trial; reject selects
`2*node+1`, accept selects `2*node+2`. The ten levels are pass 0 minus/plus through
pass 4 minus/plus. No independent trials are submitted in parallel. Initial
score, pass order, coefficient order and strict score comparison match C04.

Successful operation 4 returns the best score, `score_count=81`, and eight final
binary64 coefficient bit patterns. If requested, trace[0..80] contains the score
in signed 31-bit form and bit 31 indicates acceptance (zero on initial score).
This is sufficient to replay every visited tree node without storing all
candidate coefficients. Disabled trace contents are unspecified.

Status 1 is invalid geometry/count/job, 2 is identity/operation, 3 is numeric
domain, 4 is feature encoding, 5 is tree bounds. `error_step` identifies the
first invalid coefficient trial, and `score_count` includes only scores that
actually finished. A failed whole-grid result is never accepted or partially
continued: the application restores initial coefficients and counts a fallback.
