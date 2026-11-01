#include "net_replay.h"
#include "ethernet_config.h"

#include "lwip/init.h"
#include "lwip/ip_addr.h"
#include "lwip/udp.h"
#include "netif/xadapter.h"
#include "netif/xemacpsif.h"
#include "xemac_ieee_reg.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "xparameters.h"
#include "xtime_l.h"

#include <string.h>

#ifndef QR_REPLAY_TRANSPORT_ONLY
#define QR_REPLAY_TRANSPORT_ONLY 0
#endif

#ifndef QR_CAMERA_LIVE
#define QR_CAMERA_LIVE 0
#endif

typedef struct {
    uint8_t used;
    uint8_t state; /* 1 RECEIVING, 2 READY, 3 PROCESSING */
    uint32_t frame_id;
    uint32_t crc;
    uint32_t crc_value;
    uint32_t crc_offset;
    uint16_t packet_count;
    uint16_t received;
    uint8_t bitmap[QR_REPLAY_PACKET_COUNT];
} receive_slot_t;

static struct netif g_netif;
static struct udp_pcb *g_input_udp;
static struct udp_pcb *g_result_udp;
static receive_slot_t g_slots[3];
static uint32_t g_received_frames;
static uint32_t g_dropped_frames;
static uint32_t g_crc_dropped_frames;
static uint32_t g_packet_loss_frames;
static uint32_t g_packets_received;
static uint32_t g_packets_duplicate;
static uint32_t g_ring_overflow;
static uint32_t g_ready_id;
static UINTPTR g_ready_address;
static uint8_t g_ready;
static XTime g_link_poll_time;
static uint8_t g_link_poll_time_valid;
static int g_last_link = -1;
static XTime g_rx_window_start;
static uint32_t g_rx_window_frames;
static uint32_t g_rx_fps_milli;
static uint32_t g_crc32_table[4][256];
static uint8_t g_crc32_table_ready;
static uint32_t g_latest_frame_id;
static uint8_t g_have_latest_frame;
static uint32_t g_rejected_frame_ids[4];
static uint8_t g_rejected_frame_valid[4];
static uint8_t g_rejected_frame_next;
static uint32_t g_net_service_packets;
static uint32_t g_net_service_budget_hits;
#if !QR_REPLAY_TRANSPORT_ONLY
static XTime g_last_admitted_tick;
static uint8_t g_have_last_admitted_tick;
#endif

/* xemacpsif_input() deliberately hands one queued RX packet to lwIP per
 * call. Drain a bounded batch on every service call so the pbuf pool cannot
 * accumulate a full-frame backlog while QR processing is active. */
#define QR_REPLAY_RX_SERVICE_BUDGET 1024U

static UINTPTR slot_address(unsigned index);
static receive_slot_t *find_slot(uint32_t id);

static int frame_is_rejected(uint32_t frame_id) {
    unsigned i;
    for (i = 0; i < 4U; ++i)
        if (g_rejected_frame_valid[i] && g_rejected_frame_ids[i] == frame_id)
            return 1;
    return 0;
}

static void reject_frame(uint32_t frame_id) {
    if (frame_is_rejected(frame_id))
        return;
    g_rejected_frame_ids[g_rejected_frame_next] = frame_id;
    g_rejected_frame_valid[g_rejected_frame_next] = 1U;
    g_rejected_frame_next = (uint8_t)((g_rejected_frame_next + 1U) % 4U);
    ++g_ring_overflow;
    ++g_dropped_frames;
}

#if !QR_REPLAY_TRANSPORT_ONLY
static void drop_frame_by_admission(uint32_t frame_id) {
    if (frame_is_rejected(frame_id))
        return;
    g_rejected_frame_ids[g_rejected_frame_next] = frame_id;
    g_rejected_frame_valid[g_rejected_frame_next] = 1U;
    g_rejected_frame_next = (uint8_t)((g_rejected_frame_next + 1U) % 4U);
    ++g_dropped_frames;
}

static int processing_active(void) {
    unsigned i;
    for (i = 0; i < 3U; ++i)
        if (g_slots[i].used && g_slots[i].state == 3U)
            return 1;
    return 0;
}
#endif

