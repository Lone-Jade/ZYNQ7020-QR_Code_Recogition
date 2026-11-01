/* Continuous live-camera QR application for AX7021B/Zynq-7020.
 * Version 2 pairs PL-generated ROI metadata with guarded Binary8 VDMA frames.
 * PS copies only each requested ROI and retains quirc grid/perspective/ECC.
 * QR_CAMERA_PL_ROI=0 selects the separate legacy Gray8 reference build. */
#include "camera.h"
#include "i2c_bus.h"
#include "net_replay.h"
#include "qr_pipeline.h"
#include "qr_quirc_fallback.h"
#include "qr_replay_protocol.h"
#include "qr_pl_roi_protocol.h"
#include "qr_tracker.h"
#include "qr_publication.h"
#include "qr_test_diag.h"
#include "qr_failure_trace.h"
#include "qr_decode_scheduler.h"
#include "xuartps_hw.h"
#include "qr_osd_queue.h"

#include "xaxivdma.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "xparameters.h"
#include "xtime_l.h"
#include "xiic_l.h"
#include "sleep.h"

#include <stdint.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#define QR_CAMERA_RESET_GPIO_BASE 0x41210000U
#define QR_CAMERA_IIC_BASE        0x41600000U
#define QR_CAMERA_ARM_GPIO_BASE   0x41220000U
#define QR_HDMI_RESET_GPIO_BASE   0x41200000U
#define QR_HDMI_IIC_BASE          0x41610000U
#define QR_HDMI_VDMA_BASE         0x43010000U
#define QR_OSD_BRAM_BASE          0x42000000U
#define QR_OSD_COMMIT_GPIO_BASE   0x41240000U
#define QR_CAMERA_FRAME_TIMEOUT_US 500000U
/* Board diagnostic: keep the pre-filled RGB565 bars untouched so HDMI
 * scanout can be verified independently of camera S2MM writes. */
#define QR_HDMI_STATIC_TEST       0

#define QR_HDMI_PREVIEW_WIDTH     QR_REPLAY_WIDTH
#define QR_HDMI_PREVIEW_HEIGHT    QR_REPLAY_HEIGHT
#define QR_HDMI_STRIDE            (QR_HDMI_PREVIEW_WIDTH * 2U)
#define QR_HDMI_FRAME_BYTES       (QR_HDMI_STRIDE * QR_HDMI_PREVIEW_HEIGHT)

#ifndef QR_CAMERA_GRAY_DIVISOR
#define QR_CAMERA_GRAY_DIVISOR    1U
#endif
#if QR_CAMERA_GRAY_DIVISOR != 1U && QR_CAMERA_GRAY_DIVISOR != 2U
#error "QR_CAMERA_GRAY_DIVISOR must be 1 or 2"
#endif
#define QR_DECODE_WIDTH           (QR_REPLAY_WIDTH / QR_CAMERA_GRAY_DIVISOR)
#define QR_DECODE_HEIGHT          (QR_REPLAY_HEIGHT / QR_CAMERA_GRAY_DIVISOR)
#ifndef QR_CAMERA_PL_ROI
#define QR_CAMERA_PL_ROI           1
#endif
#ifndef QR_CAMERA_PL_GRAY_DIAGNOSTIC
#define QR_CAMERA_PL_GRAY_DIAGNOSTIC 0
#endif
#ifndef QR_CAMERA_PL_OTSU
#define QR_CAMERA_PL_OTSU          1
#endif
#ifndef QR_CAMERA_PL_THRESHOLD
#define QR_CAMERA_PL_THRESHOLD     200U
#endif
#if QR_CAMERA_PL_ROI && QR_CAMERA_GRAY_DIVISOR != 1U
#error "PL ROI guard rows require full resolution, QR_CAMERA_GRAY_DIVISOR=1"
#endif
#if QR_CAMERA_PL_THRESHOLD < 1 || QR_CAMERA_PL_THRESHOLD > 255
#error "QR_CAMERA_PL_THRESHOLD must be in 1..255"
#endif
#define QR_CAMERA_PL_FORMAT (QR_CAMERA_PL_GRAY_DIAGNOSTIC ? QR_PL_FORMAT_GRAY8 : QR_PL_FORMAT_BINARY8)
#define QR_GRAY_FRAME_BYTES       (QR_DECODE_WIDTH * QR_DECODE_HEIGHT)
#define QR_CAPTURE_HEIGHT         (QR_DECODE_HEIGHT + (QR_CAMERA_PL_ROI ? 2U : 0U))
#define QR_CAPTURE_FRAME_BYTES    (QR_DECODE_WIDTH * QR_CAPTURE_HEIGHT)
#define QR_GRAY_FRAME0            QR_REPLAY_GRAY_ADDR
#define QR_GRAY_FRAME1            (QR_GRAY_FRAME0 + QR_CAPTURE_FRAME_BYTES)
#define QR_GRAY_FRAME2            (QR_GRAY_FRAME1 + QR_CAPTURE_FRAME_BYTES)
#define QR_GRAY_FRAME_COUNT       3U
typedef char qr_camera_gray_ring_must_fit_before_results[
    QR_GRAY_FRAME2 + QR_CAPTURE_FRAME_BYTES <= QR_REPLAY_RESULT_ADDR ? 1 : -1];
#if QR_CAMERA_GRAY_DIVISOR == 2U
#if QR_REPLAY_PROFILE == QR_REPLAY_PROFILE_1280X720_30FPS
#define QR_RESCUE_WIDTH           960U
#define QR_RESCUE_HEIGHT          540U
#define QR_RESCUE_SOURCE_X(x)     ((x) + ((x) / 3U))
#define QR_RESCUE_SOURCE_Y(y)     ((y) + ((y) / 3U))
#else
#define QR_RESCUE_WIDTH           640U
#define QR_RESCUE_HEIGHT          480U
#define QR_RESCUE_SOURCE_X(x)     ((x) + ((x) >> 2))
#define QR_RESCUE_SOURCE_Y(y)     ((y) + ((y) >> 2))
#endif
#ifndef QR_FULLRES_RESCUE_PERIOD
#define QR_FULLRES_RESCUE_PERIOD  3U
#endif
#if QR_FULLRES_RESCUE_PERIOD < 1U
#error "QR_FULLRES_RESCUE_PERIOD must be positive in 2x2 mode"
#endif
#endif
#define QR_SEEN_CAPACITY          128U
#define QR_SEEN_PAYLOAD_BYTES     128U
#define QR_DECODER_MODE_QUIRC_MULTIRES 3U
#define QR_DECODER_MODE_QUIRC_FULL_GRAY 4U
#define QR_FINDER_TRIPLE_LIMIT    8U

#ifdef SDT
#define QR_CAMERA_VDMA_LOOKUP_KEY QR_REPLAY_QR_VDMA_BASE
#define QR_DISPLAY_VDMA_LOOKUP_KEY QR_HDMI_VDMA_BASE
#else
#define QR_CAMERA_VDMA_LOOKUP_KEY XPAR_AXI_VDMA_0_DEVICE_ID
#define QR_DISPLAY_VDMA_LOOKUP_KEY XPAR_DISPLAY_VDMA_DEVICE_ID
#endif

typedef struct {
    uint32_t hash;
    uint32_t last_frame;
    uint8_t valid;
    char payload[QR_SEEN_PAYLOAD_BYTES];
} qr_seen_entry_t;

static XAxiVdma g_vdma;
static XAxiVdma g_display_vdma;
static qr_pipeline_result_t g_result;
static qr_quirc_fallback_profile_t g_fallback_profile;
static qr_detector_config_t g_config;
static qr_candidate_t g_pl_candidates[QR_MAX_CANDIDATES];
static qr_finder_triple_t g_finder_triples[QR_FINDER_TRIPLE_LIMIT];
static uint8_t g_decode_image[QR_GRAY_FRAME_BYTES]
    __attribute__((aligned(64)));
#if QR_CAMERA_GRAY_DIVISOR == 2U
static uint8_t g_fullres_image[QR_RESCUE_WIDTH * QR_RESCUE_HEIGHT]
    __attribute__((aligned(64)));
#endif
static qr_seen_entry_t g_seen[QR_SEEN_CAPACITY];
static qr_seen_entry_t g_window_seen[QR_SEEN_CAPACITY];
static uint32_t g_seen_next;
static uint32_t g_window_seen_next;
static uint32_t g_window_unique_total;
static uint32_t g_window_decoded_total;
volatile uint32_t g_window_reset_request;
static uint32_t g_window_reset_ack;
static uint32_t g_unique_total;
static uint32_t g_duplicate_total;
static uint32_t g_decoded_total;
static uint32_t g_processed_frames;
static uint32_t g_capture_errors;
static uint32_t g_success_frames;
static uint32_t g_pipeline_min_us = 0xFFFFFFFFU;
static uint32_t g_pipeline_max_us;
static uint64_t g_pipeline_sum_us;
static uint32_t g_fullres_frames;
static uint32_t g_fullres_success_frames;
static uint32_t g_lowres_success_frames;
static int g_net_ready;
static int g_display_ready;
static qr_tracker_t g_tracker;
static qr_decode_scheduler_t g_decode_scheduler;
static qr_publication_t g_publication;
typedef struct {
    uint32_t frame,roi_track,result_track,association_seq;
    int observe_rc;
    const char *source;
} qr_publication_job_t;
static qr_publication_job_t g_publication_jobs[QR_PUBLICATION_CAPACITY];
static uint32_t g_publication_retries,g_publication_faults,g_publication_fallbacks;
static uint64_t g_publication_compute_us;
static uint32_t g_publication_max_us;
static void publication_flush(void);
static void publication_reset(void);
static void publication_totals(void);
static uint64_t camera_now_us(void);
#if QR_FAILURE_TRACE
uint64_t qr_trace_clock(void){return camera_now_us();}
void qr_trace_flush(const void *address,size_t bytes){
 if(bytes)Xil_DCacheFlushRange((UINTPTR)address,(u32)bytes);
}
#endif
static void osd_publish(void);
static int g_snapshot_valid;
static uint32_t g_diag_context_track;
static int uart_write_nonblocking(uint8_t byte);
static qr_osd_queue_t g_osd_queue;
static uint64_t g_last_full_scan_us;
static uint8_t g_osd_bank;
static uint32_t g_osd_sequence;
static uint32_t g_pl_epoch;
static uint32_t g_pl_config_seq = 1U;
static uint32_t g_last_pl_seq;
static int g_have_pl_seq;
/* The image storage above is reused as packed private ROI scratch. The normal
 * PL ROI route never copies the whole camera frame to it. */
typedef struct {
    qr_pl_guard_t header, footer;
    qr_pl_bank_t bank;
    qr_pl_roi_t roi[QR_PL_ROI_LIMIT];
    uint32_t slot, bank_offset;
} qr_camera_roi_snapshot_t;
static qr_camera_roi_snapshot_t g_pl_snapshot;
static qr_camera_roi_snapshot_t g_pl_probe;
static qr_finder_triple_t g_pl_roi_triples[QR_PL_ROI_LIMIT];
volatile uint32_t g_pl_roi_snapshot_rejects;
volatile uint32_t g_pl_roi_copy_rejects;
volatile uint32_t g_pl_roi_flags;
volatile uint32_t g_pl_roi_last_index;
volatile uint32_t g_pl_roi_last_min_xy, g_pl_roi_last_max_xy;
volatile uint32_t g_pl_capture_restarts, g_pl_capture_restart_failures;
/* Independent diagnostics: keep the existing JTAG struct layout stable.
 * Pixels counts the copied union, not the sum of decoded overlapping ROIs. */
volatile uint32_t g_pl_roi_union_pixels, g_pl_roi_union_copy_us;
volatile uint32_t g_pl_roi_union_frames, g_pl_roi_sealed_frame;
volatile int32_t g_pl_roi_union_status;

volatile int32_t g_hdmi_status;
volatile int32_t g_camera_init_status;
volatile int32_t g_camera_probe_status;
volatile uint32_t g_camera_sensor_id;
volatile uint32_t g_camera_probe_send_count;
volatile uint32_t g_camera_probe_recv_count;
volatile uint32_t g_hdmi_probe_count;
volatile int32_t g_capture_init_status;
volatile uint32_t g_boot_phase;
volatile uint32_t g_hdmi_mm2s_status;
volatile uint32_t g_hdmi_s2mm_status;
volatile uint32_t g_pl_candidate_count;
volatile uint32_t g_pl_triple_count;
volatile uint32_t g_skipped_equivalent_triples;

/* Keep the original prefix stable for existing JTAG tools. */
typedef struct {
    uint32_t sequence;
    uint32_t frame_id;
    int32_t status;
    uint32_t stage;
    uint32_t instances;
    uint32_t pipeline_us;
    uint32_t total_us;
    char payload[256];
    uint32_t decoder_mode;
    uint32_t processed_frames;
    uint32_t capture_errors;
    uint32_t decoded_total;
    uint32_t unique_total;
    uint32_t duplicate_total;
    uint32_t source_buffer;
    uint32_t decode_width;
    uint32_t decode_height;
    uint32_t grids_found;
    uint32_t adaptive_retry;
    uint32_t adaptive_grids_found;
    uint32_t success_frames;
    uint32_t pipeline_min_us;
    uint32_t pipeline_max_us;
    uint32_t pipeline_sum_us_low;
    uint32_t pipeline_sum_us_high;
    uint32_t fullres_frames;
    uint32_t fullres_success_frames;
    uint32_t lowres_success_frames;
    /* Cumulative profiling counters; preserve all preceding JTAG offsets. */
    uint32_t capture_us_low, capture_us_high;
    uint32_t rescue_us_low, rescue_us_high;
    uint32_t candidate_us_low, candidate_us_high;
    uint32_t roi_us_low, roi_us_high;
    uint32_t full_us_low, full_us_high;
    uint32_t roi_calls, full_calls, adaptive_calls;
    uint32_t roi_pixels_low, roi_pixels_high;
    uint32_t full_pixels_low, full_pixels_high;
    uint32_t quirc_copy_us_low, quirc_copy_us_high;
    uint32_t quirc_adaptive_us_low, quirc_adaptive_us_high;
    uint32_t quirc_identify_us_low, quirc_identify_us_high;
    uint32_t quirc_decode_us_low, quirc_decode_us_high;
    uint32_t regions_seen, capstones_seen;
    uint32_t max_regions, max_capstones;
    uint32_t pl_nonempty_frames, pl_triple_frames;
    uint32_t roi_success_frames, full_success_frames;
    uint32_t window_unique_total, window_decoded_total, window_reset_ack;
    /* Tracking/OSD extension.  The complete legacy prefix above is stable. */
    uint32_t track_created, track_retries, track_decoded_skips;
    uint32_t track_ambiguous, track_retired, full_scan_suppressed;
    uint32_t osd_read_count, osd_overflow_count, osd_revision;
} qr_camera_diagnostics_t;

volatile qr_camera_diagnostics_t g_camera_diagnostics;

