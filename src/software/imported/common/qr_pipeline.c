#include "qr_pipeline.h"

#include <string.h>

#define QR_MAX_SCAN_RUNS 2048

typedef struct {
    float tl_x, tl_y;
    float tr_x, tr_y;
    float bl_x, bl_y;
    float score;
    uint8_t tl_index, tr_index, bl_index;
} qr_triple_t;

static qr_candidate_t g_vertical[QR_MAX_CANDIDATES];
static qr_center_t g_centers[QR_MAX_CENTERS];
static uint8_t g_vertical_hit[QR_MAX_CANDIDATES];
static uint8_t g_cluster_index[QR_MAX_CANDIDATES];
static float g_module_work[QR_MAX_CANDIDATES];
static int g_run_starts[QR_MAX_SCAN_RUNS];
static int g_run_lengths[QR_MAX_SCAN_RUNS];
static uint8_t g_run_colors[QR_MAX_SCAN_RUNS];
static qr_triple_t g_hypotheses[QR_MAX_HYPOTHESES];

static float qr_absf(float value) { return value < 0.0f ? -value : value; }
static float qr_minf(float a, float b) { return a < b ? a : b; }
static float qr_maxf(float a, float b) { return a > b ? a : b; }

static float qr_sqrtf(float value)
{
    float estimate;
    int i;
    if (value <= 0.0f)
        return 0.0f;
    estimate = value > 1.0f ? value : 1.0f;
    for (i = 0; i < 10; ++i)
        estimate = 0.5f * (estimate + value / estimate);
    return estimate;
}

void qr_detector_config_default(qr_detector_config_t *config)
{
    if (config == 0)
        return;
    memset(config, 0, sizeof(*config));
    config->threshold = 128;
    config->module_count = QR_V1_MODULE_COUNT;
    config->max_instances = QR_MAX_INSTANCES;
    config->max_triple_centers = 48;
    config->enable_roi_otsu = 0;
    config->minimum_payload_length = 1;
    config->max_finder_mismatches = 24;
    config->max_timing_mismatches = 8;
    config->local_vertical_half_modules = 16.0f;
    config->local_vertical_margin_pixels = 8;
}

static int pattern_metrics(const int run[5], float *module_size, int *error)
{
    int total = run[0] + run[1] + run[2] + run[3] + run[4];
    int module = total / 7;
    int e;
    if (module <= 0 || run[0] <= 0 || run[1] <= 0 || run[2] <= 0 ||
        run[3] <= 0 || run[4] <= 0)
        return 0;
    e = (run[0] > module ? run[0] - module : module - run[0]) +
        (run[1] > module ? run[1] - module : module - run[1]) +
        (run[2] > 3 * module ? run[2] - 3 * module : 3 * module - run[2]) +
        (run[3] > module ? run[3] - module : module - run[3]) +
        (run[4] > module ? run[4] - module : module - run[4]);
    *module_size = (float)total / 7.0f;
    *error = e;
    return e * 4 <= total * 2;
}