static void report_link_state(void) {
    int link = (g_netif.flags & NETIF_FLAG_LINK_UP) != 0;
    if (link == g_last_link) return;
    g_last_link = link;
    xil_printf("QR replay Ethernet link=%s flags=0x%02x\r\n", link ? "UP" : "DOWN", (unsigned)g_netif.flags);
}

static uint32_t crc32_update(uint32_t crc, const uint8_t *data, uint32_t length) {
    uint32_t i;
    if (!g_crc32_table_ready) {
        for (i = 0; i < 256U; ++i) {
            uint32_t value = i;
            unsigned bit;
            for (bit = 0; bit < 8U; ++bit)
                value = (value >> 1) ^ ((value & 1U) ? 0xEDB88320U : 0U);
            g_crc32_table[0][i] = value;
        }
        for (i = 0; i < 256U; ++i) {
            uint32_t value = g_crc32_table[0][i];
            unsigned slice;
            for (slice = 1U; slice < 4U; ++slice) {
                value = (value >> 8) ^ g_crc32_table[0][value & 0xFFU];
                g_crc32_table[slice][i] = value;
            }
        }
        g_crc32_table_ready = 1U;
    }
    while (length >= 4U) {
        uint32_t word;
        memcpy(&word, data, sizeof(word));
        crc ^= word;
        crc = g_crc32_table[3][crc & 0xFFU] ^
              g_crc32_table[2][(crc >> 8) & 0xFFU] ^
              g_crc32_table[1][(crc >> 16) & 0xFFU] ^
              g_crc32_table[0][crc >> 24];
        data += 4U;
        length -= 4U;
    }
    while (length--)
        crc = (crc >> 8) ^ g_crc32_table[0][(crc ^ *data++) & 0xFFU];
    return crc;
}

static void mark_frame_ready(receive_slot_t *slot) {
    if (g_ready && (int32_t)(slot->frame_id - g_ready_id) <= 0) {
        ++g_dropped_frames;
        memset(slot, 0, sizeof(*slot));
        return;
    }
    slot->state = 2U;
    g_received_frames++;
    if (g_rx_window_frames == 0U) XTime_GetTime(&g_rx_window_start);
    ++g_rx_window_frames;
    {
        XTime now;
        uint64_t elapsed_ticks;
        XTime_GetTime(&now);
        elapsed_ticks = (uint64_t)(now - g_rx_window_start);
        if (elapsed_ticks >= (uint64_t)(COUNTS_PER_SECOND / 2U)) {
            g_rx_fps_milli = (uint32_t)(((uint64_t)g_rx_window_frames * 1000ULL *
                                         (uint64_t)COUNTS_PER_SECOND) / elapsed_ticks);
            g_rx_window_frames = 0U;
        }
    }
    if (g_ready) {
        receive_slot_t *previous = find_slot(g_ready_id);
        if (previous) memset(previous, 0, sizeof(*previous));
        g_dropped_frames++;
    }
    g_ready_id = slot->frame_id;
    g_ready_address = slot_address((unsigned)(slot - g_slots));
    g_ready = 1U;
}

static void service_rx(void) {
    unsigned serviced = 0U;
    int received;
    do {
        received = xemacif_input(&g_netif);
        if (received > 0) {
            g_net_service_packets += (uint32_t)received;
            serviced += (unsigned)received;
        }
    } while (received > 0 && serviced < QR_REPLAY_RX_SERVICE_BUDGET &&
             (!QR_REPLAY_TRANSPORT_ONLY || !g_ready));
    if (serviced >= QR_REPLAY_RX_SERVICE_BUDGET)
        ++g_net_service_budget_hits;
}

static UINTPTR slot_address(unsigned index) {
    static const UINTPTR addresses[3] = { QR_REPLAY_FRAME0, QR_REPLAY_FRAME1, QR_REPLAY_FRAME2 };
    return addresses[index % 3U];
}

static receive_slot_t *find_slot(uint32_t id) {
    unsigned i;
    for (i = 0; i < 3U; ++i)
        if (g_slots[i].used && g_slots[i].frame_id == id) return &g_slots[i];
    return 0;
}

