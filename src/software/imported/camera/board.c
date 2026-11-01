#include "board.h"
#include "i2c_bus.h"

#include "xil_io.h"
#include "xil_printf.h"
#include "xgpiops.h"
#include "xparameters.h"
#include "xstatus.h"

static XGpioPs gpio;

int board_init(void) {
    XGpioPs_Config *cfg = XGpioPs_LookupConfig(XPAR_XGPIOPS_0_BASEADDR);
    if (!cfg) return XST_FAILURE;
    if (XGpioPs_CfgInitialize(&gpio, cfg, cfg->BaseAddr) != XST_SUCCESS) return XST_FAILURE;
    XGpioPs_SetDirectionPin(&gpio, KEY1_MIO, 0U);
    XGpioPs_SetOutputEnablePin(&gpio, KEY1_MIO, 0U);
    return XST_SUCCESS;
}

void board_set_gpio(UINTPTR base, u32 value) {
    Xil_Out32(base + 4U, 0U);              /* 方向寄存器 = 全输出 */
    Xil_Out32(base, value & 1U);
}

int board_key_pressed(void) {
    return XGpioPs_ReadPin(&gpio, KEY1_MIO) == 0U;
}

int board_hdmi_init(void) {
    int st1 = i2c_write_reg8(HDMI_IIC_BASE, 0x39U, 0x08U, 0x35U);
    int st2 = i2c_write_reg8(HDMI_IIC_BASE, 0x3dU, 0x2fU, 0x00U);
    xil_printf("SIL9134 IIC: main=%d edid=%d\r\n", st1, st2);
    return (st1 == XST_SUCCESS && st2 == XST_SUCCESS) ? XST_SUCCESS : XST_FAILURE;
}
