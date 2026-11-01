/* VDMA S2MM 采集通道 + 三帧缓冲管理。
 *
 * 对外只暴露"策略无关"的原语，主循环负责时序与看门狗节拍。
 */
#ifndef VDMA_CAPTURE_H
#define VDMA_CAPTURE_H

#include "xil_types.h"

/* 配置并启动 S2MM（KEEP_HDMI_OUTPUT=1 时同时启动 MM2S）。 */
int capture_init(void);

/* 启动时实测"VDMA 正在写哪一个 frame store"。1 = 找到，0 = 一个都没写。 */
int capture_pick_active_frame(void);

/* SCU GIC + VDMA S2MM ISR。注意：当前**不使能** VDMA 中断（见 .c 里的说明），
 * 所以 ISR 实际不会触发，帧完成靠 capture_poll() 轮询。 */
int capture_irq_init(void);

/* 主循环每圈调用：采一次 S2MM 状态寄存器的 IOC 位（bit12）。 */
void capture_poll(void);

/* 有整帧完成则返回 1（并清标志）。 */
int capture_take_frame_ready(void);

/* 采集看门狗：S2MM 连续多次处于 Halted 就重启通道。 */
void capture_watchdog(void);

/* 选出"刚写完、接下来一整帧不会再被写"的帧缓冲，失效其 cache，
 * 返回可安全读取的基址（消除画面顶部的撕裂横条）。 */
const void *capture_begin_read(void);

/* 最近一次选中的缓冲索引（仅用于日志/调试）。 */
u32 capture_safe_index(void);

/* 诊断：把 IOC 计数推导出的索引与探针统计交出去（每 100 帧打印一次）。 */
void capture_debug(u32 *pick, u32 *copy_us, const u32 **n, const u32 **late);

#endif
