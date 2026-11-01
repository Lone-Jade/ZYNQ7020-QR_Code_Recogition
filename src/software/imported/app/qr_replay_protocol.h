#ifndef QR_REPLAY_PROTOCOL_H
#define QR_REPLAY_PROTOCOL_H

#include <stdint.h>

#define QR_REPLAY_PROFILE_800X600_48FPS 1
#define QR_REPLAY_PROFILE_1280X720_30FPS 2

/* Keep the accepted 800x600 build as the default.  Select the HD replay
 * geometry with -DQR_REPLAY_PROFILE=QR_REPLAY_PROFILE_1280X720_30FPS.
 * The camera/VDMA bitstream and the application profile must always match. */
#ifndef QR_REPLAY_PROFILE
#define QR_REPLAY_PROFILE QR_REPLAY_PROFILE_800X600_48FPS
#endif

#if QR_REPLAY_PROFILE == QR_REPLAY_PROFILE_800X600_48FPS
#define QR_REPLAY_WIDTH 800U
#define QR_REPLAY_HEIGHT 600U
#define QR_REPLAY_PROFILE_NAME "800x600_48fps"
#define QR_REPLAY_FRAME0 0x10000000U
#define QR_REPLAY_FRAME1 0x100EA600U
#define QR_REPLAY_FRAME2 0x101D4C00U
#elif QR_REPLAY_PROFILE == QR_REPLAY_PROFILE_1280X720_30FPS
#define QR_REPLAY_WIDTH 1280U
#define QR_REPLAY_HEIGHT 720U
#define QR_REPLAY_PROFILE_NAME "1280x720_30fps"
/* Use a 2 MiB slot stride for the 1,843,200-byte HD RGB565 frames. */
#define QR_REPLAY_FRAME0 0x10000000U
#define QR_REPLAY_FRAME1 0x10200000U
#define QR_REPLAY_FRAME2 0x10400000U
#else
#error "Unsupported QR_REPLAY_PROFILE"
#endif

#define QR_REPLAY_FRAME_BYTES (QR_REPLAY_WIDTH * QR_REPLAY_HEIGHT * 2U)
#define QR_REPLAY_PAYLOAD_BYTES 1372U
#define QR_REPLAY_PACKET_COUNT ((QR_REPLAY_FRAME_BYTES + QR_REPLAY_PAYLOAD_BYTES - 1U) / QR_REPLAY_PAYLOAD_BYTES)
#define QR_REPLAY_INPUT_PORT 8081U
#define QR_REPLAY_RESULT_PORT 8082U
#define QR_REPLAY_DESCRIPTOR_ADDR 0x0FF00000U
#define QR_REPLAY_GRAY_ADDR 0x11000000U
#define QR_REPLAY_RESULT_ADDR 0x12000000U
#define QR_REPLAY_QR_VDMA_BASE 0x43000000U
#define QR_REPLAY_QR_CORE_BASE 0x43C00000U

#define QR_REPLAY_QRF2_MAGIC 0x32465251U /* bytes Q R F 2 */
#define QR_REPLAY_QRS2_MAGIC 0x32535251U /* bytes Q R S 2 */
#define QR_REPLAY_PROTOCOL_VERSION 2U
#define QR_REPLAY_PIXEL_RGB565 1U

/* Packed wire header. All fields are little endian on the wire. */
#if defined(__GNUC__)
#define QR_REPLAY_PACKED __attribute__((packed))
#else
#define QR_REPLAY_PACKED
#endif
typedef struct QR_REPLAY_PACKED {
    uint32_t magic;
    uint8_t version;
    uint8_t pixel_format;
    uint16_t header_bytes;
    uint32_t frame_id;
    uint16_t packet_index;
    uint16_t packet_count;
    uint16_t width;
    uint16_t height;
    uint32_t payload_bytes;
    uint32_t frame_bytes;
    uint32_t frame_crc32;
    uint32_t reserved;
} qr_replay_qrf2_header_t;

typedef struct QR_REPLAY_PACKED {
    uint32_t magic;
    uint8_t version;
    uint8_t reserved0;
    uint16_t header_bytes;
    uint32_t frame_id;
    int32_t status;
    uint16_t stage;
    uint16_t instances;
    uint32_t payload_bytes;
    uint32_t pipeline_us;
    uint32_t total_us;
    uint32_t received_frames;
    uint32_t dropped_frames;
    uint32_t crc_dropped_frames;
    uint32_t packet_loss_frames;
    uint32_t packets_received;
    uint32_t packets_duplicate;
    uint32_t frame_packet_count;
    uint32_t frame_received_packets;
    uint32_t ring_overflow;
} qr_replay_qrs2_header_t;

typedef char qr_replay_qrf2_header_size_must_be_36[
    sizeof(qr_replay_qrf2_header_t) == 36U ? 1 : -1];
typedef char qr_replay_qrs2_header_size_must_be_68[
    sizeof(qr_replay_qrs2_header_t) == 68U ? 1 : -1];
typedef char qr_replay_frame2_must_not_overlap_gray[
    QR_REPLAY_FRAME2 + QR_REPLAY_FRAME_BYTES <= QR_REPLAY_GRAY_ADDR ? 1 : -1];

#endif
