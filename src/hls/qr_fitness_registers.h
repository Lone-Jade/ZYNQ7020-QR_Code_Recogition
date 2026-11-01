// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2025.2 (64-bit)
// Tool Version Limit: 2025.11
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
// control
// 0x000 : Control signals
//         bit 0  - ap_start (Read/Write/COH)
//         bit 1  - ap_done (Read/COR)
//         bit 2  - ap_idle (Read)
//         bit 3  - ap_ready (Read/COR)
//         bit 7  - auto_restart (Read/Write)
//         bit 9  - interrupt (Read)
//         others - reserved
// 0x004 : Global Interrupt Enable Register
//         bit 0  - Global Interrupt Enable (Read/Write)
//         others - reserved
// 0x008 : IP Interrupt Enable Register (Read/Write)
//         bit 0 - enable ap_done interrupt (Read/Write)
//         bit 1 - enable ap_ready interrupt (Read/Write)
//         others - reserved
// 0x00c : IP Interrupt Status Register (Read/TOW)
//         bit 0 - ap_done (Read/TOW)
//         bit 1 - ap_ready (Read/TOW)
//         others - reserved
// 0x010 : Data signal of memory_r
//         bit 31~0 - memory_r[31:0] (Read/Write)
// 0x014 : Data signal of memory_r
//         bit 31~0 - memory_r[63:32] (Read/Write)
// 0x018 : reserved
// 0x01c : Data signal of operation
//         bit 31~0 - operation[31:0] (Read/Write)
// 0x020 : reserved
// 0x024 : Data signal of width
//         bit 31~0 - width[31:0] (Read/Write)
// 0x028 : reserved
// 0x02c : Data signal of height
//         bit 31~0 - height[31:0] (Read/Write)
// 0x030 : reserved
// 0x034 : Data signal of stride_words
//         bit 31~0 - stride_words[31:0] (Read/Write)
// 0x038 : reserved
// 0x03c : Data signal of cells
//         bit 31~0 - cells[31:0] (Read/Write)
// 0x040 : reserved
// 0x044 : Data signal of c0
//         bit 31~0 - c0[31:0] (Read/Write)
// 0x048 : Data signal of c0
//         bit 31~0 - c0[63:32] (Read/Write)
// 0x04c : reserved
// 0x050 : Data signal of c1
//         bit 31~0 - c1[31:0] (Read/Write)
// 0x054 : Data signal of c1
//         bit 31~0 - c1[63:32] (Read/Write)
// 0x058 : reserved
// 0x05c : Data signal of c2
//         bit 31~0 - c2[31:0] (Read/Write)
// 0x060 : Data signal of c2
//         bit 31~0 - c2[63:32] (Read/Write)
// 0x064 : reserved
// 0x068 : Data signal of c3
//         bit 31~0 - c3[31:0] (Read/Write)
// 0x06c : Data signal of c3
//         bit 31~0 - c3[63:32] (Read/Write)
// 0x070 : reserved
// 0x074 : Data signal of c4
//         bit 31~0 - c4[31:0] (Read/Write)
// 0x078 : Data signal of c4
//         bit 31~0 - c4[63:32] (Read/Write)
// 0x07c : reserved
// 0x080 : Data signal of c5
//         bit 31~0 - c5[31:0] (Read/Write)
// 0x084 : Data signal of c5
//         bit 31~0 - c5[63:32] (Read/Write)
// 0x088 : reserved
// 0x08c : Data signal of c6
//         bit 31~0 - c6[31:0] (Read/Write)
// 0x090 : Data signal of c6
//         bit 31~0 - c6[63:32] (Read/Write)
// 0x094 : reserved
// 0x098 : Data signal of c7
//         bit 31~0 - c7[31:0] (Read/Write)
// 0x09c : Data signal of c7
//         bit 31~0 - c7[63:32] (Read/Write)
// 0x0a0 : reserved
// 0x0a4 : Data signal of epoch
//         bit 31~0 - epoch[31:0] (Read/Write)
// 0x0a8 : reserved
// 0x0ac : Data signal of frame
//         bit 31~0 - frame[31:0] (Read/Write)
// 0x0b0 : reserved
// 0x0b4 : Data signal of config_r
//         bit 31~0 - config_r[31:0] (Read/Write)
// 0x0b8 : reserved
// 0x0bc : Data signal of job_id
//         bit 31~0 - job_id[31:0] (Read/Write)
// 0x0c0 : reserved
// 0x0c4 : Data signal of score
//         bit 31~0 - score[31:0] (Read)
// 0x0c8 : Control signal of score
//         bit 0  - score_ap_vld (Read/COR)
//         others - reserved
// 0x0d4 : Data signal of status
//         bit 31~0 - status[31:0] (Read)
// 0x0d8 : Control signal of status
//         bit 0  - status_ap_vld (Read/COR)
//         others - reserved
// 0x0e4 : Data signal of completed_job
//         bit 31~0 - completed_job[31:0] (Read)
// 0x0e8 : Control signal of completed_job
//         bit 0  - completed_job_ap_vld (Read/COR)
//         others - reserved
// 0x0f4 : Data signal of roi_id
//         bit 31~0 - roi_id[31:0] (Read/Write)
// 0x0f8 : reserved
// 0x0fc : Data signal of binary_generation
//         bit 31~0 - binary_generation[31:0] (Read/Write)
// 0x100 : reserved
// 0x104 : Data signal of tree_word_offset
//         bit 31~0 - tree_word_offset[31:0] (Read/Write)
// 0x108 : reserved
// 0x10c : Data signal of trace_enable
//         bit 31~0 - trace_enable[31:0] (Read/Write)
// 0x110 : reserved
// 0x114 : Data signal of score_count
//         bit 31~0 - score_count[31:0] (Read)
// 0x118 : Control signal of score_count
//         bit 0  - score_count_ap_vld (Read/COR)
//         others - reserved
// 0x124 : Data signal of error_step
//         bit 31~0 - error_step[31:0] (Read)
// 0x128 : Control signal of error_step
//         bit 0  - error_step_ap_vld (Read/COR)
//         others - reserved
// 0x180 : Data signal of hardware_magic
//         bit 31~0 - hardware_magic[31:0] (Read)
// 0x184 : Control signal of hardware_magic
//         bit 0  - hardware_magic_ap_vld (Read/COR)
//         others - reserved
// 0x190 : Data signal of hardware_abi
//         bit 31~0 - hardware_abi[31:0] (Read)
// 0x194 : Control signal of hardware_abi
//         bit 0  - hardware_abi_ap_vld (Read/COR)
//         others - reserved
// 0x1a0 : Data signal of hardware_caps
//         bit 31~0 - hardware_caps[31:0] (Read)
// 0x1a4 : Control signal of hardware_caps
//         bit 0  - hardware_caps_ap_vld (Read/COR)
//         others - reserved
// 0x140 ~
// 0x17f : Memory 'result_coefficients' (8 * 64b)
//         Word 2n   : bit [31:0] - result_coefficients[n][31: 0]
//         Word 2n+1 : bit [31:0] - result_coefficients[n][63:32]
// 0x200 ~
// 0x3ff : Memory 'trace' (81 * 32b)
//         Word n : bit [31:0] - trace[n]
// (SC = Self Clear, COR = Clear on Read, TOW = Toggle on Write, COH = Clear on Handshake)