static int vertical_cross_check(const qr_frame_view_t *frame,
                                const qr_candidate_t *input, int input_count,
                                const qr_detector_config_t *config,
                                int use_local_window, int accepted,
                                int only_unaccepted,
                                qr_pipeline_profile_t *profile)
{
    int i;
    for (i = 0; i < input_count && accepted < QR_MAX_CANDIDATES; ++i) {
        int x;
        int y;
        int run_count = 0;
        int start;
        int color;
        int row;
        int run_index = -1;
        int center_run;
        int half_span;
        int window_start;
        int window_end;
        if (only_unaccepted && g_vertical_hit[i])
            continue;
        x = (int)(input[i].x + 0.5f);
        y = (int)(input[i].y + 0.5f);
        if (x < 0 || x >= frame->width || y < 0 || y >= frame->height ||
            frame->height > QR_MAX_SCAN_RUNS)
            continue;
        if (use_local_window) {
            half_span = (int)(config->local_vertical_half_modules *
                              qr_maxf(input[i].module_size, 1.0f) +
                              (float)config->local_vertical_margin_pixels + 0.5f);
            if (half_span > frame->height)
                half_span = frame->height;
            window_start = y > half_span ? y - half_span : 0;
            window_end = y + half_span + 1;
            if (window_end > frame->height)
                window_end = frame->height;
        } else {
            window_start = 0;
            window_end = frame->height;
            if (profile != 0)
                ++profile->vertical_candidates_rechecked;
        }
        if (profile != 0)
            profile->vertical_pixels_examined += (uint32_t)(window_end - window_start);
        start = window_start;
        color = frame->data[window_start * frame->stride + x] < config->threshold;
        for (row = window_start + 1; row <= window_end; ++row) {
            int next_color = row < window_end ?
                frame->data[row * frame->stride + x] < config->threshold : !color;
            if (row < window_end && next_color == color)
                continue;
            if (run_count >= QR_MAX_SCAN_RUNS)
                break;
            g_run_starts[run_count] = start;
            g_run_lengths[run_count] = row - start;
            g_run_colors[run_count] = (uint8_t)color;
            if (y >= start && y < row)
                run_index = run_count;
            ++run_count;
            start = row;
            color = next_color;
        }
        if (run_index < 0)
            continue;
        for (center_run = run_index - 1; center_run <= run_index + 1; ++center_run) {
            int run[5];
            int first = center_run - 2;
            int total;
            int center_y;
            int error;
            float module;
            float largest;
            float relative;
            if (center_run < 2 || center_run >= run_count - 2)
                continue;
            if (!g_run_colors[first] || g_run_colors[first + 1] ||
                !g_run_colors[first + 2] || g_run_colors[first + 3] ||
                !g_run_colors[first + 4])
                continue;
            memcpy(run, &g_run_lengths[first], sizeof(run));
            if (!pattern_metrics(run, &module, &error))
                continue;
            total = run[0] + run[1] + run[2] + run[3] + run[4];
            center_y = g_run_starts[first + 4] + g_run_lengths[first + 4] - total / 2;
            if (qr_absf((float)center_y - input[i].y) >
                1.25f * qr_maxf(module, 1.0f))
                continue;
            largest = qr_maxf(module, input[i].module_size);
            relative = qr_absf(module - input[i].module_size) / qr_maxf(largest, 1.0f);
            if (relative > 0.65f)
                continue;
            g_vertical[accepted].x = input[i].x;
            g_vertical[accepted].y = (float)center_y;
            g_vertical[accepted].module_size = 0.5f * (module + input[i].module_size);
            g_vertical[accepted].score = input[i].score + (65535.0f - (float)error);
            g_vertical_hit[i] = 1U;
            ++accepted;
            break;
        }
    }
    return accepted;
}

static int cluster_candidates(const qr_candidate_t *input, int count)
{
    int center_count = 0;
    int i;
    memset(g_centers, 0, sizeof(g_centers));
    for (i = 0; i < count; ++i) {
        int selected = -1;
        int c;
        for (c = 0; c < center_count; ++c) {
            float dx = input[i].x - g_centers[c].x;
            float dy = input[i].y - g_centers[c].y;
            float radius = qr_maxf(2.0f, 2.25f * qr_maxf(input[i].module_size,
                                                         g_centers[c].module_size));
            if (dx * dx + dy * dy <= radius * radius &&
                qr_absf(input[i].module_size - g_centers[c].module_size) <=
                    0.75f * qr_maxf(input[i].module_size, g_centers[c].module_size)) {
                selected = c;
                break;
            }
        }
        if (selected < 0) {
            if (center_count >= QR_MAX_CENTERS)
                continue;
            selected = center_count++;
            g_centers[selected].x = input[i].x;
            g_centers[selected].y = input[i].y;
            g_centers[selected].module_size = input[i].module_size;
            g_centers[selected].score = input[i].score;
            g_centers[selected].hits = 1;
        } else {
            qr_center_t *center = &g_centers[selected];
            float old_weight = center->score;
            float weight = qr_maxf(input[i].score, 1.0f);
            float total_weight = old_weight + weight;
            center->x = (center->x * old_weight + input[i].x * weight) / total_weight;
            center->y = (center->y * old_weight + input[i].y * weight) / total_weight;
            center->module_size = (center->module_size * center->hits + input[i].module_size) /
                                  (float)(center->hits + 1U);
            center->score = total_weight;
            ++center->hits;
        }
        g_cluster_index[i] = (uint8_t)selected;
    }
    for (i = 0; i < center_count; ++i) {
        int module_count = 0;
        int j;
        for (j = 0; j < count; ++j) {
            if (g_cluster_index[j] == (uint8_t)i) {
                int pos = module_count;
                while (pos > 0 && g_module_work[pos - 1] > input[j].module_size) {
                    g_module_work[pos] = g_module_work[pos - 1];
                    --pos;
                }
                g_module_work[pos] = input[j].module_size;
                ++module_count;
            }
        }
        if ((module_count & 1) != 0)
            g_centers[i].module_size = g_module_work[module_count / 2];
        else
            g_centers[i].module_size = 0.5f * (g_module_work[module_count / 2 - 1] +
                                               g_module_work[module_count / 2]);
    }
    for (i = 0; i < center_count; ++i) {
        int j;
        for (j = i + 1; j < center_count; ++j) {
            if (g_centers[j].hits > g_centers[i].hits ||
                (g_centers[j].hits == g_centers[i].hits &&
                 g_centers[j].score > g_centers[i].score)) {
                qr_center_t temp = g_centers[i];
                g_centers[i] = g_centers[j];
                g_centers[j] = temp;
            }
        }
    }
    return center_count;
}

