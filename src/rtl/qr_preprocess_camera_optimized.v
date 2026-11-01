`timescale 1ns/1ps

// Explicit camera source-mode wrapper. Version 2 provides guarded Binary8
// and PL-generated ROI banks; version 1 preserves the accepted Gray8 reference.
module qr_preprocess_top #(
    parameter integer CANDIDATE_COUNT_MAX = 2048,
    parameter integer GRAY_OUTPUT_DIVISOR = 1,
    parameter integer PL_ROI_ENABLE = 1,
    parameter integer RGB_OUTPUT = 0,
    parameter integer PAYLOAD_BRAM = 0,
    parameter integer ROI_SCORE_MIN=0,ROI_FINDER_DEDUP=0,ROI_IOU_DEDUP=0,ROI_IOU_UNION=0
) (
    input  wire         aclk,
    input  wire         aresetn,

    input  wire [15:0]  s_axi_awaddr,
    input  wire [2:0]   s_axi_awprot,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [15:0]  s_axi_araddr,
    input  wire [2:0]   s_axi_arprot,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,

    input  wire [15:0]  s_axis_video_tdata,
    input  wire [1:0]   s_axis_video_tkeep,
    input  wire         s_axis_video_tvalid,
    output wire         s_axis_video_tready,
    input  wire         s_axis_video_tlast,
    input  wire [64:0]  s_axis_video_tuser,

    output wire [31:0]  m_axis_image_tdata,
    output wire [3:0]   m_axis_image_tkeep,
    output wire         m_axis_image_tvalid,
    input  wire         m_axis_image_tready,
    output wire         m_axis_image_tlast,
    output wire         m_axis_image_tuser,

    output wire         irq
);
    wire [7:0] image_byte;
    wire image_keep,image_valid,image_ready,image_last,image_user;
    wire [15:0] image_rgb,image_width;
    wire image_guard,pack_resetn;
    wire [31:0] pack_stalls,pack_errors;
    wire [1:0] pack_peak;
    qr_capture_row_pack #(.RGB_ENABLE(RGB_OUTPUT)) capture_pack(
      .aclk(aclk),.aresetn(pack_resetn),.s_gray(image_byte),.s_rgb(image_rgb),
      .s_guard(image_guard),.s_width(image_width),.s_valid(image_valid),.s_ready(image_ready),
      .s_last(image_last),.s_user(image_user),.m_data(m_axis_image_tdata),.m_keep(m_axis_image_tkeep),
      .m_valid(m_axis_image_tvalid),.m_ready(m_axis_image_tready),.m_last(m_axis_image_tlast),
      .m_user(m_axis_image_tuser),.stall_count(pack_stalls),.error_count(pack_errors),.peak_rows(pack_peak));
    // Explicit build-time selection; the new protocol never falls back at run time.
    generate
        if (PL_ROI_ENABLE != 0) begin : pl_roi
            qr_pl_roi_stream #(.GRAY_OUTPUT_DIVISOR(GRAY_OUTPUT_DIVISOR),.RGB_OUTPUT(RGB_OUTPUT),.PAYLOAD_BRAM(PAYLOAD_BRAM),
              .ROI_SCORE_MIN(ROI_SCORE_MIN),.ROI_FINDER_DEDUP(ROI_FINDER_DEDUP),.ROI_IOU_DEDUP(ROI_IOU_DEDUP),.ROI_IOU_UNION(ROI_IOU_UNION)) pipeline (
            .aclk(aclk),
            .aresetn(aresetn),.source_tag(s_axis_video_tuser[64:1]),
            .s_axi_awaddr(s_axi_awaddr),
            .s_axi_awprot(s_axi_awprot),
            .s_axi_awvalid(s_axi_awvalid),
            .s_axi_awready(s_axi_awready),
            .s_axi_wdata(s_axi_wdata),
            .s_axi_wstrb(s_axi_wstrb),
            .s_axi_wvalid(s_axi_wvalid),
            .s_axi_wready(s_axi_wready),
            .s_axi_bresp(s_axi_bresp),
            .s_axi_bvalid(s_axi_bvalid),
            .s_axi_bready(s_axi_bready),
            .s_axi_araddr(s_axi_araddr),
            .s_axi_arprot(s_axi_arprot),
            .s_axi_arvalid(s_axi_arvalid),
            .s_axi_arready(s_axi_arready),
            .s_axi_rdata(s_axi_rdata),
            .s_axi_rresp(s_axi_rresp),
            .s_axi_rvalid(s_axi_rvalid),
            .s_axi_rready(s_axi_rready),
            .s_axis_video_tdata(s_axis_video_tdata),
            .s_axis_video_tkeep(s_axis_video_tkeep),
            .s_axis_video_tvalid(s_axis_video_tvalid),
            .s_axis_video_tready(s_axis_video_tready),
            .s_axis_video_tlast(s_axis_video_tlast),
            .s_axis_video_tuser(s_axis_video_tuser[0]),
            .m_axis_image_tdata(image_byte),
            .m_axis_image_tkeep(image_keep),
            .m_axis_image_tvalid(image_valid),
            .m_axis_image_tready(image_ready),
            .m_axis_image_tlast(image_last),
            .m_axis_image_tuser(image_user),
            .irq(irq),.m_axis_raw_tdata(image_rgb),.m_axis_guard(image_guard),
            .capture_width(image_width),.capture_resetn(pack_resetn),
            .capture_stall_count(pack_stalls),.capture_error_count(pack_errors),.capture_peak_rows(pack_peak)
            );
        end else begin : legacy_gray
            assign image_rgb=0;
            assign image_guard=0;
            assign pack_resetn=aresetn;
            qr_preprocess_camera_legacy #(.CANDIDATE_COUNT_MAX(CANDIDATE_COUNT_MAX),
                                          .GRAY_OUTPUT_DIVISOR(GRAY_OUTPUT_DIVISOR)) pipeline (
            .aclk(aclk),
            .aresetn(aresetn),
            .s_axi_awaddr(s_axi_awaddr),
            .s_axi_awprot(s_axi_awprot),
            .s_axi_awvalid(s_axi_awvalid),
            .s_axi_awready(s_axi_awready),
            .s_axi_wdata(s_axi_wdata),
            .s_axi_wstrb(s_axi_wstrb),
            .s_axi_wvalid(s_axi_wvalid),
            .s_axi_wready(s_axi_wready),
            .s_axi_bresp(s_axi_bresp),
            .s_axi_bvalid(s_axi_bvalid),
            .s_axi_bready(s_axi_bready),
            .s_axi_araddr(s_axi_araddr),
            .s_axi_arprot(s_axi_arprot),
            .s_axi_arvalid(s_axi_arvalid),
            .s_axi_arready(s_axi_arready),
            .s_axi_rdata(s_axi_rdata),
            .s_axi_rresp(s_axi_rresp),
            .s_axi_rvalid(s_axi_rvalid),
            .s_axi_rready(s_axi_rready),
            .s_axis_video_tdata(s_axis_video_tdata),
            .s_axis_video_tkeep(s_axis_video_tkeep),
            .s_axis_video_tvalid(s_axis_video_tvalid),
            .s_axis_video_tready(s_axis_video_tready),
            .s_axis_video_tlast(s_axis_video_tlast),
            .s_axis_video_tuser(s_axis_video_tuser[0]),
            .m_axis_image_tdata(image_byte),
            .m_axis_image_tkeep(image_keep),
            .m_axis_image_tvalid(image_valid),
            .m_axis_image_tready(image_ready),
            .m_axis_image_tlast(image_last),
            .m_axis_image_tuser(image_user),
            .irq(irq),.capture_width(image_width)
            );
        end
    endgenerate
endmodule
