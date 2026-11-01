# Optional, explicitly scoped adapters

All helpers use the Python standard library and are read-only except creating a requested new report.

- `scripts/verify_package_files.py --package DIR --manifest manifest.json`: a `files` mapping format, relative forward-slash paths to SHA-256. It permits resolved internal links but rejects escaping paths; it is not the strict no-link Linux release format. Exit 0/1/2 means listed bytes matched / listed-file failure / input or output error. `--output` creates a new report only.
- `scripts/inspect_zynq_handoff.py --xsa FILE --bit FILE --elf FILE`: a Zynq-7000 adapter checking an embedded bit, HWH/PS initialization membership and an ARM ELF32 header. This target-specific adapter must only be selected for that actual format; it does not apply to other hardware, imply target support or establish BSP/profile compatibility. See `--help` for an optional marker and exclusive report output.

Neither adapter validates the truth of a manifest's author, unlisted files, current hardware, implemented timing or behavior. Use a format-appropriate existing inspection method when these adapters do not fit; do not coerce another target into their schema.
