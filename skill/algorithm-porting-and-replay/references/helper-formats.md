# Optional tools with narrow formats

## Typed arrays

`python scripts/compare_stages.py comparison.json [--report NEW_JSON]` accepts schema_version 1 with a nonempty ordered stages list. Each unique stage names dtype, positive shape, reference/actual files and a frozen reference_sha256. Supported types: u8, u16le, i16le, u32le, i32le, f32le, f64le. File size must match exactly.

Optional finite nonnegative abs_tol/rel_tol use absolute error at most abs_tol plus rel_tol times the reference magnitude. NaN/Inf, nonfinite arithmetic, missing/hash-mismatched inputs or empty comparisons fail. It reports every declared stage and the first failing one. Exit 0/1/2 means all declared numeric checks passed / input-stage failure / CLI-report error. Reports are exclusively created. No candidate-set or decoder semantic equivalence is inferred.

## Bounded Gray8 snapshot

`scripts/failure_bundle_gray8.py` uses format 1; inspect `--help` for create/verify arguments. It validates an explicit case/failure, identity tuple, provenance, Gray8 width/height/stride, in-frame ROIs and selected artifact paths under a byte budget. It creates a new directory only, freezes payload hashes and preserves unknown provenance as warnings. It does not invoke a runner or capture a board.

Target-oriented provenance fields may explicitly be null; the schema does not require Linux. Use a different explicit adapter when another input representation is needed. The helper rejects Windows-drive and colon-bearing paths to keep bundle paths portable.

Treat traversal, escaping/ambiguous paths, duplicate keys, mismatched image length, mutated payload or out-of-frame ROI as invalid input, not successful replay. A verified bundle proves listed input consistency, not its provenance's truth or algorithm correctness.
