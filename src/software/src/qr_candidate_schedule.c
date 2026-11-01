#include "qr_candidate_schedule.h"
#include <string.h>

static int matches(const struct qr_roi_history *h,const qr_pl_roi_t *r,uint32_t tick){
 if((r->min_xy&65535U)>=(r->max_xy&65535U) || (r->min_xy>>16)>=(r->max_xy>>16))return 0;
 uint32_t module=r->module_angle&65535U;
 int32_t hx=(int32_t)(h->min_xy&65535U)+(int32_t)(h->max_xy&65535U);
 int32_t hy=(int32_t)(h->min_xy>>16)+(int32_t)(h->max_xy>>16);
 int32_t rx=(int32_t)(r->min_xy&65535U)+(int32_t)(r->max_xy&65535U);
 int32_t ry=(int32_t)(r->min_xy>>16)+(int32_t)(r->max_xy>>16);
 uint32_t width=(r->max_xy&65535U)-(r->min_xy&65535U);
 uint32_t height=(r->max_xy>>16)-(r->min_xy>>16);
 int64_t dx=(int64_t)hx-rx,dy=(int64_t)hy-ry;
 uint64_t radius=width>height?width:height;
 return h->valid && tick-h->last_seen<=3U && module && h->module_q8 &&
  4U*module<=5U*h->module_q8 && 4U*h->module_q8<=5U*module &&
  (uint64_t)(dx*dx+dy*dy)<=radius*radius;
}

static int before(const struct qr_roi_priority *s,const qr_pl_roi_t *r,
 const uint32_t *slots,uint32_t a,uint32_t b,uint32_t count,uint32_t rotate){
 const struct qr_roi_history *ha=&s->history[slots[a]],*hb=&s->history[slots[b]];
 uint32_t age_a=s->tick-ha->last_attempt,age_b=s->tick-hb->last_attempt;
 int overdue_a=age_a>=3U,overdue_b=age_b>=3U;
 if(overdue_a!=overdue_b)return overdue_a>overdue_b;
 if(overdue_a && age_a!=age_b)return age_a>age_b;
 int recent_a=ha->success && s->tick-ha->last_success<=8U;
 int recent_b=hb->success && s->tick-hb->last_success<=8U;
 if(recent_a!=recent_b)return recent_a<recent_b;
 int small_a=(r[a].module_angle&65535U)<=4U*256U;
 int small_b=(r[b].module_angle&65535U)<=4U*256U;
 if(small_a!=small_b)return small_a>small_b;
 if(age_a!=age_b)return age_a>age_b;
 uint32_t score_a=r[a].reserved[0]&255U,score_b=r[b].reserved[0]&255U;
 if(score_a!=score_b)return score_a>score_b;
 return (a+count-rotate)%count < (b+count-rotate)%count;
}

void qr_roi_priority_begin(struct qr_roi_priority *s,uint32_t epoch,uint32_t config,
 const qr_pl_roi_t *rois,uint32_t count,uint32_t rotate,uint32_t *order,uint32_t *slots){
 uint8_t used[QR_ROI_HISTORY_LIMIT]={0};
 if(!s->initialized || s->epoch!=epoch || s->config!=config || s->tick==UINT32_MAX){
  memset(s,0,sizeof(*s));s->epoch=epoch;s->config=config;s->initialized=1;
 }
 ++s->tick;if(count>QR_PL_ROI_LIMIT)count=QR_PL_ROI_LIMIT;
 for(uint32_t i=0;i<count;i++){
  uint32_t slot=QR_ROI_HISTORY_LIMIT;
  for(uint32_t j=0;j<QR_ROI_HISTORY_LIMIT;j++)if(!used[j] && matches(&s->history[j],&rois[i],s->tick)){slot=j;break;}
  if(slot==QR_ROI_HISTORY_LIMIT){
   for(uint32_t j=0;j<QR_ROI_HISTORY_LIMIT;j++)if(!used[j] &&
       (slot==QR_ROI_HISTORY_LIMIT || !s->history[j].valid || s->history[j].last_seen<s->history[slot].last_seen)){
    slot=j;if(!s->history[j].valid)break;
   }
   memset(&s->history[slot],0,sizeof(s->history[slot]));
   s->history[slot].last_attempt=s->tick-1U;
  }
  struct qr_roi_history *h=&s->history[slot];
  h->valid=1;h->min_xy=rois[i].min_xy;h->max_xy=rois[i].max_xy;
  h->module_q8=rois[i].module_angle&65535U;h->last_seen=s->tick;
  used[slot]=1;slots[i]=slot;order[i]=i;
 }
 if(!count)return;
 rotate%=count;
 for(uint32_t i=1;i<count;i++){
  uint32_t value=order[i],j=i;
  while(j && before(s,rois,slots,value,order[j-1],count,rotate)){order[j]=order[j-1];--j;}
  order[j]=value;
 }
}
void qr_roi_priority_attempt(struct qr_roi_priority *s,uint32_t slot,uint32_t decoded){
 if(slot>=QR_ROI_HISTORY_LIMIT)return;
 s->history[slot].attempted=1;s->history[slot].last_attempt=s->tick;
 if(decoded){s->history[slot].success=1;s->history[slot].last_success=s->tick;}
}
int qr_roi_same_crop(const qr_pl_roi_t *a,const qr_pl_roi_t *b){
 return a->min_xy==b->min_xy && a->max_xy==b->max_xy &&
  (a->module_angle&65535U)==(b->module_angle&65535U);
}
int qr_roi_budget_allows(uint32_t attempts,uint32_t elapsed,uint32_t budget){
 return attempts==0U || budget==0U || elapsed<budget;
}
