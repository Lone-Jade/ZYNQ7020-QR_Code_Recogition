`timescale 1ns/1ps

`ifndef QR_CAMERA_PIXELS
`define QR_CAMERA_PIXELS 800
`endif

`ifndef QR_CAMERA_LINES
`define QR_CAMERA_LINES 600
`endif

`ifndef QR_CAMERA_PL_ROI
`define QR_CAMERA_PL_ROI 1
`endif

module qr_camera_board_top (
    inout [14:0] DDR_addr, inout [2:0] DDR_ba, inout DDR_cas_n,
    inout DDR_ck_n, inout DDR_ck_p, inout DDR_cke, inout DDR_cs_n,
    inout [3:0] DDR_dm, inout [31:0] DDR_dq, inout [3:0] DDR_dqs_n,
    inout [3:0] DDR_dqs_p, inout DDR_odt, inout DDR_ras_n,
    inout DDR_reset_n, inout DDR_we_n, inout FIXED_IO_ddr_vrn,
    inout FIXED_IO_ddr_vrp, inout [53:0] FIXED_IO_mio,
    inout FIXED_IO_ps_clk, inout FIXED_IO_ps_porb, inout FIXED_IO_ps_srstb,
    inout cam1_sda, inout cam1_scl, input cam1_pclk,
    input [9:0] cam1_d, input cam1_href, input cam1_vsync,
    output cam1_reset_n,
    inout hdmi_sda, inout hdmi_scl, output [23:0] hdmi_d,
    output hdmi_de, output hdmi_hs, output hdmi_vs, output hdmi_clk,
    output hdmi_reset_n
);
    wire pl_resetn;
    reg [1:0] camera_reset_sync = 2'b00;
    reg [1:0] pixel_reset_sync = 2'b00;
    wire [0:0] camera_reset_ctrl;
    wire [0:0] camera_arm_ctrl;
    wire [0:0] hdmi_reset_ctrl;
    wire [15:0] capture_data;
    wire capture_valid, capture_ready, capture_user, capture_last;
    wire [15:0] display_raw_data, display_in_data;
    wire [1:0] display_raw_keep, display_in_keep;
    wire display_raw_valid, display_raw_ready;
    wire display_raw_user, display_raw_last;
    wire display_in_valid, display_in_ready, display_in_user, display_in_last;
    wire [15:0] qr_tap_data;
    wire [1:0] qr_tap_keep;
    wire qr_tap_valid, qr_tap_ready, qr_tap_user, qr_tap_last;
    wire [15:0] gated_data;
    wire [1:0] gated_keep;
    wire gated_valid, gated_ready, gated_user, gated_last;
    wire gate_active, gate_done_toggle;
    wire pixel_clk;
    wire [15:0] display_out_data;
    wire [1:0] display_out_keep;
    wire display_out_valid, display_out_ready;
    wire display_out_user, display_out_last;
    wire [31:0] hdmi_debug_status;
    wire [31:0] hdmi_debug_counts;
    wire [31:0] osd_commit_ctrl;
    wire [31:0] osd_bram_addr;
    wire osd_bram_en;
    wire [31:0] osd_bram_data;

    always @(posedge cam1_pclk or negedge pl_resetn) begin
        if (!pl_resetn)
            camera_reset_sync <= 2'b00;
        else
            camera_reset_sync <= {camera_reset_sync[0], 1'b1};
    end
    assign cam1_reset_n = pl_resetn && camera_reset_ctrl[0];
    assign hdmi_reset_n = pl_resetn && hdmi_reset_ctrl[0];

    always @(posedge pixel_clk or negedge pl_resetn) begin
        if (!pl_resetn)
            pixel_reset_sync <= 2'b00;
        else
            pixel_reset_sync <= {pixel_reset_sync[0], 1'b1};
    end

    ov5640_axis_capture #(
        .PIXELS(`QR_CAMERA_PIXELS),
        .LINES(`QR_CAMERA_LINES),
        .FIFO_ADDR_WIDTH(10)
    ) capture_i (
        .rst(~camera_reset_sync[1]), .cam_pclk(cam1_pclk),
        .cam_d(cam1_d[9:2]), .cam_href(cam1_href), .cam_vsync(cam1_vsync),
        .m_axis_tdata(capture_data), .m_axis_tvalid(capture_valid),
        .m_axis_tready(capture_ready), .m_axis_tuser(capture_user),
        .m_axis_tlast(capture_last));

    qr_camera_axis_fork #(
        .QR_FIFO_ADDR_WIDTH(`QR_CAMERA_PL_ROI ? 11 : 6),
        .QR_SYNC_READ(`QR_CAMERA_PL_ROI)
    ) fork_i (
        .aclk(cam1_pclk), .aresetn(camera_reset_sync[1]),
        .s_axis_tdata(capture_data), .s_axis_tkeep(2'b11),
        .s_axis_tvalid(capture_valid), .s_axis_tready(capture_ready),
        .s_axis_tuser(capture_user), .s_axis_tlast(capture_last),
        .m0_axis_tdata(display_raw_data), .m0_axis_tkeep(display_raw_keep),
        .m0_axis_tvalid(display_raw_valid), .m0_axis_tready(display_raw_ready),
        .m0_axis_tuser(display_raw_user), .m0_axis_tlast(display_raw_last),
        .m1_axis_tdata(qr_tap_data), .m1_axis_tkeep(qr_tap_keep),
        .m1_axis_tvalid(qr_tap_valid), .m1_axis_tready(qr_tap_ready),
        .m1_axis_tuser(qr_tap_user), .m1_axis_tlast(qr_tap_last));

    /* The HDMI path keeps the camera stream at its native geometry.  A 720p
     * monitor mode is transmitted for the 1280x720 profile; a 1080p panel
     * performs any required panel scaling itself. */
    assign display_in_data = display_raw_data;
    assign display_in_keep = display_raw_keep;
    assign display_in_valid = display_raw_valid;
    assign display_raw_ready = display_in_ready;
    assign display_in_user = display_raw_user;
    assign display_in_last = display_raw_last;

    qr_camera_frame_gate #(
        .LINES(`QR_CAMERA_LINES), .CONTINUOUS(1)
    ) gate_i (
        .aclk(cam1_pclk), .aresetn(camera_reset_sync[1]),
        .arm_async(camera_arm_ctrl[0]),
        .s_axis_tdata(qr_tap_data), .s_axis_tkeep(qr_tap_keep),
        .s_axis_tvalid(qr_tap_valid), .s_axis_tready(qr_tap_ready),
        .s_axis_tuser(qr_tap_user), .s_axis_tlast(qr_tap_last),
        .m_axis_tdata(gated_data), .m_axis_tkeep(gated_keep),
        .m_axis_tvalid(gated_valid), .m_axis_tready(gated_ready),
        .m_axis_tuser(gated_user), .m_axis_tlast(gated_last),
        .frame_active(gate_active), .frame_done_toggle(gate_done_toggle));

    design_1_wrapper bd_i (
        .DDR_addr(DDR_addr), .DDR_ba(DDR_ba), .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n), .DDR_ck_p(DDR_ck_p), .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n), .DDR_dm(DDR_dm), .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n), .DDR_dqs_p(DDR_dqs_p), .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n), .DDR_reset_n(DDR_reset_n), .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn), .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio), .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb), .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .pl_resetn(pl_resetn), .camera_reset_ctrl(camera_reset_ctrl),
        .camera_arm_ctrl(camera_arm_ctrl), .hdmi_reset_ctrl(hdmi_reset_ctrl),
        .IIC_0_scl_io(cam1_scl), .IIC_0_sda_io(cam1_sda),
        .IIC_1_scl_io(hdmi_scl), .IIC_1_sda_io(hdmi_sda),
        .qr_video_in_aclk(cam1_pclk),
        .qr_video_in_aresetn(camera_reset_sync[1]),
        .qr_video_in_tdata(gated_data),
        .qr_video_in_tkeep(gated_keep), .qr_video_in_tlast(gated_last),
        .qr_video_in_tready(gated_ready), .qr_video_in_tuser(gated_user),
        .qr_video_in_tvalid(gated_valid),
        .display_video_in_aclk(cam1_pclk),
        .display_video_in_tdata(display_in_data),
        .display_video_in_tkeep(display_in_keep),
        .display_video_in_tlast(display_in_last),
        .display_video_in_tready(display_in_ready),
        .display_video_in_tuser(display_in_user),
        .display_video_in_tvalid(display_in_valid),
        .display_pixel_clk(pixel_clk),
        .display_video_out_tdata(display_out_data),
        .display_video_out_tkeep(display_out_keep),
        .display_video_out_tlast(display_out_last),
        .display_video_out_tready(display_out_ready),
        .display_video_out_tuser(display_out_user),
        .display_video_out_tvalid(display_out_valid),
        .osd_commit_ctrl(osd_commit_ctrl),
        .osd_bram_addr(osd_bram_addr), .osd_bram_en(osd_bram_en),
        .osd_bram_data(osd_bram_data),
        .hdmi_diag_status(hdmi_debug_status),
        .hdmi_diag_counts(hdmi_debug_counts));

    generate
        if (`QR_CAMERA_PIXELS == 1280) begin : gen_hdmi_720p
            qr_hdmi_video_timing #(
                .H_ACTIVE(1280), .H_FP(110), .H_SYNC(40), .H_BP(220),
                .V_ACTIVE(720), .V_FP(5), .V_SYNC(5), .V_BP(20),
                .VIDEO_WIDTH(1280), .VIDEO_HEIGHT(720)
            ) timing_i (
                .pixel_clk(pixel_clk), .rst(~pixel_reset_sync[1]),
                .s_axis_tdata(display_out_data),
                .s_axis_tvalid(display_out_valid),
                .s_axis_tready(display_out_ready),
                .s_axis_tuser(display_out_user),
                .s_axis_tlast(display_out_last),
                .osd_commit(osd_commit_ctrl), .osd_bram_addr(osd_bram_addr),
                .osd_bram_en(osd_bram_en), .osd_bram_data(osd_bram_data),
                .hdmi_d(hdmi_d), .hdmi_de(hdmi_de), .hdmi_hs(hdmi_hs),
                .hdmi_vs(hdmi_vs), .hdmi_clk(hdmi_clk),
                .debug_status(hdmi_debug_status),
                .debug_counts(hdmi_debug_counts));
        end else begin : gen_hdmi_svga
            qr_hdmi_video_timing timing_i (
                .pixel_clk(pixel_clk), .rst(~pixel_reset_sync[1]),
                .s_axis_tdata(display_out_data),
                .s_axis_tvalid(display_out_valid),
                .s_axis_tready(display_out_ready),
                .s_axis_tuser(display_out_user),
                .s_axis_tlast(display_out_last),
                .osd_commit(osd_commit_ctrl), .osd_bram_addr(osd_bram_addr),
                .osd_bram_en(osd_bram_en), .osd_bram_data(osd_bram_data),
                .hdmi_d(hdmi_d), .hdmi_de(hdmi_de), .hdmi_hs(hdmi_hs),
                .hdmi_vs(hdmi_vs), .hdmi_clk(hdmi_clk),
                .debug_status(hdmi_debug_status),
                .debug_counts(hdmi_debug_counts));
        end
    endgenerate

    wire unused = gate_active ^ gate_done_toggle ^ ^display_out_keep;
endmodule