typedef struct {
    uint64_t capture_us;
    uint64_t rescue_us;
    uint64_t candidate_us;
    uint64_t roi_us;
    uint64_t full_us;
    uint64_t roi_pixels;
    uint64_t full_pixels;
    uint64_t quirc_copy_us;
    uint64_t quirc_adaptive_us;
    uint64_t quirc_identify_us;
    uint64_t quirc_decode_us;
    uint32_t roi_calls;
    uint32_t full_calls;
    uint32_t adaptive_calls;
    uint32_t regions_seen;
    uint32_t capstones_seen;
    uint32_t max_regions;
    uint32_t max_capstones;
    uint32_t pl_nonempty_frames;
    uint32_t pl_triple_frames;
    uint32_t roi_success_frames;
    uint32_t full_success_frames;
} qr_camera_perf_t;

static qr_camera_perf_t g_perf;

static const UINTPTR g_gray_addresses[QR_GRAY_FRAME_COUNT] = {
    QR_GRAY_FRAME0, QR_GRAY_FRAME1, QR_GRAY_FRAME2
};

#if QR_CAMERA_GRAY_DIVISOR == 2U
static const UINTPTR g_display_addresses[QR_GRAY_FRAME_COUNT] = {
    QR_REPLAY_FRAME0, QR_REPLAY_FRAME1, QR_REPLAY_FRAME2
};
#endif

static int diag_busy(void) {return qr_diag.active || qr_diag.ending || qr_diag_queued();}
static void trace_track(const qr_track_t *t,unsigned tag,uint64_t sample_us){
 qr_trace_record_t *r;if(!t)return;r=qr_trace_add(QRT_TRACK);if(!r)return;
 r->w[0]=qr_trace_roi_index();r->w[1]=t->id;r->w[2]=tag;r->w[3]=t->publication_id;
 r->w[4]=t->last_frame;r->w[5]=(uint32_t)t->last_us;r->w[6]=(uint32_t)(t->last_us>>32);
 memcpy(&r->w[7],&t->vx,4);memcpy(&r->w[8],&t->vy,4);
 memcpy(&r->w[9],&t->x,4);memcpy(&r->w[10],&t->y,4);
 memcpy(&r->w[11],&t->size,4);memcpy(&r->w[12],&t->module_size,4);
 memcpy(&r->w[13],t->finder_x,12);memcpy(&r->w[16],t->finder_y,12);
 r->w[19]=t->active|((uint32_t)t->decoded<<8)|((uint32_t)t->velocity_valid<<16)|((uint32_t)t->finder_valid<<24);
 r->w[20]=(uint32_t)sample_us;r->w[21]=(uint32_t)(sample_us>>32);
}
static void diagnostic_decode(int error,int mirror,int rejected,const uint8_t *p,int n) {
 qr_track_t *t=qr_tracker_find(&g_tracker,g_diag_context_track);
 qr_diag.now_us=camera_now_us();
 qr_diag_attempt(error,mirror,rejected,p,n);
 if(qr_diag.active && t){t->decode_calls++;t->mirror_calls+=(unsigned)mirror;
  if(t->decoded)t->after_success_calls++;
  if(error)t->failures++;else t->raw_success++;}
 qr_diag_pump(uart_write_nonblocking,512);
}
static void diagnostic_track(const qr_track_t *t,const char *reason) {
 char buf[2600],hex[2*QR_TRACKER_PAYLOAD_BYTES+1];
 trace_track(t,3,camera_now_us());
 if(!qr_diag_detail_enabled())return;
 qr_diag.now_us=camera_now_us();
 qr_diag_payload_hex((const uint8_t *)t->payload,strlen(t->payload),hex,sizeof(hex));
 snprintf(buf,sizeof(buf),"track=%lu first_us=%llu last_us=%llu associations=%lu retry_decisions=%lu skips=%lu ambiguous=%lu decode_calls=%lu mirror_calls=%lu failures=%lu raw_success=%lu after_success_calls=%lu decoded=%u reason=%s payload_hex=%s",
  (unsigned long)t->id,(unsigned long long)t->first_us,(unsigned long long)t->last_us,
  (unsigned long)t->associations,(unsigned long)t->retry_decisions,(unsigned long)t->skips,
  (unsigned long)t->ambiguities,(unsigned long)t->decode_calls,(unsigned long)t->mirror_calls,
  (unsigned long)t->failures,(unsigned long)t->raw_success,(unsigned long)t->after_success_calls,
  t->decoded,reason,hex);
 qr_diag_emit("track",buf);
 qr_diag_pump(uart_write_nonblocking,512);
}
static void diagnostic_tracker_totals(void) {
 unsigned i,active=0,undecoded=0;char buf[1000];
 for(i=0;i<QR_TRACKER_CAPACITY;i++)if(g_tracker.tracks[i].active){active++;undecoded+=!g_tracker.tracks[i].decoded;}
 snprintf(buf,sizeof(buf),"created=%lu retries=%lu skips=%lu ambiguous=%lu retired=%lu capacity=%lu full_suppressed=%lu payload_conflicts=%lu active=%u undecoded_active=%u success_only=%d tracker_capacity=%u roi_queries=%lu roi_unmatched=%lu roi_admitted=%lu prediction_skips=%lu retry_wait=%lu capacity_skips=%lu full_bypass=%lu point_matches=%lu point_rejects=%lu unreliable_geometry=%lu unbound_rejects=%lu multi_match_decode=%lu publication_invalidated=%lu",
  (unsigned long)g_tracker.created,(unsigned long)g_tracker.retries,(unsigned long)g_tracker.decoded_skips,
  (unsigned long)g_tracker.ambiguous,(unsigned long)g_tracker.retired,
  (unsigned long)g_tracker.capacity_rejects,(unsigned long)g_tracker.full_scan_suppressed,(unsigned long)g_tracker.payload_conflicts,
  active,undecoded,QR_STEP1_SUCCESS_ONLY,QR_TRACKER_CAPACITY,
  (unsigned long)g_tracker.roi_queries,(unsigned long)g_tracker.roi_unmatched,(unsigned long)g_tracker.roi_decode_admitted,
  (unsigned long)g_tracker.roi_prediction_skips,(unsigned long)g_tracker.roi_retry_wait,
  (unsigned long)g_tracker.roi_capacity_skips,(unsigned long)g_tracker.capacity_bypass,
  (unsigned long)g_tracker.point_matches,(unsigned long)g_tracker.point_rejects,
  (unsigned long)g_tracker.unreliable_geometry,(unsigned long)g_tracker.unbound_rejects,
  (unsigned long)g_tracker.multi_match_decode,(unsigned long)g_tracker.publication_invalidated);
 qr_diag_emit("tracker",buf);
}
static int uart_write_nonblocking(uint8_t byte) {
 if(Xil_In32(STDOUT_BASEADDRESS+XUARTPS_SR_OFFSET)&XUARTPS_SR_TXFULL)return 0;
 Xil_Out32(STDOUT_BASEADDRESS+XUARTPS_FIFO_OFFSET,byte);return 1;
}
static void diagnostic_uart_poll(uint32_t frame) {
 static char command[96];static unsigned used,discard;
 publication_flush();
 qr_diag.now_us=camera_now_us();qr_diag.frame=frame;
 while(!(Xil_In32(STDIN_BASEADDRESS+XUARTPS_SR_OFFSET)&XUARTPS_SR_RXEMPTY)) {
  char byte=(char)Xil_In32(STDIN_BASEADDRESS+XUARTPS_FIFO_OFFSET);
  if(byte=='\n') {
   unsigned v=0;int enabled=1;char run[17]={0};
   command[used]=0;
   if(!discard&&sscanf(command,"QRTEST BEGIN v=%u run=%16s diag=%d",&v,run,&enabled)>=2&&v==QRTEST_VERSION) {
    if(qr_diag_begin(run,enabled!=0,camera_now_us())==0){
     qr_tracker_init(&g_tracker);qr_decode_scheduler_reset(&g_decode_scheduler);g_last_full_scan_us=0;
     publication_reset();
     memset(g_seen,0,sizeof(g_seen));memset(g_window_seen,0,sizeof(g_window_seen));
     qr_osd_queue_init(&g_osd_queue);osd_publish();
    }
   } else if(!discard&&sscanf(command,"QRTEST END v=%u run=%16s",&v,run)==2&&v==QRTEST_VERSION&&qr_diag.active&&strcmp(run,qr_diag.run)==0) {
    while(qr_publication_pending(&g_publication)){publication_flush();qr_diag_pump(uart_write_nonblocking,1024);}
    qr_tracker_finish(&g_tracker,"test_end");diagnostic_tracker_totals();publication_totals();qr_diag_end(camera_now_us());
   }
   used=discard=0;
  } else if(byte!='\r') {if(used+1<sizeof(command))command[used++]=byte;else discard=1;}
 }
 qr_diag_pump(uart_write_nonblocking,256);
}
static void diagnostic_scan(const qr_quirc_fallback_profile_t *p,int full) {
 if(!qr_diag.active)return;
 qr_diag_count(full?QRD_FULL_SCAN:QRD_ROI_SCAN,p->identify_calls);
 qr_diag_count(QRD_GRIDS,p->grids_found+p->adaptive_grids_found);
 qr_diag_count(QRD_NO_GRID,p->no_grid_scans);
}

static uint32_t qr_read(uint32_t offset) {
    return Xil_In32(QR_REPLAY_QR_CORE_BASE + offset);
}

static void qr_write(uint32_t offset, uint32_t value) {
    Xil_Out32(QR_REPLAY_QR_CORE_BASE + offset, value);
}

static void gpio_write(UINTPTR base, uint32_t value) {
    Xil_Out32(base + 4U, 0U);
    Xil_Out32(base, value & 1U);
}

static uint64_t camera_now_us(void) {
    XTime ticks;
    XTime_GetTime(&ticks);
    return (uint64_t)ticks / ((uint64_t)COUNTS_PER_SECOND / 1000000U);
}

static void osd_event(void *context, const char *event, unsigned slot,
                      const qr_osd_entry_t *entry, uint64_t now_us) {
    (void)context;
    if (!diag_busy() && !QR_DIAG_COMPACT) xil_printf("OSD %s slot=%u track=%u time_us=%u payload=%s\r\n",
               event, slot, (unsigned)entry->track_id,
               (unsigned)now_us, entry->text);
}

static void osd_publish(void) {
    uint8_t *bank;
    char header[QR_OSD_TEXT_BYTES];
    uint32_t commit;
    unsigned row;
    g_osd_bank ^= 1U;
    bank = (uint8_t *)(QR_OSD_BRAM_BASE + (UINTPTR)g_osd_bank * 256U);
    memset(bank, ' ', 256U);
    snprintf(header, sizeof(header), "QR READ %03u  WAIT %02u",
             (unsigned)(g_osd_queue.read_count % 1000U),
             (unsigned)g_osd_queue.pending_count);
    memcpy(bank, header, strlen(header));
    for (row = 0U; row < g_osd_queue.visible_count; ++row)
        memcpy(bank + (row + 1U) * 32U, g_osd_queue.visible[row].text,
               strlen(g_osd_queue.visible[row].text));
    Xil_DCacheFlushRange((UINTPTR)bank, 256U);
    ++g_osd_sequence;
    commit = ((g_osd_sequence & 0x00FFFFFFU) << 8) |
             (((1U << g_osd_queue.visible_count) - 1U) << 4) | g_osd_bank;
    Xil_Out32(QR_OSD_COMMIT_GPIO_BASE + 4U, 0U);
    Xil_Out32(QR_OSD_COMMIT_GPIO_BASE, commit);
}

static int hdmi_iic_write(uint8_t address, uint8_t reg, uint8_t value) {
    uint8_t bytes[2] = {reg, value};
    return XIic_Send(QR_HDMI_IIC_BASE, address, bytes, 2U, XIIC_STOP) == 2U
         ? XST_SUCCESS : XST_FAILURE;
}

static int hdmi_init(void) {
    int main_status;
    int edid_status;
    if (XIic_DynInit(QR_HDMI_IIC_BASE) != XST_SUCCESS)
        return -20;
    main_status = hdmi_iic_write(0x39U, 0x08U, 0x35U);
    edid_status = hdmi_iic_write(0x3DU, 0x2FU, 0x00U);
    xil_printf("SIL9134 writes main=%d edid=%d\r\n",
               main_status, edid_status);
    return (main_status == XST_SUCCESS && edid_status == XST_SUCCESS)
         ? XST_SUCCESS : -21;
}

static void fill_color_bars(UINTPTR address) {
    static const uint16_t bars[8] = {
        0xFFFFU, 0xFFE0U, 0x07FFU, 0x07E0U,
        0xF81FU, 0xF800U, 0x001FU, 0x0000U
    };
    uint16_t *frame = (uint16_t *)address;
    uint32_t y;
    for (y = 0U; y < QR_HDMI_PREVIEW_HEIGHT; ++y) {
        uint32_t x;
        for (x = 0U; x < QR_HDMI_PREVIEW_WIDTH; ++x)
            frame[y * QR_HDMI_PREVIEW_WIDTH + x] =
                bars[(x * 8U) / QR_HDMI_PREVIEW_WIDTH];
    }
    Xil_DCacheFlushRange(address, QR_HDMI_FRAME_BYTES);
}

static void display_setup_defaults(XAxiVdma_DmaSetup *setup, int is_read) {
    memset(setup, 0, sizeof(*setup));
    setup->VertSizeInput = (int)QR_HDMI_PREVIEW_HEIGHT;
    setup->HoriSizeInput = (int)QR_HDMI_STRIDE;
    setup->Stride = (int)QR_HDMI_STRIDE;
    /* S2MM is the internal dynamic genlock master.  The 60-Hz MM2S slave
     * repeats a completed 30-fps camera frame instead of cycling into a
     * frame which S2MM is still writing.  FrameDelay is not used by the
     * dynamic genlock modes. */
    (void)is_read;
    setup->FrameDelay = 0;
    setup->EnableCircularBuf = 1;
    setup->EnableSync = !QR_HDMI_STATIC_TEST;
    setup->EnableFrameCounter = 0;
    setup->FixedFrameStoreAddr = 0;
    setup->GenLockRepeat = 0;
    setup->EnableVFlip = 0U;
}

