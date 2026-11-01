# Narrow the first unsupported video boundary

## Source/control and geometry

Inspect power/reset/control timing and actual write/read outcomes appropriate to the sensor/interface. Derive valid dimensions and rate from current evidence; a successful register table or ID alone does not establish data emission. Sensor-specific stream-on behavior remains a scoped observation, not a rule for all cameras.

Trace pixel widths, packing/endian order, line/frame markers, accepted counts, stride and buffer extents. A producer EOL threshold beyond the actual line length can freeze most of a frame. Check generated hardware and current software, not only desired macros. Include diagnostic tools and host parsing in a geometry change.

## Memory and consumers

Compare changed content across rows/times with a known changing stimulus. Separate startup-latched status from errors recurring after the proper acknowledgement. Do not interpret a raw completion counter as unique physical frames without checking its semantics.

Check the ownership interval through copies, processing and transmission. Three buffers or a completed index does not ensure an arbitrarily slow reader is safe. Use the shared-buffer method if reuse/visibility is uncertain. Keep the recognition input clean when adding OSD; overlay in an independent display path or an explicitly separate output.

## Display and optics

Use known color bars/patterns to distinguish scanout/timing from capture. Check current connector/sink/mode and link negotiation when relevant; a boot log or successful render submission is not physical confirmation. For Linux inspect the actual display subsystem state, permissions and active compositor/application rather than automatically replacing boot images. For standalone inspect return/error paths and debugger stops before rebuilding hardware.

For optical measurements bind source scene, seed, viewport, camera framing/focus, exposure and eligibility windows. A control heartbeat does not prove correct scene or focus. When the person changes physical geometry, reestablish affected baselines. Crop/scale/rotation and lens distortion are different phenomena; avoid inferring a register repair from appearance alone.

Select a bounded read/check through the actual installed APIs. Do not embed one board's IIC addresses, pin assignments, display mode, kernel command or fixed sensor table as a default.
