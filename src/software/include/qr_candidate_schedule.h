#ifndef QR_CANDIDATE_SCHEDULE_H
#define QR_CANDIDATE_SCHEDULE_H
#include <stdint.h>
#include "qr_pl_roi_protocol.h"
#define QR_ROI_HISTORY_LIMIT 64U
struct qr_roi_history {
 uint32_t min_xy,max_xy,module_q8,last_seen,last_attempt,last_success;
 uint32_t valid,attempted,success;
};
struct qr_roi_priority {
 uint32_t epoch,config,tick,initialized;
 struct qr_roi_history history[QR_ROI_HISTORY_LIMIT];
};
void qr_roi_priority_begin(struct qr_roi_priority *,uint32_t epoch,uint32_t config,
 const qr_pl_roi_t *,uint32_t count,uint32_t rotate,uint32_t *order,uint32_t *slots);
void qr_roi_priority_attempt(struct qr_roi_priority *,uint32_t slot,uint32_t decoded);
int qr_roi_same_crop(const qr_pl_roi_t *,const qr_pl_roi_t *);
int qr_roi_budget_allows(uint32_t attempts,uint32_t elapsed,uint32_t budget);
#endif
