# Scope and verification limits

Asynchronous shared-buffer ownership, DMA visibility, leases, completion and stop/recovery behavior.

The trace checker covers a documented normalized model. Software traces and hashes do not prove real DMA quiescence, coherency or protected memory lifetime.

Use the checks appropriate to the requested change and report which were actually executed. Package contents are reusable procedures and helpers; they do not certify a new environment or target.