static void sort_vertical_by_score(int count)
{
    int i;
    for (i = 1; i < count; ++i) {
        qr_candidate_t value = g_vertical[i];
        int j = i;
        while (j > 0 && g_vertical[j - 1].score < value.score) {
            g_vertical[j] = g_vertical[j - 1];
            --j;
        }
        g_vertical[j] = value;
    }
}

static void keep_hypothesis(const qr_triple_t *triple, int *count)
{
    int pos = *count;
    if (pos >= QR_MAX_HYPOTHESES) {
        if (triple->score <= g_hypotheses[QR_MAX_HYPOTHESES - 1].score)
            return;
        pos = QR_MAX_HYPOTHESES - 1;
    } else {
        ++*count;
    }
    while (pos > 0 && g_hypotheses[pos - 1].score < triple->score) {
        if (pos < QR_MAX_HYPOTHESES)
            g_hypotheses[pos] = g_hypotheses[pos - 1];
        --pos;
    }
    g_hypotheses[pos] = *triple;
}

static int collect_hypotheses(int center_count, int center_limit,
                              qr_pipeline_profile_t *profile)
{
    int count = 0;
    int limit = center_count < center_limit ? center_count : center_limit;
    int i, j, k, right;
    for (i = 0; i < limit - 2; ++i) for (j = i + 1; j < limit - 1; ++j)
    for (k = j + 1; k < limit; ++k) {
        int idx[3] = {i, j, k};
        if (profile != 0)
            ++profile->triple_combinations;
        for (right = 0; right < 3; ++right) {
            int a_index = idx[(right + 1) % 3];
            int b_index = idx[(right + 2) % 3];
            qr_center_t *tl = &g_centers[idx[right]];
            qr_center_t *a_center = &g_centers[a_index];
            qr_center_t *b_center = &g_centers[b_index];
            float ax = a_center->x - tl->x, ay = a_center->y - tl->y;
            float bx = b_center->x - tl->x, by = b_center->y - tl->y;
            float la = qr_sqrtf(ax * ax + ay * ay);
            float lb = qr_sqrtf(bx * bx + by * by);
            float cosine, leg_ratio, module_ratio, mean_module, expected;
            float distance_error, score;
            qr_center_t *tr;
            qr_center_t *bl;
            int tr_index;
            int bl_index;
            qr_triple_t triple;
            if (profile != 0)
                ++profile->triple_right_angle_tests;
            if (qr_minf(la, lb) < 8.0f)
                continue;
            cosine = qr_absf(ax * bx + ay * by) / qr_maxf(la * lb, 1.0f);
            leg_ratio = qr_minf(la, lb) / qr_maxf(la, lb);
            module_ratio = qr_minf(tl->module_size,
                              qr_minf(a_center->module_size, b_center->module_size)) /
                           qr_maxf(tl->module_size,
                              qr_maxf(a_center->module_size, b_center->module_size));
            if (cosine > 0.25f || leg_ratio < 0.75f || module_ratio < 0.70f)
                continue;
            mean_module = (tl->module_size + a_center->module_size + b_center->module_size) / 3.0f;
            expected = 22.0f * mean_module;
            if (qr_absf(la - expected) > 0.30f * expected ||
                qr_absf(lb - expected) > 0.30f * expected)
                continue;
            if (profile != 0)
                ++profile->triple_geometry_passes;
            if (ax * by - ay * bx > 0.0f) {
                tr = a_center; bl = b_center;
                tr_index = a_index; bl_index = b_index;
            } else {
                tr = b_center; bl = a_center;
                tr_index = b_index; bl_index = a_index;
            }
            distance_error = (qr_absf(la - expected) + qr_absf(lb - expected)) /
                             qr_maxf(2.0f * expected, 1.0f);
            score = -cosine * 1000000.0f - (1.0f - leg_ratio) * 500000.0f -
                    (1.0f - module_ratio) * 500000.0f - distance_error * 500000.0f +
                    (float)(tl->hits + tr->hits + bl->hits) * 100.0f;
            triple.tl_x = tl->x; triple.tl_y = tl->y;
            triple.tr_x = tr->x; triple.tr_y = tr->y;
            triple.bl_x = bl->x; triple.bl_y = bl->y;
            triple.score = score;
            triple.tl_index = (uint8_t)idx[right];
            triple.tr_index = (uint8_t)tr_index;
            triple.bl_index = (uint8_t)bl_index;
            keep_hypothesis(&triple, &count);
        }
    }
    if (profile != 0)
        profile->hypotheses_kept = (uint32_t)count;
    return count;
}

