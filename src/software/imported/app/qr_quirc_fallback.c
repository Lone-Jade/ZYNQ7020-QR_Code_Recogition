#define _POSIX_C_SOURCE 200809L
#include "qr_quirc_fallback.h"
#include "qr_candidate_trace.h"
#include <time.h>
#include "qr_failure_trace.h"

#include "quirc.h"
#include "quirc_internal.h"

#include <string.h>

int qr_quirc_end_binary(struct quirc *q);
int qr_quirc_last_otsu_threshold(void);

#if defined(QR_CAMERA_LIVE) && QR_CAMERA_LIVE
#include "xtime_l.h"
#endif

static uint64_t profile_ticks(void)
{
#if defined(QR_CAMERA_LIVE) && QR_CAMERA_LIVE
    XTime now;
    XTime_GetTime(&now);
    return (uint64_t)now;
#else
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000000ULL + (uint64_t)now.tv_nsec / 1000ULL;
#endif
}

static uint32_t profile_elapsed_us(uint64_t start, uint64_t end)
{
#if defined(QR_CAMERA_LIVE) && QR_CAMERA_LIVE
    return (uint32_t)(((end - start) * 1000000ULL) / COUNTS_PER_SECOND);
#else
    return end > start && end - start > UINT32_MAX ? UINT32_MAX : (uint32_t)(end-start);
#endif
}

/* Current Standalone camera/replay profiles top out at 1280x720.  Keeping the
 * workspace static avoids heap use and makes the worst-case DDR footprint
 * visible in the ELF map. */
#define QR_QUIRC_MAX_WIDTH 1280
#define QR_QUIRC_MAX_HEIGHT 720
#define QR_QUIRC_FILL_VARS ((QR_QUIRC_MAX_HEIGHT * 2) / 3)
/* Historical illumination retry is opt-in; normal Gray8 uses ROI Otsu only. */
#ifndef QR_QUIRC_ENABLE_LOCAL_ADAPTIVE
#define QR_QUIRC_ENABLE_LOCAL_ADAPTIVE 0
#endif
#if QR_QUIRC_ENABLE_LOCAL_ADAPTIVE
#ifndef QR_ADAPTIVE_RADIUS
#define QR_ADAPTIVE_RADIUS 8
#endif
#ifndef QR_ADAPTIVE_BIAS
#define QR_ADAPTIVE_BIAS 7
#endif
#endif

static uint8_t g_quirc_image[QR_QUIRC_MAX_WIDTH * QR_QUIRC_MAX_HEIGHT];
#if QR_QUIRC_ENABLE_LOCAL_ADAPTIVE
static uint32_t g_adaptive_integral[(QR_QUIRC_MAX_WIDTH + 1) *
                                    (QR_QUIRC_MAX_HEIGHT + 1)];
static uint32_t g_adaptive_phase;
#endif
static struct quirc_flood_fill_vars g_quirc_fill[QR_QUIRC_FILL_VARS];
static struct quirc g_quirc;
static struct quirc_code g_quirc_code;
static struct quirc_data g_quirc_data;

static int clamp_int(int value, int minimum, int maximum)
{
    if (value < minimum)
        return minimum;
    if (value > maximum)
        return maximum;
    return value;
}