static void expire_incomplete_frames(uint32_t newest_id) {
    unsigned i;
    for (i = 0; i < 3U; ++i) {
        receive_slot_t *slot = &g_slots[i];
        uint32_t age;
        if (!slot->used || slot->state != 1U)
            continue;
        age = newest_id - slot->frame_id;
        if (age >= 3U && age < 0x80000000U) {
            ++g_packet_loss_frames;
            ++g_dropped_frames;
            memset(slot, 0, sizeof(*slot));
        }
    }
}

static receive_slot_t *allocate_slot(uint32_t id) {
    unsigned i;
    receive_slot_t *oldest = 0;
#if !QR_REPLAY_TRANSPORT_ONLY
    XTime now;
    uint64_t admission_ms;
    XTime_GetTime(&now);
    admission_ms = processing_active() ? 50ULL : 30ULL;
    if (g_have_last_admitted_tick &&
        (uint64_t)(now - g_last_admitted_tick) <
            (uint64_t)(((uint64_t)COUNTS_PER_SECOND * admission_ms) / 1000ULL)) {
        drop_frame_by_admission(id);
        return 0;
    }
    g_last_admitted_tick = now;
    g_have_last_admitted_tick = 1U;
#endif
    for (i = 0; i < 3U; ++i) {
        if (!g_slots[i].used) {
            memset(&g_slots[i], 0, sizeof(g_slots[i]));
            g_slots[i].used = 1U;
            g_slots[i].state = 1U;
            g_slots[i].frame_id = id;
            return &g_slots[i];
        }
        if (g_slots[i].state == 2U &&
            (!oldest || g_slots[i].frame_id < oldest->frame_id))
            oldest = &g_slots[i];
    }
    if (oldest) {
        if (oldest->state == 2U && g_ready && oldest->frame_id == g_ready_id) g_ready = 0U;
        g_dropped_frames++;
        memset(oldest, 0, sizeof(*oldest));
        oldest->used = 1U;
        oldest->state = 1U;
        oldest->frame_id = id;
        return oldest;
    }
    reject_frame(id);
    return 0;
}