int qr_pipeline_find_triples_profiled(const qr_frame_view_t *frame,
                             const qr_detector_config_t *config,
                             const qr_candidate_t *horizontal,
                             int horizontal_count,
                             qr_finder_triple_t *triples,
                             int triple_capacity, qr_locator_profile_t *profile)
{
    int vertical_count;
    int center_count;
    int hypothesis_count;
    int output_count;
    int i;

    if (profile) {memset(profile,0,sizeof(*profile));profile->stage=QR_STAGE_ARGUMENT;}
    if (frame == 0 || config == 0 || horizontal == 0 || triples == 0 ||
        horizontal_count <= 0 || horizontal_count > QR_MAX_CANDIDATES ||
        triple_capacity <= 0 || frame->data == 0 ||
        frame->pixel_format != QR_PIXEL_FORMAT_GRAY8)
        return 0;

    memset(g_vertical_hit, 0, (size_t)horizontal_count);
    vertical_count = vertical_cross_check(frame, horizontal, horizontal_count,
                                          config, 1, 0, 0, 0);
    if (vertical_count > 0 && vertical_count < 3)
        vertical_count = vertical_cross_check(frame, horizontal,
                                              horizontal_count, config, 0,
                                              vertical_count, 1, 0);
    if (profile) {profile->vertical_count=vertical_count;profile->stage=QR_STAGE_VERTICAL;}
    if (vertical_count < 3)
        return 0;
    sort_vertical_by_score(vertical_count);
    center_count = cluster_candidates(g_vertical, vertical_count);
    if (profile) {profile->center_count=center_count;profile->stage=QR_STAGE_CLUSTER;}
    if (center_count < 3)
        return 0;
    hypothesis_count = collect_hypotheses(center_count,
                                          config->max_triple_centers, 0);
    if (profile) {profile->triple_count=hypothesis_count;profile->stage=hypothesis_count?QR_STAGE_OK:QR_STAGE_TRIPLE;}
    output_count = hypothesis_count < triple_capacity ? hypothesis_count :
                                                        triple_capacity;
    for (i = 0; i < output_count; ++i) {
        triples[i].finder[0].x = g_hypotheses[i].tl_x;
        triples[i].finder[0].y = g_hypotheses[i].tl_y;
        triples[i].finder[1].x = g_hypotheses[i].tr_x;
        triples[i].finder[1].y = g_hypotheses[i].tr_y;
        triples[i].finder[2].x = g_hypotheses[i].bl_x;
        triples[i].finder[2].y = g_hypotheses[i].bl_y;
        triples[i].finder[0].module_size =
            g_centers[g_hypotheses[i].tl_index].module_size;
        triples[i].finder[1].module_size =
            g_centers[g_hypotheses[i].tr_index].module_size;
        triples[i].finder[2].module_size =
            g_centers[g_hypotheses[i].bl_index].module_size;
        triples[i].finder[0].score = g_hypotheses[i].score;
        triples[i].finder[1].score = g_hypotheses[i].score;
        triples[i].finder[2].score = g_hypotheses[i].score;
        triples[i].score = g_hypotheses[i].score;
    }
    return output_count;
}

