#ifndef QR_TEST_DIAG_H
#define QR_TEST_DIAG_H
#include <stdint.h>
#include <stddef.h>
#define QRTEST_VERSION 1
/* Absorb bursts from simultaneous QR grids without blocking frame processing.
 * The 100-target pipeline overloaded the original 64-record queue. */
#define QRTEST_QUEUE_SIZE 1024U
#define QRTEST_LINE_SIZE 3200U
#ifndef QR_DIAG_COMPACT
#define QR_DIAG_COMPACT 1
#endif
typedef enum {
 QRD_FRAMES, QRD_CAPTURE_ERROR, QRD_VDMA_ERROR, QRD_SNAPSHOT_INVALID,
 QRD_PL_ZERO, QRD_PL_NONZERO, QRD_PL_OVERFLOW, QRD_PL_AXIS_ERROR,
 QRD_LOCATE_SCAN, QRD_VERTICAL, QRD_CENTERS, QRD_TRIPLES, QRD_VERTICAL_FAIL,
 QRD_CLUSTER_FAIL, QRD_COMBINATION_FAIL, QRD_ROI_SCAN, QRD_FULL_SCAN,
 QRD_GRIDS, QRD_NO_GRID, QRD_DECODE_CALL, QRD_MIRROR_CALL, QRD_RAW_SUCCESS,
 QRD_LENGTH_REJECT, QRD_BUSINESS_OUTPUT, QRD_ROI_EQUIVALENT,
 QRD_ROI_DISPATCH, QRD_DECODE_STARTED, QRD_BUDGET_DEFERRED,
 QRD_BUDGET_STOP, QRD_BUDGET_OVERRUN, QRD_ROTATION_ADVANCED,
 QRD_INSTANCE_DEFERRED, QRD_RAW_OVERFLOW,
 QRD_CLUSTER_OVERFLOW, QRD_ROI_OVERFLOW, QRD_PL_TIMEOUT, QRD_PL_GEOM_PASS, QRD_PL_SCALE_REJECT, QRD_COUNT
} qr_diag_counter_t;
typedef struct {
 uint32_t count[QRD_COUNT], errors[16];
 uint32_t seq, dropped, pending, frame, pl_status, vdma_status;
 uint64_t now_us, last_stats_us, pipeline_us, roi_us, roi_pixels;
 uint32_t roi_max_us;
 char run[17];
 int active, ending, enabled;
} qr_test_diag_t;
extern qr_test_diag_t qr_diag;
void qr_diag_init(void);
int qr_diag_begin(const char *run, int enabled, uint64_t now);
void qr_diag_end(uint64_t now);
void qr_diag_count(qr_diag_counter_t key, uint32_t amount);
void qr_diag_emit(const char *kind, const char *fields);
void qr_diag_legacy(const char *line);
/* Atomically admit output and compatibility line. 0 means retry, -1 invalid. */
int qr_diag_try_business(const char *fields,const char *legacy);
void qr_diag_tick(uint64_t now, uint32_t frame);
void qr_diag_attempt(int error, int mirrored, int length_rejected,
                     const uint8_t *payload, int length);
void qr_diag_context(const char *source, uint32_t track, int already_decoded);
void qr_diag_payload_hex(const uint8_t *payload, size_t length, char *out, size_t capacity);
/* Nonblocking adapter: write returns 0 when hardware FIFO is full. */
void qr_diag_pump(int (*write_byte)(uint8_t), unsigned budget);
unsigned qr_diag_queued(void);
int qr_diag_detail_enabled(void);
void qr_diag_roi_time(uint32_t elapsed_us, uint32_t pixels);
#endif
