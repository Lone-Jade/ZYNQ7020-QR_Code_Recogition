---
name: camera-hdmi-diagnosis
description: Diagnose camera acquisition and physical display failures by separating source/control, format/geometry, memory, processing and HDMI output evidence. Use for frozen, torn, miscolored, displaced or absent video; do not assume a board, sensor, driver or display mode.
---

# Camera and HDMI Diagnosis

Identify actual input and display paths, source format/timing, controls, clocks/resets, geometry/stride, buffers, conversions and current software/hardware identities. A camera preview, recognition source and network output may use different paths.

Read [layered video checks](references/layered-video.md) for only the uncertain boundary. Preserve first useful errors and use a changing scene or known pattern. Sensor identification/configuration success does not prove emitted pixels; a running engine or refreshing screen does not prove fresh complete frames.

Compare configured and generated producer/consumer geometry, packing and sideband conventions. Check color/endian arithmetic with known values, not an assumed universal channel swap. Trace coordinates through crop/scale/rotation and confirm source identity/age before associating an overlay.

Isolate output with stored patterns, capture with time-separated full-size or representative multirow evidence, and later consumers with a protected snapshot. Account for probes that pause the CPU or write signatures. A clean stopped dump cannot qualify a slow live consumer's full lifetime.

For Linux distinguish boot, display driver, connector/mode, running scene and physical sink. For standalone distinguish initialization, retained debugger stops, application failures, DMA setup and physical output. Use actual driver/API evidence instead of transplanting a board-specific recipe.

Verify the original symptom and relevant stop/restart behavior. Preserve accepted mode/artifacts and bound configuration experiments. Report measured camera novelty, memory integrity, processing and display observations separately, with physical checks explicitly untested when unavailable.

Read [scope and verification limits](references/provenance.md) when choosing checks or interpreting results.
