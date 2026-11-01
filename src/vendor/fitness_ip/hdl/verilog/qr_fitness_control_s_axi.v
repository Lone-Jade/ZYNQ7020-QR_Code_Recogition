// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2025.2 (64-bit)
// Tool Version Limit: 2025.11
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
`timescale 1ns/1ps
(* DowngradeIPIdentifiedWarnings="yes" *) module qr_fitness_control_s_axi
#(parameter
    C_S_AXI_ADDR_WIDTH = 10,
    C_S_AXI_DATA_WIDTH = 32
)(
    input  wire                          ACLK,
    input  wire                          ARESET,
    input  wire                          ACLK_EN,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] AWADDR,
    input  wire                          AWVALID,
    output wire                          AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] WDATA,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0] WSTRB,
    input  wire                          WVALID,
    output wire                          WREADY,
    output wire [1:0]                    BRESP,
    output wire                          BVALID,
    input  wire                          BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] ARADDR,
    input  wire                          ARVALID,
    output wire                          ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1:0] RDATA,
    output wire [1:0]                    RRESP,
    output wire                          RVALID,
    input  wire                          RREADY,
    output wire                          interrupt,
    output wire [63:0]                   memory_r,
    output wire [31:0]                   operation,
    output wire [31:0]                   width,
    output wire [31:0]                   height,
    output wire [31:0]                   stride_words,
    output wire [31:0]                   cells,
    output wire [63:0]                   c0,
    output wire [63:0]                   c1,
    output wire [63:0]                   c2,
    output wire [63:0]                   c3,
    output wire [63:0]                   c4,
    output wire [63:0]                   c5,
    output wire [63:0]                   c6,
    output wire [63:0]                   c7,
    output wire [31:0]                   epoch,
    output wire [31:0]                   frame,
    output wire [31:0]                   config_r,
    output wire [31:0]                   job_id,
    input  wire [31:0]                   score,
    input  wire                          score_ap_vld,
    input  wire [31:0]                   status,
    input  wire                          status_ap_vld,
    input  wire [31:0]                   completed_job,
    input  wire                          completed_job_ap_vld,
    output wire [31:0]                   roi_id,
    output wire [31:0]                   binary_generation,
    output wire [31:0]                   tree_word_offset,
    output wire [31:0]                   trace_enable,
    input  wire [31:0]                   score_count,
    input  wire                          score_count_ap_vld,
    input  wire [31:0]                   error_step,
    input  wire                          error_step_ap_vld,
    input  wire [2:0]                    result_coefficients_address0,
    input  wire                          result_coefficients_ce0,
    input  wire                          result_coefficients_we0,
    input  wire [63:0]                   result_coefficients_d0,
    input  wire [31:0]                   hardware_magic,
    input  wire                          hardware_magic_ap_vld,
    input  wire [31:0]                   hardware_abi,
    input  wire                          hardware_abi_ap_vld,
    input  wire [31:0]                   hardware_caps,
    input  wire                          hardware_caps_ap_vld,
    input  wire [6:0]                    trace_address0,
    input  wire                          trace_ce0,
    input  wire                          trace_we0,
    input  wire [31:0]                   trace_d0,
    output wire                          ap_start,
    input  wire                          ap_done,
    input  wire                          ap_ready,
    input  wire                          ap_idle
);
//------------------------Address Info-------------------
// Protocol Used: ap_ctrl_hs
//
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

//------------------------Parameter----------------------
localparam
    ADDR_AP_CTRL                  = 10'h000,
    ADDR_GIE                      = 10'h004,
    ADDR_IER                      = 10'h008,
    ADDR_ISR                      = 10'h00c,
    ADDR_MEMORY_R_DATA_0          = 10'h010,
    ADDR_MEMORY_R_DATA_1          = 10'h014,
    ADDR_MEMORY_R_CTRL            = 10'h018,
    ADDR_OPERATION_DATA_0         = 10'h01c,
    ADDR_OPERATION_CTRL           = 10'h020,
    ADDR_WIDTH_DATA_0             = 10'h024,
    ADDR_WIDTH_CTRL               = 10'h028,
    ADDR_HEIGHT_DATA_0            = 10'h02c,
    ADDR_HEIGHT_CTRL              = 10'h030,
    ADDR_STRIDE_WORDS_DATA_0      = 10'h034,
    ADDR_STRIDE_WORDS_CTRL        = 10'h038,
    ADDR_CELLS_DATA_0             = 10'h03c,
    ADDR_CELLS_CTRL               = 10'h040,
    ADDR_C0_DATA_0                = 10'h044,
    ADDR_C0_DATA_1                = 10'h048,
    ADDR_C0_CTRL                  = 10'h04c,
    ADDR_C1_DATA_0                = 10'h050,
    ADDR_C1_DATA_1                = 10'h054,
    ADDR_C1_CTRL                  = 10'h058,
    ADDR_C2_DATA_0                = 10'h05c,
    ADDR_C2_DATA_1                = 10'h060,
    ADDR_C2_CTRL                  = 10'h064,
    ADDR_C3_DATA_0                = 10'h068,
    ADDR_C3_DATA_1                = 10'h06c,
    ADDR_C3_CTRL                  = 10'h070,
    ADDR_C4_DATA_0                = 10'h074,
    ADDR_C4_DATA_1                = 10'h078,
    ADDR_C4_CTRL                  = 10'h07c,
    ADDR_C5_DATA_0                = 10'h080,
    ADDR_C5_DATA_1                = 10'h084,
    ADDR_C5_CTRL                  = 10'h088,
    ADDR_C6_DATA_0                = 10'h08c,
    ADDR_C6_DATA_1                = 10'h090,
    ADDR_C6_CTRL                  = 10'h094,
    ADDR_C7_DATA_0                = 10'h098,
    ADDR_C7_DATA_1                = 10'h09c,
    ADDR_C7_CTRL                  = 10'h0a0,
    ADDR_EPOCH_DATA_0             = 10'h0a4,
    ADDR_EPOCH_CTRL               = 10'h0a8,
    ADDR_FRAME_DATA_0             = 10'h0ac,
    ADDR_FRAME_CTRL               = 10'h0b0,
    ADDR_CONFIG_R_DATA_0          = 10'h0b4,
    ADDR_CONFIG_R_CTRL            = 10'h0b8,
    ADDR_JOB_ID_DATA_0            = 10'h0bc,
    ADDR_JOB_ID_CTRL              = 10'h0c0,
    ADDR_SCORE_DATA_0             = 10'h0c4,
    ADDR_SCORE_CTRL               = 10'h0c8,
    ADDR_STATUS_DATA_0            = 10'h0d4,
    ADDR_STATUS_CTRL              = 10'h0d8,
    ADDR_COMPLETED_JOB_DATA_0     = 10'h0e4,
    ADDR_COMPLETED_JOB_CTRL       = 10'h0e8,
    ADDR_ROI_ID_DATA_0            = 10'h0f4,
    ADDR_ROI_ID_CTRL              = 10'h0f8,
    ADDR_BINARY_GENERATION_DATA_0 = 10'h0fc,
    ADDR_BINARY_GENERATION_CTRL   = 10'h100,
    ADDR_TREE_WORD_OFFSET_DATA_0  = 10'h104,
    ADDR_TREE_WORD_OFFSET_CTRL    = 10'h108,
    ADDR_TRACE_ENABLE_DATA_0      = 10'h10c,
    ADDR_TRACE_ENABLE_CTRL        = 10'h110,
    ADDR_SCORE_COUNT_DATA_0       = 10'h114,
    ADDR_SCORE_COUNT_CTRL         = 10'h118,
    ADDR_ERROR_STEP_DATA_0        = 10'h124,
    ADDR_ERROR_STEP_CTRL          = 10'h128,
    ADDR_HARDWARE_MAGIC_DATA_0    = 10'h180,
    ADDR_HARDWARE_MAGIC_CTRL      = 10'h184,
    ADDR_HARDWARE_ABI_DATA_0      = 10'h190,
    ADDR_HARDWARE_ABI_CTRL        = 10'h194,
    ADDR_HARDWARE_CAPS_DATA_0     = 10'h1a0,
    ADDR_HARDWARE_CAPS_CTRL       = 10'h1a4,
    ADDR_RESULT_COEFFICIENTS_BASE = 10'h140,
    ADDR_RESULT_COEFFICIENTS_HIGH = 10'h17f,
    ADDR_TRACE_BASE               = 10'h200,
    ADDR_TRACE_HIGH               = 10'h3ff,
    WRIDLE                        = 2'd0,
    WRDATA                        = 2'd1,
    WRRESP                        = 2'd2,
    WRRESET                       = 2'd3,
    RDIDLE                        = 2'd0,
    RDDATA                        = 2'd1,
    RDRESET                       = 2'd2,
    ADDR_BITS                = 10;

//------------------------Local signal-------------------
    reg  [1:0]                    wstate = WRRESET;
    reg  [1:0]                    wnext;
    reg  [ADDR_BITS-1:0]          waddr;
    wire [C_S_AXI_DATA_WIDTH-1:0] wmask;
    wire                          aw_hs;
    wire                          w_hs;
    reg  [1:0]                    rstate = RDRESET;
    reg  [1:0]                    rnext;
    reg  [C_S_AXI_DATA_WIDTH-1:0] rdata;
    wire                          ar_hs;
    wire [ADDR_BITS-1:0]          raddr;
    // internal registers
    reg                           int_ap_idle = 1'b0;
    reg                           int_ap_ready = 1'b0;
    wire                          task_ap_ready;
    reg                           int_ap_done = 1'b0;
    wire                          task_ap_done;
    reg                           int_task_ap_done = 1'b0;
    reg                           int_ap_start = 1'b0;
    reg                           int_interrupt = 1'b0;
    reg                           int_auto_restart = 1'b0;
    reg                           auto_restart_status = 1'b0;
    wire                          auto_restart_done;
    reg                           int_gie = 1'b0;
    reg  [1:0]                    int_ier = 2'b0;
    reg  [1:0]                    int_isr = 2'b0;
    reg  [63:0]                   int_memory_r = 'b0;
    reg  [31:0]                   int_operation = 'b0;
    reg  [31:0]                   int_width = 'b0;
    reg  [31:0]                   int_height = 'b0;
    reg  [31:0]                   int_stride_words = 'b0;
    reg  [31:0]                   int_cells = 'b0;
    reg  [63:0]                   int_c0 = 'b0;
    reg  [63:0]                   int_c1 = 'b0;
    reg  [63:0]                   int_c2 = 'b0;
    reg  [63:0]                   int_c3 = 'b0;
    reg  [63:0]                   int_c4 = 'b0;
    reg  [63:0]                   int_c5 = 'b0;
    reg  [63:0]                   int_c6 = 'b0;
    reg  [63:0]                   int_c7 = 'b0;
    reg  [31:0]                   int_epoch = 'b0;
    reg  [31:0]                   int_frame = 'b0;
    reg  [31:0]                   int_config_r = 'b0;
    reg  [31:0]                   int_job_id = 'b0;
    reg                           int_score_ap_vld;
    reg  [31:0]                   int_score = 'b0;
    reg                           int_status_ap_vld;
    reg  [31:0]                   int_status = 'b0;
    reg                           int_completed_job_ap_vld;
    reg  [31:0]                   int_completed_job = 'b0;
    reg  [31:0]                   int_roi_id = 'b0;
    reg  [31:0]                   int_binary_generation = 'b0;
    reg  [31:0]                   int_tree_word_offset = 'b0;
    reg  [31:0]                   int_trace_enable = 'b0;
    reg                           int_score_count_ap_vld;
    reg  [31:0]                   int_score_count = 'b0;
    reg                           int_error_step_ap_vld;
    reg  [31:0]                   int_error_step = 'b0;
    reg                           int_hardware_magic_ap_vld;
    reg  [31:0]                   int_hardware_magic = 'b0;
    reg                           int_hardware_abi_ap_vld;
    reg  [31:0]                   int_hardware_abi = 'b0;
    reg                           int_hardware_caps_ap_vld;
    reg  [31:0]                   int_hardware_caps = 'b0;
    // memory signals
    wire [2:0]                    int_result_coefficients_address0;
    wire                          int_result_coefficients_ce0;
    wire [7:0]                    int_result_coefficients_be0;
    wire [63:0]                   int_result_coefficients_d0;
    wire [2:0]                    int_result_coefficients_address1;
    wire                          int_result_coefficients_ce1;
    wire [63:0]                   int_result_coefficients_q1;
    reg                           int_result_coefficients_read;
    reg                           int_result_coefficients_write;
    reg  [0:0]                    int_result_coefficients_shift1;
    wire [6:0]                    int_trace_address0;
    wire                          int_trace_ce0;
    wire [3:0]                    int_trace_be0;
    wire [31:0]                   int_trace_d0;
    wire [6:0]                    int_trace_address1;
    wire                          int_trace_ce1;
    wire [31:0]                   int_trace_q1;
    reg                           int_trace_read;
    reg                           int_trace_write;

//------------------------Instantiation------------------
// int_result_coefficients
qr_fitness_control_s_axi_ram #(
    .MEM_STYLE  ( "auto" ),
    .MEM_TYPE   ( "S2P" ),
    .BYTE_WIDTH ( 8 ),
    .WIDTH      ( 64 ),
    .BYTES      ( 8 ),
    .DEPTH      ( 8 )
) int_result_coefficients (
    .clk0       ( ACLK ),
    .address0   ( int_result_coefficients_address0 ),
    .ce0        ( int_result_coefficients_ce0 ),
    .we0        ( int_result_coefficients_be0 ),
    .d0         ( int_result_coefficients_d0 ),
    .q0         (  ),
    .clk1       ( ACLK ),
    .address1   ( int_result_coefficients_address1 ),
    .ce1        ( int_result_coefficients_ce1 ),
    .we1        ( {8{1'b0}} ),
    .d1         ( {64{1'b0}} ),
    .q1         ( int_result_coefficients_q1 )
);
// int_trace
qr_fitness_control_s_axi_ram #(
    .MEM_STYLE  ( "auto" ),
    .MEM_TYPE   ( "S2P" ),
    .BYTE_WIDTH ( 8 ),
    .WIDTH      ( 32 ),
    .BYTES      ( 4 ),
    .DEPTH      ( 81 )
) int_trace (
    .clk0       ( ACLK ),
    .address0   ( int_trace_address0 ),
    .ce0        ( int_trace_ce0 ),
    .we0        ( int_trace_be0 ),
    .d0         ( int_trace_d0 ),
    .q0         (  ),
    .clk1       ( ACLK ),
    .address1   ( int_trace_address1 ),
    .ce1        ( int_trace_ce1 ),
    .we1        ( {4{1'b0}} ),
    .d1         ( {32{1'b0}} ),
    .q1         ( int_trace_q1 )
);


//------------------------AXI write fsm------------------
assign AWREADY = (wstate == WRIDLE);
assign WREADY  = (wstate == WRDATA) && (!ar_hs);
assign BVALID  = (wstate == WRRESP);
assign BRESP   = 2'b00;  // OKAY
assign wmask   = { {8{WSTRB[3]}}, {8{WSTRB[2]}}, {8{WSTRB[1]}}, {8{WSTRB[0]}} };
assign aw_hs   = AWVALID & AWREADY;
assign w_hs    = WVALID & WREADY;

// wstate
always @(posedge ACLK) begin
    if (ARESET)
        wstate <= WRRESET;
    else if (ACLK_EN)
        wstate <= wnext;
end

// wnext
always @(*) begin
    case (wstate)
        WRIDLE:
            if (AWVALID)
                wnext = WRDATA;
            else
                wnext = WRIDLE;
        WRDATA:
            if (w_hs)
                wnext = WRRESP;
            else
                wnext = WRDATA;
        WRRESP:
            if (BREADY & BVALID)
                wnext = WRIDLE;
            else
                wnext = WRRESP;
        default:
            wnext = WRIDLE;
    endcase
end

// waddr
always @(posedge ACLK) begin
    if (ACLK_EN) begin
        if (aw_hs)
            waddr <= {AWADDR[ADDR_BITS-1:2], {2{1'b0}}};
    end
end

//------------------------AXI read fsm-------------------
assign ARREADY = (rstate == RDIDLE);
assign RDATA   = rdata;
assign RRESP   = 2'b00;  // OKAY
assign RVALID  = (rstate == RDDATA) & !int_result_coefficients_read & !int_trace_read;
assign ar_hs   = ARVALID & ARREADY;
assign raddr   = ARADDR[ADDR_BITS-1:0];

// rstate
always @(posedge ACLK) begin
    if (ARESET)
        rstate <= RDRESET;
    else if (ACLK_EN)
        rstate <= rnext;
end

// rnext
always @(*) begin
    case (rstate)
        RDIDLE:
            if (ARVALID)
                rnext = RDDATA;
            else
                rnext = RDIDLE;
        RDDATA:
            if (RREADY & RVALID)
                rnext = RDIDLE;
            else
                rnext = RDDATA;
        default:
            rnext = RDIDLE;
    endcase
end

// rdata
always @(posedge ACLK) begin
    if (ACLK_EN) begin
        if (ar_hs) begin
            rdata <= 'b0;
            case (raddr)
                ADDR_AP_CTRL: begin
                    rdata[0] <= int_ap_start;
                    rdata[1] <= int_task_ap_done;
                    rdata[2] <= int_ap_idle;
                    rdata[3] <= int_ap_ready;
                    rdata[7] <= int_auto_restart;
                    rdata[9] <= int_interrupt;
                end
                ADDR_GIE: begin
                    rdata <= int_gie;
                end
                ADDR_IER: begin
                    rdata <= int_ier;
                end
                ADDR_ISR: begin
                    rdata <= int_isr;
                end
                ADDR_MEMORY_R_DATA_0: begin
                    rdata <= int_memory_r[31:0];
                end
                ADDR_MEMORY_R_DATA_1: begin
                    rdata <= int_memory_r[63:32];
                end
                ADDR_OPERATION_DATA_0: begin
                    rdata <= int_operation[31:0];
                end
                ADDR_WIDTH_DATA_0: begin
                    rdata <= int_width[31:0];
                end
                ADDR_HEIGHT_DATA_0: begin
                    rdata <= int_height[31:0];
                end
                ADDR_STRIDE_WORDS_DATA_0: begin
                    rdata <= int_stride_words[31:0];
                end
                ADDR_CELLS_DATA_0: begin
                    rdata <= int_cells[31:0];
                end
                ADDR_C0_DATA_0: begin
                    rdata <= int_c0[31:0];
                end
                ADDR_C0_DATA_1: begin
                    rdata <= int_c0[63:32];
                end
                ADDR_C1_DATA_0: begin
                    rdata <= int_c1[31:0];
                end
                ADDR_C1_DATA_1: begin
                    rdata <= int_c1[63:32];
                end
                ADDR_C2_DATA_0: begin
                    rdata <= int_c2[31:0];
                end
                ADDR_C2_DATA_1: begin
                    rdata <= int_c2[63:32];
                end
                ADDR_C3_DATA_0: begin
                    rdata <= int_c3[31:0];
                end
                ADDR_C3_DATA_1: begin
                    rdata <= int_c3[63:32];
                end
                ADDR_C4_DATA_0: begin
                    rdata <= int_c4[31:0];
                end
                ADDR_C4_DATA_1: begin
                    rdata <= int_c4[63:32];
                end
                ADDR_C5_DATA_0: begin
                    rdata <= int_c5[31:0];
                end
                ADDR_C5_DATA_1: begin
                    rdata <= int_c5[63:32];
                end
                ADDR_C6_DATA_0: begin
                    rdata <= int_c6[31:0];
                end
                ADDR_C6_DATA_1: begin
                    rdata <= int_c6[63:32];
                end
                ADDR_C7_DATA_0: begin
                    rdata <= int_c7[31:0];
                end
                ADDR_C7_DATA_1: begin
                    rdata <= int_c7[63:32];
                end
                ADDR_EPOCH_DATA_0: begin
                    rdata <= int_epoch[31:0];
                end
                ADDR_FRAME_DATA_0: begin
                    rdata <= int_frame[31:0];
                end
                ADDR_CONFIG_R_DATA_0: begin
                    rdata <= int_config_r[31:0];
                end
                ADDR_JOB_ID_DATA_0: begin
                    rdata <= int_job_id[31:0];
                end
                ADDR_SCORE_DATA_0: begin
                    rdata <= int_score[31:0];
                end
                ADDR_SCORE_CTRL: begin
                    rdata[0] <= int_score_ap_vld;
                end
                ADDR_STATUS_DATA_0: begin
                    rdata <= int_status[31:0];
                end
                ADDR_STATUS_CTRL: begin
                    rdata[0] <= int_status_ap_vld;
                end
                ADDR_COMPLETED_JOB_DATA_0: begin
                    rdata <= int_completed_job[31:0];
                end
                ADDR_COMPLETED_JOB_CTRL: begin
                    rdata[0] <= int_completed_job_ap_vld;
                end
                ADDR_ROI_ID_DATA_0: begin
                    rdata <= int_roi_id[31:0];
                end
                ADDR_BINARY_GENERATION_DATA_0: begin
                    rdata <= int_binary_generation[31:0];
                end
                ADDR_TREE_WORD_OFFSET_DATA_0: begin
                    rdata <= int_tree_word_offset[31:0];
                end
                ADDR_TRACE_ENABLE_DATA_0: begin
                    rdata <= int_trace_enable[31:0];
                end
                ADDR_SCORE_COUNT_DATA_0: begin
                    rdata <= int_score_count[31:0];
                end
                ADDR_SCORE_COUNT_CTRL: begin
                    rdata[0] <= int_score_count_ap_vld;
                end
                ADDR_ERROR_STEP_DATA_0: begin
                    rdata <= int_error_step[31:0];
                end
                ADDR_ERROR_STEP_CTRL: begin
                    rdata[0] <= int_error_step_ap_vld;
                end
                ADDR_HARDWARE_MAGIC_DATA_0: begin
                    rdata <= int_hardware_magic[31:0];
                end
                ADDR_HARDWARE_MAGIC_CTRL: begin
                    rdata[0] <= int_hardware_magic_ap_vld;
                end
                ADDR_HARDWARE_ABI_DATA_0: begin
                    rdata <= int_hardware_abi[31:0];
                end
                ADDR_HARDWARE_ABI_CTRL: begin
                    rdata[0] <= int_hardware_abi_ap_vld;
                end
                ADDR_HARDWARE_CAPS_DATA_0: begin
                    rdata <= int_hardware_caps[31:0];
                end
                ADDR_HARDWARE_CAPS_CTRL: begin
                    rdata[0] <= int_hardware_caps_ap_vld;
                end
            endcase
        end
        else if (int_result_coefficients_read) begin
            rdata <= int_result_coefficients_q1 >> (int_result_coefficients_shift1 * 32);
        end
        else if (int_trace_read) begin
            rdata <= int_trace_q1;
        end
    end
end


//------------------------Register logic-----------------
assign interrupt         = int_interrupt;
assign ap_start          = int_ap_start;
assign task_ap_done      = (ap_done && !auto_restart_status) || auto_restart_done;
assign task_ap_ready     = ap_ready && !int_auto_restart;
assign auto_restart_done = auto_restart_status && (ap_idle && !int_ap_idle);
assign memory_r          = int_memory_r;
assign operation         = int_operation;
assign width             = int_width;
assign height            = int_height;
assign stride_words      = int_stride_words;
assign cells             = int_cells;
assign c0                = int_c0;
assign c1                = int_c1;
assign c2                = int_c2;
assign c3                = int_c3;
assign c4                = int_c4;
assign c5                = int_c5;
assign c6                = int_c6;
assign c7                = int_c7;
assign epoch             = int_epoch;
assign frame             = int_frame;
assign config_r          = int_config_r;
assign job_id            = int_job_id;
assign roi_id            = int_roi_id;
assign binary_generation = int_binary_generation;
assign tree_word_offset  = int_tree_word_offset;
assign trace_enable      = int_trace_enable;
// int_interrupt
always @(posedge ACLK) begin
    if (ARESET)
        int_interrupt <= 1'b0;
    else if (ACLK_EN) begin
        if (int_gie && (|int_isr))
            int_interrupt <= 1'b1;
        else
            int_interrupt <= 1'b0;
    end
end

// int_ap_start
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_start <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AP_CTRL && WSTRB[0] && WDATA[0])
            int_ap_start <= 1'b1;
        else if (ap_ready)
            int_ap_start <= int_auto_restart; // clear on handshake/auto restart
    end
end

// int_ap_done
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_done <= 1'b0;
    else if (ACLK_EN) begin
            int_ap_done <= ap_done;
    end
end

// int_task_ap_done
always @(posedge ACLK) begin
    if (ARESET)
        int_task_ap_done <= 1'b0;
    else if (ACLK_EN) begin
        if (task_ap_done)
            int_task_ap_done <= 1'b1;
        else if (ar_hs && raddr == ADDR_AP_CTRL)
            int_task_ap_done <= 1'b0; // clear on read
    end
end

// int_ap_idle
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_idle <= 1'b0;
    else if (ACLK_EN) begin
            int_ap_idle <= ap_idle;
    end
end

// int_ap_ready
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_ready <= 1'b0;
    else if (ACLK_EN) begin
        if (task_ap_ready)
            int_ap_ready <= 1'b1;
        else if (ar_hs && raddr == ADDR_AP_CTRL)
            int_ap_ready <= 1'b0;
    end
end

// int_auto_restart
always @(posedge ACLK) begin
    if (ARESET)
        int_auto_restart <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AP_CTRL && WSTRB[0])
            int_auto_restart <= WDATA[7];
    end
end

// auto_restart_status
always @(posedge ACLK) begin
    if (ARESET)
        auto_restart_status <= 1'b0;
    else if (ACLK_EN) begin
        if (int_auto_restart)
            auto_restart_status <= 1'b1;
        else if (ap_idle)
            auto_restart_status <= 1'b0;
    end
end

// int_gie
always @(posedge ACLK) begin
    if (ARESET)
        int_gie <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_GIE && WSTRB[0])
            int_gie <= WDATA[0];
    end
end

// int_ier
always @(posedge ACLK) begin
    if (ARESET)
        int_ier <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_IER && WSTRB[0])
            int_ier <= WDATA[1:0];
    end
end

// int_isr[0]
always @(posedge ACLK) begin
    if (ARESET)
        int_isr[0] <= 1'b0;
    else if (ACLK_EN) begin
        if (int_ier[0] & ap_done)
            int_isr[0] <= 1'b1;
        else if (w_hs && waddr == ADDR_ISR && WSTRB[0])
            int_isr[0] <= int_isr[0] ^ WDATA[0]; // toggle on write
    end
end

// int_isr[1]
always @(posedge ACLK) begin
    if (ARESET)
        int_isr[1] <= 1'b0;
    else if (ACLK_EN) begin
        if (int_ier[1] & ap_ready)
            int_isr[1] <= 1'b1;
        else if (w_hs && waddr == ADDR_ISR && WSTRB[0])
            int_isr[1] <= int_isr[1] ^ WDATA[1]; // toggle on write
    end
end

// int_memory_r[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_memory_r[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_MEMORY_R_DATA_0)
            int_memory_r[31:0] <= (WDATA[31:0] & wmask) | (int_memory_r[31:0] & ~wmask);
    end
end

// int_memory_r[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_memory_r[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_MEMORY_R_DATA_1)
            int_memory_r[63:32] <= (WDATA[31:0] & wmask) | (int_memory_r[63:32] & ~wmask);
    end
end

// int_operation[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_operation[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_OPERATION_DATA_0)
            int_operation[31:0] <= (WDATA[31:0] & wmask) | (int_operation[31:0] & ~wmask);
    end
end

// int_width[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_width[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_WIDTH_DATA_0)
            int_width[31:0] <= (WDATA[31:0] & wmask) | (int_width[31:0] & ~wmask);
    end
end

// int_height[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_height[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_HEIGHT_DATA_0)
            int_height[31:0] <= (WDATA[31:0] & wmask) | (int_height[31:0] & ~wmask);
    end
end

// int_stride_words[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_stride_words[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_STRIDE_WORDS_DATA_0)
            int_stride_words[31:0] <= (WDATA[31:0] & wmask) | (int_stride_words[31:0] & ~wmask);
    end
end

// int_cells[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_cells[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_CELLS_DATA_0)
            int_cells[31:0] <= (WDATA[31:0] & wmask) | (int_cells[31:0] & ~wmask);
    end
end

// int_c0[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_c0[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C0_DATA_0)
            int_c0[31:0] <= (WDATA[31:0] & wmask) | (int_c0[31:0] & ~wmask);
    end
end

// int_c0[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_c0[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C0_DATA_1)
            int_c0[63:32] <= (WDATA[31:0] & wmask) | (int_c0[63:32] & ~wmask);
    end
end

// int_c1[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_c1[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C1_DATA_0)
            int_c1[31:0] <= (WDATA[31:0] & wmask) | (int_c1[31:0] & ~wmask);
    end
end

// int_c1[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_c1[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C1_DATA_1)
            int_c1[63:32] <= (WDATA[31:0] & wmask) | (int_c1[63:32] & ~wmask);
    end
end

// int_c2[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_c2[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C2_DATA_0)
            int_c2[31:0] <= (WDATA[31:0] & wmask) | (int_c2[31:0] & ~wmask);
    end
end

// int_c2[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_c2[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C2_DATA_1)
            int_c2[63:32] <= (WDATA[31:0] & wmask) | (int_c2[63:32] & ~wmask);
    end
end

// int_c3[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_c3[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C3_DATA_0)
            int_c3[31:0] <= (WDATA[31:0] & wmask) | (int_c3[31:0] & ~wmask);
    end
end

// int_c3[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_c3[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C3_DATA_1)
            int_c3[63:32] <= (WDATA[31:0] & wmask) | (int_c3[63:32] & ~wmask);
    end
end

// int_c4[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_c4[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C4_DATA_0)
            int_c4[31:0] <= (WDATA[31:0] & wmask) | (int_c4[31:0] & ~wmask);
    end
end

// int_c4[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_c4[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C4_DATA_1)
            int_c4[63:32] <= (WDATA[31:0] & wmask) | (int_c4[63:32] & ~wmask);
    end
end

// int_c5[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_c5[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C5_DATA_0)
            int_c5[31:0] <= (WDATA[31:0] & wmask) | (int_c5[31:0] & ~wmask);
    end
end

// int_c5[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_c5[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C5_DATA_1)
            int_c5[63:32] <= (WDATA[31:0] & wmask) | (int_c5[63:32] & ~wmask);
    end
end

// int_c6[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_c6[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C6_DATA_0)
            int_c6[31:0] <= (WDATA[31:0] & wmask) | (int_c6[31:0] & ~wmask);
    end
end

// int_c6[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_c6[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C6_DATA_1)
            int_c6[63:32] <= (WDATA[31:0] & wmask) | (int_c6[63:32] & ~wmask);
    end
end

// int_c7[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_c7[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C7_DATA_0)
            int_c7[31:0] <= (WDATA[31:0] & wmask) | (int_c7[31:0] & ~wmask);
    end
end

// int_c7[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_c7[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_C7_DATA_1)
            int_c7[63:32] <= (WDATA[31:0] & wmask) | (int_c7[63:32] & ~wmask);
    end
end

// int_epoch[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_epoch[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_EPOCH_DATA_0)
            int_epoch[31:0] <= (WDATA[31:0] & wmask) | (int_epoch[31:0] & ~wmask);
    end
end

// int_frame[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_frame[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_FRAME_DATA_0)
            int_frame[31:0] <= (WDATA[31:0] & wmask) | (int_frame[31:0] & ~wmask);
    end
end

// int_config_r[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_config_r[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_CONFIG_R_DATA_0)
            int_config_r[31:0] <= (WDATA[31:0] & wmask) | (int_config_r[31:0] & ~wmask);
    end
end

// int_job_id[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_job_id[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_JOB_ID_DATA_0)
            int_job_id[31:0] <= (WDATA[31:0] & wmask) | (int_job_id[31:0] & ~wmask);
    end
end

// int_score
always @(posedge ACLK) begin
    if (ARESET)
        int_score <= 0;
    else if (ACLK_EN) begin
        if (score_ap_vld)
            int_score <= score;
    end
end

// int_score_ap_vld
always @(posedge ACLK) begin
    if (ARESET)
        int_score_ap_vld <= 1'b0;
    else if (ACLK_EN) begin
        if (score_ap_vld)
            int_score_ap_vld <= 1'b1;
        else if (ar_hs && raddr == ADDR_SCORE_CTRL)
            int_score_ap_vld <= 1'b0; // clear on read
    end
end

// int_status
always @(posedge ACLK) begin
    if (ARESET)
        int_status <= 0;
    else if (ACLK_EN) begin
        if (status_ap_vld)
            int_status <= status;
    end
end

// int_status_ap_vld
always @(posedge ACLK) begin
    if (ARESET)
        int_status_ap_vld <= 1'b0;
    else if (ACLK_EN) begin
        if (status_ap_vld)
            int_status_ap_vld <= 1'b1;
        else if (ar_hs && raddr == ADDR_STATUS_CTRL)
            int_status_ap_vld <= 1'b0; // clear on read
    end
end

// int_completed_job
always @(posedge ACLK) begin
    if (ARESET)
        int_completed_job <= 0;
    else if (ACLK_EN) begin
        if (completed_job_ap_vld)
            int_completed_job <= completed_job;
    end
end

// int_completed_job_ap_vld
always @(posedge ACLK) begin
    if (ARESET)
        int_completed_job_ap_vld <= 1'b0;
    else if (ACLK_EN) begin
        if (completed_job_ap_vld)
            int_completed_job_ap_vld <= 1'b1;
        else if (ar_hs && raddr == ADDR_COMPLETED_JOB_CTRL)
            int_completed_job_ap_vld <= 1'b0; // clear on read
    end
end

// int_roi_id[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_roi_id[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_ROI_ID_DATA_0)
            int_roi_id[31:0] <= (WDATA[31:0] & wmask) | (int_roi_id[31:0] & ~wmask);
    end
end

// int_binary_generation[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_binary_generation[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_BINARY_GENERATION_DATA_0)
            int_binary_generation[31:0] <= (WDATA[31:0] & wmask) | (int_binary_generation[31:0] & ~wmask);
    end
end

// int_tree_word_offset[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_tree_word_offset[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_TREE_WORD_OFFSET_DATA_0)
            int_tree_word_offset[31:0] <= (WDATA[31:0] & wmask) | (int_tree_word_offset[31:0] & ~wmask);
    end
end

// int_trace_enable[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_trace_enable[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_TRACE_ENABLE_DATA_0)
            int_trace_enable[31:0] <= (WDATA[31:0] & wmask) | (int_trace_enable[31:0] & ~wmask);
    end
end

// int_score_count
always @(posedge ACLK) begin
    if (ARESET)
        int_score_count <= 0;
    else if (ACLK_EN) begin
        if (score_count_ap_vld)
            int_score_count <= score_count;
    end
end

// int_score_count_ap_vld
always @(posedge ACLK) begin
    if (ARESET)
        int_score_count_ap_vld <= 1'b0;
    else if (ACLK_EN) begin
        if (score_count_ap_vld)
            int_score_count_ap_vld <= 1'b1;
        else if (ar_hs && raddr == ADDR_SCORE_COUNT_CTRL)
            int_score_count_ap_vld <= 1'b0; // clear on read
    end
end

// int_error_step
always @(posedge ACLK) begin
    if (ARESET)
        int_error_step <= 0;
    else if (ACLK_EN) begin
        if (error_step_ap_vld)
            int_error_step <= error_step;
    end
end

// int_error_step_ap_vld
always @(posedge ACLK) begin
    if (ARESET)
        int_error_step_ap_vld <= 1'b0;
    else if (ACLK_EN) begin
        if (error_step_ap_vld)
            int_error_step_ap_vld <= 1'b1;
        else if (ar_hs && raddr == ADDR_ERROR_STEP_CTRL)
            int_error_step_ap_vld <= 1'b0; // clear on read
    end
end

// int_hardware_magic
always @(posedge ACLK) begin
    if (ARESET)
        int_hardware_magic <= 0;
    else if (ACLK_EN) begin
        if (hardware_magic_ap_vld)
            int_hardware_magic <= hardware_magic;
    end
end

// int_hardware_magic_ap_vld
always @(posedge ACLK) begin
    if (ARESET)
        int_hardware_magic_ap_vld <= 1'b0;
    else if (ACLK_EN) begin
        if (hardware_magic_ap_vld)
            int_hardware_magic_ap_vld <= 1'b1;
        else if (ar_hs && raddr == ADDR_HARDWARE_MAGIC_CTRL)
            int_hardware_magic_ap_vld <= 1'b0; // clear on read
    end
end

// int_hardware_abi
always @(posedge ACLK) begin
    if (ARESET)
        int_hardware_abi <= 0;
    else if (ACLK_EN) begin
        if (hardware_abi_ap_vld)
            int_hardware_abi <= hardware_abi;
    end
end

// int_hardware_abi_ap_vld
always @(posedge ACLK) begin
    if (ARESET)
        int_hardware_abi_ap_vld <= 1'b0;
    else if (ACLK_EN) begin
        if (hardware_abi_ap_vld)
            int_hardware_abi_ap_vld <= 1'b1;
        else if (ar_hs && raddr == ADDR_HARDWARE_ABI_CTRL)
            int_hardware_abi_ap_vld <= 1'b0; // clear on read
    end
end

// int_hardware_caps
always @(posedge ACLK) begin
    if (ARESET)
        int_hardware_caps <= 0;
    else if (ACLK_EN) begin
        if (hardware_caps_ap_vld)
            int_hardware_caps <= hardware_caps;
    end
end

// int_hardware_caps_ap_vld
always @(posedge ACLK) begin
    if (ARESET)
        int_hardware_caps_ap_vld <= 1'b0;
    else if (ACLK_EN) begin
        if (hardware_caps_ap_vld)
            int_hardware_caps_ap_vld <= 1'b1;
        else if (ar_hs && raddr == ADDR_HARDWARE_CAPS_CTRL)
            int_hardware_caps_ap_vld <= 1'b0; // clear on read
    end
end

//synthesis translate_off
always @(posedge ACLK) begin
    if (ACLK_EN) begin
        if (int_gie & ~int_isr[0] & int_ier[0] & ap_done)
            $display ("// Interrupt Monitor : interrupt for ap_done detected @ \"%0t\"", $time);
        if (int_gie & ~int_isr[1] & int_ier[1] & ap_ready)
            $display ("// Interrupt Monitor : interrupt for ap_ready detected @ \"%0t\"", $time);
    end
end
//synthesis translate_on

//------------------------Memory logic-------------------
// result_coefficients
assign int_result_coefficients_address0 = result_coefficients_address0;
assign int_result_coefficients_ce0      = result_coefficients_ce0;
assign int_result_coefficients_be0      = {8{result_coefficients_we0}};
assign int_result_coefficients_d0       = result_coefficients_d0;
assign int_result_coefficients_address1 = raddr[5 : 3];
assign int_result_coefficients_ce1      = ar_hs;
// trace
assign int_trace_address0               = trace_address0;
assign int_trace_ce0                    = trace_ce0;
assign int_trace_be0                    = {4{trace_we0}};
assign int_trace_d0                     = trace_d0;
assign int_trace_address1               = raddr[8 : 2];
assign int_trace_ce1                    = ar_hs;
// int_result_coefficients_read
always @(posedge ACLK) begin
    if (ARESET)
        int_result_coefficients_read <= 1'b0;
    else if (ACLK_EN) begin
        if (ar_hs && raddr >= ADDR_RESULT_COEFFICIENTS_BASE && raddr <= ADDR_RESULT_COEFFICIENTS_HIGH)
            int_result_coefficients_read <= 1'b1;
        else
            int_result_coefficients_read <= 1'b0;
    end
end

// int_result_coefficients_shift1
always @(posedge ACLK) begin
    if (ARESET)
        int_result_coefficients_shift1 <= 1'd0;
    else if (ACLK_EN) begin
        if (ar_hs)
            int_result_coefficients_shift1 <= raddr[2:2];
    end
end

// int_trace_read
always @(posedge ACLK) begin
    if (ARESET)
        int_trace_read <= 1'b0;
    else if (ACLK_EN) begin
        if (ar_hs && raddr >= ADDR_TRACE_BASE && raddr <= ADDR_TRACE_HIGH)
            int_trace_read <= 1'b1;
        else
            int_trace_read <= 1'b0;
    end
end


endmodule


`timescale 1ns/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module qr_fitness_control_s_axi_ram
#(parameter
    MEM_STYLE  = "auto",
    MEM_TYPE   = "S2P",
    BYTE_WIDTH = 8,
    WIDTH  = 32,
    DEPTH  = 256,
    BYTES  = 4,
    AWIDTH = log2(DEPTH)
) (
    input  wire              clk0,
    input  wire [AWIDTH-1:0] address0,
    input  wire              ce0,
    input  wire [BYTES-1:0]  we0,
    input  wire [WIDTH-1:0]  d0,
    output reg  [WIDTH-1:0]  q0,
    input  wire              clk1,
    input  wire [AWIDTH-1:0] address1,
    input  wire              ce1,
    input  wire [BYTES-1:0]  we1,
    input  wire [WIDTH-1:0]  d1,
    output reg  [WIDTH-1:0]  q1
);
//------------------------ Parameters -------------------
localparam
    PORT0 = (MEM_TYPE == "S2P") ? "WO" : ((MEM_TYPE == "2P") ? "RO" : "RW"),
    PORT1 = (MEM_TYPE == "S2P") ? "RO" : "RW";
