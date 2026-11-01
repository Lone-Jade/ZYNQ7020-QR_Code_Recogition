#include "qr_decode_scheduler.h"

void qr_decode_scheduler_reset(qr_decode_scheduler_t *scheduler) {
    scheduler->cursor = 0U;
}

uint32_t qr_decode_scheduler_begin(const qr_decode_scheduler_t *scheduler,
                                   uint32_t count) {
    return count ? scheduler->cursor % count : 0U;
}

uint32_t qr_decode_scheduler_index(uint32_t start, uint32_t visited,
                                   uint32_t count) {
    return count ? (start + visited) % count : 0U;
}

int qr_decode_scheduler_allows(uint32_t attempts, uint32_t elapsed_us) {
    return QR_DECODE_BUDGET_US == 0U || attempts == 0U ||
           elapsed_us < QR_DECODE_BUDGET_US;
}

void qr_decode_scheduler_finish(qr_decode_scheduler_t *scheduler,
                                uint32_t count, uint32_t start,
                                uint32_t visited) {
    if (!count) {
        scheduler->cursor = 0U;
    } else if (visited < count) {
        scheduler->cursor = (start + visited) % count;
    } else {
        scheduler->cursor = (start + 1U) % count;
    }
}