static int display_vdma_start(void) {
    XAxiVdma_Config *config = XAxiVdma_LookupConfig(QR_DISPLAY_VDMA_LOOKUP_KEY);
    XAxiVdma_DmaSetup setup;
    UINTPTR addresses[XAXIVDMA_MAX_FRAMESTORE] = {0};
    int status;
    addresses[0] = QR_REPLAY_FRAME0;
    addresses[1] = QR_REPLAY_FRAME1;
    addresses[2] = QR_REPLAY_FRAME2;
    if (!config)
        return -30;
    status = XAxiVdma_CfgInitialize(&g_display_vdma, config,
                                    config->BaseAddress);
    if (status != XST_SUCCESS)
        return -31;
    if (XAxiVdma_GenLockSourceSelect(&g_display_vdma,
            XAXIVDMA_INTERNAL_GENLOCK, XAXIVDMA_READ) != XST_SUCCESS ||
        XAxiVdma_GenLockSourceSelect(&g_display_vdma,
            XAXIVDMA_INTERNAL_GENLOCK, XAXIVDMA_WRITE) != XST_SUCCESS)
        return -32;

    display_setup_defaults(&setup, 1);
    if (XAxiVdma_DmaConfig(&g_display_vdma, XAXIVDMA_READ, &setup) != XST_SUCCESS ||
        XAxiVdma_DmaSetBufferAddr(&g_display_vdma, XAXIVDMA_READ,
                                  addresses) != XST_SUCCESS)
        return -33;

#if !QR_HDMI_STATIC_TEST
    addresses[0] = QR_REPLAY_FRAME0;
    addresses[1] = QR_REPLAY_FRAME1;
    addresses[2] = QR_REPLAY_FRAME2;
    display_setup_defaults(&setup, 0);
    if (XAxiVdma_DmaConfig(&g_display_vdma, XAXIVDMA_WRITE, &setup) != XST_SUCCESS ||
        XAxiVdma_DmaSetBufferAddr(&g_display_vdma, XAXIVDMA_WRITE,
                                  addresses) != XST_SUCCESS ||
        XAxiVdma_DmaStart(&g_display_vdma, XAXIVDMA_WRITE) != XST_SUCCESS)
        return -34;
#endif

    /* Starting the capture master before the scanout slave avoids latching
     * the reader on an uninitialized writer frame pointer at boot. */
    if (XAxiVdma_DmaStart(&g_display_vdma, XAXIVDMA_READ) != XST_SUCCESS)
        return -35;

#if !QR_HDMI_STATIC_TEST
    /* The first camera frame may begin before S2MM reaches a SOF, causing a
     * harmless FSZ_MORE/VDMAIntErr latch.  PARK_PTR freezes its write-frame
     * status while that latch remains set, even after capture recovers.
     * Let the startup frame drain, then clear only W1C error/IRQ bits. */
    usleep(100000U);
    {
        uint32_t write_status = XAxiVdma_GetStatus(&g_display_vdma,
                                                   XAXIVDMA_WRITE);
        uint32_t sticky = write_status &
            (XAXIVDMA_SR_ERR_ALL_MASK | XAXIVDMA_IXR_ERROR_MASK);
        if (sticky != 0U)
            Xil_Out32(QR_HDMI_VDMA_BASE + 0x34U, sticky);
    }
#endif

    g_hdmi_mm2s_status = XAxiVdma_GetStatus(&g_display_vdma,
                                            XAXIVDMA_READ);
    g_hdmi_s2mm_status = XAxiVdma_GetStatus(&g_display_vdma,
                                            XAXIVDMA_WRITE);
    return XST_SUCCESS;
}

static int display_init(void) {
    int status;
    fill_color_bars(QR_REPLAY_FRAME0);
    fill_color_bars(QR_REPLAY_FRAME1);
    fill_color_bars(QR_REPLAY_FRAME2);
    status = hdmi_init();
    if (status != XST_SUCCESS)
        return status;
    return display_vdma_start();
}

static uint32_t elapsed_us(XTime start, XTime end) {
    return (uint32_t)(((uint64_t)(end - start) * 1000000ULL) /
                      COUNTS_PER_SECOND);
}

void qr_pipeline_cooperate(void) {
    qr_diag_pump(uart_write_nonblocking,128);
    if (g_net_ready)
        qr_replay_net_service();
}

static int continuous_capture_start(void) {
    XAxiVdma_Config *config = XAxiVdma_LookupConfig(QR_CAMERA_VDMA_LOOKUP_KEY);
    XAxiVdma_DmaSetup setup;
    UINTPTR addresses[XAXIVDMA_MAX_FRAMESTORE] = {0};
    uint32_t i;
    int status;

    if (!config)
        return -10;
    status = XAxiVdma_CfgInitialize(&g_vdma, config, config->BaseAddress);
    if (status != XST_SUCCESS || config->MaxFrameStoreNum < QR_GRAY_FRAME_COUNT)
        return -11;

    memset(&setup, 0, sizeof(setup));
    setup.VertSizeInput = (int)QR_CAPTURE_HEIGHT;
    setup.HoriSizeInput = (int)QR_DECODE_WIDTH;
    setup.Stride = (int)QR_DECODE_WIDTH;
    setup.EnableCircularBuf = 1;
    setup.EnableFrameCounter = 0;
    setup.FixedFrameStoreAddr = 0;
    for (i = 0U; i < QR_GRAY_FRAME_COUNT; ++i) {
        addresses[i] = g_gray_addresses[i];
        if (QR_CAMERA_PL_ROI) {
            /* Invalidate old-session guard records before enabling the writer. */
            memset((void *)addresses[i], 0, 64U);
            memset((void *)(addresses[i] + QR_DECODE_WIDTH * (QR_DECODE_HEIGHT + 1U)), 0, 64U);
            Xil_DCacheFlushRange(addresses[i], QR_CAPTURE_FRAME_BYTES);
        }
        Xil_DCacheInvalidateRange(addresses[i], QR_CAPTURE_FRAME_BYTES);
    }
    if (XAxiVdma_DmaConfig(&g_vdma, XAXIVDMA_WRITE, &setup) != XST_SUCCESS ||
        XAxiVdma_DmaSetBufferAddr(&g_vdma, XAXIVDMA_WRITE, addresses) != XST_SUCCESS)
        return -12;
    XAxiVdma_IntrClear(&g_vdma, XAXIVDMA_IXR_ALL_MASK, XAXIVDMA_WRITE);
    XAxiVdma_IntrEnable(&g_vdma, XAXIVDMA_IXR_FRMCNT_MASK,
                        XAXIVDMA_WRITE);

    /* PL finder coordinates always refer to the full camera geometry. */
    qr_write(0x00U, 0x02U);
    qr_write(0x08U, QR_REPLAY_WIDTH);
    qr_write(0x0CU, QR_REPLAY_HEIGHT);
    qr_write(0x10U, QR_CAMERA_PL_THRESHOLD);
    qr_write(0x18U, 1U);
    qr_write(0x2CU, 2U);
    qr_write(0x30U, 96U);
    qr_write(0x34U, QR_CAMERA_PL_ROI ? 128U : 160U);
    if (QR_CAMERA_PL_ROI) {
        XTime epoch_ticks;
        XTime_GetTime(&epoch_ticks);
        g_pl_epoch = (uint32_t)epoch_ticks ^ (uint32_t)(epoch_ticks >> 32);
        if (!g_pl_epoch) g_pl_epoch = 1U;
        qr_publication_rebase_frames(&g_publication);
        g_have_pl_seq = 0;
        qr_write(0x40U, (QR_CAMERA_PL_OTSU ? 1U : 0U) |
                          (QR_CAMERA_PL_GRAY_DIAGNOSTIC ? 0U : 2U));
        qr_write(0x44U, g_pl_epoch);
        qr_write(0x48U, g_pl_config_seq);
        /* Regional Otsu always covers all nine tiles of the complete frame.
         * Keep these legacy statistics registers at full-frame bounds too. */
        qr_write(0x4CU, 0U);
        qr_write(0x50U, 0U);
        qr_write(0x54U, QR_REPLAY_WIDTH);
        qr_write(0x58U, QR_REPLAY_HEIGHT);
    }
    qr_write(0x00U, 0x11U);

    status = XAxiVdma_DmaStart(&g_vdma, XAXIVDMA_WRITE);
    if (status != XST_SUCCESS)
        return -13;
    gpio_write(QR_CAMERA_ARM_GPIO_BASE, 1U);
    return XST_SUCCESS;
}

static int copy_latest_completed(uint32_t *buffer_index, XTime start) {
    uint32_t status;
    for (;;) {
        XTime now;
        status = XAxiVdma_GetStatus(&g_vdma, XAXIVDMA_WRITE);
        if ((status & XAXIVDMA_SR_ERR_ALL_MASK) != 0U)
            return -20;
        /* IOC is bit 12.  XAXIVDMA_FRMCNT_MASK is the unrelated bits 23:16
         * coalescing counter and may stay nonzero without any new frame. */
        if ((status & XAXIVDMA_IXR_FRMCNT_MASK) != 0U)
            break;
        qr_pipeline_cooperate();
        XTime_GetTime(&now);
        if (elapsed_us(start, now) >= QR_CAMERA_FRAME_TIMEOUT_US)
            return -21;
    }

    /* Acknowledge the event before copying, so a later completion is not
     * accidentally consumed as part of this frame. */
    XAxiVdma_IntrClear(&g_vdma, XAXIVDMA_IXR_FRMCNT_MASK,
                       XAXIVDMA_WRITE);
    {
        uint32_t current = XAxiVdma_CurrFrameStore(&g_vdma, XAXIVDMA_WRITE);
        uint32_t completed;
        if (current >= QR_GRAY_FRAME_COUNT)
            return -22;
        completed = (current + QR_GRAY_FRAME_COUNT - 1U) % QR_GRAY_FRAME_COUNT;
        Xil_DCacheInvalidateRange(g_gray_addresses[completed], QR_GRAY_FRAME_BYTES);
        memcpy(g_decode_image, (const void *)g_gray_addresses[completed],
               QR_GRAY_FRAME_BYTES);
        /* Reject the snapshot if the DMA wrapped onto its source slot while
         * the CPU was copying it.  The next IOC selects a fresh completed
         * frame without ever decoding a potentially torn snapshot. */
        if (XAxiVdma_CurrFrameStore(&g_vdma, XAXIVDMA_WRITE) == completed)
            return -23;
        *buffer_index = completed;
    }
    return 0;
}

#if QR_CAMERA_GRAY_DIVISOR == 2U
/* Reuse the latest completed HDMI RGB565 frame as a higher-resolution rescue
 * source.  Uniform 4:3 decimation preserves the 16:9 geometry while retaining
 * substantially more QR module detail than the PL 2:1 fast stream. */
static int copy_latest_display_gray(uint32_t *buffer_index) {
    const uint16_t *source;
    uint32_t current;
    uint32_t completed;
    uint32_t x;
    uint32_t y;

    if (!g_display_ready)
        return -30;
    if ((XAxiVdma_GetStatus(&g_display_vdma, XAXIVDMA_WRITE) &
         XAXIVDMA_SR_ERR_ALL_MASK) != 0U)
        return -32;
    current = XAxiVdma_CurrFrameStore(&g_display_vdma, XAXIVDMA_WRITE);
    if (current >= QR_GRAY_FRAME_COUNT)
        return -31;
    completed = (current + QR_GRAY_FRAME_COUNT - 1U) % QR_GRAY_FRAME_COUNT;
    Xil_DCacheInvalidateRange(g_display_addresses[completed],
                              QR_HDMI_FRAME_BYTES);
    source = (const uint16_t *)g_display_addresses[completed];
    for (y = 0U; y < QR_RESCUE_HEIGHT; ++y) {
        if ((y & 15U)==0U) qr_pipeline_cooperate();
        uint32_t source_y = QR_RESCUE_SOURCE_Y(y);
        for (x = 0U; x < QR_RESCUE_WIDTH; ++x) {
            uint32_t source_x = QR_RESCUE_SOURCE_X(x);
            uint32_t pixel = source[source_y * QR_HDMI_PREVIEW_WIDTH + source_x];
            uint32_t r5 = (pixel >> 11) & 0x1FU;
            uint32_t g6 = (pixel >> 5) & 0x3FU;
            uint32_t b5 = pixel & 0x1FU;
            uint32_t r8 = (r5 << 3) | (r5 >> 2);
            uint32_t g8 = (g6 << 2) | (g6 >> 4);
            uint32_t b8 = (b5 << 3) | (b5 >> 2);
            g_fullres_image[y * QR_RESCUE_WIDTH + x] =
                (uint8_t)((r8 * 77U + g8 * 150U + b8 * 29U) >> 8);
        }
    }
    if (XAxiVdma_CurrFrameStore(&g_display_vdma, XAXIVDMA_WRITE) == completed)
        return -33;
    *buffer_index = completed;
    return 0;
}
#endif

static int read_pl_candidates(uint32_t decode_width, uint32_t decode_height) {
    uint32_t completed_frame;
    uint32_t count;
    uint32_t index;
    unsigned attempt;
    float scale_x = (float)decode_width / (float)QR_REPLAY_WIDTH;
    float scale_y = (float)decode_height / (float)QR_REPLAY_HEIGHT;
    g_snapshot_valid=0;
    for (attempt = 0U; attempt < 3U; ++attempt) {
        int accepted = 0;
        completed_frame = qr_read(0x38U);
        count = qr_read(0x14U);
        if (count > QR_MAX_CANDIDATES)
            count = QR_MAX_CANDIDATES;
        for (index = 0U; index < count; ++index) {
            uint32_t base = 0x1000U + index * 16U;
            uint32_t frame_id = qr_read(base);
            uint32_t xy;
            uint32_t score_module;
            if (frame_id != completed_frame)
                continue;
            xy = qr_read(base + 4U);
            score_module = qr_read(base + 8U);
            g_pl_candidates[accepted].x = (float)(xy & 0xFFFFU) * scale_x;
            g_pl_candidates[accepted].y = (float)(xy >> 16) * scale_y;
            g_pl_candidates[accepted].module_size =
                ((float)(score_module & 0xFFFFU) / 256.0f) *
                (0.5f * (scale_x + scale_y));
            g_pl_candidates[accepted].score = (float)(score_module >> 16);
            ++accepted;
        }
        /* A new completed frame can replace the published bank mid-read.
         * A mismatched snapshot must never guide a moving-frame ROI. */
        if (qr_read(0x38U) == completed_frame && (unsigned)accepted==count && completed_frame!=0U) {
            g_snapshot_valid=1;return accepted;
        }
    }
    return 0;
}

static uint32_t payload_hash(const char *payload) {
    uint32_t hash = 2166136261U;
    while (*payload) {
        hash ^= (uint8_t)*payload++;
        hash *= 16777619U;
    }
    return hash;
}

static int record_payload(const char *payload, uint32_t frame_id) {
    uint32_t hash = payload_hash(payload);
    uint32_t i;
    for (i = 0U; i < QR_SEEN_CAPACITY; ++i) {
        if (g_seen[i].valid && g_seen[i].hash == hash &&
            strncmp(g_seen[i].payload, payload, QR_SEEN_PAYLOAD_BYTES) == 0) {
            g_seen[i].last_frame = frame_id;
            ++g_duplicate_total;
            return 0;
        }
    }
    i = g_seen_next++ % QR_SEEN_CAPACITY;
    g_seen[i].hash = hash;
    g_seen[i].last_frame = frame_id;
    g_seen[i].valid = 1U;
    strncpy(g_seen[i].payload, payload, QR_SEEN_PAYLOAD_BYTES - 1U);
    g_seen[i].payload[QR_SEEN_PAYLOAD_BYTES - 1U] = 0;
    ++g_unique_total;
    return 1;
}

