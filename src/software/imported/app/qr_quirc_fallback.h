#ifndef QR_QUIRC_FALLBACK_H
#define QR_QUIRC_FALLBACK_H

#include "qr_pipeline.h"

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Diagnostic data for the perspective-aware fallback.  The fallback uses
 * the PL finder candidates only to reduce the scan rectangle; quirc still
 * performs its own finder grouping, version estimation, alignment-pattern
 * search, homography and ECC decode inside that rectangle. */
typedef struct {
    uint16_t roi_x;
    uint16_t roi_y;
    uint16_t roi_width;
    uint16_t roi_height;
    uint16_t grids_found;
    uint16_t decode_attempts;
    uint16_t decoded_instances;
    uint16_t mirrored_instances;
    uint16_t adaptive_retry;
    uint16_t adaptive_grids_found;
    uint16_t identify_calls;
    uint16_t no_grid_scans;
    uint32_t copy_us;
    uint32_t adaptive_us;
    uint32_t identify_us;
    uint32_t decode_us;
    uint32_t regions_seen;
    uint32_t capstones_seen;
    uint16_t max_regions;
    uint16_t max_capstones;
} qr_quirc_fallback_profile_t;

typedef void (*qr_quirc_observer_fn)(int error, int mirrored, int length_rejected,
                                     const uint8_t *payload, int length);
void qr_quirc_set_observer(qr_quirc_observer_fn observer);
/* Explicit PL ROI routes. private_roi is already copied out of the DMA
 * ring, with local coordinates and an arbitrary positive byte stride.
 * Both APIs keep quirc finder/grid/perspective sampling and ECC handling.
 * Binary8 requires exactly black=0/white=255, skips every PS threshold
 * and adaptive retry, and returns -4 on any non-binary pixel. Gray8 is a
 * diagnostic Otsu-only route. Neither expands the ROI or falls back to a
 * full-frame scan. The format field remains GRAY8 for source compatibility;
 * choosing the binary API is the explicit Binary8 contract. absolute_x/y
 * are added to every decoded symbol's own finder coordinates. The default
 * detector payload/instance limits apply. profile describes absolute ROI.
 * Calls are serialized: the shared quirc workspace is not reentrant. */
int qr_quirc_binary_roi_run(const qr_frame_view_t *private_roi,
                           uint16_t absolute_x, uint16_t absolute_y,
                           qr_pipeline_result_t *result,
                           qr_quirc_fallback_profile_t *profile);
int qr_quirc_gray_roi_run(const qr_frame_view_t *private_roi,
                         uint16_t absolute_x, uint16_t absolute_y,
                         qr_pipeline_result_t *result,
                         qr_quirc_fallback_profile_t *profile);
/* Run the perspective/multi-version fallback and append decoded instances to
 * result.  Gray8 may have an arbitrary positive stride.  Returns the number
 * of newly decoded symbols, zero for a normal no-code result, or a negative
 * value for invalid geometry/resource limits. */
int qr_quirc_fallback_run(const qr_frame_view_t *frame,
                          const qr_candidate_t *horizontal,
                          int horizontal_count,
                          const qr_detector_config_t *config,
                          qr_pipeline_result_t *result,
                          qr_quirc_fallback_profile_t *profile);

#ifdef __cplusplus
}
#endif

#endif
