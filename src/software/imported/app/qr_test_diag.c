#include "qr_test_diag.h"
#include "qr_tracker.h"
#include "qr_decode_scheduler.h"
#include "qr_failure_trace.h"
#include <stdio.h>
#include <string.h>
#include <ctype.h>
qr_test_diag_t qr_diag;
static char lines[QRTEST_QUEUE_SIZE][QRTEST_LINE_SIZE];
static unsigned head, tail, used, offset;
static const char *context_source="unknown";
static uint32_t context_track;
static int context_decoded;
static uint32_t queue_peak,stats_coalesced;
#if QR_DIAG_COMPACT
#define RAW_TOTAL_CAPACITY 256U
typedef struct {uint8_t payload[1024];uint32_t length,count,first_frame,last_frame,stamp;uint64_t first_us,last_us;int rejected;uint8_t used;} raw_total_t;
static raw_total_t raw_totals[RAW_TOTAL_CAPACITY];
static uint32_t raw_stamp,raw_unstored;
static unsigned end_raw_index,end_stats_pending;
static uint64_t end_now_us;
static int flush_raw(raw_total_t *r){
 static char hex[2049],fields[2500];size_t n=r->length>1024?1024:r->length;
 if(!r->used)return 1;
 if(used>=QRTEST_QUEUE_SIZE-8U)return 0;
 qr_diag_payload_hex(r->payload,n,hex,sizeof(hex));
 snprintf(fields,sizeof(fields),"count=%lu rejected=%d payload_len=%lu payload_hex=%s truncated=%d first_us=%llu last_us=%llu first_frame=%lu last_frame=%lu",
  (unsigned long)r->count,r->rejected,(unsigned long)r->length,hex,r->length>1024,
  (unsigned long long)r->first_us,(unsigned long long)r->last_us,(unsigned long)r->first_frame,(unsigned long)r->last_frame);
 qr_diag_emit("raw_total",fields);r->used=0;return 1;
}
static void aggregate_raw(int rejected,const uint8_t *p,int length){
 unsigned i,slot=RAW_TOTAL_CAPACITY,oldest=0;size_t n;
 if(length<0||(!p&&length)){raw_unstored++;qr_diag.dropped++;return;}
 n=length>1024?1024:(size_t)length;
 for(i=0;i<RAW_TOTAL_CAPACITY;i++){
  raw_total_t *r=&raw_totals[i];
  if(r->used&&r->length==(uint32_t)length&&r->rejected==rejected&&(!n||!memcmp(r->payload,p,n))){slot=i;break;}
  if(!r->used&&slot==RAW_TOTAL_CAPACITY)slot=i;
  if(raw_totals[i].stamp<raw_totals[oldest].stamp)oldest=i;
 }
 if(slot==RAW_TOTAL_CAPACITY){slot=oldest;if(!flush_raw(&raw_totals[slot])){raw_unstored++;qr_diag.dropped++;return;}}
 {raw_total_t *r=&raw_totals[slot];if(!r->used){memset(r,0,sizeof(*r));if(n)memcpy(r->payload,p,n);r->length=(uint32_t)length;r->rejected=rejected;r->first_us=qr_diag.now_us;r->first_frame=qr_diag.frame;r->used=1;}
 r->count++;r->last_us=qr_diag.now_us;r->last_frame=qr_diag.frame;r->stamp=++raw_stamp;}
}
#endif
static const char *names[QRD_COUNT]={"frames","capture_error","vdma_error","snapshot_invalid",
 "pl_zero","pl_nonzero","pl_overflow","pl_axis_error","locate_scan","vertical","centers","triples",
 "vertical_fail","cluster_fail","combination_fail","roi_scan","full_scan","grids",
 "no_grid","decode_calls","mirror_calls","raw_success","length_reject","business_output",
 "roi_equivalent","roi_dispatch","decode_started","budget_deferred","budget_stop",
 "budget_overrun","rotation_advanced","instance_deferred","raw_overflow","cluster_overflow",
 "roi_overflow","pl_timeout","pl_geom_pass","pl_scale_reject"};