int qr_pipeline_find_triples(const qr_frame_view_t *frame,
 const qr_detector_config_t *config, const qr_candidate_t *horizontal,
 int horizontal_count, qr_finder_triple_t *triples, int triple_capacity) {
 return qr_pipeline_find_triples_profiled(frame,config,horizontal,horizontal_count,
                                         triples,triple_capacity,0);
}

static int sample_modules(const qr_frame_view_t *frame, int threshold,
                          const qr_triple_t *triple, int module_count,
                          uint8_t *modules)
{
    float x_step_x = (triple->tr_x - triple->tl_x) / 22.0f;
    float x_step_y = (triple->tr_y - triple->tl_y) / 22.0f;
    float y_step_x = (triple->bl_x - triple->tl_x) / 22.0f;
    float y_step_y = (triple->bl_y - triple->tl_y) / 22.0f;
    int row, col;
    for (row = 0; row < module_count; ++row) {
        for (col = 0; col < module_count; ++col) {
            float fx = triple->tl_x + ((float)col - 3.0f) * x_step_x +
                       ((float)row - 3.0f) * y_step_x;
            float fy = triple->tl_y + ((float)col - 3.0f) * x_step_y +
                       ((float)row - 3.0f) * y_step_y;
            int x = (int)(fx + (fx >= 0.0f ? 0.5f : -0.5f));
            int y = (int)(fy + (fy >= 0.0f ? 0.5f : -0.5f));
            if (x < 0 || x >= frame->width || y < 0 || y >= frame->height)
                return -1;
            modules[row * module_count + col] =
                frame->data[y * frame->stride + x] < threshold ? 1U : 0U;
        }
    }
    return 0;
}

static int finder_expected_dark(int row, int col)
{
    return row == 0 || row == 6 || col == 0 || col == 6 ||
           (row >= 2 && row <= 4 && col >= 2 && col <= 4);
}

/* Standards-derived, low-cost guard before the full ECC decoder. It checks
 * only fixed QR structures and deliberately allows sampling errors. */
static int validate_sampled_structure(const uint8_t *modules, int size,
                                      const qr_detector_config_t *config)
{
    const int origins[3][2] = {{0, 0}, {0, QR_V1_MODULE_COUNT - 7},
                               {QR_V1_MODULE_COUNT - 7, 0}};
    int finder_mismatches = 0;
    int timing_mismatches = 0;
    int finder;
    int row;
    int col;
    if (size != QR_V1_MODULE_COUNT)
        return 0;
    for (finder = 0; finder < 3; ++finder) {
        for (row = 0; row < 7; ++row) {
            for (col = 0; col < 7; ++col) {
                int actual = modules[(origins[finder][0] + row) * size +
                                     origins[finder][1] + col] != 0U;
                if (actual != finder_expected_dark(row, col))
                    ++finder_mismatches;
            }
        }
    }
    for (col = 8; col <= size - 9; ++col) {
        if ((modules[6 * size + col] != 0U) != ((col & 1) == 0))
            ++timing_mismatches;
    }
    for (row = 8; row <= size - 9; ++row) {
        if ((modules[row * size + 6] != 0U) != ((row & 1) == 0))
            ++timing_mismatches;
    }
    return finder_mismatches <= config->max_finder_mismatches &&
           timing_mismatches <= config->max_timing_mismatches;
}

