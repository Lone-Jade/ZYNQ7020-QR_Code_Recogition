#ifndef ETHERNET_CONFIG_H
#define ETHERNET_CONFIG_H

/* ============================================================================
 * 视频档位（profile）
 * ----------------------------------------------------------------------------
 * 一个"档位"= 一组**必须同时成立**的参数：
 *
 *   [1] 传感器寄存器表   ov5640_config.h（PLL / 输出尺寸 / 裁剪窗口 / HTS / VTS / 0x4837）
 *   [2] 采集几何 + 帧缓冲 本文件（VIDEO_* 与 FRAME0..2）
 *   [3] 位流里的 RTL 宏    vivado/create_project.tcl + build_bitstream.tcl 的
 *                         OV5640_CAP_PIXELS / OV5640_CAP_LINES
 *
 * 三者必须一致。**不一致的典型症状**：ELF 按 1280 宽发帧、而位流的 capture RTL
 * 每 800 像素就发一次 tlast -> S2MM 认为"实际收到的行数据多于设定"报
 * ERR_FSZ_MORE 并自行 halt -> 看门狗反复把它拉起来 -> 画面撕裂 + 闪烁。
 * 2026-10-03 就是这么烧进去一份 1280x720 的 ELF 配 800x600 的位流，实际表现
 * 正是"分辨率变成 1280x720、画面撕裂闪烁"。
 *
 * 所以：换档位 = 改这里 + 改 ov5640_config.h + 重跑位流，然后重新构建 ELF。
 * program_and_run.py 会在烧录前用 VIDEO_PROFILE_SIG 校验 ELF 的档位，避免再
 * 烧错。
 * ==========================================================================*/

#define VIDEO_PROFILE_800x600_48FPS 1
#define VIDEO_PROFILE_1280x720_30FPS  2

/* 当前档位。可用 -DVIDEO_PROFILE=... 覆盖（build_vitis.ps1 传参用）。 */
/* 本工程固定为 VIDEO_PROFILE_1280x720_30FPS（两套工程各自独立，不靠环境变量切换）。 */
#define VIDEO_PROFILE VIDEO_PROFILE_1280x720_30FPS

#if VIDEO_PROFILE == VIDEO_PROFILE_800x600_48FPS
/* AX7021B 实板**已上板验证**的档位。传感器：ov5640_1 的 workspace_2025_svga 那一版。 */
#define VIDEO_WIDTH        800U
#define VIDEO_HEIGHT       600U
#define VIDEO_FPS_TARGET   48U
#define VIDEO_PROFILE_NAME "800x600_48fps"
/* 帧缓冲：三帧循环，间距 = 每帧字节数（0xEA600 = 960000）。 */
#define FRAME0 0x10000000U
#define FRAME1 0x100EA600U
#define FRAME2 0x101D4C00U
/* 发送快照缓冲：不参与 VDMA 轮转，专门用来把一帧拷出来再发。
 * 必要性见 vdma_capture.c 里 capture_begin_read() 的说明。 */
#define FRAME_SNAPSHOT 0x102BF200U
/* 档位签名（只读字符串，编译进 ELF 供 program_and_run.py 校验）。 */
#define VIDEO_PROFILE_SIG \
    "OV5640ETH;PROFILE=800x600_48fps;W=800;H=600;BYTES=960000;PKTS=700"

#elif VIDEO_PROFILE == VIDEO_PROFILE_1280x720_30FPS
/* 1280x720@30fps。**必须配 OV5640_CAP_PIXELS=1280 / OV5640_CAP_LINES=720 的位流**。 */
#define VIDEO_WIDTH        1280U
#define VIDEO_HEIGHT       720U
#define VIDEO_FPS_TARGET   30U
#define VIDEO_PROFILE_NAME "1280x720_30fps"
/* 帧缓冲：间距 = 每帧字节数（0x1C2000 = 1843200）。 */
#define FRAME0 0x10000000U
#define FRAME1 0x101C2000U
#define FRAME2 0x10384000U
/* 发送快照缓冲：不参与 VDMA 轮转，专门用来把一帧拷出来再发。
 * 必要性见 vdma_capture.c 里 capture_begin_read() 的说明。 */
#define FRAME_SNAPSHOT 0x10546000U
#define VIDEO_PROFILE_SIG \
    "OV5640ETH;PROFILE=1280x720_30fps;W=1280;H=720;BYTES=1843200;PKTS=1344"

#else
#error "未知的 VIDEO_PROFILE；可选 VIDEO_PROFILE_800x600_48FPS / VIDEO_PROFILE_1280x720_30FPS"
#endif

#define VIDEO_STRIDE (VIDEO_WIDTH * 2U)
#define VIDEO_BYTES  (VIDEO_STRIDE * VIDEO_HEIGHT)

/* ---- 网络 -----------------------------------------------------------------*/
#define ETH_APP_MODE_LIVE 1
#define ETH_APP_MODE_KEY_RECORD 2
#define ETH_APP_MODE ETH_APP_MODE_KEY_RECORD

/* 1 = 按 ov5640_1 已上板验证的配置：同时启动 VDMA MM2S 读通道。
 * 内部 Genlock 下 MM2S 是动态从通道、S2MM 是动态主通道；实测必须让 MM2S 也跑起来，
 * 采集才稳定（只跑 S2MM 时 VDMA 不往 DDR 写数据）。
 * 0 = 只跑采集通路（位流里没有 MM2S 时用这个）。
 * 注意：位流里到底有没有 MM2S 由 BSP 的 HasMm2S 决定，见 vdma_capture.c。 */
#define KEEP_HDMI_OUTPUT 1

#define BOARD_IP0 192
#define BOARD_IP1 168
#define BOARD_IP2 1
#define BOARD_IP3 11
#define PC_IP0 192
#define PC_IP1 168
#define PC_IP2 1
/* 上位机地址。本机有线网卡是静态 192.168.1.42，所以这里是 .42。
 * 换机器时把这一行改成你 PC 网卡的实际地址即可（也可反过来把网卡设成 .10）。 */
#define PC_IP3 42
#define UDP_VIDEO_PORT 8080

/* ---- 采集看门狗 -----------------------------------------------------------
 * 检查周期（单位是主循环次数，空闲时约 1 ms 一圈，33 ≈ 33 ms）。
 * 连续 10 次判定为"死了"才重启通道。
 *
 * 为什么会"死"：启动瞬间 cam1_pclk / DVP 时序还没稳，或者**采集几何与位流不一致**时，
 * VDMA 会报 ERR_FSZ_MORE / ERR_INTERNAL 并自行 halt。halt 之后三个帧缓冲冻住，
 * 表现为"画面定格"。看门狗负责救回来。
 *
 * 注意：错误位是**锁存**的，启动时报过一次就会一直读到，所以只看 Halted 位；
 * 且必须"连续多次 + 期间没有任何帧完成"才算死，否则会把健康的通道打断
 * （打断本身就会带来撕裂/闪烁）。 */
#define FALLBACK_TICKS 33U
#define S2MM_DEAD_LIMIT 10U

/* 重启通道后先丢掉这么多帧再往外发，避免把"半新半旧"的撕裂帧发出去。 */
#define POST_RECOVER_SKIP_FRAMES 2U

/* ---- 吞吐探顶实验（不改传感器、不改位流，只换 ELF）-------------------------
 * 每个采集帧连续发 N 份（内容相同、帧号递增），用来单独测"这条 UDP 通路
 * 到底能跑多快"。N=1 = 正常行为。详见 THROUGHPUT_PROBE.md。 */
#define SEND_REPEAT 1U

#endif