static void choose_roi(const qr_frame_view_t *frame,
                       const qr_candidate_t *horizontal, int horizontal_count,
                       int *x0, int *y0, int *x1, int *y1)
{
    float min_x = (float)frame->width;
    float min_y = (float)frame->height;
    float max_x = 0.0f;
    float max_y = 0.0f;
    float max_module = 0.0f;
    int valid = 0;
    int i;

    for (i = 0; i < horizontal_count; ++i) {
        const qr_candidate_t *candidate = &horizontal[i];
        if (candidate->x < 0.0f || candidate->x >= (float)frame->width ||
            candidate->y < 0.0f || candidate->y >= (float)frame->height ||
            candidate->module_size <= 0.0f)
            continue;
        if (candidate->x < min_x) min_x = candidate->x;
        if (candidate->x > max_x) max_x = candidate->x;
        if (candidate->y < min_y) min_y = candidate->y;
        if (candidate->y > max_y) max_y = candidate->y;
        if (candidate->module_size > max_module)
            max_module = candidate->module_size;
        ++valid;
    }

    if (valid >= 3) {
        float span_x = max_x - min_x;
        float span_y = max_y - min_y;
        float span = span_x > span_y ? span_x : span_y;
        float margin = max_module * 12.0f;
        /* The three finder patterns do not bound the fourth QR corner after
         * a large rotation.  Half a finder-span covers that missing corner
         * while normally scanning far less than the complete frame. */
        if (margin < span * 0.55f) margin = span * 0.55f;
        if (margin < 24.0f) margin = 24.0f;
        *x0 = clamp_int((int)(min_x - margin), 0, frame->width - 1);
        *y0 = clamp_int((int)(min_y - margin), 0, frame->height - 1);
        *x1 = clamp_int((int)(max_x + margin + 1.0f), *x0 + 1, frame->width);
        *y1 = clamp_int((int)(max_y + margin + 1.0f), *y0 + 1, frame->height);
    } else {
        /* This is intentionally correctness-first.  It also lets Stage 2
         * recover a symbol whose horizontal finder candidates were lost by
         * the fixed-threshold PL front end. */
        *x0 = 0;
        *y0 = 0;
        *x1 = frame->width;
        *y1 = frame->height;
    }
}

static void copy_roi(const qr_frame_view_t *frame,
                     int x0, int y0, int width, int height)
{
    int y;
    for (y = 0; y < height; ++y) {
        memcpy(g_quirc_image + y * width,
               frame->data + (y0 + y) * frame->stride + x0,
               (size_t)width);
    }
}

#if QR_QUIRC_ENABLE_LOCAL_ADAPTIVE
/* Convert unevenly illuminated Gray8 into a locally thresholded 0/255 image.
 * This second-pass input is still consumed by quirc's normal finder,
 * homography and decoder; only the illumination model changes. */
static void adaptive_binarize(int width, int height)
{
    const int integral_stride = width + 1;
    int x;
    int y;

    memset(g_adaptive_integral, 0, (size_t)integral_stride * sizeof(uint32_t));
    for (y = 0; y < height; ++y) {
        uint32_t row_sum = 0U;
        uint32_t *current = g_adaptive_integral + (y + 1) * integral_stride;
        const uint32_t *previous = g_adaptive_integral + y * integral_stride;
        current[0] = 0U;
        for (x = 0; x < width; ++x) {
            row_sum += g_quirc_image[y * width + x];
            current[x + 1] = previous[x + 1] + row_sum;
        }
    }
    for (y = 0; y < height; ++y) {
        int top = y - QR_ADAPTIVE_RADIUS;
        int bottom = y + QR_ADAPTIVE_RADIUS + 1;
        if (top < 0) top = 0;
        if (bottom > height) bottom = height;
        for (x = 0; x < width; ++x) {
            int left = x - QR_ADAPTIVE_RADIUS;
            int right = x + QR_ADAPTIVE_RADIUS + 1;
            uint32_t sum;
            uint32_t count;
            uint8_t source = g_quirc_image[y * width + x];
            if (left < 0) left = 0;
            if (right > width) right = width;
            sum = g_adaptive_integral[bottom * integral_stride + right] -
                  g_adaptive_integral[top * integral_stride + right] -
                  g_adaptive_integral[bottom * integral_stride + left] +
                  g_adaptive_integral[top * integral_stride + left];
            count = (uint32_t)((right - left) * (bottom - top));
            /* Exact integer form of
             *   source + bias < floor(sum / count)
             * without a per-pixel software divide on Cortex-A9. */
            g_quirc_image[y * width + x] =
                (count != 0U &&
                 ((uint32_t)source + QR_ADAPTIVE_BIAS + 1U) * count <= sum)
                    ? 0U : 255U;
        }
    }
}

#endif

