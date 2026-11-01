/* 板级资源：AX7021B 上本工程用到的外设基址、MIO 按键、SIL9134 HDMI 发送器。
 *
 * 基址必须与位流里的地址分配一致（见 vivado/create_project.tcl 的 assign_bd_address）。
 */
#ifndef BOARD_H
#define BOARD_H

#include "xil_types.h"

#define CAM_IIC_BASE    0x41600000U   /* AXI IIC -> OV5640 (SCCB) */
#define HDMI_IIC_BASE   0x41610000U   /* AXI IIC -> SIL9134 */
#define VDMA_BASE       0x43000000U   /* AXI VDMA */
#define CAM_GPIO_BASE   0x41210000U   /* 摄像头复位/pwdn 控制位 */
#define HDMI_GPIO_BASE  0x41200000U

#define KEY1_MIO        11U

/* MIO 按键 KEY1 配成输入。必须在 board_key_pressed() 之前调用。 */
int  board_init(void);

/* 写 AXI GPIO 的单 bit 输出（base+4 是方向寄存器，先设成输出）。 */
void board_set_gpio(UINTPTR base, u32 value);

/* KEY1 是否按下（低电平有效）。 */
int  board_key_pressed(void);

/* SIL9134 上电 + 选 EDID 页。
 * 注意：当前应用**没有调用**它 —— 实测 HDMI 不初始化也能正常输出，
 * 而加入这两笔 I2C 反而增加启动风险。保留供需要时启用。 */
int  board_hdmi_init(void);

#endif