static void input_callback(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                           const ip_addr_t *addr, u16_t port) {
    qr_replay_qrf2_header_t header;
    receive_slot_t *slot;
    uint8_t *destination;
    uint32_t offset;
    (void)arg; (void)pcb; (void)addr; (void)port;
    if (!p || p->tot_len < sizeof(header)) { if (p) pbuf_free(p); return; }
    pbuf_copy_partial(p, &header, sizeof(header), 0);
    if (header.magic != QR_REPLAY_QRF2_MAGIC || header.version != QR_REPLAY_PROTOCOL_VERSION ||
        header.pixel_format != QR_REPLAY_PIXEL_RGB565 || header.header_bytes != sizeof(header) ||
        header.width != QR_REPLAY_WIDTH || header.height != QR_REPLAY_HEIGHT ||
        header.frame_bytes != QR_REPLAY_FRAME_BYTES || header.packet_count != QR_REPLAY_PACKET_COUNT ||
        header.packet_index >= header.packet_count || header.payload_bytes > QR_REPLAY_PAYLOAD_BYTES ||
        p->tot_len != sizeof(header) + header.payload_bytes) {
        pbuf_free(p); return;
    }
    if (!g_have_latest_frame || (int32_t)(header.frame_id - g_latest_frame_id) > 0) {
        g_latest_frame_id = header.frame_id;
        g_have_latest_frame = 1U;
        expire_incomplete_frames(header.frame_id);
    } else if ((uint32_t)(g_latest_frame_id - header.frame_id) >= 3U &&
               (uint32_t)(g_latest_frame_id - header.frame_id) < 0x80000000U) {
        pbuf_free(p);
        return;
    }
    if (frame_is_rejected(header.frame_id)) {
        pbuf_free(p);
        return;
    }
    slot = find_slot(header.frame_id);
    if (!slot) slot = allocate_slot(header.frame_id);
    if (!slot) { pbuf_free(p); return; }
    if (slot->packet_count == 0U) {
        slot->packet_count = header.packet_count;
        slot->crc = header.frame_crc32;
        slot->crc_value = 0xFFFFFFFFU;
    }
    if (slot->packet_count != header.packet_count || slot->crc != header.frame_crc32) { pbuf_free(p); return; }
    if (slot->bitmap[header.packet_index]) { g_packets_duplicate++; pbuf_free(p); return; }
    offset = (uint32_t)header.packet_index * QR_REPLAY_PAYLOAD_BYTES;
    if (offset >= QR_REPLAY_FRAME_BYTES ||
        header.payload_bytes != ((QR_REPLAY_FRAME_BYTES - offset > QR_REPLAY_PAYLOAD_BYTES) ? QR_REPLAY_PAYLOAD_BYTES : (QR_REPLAY_FRAME_BYTES - offset))) {
        pbuf_free(p); return;
    }
    destination = (uint8_t *)(slot_address((unsigned)(slot - g_slots)) + offset);
    pbuf_copy_partial(p, destination, header.payload_bytes, sizeof(header));
    slot->bitmap[header.packet_index] = 1U;
    slot->received++;
    g_packets_received++;
    while (slot->crc_offset < slot->packet_count && slot->bitmap[slot->crc_offset]) {
        uint32_t crc_packet_offset = slot->crc_offset * QR_REPLAY_PAYLOAD_BYTES;
        uint32_t crc_packet_length = QR_REPLAY_FRAME_BYTES - crc_packet_offset;
        const uint8_t *crc_data;
        if (crc_packet_length > QR_REPLAY_PAYLOAD_BYTES)
            crc_packet_length = QR_REPLAY_PAYLOAD_BYTES;
        crc_data = (const uint8_t *)(slot_address((unsigned)(slot - g_slots)) +
                                     crc_packet_offset);
        slot->crc_value = crc32_update(slot->crc_value, crc_data, crc_packet_length);
        slot->crc_offset++;
    }
    if (slot->received == slot->packet_count) {
        Xil_DCacheFlushRange((INTPTR)slot_address((unsigned)(slot - g_slots)),
                             QR_REPLAY_FRAME_BYTES);
        if (slot->crc_offset != slot->packet_count ||
            (slot->crc_value ^ 0xFFFFFFFFU) != slot->crc) {
            g_crc_dropped_frames++;
            g_dropped_frames++;
            memset(slot, 0, sizeof(*slot));
        } else {
            mark_frame_ready(slot);
        }
    }
    pbuf_free(p);
}

int qr_replay_net_init(void) {
    ip_addr_t ip, mask, gw;
    static unsigned char mac[6] = {0x00, 0x0a, 0x35, 0x00, 0x01, 0x12};
    IP4_ADDR(&ip, BOARD_IP0, BOARD_IP1, BOARD_IP2, BOARD_IP3);
    IP4_ADDR(&mask, 255, 255, 255, 0);
    IP4_ADDR(&gw, BOARD_IP0, BOARD_IP1, BOARD_IP2, 1);
    lwip_init();
    if (!xemac_add(&g_netif, &ip, &mask, &gw, mac, XPAR_XEMACPS_0_BASEADDR)) return XST_FAILURE;
    netif_set_default(&g_netif); netif_set_up(&g_netif);
    g_input_udp = udp_new(); g_result_udp = udp_new();
    if (!g_input_udp || !g_result_udp) return XST_FAILURE;
    udp_bind(g_input_udp, IP_ADDR_ANY, QR_REPLAY_INPUT_PORT);
    udp_recv(g_input_udp, input_callback, 0);
    udp_bind(g_result_udp, IP_ADDR_ANY, QR_REPLAY_RESULT_PORT);
    xil_printf("QR Ethernet %d.%d.%d.%d mode=%s result=%d\r\n",
               BOARD_IP0, BOARD_IP1, BOARD_IP2, BOARD_IP3,
               QR_CAMERA_LIVE ? "camera" : "replay", QR_REPLAY_RESULT_PORT);
    return XST_SUCCESS;
}