static void set_finder_points(qr_instance_t *instance,
                              const struct quirc_code *code,
                              int roi_x, int roi_y)
{
    /* These fields pre-date the perspective path.  Preserve their meaning as
     * approximate finder centres instead of putting outer QR corners into a
     * finder-centre field. */
    const float scale = 3.5f / (float)code->size;
    float top_x = (float)(code->corners[1].x - code->corners[0].x);
    float top_y = (float)(code->corners[1].y - code->corners[0].y);
    float left_x = (float)(code->corners[3].x - code->corners[0].x);
    float left_y = (float)(code->corners[3].y - code->corners[0].y);
    float right_x = (float)(code->corners[2].x - code->corners[1].x);
    float right_y = (float)(code->corners[2].y - code->corners[1].y);

    instance->finder_tl_x = (float)(roi_x + code->corners[0].x) +
                            scale * (top_x + left_x);
    instance->finder_tl_y = (float)(roi_y + code->corners[0].y) +
                            scale * (top_y + left_y);
    instance->finder_tr_x = (float)(roi_x + code->corners[1].x) +
                            scale * (-top_x + right_x);
    instance->finder_tr_y = (float)(roi_y + code->corners[1].y) +
                            scale * (-top_y + right_y);
    instance->finder_bl_x = (float)(roi_x + code->corners[3].x) +
                            scale * (top_x - left_x);
    instance->finder_bl_y = (float)(roi_y + code->corners[3].y) +
                            scale * (top_y - left_y);
}

static void publish_legacy_first(qr_pipeline_result_t *result)
{
    const qr_instance_t *first = &result->instances[0];
    result->finder_tl_x = first->finder_tl_x;
    result->finder_tl_y = first->finder_tl_y;
    result->finder_tr_x = first->finder_tr_x;
    result->finder_tr_y = first->finder_tr_y;
    result->finder_bl_x = first->finder_bl_x;
    result->finder_bl_y = first->finder_bl_y;
    memset(result->modules, 0, sizeof(result->modules));
    memcpy(result->payload, first->payload, sizeof(result->payload));
    result->decode_info = first->decode_info;
    result->decode_status = first->decode_status;
}

static int payload_already_present(const qr_pipeline_result_t *result,
                                   const uint8_t *payload, int payload_len)
{
    uint16_t i;
    for (i = 0U; i < result->instance_count; ++i) {
        const char *known = result->instances[i].payload;
        if ((int)strlen(known) == payload_len &&
            memcmp(known, payload, (size_t)payload_len) == 0)
            return 1;
    }
    return 0;
}

/* The explicit ROI route may see adjacent symbols carrying identical text,
 * or the same symbol again in an overlapping ROI. Only the latter is a
 * duplicate observation. Keep the original payload-only policy in legacy. */
static int symbol_already_present(const qr_pipeline_result_t *result,
                                  const uint8_t *payload, int payload_len,
                                  const struct quirc_code *code,
                                  int roi_x, int roi_y)
{
    qr_instance_t geometry;
    uint16_t i;
    float radius;
    float edge_x = (float)(code->corners[1].x - code->corners[0].x);
    float edge_y = (float)(code->corners[1].y - code->corners[0].y);
    float radius_squared = (edge_x * edge_x + edge_y * edge_y) * 0.01f;
    radius = 8.0f;
    if (radius_squared < radius * radius)
        radius_squared = radius * radius;
    set_finder_points(&geometry, code, roi_x, roi_y);
    for (i = 0U; i < result->instance_count; ++i) {
        const qr_instance_t *known = &result->instances[i];
        float dx, dy;
        if ((int)strlen(known->payload) != payload_len ||
            memcmp(known->payload, payload, (size_t)payload_len) != 0)
            continue;
        dx = known->finder_tl_x - geometry.finder_tl_x;
        dy = known->finder_tl_y - geometry.finder_tl_y;
        if (dx * dx + dy * dy <= radius_squared)
            return 1;
    }
    return 0;
}

