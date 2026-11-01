/* OV5640 初始化（SCCB over AXI IIC）。
 *
 * 三条上板实测得来的约束，改之前先读：
 *   1. 寄存器表在 ov5640_config.h。帧率 = PCLK / (HTS x VTS)，与分辨率一起由那张表决定。
 *   2. 时序类寄存器（0x380e/0x380f 的 VTS、0x3a02/0x3a03、0x3a14/0x3a15 抗闪烁步长）
 *      **必须在 stream-on(0x3008=0x02) 之前**下发：实测流启动后再写这些寄存器，
 *      AXI IIC 的 XIic_Send 会返回 0/1（失败），继续访问还会把应用卡死。
 *      ov5640_config.h 里的 OV5640_FAST_TIMING 块就是按这个顺序插进去的。
 *   3. 表里任何一条写失败都直接返回失败（避免"改了表但传感器没生效"这类静默问题）。
 */
#include "camera.h"
#include "board.h"
#include "i2c_bus.h"
#include "ov5640_config.h"

#include "xiic_l.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "sleep.h"

#define CAM_ADDR      0x3cU
#define CAM_ID_HI_REG 0x300aU
#define CAM_ID_LO_REG 0x300bU
#define CAM_ID_OV5640 0x5640U

/* 逐条打印寄存器表。
 *
 * 为什么默认打开：这张表有 250 多条 IIC 写，任何一条**卡住不动**时，串口只会
 * 停在 "OV5640 ID=0x5640" —— 完全看不出卡在哪一条。2026-10-03 的 1280x720
 * 档位就撞上了这个，只能靠瞎猜。打开以后最后一行就是"正在写的那一条"。
 *
 * 代价：约 260 行 / 5 KB 串口输出（115200 下 ≈0.5 s）。嫌吵可以
 * -DCAM_INIT_TRACE=0。
 */
#ifndef CAM_INIT_TRACE
#define CAM_INIT_TRACE 1
#endif

static u32 camera_table_len(void) {
    u32 n = 0U;
    while (g_ov5640_rgb565[n].reg != OV5640_REG_END) n++;
    return n;
}

static int camera_apply_table(void) {
    u32 i;

#if CAM_INIT_TRACE
    xil_printf("cam table: %u entries\r\n", (unsigned)camera_table_len());
#endif

    for (i = 0U; g_ov5640_rgb565[i].reg != OV5640_REG_END; ++i) {
        if (g_ov5640_rgb565[i].reg == OV5640_REG_DELAY) {
#if CAM_INIT_TRACE
            xil_printf("cam[%u] delay %u ms\r\n", (unsigned)i,
                       (unsigned)g_ov5640_rgb565[i].value);
#endif
            usleep((unsigned long)g_ov5640_rgb565[i].value * 1000UL);
        } else {
#if CAM_INIT_TRACE
            /* 先打印再写：卡死时最后一行 = 正在写的那一条 */
            xil_printf("cam[%u] %04x=%02x\r\n", (unsigned)i,
                       (unsigned)g_ov5640_rgb565[i].reg,
                       (unsigned)g_ov5640_rgb565[i].value);
#endif
            if (i2c_write_reg16(CAM_IIC_BASE, CAM_ADDR,
                                g_ov5640_rgb565[i].reg,
                                g_ov5640_rgb565[i].value) != XST_SUCCESS) {
                xil_printf("cam FAIL idx=%u reg=%04x val=%02x\r\n", (unsigned)i,
                           (unsigned)g_ov5640_rgb565[i].reg,
                           (unsigned)g_ov5640_rgb565[i].value);
                return XST_FAILURE;
            }
        }
    }
#if CAM_INIT_TRACE
    xil_printf("cam table done: %u entries\r\n", (unsigned)i);
#endif
    return XST_SUCCESS;
}

int camera_init(void) {
    u8 hi = 0U, lo = 0U;

    if (XIic_DynInit(CAM_IIC_BASE) != XST_SUCCESS) return XST_FAILURE;
    if (i2c_read_reg16(CAM_IIC_BASE, CAM_ADDR, CAM_ID_HI_REG, &hi) != XST_SUCCESS ||
        i2c_read_reg16(CAM_IIC_BASE, CAM_ADDR, CAM_ID_LO_REG, &lo) != XST_SUCCESS) {
        return XST_FAILURE;
    }
    xil_printf("OV5640 ID=0x%02x%02x\r\n", hi, lo);
    if ((((u16)hi << 8) | lo) != CAM_ID_OV5640) return XST_FAILURE;

    return camera_apply_table();
}
