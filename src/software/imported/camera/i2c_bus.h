/* AXI IIC 的寄存器级读写（动态模式）。
 *
 * OV5640 用 SCCB 兼容时序（16 位寄存器地址），SIL9134 用标准 I2C（8 位寄存器地址），
 * 两种寻址方式都在这里。
 *
 * 关于寄存器地址宽度：函数名的 16/8 指的是**寄存器地址宽度**，不是数据宽度；
 * 数据一律 8 位。
 */
#ifndef I2C_BUS_H
#define I2C_BUS_H

#include "xil_types.h"

/* 写：先发 16 位寄存器地址，再发 1 字节数据。 */
int i2c_write_reg16(UINTPTR base, u8 dev_addr, u16 reg, u8 value);

/* 写：先发 8 位寄存器地址，再发 1 字节数据。 */
int i2c_write_reg8(UINTPTR base, u8 dev_addr, u8 reg, u8 value);

/* 读：重复起始 + 16 位寄存器地址，读回 1 字节。 */
int i2c_read_reg16(UINTPTR base, u8 dev_addr, u16 reg, u8 *value);

#endif