static int roi_otsu_threshold(const qr_frame_view_t *frame,
                              const qr_triple_t *triple,
                              qr_pipeline_profile_t *profile)
{
    uint32_t histogram[256];
    float x_step_x = (triple->tr_x - triple->tl_x) / 22.0f;
    float x_step_y = (triple->tr_y - triple->tl_y) / 22.0f;
    float y_step_x = (triple->bl_x - triple->tl_x) / 22.0f;
    float y_step_y = (triple->bl_y - triple->tl_y) / 22.0f;
    float origin_x = triple->tl_x - 3.5f * x_step_x - 3.5f * y_step_x;
    float origin_y = triple->tl_y - 3.5f * x_step_y - 3.5f * y_step_y;
    float corner_x[4];
    float corner_y[4];
    float min_x, max_x, min_y, max_y;
    uint64_t total_sum = 0U;
    uint64_t background_sum = 0U;
    uint32_t total = 0U;
    uint32_t background_weight = 0U;
    double best_variance = -1.0;
    int best_threshold = 128;
    int x0, x1, y0, y1;
    int x, y, level;
    memset(histogram, 0, sizeof(histogram));
    corner_x[0] = origin_x;
    corner_y[0] = origin_y;
    corner_x[1] = origin_x + 29.0f * x_step_x;
    corner_y[1] = origin_y + 29.0f * x_step_y;
    corner_x[2] = origin_x + 29.0f * y_step_x;
    corner_y[2] = origin_y + 29.0f * y_step_y;
    corner_x[3] = corner_x[1] + 29.0f * y_step_x;
    corner_y[3] = corner_y[1] + 29.0f * y_step_y;
    min_x = max_x = corner_x[0];
    min_y = max_y = corner_y[0];
    for (level = 1; level < 4; ++level) {
        min_x = qr_minf(min_x, corner_x[level]);
        max_x = qr_maxf(max_x, corner_x[level]);
        min_y = qr_minf(min_y, corner_y[level]);
        max_y = qr_maxf(max_y, corner_y[level]);
    }
    x0 = (int)min_x; y0 = (int)min_y;
    x1 = (int)(max_x + 1.0f); y1 = (int)(max_y + 1.0f);
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 >= frame->width) x1 = frame->width - 1;
    if (y1 >= frame->height) y1 = frame->height - 1;
    if (x0 > x1 || y0 > y1)
        return 128;
    for (y = y0; y <= y1; ++y) {
        const uint8_t *row = frame->data + y * frame->stride;
        for (x = x0; x <= x1; ++x)
            ++histogram[row[x]];
    }
    total = (uint32_t)((x1 - x0 + 1) * (y1 - y0 + 1));
    if (profile != 0)
        profile->otsu_pixels_examined += total;
    for (level = 0; level < 256; ++level)
        total_sum += (uint64_t)level * histogram[level];
    for (level = 0; level < 256; ++level) {
        uint32_t foreground_weight;
        double mean_delta;
        double variance;
        background_weight += histogram[level];
        if (background_weight == 0U)
            continue;
        foreground_weight = total - background_weight;
        if (foreground_weight == 0U)
            break;
        background_sum += (uint64_t)level * histogram[level];
        mean_delta = (double)background_sum / (double)background_weight -
                     (double)(total_sum - background_sum) / (double)foreground_weight;
        variance = (double)background_weight * (double)foreground_weight *
                   mean_delta * mean_delta;
        if (variance > best_variance) {
            best_variance = variance;
            best_threshold = level + 1;
        }
    }
    return best_threshold;
}

static int same_symbol(const qr_instance_t *instance, const qr_triple_t *triple)
{
    float dx = instance->finder_tl_x - triple->tl_x;
    float dy = instance->finder_tl_y - triple->tl_y;
    float leg_x = triple->tr_x - triple->tl_x;
    float leg_y = triple->tr_y - triple->tl_y;
    float radius2 = (leg_x * leg_x + leg_y * leg_y) * 0.04f;
    return dx * dx + dy * dy <= qr_maxf(radius2, 16.0f);
}

static void publish_legacy_first(qr_pipeline_result_t *result)
{
    const qr_instance_t *first;
    if (result->instance_count == 0U)
        return;
    first = &result->instances[0];
    result->finder_tl_x = first->finder_tl_x;
    result->finder_tl_y = first->finder_tl_y;
    result->finder_tr_x = first->finder_tr_x;
    result->finder_tr_y = first->finder_tr_y;
    result->finder_bl_x = first->finder_bl_x;
    result->finder_bl_y = first->finder_bl_y;
    memcpy(result->modules, first->modules, sizeof(result->modules));
    memcpy(result->payload, first->payload, sizeof(result->payload));
    result->decode_info = first->decode_info;
    result->decode_status = first->decode_status;
}