static void record_window_payload(const char *payload, uint32_t frame_id) {
    uint32_t hash = payload_hash(payload);
    uint32_t i;
    ++g_window_decoded_total;
    for (i = 0U; i < QR_SEEN_CAPACITY; ++i) {
        if (g_window_seen[i].valid && g_window_seen[i].hash == hash &&
            strncmp(g_window_seen[i].payload, payload,
                    QR_SEEN_PAYLOAD_BYTES) == 0) {
            g_window_seen[i].last_frame = frame_id;
            return;
        }
    }
    i = g_window_seen_next++ % QR_SEEN_CAPACITY;
    g_window_seen[i].hash = hash;
    g_window_seen[i].last_frame = frame_id;
    g_window_seen[i].valid = 1U;
    strncpy(g_window_seen[i].payload, payload, QR_SEEN_PAYLOAD_BYTES - 1U);
    g_window_seen[i].payload[QR_SEEN_PAYLOAD_BYTES - 1U] = 0;
    ++g_window_unique_total;
}

static void emit_result(uint32_t frame_id, int status, uint32_t source_buffer,
                        uint32_t decode_width, uint32_t decode_height,
                        uint32_t pipeline_us, uint32_t total_us) {
    static char payload[QR_MAX_INSTANCES * QR_MAX_PAYLOAD];
    uint32_t length = 0U;
    uint32_t i;
    payload[0] = 0;
    for (i = 0U; i < g_result.instance_count; ++i) {
        uint32_t n = (uint32_t)strlen(g_result.instances[i].payload);
        int unique = record_payload(g_result.instances[i].payload, frame_id);
        record_window_payload(g_result.instances[i].payload, frame_id);
        ++g_decoded_total;
        if (length + n + (i ? 1U : 0U) < sizeof(payload)) {
            if (i)
                payload[length++] = '\n';
            memcpy(payload + length, g_result.instances[i].payload, n);
            length += n;
            payload[length] = 0;
        }
        if (unique && !diag_busy() && !QR_DIAG_COMPACT)
            xil_printf("QR NEW frame=%u %s\r\n", (unsigned)frame_id,
                       g_result.instances[i].payload);
    }

    ++g_camera_diagnostics.sequence;
    g_camera_diagnostics.frame_id = frame_id;
    g_camera_diagnostics.status = status;
    g_camera_diagnostics.stage = (uint32_t)g_result.stage;
    g_camera_diagnostics.instances = g_result.instance_count;
    g_camera_diagnostics.pipeline_us = pipeline_us;
    g_camera_diagnostics.total_us = total_us;
    for (i = 0U; i + 1U < sizeof(g_camera_diagnostics.payload) && payload[i]; ++i)
        g_camera_diagnostics.payload[i] = payload[i];
    g_camera_diagnostics.payload[i] = 0;
    g_camera_diagnostics.decoder_mode = QR_CAMERA_PL_ROI ?
        (QR_CAMERA_PL_GRAY_DIAGNOSTIC ? 6U : 5U) : QR_CAMERA_GRAY_DIVISOR == 1U ?
        QR_DECODER_MODE_QUIRC_FULL_GRAY : QR_DECODER_MODE_QUIRC_MULTIRES;
    g_camera_diagnostics.processed_frames = g_processed_frames;
    g_camera_diagnostics.capture_errors = g_capture_errors;
    g_camera_diagnostics.decoded_total = g_decoded_total;
    g_camera_diagnostics.unique_total = g_unique_total;
    g_camera_diagnostics.duplicate_total = g_duplicate_total;
    g_camera_diagnostics.source_buffer = source_buffer;
    g_camera_diagnostics.decode_width = decode_width;
    g_camera_diagnostics.decode_height = decode_height;
    g_camera_diagnostics.grids_found = g_fallback_profile.grids_found;
    g_camera_diagnostics.adaptive_retry = g_fallback_profile.adaptive_retry;
    g_camera_diagnostics.adaptive_grids_found =
        g_fallback_profile.adaptive_grids_found;
    g_camera_diagnostics.success_frames = g_success_frames;
    g_camera_diagnostics.pipeline_min_us = g_pipeline_min_us;
    g_camera_diagnostics.pipeline_max_us = g_pipeline_max_us;
    g_camera_diagnostics.pipeline_sum_us_low = (uint32_t)g_pipeline_sum_us;
    g_camera_diagnostics.pipeline_sum_us_high =
        (uint32_t)(g_pipeline_sum_us >> 32);
    g_camera_diagnostics.fullres_frames = g_fullres_frames;
    g_camera_diagnostics.fullres_success_frames = g_fullres_success_frames;
    g_camera_diagnostics.lowres_success_frames = g_lowres_success_frames;
    g_camera_diagnostics.capture_us_low = (uint32_t)g_perf.capture_us;
    g_camera_diagnostics.capture_us_high = (uint32_t)(g_perf.capture_us >> 32);
    g_camera_diagnostics.rescue_us_low = (uint32_t)g_perf.rescue_us;
    g_camera_diagnostics.rescue_us_high = (uint32_t)(g_perf.rescue_us >> 32);
    g_camera_diagnostics.candidate_us_low = (uint32_t)g_perf.candidate_us;
    g_camera_diagnostics.candidate_us_high = (uint32_t)(g_perf.candidate_us >> 32);
    g_camera_diagnostics.roi_us_low = (uint32_t)g_perf.roi_us;
    g_camera_diagnostics.roi_us_high = (uint32_t)(g_perf.roi_us >> 32);
    g_camera_diagnostics.full_us_low = (uint32_t)g_perf.full_us;
    g_camera_diagnostics.full_us_high = (uint32_t)(g_perf.full_us >> 32);
    g_camera_diagnostics.roi_calls = g_perf.roi_calls;
    g_camera_diagnostics.full_calls = g_perf.full_calls;
    g_camera_diagnostics.adaptive_calls = g_perf.adaptive_calls;
    g_camera_diagnostics.roi_pixels_low = (uint32_t)g_perf.roi_pixels;
    g_camera_diagnostics.roi_pixels_high = (uint32_t)(g_perf.roi_pixels >> 32);
    g_camera_diagnostics.full_pixels_low = (uint32_t)g_perf.full_pixels;
    g_camera_diagnostics.full_pixels_high = (uint32_t)(g_perf.full_pixels >> 32);
    g_camera_diagnostics.quirc_copy_us_low = (uint32_t)g_perf.quirc_copy_us;
    g_camera_diagnostics.quirc_copy_us_high = (uint32_t)(g_perf.quirc_copy_us >> 32);
    g_camera_diagnostics.quirc_adaptive_us_low = (uint32_t)g_perf.quirc_adaptive_us;
    g_camera_diagnostics.quirc_adaptive_us_high = (uint32_t)(g_perf.quirc_adaptive_us >> 32);
    g_camera_diagnostics.quirc_identify_us_low = (uint32_t)g_perf.quirc_identify_us;
    g_camera_diagnostics.quirc_identify_us_high = (uint32_t)(g_perf.quirc_identify_us >> 32);
    g_camera_diagnostics.quirc_decode_us_low = (uint32_t)g_perf.quirc_decode_us;
    g_camera_diagnostics.quirc_decode_us_high = (uint32_t)(g_perf.quirc_decode_us >> 32);
    g_camera_diagnostics.regions_seen = g_perf.regions_seen;
    g_camera_diagnostics.capstones_seen = g_perf.capstones_seen;
    g_camera_diagnostics.max_regions = g_perf.max_regions;
    g_camera_diagnostics.max_capstones = g_perf.max_capstones;
    g_camera_diagnostics.pl_nonempty_frames = g_perf.pl_nonempty_frames;
    g_camera_diagnostics.pl_triple_frames = g_perf.pl_triple_frames;
    g_camera_diagnostics.roi_success_frames = g_perf.roi_success_frames;
    g_camera_diagnostics.full_success_frames = g_perf.full_success_frames;
    g_camera_diagnostics.window_unique_total = g_window_unique_total;
    g_camera_diagnostics.window_decoded_total = g_window_decoded_total;
    g_camera_diagnostics.window_reset_ack = g_window_reset_ack;
    g_camera_diagnostics.track_created = g_tracker.created;
    g_camera_diagnostics.track_retries = g_tracker.retries;
    g_camera_diagnostics.track_decoded_skips = g_tracker.decoded_skips;
    g_camera_diagnostics.track_ambiguous = g_tracker.ambiguous;
    g_camera_diagnostics.track_retired = g_tracker.retired;
    g_camera_diagnostics.full_scan_suppressed = g_tracker.full_scan_suppressed;
    g_camera_diagnostics.osd_read_count = g_osd_queue.read_count;
    g_camera_diagnostics.osd_overflow_count = g_osd_queue.overflow_count;
    g_camera_diagnostics.osd_revision = g_osd_queue.revision;
    ++g_camera_diagnostics.sequence;

    if (!diag_busy() && !QR_DIAG_COMPACT) xil_printf("QR quirc frame=%u status=%d instances=%u unique_total=%u "
               "pipeline_us=%u total_us=%u buffer=%u grids=%u adaptive=%u\r\n",
               (unsigned)frame_id, status,
               (unsigned)g_result.instance_count, (unsigned)g_unique_total,
               (unsigned)pipeline_us, (unsigned)total_us,
               (unsigned)source_buffer,
               (unsigned)g_fallback_profile.grids_found,
               (unsigned)g_fallback_profile.adaptive_retry);
    if (g_net_ready)
        qr_replay_publish_result(frame_id, status, (uint32_t)g_result.stage,
                                 g_result.instance_count, payload,
                                 pipeline_us, total_us);
}

/* A finder can produce several near-identical geometric hypotheses.  Only
 * suppress a hypothesis if all three centres match a previously scanned
 * hypothesis; distinct neighbouring symbols cannot meet that condition. */
static int same_finder_triple(const qr_finder_triple_t *a,
                              const qr_finder_triple_t *b) {
    unsigned i, j;
    unsigned matched = 0U;
    for (i = 0U; i < 3U; ++i) {
        float radius = a->finder[i].module_size * 4.0f;
        int match = 0;
        if (radius < 4.0f)
            radius = 4.0f;
        for (j = 0U; j < 3U; ++j) {
            float dx = a->finder[i].x - b->finder[j].x;
            float dy = a->finder[i].y - b->finder[j].y;
            if (dx * dx + dy * dy <= radius * radius) {
                match = 1;
                break;
            }
        }
        matched += (unsigned)match;
    }
    return matched == 3U;
}

static qr_track_observation_t triple_observation(
        const qr_finder_triple_t *triple, const qr_frame_view_t *frame,
        uint32_t frame_id) {
    qr_track_observation_t observation;
    float module_sum = 0.0f;
    float edge_margin;
    unsigned i;
    memset(&observation, 0, sizeof(observation));
    float sx = (float)QR_REPLAY_WIDTH / (float)frame->width;
    float sy = (float)QR_REPLAY_HEIGHT / (float)frame->height;
    float dx1 = triple->finder[0].x - triple->finder[1].x;
    float dy1 = triple->finder[0].y - triple->finder[1].y;
    float dx2 = triple->finder[0].x - triple->finder[2].x;
    float dy2 = triple->finder[0].y - triple->finder[2].y;
    observation.x = (triple->finder[0].x + triple->finder[1].x +
                     triple->finder[2].x) * sx / 3.0f;
    observation.y = (triple->finder[0].y + triple->finder[1].y +
                     triple->finder[2].y) * sy / 3.0f;
    observation.size = 1.45f *
        (sqrtf(dx1 * dx1 + dy1 * dy1) + sqrtf(dx2 * dx2 + dy2 * dy2)) *
        0.5f * (sx + sy) * 0.5f;
    observation.sharpness = (triple->finder[0].score +
                             triple->finder[1].score +
                             triple->finder[2].score) / 3.0f;
    observation.frame_id = frame_id;
    for (i = 0U; i < 3U; ++i) {
        observation.finder_x[i] = triple->finder[i].x * sx;
        observation.finder_y[i] = triple->finder[i].y * sy;
        module_sum += triple->finder[i].module_size;
    }
    observation.module_size = module_sum * (sx + sy) / 6.0f;
    observation.finder_valid = observation.module_size > 0.0f;
    edge_margin = fmaxf(4.0f, 2.0f * observation.module_size);
    observation.geometry_reliable = observation.finder_valid;
    for (i = 0U; i < 3U; ++i)
        if (observation.finder_x[i] < edge_margin ||
            observation.finder_y[i] < edge_margin ||
            observation.finder_x[i] > (float)QR_REPLAY_WIDTH - edge_margin ||
            observation.finder_y[i] > (float)QR_REPLAY_HEIGHT - edge_margin)
            observation.geometry_reliable = 0U;
    return observation;
}

static qr_track_observation_t instance_observation(
        const qr_instance_t *instance, const qr_frame_view_t *frame,
        uint32_t frame_id) {
    qr_track_observation_t observation;
    float leg_average;
    float module_span;
    memset(&observation, 0, sizeof(observation));
    float sx = (float)QR_REPLAY_WIDTH / (float)frame->width;
    float sy = (float)QR_REPLAY_HEIGHT / (float)frame->height;
    float dx1 = instance->finder_tl_x - instance->finder_tr_x;
    float dy1 = instance->finder_tl_y - instance->finder_tr_y;
    float dx2 = instance->finder_tl_x - instance->finder_bl_x;
    float dy2 = instance->finder_tl_y - instance->finder_bl_y;
    observation.x = (instance->finder_tl_x + instance->finder_tr_x +
                     instance->finder_bl_x) * sx / 3.0f;
    observation.y = (instance->finder_tl_y + instance->finder_tr_y +
                     instance->finder_bl_y) * sy / 3.0f;
    observation.size = 1.45f *
        (sqrtf(dx1 * dx1 + dy1 * dy1) + sqrtf(dx2 * dx2 + dy2 * dy2)) *
        0.5f * (sx + sy) * 0.5f;
    observation.sharpness = 1.0f;
    observation.frame_id = frame_id;
    observation.finder_x[0] = instance->finder_tl_x * sx;
    observation.finder_y[0] = instance->finder_tl_y * sy;
    observation.finder_x[1] = instance->finder_tr_x * sx;
    observation.finder_y[1] = instance->finder_tr_y * sy;
    observation.finder_x[2] = instance->finder_bl_x * sx;
    observation.finder_y[2] = instance->finder_bl_y * sy;
    leg_average = 0.5f * (sqrtf(dx1 * dx1 + dy1 * dy1) +
                                sqrtf(dx2 * dx2 + dy2 * dy2));
    module_span = instance->module_count > 7 ?
        (float)(instance->module_count - 7) : 0.0f;
    observation.module_size = module_span > 0.0f ?
        leg_average * (sx + sy) * 0.5f / module_span : 0.0f;
    observation.finder_valid = observation.module_size > 0.0f;
    observation.geometry_reliable = observation.finder_valid;
    return observation;
}

/* Keep successful-result association distinct from the ROI decode context.
 * The sequence links this record to the later publish gate without repeating
 * two potentially 1023-byte payloads in one bounded diagnostic line. */
