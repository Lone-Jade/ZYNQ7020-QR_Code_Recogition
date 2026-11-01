-- ==============================================================
-- Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2025.2 (64-bit)
-- Tool Version Limit: 2025.11
-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
-- 
-- ==============================================================
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity qr_fitness_control_s_axi is
generic (
    C_S_AXI_ADDR_WIDTH    : INTEGER := 10;
    C_S_AXI_DATA_WIDTH    : INTEGER := 32);
port (
    ACLK                  :in   STD_LOGIC;
    ARESET                :in   STD_LOGIC;
    ACLK_EN               :in   STD_LOGIC;
    AWADDR                :in   STD_LOGIC_VECTOR(C_S_AXI_ADDR_WIDTH-1 downto 0);
    AWVALID               :in   STD_LOGIC;
    AWREADY               :out  STD_LOGIC;
    WDATA                 :in   STD_LOGIC_VECTOR(C_S_AXI_DATA_WIDTH-1 downto 0);
    WSTRB                 :in   STD_LOGIC_VECTOR(C_S_AXI_DATA_WIDTH/8-1 downto 0);
    WVALID                :in   STD_LOGIC;
    WREADY                :out  STD_LOGIC;
    BRESP                 :out  STD_LOGIC_VECTOR(1 downto 0);
    BVALID                :out  STD_LOGIC;
    BREADY                :in   STD_LOGIC;
    ARADDR                :in   STD_LOGIC_VECTOR(C_S_AXI_ADDR_WIDTH-1 downto 0);
    ARVALID               :in   STD_LOGIC;
    ARREADY               :out  STD_LOGIC;
    RDATA                 :out  STD_LOGIC_VECTOR(C_S_AXI_DATA_WIDTH-1 downto 0);
    RRESP                 :out  STD_LOGIC_VECTOR(1 downto 0);
    RVALID                :out  STD_LOGIC;
    RREADY                :in   STD_LOGIC;
    interrupt             :out  STD_LOGIC;
    memory_r              :out  STD_LOGIC_VECTOR(63 downto 0);
    operation             :out  STD_LOGIC_VECTOR(31 downto 0);
    width                 :out  STD_LOGIC_VECTOR(31 downto 0);
    height                :out  STD_LOGIC_VECTOR(31 downto 0);
    stride_words          :out  STD_LOGIC_VECTOR(31 downto 0);
    cells                 :out  STD_LOGIC_VECTOR(31 downto 0);
    c0                    :out  STD_LOGIC_VECTOR(63 downto 0);
    c1                    :out  STD_LOGIC_VECTOR(63 downto 0);
    c2                    :out  STD_LOGIC_VECTOR(63 downto 0);
    c3                    :out  STD_LOGIC_VECTOR(63 downto 0);
    c4                    :out  STD_LOGIC_VECTOR(63 downto 0);
    c5                    :out  STD_LOGIC_VECTOR(63 downto 0);
    c6                    :out  STD_LOGIC_VECTOR(63 downto 0);
    c7                    :out  STD_LOGIC_VECTOR(63 downto 0);
    epoch                 :out  STD_LOGIC_VECTOR(31 downto 0);
    frame                 :out  STD_LOGIC_VECTOR(31 downto 0);
    config_r              :out  STD_LOGIC_VECTOR(31 downto 0);
    job_id                :out  STD_LOGIC_VECTOR(31 downto 0);
    score                 :in   STD_LOGIC_VECTOR(31 downto 0);
    score_ap_vld          :in   STD_LOGIC;
    status                :in   STD_LOGIC_VECTOR(31 downto 0);
    status_ap_vld         :in   STD_LOGIC;
    completed_job         :in   STD_LOGIC_VECTOR(31 downto 0);
    completed_job_ap_vld  :in   STD_LOGIC;
    roi_id                :out  STD_LOGIC_VECTOR(31 downto 0);
    binary_generation     :out  STD_LOGIC_VECTOR(31 downto 0);
    tree_word_offset      :out  STD_LOGIC_VECTOR(31 downto 0);
    trace_enable          :out  STD_LOGIC_VECTOR(31 downto 0);
    score_count           :in   STD_LOGIC_VECTOR(31 downto 0);
    score_count_ap_vld    :in   STD_LOGIC;
    error_step            :in   STD_LOGIC_VECTOR(31 downto 0);
    error_step_ap_vld     :in   STD_LOGIC;
    result_coefficients_address0 :in   STD_LOGIC_VECTOR(2 downto 0);
    result_coefficients_ce0 :in   STD_LOGIC;
    result_coefficients_we0 :in   STD_LOGIC;
    result_coefficients_d0 :in   STD_LOGIC_VECTOR(63 downto 0);
    hardware_magic        :in   STD_LOGIC_VECTOR(31 downto 0);
    hardware_magic_ap_vld :in   STD_LOGIC;
    hardware_abi          :in   STD_LOGIC_VECTOR(31 downto 0);
    hardware_abi_ap_vld   :in   STD_LOGIC;
    hardware_caps         :in   STD_LOGIC_VECTOR(31 downto 0);
    hardware_caps_ap_vld  :in   STD_LOGIC;
    trace_address0        :in   STD_LOGIC_VECTOR(6 downto 0);
    trace_ce0             :in   STD_LOGIC;
    trace_we0             :in   STD_LOGIC;
    trace_d0              :in   STD_LOGIC_VECTOR(31 downto 0);
    ap_start              :out  STD_LOGIC;
    ap_done               :in   STD_LOGIC;
    ap_ready              :in   STD_LOGIC;
    ap_idle               :in   STD_LOGIC
);
end entity qr_fitness_control_s_axi;

