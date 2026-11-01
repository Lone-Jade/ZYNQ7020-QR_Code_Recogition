`timescale 1ns/1ps
// Version 2 camera stream. Guard rows travel through the same VDMA as pixels.
// Metadata locks at SOF; binary black=0, white=255. No whole-frame buffer here.
module qr_pl_roi_stream #(
 parameter integer SAMPLE_MODE=1, // 1=centre, 2=pooled five, 4=mean five
 parameter integer CANDIDATE_COUNT_MAX=4096,
 parameter integer GRAY_OUTPUT_DIVISOR=1,
 parameter integer DIAGONAL_ENABLE=1,
 parameter integer RGB_OUTPUT=0, PAYLOAD_BRAM=0,
 parameter integer ROI_SCORE_MIN=0,ROI_FINDER_DEDUP=0,ROI_IOU_DEDUP=0,ROI_IOU_UNION=0
)(
 input wire aclk,aresetn,
 input wire [63:0] source_tag,
 input wire [15:0] s_axi_awaddr,input wire [2:0] s_axi_awprot,input wire s_axi_awvalid,output wire s_axi_awready,
 input wire [31:0] s_axi_wdata,input wire [3:0] s_axi_wstrb,input wire s_axi_wvalid,output wire s_axi_wready,
 output wire [1:0] s_axi_bresp,output reg s_axi_bvalid,input wire s_axi_bready,
 input wire [15:0] s_axi_araddr,input wire [2:0] s_axi_arprot,input wire s_axi_arvalid,output wire s_axi_arready,
 output reg [31:0] s_axi_rdata,output wire [1:0] s_axi_rresp,output reg s_axi_rvalid,input wire s_axi_rready,
 input wire [15:0] s_axis_video_tdata,input wire [1:0] s_axis_video_tkeep,input wire s_axis_video_tvalid,
 output wire s_axis_video_tready,input wire s_axis_video_tlast,s_axis_video_tuser,
 output wire [7:0] m_axis_image_tdata,output wire m_axis_image_tkeep,m_axis_image_tvalid,
 input wire m_axis_image_tready,output wire m_axis_image_tlast,m_axis_image_tuser,
 output wire irq,
 output wire [15:0] m_axis_raw_tdata,output wire m_axis_guard,
 output wire [15:0] capture_width,output wire capture_resetn,
 input wire [31:0] capture_stall_count,capture_error_count,
 input wire [1:0] capture_peak_rows
);
 reg [31:0] control,mode,epoch,config_seq,next_frame,completed_frame,config_serial,active_serial;
 reg [15:0] width,height,min_module,max_module,tolerance,stat_xmin,stat_ymin,stat_xmax,stat_ymax;
 reg [7:0] manual_threshold,last_threshold;
 // Row-major grid, one byte per region. Locked alongside the image at SOF.
 reg [71:0] last_threshold_grid,active_threshold_grid;
 reg [8:0] last_threshold_mask,active_threshold_mask;
 reg [2:0] active_threshold_method;
 reg interp_setup;
 wire interp_ready;
 reg [31:0] last_threshold_source,last_threshold_config;
 reg soft_reset,frame_done;
 reg [15:0] awaddr;reg awheld,wheld;
 reg read_pending;reg [15:0] read_address_hold;
 wire [15:0] geometry_ro_address=read_pending?read_address_hold:s_axi_araddr;
 wire read_payload=s_axi_araddr>=16'hA000&&s_axi_araddr<16'hB800&&s_axi_araddr[10:0]>=64&&s_axi_araddr[10:0]<64+16*30*4;reg [31:0] wdata;reg [3:0] wstrb;
 wire [31:0] write_data=wheld?wdata:s_axi_wdata;
 wire [3:0] write_strb=wheld?wstrb:s_axi_wstrb;
 wire [15:0] write_addr=awheld?awaddr:s_axi_awaddr;
 wire write_fire=(awheld||s_axi_awvalid)&&(wheld||s_axi_wvalid)&&!s_axi_bvalid;
 wire config_touch=write_fire&&(write_addr!=16'h0018)&&(write_addr!=16'h001C);
 assign s_axi_awready=!awheld&&!s_axi_bvalid;
 assign s_axi_wready=!wheld&&!s_axi_bvalid;
 assign s_axi_bresp=0;assign s_axi_arready=!s_axi_rvalid&&!read_pending;assign s_axi_rresp=0;
 function [31:0] merge_bytes;
 input [31:0] old_value,new_value;input [3:0] strb;integer i;
 begin merge_bytes=old_value;for(i=0;i<4;i=i+1)if(strb[i])merge_bytes[i*8+:8]=new_value[i*8+:8];end
 endfunction
 wire processing_resetn=aresetn&&!soft_reset;
 localparam WAIT_SOF=0,HEADER=1,FIRST_PIXEL=2,PIXELS=3,FOOTER=4;
 reg [2:0] state;
 reg [15:0] gx,x,y,active_width,active_height;
 reg [15:0] active_min,active_max,active_tolerance,active_sxmin,active_symin,active_sxmax,active_symax;
 reg active_swap,last_threshold_valid;
 reg [31:0] active_frame,active_epoch,active_config,active_threshold_source,active_mode,pixel_count;
 reg [7:0] active_threshold,held_gray;
 reg [15:0] held_rgb;
 reg [1:0] held_keep;reg held_last;
 reg active_error,footer_error,geom_skip,finish_pending,finish_error,otsu_end_pending;reg [3:0] finish_delay;reg image_stalled;
 reg [31:0] guard_word;
 reg [63:0] active_source_tag;
 wire [7:0] rr={s_axis_video_tdata[15:11],s_axis_video_tdata[15:13]};
 wire [7:0] gg={s_axis_video_tdata[10:5],s_axis_video_tdata[10:9]};
 wire [7:0] bb={s_axis_video_tdata[4:0],s_axis_video_tdata[4:2]};
 wire swap_now=((state==WAIT_SOF)||((state==PIXELS)&&s_axis_video_tuser))?control[3]:active_swap;
 wire [7:0] r=swap_now?bb:rr,b=swap_now?rr:bb;
 wire [15:0] weighted_gray=r*16'd77+gg*16'd150+b*16'd29;
 wire [7:0] gray=(state==FIRST_PIXEL)?held_gray:weighted_gray[15:8];
 // Histogram split uses <= T and > T; binary must use the same convention.
 wire [7:0] spatial_threshold;
 wire black=gray<=spatial_threshold;
 wire image_phase=(state==FIRST_PIXEL)||(state==PIXELS);
 wire guard_phase=(state==HEADER)||(state==FOOTER);
 // Four parity banks accept simultaneous H/V/D45/D135 events without
 // multiple writes to a physical RAM. One logical candidate is drained/cycle.
 (* ram_style="distributed" *) reg [65:0] candidate0[0:31],candidate1[0:31],candidate2[0:31],candidate3[0:31];
 reg [6:0] fifo_write,fifo_read;reg [8:0] fifo_count;
 // Four scanner lanes, their pipeline, plus an already presented AXIS beat.
 wire fifo_space=fifo_count<104;
 // A presented AXIS beat cannot withdraw TVALID under downstream stall.
 // FIFO reserve covers scanner beats already in flight plus that held beat.
 wire image_allowed=(fifo_space||image_stalled)&&interp_ready;
 assign s_axis_video_tready=((state==WAIT_SOF)&&control[0])||((state==PIXELS)&&m_axis_image_tready&&image_allowed);
 // Unexpected SOF is a new frame, never a pixel from the truncated frame.
 assign m_axis_image_tvalid=guard_phase||(state==FIRST_PIXEL&&image_allowed)||(state==PIXELS&&s_axis_video_tvalid&&!s_axis_video_tuser&&image_allowed);
 assign m_axis_image_tdata=guard_phase?((gx<80)?(guard_word>>(gx[1:0]*8)):8'd0):(active_mode[1]?(black?8'd0:8'd255):gray);
 assign m_axis_image_tkeep=1;
 assign m_axis_raw_tdata=(state==FIRST_PIXEL)?held_rgb:s_axis_video_tdata;
 assign m_axis_guard=guard_phase;
 assign capture_width=active_width;
 assign capture_resetn=processing_resetn;
 assign m_axis_image_tlast=guard_phase?(gx==active_width-1'b1):(x==active_width-1'b1);
 assign m_axis_image_tuser=(state==HEADER)&&(gx==0);
 wire pixel_fire=image_phase&&m_axis_image_tvalid&&m_axis_image_tready;
 wire image_start=pixel_fire&&(state==FIRST_PIXEL);
 wire image_end=pixel_fire&&(x==active_width-1'b1)&&(y==active_height-1'b1);
 // All three variants apply a single SOF-locked threshold to the full frame.
 assign spatial_threshold=active_threshold;
 assign interp_ready=1'b1;
 wire input_fire=s_axis_video_tvalid&&s_axis_video_tready;
 wire abort_frame=input_fire&&(state==PIXELS)&&s_axis_video_tuser;
 wire scan_resetn=processing_resetn&&!abort_frame;
 wire [15:0] scan_tolerance=active_tolerance;
 wire h_valid,v_valid;wire [15:0] h_x,h_y,h_m,h_e,v_x,v_y,v_m,v_e;
 qr_finder_stream scanner(.aclk(aclk),.aresetn(scan_resetn),.pixel_valid(pixel_fire),.frame_start(image_start),.black(black),
  .x(x),.y(y),.min_module(active_min),.max_module(active_max),.tolerance_q8(scan_tolerance),
  .h_valid(h_valid),.v_valid(v_valid),.h_x(h_x),.h_y(h_y),.h_module_q8(h_m),.h_error(h_e),
  .v_x(v_x),.v_y(v_y),.v_module_q8(v_m),.v_error(v_e));
 wire d0_valid,d1_valid;wire [15:0] d0_x,d0_y,d0_m,d0_e,d1_x,d1_y,d1_m,d1_e;
 generate if(DIAGONAL_ENABLE)begin:diag_scan
  qr_finder_diag_stream diagonals(.aclk(aclk),.aresetn(scan_resetn),.pixel_valid(pixel_fire),.frame_start(image_start),.black(black),
   .x(x),.y(y),.width(active_width),.min_module(active_min),.max_module(active_max),.tolerance_q8(scan_tolerance),
   .d0_valid(d0_valid),.d1_valid(d1_valid),.d0_x(d0_x),.d0_y(d0_y),.d0_module_q8(d0_m),.d0_error(d0_e),
   .d1_x(d1_x),.d1_y(d1_y),.d1_module_q8(d1_m),.d1_error(d1_e));
 end else begin:no_diag_scan
  assign d0_valid=0;assign d1_valid=0;
  assign d0_x=0;assign d0_y=0;assign d0_m=0;assign d0_e=0;
  assign d1_x=0;assign d1_y=0;assign d1_m=0;assign d1_e=0;
 end endgenerate
 wire otsu_valid;wire [7:0] otsu_scalar;wire [71:0] otsu_thresholds;wire [8:0] otsu_mask;wire [31:0] otsu_frame,otsu_config;
 qr_otsu_sampled #(.MODE(SAMPLE_MODE)) otsu(.aclk(aclk),.aresetn(scan_resetn),.frame_start(image_start),.frame_end(otsu_end_pending),.frame_error(active_error),
  .pixel_valid(pixel_fire),.gray(gray),.x(x),.y(y),.width(active_width),.height(active_height),
  .frame_seq(active_frame),.config_seq(active_serial),.result_valid(otsu_valid),.result_thresholds(otsu_thresholds),
  .result_mask(otsu_mask),.result_frame(otsu_frame),.result_config(otsu_config),.result_threshold(otsu_scalar));
 wire geom_ready,geom_busy;wire [1:0] geom_occupancy;wire [31:0] geom_ro_data;
 wire pop=(fifo_count!=0)&&geom_ready&&!geom_skip;
 wire geom_end=finish_pending&&(finish_delay==0)&&(fifo_count==0)&&!h_valid&&!v_valid&&!d0_valid&&!d1_valid;
 wire [65:0] candidate=fifo_read[1:0]==0?candidate0[fifo_read[6:2]]:
  fifo_read[1:0]==1?candidate1[fifo_read[6:2]]:fifo_read[1:0]==2?candidate2[fifo_read[6:2]]:candidate3[fifo_read[6:2]];
 qr_finder_roi #(.PAYLOAD_BRAM(PAYLOAD_BRAM),.LEG_MAX_MODULES(32),.WEIGHTED_SCORE(1),.FUSION_ENABLE(DIAGONAL_ENABLE),.SCORE_MIN(ROI_SCORE_MIN),.FINDER_DEDUP(ROI_FINDER_DEDUP),.IOU_DEDUP(ROI_IOU_DEDUP),.IOU_UNION(ROI_IOU_UNION)) geometry(.aclk(aclk),.aresetn(processing_resetn),.frame_start(image_start),.frame_end(geom_end),
  .frame_seq(active_frame),.epoch(active_epoch),.config_seq(active_config),.width(active_width),.height(active_height),
  .threshold(active_threshold),.threshold_source(active_threshold_source),
  .threshold_metadata({15'd0,active_threshold_mask,active_threshold_grid[71:64],
   active_threshold_grid[63:0],29'd0,active_threshold_method}),
  .frame_error((finish_pending?finish_error:active_error)||(config_touch&&(state!=WAIT_SOF))),
  .cand_valid(fifo_count!=0&&!geom_skip),.cand_ready(geom_ready),.cand_x(candidate[15:0]),.cand_y(candidate[31:16]),
  .cand_module_q8(candidate[47:32]),.cand_direction(candidate[64]),.cand_error(candidate[63:48]),.cand_branch(candidate[65]),
  .ro_address(geometry_ro_address),.ro_data(geom_ro_data),.busy(geom_busy),.raw_occupancy(geom_occupancy));
 // Passive per-frame candidate FIFO and admission-pressure diagnostics.
 reg [8:0] observe_fifo_max,observe_done_max;
 reg [1:0] observe_raw_max,observe_done_raw;
 reg [31:0] observe_stall,observe_done_stall,observe_busy,observe_done_busy;
 wire [1:0] occupancy_count={1'b0,geom_occupancy[0]}+{1'b0,geom_occupancy[1]};
 always @(posedge aclk)begin
  if(!processing_resetn)begin
   observe_fifo_max<=0;observe_done_max<=0;observe_raw_max<=0;observe_done_raw<=0;
   observe_stall<=0;observe_done_stall<=0;observe_busy<=0;observe_done_busy<=0;
  end else begin
   if(image_start)begin observe_fifo_max<=fifo_count;observe_raw_max<=occupancy_count;observe_stall<=0;observe_busy<=0;end
   else begin
    if(fifo_count>observe_fifo_max)observe_fifo_max<=fifo_count;
    if(occupancy_count>observe_raw_max)observe_raw_max<=occupancy_count;
    if(image_phase&&!image_allowed)observe_stall<=observe_stall+1;
    if(image_phase&&geom_busy)observe_busy<=observe_busy+1;
   end
   if(image_end)begin
    observe_done_max<=observe_fifo_max;observe_done_raw<=observe_raw_max;
    observe_done_stall<=observe_stall;observe_done_busy<=observe_busy;
   end
  end
 end
 assign irq=control[4]&&frame_done;
 always @* begin
  case(gx>>2)
   0:guard_word=(state==HEADER)?32'h32485251:32'h32465251;
   1:guard_word=32'h00020003;
   2:guard_word=active_epoch;3:guard_word=active_frame;4:guard_word=~active_frame;5:guard_word=active_config;
   6:guard_word=active_mode[1]?2:1;7:guard_word={active_height,active_width};8:guard_word={24'd0,active_threshold};
   9:guard_word=active_threshold_source;10:guard_word=(state==FOOTER)?pixel_count:0;
   11:guard_word=(state==FOOTER)?(footer_error?2:1):0;
   // Scalar word 8 is the centre tile only; it is not a global threshold.
   12:guard_word={29'd0,active_threshold_method};
   13:guard_word=active_threshold_grid[31:0];14:guard_word=active_threshold_grid[63:32];
   15:guard_word={15'd0,active_threshold_mask,active_threshold_grid[71:64]};
   16:guard_word=32'h34544701;17:guard_word=active_source_tag[63:32];
   18:guard_word=active_source_tag[31:0];19:guard_word=~active_source_tag[31:0];
   default:guard_word=0;
  endcase
 end
 // AXI Lite accepts address/data independently and retains read data during stalls.
 always @(posedge aclk)begin
  if(!aresetn)begin
   control<=0;mode<=3;epoch<=1;config_seq<=1;config_serial<=0;next_frame<=1;width<=1280;height<=720;
   manual_threshold<=200;min_module<=2;max_module<=96;tolerance<=128;stat_xmin<=80;stat_ymin<=110;stat_xmax<=1140;stat_ymax<=265;
   soft_reset<=0;read_pending<=0;read_address_hold<=0;awheld<=0;wheld<=0;awaddr<=0;wdata<=0;wstrb<=0;s_axi_bvalid<=0;s_axi_rvalid<=0;s_axi_rdata<=0;
  end else begin
   soft_reset<=0;
   if(s_axi_awvalid&&s_axi_awready)begin awaddr<=s_axi_awaddr;awheld<=1;end
   if(s_axi_wvalid&&s_axi_wready)begin wdata<=s_axi_wdata;wstrb<=s_axi_wstrb;wheld<=1;end
   if(s_axi_bvalid&&s_axi_bready)s_axi_bvalid<=0;
   if(write_fire)begin
    awheld<=0;wheld<=0;s_axi_bvalid<=1;
    // The public sequence is host controlled. A private serial additionally
    // cancels in-flight Otsu work even if a host writes the same public value.
    if(write_addr!=16'h0018&&write_addr!=16'h001C)config_serial<=config_serial+1'b1;
    case(write_addr)
     16'h0000:begin control<=merge_bytes(control,write_data,write_strb)&32'hfffffffd;soft_reset<=write_strb[0]&&write_data[1];end
     16'h0008:width<=merge_bytes({16'd0,width},write_data,write_strb);
     16'h000C:height<=merge_bytes({16'd0,height},write_data,write_strb);
     16'h0010:manual_threshold<=merge_bytes({24'd0,manual_threshold},write_data,write_strb);
     16'h0018:next_frame<=merge_bytes(next_frame,write_data,write_strb);
     16'h002C:min_module<=merge_bytes({16'd0,min_module},write_data,write_strb);
     16'h0030:max_module<=merge_bytes({16'd0,max_module},write_data,write_strb);
     16'h0034:tolerance<=merge_bytes({16'd0,tolerance},write_data,write_strb);
     16'h0040:mode<=merge_bytes(mode,write_data,write_strb);
     16'h0044:epoch<=merge_bytes(epoch,write_data,write_strb);
     16'h0048:config_seq<=merge_bytes(config_seq,write_data,write_strb);
     16'h004C:stat_xmin<=merge_bytes({16'd0,stat_xmin},write_data,write_strb);
     16'h0050:stat_ymin<=merge_bytes({16'd0,stat_ymin},write_data,write_strb);
     16'h0054:stat_xmax<=merge_bytes({16'd0,stat_xmax},write_data,write_strb);
     16'h0058:stat_ymax<=merge_bytes({16'd0,stat_ymax},write_data,write_strb);
     default:begin end
    endcase
   end
   if(input_fire&&s_axis_video_tuser&&((state==WAIT_SOF)||(state==PIXELS))&&!(write_fire&&write_addr==16'h0018))next_frame<=next_frame+1'b1;
   if(s_axi_rvalid&&s_axi_rready)s_axi_rvalid<=0;
   if(read_pending)begin
    s_axi_rdata<=geom_ro_data;s_axi_rvalid<=1;read_pending<=0;
   end
   if(s_axi_arvalid&&s_axi_arready)begin
    read_address_hold<=s_axi_araddr;
    s_axi_rvalid<=!(PAYLOAD_BRAM&&read_payload);
    if(PAYLOAD_BRAM&&read_payload)read_pending<=1;
    if((s_axi_araddr>=16'hA000&&s_axi_araddr<16'hB800)||(s_axi_araddr>=16'h0100&&s_axi_araddr<16'h0200))s_axi_rdata<=geom_ro_data;
    else case(s_axi_araddr)
     16'h0000:s_axi_rdata<=control;16'h0004:s_axi_rdata<={27'd0,!active_error,active_error,1'b0,frame_done,(state!=WAIT_SOF)};
     16'h0008:s_axi_rdata<=width;16'h000C:s_axi_rdata<=height;16'h0010:s_axi_rdata<=manual_threshold;
     16'h0018:s_axi_rdata<=next_frame;16'h001C:s_axi_rdata<=frame_done;16'h0020:s_axi_rdata<=32'h00020003;
     16'h0028:s_axi_rdata<=pixel_count;16'h002C:s_axi_rdata<=min_module;16'h0030:s_axi_rdata<=max_module;
     16'h0034:s_axi_rdata<=tolerance;16'h0038:s_axi_rdata<=completed_frame;16'h003C:s_axi_rdata<=GRAY_OUTPUT_DIVISOR;
     16'h0040:s_axi_rdata<=mode;16'h0044:s_axi_rdata<=epoch;16'h0048:s_axi_rdata<=config_seq;
     16'h004C:s_axi_rdata<=stat_xmin;16'h0050:s_axi_rdata<=stat_ymin;16'h0054:s_axi_rdata<=stat_xmax;16'h0058:s_axi_rdata<=stat_ymax;
     16'h005C:s_axi_rdata<=active_threshold;16'h0060:s_axi_rdata<=active_threshold_source;
     16'h0064:s_axi_rdata<=SAMPLE_MODE;
     16'h0200:s_axi_rdata<=32'hAC040002;
     16'h0204:s_axi_rdata<={7'd0,observe_done_max,14'd0,observe_done_raw};
     16'h0208:s_axi_rdata<=observe_done_stall;
     16'h020C:s_axi_rdata<=observe_done_busy;
     16'h0210:s_axi_rdata<=32'h00010000; // independent capture layout ABI
     16'h0214:s_axi_rdata<=32'd1|(RGB_OUTPUT?32'd2:32'd0)|(PAYLOAD_BRAM?32'd4:32'd0);
     16'h0218:s_axi_rdata<=RGB_OUTPUT?32'd1:32'd0;
     16'h021C:s_axi_rdata<=width*(RGB_OUTPUT?32'd3:32'd1);
     16'h0220:s_axi_rdata<=0;
     16'h0224:s_axi_rdata<=RGB_OUTPUT?({16'd0,width}<<1):32'd0;
     16'h0228:s_axi_rdata<={30'd0,capture_peak_rows};
     16'h022C:s_axi_rdata<=capture_error_count;
     16'h0230:s_axi_rdata<=capture_stall_count;
     16'h0234:s_axi_rdata<=32'hAC040401;
     16'h007C:s_axi_rdata<=32'h00010001;
     16'h0080,16'h0084,16'h0088,16'h008C,16'h0090:s_axi_rdata<=geom_ro_data;
     16'h0078:s_axi_rdata<=30; // ROI capacity, paired with ABI revision.
     16'h0068:s_axi_rdata<=active_threshold_grid[31:0];16'h006C:s_axi_rdata<=active_threshold_grid[63:32];
     16'h0070:s_axi_rdata<={15'd0,active_threshold_mask,active_threshold_grid[71:64]};
     16'h0074:s_axi_rdata<=active_threshold_method;
     default:s_axi_rdata<=0;
    endcase
   end
  end
 end
 integer grid_i;
 reg push_h,push_v,push_d0,push_d1;reg [2:0] push_count;
 wire [6:0] h_write=fifo_write;
 wire [6:0] v_write=fifo_write+(push_h?7'd1:7'd0);
 wire [6:0] d0_write=v_write+(push_v?7'd1:7'd0);
 wire [6:0] d1_write=d0_write+(push_d0?7'd1:7'd0);
 wire [65:0] h_word={2'b00,1'b0,(h_e[15]?15'h7fff:h_e[14:0]),h_m,h_y,h_x};
 wire [65:0] v_word={2'b01,1'b0,(v_e[15]?15'h7fff:v_e[14:0]),v_m,v_y,v_x};
 wire [65:0] d0_word={2'b10,1'b0,(d0_e[15]?15'h7fff:d0_e[14:0]),d0_m,d0_y,d0_x};
 wire [65:0] d1_word={2'b11,1'b0,(d1_e[15]?15'h7fff:d1_e[14:0]),d1_m,d1_y,d1_x};
 genvar bank;
 generate for(bank=0;bank<4;bank=bank+1)begin:queue_bank
  wire wh=push_h&&h_write[1:0]==bank;
  wire wv=push_v&&v_write[1:0]==bank;
  wire wd0=push_d0&&d0_write[1:0]==bank;
  wire wd1=push_d1&&d1_write[1:0]==bank;
  wire we=wh||wv||wd0||wd1;
  wire [4:0] address=wh?h_write[6:2]:wv?v_write[6:2]:wd0?d0_write[6:2]:d1_write[6:2];
  wire [65:0] word=wh?h_word:wv?v_word:wd0?d0_word:d1_word;
  if(bank==0)always @(posedge aclk)if(we)candidate0[address]<=word;
  if(bank==1)always @(posedge aclk)if(we)candidate1[address]<=word;
  if(bank==2)always @(posedge aclk)if(we)candidate2[address]<=word;
  if(bank==3)always @(posedge aclk)if(we)candidate3[address]<=word;
 end endgenerate
 always @*begin
  push_h=h_valid&&!geom_skip&&(fifo_count<128);
  push_v=v_valid&&!geom_skip&&(fifo_count+(push_h?1:0)<128);
  push_d0=d0_valid&&!geom_skip&&(fifo_count+(push_h?1:0)+(push_v?1:0)<128);
  push_d1=d1_valid&&!geom_skip&&(fifo_count+(push_h?1:0)+(push_v?1:0)+(push_d0?1:0)<128);
  push_count={2'b0,push_h}+{2'b0,push_v}+{2'b0,push_d0}+{2'b0,push_d1};
 end
 always @(posedge aclk)begin
  if(!processing_resetn)begin
   active_source_tag<=0;state<=WAIT_SOF;gx<=0;x<=0;y<=0;active_width<=1280;active_height<=720;active_frame<=0;active_epoch<=0;active_config<=0;
   active_threshold<=200;active_threshold_source<=0;active_mode<=3;pixel_count<=0;held_gray<=0;held_rgb<=0;held_keep<=0;held_last<=0;
   active_error<=0;footer_error<=0;geom_skip<=0;finish_pending<=0;finish_error<=0;finish_delay<=0;otsu_end_pending<=0;frame_done<=0;completed_frame<=0;image_stalled<=0;
   last_threshold<=200;last_threshold_source<=0;last_threshold_config<=0;last_threshold_valid<=0;fifo_count<=0;fifo_write<=0;fifo_read<=0;
   last_threshold_grid<={9{8'd200}};active_threshold_grid<={9{8'd200}};
   last_threshold_mask<=0;active_threshold_mask<=0;active_threshold_method<=0;
   interp_setup<=0;
   active_min<=2;active_max<=96;active_tolerance<=128;active_sxmin<=80;active_symin<=110;active_sxmax<=1140;active_symax<=265;active_swap<=0;active_serial<=0;
  end else begin
   otsu_end_pending<=0;interp_setup<=0;if(finish_delay!=0)finish_delay<=finish_delay-1'b1;
   if(image_phase&&m_axis_image_tvalid&&!m_axis_image_tready)image_stalled<=1;
   if(pixel_fire)image_stalled<=0;
   if(otsu_valid&&otsu_config==config_serial&&!config_touch)begin
    for(grid_i=0;grid_i<9;grid_i=grid_i+1)
     last_threshold_grid[grid_i*8+:8]<=otsu_mask[grid_i]?otsu_thresholds[grid_i*8+:8]:
      (last_threshold_valid?last_threshold_grid[grid_i*8+:8]:manual_threshold);
    last_threshold<=otsu_scalar;
    last_threshold_mask<=otsu_mask;last_threshold_source<=otsu_frame;last_threshold_config<=config_seq;last_threshold_valid<=1;
   end
   if(config_touch)begin
    last_threshold_valid<=0;
    if(state!=WAIT_SOF)begin active_error<=1;if(finish_pending)finish_error<=1;end
   end
   fifo_write<=fifo_write+push_count;
   if(pop)fifo_read<=fifo_read+1'b1;
   fifo_count<=fifo_count+push_count-(pop?1:0);
   if((h_valid&&!push_h)||(v_valid&&!push_v)||(d0_valid&&!push_d0)||(d1_valid&&!push_d1))begin active_error<=1;if(finish_pending)finish_error<=1;end
   if(geom_end)finish_pending<=0;
   if(write_fire&&write_addr==16'h001C&&write_data[0])frame_done<=0;
   case(state)
    WAIT_SOF:begin end
    HEADER:if(m_axis_image_tready)begin if(gx==active_width-1'b1)begin gx<=0;state<=FIRST_PIXEL;end else gx<=gx+1'b1;end
    FIRST_PIXEL,PIXELS:if(pixel_fire)begin
     pixel_count<=pixel_count+1'b1;
     if((state==FIRST_PIXEL?held_keep:s_axis_video_tkeep)!=2'b11 ||
      (state==FIRST_PIXEL?held_last:s_axis_video_tlast)!=(x==active_width-1'b1)||
      (state==PIXELS&&s_axis_video_tuser))active_error<=1;
     if(image_end)begin
      state<=FOOTER;gx<=0;finish_pending<=1;finish_delay<=8;otsu_end_pending<=1;
      finish_error<=active_error||((state==FIRST_PIXEL?held_keep:s_axis_video_tkeep)!=2'b11)||
       ((state==FIRST_PIXEL?held_last:s_axis_video_tlast)!=(x==active_width-1'b1))||config_touch;
      // Freeze the complete footer at entry, so a later configuration write
      // cannot change an already presented AXIS byte while TREADY is low.
      // Late candidate/geometry errors remain visible in the ROI descriptor.
      footer_error<=active_error||((state==FIRST_PIXEL?held_keep:s_axis_video_tkeep)!=2'b11)||
       ((state==FIRST_PIXEL?held_last:s_axis_video_tlast)!=(x==active_width-1'b1))||config_touch;
     end
     else begin state<=PIXELS;if(x==active_width-1'b1)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;end
    end
    FOOTER:if(m_axis_image_tready)begin
     if(gx==active_width-1'b1)begin state<=WAIT_SOF;gx<=0;frame_done<=1;completed_frame<=active_frame;end else gx<=gx+1'b1;
    end
    default:state<=WAIT_SOF;
   endcase
   if(input_fire&&s_axis_video_tuser&&((state==WAIT_SOF)||(state==PIXELS)))begin
    held_gray<=weighted_gray[15:8];held_rgb<=s_axis_video_tdata;held_keep<=s_axis_video_tkeep;held_last<=s_axis_video_tlast;
    interp_setup<=1;
    active_source_tag<=source_tag;active_frame<=next_frame;active_epoch<=epoch;active_config<=config_seq;active_mode<=mode;active_serial<=config_serial;
    active_width<=((width<64)||(width>1280)||(width[1:0]!=0))?16'd1280:width;active_height<=((height==0)||(height>720))?16'd720:height;
    gx<=0;x<=0;y<=0;pixel_count<=0;frame_done<=0;image_stalled<=0;
    active_min<=((min_module<2)||(min_module>96))?16'd2:min_module;
    active_max<=((max_module<min_module)||(max_module>96)||(min_module<2)||(min_module>96))?16'd96:max_module;
    active_tolerance<=(tolerance>255)?16'd128:tolerance;
    active_sxmin<=stat_xmin;active_symin<=stat_ymin;active_sxmax<=stat_xmax;active_symax<=stat_ymax;active_swap<=control[3];
    active_threshold<=(mode[0]&&last_threshold_valid&&last_threshold_config==config_seq)?last_threshold:manual_threshold;
    active_threshold_source<=(mode[0]&&last_threshold_valid&&last_threshold_config==config_seq)?last_threshold_source:0;
    active_threshold_grid<=(mode[0]&&last_threshold_valid&&last_threshold_config==config_seq)?last_threshold_grid:{9{manual_threshold}};
    active_threshold_mask<=(mode[0]&&last_threshold_valid&&last_threshold_config==config_seq)?last_threshold_mask:0;
    active_threshold_method<=(mode[0]&&last_threshold_valid&&last_threshold_config==config_seq)?SAMPLE_MODE:3'd0;
    active_error<=(width<64)||(width>1280)||(width[1:0]!=0)||(height==0)||(height>720)||(GRAY_OUTPUT_DIVISOR!=1)||geom_busy||
     (min_module<2)||(min_module>96)||(max_module<min_module)||(max_module>96)||(tolerance>255);
    geom_skip<=geom_busy;state<=control[0]?HEADER:WAIT_SOF;
    if(abort_frame)begin
     // The old image deliberately has no footer, so it can never satisfy
     // the PS guard-pair check. End its geometry as invalid before starting
     // the new frame; HEADER gives this drain and histogram clear time.
     fifo_count<=0;fifo_read<=0;fifo_write<=0;
     finish_pending<=1;finish_delay<=8;finish_error<=1;otsu_end_pending<=0;
    end
   end
  end
 end
endmodule
