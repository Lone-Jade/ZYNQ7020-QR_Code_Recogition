/* 应用入口：上电时序 + 主循环。
 *
 * 模块划分（每个模块的细节、以及"为什么这么写"的踩坑记录都在它自己的 .c 里）：
 *   board.c        —— 外设基址、MIO 按键、SIL9134 HDMI 发送器
 *   i2c_bus.c      —— AXI IIC 寄存器级读写（SCCB / I2C 共用）
 *   camera.c       —— OV5640 初始化（SCCB + ov5640_config.h 的寄存器表）
 *   vdma_capture.c —— VDMA S2MM 通道、三帧缓冲、采集看门狗、防撕裂选帧
 *   net_udp.c      —— lwIP/EMAC、链路维护、视频帧 UDP 分片发送
 *   main.c         —— 启动时序与主循环（本文件只放"策略"，不放寄存器操作）
 */
#include "board.h"
#include "camera.h"
#include "ethernet_config.h"
#include "net_udp.h"
#include "ov5640_config.h"
#include "video_protocol.h"
#include "vdma_capture.h"

#include "xil_printf.h"
#include "xstatus.h"
#include "sleep.h"

/* 把实验开关的值原样编进字符串常量：这样用"二进制里有没有 SEND_REPEAT=4"
 * 就能直接校验烧进去的到底是哪一版镜像，不依赖串口。 */
#define STR2(x) #x
#define STR(x) STR2(x)

static volatile int recording;
static u32 frame_number;

/* 档位签名。**故意做成全局、非 static，并且真的被打印**：这样它一定留在 ELF 的
 * 只读段里，program_and_run.py 可以直接在 ELF 二进制里搜这个字符串，确认
 * "这份 ELF 就是我要烧的档位"。
 *
 * 为什么需要它：build/ 目录里的 ELF 可能比源码**新**，但内容是更早的实验版本
 * （2026-10-03 实际烧进去的就是一份 1280x720 的旧 ELF，却配着 800x600 的位流）。
 * 只看文件时间戳判断不出来，只能靠签名。 */
const char g_video_profile_sig[] = VIDEO_PROFILE_SIG;

/* KEY1 按一下切换录制标志：下降沿触发 + 30 ms 消抖确认。 */
static void poll_key(void) {
    static int last_pressed = 0;
    int now = board_key_pressed();

    if (ETH_APP_MODE == ETH_APP_MODE_KEY_RECORD && now && !last_pressed) {
        usleep(30000);
        if (board_key_pressed()) {
            recording = !recording;
            xil_printf("recording=%d\r\n", recording);
        }
    }
    last_pressed = now;
}

int main(void) {
    xil_printf("OV5640 Ethernet live/key-record demo\r\n");
    xil_printf("BUILD SEND_REPEAT=" STR(SEND_REPEAT)
               " OV5640_FAST_TIMING=" STR(OV5640_FAST_TIMING) "\r\n");
    xil_printf("PROFILE %s\r\n", g_video_profile_sig);
    xil_printf("IP %d.%d.%d.%d UDP %d\r\n",
               BOARD_IP0, BOARD_IP1, BOARD_IP2, BOARD_IP3, UDP_VIDEO_PORT);
    xil_printf("HDMI output: %s\r\n", KEEP_HDMI_OUTPUT ? "on" : "off");

    /* 摄像头复位/pwdn 时序：低-高各留 500 ms。 */
    board_set_gpio(CAM_GPIO_BASE, 1U);
    usleep(500000);
    board_set_gpio(CAM_GPIO_BASE, 0U);
    usleep(500000);
    board_set_gpio(CAM_GPIO_BASE, 1U);
    usleep(500000);

    xil_printf("Starting camera init...\r\n");
    if (camera_init() != XST_SUCCESS) xil_printf("WARNING: camera init failed\r\n");
    if (capture_init() != XST_SUCCESS) xil_printf("WARNING: VDMA init failed\r\n");
    capture_pick_active_frame();

    if (board_init() != XST_SUCCESS) xil_printf("WARNING: MIO key init failed\r\n");
    if (capture_irq_init() != XST_SUCCESS) {
        xil_printf("WARNING: VDMA IRQ init failed; using timed fallback\r\n");
    }
    if (net_init() != XST_SUCCESS) xil_printf("WARNING: Ethernet init failed\r\n");

    for (;;) {
        poll_key();
        net_service();
        if (ETH_APP_MODE == ETH_APP_MODE_LIVE) recording = 0;

        capture_poll();
        capture_watchdog();

        if (capture_take_frame_ready()) {
            u32 rep;
            /* SEND_REPEAT > 1 只在吞吐探顶实验里用（见 THROUGHPUT_PROBE.md）。 */
            for (rep = 0U; rep < SEND_REPEAT; rep++) {
                const void *src = capture_begin_read();

                if (!src) {
                    /* 防撕裂选帧还没建立可信基线（刚上电 / 刚重启 S2MM）。
                     * 这一帧**不发** —— 宁可不发，也不要把"正在被写"的缓冲
                     * 发出去（那正是上半部横条撕裂的来源）。 */
                    frame_number++;
                    continue;
                }
                if (frame_number <= 3U || frame_number == 200U) {
                    /* 注意：xil_printf 不支持 %l 修饰符，写 %lx/%lu 会把参数当 64 位
                     * 读导致串位，所以这里统一用 %x / %u。 */
                    xil_printf("DBG frame=%u idx=%u src=0x%08x w0=0x%08x w1=0x%08x w2=0x%08x\r\n",
                               (unsigned)frame_number, (unsigned)capture_safe_index(),
                               (unsigned)(UINTPTR)src,
                               (unsigned)((const volatile u32 *)src)[0],
                               (unsigned)((const volatile u32 *)src)[1],
                               (unsigned)((const volatile u32 *)src)[2]);
                }
                /* 每 100 帧一次诊断：cidx=刚写完的缓冲，nxt=下次会写的，
                 * done=累计完成帧数，n/late=探针统计（变了几个采样行/靠后的行变没变）。
                 * 判读：若 done 的增长远慢于 frame 的增长，说明还在漏 IOC；
                 *       若 n[] 里始终只有一个非 0，说明 VDMA 其实没在三个缓冲间轮转。 */
                if ((frame_number % 100U) == 0U) {
                    u32 d_pick = 0U, d_copy = 0U;
                    const u32 *d_n = 0;
                    const u32 *d_late = 0;
                    capture_debug(&d_pick, &d_copy, &d_n, &d_late);
                    xil_printf("DBG100 frame=%u pick=%u copy_us=%u n=%u,%u,%u late=%u%u%u\r\n",
                               (unsigned)frame_number, (unsigned)d_pick, (unsigned)d_copy,
                               d_n ? (unsigned)d_n[0] : 0U,
                               d_n ? (unsigned)d_n[1] : 0U,
                               d_n ? (unsigned)d_n[2] : 0U,
                               d_late ? (unsigned)d_late[0] : 0U,
                               d_late ? (unsigned)d_late[1] : 0U,
                               d_late ? (unsigned)d_late[2] : 0U);
                }
                net_send_video_frame(src, frame_number, recording);
                frame_number++;
            }
        } else {
            usleep(1000);
        }
    }
}