static qr_quirc_observer_fn g_decode_observer;
static uint32_t g_sample_us,g_ecc_us,g_attempt_errors[8],g_attempt_flags;
uint32_t qr_quirc_last_sample_us(void){return g_sample_us;}
uint32_t qr_quirc_last_ecc_us(void){return g_ecc_us;}
uint32_t qr_quirc_last_error_count(uint32_t error){return error<8?g_attempt_errors[error]:0;}
uint32_t qr_quirc_last_attempt_flags(void){return g_attempt_flags;}
static int trace_grid_index,trace_roi_x,trace_roi_y;
void qr_quirc_set_observer(qr_quirc_observer_fn observer) {g_decode_observer=observer;}
static void record_attempt(quirc_decode_error_t error, int mirrored,
                           const qr_detector_config_t *config,
                           qr_quirc_fallback_profile_t *profile) {
    int rejected = error == QUIRC_SUCCESS &&
        (g_quirc_data.payload_len < config->minimum_payload_length ||
         g_quirc_data.payload_len >= QR_MAX_PAYLOAD);
    if ((unsigned)error < 8U) ++g_attempt_errors[error];
    if (rejected) g_attempt_flags |= 1U;
    if (mirrored) g_attempt_flags |= 2U;
    if (profile != 0) ++profile->decode_attempts;
    qr_trace_payload((int)error,mirrored,rejected,g_quirc_data.payload,g_quirc_data.payload_len,trace_grid_index);
    {
        qr_trace_record_t *r=qr_trace_add(QRT_GRID);unsigned j;
        if(r){
            r->w[0]=qr_trace_roi_index();r->w[1]=(uint32_t)trace_grid_index;
            r->w[2]=(uint32_t)g_quirc_code.size;r->w[3]=(uint32_t)error;
            r->w[4]=(uint32_t)mirrored;r->w[5]=(uint32_t)rejected;
            if(error==QUIRC_SUCCESS){
                r->w[6]=(uint32_t)g_quirc_data.version;r->w[7]=(uint32_t)g_quirc_data.ecc_level;
                r->w[8]=(uint32_t)g_quirc_data.mask;r->w[9]=(uint32_t)g_quirc_data.payload_len;
            }
            for(j=0;j<4;j++){
                r->w[10+2*j]=(uint32_t)(g_quirc_code.corners[j].x+trace_roi_x);
                r->w[11+2*j]=(uint32_t)(g_quirc_code.corners[j].y+trace_roi_y);
            }
            for(j=0;j<3;j++)r->w[18+j]=(uint32_t)g_quirc.grids[trace_grid_index].caps[j];
            r->w[21]=(uint32_t)g_quirc.grids[trace_grid_index].align_region;
        }
    }
    if (g_decode_observer != 0) g_decode_observer((int)error, mirrored, rejected,
        g_quirc_data.payload, g_quirc_data.payload_len);
}

