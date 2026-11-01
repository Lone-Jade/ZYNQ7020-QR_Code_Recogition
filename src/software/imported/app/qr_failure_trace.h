#ifndef QR_FAILURE_TRACE_H
#define QR_FAILURE_TRACE_H
#include <stdint.h>
#include <stddef.h>
#ifndef QR_FAILURE_TRACE
#define QR_FAILURE_TRACE 0
#endif
#define QRT_MAGIC 0x39545251U
#ifndef QRT_CAPACITY
#define QRT_CAPACITY 524288U
#endif
#ifndef QRT_SNAP_CAPACITY
#define QRT_SNAP_CAPACITY 48U
#endif
#define QRT_SNAP_BYTES (1280U * 720U)
#define QRT_SNAP_INTERVAL_US 4000000U
enum { QRT_FRAME=1, QRT_ROI, QRT_CALL, QRT_CAPSTONE, QRT_GRID,
       QRT_PAYLOAD, QRT_TRACK, QRT_FRAME_END, QRT_IDENTIFY, QRT_GRID_BITS };
enum { QRT_PENDING=0, QRT_DECODE=1, QRT_EQUIVALENT=2, QRT_PREDICT=3,
       QRT_TRACK_ERROR=4, QRT_BUDGET=5, QRT_INSTANCE=6, QRT_ABORT=7,
       QRT_COPY_REJECT=8 };
typedef struct { uint32_t kind,frame; uint64_t us; uint32_t w[28]; } qr_trace_record_t;
typedef struct {
 uint32_t magic,version,record_bytes,capacity,count,dropped,state,records_address;
 uint32_t snap_meta_address,snap_data_address,snap_count,snap_capacity,snap_bytes;
 uint32_t snap_interval_us,snap_attempted,snap_rejected;
 uint64_t begin_us,end_us;
 char run[24];
 uint32_t capture_us_total,trace_us_total,reserved[4];
} qr_trace_descriptor_t;
typedef struct {
 uint32_t frame,epoch,valid,copy_us; uint64_t us; uint32_t guard[10];
} qr_trace_snapshot_t;
typedef char qrt_record_size[sizeof(qr_trace_record_t)==128?1:-1];
typedef char qrt_descriptor_size[sizeof(qr_trace_descriptor_t)==128?1:-1];
typedef char qrt_snapshot_size[sizeof(qr_trace_snapshot_t)==64?1:-1];
#if QR_FAILURE_TRACE
extern qr_trace_descriptor_t g_qr_trace_descriptor;
uint64_t qr_trace_clock(void);
void qr_trace_flush(const void *address,size_t bytes);
void qr_trace_begin(const char *run,int enabled,uint64_t now);
void qr_trace_end(uint64_t now);
void qr_trace_context(uint32_t frame,uint32_t roi);
uint32_t qr_trace_roi_index(void);
qr_trace_record_t *qr_trace_add(uint32_t kind);
void qr_trace_payload(int error,int mirror,int rejected,const uint8_t *payload,int length,int grid);
uint8_t *qr_trace_snapshot_begin(uint64_t now);
void qr_trace_snapshot_end(uint32_t frame,uint32_t epoch,const uint32_t *guard,
                           uint64_t now,uint32_t copy_us,int valid);
#else
static inline void qr_trace_begin(const char *r,int e,uint64_t n){(void)r;(void)e;(void)n;}
static inline void qr_trace_end(uint64_t n){(void)n;}
static inline void qr_trace_context(uint32_t f,uint32_t r){(void)f;(void)r;}
static inline uint32_t qr_trace_roi_index(void){return 0;}
static inline qr_trace_record_t *qr_trace_add(uint32_t k){(void)k;return NULL;}
static inline void qr_trace_payload(int e,int m,int r,const uint8_t *p,int n,int g){(void)e;(void)m;(void)r;(void)p;(void)n;(void)g;}
#endif
#endif
