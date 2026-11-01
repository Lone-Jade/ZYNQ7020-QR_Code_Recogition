// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2025.2 (64-bit)
// Tool Version Limit: 2025.11
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
/***************************** Include Files *********************************/
#include "xqr_fitness.h"

/************************** Function Implementation *************************/
#ifndef __linux__
int XQr_fitness_CfgInitialize(XQr_fitness *InstancePtr, XQr_fitness_Config *ConfigPtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(ConfigPtr != NULL);

    InstancePtr->Control_BaseAddress = ConfigPtr->Control_BaseAddress;
    InstancePtr->IsReady = XIL_COMPONENT_IS_READY;

    return XST_SUCCESS;
}
#endif

void XQr_fitness_Start(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_AP_CTRL) & 0x80;
    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_AP_CTRL, Data | 0x01);
}

u32 XQr_fitness_IsDone(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_AP_CTRL);
    return (Data >> 1) & 0x1;
}

u32 XQr_fitness_IsIdle(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_AP_CTRL);
    return (Data >> 2) & 0x1;
}

u32 XQr_fitness_IsReady(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_AP_CTRL);
    // check ap_start to see if the pcore is ready for next input
    return !(Data & 0x1);
}

void XQr_fitness_EnableAutoRestart(XQr_fitness *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_AP_CTRL, 0x80);
}

void XQr_fitness_DisableAutoRestart(XQr_fitness *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_AP_CTRL, 0);
}

void XQr_fitness_Set_memory_r(XQr_fitness *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_MEMORY_R_DATA, (u32)(Data));
    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_MEMORY_R_DATA + 4, (u32)(Data >> 32));
}

u64 XQr_fitness_Get_memory_r(XQr_fitness *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_MEMORY_R_DATA);
    Data += (u64)XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_MEMORY_R_DATA + 4) << 32;
    return Data;
}

void XQr_fitness_Set_operation(XQr_fitness *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_OPERATION_DATA, Data);
}

u32 XQr_fitness_Get_operation(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_OPERATION_DATA);
    return Data;
}

void XQr_fitness_Set_width(XQr_fitness *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_WIDTH_DATA, Data);
}

u32 XQr_fitness_Get_width(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_WIDTH_DATA);
    return Data;
}

void XQr_fitness_Set_height(XQr_fitness *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_HEIGHT_DATA, Data);
}

u32 XQr_fitness_Get_height(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_HEIGHT_DATA);
    return Data;
}

void XQr_fitness_Set_stride_words(XQr_fitness *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_STRIDE_WORDS_DATA, Data);
}

u32 XQr_fitness_Get_stride_words(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_STRIDE_WORDS_DATA);
    return Data;
}

void XQr_fitness_Set_cells(XQr_fitness *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_CELLS_DATA, Data);
}

u32 XQr_fitness_Get_cells(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_CELLS_DATA);
    return Data;
}

void XQr_fitness_Set_c0(XQr_fitness *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C0_DATA, (u32)(Data));
    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C0_DATA + 4, (u32)(Data >> 32));
}

u64 XQr_fitness_Get_c0(XQr_fitness *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C0_DATA);
    Data += (u64)XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C0_DATA + 4) << 32;
    return Data;
}

void XQr_fitness_Set_c1(XQr_fitness *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C1_DATA, (u32)(Data));
    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C1_DATA + 4, (u32)(Data >> 32));
}

u64 XQr_fitness_Get_c1(XQr_fitness *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C1_DATA);
    Data += (u64)XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C1_DATA + 4) << 32;
    return Data;
}

void XQr_fitness_Set_c2(XQr_fitness *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C2_DATA, (u32)(Data));
    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C2_DATA + 4, (u32)(Data >> 32));
}

u64 XQr_fitness_Get_c2(XQr_fitness *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C2_DATA);
    Data += (u64)XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C2_DATA + 4) << 32;
    return Data;
}

void XQr_fitness_Set_c3(XQr_fitness *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C3_DATA, (u32)(Data));
    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C3_DATA + 4, (u32)(Data >> 32));
}

u64 XQr_fitness_Get_c3(XQr_fitness *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C3_DATA);
    Data += (u64)XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C3_DATA + 4) << 32;
    return Data;
}

