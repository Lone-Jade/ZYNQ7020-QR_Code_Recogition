#ifndef QR_DECODE_SCHEDULER_H
#define QR_DECODE_SCHEDULER_H

#include <stdint.h>

#ifndef QR_DECODE_BUDGET_US
#define QR_DECODE_BUDGET_US 0U
#endif

typedef struct {
    uint32_t cursor;
} qr_decode_scheduler_t;

void qr_decode_scheduler_reset(qr_decode_scheduler_t *scheduler);
uint32_t qr_decode_scheduler_begin(const qr_decode_scheduler_t *scheduler,
                                   uint32_t count);
uint32_t qr_decode_scheduler_index(uint32_t start, uint32_t visited,
                                   uint32_t count);
int qr_decode_scheduler_allows(uint32_t attempts, uint32_t elapsed_us);
void qr_decode_scheduler_finish(qr_decode_scheduler_t *scheduler,
                                uint32_t count, uint32_t start,
                                uint32_t visited);

#endif
