#include "qr_binary_pack.h"
#if defined(__ARM_NEON)
#include <arm_neon.h>
static unsigned mask8(const void *source, unsigned pixel_bytes)
{
    static const uint8_t weights[8] = {1,2,4,8,16,32,64,128};
    uint8x8_t bits;
    if (pixel_bytes == 1)
        bits = vmvn_u8(vceq_u8(vld1_u8(source), vdup_n_u8(0)));
    else
        bits = vmovn_u16(vmvnq_u16(vceqq_u16(vld1q_u16(source), vdupq_n_u16(0))));
    return (unsigned)vget_lane_u64(vpaddl_u32(vpaddl_u16(vpaddl_u8(
        vand_u8(bits, vld1_u8(weights))))), 0);
}
#endif
int qr_binary_pack(uint32_t *dst, size_t words, const void *pixels,
                   unsigned width, unsigned height, unsigned pixel_bytes)
{
    unsigned stride, y;
    if (!dst || !pixels || !width || !height || width > 1280 || height > 720 ||
        (pixel_bytes != 1 && pixel_bytes != 2)) return -1;
    stride = (width + 31) / 32;
    if (words < (size_t)stride * height) return -1;
    for (y = 0; y < height; ++y) {
        unsigned base;
        for (base = 0; base < width; base += 32) {
            unsigned x = base, end = width - base < 32 ? width : base + 32;
            uint32_t value = 0;
#if defined(__ARM_NEON)
            for (; x + 8 <= end; x += 8)
                value |= (uint32_t)mask8((const uint8_t *)pixels +
                         ((size_t)y * width + x) * pixel_bytes, pixel_bytes) << (x - base);
#endif
            for (; x < end; ++x) {
                size_t index = (size_t)y * width + x;
                unsigned black = pixel_bytes == 1 ? ((const uint8_t *)pixels)[index] != 0 :
                                                  ((const uint16_t *)pixels)[index] != 0;
                value |= (uint32_t)black << (x - base);
            }
            dst[(size_t)y * stride + base / 32] = value;
        }
    }
    return 0;
}
