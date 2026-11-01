#ifndef QR_OSD_QUEUE_H
#define QR_OSD_QUEUE_H
#include <stdint.h>
#define QR_OSD_VISIBLE 4U
#define QR_OSD_CAPACITY 16U
#define QR_OSD_TEXT_BYTES 33U
typedef struct{uint32_t track_id;uint64_t show_us;char text[QR_OSD_TEXT_BYTES];}qr_osd_entry_t;
typedef struct{qr_osd_entry_t visible[QR_OSD_VISIBLE],pending[QR_OSD_CAPACITY-QR_OSD_VISIBLE];uint8_t visible_count,pending_count;uint32_t read_count,overflow_count,revision;}qr_osd_queue_t;
typedef void(*qr_osd_event_fn)(void*,const char*,unsigned,const qr_osd_entry_t*,uint64_t);
void qr_osd_queue_init(qr_osd_queue_t*q);
int qr_osd_queue_enqueue(qr_osd_queue_t*q,uint32_t track,const char*payload,uint64_t now,qr_osd_event_fn fn,void*ctx);
int qr_osd_queue_update(qr_osd_queue_t*q,uint64_t now,qr_osd_event_fn fn,void*ctx);
#endif