int qr_pipeline_run_v1_2(const qr_frame_view_t *frame,
                         const qr_detector_config_t *config,
                         const qr_candidate_t *horizontal, int horizontal_count,
                         qr_pipeline_result_t *result,
                         qr_pipeline_profile_t *profile,
                         qr_profile_clock_fn clock_fn, void *clock_context)
{
    int vertical_count;
    int center_count;
    int hypothesis_count;
    int sampled_count = 0;
    int h;
    uint64_t stage_start = 0U;
    uint64_t tick_start;
    uint64_t tick_end;
    if (result != 0)
        memset(result, 0, sizeof(*result));
    if (profile != 0)
        memset(profile, 0, sizeof(*profile));
    if (frame == 0 || config == 0 || horizontal == 0 || result == 0 ||
        frame->data == 0 || frame->width <= 0 || frame->height <= 0 ||
        frame->stride < frame->width || frame->height > QR_MAX_SCAN_RUNS ||
        frame->pixel_format != QR_PIXEL_FORMAT_GRAY8 || horizontal_count <= 0 ||
        horizontal_count > QR_MAX_CANDIDATES || config->module_count != QR_V1_MODULE_COUNT ||
        config->max_instances <= 0 || config->max_triple_centers < 3) {
        if (result != 0)
            result->stage = QR_STAGE_ARGUMENT;
        return -1;
    }
    memset(g_vertical_hit, 0, (size_t)horizontal_count);
    if (profile != 0 && clock_fn != 0)
        stage_start = clock_fn(clock_context);
    vertical_count = vertical_cross_check(frame, horizontal, horizontal_count, config,
                                          1, 0, 0, profile);
    /* Only a near-complete local result justifies the expensive fallback.
     * Recheck rejected horizontal candidates only, then continue the same
     * pipeline instead of restarting every PS stage. */
    if (vertical_count > 0 && vertical_count < 3) {
        vertical_count = vertical_cross_check(frame, horizontal, horizontal_count, config,
                                              0, vertical_count, 1, profile);
        if (profile != 0)
            profile->fallback_used = 1U;
    }
    if (profile != 0 && clock_fn != 0) {
        tick_end = clock_fn(clock_context);
        profile->vertical_ticks = tick_end - stage_start;
        stage_start = tick_end;
    }
    result->vertical_count = (uint16_t)vertical_count;
    if (vertical_count < 3) {
        result->stage = QR_STAGE_VERTICAL;
        return -1;
    }
    sort_vertical_by_score(vertical_count);
    if (profile != 0 && clock_fn != 0) {
        tick_end = clock_fn(clock_context);
        profile->sort_ticks = tick_end - stage_start;
        stage_start = tick_end;
    }
    center_count = cluster_candidates(g_vertical, vertical_count);
    if (profile != 0 && clock_fn != 0) {
        tick_end = clock_fn(clock_context);
        profile->cluster_ticks = tick_end - stage_start;
        stage_start = tick_end;
    }
    result->center_count = (uint16_t)center_count;
    if (center_count < 3) {
        result->stage = QR_STAGE_CLUSTER;
        return -1;
    }
    hypothesis_count = collect_hypotheses(center_count, config->max_triple_centers, profile);
    if (profile != 0 && clock_fn != 0) {
        tick_end = clock_fn(clock_context);
        profile->triple_ticks = tick_end - stage_start;
    }
    if (hypothesis_count == 0) {
        result->stage = QR_STAGE_TRIPLE;
        return -1;
    }
    for (h = 0; h < hypothesis_count &&
         result->instance_count < (uint16_t)config->max_instances &&
         result->instance_count < QR_MAX_INSTANCES; ++h) {
        qr_triple_t *triple = &g_hypotheses[h];
        qr_instance_t candidate;
        int threshold = config->threshold;
        int duplicate = 0;
        int i;
        memset(&candidate, 0, sizeof(candidate));
        for (i = 0; i < (int)result->instance_count; ++i) {
            if (same_symbol(&result->instances[i], triple)) {
                duplicate = 1;
                break;
            }
        }
        if (duplicate)
            continue;
        candidate.stage = QR_STAGE_SAMPLE;
        candidate.finder_tl_x = triple->tl_x; candidate.finder_tl_y = triple->tl_y;
        candidate.finder_tr_x = triple->tr_x; candidate.finder_tr_y = triple->tr_y;
        candidate.finder_bl_x = triple->bl_x; candidate.finder_bl_y = triple->bl_y;
        candidate.geometry_score = triple->score;
        candidate.module_count = config->module_count;
        if (config->enable_roi_otsu) {
            tick_start = clock_fn != 0 ? clock_fn(clock_context) : 0U;
            threshold = roi_otsu_threshold(frame, triple, profile);
            if (profile != 0 && clock_fn != 0) {
                tick_end = clock_fn(clock_context);
                profile->otsu_ticks += tick_end - tick_start;
            }
        }
        candidate.sample_threshold = threshold;
        tick_start = clock_fn != 0 ? clock_fn(clock_context) : 0U;
        if (sample_modules(frame, threshold, triple, config->module_count,
                           candidate.modules) != 0) {
            if (profile != 0 && clock_fn != 0) {
                tick_end = clock_fn(clock_context);
                profile->sample_ticks += tick_end - tick_start;
            }
            continue;
        }
        ++sampled_count;
        if (profile != 0 && clock_fn != 0) {
            tick_end = clock_fn(clock_context);
            profile->sample_ticks += tick_end - tick_start;
        }
        if (!validate_sampled_structure(candidate.modules, config->module_count, config)) {
            if (profile != 0)
                ++profile->structure_rejects;
            continue;
        }
        tick_start = clock_fn != 0 ? clock_fn(clock_context) : 0U;
        candidate.decode_status = qr_decode_modules(candidate.modules,
                                                     config->module_count,
                                                     candidate.payload,
                                                     sizeof(candidate.payload),
                                                     &candidate.decode_info);
        if (profile != 0)
            ++profile->decode_attempts;
        if (profile != 0 && clock_fn != 0) {
            tick_end = clock_fn(clock_context);
            profile->decode_ticks += tick_end - tick_start;
        }
        if (candidate.decode_status != 0)
            continue;
        if ((int)strlen(candidate.payload) < config->minimum_payload_length)
            continue;
        candidate.stage = QR_STAGE_OK;
        result->instances[result->instance_count++] = candidate;
    }
    if (profile != 0)
        profile->instances_found = result->instance_count;
    if (result->instance_count == 0U) {
        result->stage = sampled_count == 0 ? QR_STAGE_SAMPLE : QR_STAGE_DECODE;
        return -1;
    }
    result->stage = QR_STAGE_OK;
    publish_legacy_first(result);
    return 0;
}