void XQr_fitness_Set_c4(XQr_fitness *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C4_DATA, (u32)(Data));
    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C4_DATA + 4, (u32)(Data >> 32));
}

u64 XQr_fitness_Get_c4(XQr_fitness *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C4_DATA);
    Data += (u64)XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C4_DATA + 4) << 32;
    return Data;
}

void XQr_fitness_Set_c5(XQr_fitness *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C5_DATA, (u32)(Data));
    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C5_DATA + 4, (u32)(Data >> 32));
}

u64 XQr_fitness_Get_c5(XQr_fitness *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C5_DATA);
    Data += (u64)XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C5_DATA + 4) << 32;
    return Data;
}

void XQr_fitness_Set_c6(XQr_fitness *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C6_DATA, (u32)(Data));
    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C6_DATA + 4, (u32)(Data >> 32));
}

u64 XQr_fitness_Get_c6(XQr_fitness *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C6_DATA);
    Data += (u64)XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C6_DATA + 4) << 32;
    return Data;
}

void XQr_fitness_Set_c7(XQr_fitness *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C7_DATA, (u32)(Data));
    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C7_DATA + 4, (u32)(Data >> 32));
}

u64 XQr_fitness_Get_c7(XQr_fitness *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C7_DATA);
    Data += (u64)XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_C7_DATA + 4) << 32;
    return Data;
}

void XQr_fitness_Set_epoch(XQr_fitness *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_EPOCH_DATA, Data);
}

u32 XQr_fitness_Get_epoch(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_EPOCH_DATA);
    return Data;
}

void XQr_fitness_Set_frame(XQr_fitness *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_FRAME_DATA, Data);
}

u32 XQr_fitness_Get_frame(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_FRAME_DATA);
    return Data;
}

void XQr_fitness_Set_config_r(XQr_fitness *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_CONFIG_R_DATA, Data);
}

u32 XQr_fitness_Get_config_r(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_CONFIG_R_DATA);
    return Data;
}

void XQr_fitness_Set_job_id(XQr_fitness *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_JOB_ID_DATA, Data);
}

u32 XQr_fitness_Get_job_id(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_JOB_ID_DATA);
    return Data;
}

u32 XQr_fitness_Get_score(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_SCORE_DATA);
    return Data;
}

u32 XQr_fitness_Get_score_vld(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_SCORE_CTRL);
    return Data & 0x1;
}

u32 XQr_fitness_Get_status(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_STATUS_DATA);
    return Data;
}

u32 XQr_fitness_Get_status_vld(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_STATUS_CTRL);
    return Data & 0x1;
}

u32 XQr_fitness_Get_completed_job(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_COMPLETED_JOB_DATA);
    return Data;
}

u32 XQr_fitness_Get_completed_job_vld(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_COMPLETED_JOB_CTRL);
    return Data & 0x1;
}

void XQr_fitness_Set_roi_id(XQr_fitness *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_ROI_ID_DATA, Data);
}

u32 XQr_fitness_Get_roi_id(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_ROI_ID_DATA);
    return Data;
}

void XQr_fitness_Set_binary_generation(XQr_fitness *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_BINARY_GENERATION_DATA, Data);
}

u32 XQr_fitness_Get_binary_generation(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_BINARY_GENERATION_DATA);
    return Data;
}

void XQr_fitness_Set_tree_word_offset(XQr_fitness *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_TREE_WORD_OFFSET_DATA, Data);
}

u32 XQr_fitness_Get_tree_word_offset(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_TREE_WORD_OFFSET_DATA);
    return Data;
}

void XQr_fitness_Set_trace_enable(XQr_fitness *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_TRACE_ENABLE_DATA, Data);
}

u32 XQr_fitness_Get_trace_enable(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_TRACE_ENABLE_DATA);
    return Data;
}

u32 XQr_fitness_Get_score_count(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_SCORE_COUNT_DATA);
    return Data;
}

u32 XQr_fitness_Get_score_count_vld(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_SCORE_COUNT_CTRL);
    return Data & 0x1;
}

u32 XQr_fitness_Get_error_step(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_ERROR_STEP_DATA);
    return Data;
}