//------------------------Local signal-------------------
(* ram_style = MEM_STYLE*)
reg  [WIDTH-1:0] mem[0:DEPTH-1];
wire re0, re1;
//------------------------Task and function--------------
function integer log2;
    input integer x;
    integer n, m;
begin
    n = 1;
    m = 2;
    while (m < x) begin
        n = n + 1;
        m = m * 2;
    end
    log2 = n;
end
endfunction
//------------------------Body---------------------------
generate
    if (MEM_STYLE == "hls_ultra" && PORT0 == "RW") begin
        assign re0 = ce0 & ~|we0;
    end else begin
        assign re0 = ce0;
    end
endgenerate

generate
    if (MEM_STYLE == "hls_ultra" && PORT1 == "RW") begin
        assign re1 = ce1 & ~|we1;
    end else begin
        assign re1 = ce1;
    end
endgenerate

// read port 0
generate if (PORT0 != "WO") begin
    always @(posedge clk0) begin
        if (re0) q0 <= mem[address0];
    end
end
endgenerate

// read port 1
generate if (PORT1 != "WO") begin
    always @(posedge clk1) begin
        if (re1) q1 <= mem[address1];
    end
end
endgenerate

integer i;
// write port 0
generate if (PORT0 != "RO") begin
    always @(posedge clk0) begin
        if (ce0)
        for (i = 0; i < BYTES; i = i + 1)
            if (we0[i])
                mem[address0][i*BYTE_WIDTH +: BYTE_WIDTH] <= d0[i*BYTE_WIDTH +: BYTE_WIDTH];
    end
end
endgenerate

// write port 1
generate if (PORT1 != "RO") begin
    always @(posedge clk1) begin
        if (ce1)
        for (i = 0; i < BYTES; i = i + 1)
            if (we1[i])
                mem[address1][i*BYTE_WIDTH +: BYTE_WIDTH] <= d1[i*BYTE_WIDTH +: BYTE_WIDTH];
    end
end
endgenerate

endmodule

