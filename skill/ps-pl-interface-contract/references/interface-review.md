# Representation and semantics

Specify address spaces, units, half-open/inclusive bounds, strides, byte order, signedness, alignment and access effects. Keep read-only, read/write, write-one-to-clear, pulse and read-to-clear behavior distinct. An observational status read may itself clear state.

For structures and ioctls, verify field offsets/sizes, explicit padding/reserved spans, target alignment and encoded command/argument semantics. Equal total sizes do not prove equal layouts; a type string is not a compiler-derived alignment rule. Freeze the target source/headers/compiler options behind layout measurements.

For transactions, define command publication, acceptance, data validity, DMA drain/visibility, result consumption and release. Polling and IRQ paths must mean the same documented completion. Include timeout/cancel/reset and generation reuse; do not transfer ownership on an unproven notification.

Compare old/new additions, removals, register meaning/effects, layout, identity ordering, completion and restart behavior. Additions may still matter to a particular consumer. A description comparison reports review candidates, not an automatic backward-compatibility verdict. Check actual RTL/DT/BSP/UAPI and source imported into the executable.

Standalone and Linux share these invariants but use different APIs. Keep target compiler layout, driver/user boundaries and memory ownership visible rather than porting BSP cache/MMIO calls directly into a Linux application.
