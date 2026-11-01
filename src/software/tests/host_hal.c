/* In-memory fake capture descriptor only. No hardware/board operations. */
#include <stdarg.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include "ax7021b_qr.h"
#undef clock_gettime
extern int clock_gettime(clockid_t,struct timespec*);
static struct ax7021b_qr_roi_bank bank;
static uint64_t fake_clock;
static uint32_t clock_step;
int qr_test_clock_gettime(clockid_t id,struct timespec *out){
 if(clock_step){fake_clock+=clock_step;out->tv_sec=(time_t)(fake_clock/1000000U);out->tv_nsec=(long)((fake_clock%1000000U)*1000U);return 0;}
 return clock_gettime(id,out);
}
void qr_test_set_clock_step(uint32_t value){clock_step=value;fake_clock=1000000U;}
void qr_test_set_bank(const void *data){memcpy(&bank,data,sizeof(bank));}
int ioctl(int fd,unsigned long request,...){
 va_list ap;void *p;va_start(ap,request);p=va_arg(ap,void*);va_end(ap);
 if(fd!=42){errno=EBADF;return -1;}
 if(request==AX7021B_QR_IOC_GET_ROI_BANK){
  struct ax7021b_qr_roi_bank *r=p;
  if(r->bank==bank.bank){memcpy(r,&bank,sizeof(bank));return 0;}
  memset(r->data,0,sizeof(r->data));r->words=AX7021B_QR_ROI_BANK_WORDS;return 0;
 }
 errno=ENOTTY;return -1;
}