static void note_queue(void){if(used>queue_peak)queue_peak=used;}
void qr_diag_init(void){memset(&qr_diag,0,sizeof(qr_diag));head=tail=used=offset=0;queue_peak=stats_coalesced=0;
#if QR_DIAG_COMPACT
 memset(raw_totals,0,sizeof(raw_totals));raw_stamp=raw_unstored=end_raw_index=end_stats_pending=0;
#endif
}
int qr_diag_detail_enabled(void){return qr_diag.active&&qr_diag.enabled&&!QR_DIAG_COMPACT;}
void qr_diag_roi_time(uint32_t elapsed_us,uint32_t pixels){if(qr_diag.active){qr_diag.roi_us+=elapsed_us;qr_diag.roi_pixels+=pixels;if(elapsed_us>qr_diag.roi_max_us)qr_diag.roi_max_us=elapsed_us;}}
unsigned qr_diag_queued(void){return used;}
void qr_diag_legacy(const char *line){
 size_t n=strlen(line);
 if(used==QRTEST_QUEUE_SIZE||n>=QRTEST_LINE_SIZE){qr_diag.dropped++;return;}
 memcpy(lines[tail],line,n+1);tail=(tail+1)%QRTEST_QUEUE_SIZE;used++;note_queue();
}
void qr_diag_payload_hex(const uint8_t *p,size_t n,char *out,size_t cap){
 static const char hex[]="0123456789abcdef";size_t i;
 if(!cap)return;
 for(i=0;i<n&&2*i+2<cap;i++){out[2*i]=hex[p[i]>>4];out[2*i+1]=hex[p[i]&15];}
 out[2*i]=0;
}
void qr_diag_emit(const char *kind,const char *fields){
 int length;uint32_t seq;
 if(!qr_diag.active&&!qr_diag.ending)return;
 seq=++qr_diag.seq;
 if(used==QRTEST_QUEUE_SIZE){qr_diag.dropped++;return;}
 length=snprintf(lines[tail],QRTEST_LINE_SIZE,
  "QRDIAG v=1 run=%s seq=%lu us=%llu frame=%lu kind=%s source=global track=0 %s\r\n",
  qr_diag.run,(unsigned long)seq,(unsigned long long)qr_diag.now_us,
  (unsigned long)qr_diag.frame,kind,fields?fields:"");
 if(length<0||(unsigned)length>=QRTEST_LINE_SIZE){qr_diag.dropped++;return;}
 tail=(tail+1)%QRTEST_QUEUE_SIZE;used++;note_queue();
}
int qr_diag_try_business(const char *fields,const char *legacy){
 unsigned next;int length;size_t n;
 if((!qr_diag.active&&!qr_diag.ending)||!fields||!legacy)return -1;
 n=strlen(legacy);if(n>=QRTEST_LINE_SIZE)return -1;
 if(used>QRTEST_QUEUE_SIZE-2U)return 0;
 length=snprintf(lines[tail],QRTEST_LINE_SIZE,
  "QRDIAG v=1 run=%s seq=%lu us=%llu frame=%lu kind=output source=global track=0 %s\r\n",
  qr_diag.run,(unsigned long)(qr_diag.seq+1),(unsigned long long)qr_diag.now_us,
  (unsigned long)qr_diag.frame,fields);
 if(length<0||(unsigned)length>=QRTEST_LINE_SIZE)return -1;
 next=(tail+1)%QRTEST_QUEUE_SIZE;memcpy(lines[next],legacy,n+1);
 tail=(next+1)%QRTEST_QUEUE_SIZE;used+=2;qr_diag.seq++;note_queue();
 qr_diag_count(QRD_BUSINESS_OUTPUT,1);return 1;
}
int qr_diag_begin(const char *run,int enabled,uint64_t now){
 char fields[300];size_t i,n=strlen(run);
 if(qr_diag.active||qr_diag.ending||used||n<1||n>16)return -1;
 for(i=0;i<n;i++)if(!isalnum((unsigned char)run[i]))return -1;
 memset(&qr_diag,0,sizeof(qr_diag));strcpy(qr_diag.run,run);
 qr_diag.active=1;qr_diag.enabled=enabled;qr_diag.now_us=qr_diag.last_stats_us=now;
 queue_peak=stats_coalesced=0;
#if QR_DIAG_COMPACT
 memset(raw_totals,0,sizeof(raw_totals));raw_stamp=raw_unstored=end_raw_index=end_stats_pending=0;
 snprintf(fields,sizeof(fields),"command=BEGIN status=ok firmware=realtime-detection-qrtest1 diagnostics=%d diag_revision=%u queue_capacity=%u log_mode=compact raw_mode=aggregate success_only=%d tracker_capacity=%u decode_budget_us=%lu schedule=%s pl_leg_limit=32",
  enabled!=0,QR_FAILURE_TRACE?11U:(QR_TRACKER_POINT_ASSOC?8U:(QR_DECODE_BUDGET_US?7U:6U)),QRTEST_QUEUE_SIZE,QR_STEP1_SUCCESS_ONLY,
  QR_TRACKER_CAPACITY,(unsigned long)QR_DECODE_BUDGET_US,
  QR_DECODE_BUDGET_US?"round_robin":"linear");
#else
 snprintf(fields,sizeof(fields),"command=BEGIN status=ok firmware=realtime-detection-qrtest1 diagnostics=%d diag_revision=4 queue_capacity=%u",enabled!=0,QRTEST_QUEUE_SIZE);
#endif
 qr_trace_begin(run,enabled,now);
 qr_diag_emit("ack",fields);return 0;
}
void qr_diag_count(qr_diag_counter_t k,uint32_t n){if(qr_diag.active)qr_diag.count[k]+=n;}
static void stats(const char *kind){
 char buf[1600];size_t pos=0;unsigned i;
 for(i=0;i<QRD_COUNT;i++)pos+=(size_t)snprintf(buf+pos,sizeof(buf)-pos,"%s=%lu ",names[i],(unsigned long)qr_diag.count[i]);
 snprintf(buf+pos,sizeof(buf)-pos,"pl_status=%lu vdma_status=%lu pipeline_us=%llu dropped=%lu pending=%u roi_us=%llu roi_max_us=%lu roi_pixels=%llu queue_peak=%lu stats_coalesced=%lu",
  (unsigned long)qr_diag.pl_status,(unsigned long)qr_diag.vdma_status,
  (unsigned long long)qr_diag.pipeline_us,(unsigned long)qr_diag.dropped,used,
  (unsigned long long)qr_diag.roi_us,(unsigned long)qr_diag.roi_max_us,(unsigned long long)qr_diag.roi_pixels,(unsigned long)queue_peak,(unsigned long)stats_coalesced);
#if QR_DIAG_COMPACT
 pos=strlen(buf);snprintf(buf+pos,sizeof(buf)-pos," raw_unstored=%lu",(unsigned long)raw_unstored);
#endif
 qr_diag_emit(kind,buf);
 pos=0;for(i=0;i<16;i++)pos+=(size_t)snprintf(buf+pos,sizeof(buf)-pos,"e%u=%lu ",i,(unsigned long)qr_diag.errors[i]);
 qr_diag_emit("errors",buf);
}
void qr_diag_tick(uint64_t now,uint32_t frame){
 qr_diag.now_us=now;qr_diag.frame=frame;
 if(qr_diag.active&&qr_diag.enabled&&now-qr_diag.last_stats_us>=(QR_DIAG_COMPACT?5000000U:1000000U)){
  if(used<=QRTEST_QUEUE_SIZE-8U){stats("stats");qr_diag.last_stats_us=now;}else stats_coalesced++;
 }
}
void qr_diag_context(const char *s,uint32_t t,int decoded){context_source=s;context_track=t;context_decoded=decoded;}
void qr_diag_attempt(int error,int mirror,int rejected,const uint8_t *p,int n){
#if !QR_DIAG_COMPACT
 char hex[2*1024+1],buf[2400];
#endif
 if(!qr_diag.active)return;
 qr_diag_count(QRD_DECODE_CALL,1);if(mirror)qr_diag_count(QRD_MIRROR_CALL,1);
 if(error>=0&&error<16)qr_diag.errors[error]++;
 if(rejected)qr_diag_count(QRD_LENGTH_REJECT,1);
 if(error==0){
  qr_diag_count(QRD_RAW_SUCCESS,1);
  if(qr_diag.enabled){
#if QR_DIAG_COMPACT
   aggregate_raw(rejected,p,n);
#else
   qr_diag_payload_hex(p,(size_t)n,hex,sizeof(hex));
   snprintf(buf,sizeof(buf),"source=%s track=%lu mirrored=%d rejected=%d after_success=%d payload_len=%d payload_hex=%s truncated=%d",
    context_source,(unsigned long)context_track,mirror,rejected,context_decoded,n,hex,n>1024);
   qr_diag_emit("raw_success",buf);
#endif
  }
 }
}
void qr_diag_end(uint64_t now){
 if(!qr_diag.active)return;
 qr_diag.now_us=now;
 qr_trace_end(now);
#if QR_FAILURE_TRACE
 {char fields[400];qr_trace_descriptor_t *d=&g_qr_trace_descriptor;
  snprintf(fields,sizeof(fields),"version=1 descriptor=0x%08lx state=%lu records=%lu capacity=%lu dropped=%lu snapshots=%lu snapshot_attempts=%lu snapshot_rejected=%lu snapshot_copy_us=%lu transport=jtag_after_end",
   (unsigned long)(uintptr_t)d,(unsigned long)d->state,(unsigned long)d->count,
   (unsigned long)d->capacity,(unsigned long)d->dropped,(unsigned long)d->snap_count,
   (unsigned long)d->snap_attempted,(unsigned long)d->snap_rejected,(unsigned long)d->capture_us_total);
  qr_diag_emit("trace_manifest",fields);
 }
#endif
#if QR_DIAG_COMPACT
 end_now_us=now;end_raw_index=0;end_stats_pending=1;qr_diag.active=0;qr_diag.ending=1;
#else
 stats("summary");qr_diag.active=0;qr_diag.ending=1;
#endif
}
void qr_diag_pump(int (*write_byte)(uint8_t),unsigned budget){
 while(used&&budget){
  if(!write_byte((uint8_t)lines[head][offset]))return;
  offset++;budget--;
  if(!lines[head][offset]){head=(head+1)%QRTEST_QUEUE_SIZE;used--;offset=0;}
 }
 if(qr_diag.ending&&!used){
  char buf[160];
#if QR_DIAG_COMPACT
  qr_diag.now_us=end_now_us;
  while(end_raw_index<RAW_TOTAL_CAPACITY){if(!flush_raw(&raw_totals[end_raw_index]))return;end_raw_index++;}
  if(used)return;
  if(end_stats_pending){stats("summary");end_stats_pending=0;return;}
#endif
  snprintf(buf,sizeof(buf),"command=END status=ok dropped=%lu unsent=0 records=%lu complete=%d",
    (unsigned long)qr_diag.dropped,(unsigned long)qr_diag.seq,qr_diag.dropped==0);
  qr_diag_emit("ack",buf);qr_diag.ending=0;
 }
}