static int decode_current_grids(const qr_detector_config_t *config,
                                qr_pipeline_result_t *result,
                                qr_quirc_fallback_profile_t *profile,
                                int roi_x, int roi_y, int spatial_dedupe)
{
    int initial_count = (int)result->instance_count;
    int index;

    for (index = 0; index < g_quirc.num_grids &&
         result->instance_count < (uint16_t)config->max_instances &&
         result->instance_count < QR_MAX_INSTANCES; ++index) {
        qr_instance_t *instance;
        quirc_decode_error_t error;
        int mirrored = 0;
        uint64_t stage_started;

        memset(&g_quirc_code, 0, sizeof(g_quirc_code));
        memset(&g_quirc_data, 0, sizeof(g_quirc_data));
        stage_started=profile_ticks();
        quirc_extract(&g_quirc, index, &g_quirc_code);
        g_sample_us+=profile_elapsed_us(stage_started,profile_ticks());
        trace_grid_index=index;trace_roi_x=roi_x;trace_roi_y=roi_y;
#if QR_FAILURE_TRACE
        {
            unsigned size=(unsigned)g_quirc_code.size;
            unsigned total=size<=QUIRC_MAX_GRID_SIZE?(size*size+7U)/8U:0U,offset;
            for(offset=0;offset<total;offset+=92U){
                qr_trace_record_t *r=qr_trace_add(QRT_GRID_BITS);
                unsigned n=total-offset;if(n>92U)n=92U;
                if(!r)break;
                r->w[0]=qr_trace_roi_index();r->w[1]=(uint32_t)index;
                r->w[2]=offset;r->w[3]=total;r->w[4]=n;
                memcpy(&r->w[5],g_quirc_code.cell_bitmap+offset,n);
            }
        }
#endif
        stage_started=profile_ticks();
        error = quirc_decode(&g_quirc_code, &g_quirc_data);
        g_ecc_us+=profile_elapsed_us(stage_started,profile_ticks());
        record_attempt(error, 0, config, profile);
        if (error == QUIRC_ERROR_DATA_ECC) {
            quirc_flip(&g_quirc_code);
            stage_started=profile_ticks();
            error = quirc_decode(&g_quirc_code, &g_quirc_data);
            g_ecc_us+=profile_elapsed_us(stage_started,profile_ticks());
            record_attempt(error, 1, config, profile);
            mirrored = 1;
        }
        if (error != QUIRC_SUCCESS ||
            g_quirc_data.payload_len < config->minimum_payload_length ||
            g_quirc_data.payload_len >= QR_MAX_PAYLOAD)
            continue;
        if (spatial_dedupe ?
            symbol_already_present(result, g_quirc_data.payload,
                g_quirc_data.payload_len, &g_quirc_code, roi_x, roi_y) :
            payload_already_present(result, g_quirc_data.payload,
                                    g_quirc_data.payload_len))
            continue;

        instance = &result->instances[result->instance_count];
        memset(instance, 0, sizeof(*instance));
        instance->stage = QR_STAGE_OK;
        instance->module_count = g_quirc_code.size;
        instance->sample_threshold = -1;
        set_finder_points(instance, &g_quirc_code, roi_x, roi_y);
        for (int corner=0; corner<4; ++corner) {
            instance->outer_corners[2*corner] = (float)(roi_x+g_quirc_code.corners[corner].x);
            instance->outer_corners[2*corner+1] = (float)(roi_y+g_quirc_code.corners[corner].y);
        }
        instance->outer_corners_valid = 1;
        memcpy(instance->payload, g_quirc_data.payload,
               (size_t)g_quirc_data.payload_len);
        instance->payload[g_quirc_data.payload_len] = '\0';
        instance->decode_info.version = g_quirc_data.version;
        instance->decode_info.ecc_level = g_quirc_data.ecc_level;
        instance->decode_info.mask = g_quirc_data.mask;
        instance->decode_info.data_type = g_quirc_data.data_type;
        instance->decode_info.eci = g_quirc_data.eci;
        instance->decode_info.mirrored = mirrored;
        instance->decode_info.backend_error = (int)error;
        instance->decode_status = 0;
        ++result->instance_count;
        if (profile != 0) {
            ++profile->decoded_instances;
            if (mirrored)
                ++profile->mirrored_instances;
        }
    }
    return (int)result->instance_count - initial_count;
}