static uint32_t diagnostic_result_association(
        uint32_t frame_id, uint32_t roi_track,
        const qr_track_observation_t *observation,
        const qr_track_decision_t *decision, int observe_rc,uint32_t payload_conflicts,
        const char *payload) {
    char fields[2600], hex[2 * QR_MAX_PAYLOAD + 1];
    if (!qr_diag_detail_enabled()) return 0;
    qr_diag_payload_hex((const uint8_t *)payload, strlen(payload), hex, sizeof(hex));
    qr_diag.now_us = camera_now_us();
    snprintf(fields, sizeof(fields),
             "result_frame=%lu roi_track=%lu result_track=%lu observe_rc=%d "
             "mark_called=%d created=%u already_decoded=%u ambiguous=%u payload_conflicts=%lu "
             "x_q8=%ld y_q8=%ld size_q8=%ld payload_hex=%s",
             (unsigned long)frame_id, (unsigned long)roi_track,
             (unsigned long)decision->track_id, observe_rc, observe_rc == 0,
             (unsigned)decision->created, (unsigned)decision->already_decoded,
             (unsigned)decision->ambiguous,(unsigned long)payload_conflicts,
             (long)(observation->x * 256.0f), (long)(observation->y * 256.0f),
             (long)(observation->size * 256.0f), hex);
    qr_diag_emit("result_assoc", fields);
    return qr_diag.seq;
}

static int mark_and_diagnose_tracker(uint32_t track_id, uint32_t frame_id,
                                     const char *payload, uint64_t now_us,
                                     uint32_t association_seq) {
    char fields[2400], old_hex[2 * QR_TRACKER_PAYLOAD_BYTES + 1];
    qr_track_t *track = qr_tracker_find(&g_tracker, track_id);
    int old_decoded = track ? track->decoded : -1;
    int enabled = qr_diag_detail_enabled();
    int mark_rc;
    if (enabled)
        qr_diag_payload_hex((const uint8_t *)(track ? track->payload : ""),
                            track ? strlen(track->payload) : 0,
                            old_hex, sizeof(old_hex));
    mark_rc = qr_tracker_mark_attempt(&g_tracker, track_id, now_us, 1, payload);
    if (enabled) {
        qr_diag.now_us = camera_now_us();
        snprintf(fields, sizeof(fields),
                 "association_seq=%lu result_frame=%lu result_track=%lu "
                 "mark_rc=%d old_decoded=%d tracker_new_decoded=%d old_payload_hex=%s",
                 (unsigned long)association_seq, (unsigned long)frame_id,
                 (unsigned long)track_id, mark_rc, old_decoded, mark_rc == 1,
                 old_hex);
        qr_diag_emit("tracker_mark", fields);
    }
    return mark_rc;
}

static void publication_reset(void) {
    qr_publication_init(&g_publication);
#if QR_CAMERA_PL_ROI
#if QR_REPLAY_PROFILE == QR_REPLAY_PROFILE_800X600_48FPS
    g_publication.frame_period_s=1.0f/48.0f;
#endif
#else
    /* Legacy frame IDs count processed frames, not native camera frames. */
    g_publication.frame_period_s=0;
#endif
    memset(g_publication_jobs,0,sizeof(g_publication_jobs));
    g_publication_retries=g_publication_faults=g_publication_fallbacks=0;
    g_publication_compute_us=0;g_publication_max_us=0;
}

static void publication_totals(void) {
    char fields[600];
    if(!qr_diag.active)return;
    qr_diag.now_us=camera_now_us();
    snprintf(fields,sizeof(fields),"created=%lu same_entity=%lu committed=%lu "
             "cache_evictions=%lu full_pending=%lu pending_entities=%u "
             "enqueue_retries=%lu faults=%lu capacity_fallback_outputs=%lu "
             "compute_us=%llu compute_max_us=%lu osd_read=%lu osd_overflow=%lu",
             (unsigned long)g_publication.created,(unsigned long)g_publication.duplicates,
             (unsigned long)g_publication.committed,(unsigned long)g_publication.evictions,
             (unsigned long)g_publication.full_pending,qr_publication_pending(&g_publication),
             (unsigned long)g_publication_retries,(unsigned long)g_publication_faults,
             (unsigned long)g_publication_fallbacks,(unsigned long long)g_publication_compute_us,
             (unsigned long)g_publication_max_us,(unsigned long)g_osd_queue.read_count,
             (unsigned long)g_osd_queue.overflow_count);
    qr_diag_emit("publication_summary",fields);
}

static void publication_send(unsigned slot) {
    /* Static scratch avoids nesting large payload-format buffers on the A9 stack. */
    static char line[1200],fields[2500],hex[2*QR_PUBLICATION_PAYLOAD_BYTES+1];
    qr_publication_entry_t *entry=&g_publication.entries[slot];
    const qr_publication_job_t *job=&g_publication_jobs[slot];
    uint64_t now=camera_now_us();int accepted;
    if(entry->state!=QR_PUB_PENDING)return;
    if(qr_diag.active||qr_diag.ending){
        uint32_t saved_frame=qr_diag.frame;
        qr_diag_payload_hex((const uint8_t *)entry->payload,entry->length,hex,sizeof(hex));
        snprintf(fields,sizeof(fields),"track=%lu output_id=%lu result_track=%lu roi_track=%lu "
                 "association_seq=%lu observe_rc=%d source=%s payload_hex=%s",
                 (unsigned long)entry->id,(unsigned long)entry->id,
                 (unsigned long)job->result_track,(unsigned long)job->roi_track,
                 (unsigned long)job->association_seq,job->observe_rc,job->source,hex);
        snprintf(line,sizeof(line),"QR TRACK event=decoded track=%u frame=%u source=%s payload=%s\r\n",
                 (unsigned)entry->id,(unsigned)job->frame,job->source,entry->payload);
        qr_diag.now_us=now;qr_diag.frame=job->frame;
        accepted=qr_diag_try_business(fields,line);qr_diag.frame=saved_frame;
    }else if(qr_diag_queued())accepted=0;
    else{
        xil_printf("QR TRACK event=decoded track=%u frame=%u source=%s payload=%s\r\n",
                   (unsigned)entry->id,(unsigned)job->frame,job->source,entry->payload);
        accepted=1;
    }
    if(accepted!=1){g_publication_retries++;
        if(accepted<0){g_publication_faults++;qr_diag.dropped++;}return;}
    if(qr_publication_commit(&g_publication,slot,entry->id)){g_publication_faults++;return;}
    if(job->observe_rc==-1)g_publication_fallbacks++;
    qr_osd_queue_enqueue(&g_osd_queue,entry->id,entry->payload,now,osd_event,0);
    osd_publish();
}

static void publication_flush(void) {
    unsigned i;
    for(i=0;i<QR_PUBLICATION_CAPACITY;i++)
        if(g_publication.entries[i].state==QR_PUB_PENDING)publication_send(i);
}

static void validate_tracker_publications(uint64_t now_us) {
    unsigned i;
    for (i = 0U; i < QR_TRACKER_CAPACITY; ++i) {
        qr_track_t *track = &g_tracker.tracks[i];
        if (track->active && track->publication_id &&
            !qr_publication_identity_live(&g_publication,
                                          track->publication_id, now_us))
            qr_tracker_invalidate_publication(&g_tracker, track->id);
    }
}

static void handle_success_instance(uint32_t frame_id,uint32_t roi_track,
                                    const qr_instance_t *instance,const qr_frame_view_t *frame,
                                    const char *source,uint64_t sample_us) {
    qr_track_observation_t observation=instance_observation(instance,frame,frame_id);
    qr_publication_observation_t pub_observation;
    qr_track_decision_t decision;
    uint64_t started;uint32_t elapsed,association_seq,conflicts;unsigned slot=0;
    int action,observe_rc,mark_rc=-1;
    pub_observation.x=observation.x;pub_observation.y=observation.y;
    pub_observation.size=observation.size;pub_observation.frame=frame_id;
    pub_observation.sample_us=sample_us;pub_observation.now_us=camera_now_us();
    started=camera_now_us();
    action=qr_publication_prepare(&g_publication,instance->payload,strlen(instance->payload),&pub_observation,&slot);
    elapsed=(uint32_t)(camera_now_us()-started);g_publication_compute_us+=elapsed;
    if(elapsed>g_publication_max_us)g_publication_max_us=elapsed;
    while(action==QR_PUB_FULL){
        publication_flush();qr_diag_pump(uart_write_nonblocking,1024);qr_pipeline_cooperate();
        pub_observation.now_us=camera_now_us();
        action=qr_publication_prepare(&g_publication,instance->payload,strlen(instance->payload),&pub_observation,&slot);
    }
    if(action<0){g_publication_faults++;qr_diag.dropped++;return;}
    conflicts=g_tracker.payload_conflicts;
    observe_rc=qr_tracker_observe_success(&g_tracker,&observation,sample_us,instance->payload,&decision);
    association_seq=diagnostic_result_association(frame_id,roi_track,&observation,&decision,observe_rc,
                                                g_tracker.payload_conflicts-conflicts,instance->payload);
    if(observe_rc==0)mark_rc=mark_and_diagnose_tracker(decision.track_id,frame_id,instance->payload,sample_us,association_seq);
    if(action==QR_PUB_NEW){
        qr_publication_job_t *job=&g_publication_jobs[slot];
        job->frame=frame_id;job->roi_track=roi_track;job->result_track=decision.track_id;
        job->association_seq=association_seq;job->observe_rc=observe_rc;job->source=source;
    }
    if(action!=QR_PUB_DUPLICATE)publication_send(slot);
    if(observe_rc==0&&decision.track_id&&
       g_publication.entries[slot].state!=QR_PUB_UNUSED)
        qr_tracker_bind_publication(&g_tracker,decision.track_id,
                                    g_publication.entries[slot].id);
    {
        qr_trace_record_t *r=qr_trace_add(QRT_TRACK);
        if(r){r->w[0]=qr_trace_roi_index();r->w[1]=decision.track_id;r->w[2]=4;
            r->w[3]=g_publication.entries[slot].id;r->w[4]=(uint32_t)action;
            r->w[5]=(uint32_t)observe_rc;r->w[6]=(uint32_t)mark_rc;
            r->w[7]=g_publication.entries[slot].state;
        }
        trace_track(qr_tracker_find(&g_tracker,decision.track_id),2,sample_us);
    }
    if(qr_diag_detail_enabled()){
        char fields[350];qr_diag.now_us=camera_now_us();
        snprintf(fields,sizeof(fields),"association_seq=%lu output_id=%lu action=%d "
                 "result_track=%lu observe_rc=%d mark_rc=%d published=%d pending_entities=%u",
                 (unsigned long)association_seq,(unsigned long)g_publication.entries[slot].id,action,
                 (unsigned long)decision.track_id,observe_rc,mark_rc,
                 g_publication.entries[slot].state==QR_PUB_PUBLISHED,qr_publication_pending(&g_publication));
        qr_diag_emit("publish_decision",fields);
    }
}

