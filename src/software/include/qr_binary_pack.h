#ifndef QR_BINARY_PACK_H
#define QR_BINARY_PACK_H
#include <stddef.h>
#include <stdint.h>
/* Each row starts at a fresh word; nonzero region labels are black. */
int qr_binary_pack(uint32_t *dst, size_t words, const void *pixels,
                   unsigned width, unsigned height, unsigned pixel_bytes);
#endif
