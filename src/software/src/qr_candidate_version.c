#include <stdint.h>
#include <stddef.h>
#include "qr_mainline_linux.h"
#ifndef QR_CANDIDATE_LEVEL
#define QR_CANDIDATE_LEVEL 1
#endif
uint32_t qr_candidate_level(void){return QR_CANDIDATE_LEVEL;}
uint32_t qr_candidate_result_size(void){return (uint32_t)sizeof(struct qr_mainline_result);}
uint32_t qr_candidate_symbol_offset(void){return (uint32_t)offsetof(struct qr_mainline_result,symbols);}
_Static_assert(sizeof(struct qr_mainline_symbol)==1044,"public symbol ABI changed");
_Static_assert(sizeof(struct qr_mainline_result)==8392,"public result ABI changed");
_Static_assert(offsetof(struct qr_mainline_result,symbols)==36,"public result offsets changed");

#include "qr_profile.h"
static uint64_t profile_us[8], profile_calls[8], fitness_calls;
const char *qr_candidate_id(void){return "C04-AC-FITNESS";}
void qr_profile_reset(void){for(unsigned i=0;i<8;i++){profile_us[i]=0;profile_calls[i]=0;}fitness_calls=0;}
void qr_profile_add(unsigned i,uint64_t us){
#if QR_PROFILE_ENABLED
    if(i<8){profile_us[i]+=us;profile_calls[i]++;}
#else
    (void)i;(void)us;
#endif
}
uint64_t qr_profile_get(unsigned i){return i<8?profile_us[i]:0;}
uint64_t qr_profile_calls(unsigned i){return i<8?profile_calls[i]:0;}
void qr_profile_fitness_call(void){
#if QR_PROFILE_ENABLED
    fitness_calls++;
#endif
}
uint64_t qr_profile_fitness_calls(void){return fitness_calls;}

void qr_profile_add_time(unsigned stage,uint64_t us){
#if QR_PROFILE_ENABLED
 if(stage<8)profile_us[stage]+=us;
#else
 (void)stage;(void)us;
#endif
}
