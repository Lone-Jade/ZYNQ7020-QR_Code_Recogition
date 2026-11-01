#include "i2c_bus.h"

#include "xiic_l.h"
#include "xstatus.h"

int i2c_write_reg16(UINTPTR base, u8 dev_addr, u16 reg, u8 value) {
    u8 tx[3] = {(u8)(reg >> 8), (u8)reg, value};
    return XIic_Send(base, dev_addr, tx, 3U, XIIC_STOP) == 3U ? XST_SUCCESS : XST_FAILURE;
}

int i2c_write_reg8(UINTPTR base, u8 dev_addr, u8 reg, u8 value) {
    u8 tx[2] = {reg, value};
    return XIic_Send(base, dev_addr, tx, 2U, XIIC_STOP) == 2U ? XST_SUCCESS : XST_FAILURE;
}

int i2c_read_reg16(UINTPTR base, u8 dev_addr, u16 reg, u8 *value) {
    u8 tx[2] = {(u8)(reg >> 8), (u8)reg};
    if (XIic_Send(base, dev_addr, tx, 2U, XIIC_REPEATED_START) != 2U) return XST_FAILURE;
    return XIic_Recv(base, dev_addr, value, 1U, XIIC_STOP) == 1U ? XST_SUCCESS : XST_FAILURE;
}
