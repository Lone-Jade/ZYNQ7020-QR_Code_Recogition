#include "qr_osd_queue.h"
#include <string.h>
static void copy_text(char*d,const char*s){unsigned i=0;while(s&&s[i]&&i<32){d[i]=(s[i]>=32&&s[i]<=126)?s[i]:'?';i++;}if(s&&s[i]){d[31]='>';i=32;}d[i]=0;}
void qr_osd_queue_init(qr_osd_queue_t*q){memset(q,0,sizeof(*q));}
static void show(qr_osd_queue_t*q,qr_osd_entry_t*e,unsigned slot,uint64_t now,qr_osd_event_fn fn,void*ctx){e->show_us=now;if(fn)fn(ctx,"SHOW",slot,e,now);q->revision++;}
int qr_osd_queue_enqueue(qr_osd_queue_t*q,uint32_t track,const char*payload,uint64_t now,qr_osd_event_fn fn,void*ctx){qr_osd_entry_t e;memset(&e,0,sizeof(e));e.track_id=track;copy_text(e.text,payload);q->read_count++;
 if(q->visible_count<QR_OSD_VISIBLE){q->visible[q->visible_count]=e;show(q,&q->visible[q->visible_count],q->visible_count,now,fn,ctx);q->visible_count++;return 1;}
 if(q->pending_count>=QR_OSD_CAPACITY-QR_OSD_VISIBLE){memmove(&q->pending[0],&q->pending[1],sizeof(q->pending[0])*(q->pending_count-1));q->pending_count--;q->overflow_count++;}
 q->pending[q->pending_count++]=e;q->revision++;return 1;}
int qr_osd_queue_update(qr_osd_queue_t*q,uint64_t now,qr_osd_event_fn fn,void*ctx){int changed=0;while(q->visible_count&&now-q->visible[0].show_us>=3000000U){qr_osd_entry_t old=q->visible[0];if(fn)fn(ctx,"HIDE",0,&old,now);memmove(&q->visible[0],&q->visible[1],sizeof(q->visible[0])*(q->visible_count-1));q->visible_count--;changed=1;if(q->pending_count){q->visible[q->visible_count]=q->pending[0];memmove(&q->pending[0],&q->pending[1],sizeof(q->pending[0])*(q->pending_count-1));q->pending_count--;show(q,&q->visible[q->visible_count],q->visible_count,now,fn,ctx);q->visible_count++;}}
 if(changed)q->revision++;
 return changed;}
