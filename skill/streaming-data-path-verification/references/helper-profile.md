# One-pixel video helpers

The unmodified local-Win11 helpers are optional: `assets/axis_video_monitor.sv`, `assets/tb_axis_video_monitor.sv`, and `scripts/check_axis_trace.py`. They support one pixel per beat, full keep, scalar SOF, EOL and complete progressive frames. These constraints describe a helper, not every project handled by this skill.

The monitor samples `clk, reset_n, valid, ready, data, keep, user, last` and exposes counters. Parameters select DATA_WIDTH/WIDTH/HEIGHT and a declared reset-abort policy. Its counters restart on reset. The self-test has seed `19b7`, a bounded timeout and payload scoreboard; optional FAULT=stall/last/sof/unknown must cause a corresponding fatal, not be counted as a successful simulation merely because a launcher returns 0.

The CSV helper requires every rising edge, with consecutive `cycle,reset_n,valid,ready,data,keep,user,last` samples. Example: `python scripts/check_axis_trace.py trace.csv --width 4 --height 2 --data-bits 16 --frames 3`. It checks stalled-item stability including the accepting edge, markers, counts, reset and EOF. Its completed count is cumulative across allowed reset aborts. X/Z valid payload, partial keep and missing cycles fail.

Optional `--expected-data FILE --expected-sha256 HEX` checks little-endian accepted words for exactly the requested complete frames; it cannot index reset-aborted generations. Without golden data, legal-marker-preserving corruption can remain undetected. `--report` refuses overwrite. Exit 0/1/2 means observed profile passed / input or check failure / CLI or output error. No helper invokes hardware or establishes CDC/timing qualification.
