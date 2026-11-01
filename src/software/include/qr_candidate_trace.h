#ifndef QR_CANDIDATE_TRACE_H
#define QR_CANDIDATE_TRACE_H
#include <stdint.h>
#include <stddef.h>
enum qr_roi_reason {
 QR_ROI_PENDING=0,QR_ROI_DECODED=1,QR_ROI_NO_GRID=2,QR_ROI_DECODE_FAILED=3,
 QR_ROI_INVALID=4,QR_ROI_BUDGET=5,QR_ROI_RESULT_LIMIT=6,QR_ROI_OUTPUT_FILTERED=7,
 QR_ROI_SAME_FRAME_DUPLICATE=8
};
/* Fixed-width, versioned metadata only. No pixels or successful payloads. */
struct qr_roi_trace {
 uint32_t index,epoch,frame,config;
 uint32_t min_xy,max_xy,module_angle,score_word;
 uint32_t reason,decode_attempts,grids_found,decoded_instances;
 uint32_t copy_us,identify_us,sample_us,ecc_us,total_us,otsu_threshold;
 uint32_t errors[8];
 uint32_t flags,retry_count,retry_reason,retry_elapsed_us;
};
struct qr_mainline_context;
uint32_t qr_mainline_trace_count(const struct qr_mainline_context *context);
int qr_mainline_get_roi_trace(const struct qr_mainline_context *context,uint32_t index,
                             struct qr_roi_trace *trace,size_t bytes);
uint32_t qr_mainline_trace_size(void);
int qr_mainline_set_decode_budget_us(struct qr_mainline_context *,uint32_t budget);
uint32_t qr_quirc_last_sample_us(void);
uint32_t qr_quirc_last_ecc_us(void);
uint32_t qr_quirc_last_error_count(uint32_t error);
uint32_t qr_quirc_last_attempt_flags(void);
int qr_quirc_last_otsu_threshold(void);
_Static_assert(sizeof(struct qr_roi_trace)==120,"ROI trace ABI changed");
#endif