-- ------------------------Address Info-------------------
-- Protocol Used: ap_ctrl_hs
--
-- 0x000 : Control signals
--         bit 0  - ap_start (Read/Write/COH)
--         bit 1  - ap_done (Read/COR)
--         bit 2  - ap_idle (Read)
--         bit 3  - ap_ready (Read/COR)
--         bit 7  - auto_restart (Read/Write)
--         bit 9  - interrupt (Read)
--         others - reserved
-- 0x004 : Global Interrupt Enable Register
--         bit 0  - Global Interrupt Enable (Read/Write)
--         others - reserved
-- 0x008 : IP Interrupt Enable Register (Read/Write)
--         bit 0 - enable ap_done interrupt (Read/Write)
--         bit 1 - enable ap_ready interrupt (Read/Write)
--         others - reserved
-- 0x00c : IP Interrupt Status Register (Read/TOW)
--         bit 0 - ap_done (Read/TOW)
--         bit 1 - ap_ready (Read/TOW)
--         others - reserved
-- 0x010 : Data signal of memory_r
--         bit 31~0 - memory_r[31:0] (Read/Write)
-- 0x014 : Data signal of memory_r
--         bit 31~0 - memory_r[63:32] (Read/Write)
-- 0x018 : reserved
-- 0x01c : Data signal of operation
--         bit 31~0 - operation[31:0] (Read/Write)
-- 0x020 : reserved
-- 0x024 : Data signal of width
--         bit 31~0 - width[31:0] (Read/Write)
-- 0x028 : reserved
-- 0x02c : Data signal of height
--         bit 31~0 - height[31:0] (Read/Write)
-- 0x030 : reserved
-- 0x034 : Data signal of stride_words
--         bit 31~0 - stride_words[31:0] (Read/Write)
-- 0x038 : reserved
-- 0x03c : Data signal of cells
--         bit 31~0 - cells[31:0] (Read/Write)
-- 0x040 : reserved
-- 0x044 : Data signal of c0
--         bit 31~0 - c0[31:0] (Read/Write)
-- 0x048 : Data signal of c0
--         bit 31~0 - c0[63:32] (Read/Write)
-- 0x04c : reserved
-- 0x050 : Data signal of c1
--         bit 31~0 - c1[31:0] (Read/Write)
-- 0x054 : Data signal of c1
--         bit 31~0 - c1[63:32] (Read/Write)
-- 0x058 : reserved
-- 0x05c : Data signal of c2
--         bit 31~0 - c2[31:0] (Read/Write)
-- 0x060 : Data signal of c2
--         bit 31~0 - c2[63:32] (Read/Write)
-- 0x064 : reserved
-- 0x068 : Data signal of c3
--         bit 31~0 - c3[31:0] (Read/Write)
-- 0x06c : Data signal of c3
--         bit 31~0 - c3[63:32] (Read/Write)
-- 0x070 : reserved
-- 0x074 : Data signal of c4
--         bit 31~0 - c4[31:0] (Read/Write)
-- 0x078 : Data signal of c4
--         bit 31~0 - c4[63:32] (Read/Write)
-- 0x07c : reserved
-- 0x080 : Data signal of c5
--         bit 31~0 - c5[31:0] (Read/Write)
-- 0x084 : Data signal of c5
--         bit 31~0 - c5[63:32] (Read/Write)
-- 0x088 : reserved
-- 0x08c : Data signal of c6
--         bit 31~0 - c6[31:0] (Read/Write)
-- 0x090 : Data signal of c6
--         bit 31~0 - c6[63:32] (Read/Write)
-- 0x094 : reserved
-- 0x098 : Data signal of c7
--         bit 31~0 - c7[31:0] (Read/Write)
-- 0x09c : Data signal of c7
--         bit 31~0 - c7[63:32] (Read/Write)
-- 0x0a0 : reserved
-- 0x0a4 : Data signal of epoch
--         bit 31~0 - epoch[31:0] (Read/Write)
-- 0x0a8 : reserved
-- 0x0ac : Data signal of frame
--         bit 31~0 - frame[31:0] (Read/Write)
-- 0x0b0 : reserved
-- 0x0b4 : Data signal of config_r
--         bit 31~0 - config_r[31:0] (Read/Write)
-- 0x0b8 : reserved
-- 0x0bc : Data signal of job_id
--         bit 31~0 - job_id[31:0] (Read/Write)
-- 0x0c0 : reserved
-- 0x0c4 : Data signal of score
--         bit 31~0 - score[31:0] (Read)
-- 0x0c8 : Control signal of score
--         bit 0  - score_ap_vld (Read/COR)
--         others - reserved
-- 0x0d4 : Data signal of status
--         bit 31~0 - status[31:0] (Read)
-- 0x0d8 : Control signal of status
--         bit 0  - status_ap_vld (Read/COR)
--         others - reserved
-- 0x0e4 : Data signal of completed_job
--         bit 31~0 - completed_job[31:0] (Read)
-- 0x0e8 : Control signal of completed_job
--         bit 0  - completed_job_ap_vld (Read/COR)
--         others - reserved
-- 0x0f4 : Data signal of roi_id
--         bit 31~0 - roi_id[31:0] (Read/Write)
-- 0x0f8 : reserved
-- 0x0fc : Data signal of binary_generation
--         bit 31~0 - binary_generation[31:0] (Read/Write)
-- 0x100 : reserved
-- 0x104 : Data signal of tree_word_offset
--         bit 31~0 - tree_word_offset[31:0] (Read/Write)
-- 0x108 : reserved
-- 0x10c : Data signal of trace_enable
--         bit 31~0 - trace_enable[31:0] (Read/Write)
-- 0x110 : reserved
-- 0x114 : Data signal of score_count
--         bit 31~0 - score_count[31:0] (Read)
-- 0x118 : Control signal of score_count
--         bit 0  - score_count_ap_vld (Read/COR)
--         others - reserved
-- 0x124 : Data signal of error_step
--         bit 31~0 - error_step[31:0] (Read)
-- 0x128 : Control signal of error_step
--         bit 0  - error_step_ap_vld (Read/COR)
--         others - reserved
-- 0x180 : Data signal of hardware_magic
--         bit 31~0 - hardware_magic[31:0] (Read)
-- 0x184 : Control signal of hardware_magic
--         bit 0  - hardware_magic_ap_vld (Read/COR)
--         others - reserved
-- 0x190 : Data signal of hardware_abi
--         bit 31~0 - hardware_abi[31:0] (Read)
-- 0x194 : Control signal of hardware_abi
--         bit 0  - hardware_abi_ap_vld (Read/COR)
--         others - reserved
-- 0x1a0 : Data signal of hardware_caps
--         bit 31~0 - hardware_caps[31:0] (Read)
-- 0x1a4 : Control signal of hardware_caps
--         bit 0  - hardware_caps_ap_vld (Read/COR)
--         others - reserved
-- 0x140 ~
-- 0x17f : Memory 'result_coefficients' (8 * 64b)
--         Word 2n   : bit [31:0] - result_coefficients[n][31: 0]
--         Word 2n+1 : bit [31:0] - result_coefficients[n][63:32]
-- 0x200 ~
-- 0x3ff : Memory 'trace' (81 * 32b)
--         Word n : bit [31:0] - trace[n]
-- (SC = Self Clear, COR = Clear on Read, TOW = Toggle on Write, COH = Clear on Handshake)

