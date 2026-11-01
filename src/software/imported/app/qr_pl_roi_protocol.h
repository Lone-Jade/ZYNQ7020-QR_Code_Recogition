#ifndef QR_PL_ROI_PROTOCOL_H
#define QR_PL_ROI_PROTOCOL_H

#include <stdint.h>

/* Version 2 camera ABI. DDR words are little endian; ROI bounds are half open.
 * The pixel row immediately after the header is image y=0. Binary8 is black=0,
 * white=255, and is deliberately not the legacy debug-binary polarity. */
#define QR_PL_ABI_VERSION       0x00020003U
#define QR_PL_HEADER_MAGIC      0x32485251U
#define QR_PL_FOOTER_MAGIC      0x32465251U
#define QR_PL_FORMAT_GRAY8      1U
#define QR_PL_FORMAT_BINARY8    2U
/* Guard/bank first four reserved words: method, grid[0..3], grid[4..7], grid[8]|mask<<8.
 * Method 0 is manual uniform; 3 is a 3x3 interpolated threshold field.
 * For method 3, threshold is the centre tile value (metadata, not a global T).
 * Mask marks tiles updated by the source frame; other tiles retain a prior
 * valid value, or the manual threshold when no prior grid exists. */
#define QR_PL_THRESHOLD_CENTRE  1U
#define QR_PL_THRESHOLD_POOLED5 2U
#define QR_PL_THRESHOLD_GRID3   3U
#define QR_PL_THRESHOLD_MEAN5   4U
#define QR_PL_GUARD_WORDS       16U
#define QR_PL_ROI_BANKS         3U
#define QR_PL_ROI_LIMIT         30U
#define QR_PL_BANK_BASE         0xA000U
#define QR_PL_BANK_STRIDE       0x0800U
#define QR_PL_BANK_DESC_BYTES   64U
#define QR_PL_ROI_BYTES         64U
#define QR_PL_COMPLETE          1U
#define QR_PL_AXIS_ERROR        2U
#define QR_PL_RAW_OVERFLOW      4U
#define QR_PL_CLUSTER_OVERFLOW  8U
#define QR_PL_ROI_OVERFLOW      16U
#define QR_PL_TIMEOUT           32U
#define QR_PL_ROI_CLIPPED       1U

typedef struct {
    uint32_t magic, version, epoch, frame_seq, frame_seq_inverse;
    uint32_t config_seq, format, dimensions, threshold, threshold_source;
    uint32_t pixels, flags, reserved[4];
} qr_pl_guard_t;

typedef struct {
    uint32_t generation, epoch, frame_seq, config_seq, roi_count, flags;
    uint32_t threshold, threshold_source, raw_count, cluster_count;
    /* [4]: rejected16 | original geometry passed16; [5]: 0x5343 | limit16. */
    uint32_t reserved[6];
} qr_pl_bank_t;

typedef struct {
    uint32_t min_xy, max_xy, finder_xy[3], module_angle, hits, flags;
    uint32_t reserved[8];
} qr_pl_roi_t;

typedef char qr_pl_guard_size_check[sizeof(qr_pl_guard_t) == 64U ? 1 : -1];
typedef char qr_pl_bank_size_check[sizeof(qr_pl_bank_t) == 64U ? 1 : -1];
typedef char qr_pl_roi_size_check[sizeof(qr_pl_roi_t) == 64U ? 1 : -1];

static inline uint16_t qr_pl_x(uint32_t xy) { return (uint16_t)xy; }
static inline uint16_t qr_pl_y(uint32_t xy) { return (uint16_t)(xy >> 16); }

/* Pure validation helpers, shared by the camera capture path and offline tools.
 * A result bank is never paired using frame_seq % 3 or a VDMA slot number. */
int qr_pl_guards_valid(const qr_pl_guard_t *header, const qr_pl_guard_t *footer,
                       uint32_t width, uint32_t height, uint32_t format,
                       uint32_t epoch, uint32_t config_seq);
int qr_pl_bank_matches(const qr_pl_bank_t *bank, const qr_pl_guard_t *header);
int qr_pl_roi_valid(const qr_pl_roi_t *roi, uint32_t width, uint32_t height);

#endif