#define XQR_FITNESS_CONTROL_ADDR_AP_CTRL                  0x000
#define XQR_FITNESS_CONTROL_ADDR_GIE                      0x004
#define XQR_FITNESS_CONTROL_ADDR_IER                      0x008
#define XQR_FITNESS_CONTROL_ADDR_ISR                      0x00c
#define XQR_FITNESS_CONTROL_ADDR_MEMORY_R_DATA            0x010
#define XQR_FITNESS_CONTROL_BITS_MEMORY_R_DATA            64
#define XQR_FITNESS_CONTROL_ADDR_OPERATION_DATA           0x01c
#define XQR_FITNESS_CONTROL_BITS_OPERATION_DATA           32
#define XQR_FITNESS_CONTROL_ADDR_WIDTH_DATA               0x024
#define XQR_FITNESS_CONTROL_BITS_WIDTH_DATA               32
#define XQR_FITNESS_CONTROL_ADDR_HEIGHT_DATA              0x02c
#define XQR_FITNESS_CONTROL_BITS_HEIGHT_DATA              32
#define XQR_FITNESS_CONTROL_ADDR_STRIDE_WORDS_DATA        0x034
#define XQR_FITNESS_CONTROL_BITS_STRIDE_WORDS_DATA        32
#define XQR_FITNESS_CONTROL_ADDR_CELLS_DATA               0x03c
#define XQR_FITNESS_CONTROL_BITS_CELLS_DATA               32
#define XQR_FITNESS_CONTROL_ADDR_C0_DATA                  0x044
#define XQR_FITNESS_CONTROL_BITS_C0_DATA                  64
#define XQR_FITNESS_CONTROL_ADDR_C1_DATA                  0x050
#define XQR_FITNESS_CONTROL_BITS_C1_DATA                  64
#define XQR_FITNESS_CONTROL_ADDR_C2_DATA                  0x05c
#define XQR_FITNESS_CONTROL_BITS_C2_DATA                  64
#define XQR_FITNESS_CONTROL_ADDR_C3_DATA                  0x068
#define XQR_FITNESS_CONTROL_BITS_C3_DATA                  64
#define XQR_FITNESS_CONTROL_ADDR_C4_DATA                  0x074
#define XQR_FITNESS_CONTROL_BITS_C4_DATA                  64
#define XQR_FITNESS_CONTROL_ADDR_C5_DATA                  0x080
#define XQR_FITNESS_CONTROL_BITS_C5_DATA                  64
#define XQR_FITNESS_CONTROL_ADDR_C6_DATA                  0x08c
#define XQR_FITNESS_CONTROL_BITS_C6_DATA                  64
#define XQR_FITNESS_CONTROL_ADDR_C7_DATA                  0x098
#define XQR_FITNESS_CONTROL_BITS_C7_DATA                  64
#define XQR_FITNESS_CONTROL_ADDR_EPOCH_DATA               0x0a4
#define XQR_FITNESS_CONTROL_BITS_EPOCH_DATA               32
#define XQR_FITNESS_CONTROL_ADDR_FRAME_DATA               0x0ac
#define XQR_FITNESS_CONTROL_BITS_FRAME_DATA               32
#define XQR_FITNESS_CONTROL_ADDR_CONFIG_R_DATA            0x0b4
#define XQR_FITNESS_CONTROL_BITS_CONFIG_R_DATA            32
#define XQR_FITNESS_CONTROL_ADDR_JOB_ID_DATA              0x0bc
#define XQR_FITNESS_CONTROL_BITS_JOB_ID_DATA              32
#define XQR_FITNESS_CONTROL_ADDR_SCORE_DATA               0x0c4
#define XQR_FITNESS_CONTROL_BITS_SCORE_DATA               32
#define XQR_FITNESS_CONTROL_ADDR_SCORE_CTRL               0x0c8
#define XQR_FITNESS_CONTROL_ADDR_STATUS_DATA              0x0d4
#define XQR_FITNESS_CONTROL_BITS_STATUS_DATA              32
#define XQR_FITNESS_CONTROL_ADDR_STATUS_CTRL              0x0d8
#define XQR_FITNESS_CONTROL_ADDR_COMPLETED_JOB_DATA       0x0e4
#define XQR_FITNESS_CONTROL_BITS_COMPLETED_JOB_DATA       32
#define XQR_FITNESS_CONTROL_ADDR_COMPLETED_JOB_CTRL       0x0e8
#define XQR_FITNESS_CONTROL_ADDR_ROI_ID_DATA              0x0f4
#define XQR_FITNESS_CONTROL_BITS_ROI_ID_DATA              32
#define XQR_FITNESS_CONTROL_ADDR_BINARY_GENERATION_DATA   0x0fc
#define XQR_FITNESS_CONTROL_BITS_BINARY_GENERATION_DATA   32
#define XQR_FITNESS_CONTROL_ADDR_TREE_WORD_OFFSET_DATA    0x104
#define XQR_FITNESS_CONTROL_BITS_TREE_WORD_OFFSET_DATA    32
#define XQR_FITNESS_CONTROL_ADDR_TRACE_ENABLE_DATA        0x10c
#define XQR_FITNESS_CONTROL_BITS_TRACE_ENABLE_DATA        32
#define XQR_FITNESS_CONTROL_ADDR_SCORE_COUNT_DATA         0x114
#define XQR_FITNESS_CONTROL_BITS_SCORE_COUNT_DATA         32
#define XQR_FITNESS_CONTROL_ADDR_SCORE_COUNT_CTRL         0x118
#define XQR_FITNESS_CONTROL_ADDR_ERROR_STEP_DATA          0x124
#define XQR_FITNESS_CONTROL_BITS_ERROR_STEP_DATA          32
#define XQR_FITNESS_CONTROL_ADDR_ERROR_STEP_CTRL          0x128
#define XQR_FITNESS_CONTROL_ADDR_HARDWARE_MAGIC_DATA      0x180
#define XQR_FITNESS_CONTROL_BITS_HARDWARE_MAGIC_DATA      32
#define XQR_FITNESS_CONTROL_ADDR_HARDWARE_MAGIC_CTRL      0x184
#define XQR_FITNESS_CONTROL_ADDR_HARDWARE_ABI_DATA        0x190
#define XQR_FITNESS_CONTROL_BITS_HARDWARE_ABI_DATA        32
#define XQR_FITNESS_CONTROL_ADDR_HARDWARE_ABI_CTRL        0x194
#define XQR_FITNESS_CONTROL_ADDR_HARDWARE_CAPS_DATA       0x1a0
#define XQR_FITNESS_CONTROL_BITS_HARDWARE_CAPS_DATA       32
#define XQR_FITNESS_CONTROL_ADDR_HARDWARE_CAPS_CTRL       0x1a4
#define XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_BASE 0x140
#define XQR_FITNESS_CONTROL_ADDR_RESULT_COEFFICIENTS_HIGH 0x17f
#define XQR_FITNESS_CONTROL_WIDTH_RESULT_COEFFICIENTS     64
#define XQR_FITNESS_CONTROL_DEPTH_RESULT_COEFFICIENTS     8
#define XQR_FITNESS_CONTROL_ADDR_TRACE_BASE               0x200
#define XQR_FITNESS_CONTROL_ADDR_TRACE_HIGH               0x3ff
#define XQR_FITNESS_CONTROL_WIDTH_TRACE                   32
#define XQR_FITNESS_CONTROL_DEPTH_TRACE                   81