static int capture_and_decode_legacy(uint32_t frame_id) {
    qr_frame_view_t frame;
    XTime total_start, segment_start, segment_end, pipeline_start, pipeline_end;
    uint32_t source_buffer = 0xFFFFFFFFU;
    uint32_t decode_width = QR_DECODE_WIDTH;
    uint32_t decode_height = QR_DECODE_HEIGHT;
    int use_fullres = (QR_CAMERA_GRAY_DIVISOR == 1U);
    int candidate_count;
    int triple_count;
    qr_locator_profile_t locator;
    int decoded;
    int status;
    uint64_t now_us;

    memset(&g_result, 0, sizeof(g_result));
    memset(&g_fallback_profile, 0, sizeof(g_fallback_profile));
    XTime_GetTime(&total_start);
    status = copy_latest_completed(&source_buffer, total_start);
    XTime_GetTime(&segment_end);
    g_perf.capture_us += elapsed_us(total_start, segment_end);
    if (status != 0) {
        ++g_capture_errors;qr_diag_count(QRD_CAPTURE_ERROR,1);
        return status;
    }
#if QR_CAMERA_GRAY_DIVISOR == 1U
    ++g_fullres_frames;
#endif

    /* Capture the completed PL candidate bank next to the gray VDMA IOC.
     * The optional HDMI-to-gray rescue copy can take most of one camera
     * period; reading candidates after it would pair moving pixels with the
     * following frame's finder positions. */
    XTime_GetTime(&segment_start);
    candidate_count = read_pl_candidates(QR_DECODE_WIDTH, QR_DECODE_HEIGHT);
    qr_diag_count(QRD_FRAMES,1);
    qr_diag.pl_status=qr_read(0x04U);
    qr_diag.vdma_status=XAxiVdma_GetStatus(&g_vdma,XAXIVDMA_WRITE);
    qr_diag_count(QRD_VDMA_ERROR,(qr_diag.vdma_status&0x770U)!=0);
    qr_diag_count(QRD_PL_OVERFLOW,(qr_diag.pl_status&4U)!=0);
    qr_diag_count(QRD_PL_AXIS_ERROR,(qr_diag.pl_status&8U)!=0);
    qr_diag_count(g_snapshot_valid?(candidate_count?QRD_PL_NONZERO:QRD_PL_ZERO):QRD_SNAPSHOT_INVALID,1);
    XTime_GetTime(&segment_end);
    g_perf.candidate_us += elapsed_us(segment_start, segment_end);

    frame.data = g_decode_image;
    frame.width = (int)QR_DECODE_WIDTH;
    frame.height = (int)QR_DECODE_HEIGHT;
    frame.stride = (int)QR_DECODE_WIDTH;
#if QR_CAMERA_GRAY_DIVISOR == 2U
    use_fullres = g_display_ready &&
                  ((frame_id % QR_FULLRES_RESCUE_PERIOD) == 0U);
    if (use_fullres) {
        uint32_t display_buffer;
        XTime_GetTime(&segment_start);
        status = copy_latest_display_gray(&display_buffer);
        XTime_GetTime(&segment_end);
        g_perf.rescue_us += elapsed_us(segment_start, segment_end);
        if (status == 0) {
            frame.data = g_fullres_image;
            frame.width = (int)QR_RESCUE_WIDTH;
            frame.height = (int)QR_RESCUE_HEIGHT;
            frame.stride = (int)QR_RESCUE_WIDTH;
            decode_width = QR_RESCUE_WIDTH;
            decode_height = QR_RESCUE_HEIGHT;
            source_buffer = 0x100U | display_buffer;
            ++g_fullres_frames;
            {
                const float x_scale = (float)QR_RESCUE_WIDTH /
                                      (float)QR_DECODE_WIDTH;
                const float y_scale = (float)QR_RESCUE_HEIGHT /
                                      (float)QR_DECODE_HEIGHT;
                const float module_scale = 0.5f * (x_scale + y_scale);
                int index;
                for (index = 0; index < candidate_count; ++index) {
                    g_pl_candidates[index].x *= x_scale;
                    g_pl_candidates[index].y *= y_scale;
                    g_pl_candidates[index].module_size *= module_scale;
                }
            }
        } else {
            use_fullres = 0;
        }
    }
#endif
    frame.pixel_format = QR_PIXEL_FORMAT_GRAY8;

    XTime_GetTime(&pipeline_start);
    now_us = camera_now_us();
    validate_tracker_publications(now_us);
    if (qr_osd_queue_update(&g_osd_queue, now_us, osd_event, 0))
        osd_publish();
    segment_start = pipeline_start;
    triple_count = qr_pipeline_find_triples_profiled(&frame, &g_config,
                                            g_pl_candidates,
                                            candidate_count,
                                            g_finder_triples,
                                            QR_FINDER_TRIPLE_LIMIT,&locator);
    if(g_snapshot_valid&&candidate_count>0){
      qr_diag_count(QRD_LOCATE_SCAN,1);
      qr_diag_count(QRD_VERTICAL,(uint32_t)locator.vertical_count);
      qr_diag_count(QRD_CENTERS,(uint32_t)locator.center_count);
      qr_diag_count(QRD_TRIPLES,(uint32_t)locator.triple_count);
      qr_diag_count(QRD_VERTICAL_FAIL,locator.stage==QR_STAGE_VERTICAL);
      qr_diag_count(QRD_CLUSTER_FAIL,locator.stage==QR_STAGE_CLUSTER);
      qr_diag_count(QRD_COMBINATION_FAIL,locator.stage==QR_STAGE_TRIPLE);
    }
    XTime_GetTime(&segment_end);
    g_perf.candidate_us += elapsed_us(segment_start, segment_end);
    g_pl_candidate_count = (uint32_t)candidate_count;
    g_pl_triple_count = (uint32_t)triple_count;
    if (candidate_count > 0)
        ++g_perf.pl_nonempty_frames;
    if (triple_count > 0)
        ++g_perf.pl_triple_frames;
    decoded = 0;
    if (triple_count > 0) {
        int triple_index;
        uint32_t scanned_mask = 0U;
        for (triple_index = 0; triple_index < triple_count &&
             g_result.instance_count < QR_MAX_INSTANCES; ++triple_index) {
            int found;
            int previous;
            int equivalent = 0;
            uint16_t instance_before;
            qr_track_observation_t observation;
            qr_track_decision_t track_decision;
            for (previous = 0; previous < triple_index; ++previous) {
                if ((scanned_mask & (1U << previous)) != 0U &&
                    same_finder_triple(&g_finder_triples[triple_index],
                                       &g_finder_triples[previous])) {
                    equivalent = 1;
                    break;
                }
            }
            if (equivalent) {
                ++g_skipped_equivalent_triples;
                continue;
            }
            scanned_mask |= 1U << triple_index;
            observation = triple_observation(&g_finder_triples[triple_index],
                                             &frame, frame_id);
            if (qr_tracker_observe(&g_tracker, &observation, now_us,
                                   &track_decision) != 0)
                continue;
            if (!track_decision.should_decode)
                continue;
            instance_before = g_result.instance_count;
            XTime_GetTime(&segment_start);
            g_diag_context_track=track_decision.track_id;
            qr_diag_context("roi",track_decision.track_id,track_decision.already_decoded);
            found = qr_quirc_fallback_run(
                &frame, g_finder_triples[triple_index].finder, 3,
                &g_config, &g_result, &g_fallback_profile);
            XTime_GetTime(&segment_end);
            diagnostic_scan(&g_fallback_profile,0);
            g_perf.roi_us += elapsed_us(segment_start, segment_end);
            g_perf.roi_pixels +=
                (uint64_t)g_fallback_profile.roi_width *
                g_fallback_profile.roi_height;
            ++g_perf.roi_calls;
            g_perf.adaptive_calls += g_fallback_profile.adaptive_retry;
            g_perf.quirc_copy_us += g_fallback_profile.copy_us;
            g_perf.quirc_adaptive_us += g_fallback_profile.adaptive_us;
            g_perf.quirc_identify_us += g_fallback_profile.identify_us;
            g_perf.quirc_decode_us += g_fallback_profile.decode_us;
            g_perf.regions_seen += g_fallback_profile.regions_seen;
            g_perf.capstones_seen += g_fallback_profile.capstones_seen;
            if (g_fallback_profile.max_regions > g_perf.max_regions)
                g_perf.max_regions = g_fallback_profile.max_regions;
            if (g_fallback_profile.max_capstones > g_perf.max_capstones)
                g_perf.max_capstones = g_fallback_profile.max_capstones;
            if (found > 0)
                decoded += found;
            if (found > 0 && g_result.instance_count > instance_before) {
                uint16_t new_index;
                for (new_index = instance_before;
                     new_index < g_result.instance_count; ++new_index) {
                    handle_success_instance(frame_id,track_decision.track_id,
                                            &g_result.instances[new_index],&frame,"roi",now_us);
                }
            } else {
                qr_tracker_mark_attempt(&g_tracker, track_decision.track_id,
                                        now_us, 0, 0);
            }
        }
    }
    if (decoded > 0)
        ++g_perf.roi_success_frames;
    if (decoded == 0 &&
        (g_last_full_scan_us == 0U || now_us - g_last_full_scan_us >= 500000U)) {
        uint16_t instance_before = g_result.instance_count;
        g_last_full_scan_us = now_us;
        XTime_GetTime(&segment_start);
        g_diag_context_track=0;qr_diag_context("full",0,0);
        decoded = qr_quirc_fallback_run(&frame, 0, 0, &g_config, &g_result,
                                        &g_fallback_profile);
        XTime_GetTime(&segment_end);
        diagnostic_scan(&g_fallback_profile,1);
        g_perf.full_us += elapsed_us(segment_start, segment_end);
        g_perf.full_pixels += (uint64_t)frame.width * frame.height;
        ++g_perf.full_calls;
        g_perf.adaptive_calls += g_fallback_profile.adaptive_retry;
        g_perf.quirc_copy_us += g_fallback_profile.copy_us;
        g_perf.quirc_adaptive_us += g_fallback_profile.adaptive_us;
        g_perf.quirc_identify_us += g_fallback_profile.identify_us;
        g_perf.quirc_decode_us += g_fallback_profile.decode_us;
        g_perf.regions_seen += g_fallback_profile.regions_seen;
        g_perf.capstones_seen += g_fallback_profile.capstones_seen;
        if (g_fallback_profile.max_regions > g_perf.max_regions)
            g_perf.max_regions = g_fallback_profile.max_regions;
        if (g_fallback_profile.max_capstones > g_perf.max_capstones)
            g_perf.max_capstones = g_fallback_profile.max_capstones;
        if (decoded > 0)
            ++g_perf.full_success_frames;
        if (decoded > 0) {
            uint16_t new_index;
            for (new_index = instance_before;
                 new_index < g_result.instance_count; ++new_index) {
                handle_success_instance(frame_id,0,&g_result.instances[new_index],&frame,"full",now_us);
            }
        }
    } else if (decoded == 0) {
        ++g_tracker.full_scan_suppressed;
    }
    XTime_GetTime(&pipeline_end);
    ++g_processed_frames;
    {
        uint32_t pipeline_us = elapsed_us(pipeline_start, pipeline_end);
        if (g_result.instance_count > 0U) {
            ++g_success_frames;
            if (use_fullres)
                ++g_fullres_success_frames;
            else
                ++g_lowres_success_frames;
        }
        if (pipeline_us < g_pipeline_min_us)
            g_pipeline_min_us = pipeline_us;
        if (pipeline_us > g_pipeline_max_us)
            g_pipeline_max_us = pipeline_us;
        g_pipeline_sum_us += pipeline_us;
        if(qr_diag.active)qr_diag.pipeline_us+=pipeline_us;
    }
    status = decoded < 0 ? decoded : 0;
    if (g_result.instance_count == 0U)
        g_result.stage = QR_STAGE_DECODE;
    emit_result(frame_id, status, source_buffer, decode_width, decode_height,
                elapsed_us(pipeline_start, pipeline_end),
                elapsed_us(total_start, pipeline_end));
    if (g_display_ready) {
        g_hdmi_mm2s_status = XAxiVdma_GetStatus(&g_display_vdma,
                                                XAXIVDMA_READ);
        g_hdmi_s2mm_status = XAxiVdma_GetStatus(&g_display_vdma,
                                                XAXIVDMA_WRITE);
    }
    return status;
}

/* Cache invalidation and ARM ordering barriers surround every shared-memory
 * observation. The bank generation is a seqlock, not an image-slot index. */
static void capture_barrier(void) {
    __asm__ volatile("dmb sy" ::: "memory");
}

static void read_guard(uint32_t slot, int footer, qr_pl_guard_t *record) {
    UINTPTR address = g_gray_addresses[slot] + (footer ?
        QR_DECODE_WIDTH * (QR_DECODE_HEIGHT + 1U) : 0U);
    Xil_DCacheInvalidateRange(address, sizeof(*record));
    capture_barrier();
    memcpy(record, (const void *)address, sizeof(*record));
    capture_barrier();
}

static void read_result_words(uint32_t base, void *record, unsigned words) {
    uint32_t *destination = (uint32_t *)record;
    unsigned i;
    capture_barrier();
    for (i = 0; i < words; ++i) destination[i] = qr_read(base + 4U * i);
    capture_barrier();
}

static int roi_snapshot_stable(const qr_camera_roi_snapshot_t *snapshot) {
    qr_pl_guard_t header, footer;
    qr_pl_bank_t bank;
    uint32_t dma = XAxiVdma_GetStatus(&g_vdma, XAXIVDMA_WRITE);
    if ((dma & XAXIVDMA_SR_ERR_ALL_MASK) ||
        XAxiVdma_CurrFrameStore(&g_vdma, XAXIVDMA_WRITE) == snapshot->slot)
        return 0;
    read_guard(snapshot->slot, 0, &header);
    read_guard(snapshot->slot, 1, &footer);
    read_result_words(snapshot->bank_offset, &bank, QR_PL_GUARD_WORDS);
    if (!qr_pl_guards_valid(&header, &footer, QR_DECODE_WIDTH, QR_DECODE_HEIGHT,
                            QR_CAMERA_PL_FORMAT, g_pl_epoch, g_pl_config_seq) ||
        !qr_pl_bank_matches(&bank, &header) ||
        memcmp(&header, &snapshot->header, sizeof(header)) ||
        memcmp(&footer, &snapshot->footer, sizeof(footer)) ||
        memcmp(&bank, &snapshot->bank, sizeof(bank)))
        return 0;
    capture_barrier();
    return !(XAxiVdma_GetStatus(&g_vdma, XAXIVDMA_WRITE) & XAXIVDMA_SR_ERR_ALL_MASK) &&
        XAxiVdma_CurrFrameStore(&g_vdma, XAXIVDMA_WRITE) != snapshot->slot;
}

static int read_roi_snapshot(uint32_t slot, qr_camera_roi_snapshot_t *snapshot) {
    unsigned b, i;
    if (XAxiVdma_CurrFrameStore(&g_vdma, XAXIVDMA_WRITE) == slot) return 0;
    snapshot->slot = slot;
    read_guard(slot, 0, &snapshot->header);
    read_guard(slot, 1, &snapshot->footer);
    if (!qr_pl_guards_valid(&snapshot->header, &snapshot->footer,
            QR_DECODE_WIDTH, QR_DECODE_HEIGHT, QR_CAMERA_PL_FORMAT,
            g_pl_epoch, g_pl_config_seq)) return 0;
    if (g_have_pl_seq && (int32_t)(snapshot->header.frame_seq - g_last_pl_seq) <= 0)
        return 0;
    for (b = 0; b < QR_PL_ROI_BANKS; ++b) {
        snapshot->bank_offset = QR_PL_BANK_BASE + b * QR_PL_BANK_STRIDE;
        read_result_words(snapshot->bank_offset, &snapshot->bank, QR_PL_GUARD_WORDS);
        if (!qr_pl_bank_matches(&snapshot->bank, &snapshot->header)) continue;
        for (i = 0; i < snapshot->bank.roi_count; ++i) {
            read_result_words(snapshot->bank_offset + QR_PL_BANK_DESC_BYTES +
                               i * QR_PL_ROI_BYTES, &snapshot->roi[i], QR_PL_GUARD_WORDS);
            if (!qr_pl_roi_valid(&snapshot->roi[i], QR_DECODE_WIDTH, QR_DECODE_HEIGHT))
                return 0;
        }
        return roi_snapshot_stable(snapshot);
    }
    return 0;
}

static int wait_pl_roi_snapshot(XTime start) {
    for (;;) {
        unsigned slot;
        int found = 0;
        XTime now;
        uint32_t dma = XAxiVdma_GetStatus(&g_vdma, XAXIVDMA_WRITE);
        if (dma & XAXIVDMA_SR_ERR_ALL_MASK) return -40;
        /* IOC alone is insufficient: the post-frame ROI engine may still be
         * working. Search all non-writing slots by their actual guard identity. */
        if (dma & XAXIVDMA_IXR_FRMCNT_MASK)
            XAxiVdma_IntrClear(&g_vdma, XAXIVDMA_IXR_FRMCNT_MASK, XAXIVDMA_WRITE);
        for (slot = 0; slot < QR_GRAY_FRAME_COUNT; ++slot) {
            if (read_roi_snapshot(slot, &g_pl_probe) && (!found ||
                (int32_t)(g_pl_probe.header.frame_seq - g_pl_snapshot.header.frame_seq) > 0)) {
                g_pl_snapshot = g_pl_probe;
                found = 1;
            }
        }
        if (found && roi_snapshot_stable(&g_pl_snapshot)) {
            g_last_pl_seq = g_pl_snapshot.header.frame_seq;
            g_have_pl_seq = 1;
            return 0;
        }
        qr_pipeline_cooperate();
        XTime_GetTime(&now);
        if (elapsed_us(start, now) >= QR_CAMERA_FRAME_TIMEOUT_US) {
            ++g_pl_roi_snapshot_rejects;
            return -41;
        }
        usleep(100U);
    }
}

static uint32_t copy_pl_roi_interval(uint32_t row, uint32_t xmin, uint32_t xmax) {
    uint32_t length = xmax - xmin;
    UINTPTR source = g_gray_addresses[g_pl_snapshot.slot] +
                    (row + 1U) * QR_DECODE_WIDTH + xmin;
    Xil_DCacheInvalidateRange(source, length);
    capture_barrier();
    memcpy(g_decode_image + row * QR_DECODE_WIDTH + xmin,
           (const void *)source, length);
    return length;
}

/* Seal all PL ROI pixels before quirc can spend time decoding any of them.
 * Only the half-open ROI union is read; holes retain unused scratch contents.
 * Sorting xmin once makes each row's active intervals already ordered. */