architecture behave of qr_fitness_control_s_axi is
attribute DowngradeIPIdentifiedWarnings : STRING;
attribute DowngradeIPIdentifiedWarnings of behave : architecture is "yes";
    type states is (wridle, wrdata, wrresp, wrreset, rdidle, rddata, rdreset);  -- read and write fsm states
    signal wstate  : states := wrreset;
    signal rstate  : states := rdreset;
    signal wnext, rnext: states;
    constant ADDR_AP_CTRL                  : INTEGER := 16#000#;
    constant ADDR_GIE                      : INTEGER := 16#004#;
    constant ADDR_IER                      : INTEGER := 16#008#;
    constant ADDR_ISR                      : INTEGER := 16#00c#;
    constant ADDR_MEMORY_R_DATA_0          : INTEGER := 16#010#;
    constant ADDR_MEMORY_R_DATA_1          : INTEGER := 16#014#;
    constant ADDR_MEMORY_R_CTRL            : INTEGER := 16#018#;
    constant ADDR_OPERATION_DATA_0         : INTEGER := 16#01c#;
    constant ADDR_OPERATION_CTRL           : INTEGER := 16#020#;
    constant ADDR_WIDTH_DATA_0             : INTEGER := 16#024#;
    constant ADDR_WIDTH_CTRL               : INTEGER := 16#028#;
    constant ADDR_HEIGHT_DATA_0            : INTEGER := 16#02c#;
    constant ADDR_HEIGHT_CTRL              : INTEGER := 16#030#;
    constant ADDR_STRIDE_WORDS_DATA_0      : INTEGER := 16#034#;
    constant ADDR_STRIDE_WORDS_CTRL        : INTEGER := 16#038#;
    constant ADDR_CELLS_DATA_0             : INTEGER := 16#03c#;
    constant ADDR_CELLS_CTRL               : INTEGER := 16#040#;
    constant ADDR_C0_DATA_0                : INTEGER := 16#044#;
    constant ADDR_C0_DATA_1                : INTEGER := 16#048#;
    constant ADDR_C0_CTRL                  : INTEGER := 16#04c#;
    constant ADDR_C1_DATA_0                : INTEGER := 16#050#;
    constant ADDR_C1_DATA_1                : INTEGER := 16#054#;
    constant ADDR_C1_CTRL                  : INTEGER := 16#058#;
    constant ADDR_C2_DATA_0                : INTEGER := 16#05c#;
    constant ADDR_C2_DATA_1                : INTEGER := 16#060#;
    constant ADDR_C2_CTRL                  : INTEGER := 16#064#;
    constant ADDR_C3_DATA_0                : INTEGER := 16#068#;
    constant ADDR_C3_DATA_1                : INTEGER := 16#06c#;
    constant ADDR_C3_CTRL                  : INTEGER := 16#070#;
    constant ADDR_C4_DATA_0                : INTEGER := 16#074#;
    constant ADDR_C4_DATA_1                : INTEGER := 16#078#;
    constant ADDR_C4_CTRL                  : INTEGER := 16#07c#;
    constant ADDR_C5_DATA_0                : INTEGER := 16#080#;
    constant ADDR_C5_DATA_1                : INTEGER := 16#084#;
    constant ADDR_C5_CTRL                  : INTEGER := 16#088#;
    constant ADDR_C6_DATA_0                : INTEGER := 16#08c#;
    constant ADDR_C6_DATA_1                : INTEGER := 16#090#;
    constant ADDR_C6_CTRL                  : INTEGER := 16#094#;
    constant ADDR_C7_DATA_0                : INTEGER := 16#098#;
    constant ADDR_C7_DATA_1                : INTEGER := 16#09c#;
    constant ADDR_C7_CTRL                  : INTEGER := 16#0a0#;
    constant ADDR_EPOCH_DATA_0             : INTEGER := 16#0a4#;
    constant ADDR_EPOCH_CTRL               : INTEGER := 16#0a8#;
    constant ADDR_FRAME_DATA_0             : INTEGER := 16#0ac#;
    constant ADDR_FRAME_CTRL               : INTEGER := 16#0b0#;
    constant ADDR_CONFIG_R_DATA_0          : INTEGER := 16#0b4#;
    constant ADDR_CONFIG_R_CTRL            : INTEGER := 16#0b8#;
    constant ADDR_JOB_ID_DATA_0            : INTEGER := 16#0bc#;
    constant ADDR_JOB_ID_CTRL              : INTEGER := 16#0c0#;
    constant ADDR_SCORE_DATA_0             : INTEGER := 16#0c4#;
    constant ADDR_SCORE_CTRL               : INTEGER := 16#0c8#;
    constant ADDR_STATUS_DATA_0            : INTEGER := 16#0d4#;
    constant ADDR_STATUS_CTRL              : INTEGER := 16#0d8#;
    constant ADDR_COMPLETED_JOB_DATA_0     : INTEGER := 16#0e4#;
    constant ADDR_COMPLETED_JOB_CTRL       : INTEGER := 16#0e8#;
    constant ADDR_ROI_ID_DATA_0            : INTEGER := 16#0f4#;
    constant ADDR_ROI_ID_CTRL              : INTEGER := 16#0f8#;
    constant ADDR_BINARY_GENERATION_DATA_0 : INTEGER := 16#0fc#;
    constant ADDR_BINARY_GENERATION_CTRL   : INTEGER := 16#100#;
    constant ADDR_TREE_WORD_OFFSET_DATA_0  : INTEGER := 16#104#;
    constant ADDR_TREE_WORD_OFFSET_CTRL    : INTEGER := 16#108#;
    constant ADDR_TRACE_ENABLE_DATA_0      : INTEGER := 16#10c#;
    constant ADDR_TRACE_ENABLE_CTRL        : INTEGER := 16#110#;
    constant ADDR_SCORE_COUNT_DATA_0       : INTEGER := 16#114#;
    constant ADDR_SCORE_COUNT_CTRL         : INTEGER := 16#118#;
    constant ADDR_ERROR_STEP_DATA_0        : INTEGER := 16#124#;
    constant ADDR_ERROR_STEP_CTRL          : INTEGER := 16#128#;
    constant ADDR_HARDWARE_MAGIC_DATA_0    : INTEGER := 16#180#;
    constant ADDR_HARDWARE_MAGIC_CTRL      : INTEGER := 16#184#;
    constant ADDR_HARDWARE_ABI_DATA_0      : INTEGER := 16#190#;
    constant ADDR_HARDWARE_ABI_CTRL        : INTEGER := 16#194#;
    constant ADDR_HARDWARE_CAPS_DATA_0     : INTEGER := 16#1a0#;
    constant ADDR_HARDWARE_CAPS_CTRL       : INTEGER := 16#1a4#;
    constant ADDR_RESULT_COEFFICIENTS_BASE : INTEGER := 16#140#;
    constant ADDR_RESULT_COEFFICIENTS_HIGH : INTEGER := 16#17f#;
    constant ADDR_TRACE_BASE               : INTEGER := 16#200#;
    constant ADDR_TRACE_HIGH               : INTEGER := 16#3ff#;
    constant ADDR_BITS         : INTEGER := 10;

    signal AWREADY_t           : STD_LOGIC;
    signal WREADY_t            : STD_LOGIC;
    signal ARREADY_t           : STD_LOGIC;
    signal RVALID_t            : STD_LOGIC;
    signal BVALID_t            : STD_LOGIC;
    signal waddr               : UNSIGNED(ADDR_BITS-1 downto 0);
    signal wmask               : UNSIGNED(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal aw_hs               : STD_LOGIC;
    signal w_hs                : STD_LOGIC;
    signal rdata_data          : UNSIGNED(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal ar_hs               : STD_LOGIC;
    signal raddr               : UNSIGNED(ADDR_BITS-1 downto 0);
    -- internal registers
    signal int_ap_idle         : STD_LOGIC := '0';
    signal int_ap_ready        : STD_LOGIC := '0';
    signal task_ap_ready       : STD_LOGIC;
    signal int_ap_done         : STD_LOGIC := '0';
    signal task_ap_done        : STD_LOGIC;
    signal int_task_ap_done    : STD_LOGIC := '0';
    signal int_ap_start        : STD_LOGIC := '0';
    signal int_interrupt       : STD_LOGIC := '0';
    signal int_auto_restart    : STD_LOGIC := '0';
    signal auto_restart_status : STD_LOGIC := '0';
    signal auto_restart_done   : STD_LOGIC;
    signal int_gie             : STD_LOGIC := '0';
    signal int_ier             : UNSIGNED(1 downto 0) := (others => '0');
    signal int_isr             : UNSIGNED(1 downto 0) := (others => '0');
    signal int_memory_r        : UNSIGNED(63 downto 0) := (others => '0');
    signal int_operation       : UNSIGNED(31 downto 0) := (others => '0');
    signal int_width           : UNSIGNED(31 downto 0) := (others => '0');
    signal int_height          : UNSIGNED(31 downto 0) := (others => '0');
    signal int_stride_words    : UNSIGNED(31 downto 0) := (others => '0');
    signal int_cells           : UNSIGNED(31 downto 0) := (others => '0');
    signal int_c0              : UNSIGNED(63 downto 0) := (others => '0');
    signal int_c1              : UNSIGNED(63 downto 0) := (others => '0');
    signal int_c2              : UNSIGNED(63 downto 0) := (others => '0');
    signal int_c3              : UNSIGNED(63 downto 0) := (others => '0');
    signal int_c4              : UNSIGNED(63 downto 0) := (others => '0');
    signal int_c5              : UNSIGNED(63 downto 0) := (others => '0');
    signal int_c6              : UNSIGNED(63 downto 0) := (others => '0');
    signal int_c7              : UNSIGNED(63 downto 0) := (others => '0');
    signal int_epoch           : UNSIGNED(31 downto 0) := (others => '0');
    signal int_frame           : UNSIGNED(31 downto 0) := (others => '0');
    signal int_config_r        : UNSIGNED(31 downto 0) := (others => '0');
    signal int_job_id          : UNSIGNED(31 downto 0) := (others => '0');
    signal int_score_ap_vld    : STD_LOGIC;
    signal int_score           : UNSIGNED(31 downto 0) := (others => '0');
    signal int_status_ap_vld   : STD_LOGIC;
    signal int_status          : UNSIGNED(31 downto 0) := (others => '0');
    signal int_completed_job_ap_vld : STD_LOGIC;
    signal int_completed_job   : UNSIGNED(31 downto 0) := (others => '0');
    signal int_roi_id          : UNSIGNED(31 downto 0) := (others => '0');
    signal int_binary_generation : UNSIGNED(31 downto 0) := (others => '0');
    signal int_tree_word_offset : UNSIGNED(31 downto 0) := (others => '0');
    signal int_trace_enable    : UNSIGNED(31 downto 0) := (others => '0');
    signal int_score_count_ap_vld : STD_LOGIC;
    signal int_score_count     : UNSIGNED(31 downto 0) := (others => '0');
    signal int_error_step_ap_vld : STD_LOGIC;
    signal int_error_step      : UNSIGNED(31 downto 0) := (others => '0');
    signal int_hardware_magic_ap_vld : STD_LOGIC;
    signal int_hardware_magic  : UNSIGNED(31 downto 0) := (others => '0');
    signal int_hardware_abi_ap_vld : STD_LOGIC;
    signal int_hardware_abi    : UNSIGNED(31 downto 0) := (others => '0');
    signal int_hardware_caps_ap_vld : STD_LOGIC;
    signal int_hardware_caps   : UNSIGNED(31 downto 0) := (others => '0');
    -- memory signals
    signal int_result_coefficients_address0 : UNSIGNED(2 downto 0);
    signal int_result_coefficients_ce0 : STD_LOGIC;
    signal int_result_coefficients_be0 : UNSIGNED(7 downto 0);
    signal int_result_coefficients_d0 : UNSIGNED(63 downto 0);
    signal int_result_coefficients_address1 : UNSIGNED(2 downto 0);
    signal int_result_coefficients_ce1 : STD_LOGIC;
    signal int_result_coefficients_q1 : UNSIGNED(63 downto 0);
    signal int_result_coefficients_read : STD_LOGIC;
    signal int_result_coefficients_write : STD_LOGIC;
    signal int_result_coefficients_shift1 : UNSIGNED(0 downto 0);
    signal int_trace_address0  : UNSIGNED(6 downto 0);
    signal int_trace_ce0       : STD_LOGIC;
    signal int_trace_be0       : UNSIGNED(3 downto 0);
    signal int_trace_d0        : UNSIGNED(31 downto 0);
    signal int_trace_address1  : UNSIGNED(6 downto 0);
    signal int_trace_ce1       : STD_LOGIC;
    signal int_trace_q1        : UNSIGNED(31 downto 0);
    signal int_trace_read      : STD_LOGIC;
    signal int_trace_write     : STD_LOGIC;

    component qr_fitness_control_s_axi_ram is
        generic (
            MEM_STYLE : STRING :="auto";
            MEM_TYPE  : STRING :="S2P";
            BYTE_WIDTH : INTEGER :=8;
            WIDTH   : INTEGER :=32;
            BYTES   : INTEGER :=4;
            DEPTH   : INTEGER :=256;
            AWIDTH  : INTEGER :=8);
        port (
            clk0    : in  STD_LOGIC;
            address0: in  UNSIGNED(AWIDTH-1 downto 0);
            ce0     : in  STD_LOGIC;
            we0     : in  UNSIGNED(BYTES-1 downto 0);
            d0      : in  UNSIGNED(WIDTH-1 downto 0);
            q0      : out UNSIGNED(WIDTH-1 downto 0);
            clk1    : in  STD_LOGIC;
            address1: in  UNSIGNED(AWIDTH-1 downto 0);
            ce1     : in  STD_LOGIC;
            we1     : in  UNSIGNED(BYTES-1 downto 0);
            d1      : in  UNSIGNED(WIDTH-1 downto 0);
            q1      : out UNSIGNED(WIDTH-1 downto 0));
    end component qr_fitness_control_s_axi_ram;

    function log2 (x : INTEGER) return INTEGER is
        variable n, m : INTEGER;
    begin
        n := 1;
        m := 2;
        while m < x loop
            n := n + 1;
            m := m * 2;
        end loop;
        return n;
    end function log2;

begin
-- ----------------------- Instantiation------------------
-- int_result_coefficients
int_result_coefficients : qr_fitness_control_s_axi_ram
generic map (
     MEM_STYLE  => "auto",
     MEM_TYPE   => "S2P",
     BYTE_WIDTH => 8,
     WIDTH      => 64,
     BYTES      => 8,
     DEPTH      => 8,
     AWIDTH     => log2(8))
port map (
     clk0       => ACLK,
     address0   => int_result_coefficients_address0,
     ce0        => int_result_coefficients_ce0,
     we0        => int_result_coefficients_be0,
     d0         => int_result_coefficients_d0,
     q0         => open,
     clk1       => ACLK,
     address1   => int_result_coefficients_address1,
     ce1        => int_result_coefficients_ce1,
     we1        => (others=>'0'),
     d1         => (others=>'0'),
     q1         => int_result_coefficients_q1);
-- int_trace
int_trace : qr_fitness_control_s_axi_ram
generic map (
     MEM_STYLE  => "auto",
     MEM_TYPE   => "S2P",
     BYTE_WIDTH => 8,
     WIDTH      => 32,
     BYTES      => 4,
     DEPTH      => 81,
     AWIDTH     => log2(81))
port map (
     clk0       => ACLK,
     address0   => int_trace_address0,
     ce0        => int_trace_ce0,
     we0        => int_trace_be0,
     d0         => int_trace_d0,
     q0         => open,
     clk1       => ACLK,
     address1   => int_trace_address1,
     ce1        => int_trace_ce1,
     we1        => (others=>'0'),
     d1         => (others=>'0'),
     q1         => int_trace_q1);


-- ----------------------- AXI WRITE ---------------------
    AWREADY_t <=  '1' when wstate = wridle else '0';
    AWREADY   <=  AWREADY_t;
    WREADY_t  <=  '1' when wstate = wrdata and ar_hs = '0' else '0';
    WREADY    <=  WREADY_t;
    BVALID_t  <=  '1' when wstate = wrresp else '0';
    BVALID    <=  BVALID_t;
    BRESP     <=  "00";  -- OKAY
    wmask     <=  (31 downto 24 => WSTRB(3), 23 downto 16 => WSTRB(2), 15 downto 8 => WSTRB(1), 7 downto 0 => WSTRB(0));
    aw_hs     <=  AWVALID and AWREADY_t;
    w_hs      <=  WVALID and WREADY_t;

    -- write FSM
    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                wstate <= wrreset;
            elsif (ACLK_EN = '1') then
                wstate <= wnext;
            end if;
        end if;
    end process;

    process (wstate, AWVALID, w_hs, BREADY, BVALID_t)
    begin
        case (wstate) is
        when wridle =>
            if (AWVALID = '1') then
                wnext <= wrdata;
            else
                wnext <= wridle;
            end if;
        when wrdata =>
            if (w_hs = '1') then
                wnext <= wrresp;
            else
                wnext <= wrdata;
            end if;
        when wrresp =>
            if (BREADY = '1' and BVALID_t = '1') then
                wnext <= wridle;
            else
                wnext <= wrresp;
            end if;
        when others =>
            wnext <= wridle;
        end case;
    end process;

    waddr_proc : process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ACLK_EN = '1') then
                if (aw_hs = '1') then
                    waddr <= UNSIGNED(AWADDR(ADDR_BITS-1 downto 2) & (1 downto 0 => '0'));
                end if;
            end if;
        end if;
    end process;

-- ----------------------- AXI READ ----------------------
    ARREADY_t <= '1' when (rstate = rdidle) else '0';
    ARREADY <= ARREADY_t;
    RDATA   <= STD_LOGIC_VECTOR(rdata_data);
    RRESP   <= "00";  -- OKAY
    RVALID_t  <= '1' when (rstate = rddata) and (int_result_coefficients_read = '0') and (int_trace_read = '0') else '0';
    RVALID    <= RVALID_t;
    ar_hs   <= ARVALID and ARREADY_t;
    raddr   <= UNSIGNED(ARADDR(ADDR_BITS-1 downto 0));

    -- read FSM
    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                rstate <= rdreset;
            elsif (ACLK_EN = '1') then
                rstate <= rnext;
            end if;
        end if;
    end process;

    process (rstate, ARVALID, RREADY, RVALID_t)
    begin
        case (rstate) is
        when rdidle =>
            if (ARVALID = '1') then
                rnext <= rddata;
            else
                rnext <= rdidle;
            end if;
        when rddata =>
            if (RREADY = '1' and RVALID_t = '1') then
                rnext <= rdidle;
            else
                rnext <= rddata;
            end if;
        when others =>
            rnext <= rdidle;
        end case;
    end process;

    rdata_proc : process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ACLK_EN = '1') then
                if (ar_hs = '1') then
                    rdata_data <= (others => '0');
                    case (TO_INTEGER(raddr)) is
                    when ADDR_AP_CTRL =>
                        rdata_data(9) <= int_interrupt;
                        rdata_data(7) <= int_auto_restart;
                        rdata_data(3) <= int_ap_ready;
                        rdata_data(2) <= int_ap_idle;
                        rdata_data(1) <= int_task_ap_done;
                        rdata_data(0) <= int_ap_start;
                    when ADDR_GIE =>
                        rdata_data(0) <= int_gie;
                    when ADDR_IER =>
                        rdata_data(1 downto 0) <= int_ier;
                    when ADDR_ISR =>
                        rdata_data(1 downto 0) <= int_isr;
                    when ADDR_MEMORY_R_DATA_0 =>
                        rdata_data <= RESIZE(int_memory_r(31 downto 0), 32);
                    when ADDR_MEMORY_R_DATA_1 =>
                        rdata_data <= RESIZE(int_memory_r(63 downto 32), 32);
                    when ADDR_OPERATION_DATA_0 =>
                        rdata_data <= RESIZE(int_operation(31 downto 0), 32);
                    when ADDR_WIDTH_DATA_0 =>
                        rdata_data <= RESIZE(int_width(31 downto 0), 32);
                    when ADDR_HEIGHT_DATA_0 =>
                        rdata_data <= RESIZE(int_height(31 downto 0), 32);
                    when ADDR_STRIDE_WORDS_DATA_0 =>
                        rdata_data <= RESIZE(int_stride_words(31 downto 0), 32);
                    when ADDR_CELLS_DATA_0 =>
                        rdata_data <= RESIZE(int_cells(31 downto 0), 32);
                    when ADDR_C0_DATA_0 =>
                        rdata_data <= RESIZE(int_c0(31 downto 0), 32);
                    when ADDR_C0_DATA_1 =>
                        rdata_data <= RESIZE(int_c0(63 downto 32), 32);
                    when ADDR_C1_DATA_0 =>
                        rdata_data <= RESIZE(int_c1(31 downto 0), 32);
                    when ADDR_C1_DATA_1 =>
                        rdata_data <= RESIZE(int_c1(63 downto 32), 32);
                    when ADDR_C2_DATA_0 =>
                        rdata_data <= RESIZE(int_c2(31 downto 0), 32);
                    when ADDR_C2_DATA_1 =>
                        rdata_data <= RESIZE(int_c2(63 downto 32), 32);
                    when ADDR_C3_DATA_0 =>
                        rdata_data <= RESIZE(int_c3(31 downto 0), 32);
                    when ADDR_C3_DATA_1 =>
                        rdata_data <= RESIZE(int_c3(63 downto 32), 32);
                    when ADDR_C4_DATA_0 =>
                        rdata_data <= RESIZE(int_c4(31 downto 0), 32);
                    when ADDR_C4_DATA_1 =>
                        rdata_data <= RESIZE(int_c4(63 downto 32), 32);
                    when ADDR_C5_DATA_0 =>
                        rdata_data <= RESIZE(int_c5(31 downto 0), 32);
                    when ADDR_C5_DATA_1 =>
                        rdata_data <= RESIZE(int_c5(63 downto 32), 32);
                    when ADDR_C6_DATA_0 =>
                        rdata_data <= RESIZE(int_c6(31 downto 0), 32);
                    when ADDR_C6_DATA_1 =>
                        rdata_data <= RESIZE(int_c6(63 downto 32), 32);
                    when ADDR_C7_DATA_0 =>
                        rdata_data <= RESIZE(int_c7(31 downto 0), 32);
                    when ADDR_C7_DATA_1 =>
                        rdata_data <= RESIZE(int_c7(63 downto 32), 32);
                    when ADDR_EPOCH_DATA_0 =>
                        rdata_data <= RESIZE(int_epoch(31 downto 0), 32);
                    when ADDR_FRAME_DATA_0 =>
                        rdata_data <= RESIZE(int_frame(31 downto 0), 32);
                    when ADDR_CONFIG_R_DATA_0 =>
                        rdata_data <= RESIZE(int_config_r(31 downto 0), 32);
                    when ADDR_JOB_ID_DATA_0 =>
                        rdata_data <= RESIZE(int_job_id(31 downto 0), 32);
                    when ADDR_SCORE_DATA_0 =>
                        rdata_data <= RESIZE(int_score(31 downto 0), 32);
                    when ADDR_SCORE_CTRL =>
                        rdata_data(0) <= int_score_ap_vld;
                    when ADDR_STATUS_DATA_0 =>
                        rdata_data <= RESIZE(int_status(31 downto 0), 32);
                    when ADDR_STATUS_CTRL =>
                        rdata_data(0) <= int_status_ap_vld;
                    when ADDR_COMPLETED_JOB_DATA_0 =>
                        rdata_data <= RESIZE(int_completed_job(31 downto 0), 32);
                    when ADDR_COMPLETED_JOB_CTRL =>
                        rdata_data(0) <= int_completed_job_ap_vld;
                    when ADDR_ROI_ID_DATA_0 =>
                        rdata_data <= RESIZE(int_roi_id(31 downto 0), 32);
                    when ADDR_BINARY_GENERATION_DATA_0 =>
                        rdata_data <= RESIZE(int_binary_generation(31 downto 0), 32);
                    when ADDR_TREE_WORD_OFFSET_DATA_0 =>
                        rdata_data <= RESIZE(int_tree_word_offset(31 downto 0), 32);
                    when ADDR_TRACE_ENABLE_DATA_0 =>
                        rdata_data <= RESIZE(int_trace_enable(31 downto 0), 32);
                    when ADDR_SCORE_COUNT_DATA_0 =>
                        rdata_data <= RESIZE(int_score_count(31 downto 0), 32);
                    when ADDR_SCORE_COUNT_CTRL =>
                        rdata_data(0) <= int_score_count_ap_vld;
                    when ADDR_ERROR_STEP_DATA_0 =>
                        rdata_data <= RESIZE(int_error_step(31 downto 0), 32);
                    when ADDR_ERROR_STEP_CTRL =>
                        rdata_data(0) <= int_error_step_ap_vld;
                    when ADDR_HARDWARE_MAGIC_DATA_0 =>
                        rdata_data <= RESIZE(int_hardware_magic(31 downto 0), 32);
                    when ADDR_HARDWARE_MAGIC_CTRL =>
                        rdata_data(0) <= int_hardware_magic_ap_vld;
                    when ADDR_HARDWARE_ABI_DATA_0 =>
                        rdata_data <= RESIZE(int_hardware_abi(31 downto 0), 32);
                    when ADDR_HARDWARE_ABI_CTRL =>
                        rdata_data(0) <= int_hardware_abi_ap_vld;
                    when ADDR_HARDWARE_CAPS_DATA_0 =>
                        rdata_data <= RESIZE(int_hardware_caps(31 downto 0), 32);
                    when ADDR_HARDWARE_CAPS_CTRL =>
                        rdata_data(0) <= int_hardware_caps_ap_vld;
                    when others =>
                        NULL;
                    end case;
                elsif (int_result_coefficients_read = '1') then
                    rdata_data <= RESIZE(SHIFT_RIGHT(int_result_coefficients_q1, TO_INTEGER(int_result_coefficients_shift1)*32), 32);
                elsif (int_trace_read = '1') then
                    rdata_data <= RESIZE(int_trace_q1, 32);
                end if;
            end if;
        end if;
    end process;

