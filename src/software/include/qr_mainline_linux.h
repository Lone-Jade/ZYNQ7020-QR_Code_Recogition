#ifndef QR_MAINLINE_LINUX_H
#define QR_MAINLINE_LINUX_H

#include <stddef.h>
#include <stdint.h>

#include "ax7021b_qr.h"

#ifdef __cplusplus
extern "C" {
#endif

#define QR_MAINLINE_MAX_RESULTS 8U
#define QR_MAINLINE_PAYLOAD_BYTES 1024U

struct qr_mainline_symbol {
	uint32_t track_id;
	uint32_t publication_id;
	float x;
	float y;
	float size;
	char payload[QR_MAINLINE_PAYLOAD_BYTES];
};

struct qr_mainline_result {
	uint64_t capture_sequence;
	uint32_t pl_frame_sequence;
	uint32_t threshold;
	uint32_t roi_count;
	uint32_t decoded_count;
	uint32_t elapsed_us;
	uint32_t soft_budget_exceeded;
	uint32_t metadata_valid;
	struct qr_mainline_symbol symbols[QR_MAINLINE_MAX_RESULTS];
};

/* Additive display metadata API; qr_mainline_result ABI is unchanged. */
struct qr_mainline_symbol_geometry {
 uint32_t version, frame, epoch, valid;
 float corners[8];
 uint32_t roi_min_xy,roi_max_xy;
};
struct qr_mainline_context;
int qr_mainline_get_symbol_geometry(const struct qr_mainline_context *,uint32_t,
 struct qr_mainline_symbol_geometry *,size_t);

struct qr_mainline_context *qr_mainline_create(void);
void qr_mainline_destroy(struct qr_mainline_context *context);
/* Diagnostic accessor; no result/UAPI structure layout change. */
uint32_t qr_mainline_last_roi_decode_calls(const struct qr_mainline_context *context);
uint32_t qr_mainline_last_pl_epoch(const struct qr_mainline_context *context);
int qr_mainline_process(struct qr_mainline_context *context, int capture_fd,
			const uint8_t *storage, size_t storage_bytes,
			uint64_t capture_sequence, struct qr_mainline_result *result);
int qr_mainline_process_snapshot(struct qr_mainline_context *,const uint8_t *,size_t,
 uint64_t,const struct ax7021b_qr_frame_snapshot *,struct qr_mainline_result *);
int qr_mainline_process_file(struct qr_mainline_context *context,
			     const uint8_t *gray, uint32_t width, uint32_t height,
			     uint32_t stride, struct qr_mainline_result *result);

int ax7021b_qr_open(const char *path);
int ax7021b_qr_get_info(int fd, struct ax7021b_qr_info *info);
void *ax7021b_qr_map_buffer(int fd, const struct ax7021b_qr_info *info, uint32_t index);
int ax7021b_qr_start(int fd);
int ax7021b_qr_stop(int fd);
int ax7021b_qr_dequeue(int fd, struct ax7021b_qr_buffer *buffer);
int ax7021b_qr_queue(int fd, uint32_t index);
int ax7021b_qr_get_counters(int fd, struct ax7021b_qr_counters *counters);
int ax7021b_qr_camera_init(const char *sysfs_root, const char *dev_root, int trace);

#ifdef __cplusplus
}
#endif
#endif