static int scan_roi(const qr_frame_view_t *frame,
                    const qr_detector_config_t *config,
                    qr_pipeline_result_t *result,
                    qr_quirc_fallback_profile_t *profile,
                    int x0, int y0, int width, int height,
                    int adaptive, int binary, int absolute_x,
                    int absolute_y, int spatial_dedupe)
{
    int grids;
    int decoded;
    uint64_t start, end;

    start = profile_ticks();
    copy_roi(frame, x0, y0, width, height);
    end = profile_ticks();
    if (profile != 0)
        profile->copy_us += profile_elapsed_us(start, end);
    memset(&g_quirc, 0, sizeof(g_quirc));
    g_quirc.image = g_quirc_image;
    g_quirc.pixels = (quirc_pixel_t *)g_quirc_image;
    g_quirc.w = width;
    g_quirc.h = height;
    g_quirc.flood_fill_vars = g_quirc_fill;
    g_quirc.num_flood_fill_vars = (size_t)height * 2U / 3U;
    if (g_quirc.num_flood_fill_vars == 0U)
        g_quirc.num_flood_fill_vars = 1U;

    start = profile_ticks();
#if QR_QUIRC_ENABLE_LOCAL_ADAPTIVE
    if (adaptive)
        adaptive_binarize(width, height);
#endif
    end = profile_ticks();
    if (profile != 0)
        profile->adaptive_us += profile_elapsed_us(start, end);
    start = profile_ticks();
    (void)quirc_begin(&g_quirc, 0, 0);
    if (binary) {
        if (qr_quirc_end_binary(&g_quirc) != 0)
            return -4;
    } else {
        quirc_end(&g_quirc);
    }
    end = profile_ticks();
    if (profile != 0)
        profile->identify_us += profile_elapsed_us(start, end);
    grids = g_quirc.num_grids;
    {
        qr_trace_record_t *r=qr_trace_add(QRT_IDENTIFY);int i,j;
        if(r){
            r->w[0]=qr_trace_roi_index();r->w[1]=(uint32_t)qr_quirc_last_otsu_threshold();
            r->w[2]=(uint32_t)width;r->w[3]=(uint32_t)height;
            r->w[4]=(uint32_t)g_quirc.num_regions;r->w[5]=(uint32_t)g_quirc.num_capstones;
            r->w[6]=(uint32_t)grids;
            r->w[7]=(g_quirc.num_regions>=QUIRC_MAX_REGIONS?1U:0U)|
                (g_quirc.num_capstones>=QUIRC_MAX_CAPSTONES?2U:0U)|
                (grids>=QUIRC_MAX_GRIDS?4U:0U);
            r->w[8]=(uint32_t)absolute_x;r->w[9]=(uint32_t)absolute_y;
            r->w[10]=profile?profile->identify_us:0U;
        }
        /* Record every quirc finder, even when no three can form a grid. */
        for(i=0;i<g_quirc.num_capstones;i++){
            const struct quirc_capstone *c=&g_quirc.capstones[i];
            r=qr_trace_add(QRT_CAPSTONE);if(!r)break;
            r->w[0]=qr_trace_roi_index();r->w[1]=(uint32_t)i;
            r->w[2]=(uint32_t)(c->center.x+absolute_x);
            r->w[3]=(uint32_t)(c->center.y+absolute_y);r->w[4]=(uint32_t)c->qr_grid;
            r->w[5]=(uint32_t)c->ring;r->w[6]=(uint32_t)c->stone;
            for(j=0;j<4;j++){
                r->w[7+2*j]=(uint32_t)(c->corners[j].x+absolute_x);
                r->w[8+2*j]=(uint32_t)(c->corners[j].y+absolute_y);
            }
            if(c->ring>=0&&c->ring<g_quirc.num_regions)r->w[15]=(uint32_t)g_quirc.regions[c->ring].count;
            if(c->stone>=0&&c->stone<g_quirc.num_regions)r->w[16]=(uint32_t)g_quirc.regions[c->stone].count;
        }
    }
    if (profile != 0) {
        ++profile->identify_calls;
        if (!grids) ++profile->no_grid_scans;
        profile->regions_seen += (uint32_t)g_quirc.num_regions;
        profile->capstones_seen += (uint32_t)g_quirc.num_capstones;
        if (g_quirc.num_regions > profile->max_regions)
            profile->max_regions = (uint16_t)g_quirc.num_regions;
        if (g_quirc.num_capstones > profile->max_capstones)
            profile->max_capstones = (uint16_t)g_quirc.num_capstones;
        if (adaptive) {
            profile->adaptive_retry = 1U;
            profile->adaptive_grids_found = (uint16_t)
                (profile->adaptive_grids_found + grids);
        } else {
            profile->grids_found = (uint16_t)
                (profile->grids_found + grids);
        }
    }
    start = profile_ticks();
    decoded = decode_current_grids(config, result, profile,
                                   absolute_x, absolute_y, spatial_dedupe);
    end = profile_ticks();
    if (profile != 0)
        profile->decode_us += profile_elapsed_us(start, end);
    return decoded;
}

