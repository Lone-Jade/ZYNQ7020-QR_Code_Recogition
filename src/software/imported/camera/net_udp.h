/* 以太网：lwIP/EMAC 初始化、链路维护、视频帧 UDP 分片发送。 */
#ifndef NET_UDP_H
#define NET_UDP_H

#include "xil_types.h"

/* lwIP + EMAC + UDP socket 初始化（IP/端口见 ethernet_config.h）。 */
int net_init(void);

/* 主循环每圈调用：收包处理 + 周期检测链路状态并上报 PHY。 */
void net_service(void);

/* 链路是否就绪。 */
int net_link_up(void);

/* 把一帧原始像素（VIDEO_BYTES 字节）切成 UDP 包发出。
 * 返回实际发包数；链路未就绪或 socket 未建立时返回 0。 */
u32 net_send_video_frame(const void *src, u32 frame_number, int recording);

#endif
