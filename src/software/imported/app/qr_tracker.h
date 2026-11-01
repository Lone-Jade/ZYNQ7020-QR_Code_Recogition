#ifndef QR_TRACKER_H
#define QR_TRACKER_H
#include <stdint.h>
#define QR_TRACKER_CAPACITY 16U
#define QR_TRACKER_PAYLOAD_BYTES 1024U
#ifndef QR_STEP1_SUCCESS_ONLY
#define QR_STEP1_SUCCESS_ONLY 1
#endif
#ifndef QR_TRACKER_POINT_ASSOC
#define QR_TRACKER_POINT_ASSOC 1
#endif
typedef struct {
    float x,y,size,sharpness;
    uint32_t frame_id;
    float finder_x[3],finder_y[3],module_size;
    uint8_t finder_valid,geometry_reliable;
} qr_track_observation_t;
typedef struct {
    uint32_t id;
    float x,y,size,vx,vy,sharpness;
    float finder_x[3],finder_y[3],module_size;
    uint64_t first_us,last_us,last_attempt_us;
    uint32_t last_frame,last_result_frame,publication_id;
    uint32_t associations,retry_decisions,skips,ambiguities,decode_calls,mirror_calls,failures,raw_success,after_success_calls;
    uint8_t active,decoded,finder_valid,velocity_valid;
    char payload[QR_TRACKER_PAYLOAD_BYTES];
} qr_track_t;
typedef struct {
    uint32_t created,retries,decoded_skips,ambiguous,retired,full_scan_suppressed,capacity_rejects,payload_conflicts;
    uint32_t next_id;
    qr_track_t tracks[QR_TRACKER_CAPACITY];
    uint32_t roi_queries,roi_unmatched,roi_decode_admitted,roi_prediction_skips,roi_retry_wait,roi_capacity_skips,capacity_bypass;
    uint32_t point_matches,point_rejects,unreliable_geometry,unbound_rejects,multi_match_decode,publication_invalidated;
} qr_tracker_t;
typedef struct {uint32_t track_id;uint8_t created,ambiguous,should_decode,already_decoded,matched_tracks;} qr_track_decision_t;
typedef void (*qr_track_retire_fn)(const qr_track_t *, const char *reason);
void qr_tracker_set_retire_observer(qr_track_retire_fn observer);
void qr_tracker_finish(qr_tracker_t *tracker, const char *reason);
void qr_tracker_init(qr_tracker_t *tracker);
void qr_tracker_retire(qr_tracker_t *tracker,uint64_t now_us);
int qr_tracker_observe(qr_tracker_t *tracker,const qr_track_observation_t *observation,uint64_t now_us,qr_track_decision_t *decision);
int qr_tracker_observe_result(qr_tracker_t *tracker,const qr_track_observation_t *observation,uint64_t now_us,qr_track_decision_t *decision);
int qr_tracker_observe_success(qr_tracker_t *tracker,const qr_track_observation_t *observation,uint64_t now_us,const char *payload,qr_track_decision_t *decision);
void qr_tracker_claim_result(qr_tracker_t *tracker,uint32_t track_id,uint32_t frame_id);
int qr_tracker_mark_attempt(qr_tracker_t *tracker,uint32_t track_id,uint64_t now_us,int success,const char *payload);
int qr_tracker_bind_publication(qr_tracker_t *tracker,uint32_t track_id,uint32_t publication_id);
void qr_tracker_invalidate_publication(qr_tracker_t *tracker,uint32_t track_id);
qr_track_t *qr_tracker_find(qr_tracker_t *tracker,uint32_t track_id);
#endif