u32 XQr_fitness_Get_error_step_vld(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_ERROR_STEP_CTRL);
    return Data & 0x1;
}

u32 XQr_fitness_Get_hardware_magic(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_HARDWARE_MAGIC_DATA);
    return Data;
}

u32 XQr_fitness_Get_hardware_magic_vld(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_HARDWARE_MAGIC_CTRL);
    return Data & 0x1;
}

u32 XQr_fitness_Get_hardware_abi(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_HARDWARE_ABI_DATA);
    return Data;
}

u32 XQr_fitness_Get_hardware_abi_vld(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_HARDWARE_ABI_CTRL);
    return Data & 0x1;
}

u32 XQr_fitness_Get_hardware_caps(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_HARDWARE_CAPS_DATA);
    return Data;
}

u32 XQr_fitness_Get_hardware_caps_vld(XQr_fitness *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_HARDWARE_CAPS_CTRL);
    return Data & 0x1;
}

u32 XQr_fitness_Get_result_coefficients_BaseAddress(XQr_fitness *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return (InstancePtr->Control_BaseAddress + XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_BASE);
}

u32 XQr_fitness_Get_result_coefficients_HighAddress(XQr_fitness *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return (InstancePtr->Control_BaseAddress + XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_HIGH);
}

u32 XQr_fitness_Get_result_coefficients_TotalBytes(XQr_fitness *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return (XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_HIGH - XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_BASE + 1);
}

u32 XQr_fitness_Get_result_coefficients_BitWidth(XQr_fitness *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XQR_FITNESS_CONTROL_WIDTH_RESULT_COEFFICIENTS;
}

u32 XQr_fitness_Get_result_coefficients_Depth(XQr_fitness *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XQR_FITNESS_CONTROL_DEPTH_RESULT_COEFFICIENTS;
}

u32 XQr_fitness_Write_result_coefficients_Words(XQr_fitness *InstancePtr, int offset, word_type *data, int length) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr -> IsReady == XIL_COMPONENT_IS_READY);

    int i;

    if ((offset + length)*4 > (XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_HIGH - XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_BASE + 1))
        return 0;

    for (i = 0; i < length; i++) {
        *(int *)(InstancePtr->Control_BaseAddress + XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_BASE + (offset + i)*4) = *(data + i);
    }
    return length;
}

u32 XQr_fitness_Read_result_coefficients_Words(XQr_fitness *InstancePtr, int offset, word_type *data, int length) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr -> IsReady == XIL_COMPONENT_IS_READY);

    int i;

    if ((offset + length)*4 > (XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_HIGH - XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_BASE + 1))
        return 0;

    for (i = 0; i < length; i++) {
        *(data + i) = *(int *)(InstancePtr->Control_BaseAddress + XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_BASE + (offset + i)*4);
    }
    return length;
}

u32 XQr_fitness_Write_result_coefficients_Bytes(XQr_fitness *InstancePtr, int offset, char *data, int length) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr -> IsReady == XIL_COMPONENT_IS_READY);

    int i;

    if ((offset + length) > (XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_HIGH - XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_BASE + 1))
        return 0;

    for (i = 0; i < length; i++) {
        *(char *)(InstancePtr->Control_BaseAddress + XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_BASE + offset + i) = *(data + i);
    }
    return length;
}

u32 XQr_fitness_Read_result_coefficients_Bytes(XQr_fitness *InstancePtr, int offset, char *data, int length) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr -> IsReady == XIL_COMPONENT_IS_READY);

    int i;

    if ((offset + length) > (XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_HIGH - XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_BASE + 1))
        return 0;

    for (i = 0; i < length; i++) {
        *(data + i) = *(char *)(InstancePtr->Control_BaseAddress + XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_BASE + offset + i);
    }
    return length;
}

u32 XQr_fitness_Get_trace_BaseAddress(XQr_fitness *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return (InstancePtr->Control_BaseAddress + XQR_FITNESS_CONTROL_ADDR_TRACE_BASE);
}

u32 XQr_fitness_Get_trace_HighAddress(XQr_fitness *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return (InstancePtr->Control_BaseAddress + XQR_FITNESS_CONTROL_ADDR_TRACE_HIGH);
}