void qr_replay_net_service(void) {
    XTime now;
    service_rx();
    XTime_GetTime(&now);
    /* The replay loop can run much faster than the camera application.  A
     * loop-count poll would call eth_link_detect repeatedly during PHY
     * autonegotiation and can force a false DOWN/re-negotiation transition.
     * Use wall-clock time so the PHY is checked about once per second. */
    if (!g_link_poll_time_valid ||
        (uint64_t)(now - g_link_poll_time) >= (uint64_t)COUNTS_PER_SECOND) {
        g_link_poll_time = now;
        g_link_poll_time_valid = 1U;
        eth_link_detect(&g_netif);
        report_link_state();
    }
}
int qr_replay_net_link_up(void) { return (g_netif.flags & NETIF_FLAG_LINK_UP) != 0; }

int qr_replay_take_ready_frame(uint32_t *frame_id, UINTPTR *address) {
    if (!g_ready) return 0;
    *frame_id = g_ready_id; *address = g_ready_address; g_ready = 0U;
    {
        receive_slot_t *slot = find_slot(*frame_id);
        if (slot) slot->state = 3U; /* PROCESSING; never overwrite until release */
    }
    return 1;
}

void qr_replay_release_frame(uint32_t frame_id) {
    receive_slot_t *slot = find_slot(frame_id);
    if (slot) memset(slot, 0, sizeof(*slot));
}

void qr_replay_publish_result(uint32_t frame_id, int status, uint32_t stage, uint32_t instances,
                              const char *payload, uint32_t pipeline_us, uint32_t total_us) {
    qr_replay_qrs2_header_t header;
    ip_addr_t destination;
    struct pbuf *packet;
    uint32_t payload_bytes = payload ? (uint32_t)strlen(payload) : 0U;
    IP4_ADDR(&destination, PC_IP0, PC_IP1, PC_IP2, PC_IP3);
    if (!g_result_udp || !qr_replay_net_link_up() || payload_bytes > 8192U) return;
    memset(&header, 0, sizeof(header)); header.magic = QR_REPLAY_QRS2_MAGIC; header.version = QR_REPLAY_PROTOCOL_VERSION;
    header.header_bytes = sizeof(header); header.frame_id = frame_id; header.status = status; header.stage = (uint16_t)stage;
    header.instances = (uint16_t)instances; header.payload_bytes = payload_bytes; header.pipeline_us = pipeline_us; header.total_us = total_us;
    header.received_frames = g_received_frames; header.dropped_frames = g_dropped_frames; header.crc_dropped_frames = g_crc_dropped_frames;
    header.packet_loss_frames = g_packet_loss_frames;
    header.packets_received = g_packets_received; header.packets_duplicate = g_packets_duplicate;
    {
        receive_slot_t *slot = find_slot(frame_id);
        header.frame_packet_count = slot ? slot->packet_count :
                                    (QR_CAMERA_LIVE ? 0U : QR_REPLAY_PACKET_COUNT);
        header.frame_received_packets = slot ? slot->received :
                                      (QR_CAMERA_LIVE ? 0U : QR_REPLAY_PACKET_COUNT);
    }
    header.ring_overflow = g_ring_overflow;
    packet = pbuf_alloc(PBUF_TRANSPORT, sizeof(header) + payload_bytes, PBUF_RAM);
    if (!packet) return;
    memcpy(packet->payload, &header, sizeof(header)); if (payload_bytes) memcpy((uint8_t *)packet->payload + sizeof(header), payload, payload_bytes);
    udp_sendto(g_result_udp, packet, &destination, QR_REPLAY_RESULT_PORT); pbuf_free(packet);
}

uint32_t qr_replay_received_frames(void) { return g_received_frames; }
uint32_t qr_replay_dropped_frames(void) { return g_dropped_frames; }
uint32_t qr_replay_crc_dropped_frames(void) { return g_crc_dropped_frames; }
uint32_t qr_replay_packets_received(void) { return g_packets_received; }
uint32_t qr_replay_packets_duplicate(void) { return g_packets_duplicate; }
uint32_t qr_replay_ring_overflow(void) { return g_ring_overflow; }
uint32_t qr_replay_receive_fps_milli(void) { return g_rx_fps_milli; }