int qr_pipeline_run_profiled(const uint8_t *gray, int width, int height, int threshold,
                             const qr_candidate_t *horizontal, int horizontal_count,
                             qr_pipeline_result_t *result,
                             qr_pipeline_profile_t *profile,
                             qr_profile_clock_fn clock_fn, void *clock_context)
{
    qr_frame_view_t frame;
    qr_detector_config_t config;
    qr_detector_config_default(&config);
    config.threshold = threshold;
    frame.data = gray;
    frame.width = width;
    frame.height = height;
    frame.stride = width;
    frame.pixel_format = QR_PIXEL_FORMAT_GRAY8;
    return qr_pipeline_run_v1_2(&frame, &config, horizontal, horizontal_count,
                                result, profile, clock_fn, clock_context);
}

int qr_pipeline_run(const uint8_t *gray, int width, int height, int threshold,
                    const qr_candidate_t *horizontal, int horizontal_count,
                    qr_pipeline_result_t *result)
{
    return qr_pipeline_run_profiled(gray, width, height, threshold, horizontal,
                                    horizontal_count, result, 0, 0, 0);
}

const char *qr_stage_string(qr_stage_t stage)
{
    switch (stage) {
    case QR_STAGE_OK: return "ok";
    case QR_STAGE_VERTICAL: return "vertical";
    case QR_STAGE_CLUSTER: return "cluster";
    case QR_STAGE_TRIPLE: return "triple";
    case QR_STAGE_SAMPLE: return "sample";
    case QR_STAGE_DECODE: return "decode";
    case QR_STAGE_ARGUMENT: return "argument";
    }
    return "unknown";
}
