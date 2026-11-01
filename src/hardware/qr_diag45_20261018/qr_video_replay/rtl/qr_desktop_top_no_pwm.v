`timescale 1ns/1ps

module qr_desktop_top (
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
    inout hdmi_iic_scl_io, inout hdmi_iic_sda_io,
    output [23:0] hdmi_d, output hdmi_de, output hdmi_hs,
    output hdmi_vs, output hdmi_clk, output [0:0] hdmi_reset_n
);
    wire pl_resetn;
    wire [0:0] camera_reset_ctrl;
    wire [0:0] camera_arm_ctrl;
    reg [1:0] camera_reset_sync = 2'b00;
    wire [15:0] capture_data;
    wire capture_valid, capture_ready, capture_user, capture_last;
    wire [15:0] fork_qr_data,display_data;
    wire [64:0] fork_qr_user,display_user;
    wire fork_qr_valid,fork_qr_ready,fork_qr_last,display_valid,display_ready,display_last;
    wire display_fault,qr_fault,display_enable,display_clear;
    wire [31:0] source_epoch,display_drops,qr_drops,display_frames,qr_frames,source_frames;
    wire [10:0] display_peak,qr_peak;
    (* ASYNC_REG="TRUE" *) reg en0,en1,cl0,cl1;
    (* ASYNC_REG="TRUE" *) reg [31:0] epoch0,epoch1;
    reg cl_seen;
    always @(posedge cam1_pclk)begin
      if(!camera_reset_sync[1])begin en0<=0;en1<=0;cl0<=0;cl1<=0;cl_seen<=0;epoch0<=0;epoch1<=0;end
      else begin en0<=display_enable;en1<=en0;cl0<=display_clear;cl1<=cl0;cl_seen<=cl1;epoch0<=source_epoch;epoch1<=epoch0;end
    end
    r4_camera_fork fork_i(.clk(cam1_pclk),.resetn(camera_reset_sync[1]),.epoch(epoch1),
      .display_enable(en1),.display_clear(cl1^cl_seen),
      .s_data(capture_data),.s_valid(capture_valid),.s_sof(capture_user),.s_last(capture_last),.s_ready(capture_ready),
      .display_data(display_data),.display_user(display_user),.display_valid(display_valid),.display_last(display_last),.display_ready(display_ready),
      .qr_data(fork_qr_data),.qr_user(fork_qr_user),.qr_valid(fork_qr_valid),.qr_last(fork_qr_last),.qr_ready(fork_qr_ready),
      .display_fault(display_fault),.qr_fault(qr_fault),.display_dropped(display_drops),.qr_dropped(qr_drops),
      .display_completed(display_frames),.qr_completed(qr_frames),.display_peak(display_peak),.qr_peak(qr_peak),.source_frames(source_frames));
    wire [15:0] gated_data;
    wire [1:0] gated_keep;
    wire gated_valid, gated_ready, gated_user, gated_last;
    wire frame_active, frame_done_toggle;
    wire [1:0] gate_state;
    wire gate_arm;

    always @(posedge cam1_pclk or negedge pl_resetn) begin
        if (!pl_resetn)
            camera_reset_sync <= 2'b00;
        else
            camera_reset_sync <= {camera_reset_sync[0], 1'b1};
    end
    assign cam1_reset_n = pl_resetn && camera_reset_ctrl[0];

    ov5640_axis_capture #(.PIXELS(1280), .LINES(720), .FIFO_ADDR_WIDTH(10)) capture_i (
        .rst(~camera_reset_sync[1]), .cam_pclk(cam1_pclk),
        .cam_d(cam1_d[9:2]), .cam_href(cam1_href), .cam_vsync(cam1_vsync),
        .m_axis_tdata(capture_data), .m_axis_tvalid(capture_valid),
        .m_axis_tready(capture_ready), .m_axis_tuser(capture_user),
        .m_axis_tlast(capture_last));

    // Linux hands a stable frame to userspace before requesting another.
    // One-shot admission prevents DVP overflow while DMA is stopped and keeps
    // the QR core alive so Otsu state survives between captured frames.
    qr_camera_frame_gate #(.LINES(720), .CONTINUOUS(0)) gate_i (
        .aclk(cam1_pclk), .aresetn(camera_reset_sync[1]),
        .arm_async(camera_arm_ctrl[0]),
        .s_axis_tdata(fork_qr_data), .s_axis_tkeep(2'b11),
        .s_axis_tvalid(fork_qr_valid), .s_axis_tready(fork_qr_ready),
        .s_axis_tuser(fork_qr_user[0]), .s_axis_tlast(fork_qr_last),
        .m_axis_tdata(gated_data), .m_axis_tkeep(gated_keep),
        .m_axis_tvalid(gated_valid), .m_axis_tready(gated_ready),
        .m_axis_tuser(gated_user), .m_axis_tlast(gated_last),
        .frame_active(frame_active), .frame_done_toggle(frame_done_toggle),
        .state_debug(gate_state),.arm_debug(gate_arm));

    system_wrapper system_i (
        .display_video_aclk(cam1_pclk),.display_video_aresetn(camera_reset_sync[1]),
        .display_video_tdata(display_data),.display_video_tkeep(2'b11),
        .display_video_tvalid(display_valid),.display_video_tready(display_ready),
        .display_video_tuser(display_user),.display_video_tlast(display_last),
        .r4_display_enable(display_enable),.r4_source_epoch(source_epoch),.r4_display_clear(display_clear),
        .r4_display_fault(display_fault),.r4_source_frames(source_frames),.r4_display_frames(display_frames),
        .r4_display_drops(display_drops),.r4_qr_drops(qr_drops),
        .diag_cam_clk(cam1_pclk),.diag_cam_resetn(camera_reset_sync[1]),
        .diag_cam_vsync(cam1_vsync),.diag_source_sof(capture_valid&&capture_ready&&capture_user),
        .diag_accepted_sof(gated_valid&&gated_ready&&gated_user),
        .diag_eof_toggle(frame_done_toggle),.diag_arm(gate_arm),.diag_gate_state(gate_state),
        .DDR_addr(DDR_addr), .DDR_ba(DDR_ba), .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n), .DDR_ck_p(DDR_ck_p), .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n), .DDR_dm(DDR_dm), .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n), .DDR_dqs_p(DDR_dqs_p), .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n), .DDR_reset_n(DDR_reset_n), .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn), .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio), .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb), .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .camera_iic_scl_io(cam1_scl), .camera_iic_sda_io(cam1_sda),
        .camera_reset_ctrl(camera_reset_ctrl), .camera_arm_ctrl(camera_arm_ctrl),
        .pl_resetn(pl_resetn), .qr_video_in_aclk(cam1_pclk),
        .qr_video_in_aresetn(camera_reset_sync[1]),
        .qr_video_in_tdata(gated_data), .qr_video_in_tkeep(gated_keep),
        .qr_video_in_tvalid(gated_valid), .qr_video_in_tready(gated_ready),
        .qr_video_in_tuser({fork_qr_user[64:1],gated_user}), .qr_video_in_tlast(gated_last),
        .hdmi_iic_scl_io(hdmi_iic_scl_io), .hdmi_iic_sda_io(hdmi_iic_sda_io),
        .hdmi_d(hdmi_d), .hdmi_de(hdmi_de), .hdmi_hs(hdmi_hs),
        .hdmi_vs(hdmi_vs), .hdmi_clk(hdmi_clk), .hdmi_reset_n(hdmi_reset_n));

    wire unused = frame_active ^ frame_done_toggle;
endmodule
