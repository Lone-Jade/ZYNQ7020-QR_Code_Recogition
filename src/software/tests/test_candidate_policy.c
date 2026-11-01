#include "qr_candidate_schedule.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static qr_pl_roi_t roi(unsigned x,unsigned module){
 qr_pl_roi_t r={0};r.min_xy=x|(20U<<16);r.max_xy=(x+20U)|(40U<<16);
 r.module_angle=module;r.reserved[0]=180;return r;
}
int main(void){
 struct qr_roi_priority state={0};qr_pl_roi_t rois[30];
 uint32_t order[30],slots[30],seen[30]={0},last[30]={0},max_gap=0;
 for(unsigned i=0;i<30;i++)rois[i]=roi(30U*i+5U,i==1?3U*256U:6U*256U);
 qr_roi_priority_begin(&state,1,7,rois,30,0,order,slots);
 assert(order[0]==1);qr_roi_priority_attempt(&state,slots[1],1);
 qr_roi_priority_begin(&state,1,7,rois,30,1,order,slots);
 assert(order[0]!=1); /* recent success gives unread targets an opportunity */
 memset(&state,0,sizeof(state));
 for(unsigned tick=1;tick<=150;tick++){
  qr_roi_priority_begin(&state,1,7,rois,30,tick%30,order,slots);
  unsigned selected=order[0];seen[selected]++;
  if(last[selected] && tick-last[selected]>max_gap)max_gap=tick-last[selected];
  last[selected]=tick;qr_roi_priority_attempt(&state,slots[selected],selected%2);
 }
 for(unsigned i=0;i<30;i++)assert(seen[i]>=3);assert(max_gap<=32);
 qr_roi_priority_begin(&state,2,7,rois,30,0,order,slots);
 assert(state.tick==1 && state.epoch==2);
 for(unsigned i=0;i<30;i++)assert(!state.history[slots[i]].success);
 qr_pl_roi_t a=roi(5,768),b=a;
 assert(qr_roi_same_crop(&a,&b));b.module_angle=1024;assert(!qr_roi_same_crop(&a,&b));
 assert(qr_roi_budget_allows(0,90000,60000));
 assert(qr_roi_budget_allows(1,59999,60000));
 assert(!qr_roi_budget_allows(1,60000,60000));
 puts("PASS unread/small priority, bounded starvation, epoch reset, crop key, soft budget");
 return 0;
}
