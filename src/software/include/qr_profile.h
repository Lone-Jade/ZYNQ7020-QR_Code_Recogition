#ifndef QR_PROFILE_H
#define QR_PROFILE_H
#include <stdint.h>
#include <time.h>
#ifndef QR_PROFILE_ENABLED
#define QR_PROFILE_ENABLED 1
#endif
void qr_profile_reset(void);
void qr_profile_add(unsigned stage, uint64_t us);
/* Shared ROI teardown adds time without inventing another grid call. */
void qr_profile_add_time(unsigned stage, uint64_t us);
uint64_t qr_profile_get(unsigned stage);
uint64_t qr_profile_calls(unsigned stage);
void qr_profile_fitness_call(void);
uint64_t qr_profile_fitness_calls(void);
static inline uint64_t qr_profile_now(void) {
#if QR_PROFILE_ENABLED
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec*1000000ULL+(uint64_t)t.tv_nsec/1000ULL;
#else
    return 0;
#endif
}
#endif
