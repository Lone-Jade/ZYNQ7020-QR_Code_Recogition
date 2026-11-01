/* 上行视频流的 24 字节包头（板卡 -> 上位机）。
 *
 * 权威实现同时存在于两处，改动必须成对：
 *   * 板卡端：net_udp.c 的 net_send_video_frame()
 *   * 上位机端：host/receiver.py 的解析逻辑
 *
 * 字节偏移（小端）：
 *   0..3   MAGIC 'O''V''5''6'
 *   4      协议版本 = 1
 *   5      像素格式 = 1（RGB565，注意本板字节序见 receiver.py 的说明）
 *   6..7   recording 标志（0/1）
 *   8..11  帧号（每帧递增）
 *   12..13 本帧内的分包序号
 *   14..15 本帧总包数
 *   16..17 宽（像素）
 *   18..19 高（像素）
 *   20..23 本包负载字节数
 *   24..   负载（RGB565 原始数据）
 */
#ifndef VIDEO_PROTOCOL_H
#define VIDEO_PROTOCOL_H

#define VIDEO_MAGIC0 'O'
#define VIDEO_MAGIC1 'V'
#define VIDEO_MAGIC2 '5'
#define VIDEO_MAGIC3 '6'

#define VIDEO_PROTO_VERSION 1U
#define VIDEO_PIXFMT_RGB565 1U

#define VIDEO_HDR_BYTES 24U

/* 单包最大负载。1400 = 以太网常见 MTU 上限（不含以太网头 14 + FCS 4），
 * 再扣掉 IPv4(20) + UDP(8) = 28 字节头。 */
#define VIDEO_UDP_DATAGRAM_MAX 1400U
#define VIDEO_MAX_PAYLOAD (VIDEO_UDP_DATAGRAM_MAX - 28U)

#endif