-- ----------------------- Register logic ----------------
    interrupt            <= int_interrupt;
    ap_start             <= int_ap_start;
    task_ap_done         <= (ap_done and not auto_restart_status) or auto_restart_done;
    task_ap_ready        <= ap_ready and not int_auto_restart;
    auto_restart_done    <= auto_restart_status and (ap_idle and not int_ap_idle);
    memory_r             <= STD_LOGIC_VECTOR(int_memory_r);
    operation            <= STD_LOGIC_VECTOR(int_operation);
    width                <= STD_LOGIC_VECTOR(int_width);
    height               <= STD_LOGIC_VECTOR(int_height);
    stride_words         <= STD_LOGIC_VECTOR(int_stride_words);
    cells                <= STD_LOGIC_VECTOR(int_cells);
    c0                   <= STD_LOGIC_VECTOR(int_c0);
    c1                   <= STD_LOGIC_VECTOR(int_c1);
    c2                   <= STD_LOGIC_VECTOR(int_c2);
    c3                   <= STD_LOGIC_VECTOR(int_c3);
    c4                   <= STD_LOGIC_VECTOR(int_c4);
    c5                   <= STD_LOGIC_VECTOR(int_c5);
    c6                   <= STD_LOGIC_VECTOR(int_c6);
    c7                   <= STD_LOGIC_VECTOR(int_c7);
    epoch                <= STD_LOGIC_VECTOR(int_epoch);
    frame                <= STD_LOGIC_VECTOR(int_frame);
    config_r             <= STD_LOGIC_VECTOR(int_config_r);
    job_id               <= STD_LOGIC_VECTOR(int_job_id);
    roi_id               <= STD_LOGIC_VECTOR(int_roi_id);
    binary_generation    <= STD_LOGIC_VECTOR(int_binary_generation);
    tree_word_offset     <= STD_LOGIC_VECTOR(int_tree_word_offset);
    trace_enable         <= STD_LOGIC_VECTOR(int_trace_enable);

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_interrupt <= '0';
            elsif (ACLK_EN = '1') then
                if (int_gie = '1' and (int_isr(0) or int_isr(1)) = '1') then
                    int_interrupt <= '1';
                else
                    int_interrupt <= '0';
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_ap_start <= '0';
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_AP_CTRL and WSTRB(0) = '1' and WDATA(0) = '1') then
                    int_ap_start <= '1';
                elsif (ap_ready = '1') then
                    int_ap_start <= int_auto_restart; -- clear on handshake/auto restart
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_ap_done <= '0';
            elsif (ACLK_EN = '1') then
                if (true) then
                    int_ap_done <= ap_done;
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_task_ap_done <= '0';
            elsif (ACLK_EN = '1') then
                if (task_ap_done = '1') then
                    int_task_ap_done <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_AP_CTRL) then
                    int_task_ap_done <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_ap_idle <= '0';
            elsif (ACLK_EN = '1') then
                if (true) then
                    int_ap_idle <= ap_idle;
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_ap_ready <= '0';
            elsif (ACLK_EN = '1') then
                if (task_ap_ready = '1') then
                    int_ap_ready <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_AP_CTRL) then
                    int_ap_ready <= '0';
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_auto_restart <= '0';
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_AP_CTRL and WSTRB(0) = '1') then
                    int_auto_restart <= WDATA(7);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                auto_restart_status <= '0';
            elsif (ACLK_EN = '1') then
                if (int_auto_restart = '1') then
                    auto_restart_status <= '1';
                elsif (ap_idle = '1') then
                    auto_restart_status <= '0';
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_gie <= '0';
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_GIE and WSTRB(0) = '1') then
                    int_gie <= WDATA(0);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_ier <= (others=>'0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_IER and WSTRB(0) = '1') then
                    int_ier <= UNSIGNED(WDATA(1 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_isr(0) <= '0';
            elsif (ACLK_EN = '1') then
                if (int_ier(0) = '1' and ap_done = '1') then
                    int_isr(0) <= '1';
                elsif (w_hs = '1' and waddr = ADDR_ISR and WSTRB(0) = '1') then
                    int_isr(0) <= int_isr(0) xor WDATA(0); -- toggle on write
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_isr(1) <= '0';
            elsif (ACLK_EN = '1') then
                if (int_ier(1) = '1' and ap_ready = '1') then
                    int_isr(1) <= '1';
                elsif (w_hs = '1' and waddr = ADDR_ISR and WSTRB(0) = '1') then
                    int_isr(1) <= int_isr(1) xor WDATA(1); -- toggle on write
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_memory_r(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_MEMORY_R_DATA_0) then
                    int_memory_r(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_memory_r(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_memory_r(63 downto 32) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_MEMORY_R_DATA_1) then
                    int_memory_r(63 downto 32) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_memory_r(63 downto 32));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_operation(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_OPERATION_DATA_0) then
                    int_operation(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_operation(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_width(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_WIDTH_DATA_0) then
                    int_width(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_width(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_height(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_HEIGHT_DATA_0) then
                    int_height(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_height(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_stride_words(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_STRIDE_WORDS_DATA_0) then
                    int_stride_words(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_stride_words(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_cells(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_CELLS_DATA_0) then
                    int_cells(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_cells(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c0(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C0_DATA_0) then
                    int_c0(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c0(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c0(63 downto 32) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C0_DATA_1) then
                    int_c0(63 downto 32) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c0(63 downto 32));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c1(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C1_DATA_0) then
                    int_c1(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c1(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c1(63 downto 32) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C1_DATA_1) then
                    int_c1(63 downto 32) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c1(63 downto 32));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c2(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C2_DATA_0) then
                    int_c2(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c2(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c2(63 downto 32) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C2_DATA_1) then
                    int_c2(63 downto 32) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c2(63 downto 32));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c3(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C3_DATA_0) then
                    int_c3(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c3(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c3(63 downto 32) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C3_DATA_1) then
                    int_c3(63 downto 32) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c3(63 downto 32));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c4(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C4_DATA_0) then
                    int_c4(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c4(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c4(63 downto 32) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C4_DATA_1) then
                    int_c4(63 downto 32) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c4(63 downto 32));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c5(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C5_DATA_0) then
                    int_c5(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c5(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c5(63 downto 32) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C5_DATA_1) then
                    int_c5(63 downto 32) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c5(63 downto 32));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c6(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C6_DATA_0) then
                    int_c6(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c6(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c6(63 downto 32) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C6_DATA_1) then
                    int_c6(63 downto 32) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c6(63 downto 32));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c7(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C7_DATA_0) then
                    int_c7(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c7(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_c7(63 downto 32) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_C7_DATA_1) then
                    int_c7(63 downto 32) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_c7(63 downto 32));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_epoch(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_EPOCH_DATA_0) then
                    int_epoch(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_epoch(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_frame(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_FRAME_DATA_0) then
                    int_frame(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_frame(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_config_r(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_CONFIG_R_DATA_0) then
                    int_config_r(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_config_r(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_job_id(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_JOB_ID_DATA_0) then
                    int_job_id(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_job_id(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_score <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (score_ap_vld = '1') then
                    int_score <= UNSIGNED(score);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_score_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (score_ap_vld = '1') then
                    int_score_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_SCORE_CTRL) then
                    int_score_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_status <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (status_ap_vld = '1') then
                    int_status <= UNSIGNED(status);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_status_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (status_ap_vld = '1') then
                    int_status_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_STATUS_CTRL) then
                    int_status_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_completed_job <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (completed_job_ap_vld = '1') then
                    int_completed_job <= UNSIGNED(completed_job);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_completed_job_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (completed_job_ap_vld = '1') then
                    int_completed_job_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_COMPLETED_JOB_CTRL) then
                    int_completed_job_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_roi_id(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_ROI_ID_DATA_0) then
                    int_roi_id(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_roi_id(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_binary_generation(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_BINARY_GENERATION_DATA_0) then
                    int_binary_generation(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_binary_generation(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_tree_word_offset(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_TREE_WORD_OFFSET_DATA_0) then
                    int_tree_word_offset(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_tree_word_offset(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_trace_enable(31 downto 0) <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (w_hs = '1' and waddr = ADDR_TRACE_ENABLE_DATA_0) then
                    int_trace_enable(31 downto 0) <= (UNSIGNED(WDATA(31 downto 0)) and wmask(31 downto 0)) or ((not wmask(31 downto 0)) and int_trace_enable(31 downto 0));
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_score_count <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (score_count_ap_vld = '1') then
                    int_score_count <= UNSIGNED(score_count);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_score_count_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (score_count_ap_vld = '1') then
                    int_score_count_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_SCORE_COUNT_CTRL) then
                    int_score_count_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_error_step <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (error_step_ap_vld = '1') then
                    int_error_step <= UNSIGNED(error_step);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_error_step_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (error_step_ap_vld = '1') then
                    int_error_step_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_ERROR_STEP_CTRL) then
                    int_error_step_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_hardware_magic <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (hardware_magic_ap_vld = '1') then
                    int_hardware_magic <= UNSIGNED(hardware_magic);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_hardware_magic_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (hardware_magic_ap_vld = '1') then
                    int_hardware_magic_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_HARDWARE_MAGIC_CTRL) then
                    int_hardware_magic_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_hardware_abi <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (hardware_abi_ap_vld = '1') then
                    int_hardware_abi <= UNSIGNED(hardware_abi);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_hardware_abi_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (hardware_abi_ap_vld = '1') then
                    int_hardware_abi_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_HARDWARE_ABI_CTRL) then
                    int_hardware_abi_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_hardware_caps <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (hardware_caps_ap_vld = '1') then
                    int_hardware_caps <= UNSIGNED(hardware_caps);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_hardware_caps_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (hardware_caps_ap_vld = '1') then
                    int_hardware_caps_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_HARDWARE_CAPS_CTRL) then
                    int_hardware_caps_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;


-- ----------------------- Memory logic ------------------
    -- result_coefficients
    int_result_coefficients_address0 <= RESIZE(UNSIGNED(result_coefficients_address0), 3);
    int_result_coefficients_ce0 <= result_coefficients_ce0;
    int_result_coefficients_be0 <= (others => result_coefficients_we0);
    int_result_coefficients_d0 <= RESIZE(UNSIGNED(result_coefficients_d0), 64);
    int_result_coefficients_address1 <= raddr(5 downto 3);
    int_result_coefficients_ce1 <= '1' when ar_hs = '1' else '0';
    -- trace
    int_trace_address0   <= RESIZE(UNSIGNED(trace_address0), 7);
    int_trace_ce0        <= trace_ce0;
    int_trace_be0        <= (others => trace_we0);
    int_trace_d0         <= RESIZE(UNSIGNED(trace_d0), 32);
    int_trace_address1   <= raddr(8 downto 2);
    int_trace_ce1        <= '1' when ar_hs = '1' else '0';

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_result_coefficients_read <= '0';
            elsif (ACLK_EN = '1') then
                if (ar_hs = '1' and raddr >= ADDR_RESULT_COEFFICIENTS_BASE and raddr <= ADDR_RESULT_COEFFICIENTS_HIGH) then
                    int_result_coefficients_read <= '1';
                else
                    int_result_coefficients_read <= '0';
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_result_coefficients_shift1 <= (others=>'0');
            elsif (ACLK_EN = '1') then
                if (ar_hs = '1') then
                    int_result_coefficients_shift1 <= raddr(2 downto 2);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_trace_read <= '0';
            elsif (ACLK_EN = '1') then
                if (ar_hs = '1' and raddr >= ADDR_TRACE_BASE and raddr <= ADDR_TRACE_HIGH) then
                    int_trace_read <= '1';
                else
                    int_trace_read <= '0';
                end if;
            end if;
        end if;
    end process;


end architecture behave;

library IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

entity qr_fitness_control_s_axi_ram is
    generic (
        MEM_STYLE  : STRING :="auto";
        MEM_TYPE   : STRING :="S2P";
        BYTE_WIDTH : INTEGER :=8;
        WIDTH   : INTEGER :=32;
        DEPTH   : INTEGER :=256;
        BYTES   : INTEGER :=4;
        AWIDTH  : INTEGER :=8);
    port (
        clk0    : in  STD_LOGIC;
        address0: in  UNSIGNED(AWIDTH-1 downto 0);
        ce0     : in  STD_LOGIC;
        we0     : in  UNSIGNED(BYTES-1 downto 0);
        d0      : in  UNSIGNED(WIDTH-1 downto 0);
        q0      : out UNSIGNED(WIDTH-1 downto 0);
        clk1    : in  STD_LOGIC;
        address1: in  UNSIGNED(AWIDTH-1 downto 0);
        ce1     : in  STD_LOGIC;
        we1     : in  UNSIGNED(BYTES-1 downto 0);
        d1      : in  UNSIGNED(WIDTH-1 downto 0);
        q1      : out UNSIGNED(WIDTH-1 downto 0));

end entity qr_fitness_control_s_axi_ram;

architecture behave of qr_fitness_control_s_axi_ram is
    signal address0_tmp : UNSIGNED(AWIDTH-1 downto 0);
    signal address1_tmp : UNSIGNED(AWIDTH-1 downto 0);
    type RAM_T is array (0 to DEPTH - 1) of UNSIGNED(WIDTH - 1 downto 0);
    shared variable mem : RAM_T := (others => (others => '0'));
    attribute ram_style: string;
    attribute ram_style of mem: variable is MEM_STYLE;

    function port_type_gen( MEM_TYPE: STRING; MEM_STYLE: STRING; PORT_NAME: STRING) return STRING is
    begin
        if (MEM_TYPE = "S2P") and (PORT_NAME = "PORT0") then
            return "WO";
        elsif((MEM_TYPE = "S2P") and (PORT_NAME = "PORT1")) or ((MEM_TYPE = "2P") and (PORT_NAME = "PORT0")) then
            return "RO";
        elsif (MEM_STYLE = "hls_ultra") then
            return "RWNC";
        else
            return "RWRF";
        end if;
    end port_type_gen;
    constant PORT0 :STRING := port_type_gen(MEM_TYPE, MEM_STYLE, "PORT0");
    constant PORT1 :STRING := port_type_gen(MEM_TYPE, MEM_STYLE, "PORT1");

    function or_reduce( V: UNSIGNED) return std_logic is
    variable result: std_logic;
    begin
        for i in V'range loop
            if i = V'left then
                result := V(i);
            else
                result := result OR V(i);
            end if;
            exit when result = '1';
        end loop;
        return result;
    end or_reduce;

begin

    process (address0)
    begin
    address0_tmp <= address0;
    --synthesis translate_off
        if (address0 > DEPTH-1) then
            address0_tmp <= (others => '0');
        else
            address0_tmp <= address0;
        end if;
    --synthesis translate_on
    end process;

    process (address1)
    begin
    address1_tmp <= address1;
    --synthesis translate_off
        if (address1 > DEPTH-1) then
            address1_tmp <= (others => '0');
        else
            address1_tmp <= address1;
        end if;
    --synthesis translate_on
    end process;

    --read port 0
    read_p0_rf : if (PORT0 = "RO" or PORT0 = "RWRF") generate
        process (clk0) begin
            if (clk0'event and clk0 = '1') then
                if (ce0 = '1') then
                    q0 <= mem(to_integer(address0_tmp));
                end if;
            end if;
        end process;
    end generate read_p0_rf;

    read_p0_nc : if (PORT0 = "RWNC") generate
        process (clk0) begin
            if (clk0'event and clk0 = '1') then
                if (ce0 = '1') then
                    if (we0 = (we0'range => '0')) then
                        q0 <= mem(to_integer(address0_tmp));
                    end if;
                end if;
            end if;
        end process;
    end generate read_p0_nc;

    --read port 1
    read_p1_rf : if (PORT1 = "RO" or PORT1 = "RWRF") generate
        process (clk1) begin
            if (clk1'event and clk1 = '1') then
                if (ce1 = '1') then
                    q1 <= mem(to_integer(address1_tmp));
                end if;
            end if;
        end process;
    end generate read_p1_rf;

    read_p1_nc : if (PORT1 = "RWNC") generate
        process (clk1) begin
            if (clk1'event and clk1 = '1') then
                if (ce1 = '1') then
                    if (we1 = (we1'range => '0')) then
                        q1 <= mem(to_integer(address1_tmp));
                    end if;
                end if;
            end if;
        end process;
    end generate read_p1_nc;

    --write port 0
    write_p0 : if (PORT0 /= "RO") generate
        process (clk0)
        begin
            if (clk0'event and clk0 = '1') then
                if (ce0 = '1') then
                for i in 0 to BYTES - 1 loop
                    if (we0(i) = '1') then
                        mem(to_integer(address0_tmp))((i+1)*BYTE_WIDTH-1 downto i*BYTE_WIDTH) := d0((i+1)*BYTE_WIDTH-1 downto i*BYTE_WIDTH);
                    end if;
                end loop;
                end if;
            end if;
        end process;
    end generate write_p0;

    --write port 1
    write_p1 : if (PORT1 /= "RO") generate
        process (clk1)
        begin
            if (clk1'event and clk1 = '1') then
                if (ce1 = '1') then
                for i in 0 to BYTES - 1 loop
                    if (we1(i) = '1') then
                        mem(to_integer(address1_tmp))((i+1)*BYTE_WIDTH-1 downto i*BYTE_WIDTH) := d1((i+1)*BYTE_WIDTH-1 downto i*BYTE_WIDTH);
                    end if;
                end loop;
                end if;
            end if;
        end process;
    end generate write_p1;

end architecture behave;


