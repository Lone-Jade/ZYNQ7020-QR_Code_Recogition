// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2025.2 (64-bit)
// Tool Version Limit: 2025.11
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
#ifndef XQR_FITNESS_H
#define XQR_FITNESS_H

#ifdef __cplusplus
extern "C" {
#endif

/***************************** Include Files *********************************/
#ifndef __linux__
#include "xil_types.h"
#include "xil_assert.h"
#include "xstatus.h"
#include "xil_io.h"
#else
#include <stdint.h>
#include <assert.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stddef.h>
#endif
#include "xqr_fitness_hw.h"

/**************************** Type Definitions ******************************/
#ifdef __linux__
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
#else
typedef struct {
#ifdef SDT
    char *Name;
#else
    u16 DeviceId;
#endif
    u64 Control_BaseAddress;
} XQr_fitness_Config;
#endif

typedef struct {
    u64 Control_BaseAddress;
    u32 IsReady;
} XQr_fitness;

typedef u32 word_type;

/***************** Macros (Inline Functions) Definitions *********************/
#ifndef __linux__
#define XQr_fitness_WriteReg(BaseAddress, RegOffset, Data) \
    Xil_Out32((BaseAddress) + (RegOffset), (u32)(Data))
#define XQr_fitness_ReadReg(BaseAddress, RegOffset) \
    Xil_In32((BaseAddress) + (RegOffset))
#else
#define XQr_fitness_WriteReg(BaseAddress, RegOffset, Data) \
    *(volatile u32*)((BaseAddress) + (RegOffset)) = (u32)(Data)
#define XQr_fitness_ReadReg(BaseAddress, RegOffset) \
    *(volatile u32*)((BaseAddress) + (RegOffset))

#define Xil_AssertVoid(expr)    assert(expr)
#define Xil_AssertNonvoid(expr) assert(expr)

#define XST_SUCCESS             0
#define XST_DEVICE_NOT_FOUND    2
#define XST_OPEN_DEVICE_FAILED  3
#define XIL_COMPONENT_IS_READY  1
#endif

/************************** Function Prototypes *****************************/
#ifndef __linux__
#ifdef SDT
int XQr_fitness_Initialize(XQr_fitness *InstancePtr, UINTPTR BaseAddress);
XQr_fitness_Config* XQr_fitness_LookupConfig(UINTPTR BaseAddress);
#else
int XQr_fitness_Initialize(XQr_fitness *InstancePtr, u16 DeviceId);
XQr_fitness_Config* XQr_fitness_LookupConfig(u16 DeviceId);
#endif
int XQr_fitness_CfgInitialize(XQr_fitness *InstancePtr, XQr_fitness_Config *ConfigPtr);
#else
int XQr_fitness_Initialize(XQr_fitness *InstancePtr, const char* InstanceName);
int XQr_fitness_Release(XQr_fitness *InstancePtr);
#endif

void XQr_fitness_Start(XQr_fitness *InstancePtr);
u32 XQr_fitness_IsDone(XQr_fitness *InstancePtr);
u32 XQr_fitness_IsIdle(XQr_fitness *InstancePtr);
u32 XQr_fitness_IsReady(XQr_fitness *InstancePtr);
void XQr_fitness_EnableAutoRestart(XQr_fitness *InstancePtr);
void XQr_fitness_DisableAutoRestart(XQr_fitness *InstancePtr);

void XQr_fitness_Set_memory_r(XQr_fitness *InstancePtr, u64 Data);
u64 XQr_fitness_Get_memory_r(XQr_fitness *InstancePtr);
void XQr_fitness_Set_operation(XQr_fitness *InstancePtr, u32 Data);
u32 XQr_fitness_Get_operation(XQr_fitness *InstancePtr);
void XQr_fitness_Set_width(XQr_fitness *InstancePtr, u32 Data);
u32 XQr_fitness_Get_width(XQr_fitness *InstancePtr);
void XQr_fitness_Set_height(XQr_fitness *InstancePtr, u32 Data);
u32 XQr_fitness_Get_height(XQr_fitness *InstancePtr);
void XQr_fitness_Set_stride_words(XQr_fitness *InstancePtr, u32 Data);
u32 XQr_fitness_Get_stride_words(XQr_fitness *InstancePtr);
void XQr_fitness_Set_cells(XQr_fitness *InstancePtr, u32 Data);
u32 XQr_fitness_Get_cells(XQr_fitness *InstancePtr);
void XQr_fitness_Set_c0(XQr_fitness *InstancePtr, u64 Data);
u64 XQr_fitness_Get_c0(XQr_fitness *InstancePtr);
void XQr_fitness_Set_c1(XQr_fitness *InstancePtr, u64 Data);
u64 XQr_fitness_Get_c1(XQr_fitness *InstancePtr);
void XQr_fitness_Set_c2(XQr_fitness *InstancePtr, u64 Data);
u64 XQr_fitness_Get_c2(XQr_fitness *InstancePtr);
void XQr_fitness_Set_c3(XQr_fitness *InstancePtr, u64 Data);
u64 XQr_fitness_Get_c3(XQr_fitness *InstancePtr);
void XQr_fitness_Set_c4(XQr_fitness *InstancePtr, u64 Data);
u64 XQr_fitness_Get_c4(XQr_fitness *InstancePtr);
void XQr_fitness_Set_c5(XQr_fitness *InstancePtr, u64 Data);
u64 XQr_fitness_Get_c5(XQr_fitness *InstancePtr);
void XQr_fitness_Set_c6(XQr_fitness *InstancePtr, u64 Data);
u64 XQr_fitness_Get_c6(XQr_fitness *InstancePtr);
void XQr_fitness_Set_c7(XQr_fitness *InstancePtr, u64 Data);
u64 XQr_fitness_Get_c7(XQr_fitness *InstancePtr);
void XQr_fitness_Set_epoch(XQr_fitness *InstancePtr, u32 Data);
u32 XQr_fitness_Get_epoch(XQr_fitness *InstancePtr);
void XQr_fitness_Set_frame(XQr_fitness *InstancePtr, u32 Data);
u32 XQr_fitness_Get_frame(XQr_fitness *InstancePtr);
void XQr_fitness_Set_config_r(XQr_fitness *InstancePtr, u32 Data);
u32 XQr_fitness_Get_config_r(XQr_fitness *InstancePtr);
void XQr_fitness_Set_job_id(XQr_fitness *InstancePtr, u32 Data);
u32 XQr_fitness_Get_job_id(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_score(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_score_vld(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_status(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_status_vld(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_completed_job(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_completed_job_vld(XQr_fitness *InstancePtr);
void XQr_fitness_Set_roi_id(XQr_fitness *InstancePtr, u32 Data);
u32 XQr_fitness_Get_roi_id(XQr_fitness *InstancePtr);
void XQr_fitness_Set_binary_generation(XQr_fitness *InstancePtr, u32 Data);
u32 XQr_fitness_Get_binary_generation(XQr_fitness *InstancePtr);
void XQr_fitness_Set_tree_word_offset(XQr_fitness *InstancePtr, u32 Data);
u32 XQr_fitness_Get_tree_word_offset(XQr_fitness *InstancePtr);
void XQr_fitness_Set_trace_enable(XQr_fitness *InstancePtr, u32 Data);
u32 XQr_fitness_Get_trace_enable(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_score_count(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_score_count_vld(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_error_step(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_error_step_vld(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_hardware_magic(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_hardware_magic_vld(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_hardware_abi(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_hardware_abi_vld(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_hardware_caps(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_hardware_caps_vld(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_result_coefficients_BaseAddress(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_result_coefficients_HighAddress(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_result_coefficients_TotalBytes(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_result_coefficients_BitWidth(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_result_coefficients_Depth(XQr_fitness *InstancePtr);
u32 XQr_fitness_Write_result_coefficients_Words(XQr_fitness *InstancePtr, int offset, word_type *data, int length);
u32 XQr_fitness_Read_result_coefficients_Words(XQr_fitness *InstancePtr, int offset, word_type *data, int length);
u32 XQr_fitness_Write_result_coefficients_Bytes(XQr_fitness *InstancePtr, int offset, char *data, int length);
u32 XQr_fitness_Read_result_coefficients_Bytes(XQr_fitness *InstancePtr, int offset, char *data, int length);
u32 XQr_fitness_Get_trace_BaseAddress(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_trace_HighAddress(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_trace_TotalBytes(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_trace_BitWidth(XQr_fitness *InstancePtr);
u32 XQr_fitness_Get_trace_Depth(XQr_fitness *InstancePtr);
u32 XQr_fitness_Write_trace_Words(XQr_fitness *InstancePtr, int offset, word_type *data, int length);
u32 XQr_fitness_Read_trace_Words(XQr_fitness *InstancePtr, int offset, word_type *data, int length);
u32 XQr_fitness_Write_trace_Bytes(XQr_fitness *InstancePtr, int offset, char *data, int length);
u32 XQr_fitness_Read_trace_Bytes(XQr_fitness *InstancePtr, int offset, char *data, int length);

void XQr_fitness_InterruptGlobalEnable(XQr_fitness *InstancePtr);
void XQr_fitness_InterruptGlobalDisable(XQr_fitness *InstancePtr);
void XQr_fitness_InterruptEnable(XQr_fitness *InstancePtr, u32 Mask);
void XQr_fitness_InterruptDisable(XQr_fitness *InstancePtr, u32 Mask);
void XQr_fitness_InterruptClear(XQr_fitness *InstancePtr, u32 Mask);
u32 XQr_fitness_InterruptGetEnabled(XQr_fitness *InstancePtr);
u32 XQr_fitness_InterruptGetStatus(XQr_fitness *InstancePtr);

#ifdef __cplusplus
}
#endif

#endif
