/* 以太网：lwIP/EMAC 初始化、链路维护、视频帧 UDP 分片发送。
 *
 * PHY 是景略 JL2121，lwIP 自带驱动不认它，BSP 里打了补丁（见 vitis/apply_jl2121_patch.py），
 * 否则会从恒为 0x0000 的厂商状态页读速率、误判成 10 Mbps，表现为"链路通了但收不到包"。
 */
#include "net_udp.h"
#include "ethernet_config.h"
#include "video_protocol.h"
#include "vdma_capture.h"

#include "lwip/init.h"
#include "lwip/ip_addr.h"
#include "lwip/udp.h"
#include "netif/xadapter.h"
#include "netif/xemacpsif.h"
#include "xemac_ieee_reg.h"
#include "xil_printf.h"
#include "xstatus.h"

#include <string.h>

/* 链路状态轮询间隔（主循环圈数；空闲时约 1 ms 一圈）。 */
#define LINK_POLL_TICKS 100U

static struct netif netif0;
static struct udp_pcb *udp;
static enum ethernet_link_status link_state = ETH_LINK_UNDEFINED;
static u32 link_poll_ticks;

/* BSP 里由 xemacpsif 填好的 PHY 地址。 */
extern u32_t phyaddrforemac;

/* 24 字节包头按小端打包。注意 xil_printf 不支持 %l，日志统一用 %x/%u。 */
static void put_le16(u8 *p, u16 v) {
    p[0] = (u8)v;
    p[1] = (u8)(v >> 8);
}

static void put_le32(u8 *p, u32 v) {
    p[0] = (u8)v;
    p[1] = (u8)(v >> 8);
    p[2] = (u8)(v >> 16);
    p[3] = (u8)(v >> 24);
}

static void phy_report(void) {
    struct xemac_s *emac = (struct xemac_s *)netif0.state;
    xemacpsif_s *ps;
    u16 id1 = 0xffff, id2 = 0xffff, status = 0xffff;

    if (!emac || emac->type != xemac_type_emacps) return;
    ps = (xemacpsif_s *)emac->state;
    if (!ps) return;

    XEmacPs_PhyRead(&ps->emacps, phyaddrforemac, 2, &id1);
    XEmacPs_PhyRead(&ps->emacps, phyaddrforemac, 3, &id2);
    XEmacPs_PhyRead(&ps->emacps, phyaddrforemac, IEEE_STATUS_REG_OFFSET, &status);
    xil_printf("PHY addr=%d id=0x%04x:0x%04x status=0x%04x link=%d an=%d\r\n",
               (int)phyaddrforemac, (unsigned)id1, (unsigned)id2, (unsigned)status,
               (status & IEEE_STAT_LINK_STATUS) ? 1 : 0,
               (status & IEEE_STAT_AUTONEGOTIATE_COMPLETE) ? 1 : 0);
}

int net_init(void) {
    ip_addr_t ip, mask, gw;
    static unsigned char mac[6] = {0x00, 0x0a, 0x35, 0x00, 0x01, 0x02};

    IP4_ADDR(&ip, BOARD_IP0, BOARD_IP1, BOARD_IP2, BOARD_IP3);
    IP4_ADDR(&mask, 255, 255, 255, 0);
    IP4_ADDR(&gw, BOARD_IP0, BOARD_IP1, BOARD_IP2, 1);

    lwip_init();
    if (!xemac_add(&netif0, &ip, &mask, &gw, mac, XPAR_XEMACPS_0_BASEADDR)) {
        xil_printf("Ethernet add failed\r\n");
        return XST_FAILURE;
    }
    netif_set_default(&netif0);
    netif_set_up(&netif0);

    udp = udp_new();
    if (udp) udp_bind(udp, IP_ADDR_ANY, UDP_VIDEO_PORT);

    xil_printf("Ethernet0 IP %d.%d.%d.%d UDP %d\r\n",
               BOARD_IP0, BOARD_IP1, BOARD_IP2, BOARD_IP3, UDP_VIDEO_PORT);
    return udp ? XST_SUCCESS : XST_FAILURE;
}

void net_service(void) {
    int up;
    enum ethernet_link_status next;

    xemacif_input(&netif0);

    if (++link_poll_ticks >= LINK_POLL_TICKS) {
        link_poll_ticks = 0U;
        eth_link_detect(&netif0);
    }

    up = (netif0.flags & NETIF_FLAG_LINK_UP) != 0;
    next = up ? ETH_LINK_UP : ETH_LINK_DOWN;
    if (next != link_state) {
        link_state = next;
        xil_printf("Ethernet link state=%d flags=0x%02x\r\n",
                   (int)link_state, (unsigned)netif0.flags);
        phy_report();
    }
}

int net_link_up(void) {
    return (netif0.flags & NETIF_FLAG_LINK_UP) != 0;
}

u32 net_send_video_frame(const void *src, u32 frame_number, int recording) {
    const u8 *frame = (const u8 *)src;
    const u32 max_payload = VIDEO_MAX_PAYLOAD;
    const u32 count = (VIDEO_BYTES + max_payload - 1U) / max_payload;
    ip_addr_t dst;
    u32 i;

    if (!udp || !(netif0.flags & NETIF_FLAG_LINK_UP)) return 0U;

    IP4_ADDR(&dst, PC_IP0, PC_IP1, PC_IP2, PC_IP3);

    for (i = 0U; i < count; i++) {
        u32 off = i * max_payload;
        u32 n = (VIDEO_BYTES - off > max_payload) ? max_payload : (VIDEO_BYTES - off);
        u8 hdr[VIDEO_HDR_BYTES];
        struct pbuf *p;

        hdr[0] = VIDEO_MAGIC0;
        hdr[1] = VIDEO_MAGIC1;
        hdr[2] = VIDEO_MAGIC2;
        hdr[3] = VIDEO_MAGIC3;
        hdr[4] = (u8)VIDEO_PROTO_VERSION;
        hdr[5] = (u8)VIDEO_PIXFMT_RGB565;
        put_le16(&hdr[6], (u16)recording);
        put_le32(&hdr[8], frame_number);
        put_le16(&hdr[12], (u16)i);
        put_le16(&hdr[14], (u16)count);
        put_le16(&hdr[16], VIDEO_WIDTH);
        put_le16(&hdr[18], VIDEO_HEIGHT);
        put_le32(&hdr[20], n);

        p = pbuf_alloc(PBUF_TRANSPORT, VIDEO_HDR_BYTES + n, PBUF_RAM);
        if (!p) continue;
        memcpy(p->payload, hdr, VIDEO_HDR_BYTES);
        memcpy((u8 *)p->payload + VIDEO_HDR_BYTES, frame + off, n);
        udp_sendto(udp, p, &dst, UDP_VIDEO_PORT);
        pbuf_free(p);

        /* 每 32 个包（约 1 ms）看一眼 VDMA 的帧完成位。
         * 必要性：主循环一帧要花 ~28 ms，而采集是 20.8 ms 一帧 —— **主循环比采集慢**，
         * 只在主循环每圈调一次 capture_poll() 一定会漏掉帧完成事件；而 IOC 是粘滞
         * 单 bit，漏一次就永久错位，于是"刚写完的缓冲"判断全错，画面出现上下错位
         * 的横向撕裂。这里补上高频轮询就是为了不漏。 */
        if ((i & 0x1FU) == 0x1FU) {
            capture_poll();
        }
    }
    return count;
}
