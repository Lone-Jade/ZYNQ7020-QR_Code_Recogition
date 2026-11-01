// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2025.2 (64-bit)
// Tool Version Limit: 2025.11
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
#ifndef __linux__

#include "xstatus.h"
#ifdef SDT
#include "xparameters.h"
#endif
#include "xqr_fitness.h"

extern XQr_fitness_Config XQr_fitness_ConfigTable[];

#ifdef SDT
XQr_fitness_Config *XQr_fitness_LookupConfig(UINTPTR BaseAddress) {
	XQr_fitness_Config *ConfigPtr = NULL;

	int Index;

	for (Index = (u32)0x0; XQr_fitness_ConfigTable[Index].Name != NULL; Index++) {
		if (!BaseAddress || XQr_fitness_ConfigTable[Index].Control_BaseAddress == BaseAddress) {
			ConfigPtr = &XQr_fitness_ConfigTable[Index];
			break;
		}
	}

	return ConfigPtr;
}

int XQr_fitness_Initialize(XQr_fitness *InstancePtr, UINTPTR BaseAddress) {
	XQr_fitness_Config *ConfigPtr;

	Xil_AssertNonvoid(InstancePtr != NULL);

	ConfigPtr = XQr_fitness_LookupConfig(BaseAddress);
	if (ConfigPtr == NULL) {
		InstancePtr->IsReady = 0;
		return (XST_DEVICE_NOT_FOUND);
	}

	return XQr_fitness_CfgInitialize(InstancePtr, ConfigPtr);
}
#else
XQr_fitness_Config *XQr_fitness_LookupConfig(u16 DeviceId) {
	XQr_fitness_Config *ConfigPtr = NULL;

	int Index;

	for (Index = 0; Index < XPAR_XQR_FITNESS_NUM_INSTANCES; Index++) {
		if (XQr_fitness_ConfigTable[Index].DeviceId == DeviceId) {
			ConfigPtr = &XQr_fitness_ConfigTable[Index];
			break;
		}
	}

	return ConfigPtr;
}

int XQr_fitness_Initialize(XQr_fitness *InstancePtr, u16 DeviceId) {
	XQr_fitness_Config *ConfigPtr;

	Xil_AssertNonvoid(InstancePtr != NULL);

	ConfigPtr = XQr_fitness_LookupConfig(DeviceId);
	if (ConfigPtr == NULL) {
		InstancePtr->IsReady = 0;
		return (XST_DEVICE_NOT_FOUND);
	}

	return XQr_fitness_CfgInitialize(InstancePtr, ConfigPtr);
}
#endif

#endif

