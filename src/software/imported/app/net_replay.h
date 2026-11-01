#ifndef QR_REPLAY_NET_REPLAY_H
#define QR_REPLAY_NET_REPLAY_H
#include "xil_types.h"
#include "qr_replay_protocol.h"

int qr_replay_net_init(void);
void qr_replay_net_service(void);
int qr_replay_net_link_up(void);
int qr_replay_take_ready_frame(uint32_t *frame_id, UINTPTR *address);
void qr_replay_publish_result(uint32_t frame_id, int status, uint32_t stage,
                              uint32_t instances, const char *payload,
                              uint32_t pipeline_us, uint32_t total_us);
void qr_replay_release_frame(uint32_t frame_id);
uint32_t qr_replay_received_frames(void);
uint32_t qr_replay_dropped_frames(void);
uint32_t qr_replay_crc_dropped_frames(void);
uint32_t qr_replay_packets_received(void);
uint32_t qr_replay_packets_duplicate(void);
uint32_t qr_replay_ring_overflow(void);
uint32_t qr_replay_receive_fps_milli(void);

#endif
