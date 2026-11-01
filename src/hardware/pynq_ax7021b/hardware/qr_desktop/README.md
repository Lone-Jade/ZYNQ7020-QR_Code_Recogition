# AX7021B QR video hardware

The checked-in Tcl, XDC and RTL form the static boot-loaded Zynq design.
The R4 video path provides independent PL RGB565 preview, Gray8 capture with
ROI metadata, PL fitness acceleration and HDMI text/box overlay.

Use `python3 -B build/scripts/hardware.py rebuild1` from the project root to
create a clean Vivado project. Run `build/scripts/qualify.py` on its final
implementation before packaging the boot image. Full commands and the matched
toolchain are documented in the project README.