u32 XQr_fitness_Get_trace_TotalBytes(XQr_fitness *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return (XQR_FITNESS_CONTROL_ADDR_TRACE_HIGH - XQR_FITNESS_CONTROL_ADDR_TRACE_BASE + 1);
}

u32 XQr_fitness_Get_trace_BitWidth(XQr_fitness *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XQR_FITNESS_CONTROL_WIDTH_TRACE;
}

u32 XQr_fitness_Get_trace_Depth(XQr_fitness *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XQR_FITNESS_CONTROL_DEPTH_TRACE;
}

u32 XQr_fitness_Write_trace_Words(XQr_fitness *InstancePtr, int offset, word_type *data, int length) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr -> IsReady == XIL_COMPONENT_IS_READY);

    int i;

    if ((offset + length)*4 > (XQR_FITNESS_CONTROL_ADDR_TRACE_HIGH - XQR_FITNESS_CONTROL_ADDR_TRACE_BASE + 1))
        return 0;

    for (i = 0; i < length; i++) {
        *(int *)(InstancePtr->Control_BaseAddress + XQR_FITNESS_CONTROL_ADDR_TRACE_BASE + (offset + i)*4) = *(data + i);
    }
    return length;
}

u32 XQr_fitness_Read_trace_Words(XQr_fitness *InstancePtr, int offset, word_type *data, int length) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr -> IsReady == XIL_COMPONENT_IS_READY);

    int i;

    if ((offset + length)*4 > (XQR_FITNESS_CONTROL_ADDR_TRACE_HIGH - XQR_FITNESS_CONTROL_ADDR_TRACE_BASE + 1))
        return 0;

    for (i = 0; i < length; i++) {
        *(data + i) = *(int *)(InstancePtr->Control_BaseAddress + XQR_FITNESS_CONTROL_ADDR_TRACE_BASE + (offset + i)*4);
    }
    return length;
}

u32 XQr_fitness_Write_trace_Bytes(XQr_fitness *InstancePtr, int offset, char *data, int length) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr -> IsReady == XIL_COMPONENT_IS_READY);

    int i;

    if ((offset + length) > (XQR_FITNESS_CONTROL_ADDR_TRACE_HIGH - XQR_FITNESS_CONTROL_ADDR_TRACE_BASE + 1))
        return 0;

    for (i = 0; i < length; i++) {
        *(char *)(InstancePtr->Control_BaseAddress + XQR_FITNESS_CONTROL_ADDR_TRACE_BASE + offset + i) = *(data + i);
    }
    return length;
}

u32 XQr_fitness_Read_trace_Bytes(XQr_fitness *InstancePtr, int offset, char *data, int length) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr -> IsReady == XIL_COMPONENT_IS_READY);

    int i;

    if ((offset + length) > (XQR_FITNESS_CONTROL_ADDR_TRACE_HIGH - XQR_FITNESS_CONTROL_ADDR_TRACE_BASE + 1))
        return 0;

    for (i = 0; i < length; i++) {
        *(data + i) = *(char *)(InstancePtr->Control_BaseAddress + XQR_FITNESS_CONTROL_ADDR_TRACE_BASE + offset + i);
    }
    return length;
}

void XQr_fitness_InterruptGlobalEnable(XQr_fitness *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_GIE, 1);
}

void XQr_fitness_InterruptGlobalDisable(XQr_fitness *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_GIE, 0);
}

void XQr_fitness_InterruptEnable(XQr_fitness *InstancePtr, u32 Mask) {
    u32 Register;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Register =  XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_IER);
    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_IER, Register | Mask);
}

void XQr_fitness_InterruptDisable(XQr_fitness *InstancePtr, u32 Mask) {
    u32 Register;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Register =  XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_IER);
    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_IER, Register & (~Mask));
}

void XQr_fitness_InterruptClear(XQr_fitness *InstancePtr, u32 Mask) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XQr_fitness_WriteReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_ISR, Mask);
}

u32 XQr_fitness_InterruptGetEnabled(XQr_fitness *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_IER);
}

u32 XQr_fitness_InterruptGetStatus(XQr_fitness *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XQr_fitness_ReadReg(InstancePtr->Control_BaseAddress, XQR_FITNESS_CONTROL_ADDR_ISR);
}