static int copy_pl_roi_union(void) {
    unsigned order[QR_PL_ROI_LIMIT];
    unsigned count = g_pl_snapshot.bank.roi_count, i, j;
    uint32_t ymin = QR_DECODE_HEIGHT, ymax = 0U, row, copied_pixels = 0U;
    g_pl_roi_union_pixels = 0U;
    g_pl_roi_sealed_frame = 0U;
    if (count > QR_PL_ROI_LIMIT || !roi_snapshot_stable(&g_pl_snapshot))
        return -42;
    for (i = 0U; i < count; ++i) {
        const qr_pl_roi_t *roi = &g_pl_snapshot.roi[i];
        uint32_t xstart = qr_pl_x(roi->min_xy);
        uint32_t ystart = qr_pl_y(roi->min_xy), yend = qr_pl_y(roi->max_xy);
        /* Metadata was validated while taking the result-bank snapshot;
         * recheck before using it to bound private-memory writes. */
        if (!qr_pl_roi_valid(roi, QR_DECODE_WIDTH, QR_DECODE_HEIGHT))
            return -42;
        if (ystart < ymin) ymin = ystart;
        if (yend > ymax) ymax = yend;
        j = i;
        while (j > 0U && qr_pl_x(g_pl_snapshot.roi[order[j - 1U]].min_xy) > xstart) {
            order[j] = order[j - 1U];
            --j;
        }
        order[j] = i;
    }
    for (row = ymin; row < ymax; ++row) {
        uint32_t left = 0U, right = 0U;
        int active = 0;
        for (i = 0U; i < count; ++i) {
            const qr_pl_roi_t *roi = &g_pl_snapshot.roi[order[i]];
            uint32_t start_x, end_x;
            if (row < qr_pl_y(roi->min_xy) || row >= qr_pl_y(roi->max_xy))
                continue;
            start_x = qr_pl_x(roi->min_xy); end_x = qr_pl_x(roi->max_xy);
            if (!active) {
                left = start_x; right = end_x; active = 1;
            } else if (start_x <= right) {
                if (end_x > right) right = end_x;
            } else {
                copied_pixels += copy_pl_roi_interval(row, left, right);
                left = start_x; right = end_x;
            }
        }
        if (active)
            copied_pixels += copy_pl_roi_interval(row, left, right);
    }
    g_pl_roi_union_pixels = copied_pixels;
    capture_barrier();
    if (!roi_snapshot_stable(&g_pl_snapshot)) return -43;
    g_pl_roi_sealed_frame = g_pl_snapshot.header.frame_seq;
    ++g_pl_roi_union_frames;
    return 0;
}

/* The snapshot metadata and ROI-union pixels are now private. DMA/bank
 * rotation after sealing must not invalidate this frame during decoding.
 * quirc still copies each view into its own label-mutating workspace. */
static void private_pl_roi_view(unsigned index, qr_frame_view_t *private_roi) {
    const qr_pl_roi_t *r = &g_pl_snapshot.roi[index];
    uint32_t xmin = qr_pl_x(r->min_xy), ymin = qr_pl_y(r->min_xy);
    uint32_t width = qr_pl_x(r->max_xy) - xmin;
    uint32_t height = qr_pl_y(r->max_xy) - ymin;
    private_roi->data = g_decode_image + ymin * QR_DECODE_WIDTH + xmin;
    private_roi->width = (int)width; private_roi->height = (int)height;
    private_roi->stride = (int)QR_DECODE_WIDTH;
    /* This explicit API's contract, not the legacy enum, selects binary data. */
    private_roi->pixel_format = QR_PIXEL_FORMAT_GRAY8;
    g_pl_roi_last_index = index;
    g_pl_roi_last_min_xy = r->min_xy; g_pl_roi_last_max_xy = r->max_xy;
}

static int capture_and_decode_pl_roi(void) {
    qr_frame_view_t dimensions, private_roi;
    XTime start, pipeline_start, end, segment_start, segment_end;
    uint32_t frame_id, i, pipeline_us, roi_count, schedule_start, visited;
    int budget_stopped = 0;
#if QR_DECODE_BUDGET_US > 0U
    XTime decode_budget_start, budget_now;
    unsigned decode_attempts = 0U;
    int budget_overrun_recorded = 0;
#endif
    int status;
    int final_status = 0;
    uint32_t observed_mask = 0U;
    uint64_t now_us;
    qr_trace_record_t *trace_frame, *trace_roi[QR_PL_ROI_LIMIT]={0};
    memset(&g_result, 0, sizeof(g_result));
    memset(&g_fallback_profile, 0, sizeof(g_fallback_profile));
    XTime_GetTime(&start);
    status = wait_pl_roi_snapshot(start);
    XTime_GetTime(&pipeline_start);
    g_perf.capture_us += elapsed_us(start, pipeline_start);
    if (status) { ++g_capture_errors; qr_diag_count(QRD_CAPTURE_ERROR, 1); return status; }
    frame_id = g_pl_snapshot.header.frame_seq;
    qr_trace_context(frame_id,0xFFFFFFFFU);
    trace_frame=qr_trace_add(QRT_FRAME);
    if(trace_frame){
        memcpy(trace_frame->w,&g_pl_snapshot.bank,sizeof(g_pl_snapshot.bank));
        trace_frame->w[16]=g_pl_snapshot.header.epoch;
        trace_frame->w[17]=g_pl_snapshot.slot;
        memcpy(&trace_frame->w[18],g_pl_snapshot.header.reserved,16);
        trace_frame->w[22]=g_pl_snapshot.header.threshold;
        trace_frame->w[23]=g_pl_snapshot.header.threshold_source;
    }
    for(i=0;i<g_pl_snapshot.bank.roi_count;++i){
        trace_roi[i]=qr_trace_add(QRT_ROI);
        if(trace_roi[i]){
            trace_roi[i]->w[0]=i;
            memcpy(&trace_roi[i]->w[6],&g_pl_snapshot.roi[i],sizeof(qr_pl_roi_t));
        }
    }
    qr_diag.frame = frame_id;
    g_snapshot_valid = 1;
    g_pl_roi_flags = g_pl_snapshot.bank.flags;
    g_pl_candidate_count = g_pl_snapshot.bank.raw_count;
    g_pl_triple_count = g_pl_snapshot.bank.roi_count;
    qr_diag_count(QRD_FRAMES, 1);
    qr_diag_count(g_pl_snapshot.bank.raw_count ? QRD_PL_NONZERO : QRD_PL_ZERO, 1);
    qr_diag_count(QRD_PL_OVERFLOW, (g_pl_roi_flags & (QR_PL_RAW_OVERFLOW |
                         QR_PL_CLUSTER_OVERFLOW | QR_PL_ROI_OVERFLOW)) != 0U);
    qr_diag_count(QRD_RAW_OVERFLOW, (g_pl_roi_flags & QR_PL_RAW_OVERFLOW) != 0U);
    qr_diag_count(QRD_CLUSTER_OVERFLOW, (g_pl_roi_flags & QR_PL_CLUSTER_OVERFLOW) != 0U);
    qr_diag_count(QRD_ROI_OVERFLOW, (g_pl_roi_flags & QR_PL_ROI_OVERFLOW) != 0U);
    qr_diag_count(QRD_PL_TIMEOUT, (g_pl_roi_flags & QR_PL_TIMEOUT) != 0U);
    qr_diag_count(QRD_CENTERS, g_pl_snapshot.bank.cluster_count);
    qr_diag_count(QRD_TRIPLES, g_pl_snapshot.bank.roi_count);
    qr_diag_count(QRD_PL_GEOM_PASS, g_pl_snapshot.bank.reserved[4] & 65535U);
    qr_diag_count(QRD_PL_SCALE_REJECT, g_pl_snapshot.bank.reserved[4] >> 16);
    if (g_pl_snapshot.bank.raw_count) ++g_perf.pl_nonempty_frames;
    if (g_pl_snapshot.bank.roi_count) ++g_perf.pl_triple_frames;
    ++g_fullres_frames;
    dimensions.data = 0; dimensions.width = QR_DECODE_WIDTH;
    dimensions.height = QR_DECODE_HEIGHT; dimensions.stride = QR_DECODE_WIDTH;
    dimensions.pixel_format = QR_PIXEL_FORMAT_GRAY8;
    XTime_GetTime(&segment_start);
    status = copy_pl_roi_union();
    XTime_GetTime(&segment_end);
    g_pl_roi_union_copy_us = elapsed_us(segment_start, segment_end);
    g_pl_roi_union_status = status;
    g_perf.capture_us += g_pl_roi_union_copy_us;
    if (status) {
        for(i=0;i<g_pl_snapshot.bank.roi_count;++i)
            if(trace_roi[i])trace_roi[i]->w[1]=QRT_COPY_REJECT;
        ++g_pl_roi_copy_rejects;
        final_status = status;
        goto finish_pl_roi_frame;
    }
#if QR_FAILURE_TRACE
    /* Sampling is independent of the sealed ROI union. A rotating source
     * invalidates this sample only; it cannot invalidate the private ROIs. */
    {
        uint64_t sample_us=camera_now_us();
        uint8_t *sample=qr_trace_snapshot_begin(sample_us);
        if(sample){
            int valid=roi_snapshot_stable(&g_pl_snapshot);
            XTime a,b;XTime_GetTime(&a);
            if(valid){
                UINTPTR src=g_gray_addresses[g_pl_snapshot.slot]+QR_DECODE_WIDTH;
                Xil_DCacheInvalidateRange(src,QRT_SNAP_BYTES);capture_barrier();
                memcpy(sample,(const void *)src,QRT_SNAP_BYTES);capture_barrier();
                valid=roi_snapshot_stable(&g_pl_snapshot);
            }
            XTime_GetTime(&b);
            qr_trace_snapshot_end(frame_id,g_pl_snapshot.header.epoch,
                (const uint32_t *)&g_pl_snapshot.header,sample_us,elapsed_us(a,b),valid);
        }
    }
#endif
    now_us = camera_now_us();
    validate_tracker_publications(now_us);
    if (qr_osd_queue_update(&g_osd_queue, now_us, osd_event, 0)) osd_publish();
    roi_count = g_pl_snapshot.bank.roi_count;
    schedule_start = qr_decode_scheduler_begin(&g_decode_scheduler, roi_count);
    if(trace_frame)trace_frame->w[24]=schedule_start;
    for(i=0;i<QR_TRACKER_CAPACITY;i++)if(g_tracker.tracks[i].active)
        trace_track(&g_tracker.tracks[i],0,now_us);
    visited = 0U;
#if QR_DECODE_BUDGET_US > 0U
    XTime_GetTime(&decode_budget_start);
#endif
    while (visited < roi_count && g_result.instance_count < QR_MAX_INSTANCES) {
        const qr_pl_roi_t *roi;
        qr_finder_triple_t triple;
        qr_track_observation_t observation;
        qr_track_decision_t decision;
        unsigned k;
        uint16_t before;
        int found;
#if QR_DECODE_BUDGET_US > 0U
        XTime_GetTime(&budget_now);
        if (!qr_decode_scheduler_allows(
                decode_attempts, elapsed_us(decode_budget_start, budget_now))) {
            budget_stopped = 1;
            qr_diag_count(QRD_BUDGET_STOP, 1U);
            qr_diag_count(QRD_BUDGET_DEFERRED, roi_count - visited);
            break;
        }
#endif
        i = qr_decode_scheduler_index(schedule_start, visited, roi_count);
        ++visited;
        qr_trace_context(frame_id,i);
        if(trace_roi[i])trace_roi[i]->w[4]=visited;
        roi = &g_pl_snapshot.roi[i];
        for (k = 0; k < 3; ++k) {
            triple.finder[k].x = (float)qr_pl_x(roi->finder_xy[k]);
            triple.finder[k].y = (float)qr_pl_y(roi->finder_xy[k]);
            triple.finder[k].module_size = (float)(roi->module_angle & 65535U) / 256.0f;
            triple.finder[k].score = (float)roi->hits;
        }
        g_pl_roi_triples[i] = triple;
        for (k = 0; k < roi_count; ++k)
            if (k != i && (observed_mask & (1U << k)) &&
                same_finder_triple(&triple, &g_pl_roi_triples[k])) break;
        if (k != roi_count) {
            if(trace_roi[i]){trace_roi[i]->w[1]=QRT_EQUIVALENT;trace_roi[i]->w[2]=k;}
            ++g_skipped_equivalent_triples; qr_diag_count(QRD_ROI_EQUIVALENT,1); continue;
        }
        observed_mask |= 1U << i;
        observation = triple_observation(&triple, &dimensions, frame_id);
        {
            int rc=qr_tracker_observe(&g_tracker,&observation,now_us,&decision);
            if(trace_roi[i]){
                trace_roi[i]->w[1]=rc?QRT_TRACK_ERROR:(decision.should_decode?QRT_DECODE:QRT_PREDICT);
                trace_roi[i]->w[2]=decision.track_id;
                trace_roi[i]->w[3]=(uint32_t)decision.created|((uint32_t)decision.ambiguous<<8)|
                  ((uint32_t)decision.already_decoded<<16)|((uint32_t)decision.matched_tracks<<24);
                trace_roi[i]->w[24]=(uint32_t)rc;
            }
            if(rc!=0||!decision.should_decode){
                trace_track(qr_tracker_find(&g_tracker,decision.track_id),1,now_us);
                continue;
            }
        }
        private_pl_roi_view(i, &private_roi);
        before = g_result.instance_count;
        g_diag_context_track = decision.track_id;
        qr_diag_context(QR_CAMERA_PL_GRAY_DIAGNOSTIC ? "pl_gray_roi" : "pl_binary_roi",
                        decision.track_id, decision.already_decoded);
        qr_diag_count(QRD_DECODE_STARTED, 1U);
#if QR_DECODE_BUDGET_US > 0U
        ++decode_attempts;
#endif
        XTime_GetTime(&segment_start);
        found = QR_CAMERA_PL_GRAY_DIAGNOSTIC ?
            qr_quirc_gray_roi_run(&private_roi, qr_pl_x(roi->min_xy), qr_pl_y(roi->min_xy),
                                  &g_result, &g_fallback_profile) :
            qr_quirc_binary_roi_run(&private_roi, qr_pl_x(roi->min_xy), qr_pl_y(roi->min_xy),
                                    &g_result, &g_fallback_profile);
        XTime_GetTime(&segment_end);
        if(trace_roi[i]){
            trace_roi[i]->w[22]=(uint32_t)found;
            trace_roi[i]->w[23]=elapsed_us(segment_start,segment_end);
        }
        {
            qr_trace_record_t *r=qr_trace_add(QRT_CALL);
            if(r){
                r->w[0]=i;r->w[1]=g_fallback_profile.copy_us;
                r->w[2]=g_fallback_profile.identify_us;r->w[3]=g_fallback_profile.decode_us;
                r->w[4]=elapsed_us(segment_start,segment_end);
                r->w[5]=g_fallback_profile.regions_seen;r->w[6]=g_fallback_profile.capstones_seen;
                r->w[7]=g_fallback_profile.grids_found;r->w[8]=g_fallback_profile.decode_attempts;
                r->w[9]=g_fallback_profile.decoded_instances;r->w[10]=(uint32_t)found;
                r->w[11]=g_fallback_profile.mirrored_instances;
            }
        }
#if QR_DECODE_BUDGET_US > 0U
        if (!budget_overrun_recorded &&
            elapsed_us(decode_budget_start, segment_end) >= QR_DECODE_BUDGET_US) {
            budget_overrun_recorded = 1;
            qr_diag_count(QRD_BUDGET_OVERRUN, 1U);
        }
#endif
        qr_diag_count(QRD_ROI_DISPATCH,1);
        qr_diag_roi_time(elapsed_us(segment_start,segment_end),(uint32_t)private_roi.width*(uint32_t)private_roi.height);
        diagnostic_scan(&g_fallback_profile, 0);
        ++g_perf.roi_calls;
        g_perf.roi_us += elapsed_us(segment_start, segment_end);
        g_perf.roi_pixels += (uint64_t)private_roi.width * private_roi.height;
        g_perf.quirc_copy_us += g_fallback_profile.copy_us;
        g_perf.quirc_identify_us += g_fallback_profile.identify_us;
        g_perf.quirc_decode_us += g_fallback_profile.decode_us;
        g_perf.regions_seen += g_fallback_profile.regions_seen;
        g_perf.capstones_seen += g_fallback_profile.capstones_seen;
        if (g_fallback_profile.max_regions > g_perf.max_regions)
            g_perf.max_regions = g_fallback_profile.max_regions;
        if (g_fallback_profile.max_capstones > g_perf.max_capstones)
            g_perf.max_capstones = g_fallback_profile.max_capstones;
        /* Even a neighbouring decode consumes this ROI's retry attempt. A
         * successful association below then changes the appropriate track. */
        qr_tracker_mark_attempt(&g_tracker, decision.track_id, now_us, 0, 0);
        if (found > 0) {
            /* An enlarged ROI may contain a neighbour. Associate every result
             * by its decoded finder geometry, never by this ROI's index. */
            for (k = before; k < g_result.instance_count; ++k) {
                handle_success_instance(frame_id,decision.track_id,&g_result.instances[k],&dimensions,
                    QR_CAMERA_PL_GRAY_DIAGNOSTIC ? "pl_gray_roi" : "pl_binary_roi",now_us);
            }
        } else if (found < 0) { final_status = found; break; }
    }
    qr_decode_scheduler_finish(&g_decode_scheduler, roi_count, schedule_start, visited);
    if (roi_count > 1U && g_decode_scheduler.cursor != schedule_start)
        qr_diag_count(QRD_ROTATION_ADVANCED, 1U);
    /* Zero-ROI frames are valid completed captures. There is intentionally no
     * full-image rescue or legacy locator fallback in this experiment mode. */
    if(!budget_stopped && visited < roi_count && g_result.instance_count>=QR_MAX_INSTANCES)
        qr_diag_count(QRD_INSTANCE_DEFERRED,roi_count-visited);
    for(i=0;i<roi_count;++i)if(trace_roi[i]&&trace_roi[i]->w[1]==QRT_PENDING)
        trace_roi[i]->w[1]=budget_stopped?QRT_BUDGET:
            (g_result.instance_count>=QR_MAX_INSTANCES?QRT_INSTANCE:QRT_ABORT);
finish_pl_roi_frame:
    XTime_GetTime(&end);
    pipeline_us = elapsed_us(pipeline_start, end);
    {
        qr_trace_record_t *r=qr_trace_add(QRT_FRAME_END);
        if(r){r->w[0]=(uint32_t)final_status;r->w[1]=pipeline_us;
            r->w[2]=g_pl_roi_union_copy_us;r->w[3]=g_pl_roi_union_pixels;
            r->w[4]=g_result.instance_count;r->w[5]=g_decode_scheduler.cursor;
        }
    }
    ++g_processed_frames;
    if (g_result.instance_count) {
        ++g_success_frames; ++g_fullres_success_frames; ++g_perf.roi_success_frames;
        g_result.stage = QR_STAGE_OK;
    } else g_result.stage = QR_STAGE_DECODE;
    if (pipeline_us < g_pipeline_min_us) g_pipeline_min_us = pipeline_us;
    if (pipeline_us > g_pipeline_max_us) g_pipeline_max_us = pipeline_us;
    g_pipeline_sum_us += pipeline_us;
    if (qr_diag.active) qr_diag.pipeline_us += pipeline_us;
    if (final_status) { ++g_capture_errors; qr_diag_count(QRD_CAPTURE_ERROR, 1); }
    emit_result(frame_id, final_status, g_pl_snapshot.slot, QR_DECODE_WIDTH, QR_DECODE_HEIGHT,
                pipeline_us, elapsed_us(start, end));
    return final_status;
}