int qr_quirc_fallback_run(const qr_frame_view_t *frame,
                          const qr_candidate_t *horizontal,
                          int horizontal_count,
                          const qr_detector_config_t *config,
                          qr_pipeline_result_t *result,
                          qr_quirc_fallback_profile_t *profile)
{
    int x0, y0, x1, y1;
    int width, height;
    int initial_count;
    int decoded;

    if (profile != 0)
        memset(profile, 0, sizeof(*profile));
    if (frame == 0 || config == 0 || result == 0 || frame->data == 0 ||
        frame->pixel_format != QR_PIXEL_FORMAT_GRAY8 || frame->width <= 0 ||
        frame->height <= 0 || frame->stride < frame->width ||
        horizontal_count < 0 ||
        (horizontal_count > 0 && horizontal == 0))
        return -1;
    if (frame->width > QR_QUIRC_MAX_WIDTH || frame->height > QR_QUIRC_MAX_HEIGHT)
        return -2;

    choose_roi(frame, horizontal, horizontal_count, &x0, &y0, &x1, &y1);
    width = x1 - x0;
    height = y1 - y0;
    if (width <= 0 || height <= 0 || width > QR_QUIRC_MAX_WIDTH ||
        height > QR_QUIRC_MAX_HEIGHT)
        return -3;

    if (profile != 0) {
        profile->roi_x = (uint16_t)x0;
        profile->roi_y = (uint16_t)y0;
        profile->roi_width = (uint16_t)width;
        profile->roi_height = (uint16_t)height;
    }

    initial_count = (int)result->instance_count;
    decoded = scan_roi(frame, config, result, profile,
                       x0, y0, width, height, 0, 0, x0, y0, 0);
#if QR_QUIRC_ENABLE_LOCAL_ADAPTIVE
    /* Candidate-directed ROIs are small, so retry them adaptively at once.
     * A blind full-frame adaptive pass is substantially more expensive; run
     * it once per four misses while retaining a full-frame Otsu scan on every
     * captured image. */
    if (decoded == 0 &&
        (horizontal_count > 0 || ((g_adaptive_phase++ & 3U) == 0U))) {
        decoded += scan_roi(frame, config, result, profile,
                            x0, y0, width, height, 1, 0, x0, y0, 0);
    }
#else
    (void)decoded;
#endif

    if ((int)result->instance_count > initial_count) {
        result->stage = QR_STAGE_OK;
        publish_legacy_first(result);
    }
    return (int)result->instance_count - initial_count;
}

static int explicit_roi_run(const qr_frame_view_t *private_roi,
                            uint16_t absolute_x, uint16_t absolute_y,
                            qr_pipeline_result_t *result,
                            qr_quirc_fallback_profile_t *profile, int binary)
{
    qr_detector_config_t config;
    int decoded;
    g_sample_us=g_ecc_us=g_attempt_flags=0;
    memset(g_attempt_errors,0,sizeof(g_attempt_errors));
    if (profile != 0)
        memset(profile, 0, sizeof(*profile));
    if (private_roi == 0 || result == 0 || private_roi->data == 0 ||
        private_roi->pixel_format != QR_PIXEL_FORMAT_GRAY8 ||
        private_roi->width <= 0 || private_roi->height <= 0 ||
        private_roi->stride < private_roi->width ||
        result->instance_count > QR_MAX_INSTANCES)
        return -1;
    if (private_roi->width > QR_QUIRC_MAX_WIDTH ||
        private_roi->height > QR_QUIRC_MAX_HEIGHT ||
        (uint32_t)absolute_x + (uint32_t)private_roi->width > 65535U ||
        (uint32_t)absolute_y + (uint32_t)private_roi->height > 65535U)
        return -2;
    if (profile != 0) {
        profile->roi_x = absolute_x;
        profile->roi_y = absolute_y;
        profile->roi_width = (uint16_t)private_roi->width;
        profile->roi_height = (uint16_t)private_roi->height;
    }
    qr_detector_config_default(&config);
    decoded = scan_roi(private_roi, &config, result, profile, 0, 0,
                       private_roi->width, private_roi->height,
                       0, binary, absolute_x, absolute_y, 1);
    if (decoded > 0) {
        result->stage = QR_STAGE_OK;
        publish_legacy_first(result);
    }
    return decoded;
}

int qr_quirc_binary_roi_run(const qr_frame_view_t *private_roi,
                           uint16_t absolute_x, uint16_t absolute_y,
                           qr_pipeline_result_t *result,
                           qr_quirc_fallback_profile_t *profile)
{
    return explicit_roi_run(private_roi, absolute_x, absolute_y,
                            result, profile, 1);
}

int qr_quirc_gray_roi_run(const qr_frame_view_t *private_roi,
                         uint16_t absolute_x, uint16_t absolute_y,
                         qr_pipeline_result_t *result,
                         qr_quirc_fallback_profile_t *profile)
{
    return explicit_roi_run(private_roi, absolute_x, absolute_y,
                            result, profile, 0);
}
