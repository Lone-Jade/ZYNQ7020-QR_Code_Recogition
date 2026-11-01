#define _POSIX_C_SOURCE 200809L
#include "qr_profile.h"
/* Build the vendored quirc detector with cooperative network service points.
 * Renaming the upstream quirc_end lets this translation unit reuse all of its
 * private detector primitives without maintaining a fork of identify.c. */
#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-parameter"
#pragma GCC diagnostic ignored "-Wsign-compare"
#endif
#define quirc_end quirc_end_upstream
#if defined(__has_include)
#if __has_include("quirc_identify.inc")
#include "quirc_identify.inc"
#else
#include "identify.c"
#endif
#else
#include "identify.c"
#endif
#undef quirc_end
#include "qr_failure_trace.h"
static int last_otsu_threshold=-1;
int qr_quirc_last_otsu_threshold(void){return last_otsu_threshold;}
#if defined(__GNUC__)
#pragma GCC diagnostic pop
#endif

/* Host tests may omit the replay network layer.  The board application
 * supplies a strong implementation which drains lwIP RX. */
__attribute__((weak)) void qr_pipeline_cooperate(void)
{
}

static void identify_prepared_pixels(struct quirc *q)
{
    int i;
    qr_fitness_binary_begin(q);
    uint64_t started=qr_profile_now();
    for (i = 0; i < q->h; ++i) {
        if ((i & 3) == 0)
            qr_pipeline_cooperate();
        finder_scan(q, (unsigned int)i);
    }
    qr_profile_add(2,qr_profile_now()-started);started=qr_profile_now();
    for (i = 0; i < q->num_capstones; ++i) {
        qr_pipeline_cooperate();
        test_grouping(q, (unsigned int)i);
    }
    qr_fitness_binary_end(q);
    qr_profile_add(3,qr_profile_now()-started);
}

void quirc_end(struct quirc *q)
{
    uint8_t threshold = otsu(q);
    last_otsu_threshold=threshold;
    pixels_setup(q, threshold);
    identify_prepared_pixels(q);
}

/* PL Binary8 has black=0 and white=255.  quirc's working image uses
 * black=1 and white=0 (then region labels during flood fill).  Do not run
 * Otsu on this input: an all-black or all-white ROI remains exactly that.
 * The caller supplies private storage because quirc labels it in place.
 * A non-binary value rejects a wrong-format/corrupted ROI rather than
 * silently treating a grayscale diagnostic frame as binary. */
int qr_quirc_end_binary(struct quirc *q)
{
    last_otsu_threshold=-1;
    int i;
    int length = q->w * q->h;
    if (QUIRC_PIXEL_ALIAS_IMAGE)
        q->pixels = (quirc_pixel_t *)q->image;
    for (i = 0; i < length; ++i) {
        uint8_t value = q->image[i];
        if (value != 0U && value != 255U)
            return -1;
        q->pixels[i] = value == 0U ? QUIRC_PIXEL_BLACK : QUIRC_PIXEL_WHITE;
    }
    identify_prepared_pixels(q);
    return 0;
}