static int capture_and_decode(uint32_t frame_id) {
    return QR_CAMERA_PL_ROI ? capture_and_decode_pl_roi() : capture_and_decode_legacy(frame_id);
}

static int recover_pl_capture(void) {
    XTime start, now;
    unsigned i;
    int status;
    /* Early SOF after a truncated source frame can latch a VDMA error. Reset
     * this capture channel and PL session explicitly; HDMI is a separate VDMA.
     * This recovery code has only been syntax checked, not exercised on board. */
    ++g_pl_capture_restarts;
    gpio_write(QR_CAMERA_ARM_GPIO_BASE, 0U);
    qr_write(0x00U, 0U);
    XAxiVdma_Reset(&g_vdma, XAXIVDMA_WRITE);
    XTime_GetTime(&start);
    while (XAxiVdma_ResetNotDone(&g_vdma, XAXIVDMA_WRITE)) {
        qr_pipeline_cooperate();
        XTime_GetTime(&now);
        if (elapsed_us(start, now) >= QR_CAMERA_FRAME_TIMEOUT_US) {
            ++g_pl_capture_restart_failures;
            return -44;
        }
        usleep(100U);
    }
    qr_tracker_finish(&g_tracker, "capture_reset");
    for (i = 0; i < QR_TRACKER_CAPACITY; ++i)
        if (g_tracker.tracks[i].active) {
            g_tracker.tracks[i].active = 0;
            ++g_tracker.retired;
        }
    status = continuous_capture_start();
    if (status) ++g_pl_capture_restart_failures;
    return status;
}

int main(void) {
    uint32_t frame_id = 1U;
    int capture_status;
    Xil_ICacheEnable();
    Xil_DCacheEnable();
    qr_detector_config_default(&g_config);
    g_config.threshold = QR_CAMERA_PL_THRESHOLD;
    qr_tracker_init(&g_tracker);
    qr_decode_scheduler_reset(&g_decode_scheduler);
    qr_diag_init();qr_tracker_set_retire_observer(diagnostic_track);
    qr_quirc_set_observer(diagnostic_decode);
    qr_osd_queue_init(&g_osd_queue);
    publication_reset();
    osd_publish();
    gpio_write(QR_CAMERA_ARM_GPIO_BASE, 0U);
    gpio_write(QR_HDMI_RESET_GPIO_BASE, 0U);
    g_hdmi_status = 0;
    g_camera_init_status = 0;
    g_camera_probe_status = -1;
    g_camera_sensor_id = 0;
    g_camera_probe_send_count = 0U;
    g_camera_probe_recv_count = 0U;
    g_hdmi_probe_count = 0U;
    g_capture_init_status = 0;
    g_boot_phase = 1U;

    xil_printf("QR continuous camera boot profile=%s source=%ux%u decode=%ux%u\r\n",
               QR_REPLAY_PROFILE_NAME, (unsigned)QR_REPLAY_WIDTH,
               (unsigned)QR_REPLAY_HEIGHT, (unsigned)QR_DECODE_WIDTH,
               (unsigned)QR_DECODE_HEIGHT);
    xil_printf("QR compare success_only=%u tracker_capacity=%u compact_diag=%u diag_revision=%u decode_budget_us=%u schedule=%s\r\n",
               (unsigned)QR_STEP1_SUCCESS_ONLY,(unsigned)QR_TRACKER_CAPACITY,
               (unsigned)QR_DIAG_COMPACT,
               (unsigned)(QR_DIAG_COMPACT?(QR_TRACKER_POINT_ASSOC?8U:(QR_DECODE_BUDGET_US?7U:6U)):4U),
               (unsigned)QR_DECODE_BUDGET_US,
               QR_DECODE_BUDGET_US?"round_robin":"linear");
    xil_printf("QR capture pl_roi=%u format=%u divisor=%u frame_bytes=%u ring_end=0x%08x\r\n",
               (unsigned)QR_CAMERA_PL_ROI, (unsigned)(QR_CAMERA_PL_ROI ? QR_CAMERA_PL_FORMAT : QR_PL_FORMAT_GRAY8),
               (unsigned)QR_CAMERA_GRAY_DIVISOR, (unsigned)QR_CAPTURE_FRAME_BYTES,
               (unsigned)(QR_GRAY_FRAME2 + QR_CAPTURE_FRAME_BYTES));
#if QR_CAMERA_GRAY_DIVISOR == 2U
    xil_printf("QR engine unified=quirc/version1-40 rescue=%ux%u every %u frames\r\n",
               (unsigned)QR_RESCUE_WIDTH, (unsigned)QR_RESCUE_HEIGHT,
               (unsigned)QR_FULLRES_RESCUE_PERIOD);
#else
    xil_printf("QR engine quirc/version1-40 PL_ROI=%u binary=%u Otsu=%u; source ABI must match\r\n",
               (unsigned)QR_CAMERA_PL_ROI, (unsigned)!QR_CAMERA_PL_GRAY_DIAGNOSTIC, (unsigned)QR_CAMERA_PL_OTSU);
#endif
    xil_printf("QR core version=0x%08x\r\n", (unsigned)qr_read(0x20U));
    if (qr_read(0x20U) != (QR_CAMERA_PL_ROI ? QR_PL_ABI_VERSION : 0x00010100U)) {
        xil_printf("QR camera hardware initialization failed\r\n");
        return XST_FAILURE;
    }
    if (qr_read(0x3CU) != QR_CAMERA_GRAY_DIVISOR) {
        xil_printf("QR Gray8 bitstream/ELF mismatch: hardware divisor=%u ELF divisor=%u\r\n",
                   (unsigned)qr_read(0x3CU),
                   (unsigned)QR_CAMERA_GRAY_DIVISOR);
        return XST_FAILURE;
    }

    gpio_write(QR_CAMERA_RESET_GPIO_BASE, 1U);
    usleep(500000U);
    gpio_write(QR_CAMERA_RESET_GPIO_BASE, 0U);
    usleep(500000U);
    gpio_write(QR_HDMI_RESET_GPIO_BASE, 1U);
    gpio_write(QR_CAMERA_RESET_GPIO_BASE, 1U);
    usleep(500000U);
    /* Display S2MM uses cam1_pclk.  The OV5640 must provide that clock
     * before the VDMA driver can complete its channel reset. */
    g_boot_phase = 2U;
    g_camera_init_status = camera_init();
    if (g_camera_init_status != XST_SUCCESS) {
        u8 id_hi = 0U, id_lo = 0U;
        u8 id_reg[2] = {0x30U, 0x0AU};
        u8 hdmi_reg = 0x08U;
        if (XIic_DynInit(QR_CAMERA_IIC_BASE) != XST_SUCCESS)
            g_camera_probe_status = 1;
        else {
            g_camera_probe_send_count = XIic_Send(QR_CAMERA_IIC_BASE,
                0x3CU, id_reg, 2U, XIIC_REPEATED_START);
            if (g_camera_probe_send_count != 2U)
                g_camera_probe_status = 2;
            else {
                g_camera_probe_recv_count = XIic_Recv(QR_CAMERA_IIC_BASE,
                    0x3CU, &id_hi, 1U, XIIC_STOP);
                if (g_camera_probe_recv_count != 1U)
                    g_camera_probe_status = 3;
                else if (i2c_read_reg16(QR_CAMERA_IIC_BASE, 0x3CU,
                                        0x300BU, &id_lo) != XST_SUCCESS)
                    g_camera_probe_status = 4;
                else {
                    g_camera_probe_status = 0;
                    g_camera_sensor_id = ((uint32_t)id_hi << 8) | id_lo;
                }
            }
        }
        if (XIic_DynInit(QR_HDMI_IIC_BASE) == XST_SUCCESS)
            g_hdmi_probe_count = XIic_Send(QR_HDMI_IIC_BASE, 0x39U,
                                            &hdmi_reg, 1U, XIIC_STOP);
        xil_printf("OV5640 initialization failed status=%d\r\n",
                   (int)g_camera_init_status);
        return XST_FAILURE;
    }
    g_boot_phase = 3U;
    g_hdmi_status = display_init();
    g_display_ready = (g_hdmi_status == XST_SUCCESS);
    if (g_display_ready)
        xil_printf("HDMI READY RGB565 triple-buffer display %ux%u\r\n",
                   (unsigned)QR_REPLAY_WIDTH, (unsigned)QR_REPLAY_HEIGHT);
    else
        xil_printf("WARNING: HDMI disabled status=%d; QR recognition continues\r\n",
                   (int)g_hdmi_status);

#if QR_HDMI_STATIC_TEST
    xil_printf("HDMI STATIC TEST %ux%u centred in 1280x720\r\n",
               (unsigned)QR_HDMI_PREVIEW_WIDTH,
               (unsigned)QR_HDMI_PREVIEW_HEIGHT);
    for (;;) {
        g_hdmi_mm2s_status = XAxiVdma_GetStatus(&g_display_vdma,
                                                XAXIVDMA_READ);
        g_hdmi_s2mm_status = 0U;
        sleep(1U);
    }
#endif

    g_boot_phase = 4U;
    capture_status = continuous_capture_start();
    g_capture_init_status = capture_status;
    if (capture_status != XST_SUCCESS) {
        xil_printf("QR continuous capture initialization failed status=%d\r\n",
                   capture_status);
        return XST_FAILURE;
    }
    g_net_ready = (qr_replay_net_init() == XST_SUCCESS);
    g_boot_phase = 5U;
    if (!g_net_ready)
        xil_printf("WARNING: Ethernet result output disabled; UART remains active\r\n");
    xil_printf("QR LIVE CAMERA READY continuous triple-buffer quirc mode\r\n");

    for (;;) {
        diagnostic_uart_poll(frame_id);
        /* END freezes the scored batch until its summary and ACK drain. */
        if(qr_diag.ending||(!qr_diag.active&&qr_diag_queued())){
            qr_diag_pump(uart_write_nonblocking,1024);qr_pipeline_cooperate();continue;
        }
        if (g_window_reset_ack != g_window_reset_request) {
            memset(g_window_seen, 0, sizeof(g_window_seen));
            g_window_seen_next = 0U;
            g_window_unique_total = 0U;
            g_window_decoded_total = 0U;
            g_window_reset_ack = g_window_reset_request;
        }
        int status = capture_and_decode(frame_id);
        if (status != 0) {
            if(!diag_busy()) xil_printf("QR camera frame=%u status=%d core=0x%08x vdma=0x%08x\r\n",
                       (unsigned)frame_id, status, (unsigned)qr_read(0x04U),
                       (unsigned)XAxiVdma_GetStatus(&g_vdma,
                                                    XAXIVDMA_WRITE));
            if (QR_CAMERA_PL_ROI &&
                (XAxiVdma_GetStatus(&g_vdma, XAXIVDMA_WRITE) & XAXIVDMA_SR_ERR_ALL_MASK)) {
                int restart_status = recover_pl_capture();
                if (restart_status) {
                    if (!diag_busy()) xil_printf("QR capture restart failed status=%d\r\n", restart_status);
                    usleep(100000U);
                }
            }
            usleep(1000U);
        }
        qr_tracker_retire(&g_tracker,camera_now_us());
        {
            uint64_t previous_stats=qr_diag.last_stats_us;
            qr_diag_tick(camera_now_us(),frame_id);
            if(qr_diag.active&&qr_diag.enabled&&previous_stats!=qr_diag.last_stats_us){
                diagnostic_tracker_totals();publication_totals();
            }
        }
        diagnostic_uart_poll(frame_id);
        ++frame_id;
        if (frame_id == 0U)
            frame_id = 1U;
    }
}
