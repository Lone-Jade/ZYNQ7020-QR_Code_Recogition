#ifndef QR_PUBLICATION_H
#define QR_PUBLICATION_H
#include <stdint.h>
#include <stddef.h>
#define QR_PUBLICATION_CAPACITY 32U
#define QR_PUBLICATION_PAYLOAD_BYTES 1024U
#define QR_PUBLICATION_RETENTION_US 6000000ULL
enum { QR_PUB_INVALID=-2, QR_PUB_FULL=-1, QR_PUB_DUPLICATE=0,
       QR_PUB_NEW=1, QR_PUB_RETRY=2 };
enum { QR_PUB_UNUSED=0, QR_PUB_PENDING=1, QR_PUB_PUBLISHED=2 };
typedef struct {
    float x,y,size;
    uint32_t frame;
    uint64_t sample_us, now_us;
} qr_publication_observation_t;
typedef struct {
    uint32_t id,hash,frame;
    uint64_t sample_us,last_us;
    float x,y,size,vx,vy;
    uint16_t length;
    uint8_t state,velocity_valid,frame_valid;
    char payload[QR_PUBLICATION_PAYLOAD_BYTES];
} qr_publication_entry_t;
typedef struct {
    qr_publication_entry_t entries[QR_PUBLICATION_CAPACITY];
    uint32_t next_id,created,duplicates,evictions,full_pending,invalid,committed;
    float frame_period_s,flow_vx,flow_vy;
    uint32_t flow_samples;
} qr_publication_t;
void qr_publication_init(qr_publication_t *p);
/* Retain publication/PENDING identity across a camera frame-counter restart. */
void qr_publication_rebase_frames(qr_publication_t *p);
int qr_publication_prepare(qr_publication_t *p,const char *payload,size_t length,
                          const qr_publication_observation_t *o,unsigned *slot);
int qr_publication_commit(qr_publication_t *p,unsigned slot,uint32_t id);
unsigned qr_publication_pending(const qr_publication_t *p);
int qr_publication_identity_live(const qr_publication_t *p,uint32_t id,uint64_t now_us);
#endif
