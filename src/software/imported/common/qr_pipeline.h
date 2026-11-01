#ifndef QR_PIPELINE_H
#define QR_PIPELINE_H

#include <stdint.h>

#include "qr_decode_backend.h"

#define QR_V1_MODULE_COUNT 29
#define QR_MAX_CANDIDATES 2048
#define QR_MAX_CENTERS 128
#define QR_MAX_INSTANCES 8
#define QR_MAX_HYPOTHESES 128
#define QR_MAX_PAYLOAD 1024

typedef struct {
    float x;
    float y;
    float module_size;
    float score;
} qr_candidate_t;

typedef struct {
    float x;
    float y;
    float module_size;
    float score;
    uint16_t hits;
} qr_center_t;

typedef struct {
    qr_candidate_t finder[3];
    float score;
} qr_finder_triple_t;

typedef enum {
    QR_PIXEL_FORMAT_GRAY8 = 0
} qr_pixel_format_t;

/* Camera-ready image view. Stride is expressed in bytes. */
typedef struct {
    const uint8_t *data;
    int width;
    int height;
    int stride;
    qr_pixel_format_t pixel_format;
} qr_frame_view_t;

typedef struct {
    int threshold;
    int module_count;
    int max_instances;
    int max_triple_centers;
    int enable_roi_otsu;
    int minimum_payload_length;
    int max_finder_mismatches;
    int max_timing_mismatches;
    float local_vertical_half_modules;
    int local_vertical_margin_pixels;
} qr_detector_config_t;

typedef enum {
    QR_STAGE_OK = 0,
    QR_STAGE_VERTICAL = 1,
    QR_STAGE_CLUSTER = 2,
    QR_STAGE_TRIPLE = 3,
    QR_STAGE_SAMPLE = 4,
    QR_STAGE_DECODE = 5,
    QR_STAGE_ARGUMENT = 6
} qr_stage_t;

typedef struct {
    qr_stage_t stage;
    float finder_tl_x, finder_tl_y;
    float finder_tr_x, finder_tr_y;
    float finder_bl_x, finder_bl_y;
    float outer_corners[8]; /* display metadata: absolute x/y, no decode decisions */
    unsigned outer_corners_valid;
    float geometry_score;
    int module_count;
    int sample_threshold;
    uint8_t modules[QR_V1_MODULE_COUNT * QR_V1_MODULE_COUNT];
    char payload[QR_MAX_PAYLOAD];
    qr_decode_info_t decode_info;
    int decode_status;
} qr_instance_t;

typedef struct {
    qr_stage_t stage;
    uint16_t vertical_count;
    uint16_t center_count;
    uint16_t instance_count;
    qr_instance_t instances[QR_MAX_INSTANCES];

    /* V1/V1.1 compatibility view of instances[0]. */
    float finder_tl_x, finder_tl_y;
    float finder_tr_x, finder_tr_y;
    float finder_bl_x, finder_bl_y;
    uint8_t modules[QR_V1_MODULE_COUNT * QR_V1_MODULE_COUNT];
    char payload[QR_MAX_PAYLOAD];
    qr_decode_info_t decode_info;
    int decode_status;
} qr_pipeline_result_t;

typedef uint64_t (*qr_profile_clock_fn)(void *context);

typedef struct {
    uint64_t vertical_ticks;
    uint64_t sort_ticks;
    uint64_t cluster_ticks;
    uint64_t triple_ticks;
    uint64_t otsu_ticks;
    uint64_t sample_ticks;
    uint64_t decode_ticks;
    uint32_t vertical_pixels_examined;
    uint32_t vertical_candidates_rechecked;
    uint32_t otsu_pixels_examined;
    uint32_t triple_combinations;
    uint32_t triple_right_angle_tests;
    uint32_t triple_geometry_passes;
    uint32_t hypotheses_kept;
    uint32_t structure_rejects;
    uint32_t decode_attempts;
    uint32_t instances_found;
    uint32_t fallback_used;
} qr_pipeline_profile_t;

void qr_detector_config_default(qr_detector_config_t *config);

/* Convert horizontal PL run-length hits into perspective-aware finder
 * triples.  The output is intended as a small ROI hint list for a general QR
 * decoder; it does not sample or decode modules itself. */
typedef struct {int vertical_count, center_count, triple_count; qr_stage_t stage;} qr_locator_profile_t;
int qr_pipeline_find_triples_profiled(const qr_frame_view_t *frame,
 const qr_detector_config_t *config, const qr_candidate_t *horizontal,
 int horizontal_count, qr_finder_triple_t *triples, int triple_capacity,
 qr_locator_profile_t *profile);
int qr_pipeline_find_triples(const qr_frame_view_t *frame,
                             const qr_detector_config_t *config,
                             const qr_candidate_t *horizontal,
                             int horizontal_count,
                             qr_finder_triple_t *triples,
                             int triple_capacity);

int qr_pipeline_run_v1_2(const qr_frame_view_t *frame,
                         const qr_detector_config_t *config,
                         const qr_candidate_t *horizontal, int horizontal_count,
                         qr_pipeline_result_t *result,
                         qr_pipeline_profile_t *profile,
                         qr_profile_clock_fn clock_fn, void *clock_context);

int qr_pipeline_run(const uint8_t *gray, int width, int height, int threshold,
                    const qr_candidate_t *horizontal, int horizontal_count,
                    qr_pipeline_result_t *result);

int qr_pipeline_run_profiled(const uint8_t *gray, int width, int height, int threshold,
                             const qr_candidate_t *horizontal, int horizontal_count,
                             qr_pipeline_result_t *result,
                             qr_pipeline_profile_t *profile,
                             qr_profile_clock_fn clock_fn, void *clock_context);

const char *qr_stage_string(qr_stage_t stage);

#endif
