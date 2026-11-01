#include "qr_failure_trace.h"
#if QR_FAILURE_TRACE
#include <string.h>
qr_trace_descriptor_t g_qr_trace_descriptor __attribute__((aligned(64)));
static qr_trace_record_t records[QRT_CAPACITY] __attribute__((aligned(64)));
static qr_trace_snapshot_t snapshots[QRT_SNAP_CAPACITY] __attribute__((aligned(64)));
static uint8_t images[QRT_SNAP_CAPACITY][QRT_SNAP_BYTES] __attribute__((aligned(64)));
static uint32_t source_frame,roi_index;
static uint64_t last_snapshot_us;
static int snapshot_pending;
void qr_trace_begin(const char *run,int enabled,uint64_t now){
 qr_trace_descriptor_t *d=&g_qr_trace_descriptor;
 memset(d,0,sizeof(*d));
 d->magic=QRT_MAGIC;d->version=1;d->record_bytes=sizeof(records[0]);
 d->capacity=QRT_CAPACITY;d->records_address=(uint32_t)(uintptr_t)records;
 d->snap_meta_address=(uint32_t)(uintptr_t)snapshots;
 d->snap_data_address=(uint32_t)(uintptr_t)images;
 d->snap_capacity=QRT_SNAP_CAPACITY;d->snap_bytes=QRT_SNAP_BYTES;
 d->snap_interval_us=QRT_SNAP_INTERVAL_US;d->begin_us=now;
 strncpy(d->run,run,sizeof(d->run)-1);d->state=enabled?1U:0U;
 source_frame=0;roi_index=0;last_snapshot_us=0;snapshot_pending=0;
}
void qr_trace_context(uint32_t frame,uint32_t roi){source_frame=frame;roi_index=roi;}
uint32_t qr_trace_roi_index(void){return roi_index;}
qr_trace_record_t *qr_trace_add(uint32_t kind){
 qr_trace_descriptor_t *d=&g_qr_trace_descriptor;qr_trace_record_t *r;
 if(d->state!=1)return NULL;
 if(d->count>=d->capacity){d->dropped++;return NULL;}
 r=&records[d->count++];memset(r,0,sizeof(*r));
 r->kind=kind;r->frame=source_frame;r->us=qr_trace_clock();return r;
}
void qr_trace_payload(int error,int mirror,int rejected,const uint8_t *p,int n,int grid){
 qr_trace_record_t *r;
 /* Failed quirc_data may contain an invalid/partial payload: never inspect it. */
 if(error)return;
 r=qr_trace_add(QRT_PAYLOAD);if(!r)return;
 r->w[0]=roi_index;r->w[1]=(uint32_t)mirror;r->w[2]=(uint32_t)rejected;
 r->w[3]=(uint32_t)n;r->w[4]=(uint32_t)(n<0?0:(n>88?88:n));
 r->w[5]=(uint32_t)grid;
 if(p&&r->w[4])memcpy(&r->w[6],p,r->w[4]);
}
uint8_t *qr_trace_snapshot_begin(uint64_t now){
 qr_trace_descriptor_t *d=&g_qr_trace_descriptor;
 if(d->state!=1||snapshot_pending||d->snap_count>=d->snap_capacity)return NULL;
 if(d->snap_attempted&&now-last_snapshot_us<d->snap_interval_us)return NULL;
 last_snapshot_us=now;d->snap_attempted++;snapshot_pending=1;
 return images[d->snap_count];
}
void qr_trace_snapshot_end(uint32_t frame,uint32_t epoch,const uint32_t *guard,
                           uint64_t now,uint32_t copy_us,int valid){
 qr_trace_descriptor_t *d=&g_qr_trace_descriptor;qr_trace_snapshot_t *s;
 if(!snapshot_pending)return;
 snapshot_pending=0;d->capture_us_total+=copy_us;
 if(!valid){d->snap_rejected++;return;}
 s=&snapshots[d->snap_count++];memset(s,0,sizeof(*s));
 s->frame=frame;s->epoch=epoch;s->valid=1;s->copy_us=copy_us;s->us=now;
 memcpy(s->guard,guard,sizeof(s->guard));
}
void qr_trace_end(uint64_t now){
 qr_trace_descriptor_t *d=&g_qr_trace_descriptor;
 if(d->state!=1)return;
 d->end_us=now;d->state=2;
 qr_trace_flush(records,(size_t)d->count*sizeof(records[0]));
 qr_trace_flush(snapshots,(size_t)d->snap_count*sizeof(snapshots[0]));
 qr_trace_flush(images,(size_t)d->snap_count*QRT_SNAP_BYTES);
 qr_trace_flush(d,sizeof(*d));
}
#endif
