`timescale 1ns/1ps
// Independent AXI-lite control and pixel-clock compositor. One request may be
// outstanding. PS writes only the inactive bank; bank ownership changes at VB.
module r4_display_osd (
 (* X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *)
 input wire aclk,input wire aresetn,
 input wire pixel_clk,pixel_resetn,
 input wire [15:0] pixel_rgb,input wire [10:0] pixel_x,input wire [9:0] pixel_y,
 input wire pixel_de,pixel_hs,pixel_vs,
 output reg [15:0] out_rgb,output reg out_de,out_hs,out_vs,
 output wire capture_enable,output reg [31:0] source_epoch,
 output reg clear_toggle,
 input wire display_fault,
 input wire cam_clk,cam_resetn,
 output reg [31:0] base0,base1,base2,
 input wire [63:0] tag0,tag1,tag2,scan_tag,
 input wire [2:0] valid_slots,
 input wire memory_fault,safe_video,
 input wire [31:0] memory_errors,committed_frames,
 input wire [31:0] source_frames,display_frames,display_drops,qr_drops,
 input wire [31:0] unique_frames,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *) input wire [15:0] s_axi_awaddr,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *) input wire [2:0] s_axi_awprot,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *) input wire s_axi_awvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *) output wire s_axi_awready,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WDATA" *) input wire [31:0] s_axi_wdata,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *) input wire [3:0] s_axi_wstrb,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WVALID" *) input wire s_axi_wvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WREADY" *) output wire s_axi_wready,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BRESP" *) output wire [1:0] s_axi_bresp,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BVALID" *) output reg s_axi_bvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BREADY" *) input wire s_axi_bready,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *) input wire [15:0] s_axi_araddr,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *) input wire [2:0] s_axi_arprot,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *) input wire s_axi_arvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *) output wire s_axi_arready,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RDATA" *) output reg [31:0] s_axi_rdata,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RRESP" *) output wire [1:0] s_axi_rresp,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RVALID" *) output reg s_axi_rvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RREADY" *) input wire s_axi_rready
);
 reg [31:0] control,request_seq;
 // Coherent passive counter snapshot. The camera holds the bundle until the
 // next request; data has settled for two clocks before acknowledgement.
 reg stat_req;
 (* ASYNC_REG="TRUE" *) reg sr0,sr1,sa0,sa1;
 reg stat_ack;reg [127:0] stat_hold,stat_cache;
 always @(posedge cam_clk)begin
  if(!cam_resetn)begin sr0<=0;sr1<=0;stat_ack<=0;stat_hold<=0;end
  else begin sr0<=stat_req;sr1<=sr0;
   if(sr1!=stat_ack)begin stat_hold<={source_frames,display_frames,display_drops,qr_drops};stat_ack<=sr1;end
  end
 end
 always @(posedge aclk)begin
  if(!aresetn)begin stat_req<=0;sa0<=0;sa1<=0;stat_cache<=0;end
  else begin sa0<=stat_ack;sa1<=sa0;
   if(sa1==stat_req)begin stat_cache<=stat_hold;stat_req<=~stat_req;end
  end
 end
 (* ASYNC_REG="TRUE" *) reg ff0,ff1;
 always @(posedge aclk)if(!aresetn)begin ff0<=0;ff1<=0;end else begin ff0<=display_fault;ff1<=ff0;end
 reg request_toggle;
 (* ASYNC_REG="TRUE" *) reg req0,req1,ack0,ack1;
 (* ASYNC_REG="TRUE" *) reg [2:0] ctl0,ctl1;
 (* ASYNC_REG="TRUE" *) reg fault0,fault1;
 reg ack_toggle,bank;
 (* ASYNC_REG="TRUE" *) reg safe0,safe1;
 reg [31:0] applied_seq;
 // Banks written only while PS owns them. All 128 bytes must be submitted
 // before commit; pending freezes them until the round-trip acknowledge.
 (* ram_style="block" *) reg [31:0] chars0[0:255],chars1[0:255];
 reg [31:0] desc0[0:31],desc1[0:31],active_desc[0:31];
 reg [7:0] scene_age;
 reg [31:0] charword0,charword1;reg [1:0] byte_select;
 wire busy=request_toggle!=ack1;
 assign capture_enable=control[0];
 reg [31:0] applied0,applied1;
 always @(posedge aclk)begin
  if(!aresetn)begin ack0<=0;ack1<=0;applied0<=0;applied1<=0;end
  else begin ack0<=ack_toggle;ack1<=ack0;applied0<=applied_seq;applied1<=applied0;end
 end
 // Char read, font ROM, and compositing form a matched three-cycle pipeline.
 `include "r4_font.vh"
 wire [31:0] charword=bank?charword1:charword0;
 wire [7:0] character=charword>>{byte_select,3'b0};
 reg [4:0] glyph;
 reg [2:0] col0,col1;
 reg [2:0] row0;
 reg area0,area1;
 reg [15:0] rgb0,rgb1;
 reg [2:0] timing0,timing1;
 // Select one text area before constant division and shared BRAM/font reads.
 reg in_area,box_hit;reg [10:0] local_x;reg [9:0] local_y;
 reg [9:0] text_base;integer k;
 wire [9:0] char_index=text_base+{local_y[5:4],5'b0}+local_x/12;
 wire [2:0] column=(local_x%12)>>1;
 always @* begin
  in_area=0;local_x=0;local_y=0;text_base=0;box_hit=0;
  for(k=7;k>=0;k=k-1)begin
   if(active_desc[4*k+3][0])begin
    if(pixel_x>=active_desc[4*k][10:0] && pixel_x<active_desc[4*k+1][10:0] &&
       pixel_y>=active_desc[4*k][25:16] && pixel_y<active_desc[4*k+1][25:16] &&
       (pixel_x<active_desc[4*k][10:0]+2 || pixel_x>=active_desc[4*k+1][10:0]-2 ||
        pixel_y<active_desc[4*k][25:16]+2 || pixel_y>=active_desc[4*k+1][25:16]-2))box_hit=1;
    if(pixel_x>=active_desc[4*k+2][10:0] && pixel_x<active_desc[4*k+2][10:0]+384 &&
       pixel_y>=active_desc[4*k+2][25:16] && pixel_y<active_desc[4*k+2][25:16]+32)begin
     in_area=1;local_x=pixel_x-active_desc[4*k+2][10:0];
     local_y=pixel_y-active_desc[4*k+2][25:16];text_base=128+k*64;
    end
   end
  end
  // Fixed HUD has priority over target text.
  if(pixel_x>=880 && pixel_x<1264 && pixel_y>=16 && pixel_y<80)begin
   in_area=1;local_x=pixel_x-880;local_y=pixel_y-16;text_base=0;
  end
 end
 reg box0,box1;
 integer i,j;
 always @(posedge pixel_clk)begin
  if(!pixel_resetn)begin
   req0<=0;req1<=0;ack_toggle<=0;bank<=0;applied_seq<=0;
   ctl0<=0;ctl1<=0;fault0<=0;fault1<=0;safe0<=0;safe1<=0;
   byte_select<=0;glyph<=0;col0<=0;col1<=0;row0<=0;
   area0<=0;area1<=0;rgb0<=0;rgb1<=0;timing0<=0;timing1<=0;
   out_rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;scene_age<=180;box0<=0;box1<=0;
   for(j=0;j<32;j=j+1)active_desc[j]<=0;
  end else begin
   safe0<=safe_video;safe1<=safe0;req0<=request_toggle;req1<=req0;ctl0<=control[2:0];ctl1<=ctl0;
   fault0<=display_fault||memory_fault;fault1<=fault0;
   // Switch once at the beginning of vertical blank. Request sequence is
   // stable for the entire handshake; no pixel depends on later PS activity.
   if(pixel_y==720&&pixel_x==0&&req1!=ack_toggle)begin
    bank<=~bank;applied_seq<=request_seq;ack_toggle<=req1;scene_age<=0;
    for(j=0;j<32;j=j+1)active_desc[j]<=bank?desc0[j]:desc1[j];
   end
   else if(pixel_y==720&&pixel_x==0&&scene_age<180)scene_age<=scene_age+1;
   byte_select<=char_index[1:0];
   col0<=column;row0<=local_y[3:1];area0<=in_area&&pixel_de&&ctl1[2]&&scene_age<180;
   box0<=box_hit&&pixel_de&&ctl1[2]&&scene_age<180;box1<=box0;
   glyph<=font_row({character[6:0],row0});col1<=col0;area1<=area0;
   rgb0<=(ctl1[1]&&!fault1&&safe1)?pixel_rgb:0;rgb1<=rgb0;
   timing0<={pixel_de,pixel_hs,pixel_vs};timing1<=timing0;
   out_rgb<=(box1||(area1&&col1<5&&glyph[4-col1]))?16'h07e0:rgb1;
   {out_de,out_hs,out_vs}<=timing1;
  end
 end
 reg awheld,wheld;reg [15:0] awaddr;reg [31:0] wdata;reg [3:0] wstrb;
 reg [1:0] bresp;
 // Power-up spaces use BRAM INIT, not a 2048-bit resettable FF bank.
 // The inactive bank is immutable for the complete commit/ack handshake.
 initial begin
  for(i=0;i<256;i=i+1)begin chars0[i]=32'h20202020;chars1[i]=32'h20202020;end
  for(i=0;i<32;i=i+1)begin desc0[i]=0;desc1[i]=0;end
 end
 always @(posedge pixel_clk)begin
  charword0<=chars0[char_index[9:2]];charword1<=chars1[char_index[9:2]];
 end
 wire old_chars=awaddr>=16'h100&&awaddr<16'h180;
 wire scene_chars=awaddr>=16'h1000&&awaddr<16'h1400;
 wire [7:0] write_index=old_chars?{3'b0,awaddr[6:2]}:awaddr[9:2];
 always @(posedge aclk)if(aresetn&&awheld&&wheld&&(old_chars||scene_chars)&&!busy)begin
  for(i=0;i<4;i=i+1)if(wstrb[i])begin
   if(ack1)chars0[write_index][i*8+:8]<=wdata[i*8+:8];
   else chars1[write_index][i*8+:8]<=wdata[i*8+:8];
  end
 end
 always @(posedge aclk)if(aresetn&&awheld&&wheld&&awaddr>=16'h200&&awaddr<16'h280&&!busy&&wstrb==15)begin
  if(ack1)desc0[awaddr[6:2]]<=wdata;else desc1[awaddr[6:2]]<=wdata;
 end

 assign s_axi_awready=!awheld&&!s_axi_bvalid;
 assign s_axi_wready=!wheld&&!s_axi_bvalid;
 assign s_axi_bresp=bresp;
 assign s_axi_arready=!s_axi_rvalid;
 assign s_axi_rresp=0;
 always @(posedge aclk)begin
  if(!aresetn)begin
   awheld<=0;wheld<=0;s_axi_bvalid<=0;s_axi_rvalid<=0;s_axi_rdata<=0;bresp<=0;
   awaddr<=0;wdata<=0;wstrb<=0;control<=0;source_epoch<=0;clear_toggle<=0;
   request_seq<=0;request_toggle<=0;base0<=0;base1<=0;base2<=0;
  end else begin
   if(s_axi_awvalid&&s_axi_awready)begin awheld<=1;awaddr<=s_axi_awaddr;end
   if(s_axi_wvalid&&s_axi_wready)begin wheld<=1;wdata<=s_axi_wdata;wstrb<=s_axi_wstrb;end
   if(s_axi_bvalid&&s_axi_bready)s_axi_bvalid<=0;
   if(awheld&&wheld)begin
    awheld<=0;wheld<=0;s_axi_bvalid<=1;bresp<=0;
    if((old_chars||scene_chars||(awaddr>=16'h200&&awaddr<16'h280))&&!busy)begin
     // Byte writes are implemented by the dual-clock BRAM ports below.
    end else if(wstrb!=4'hf)bresp<=2;
    else case(awaddr)
     16'h10:control<=wdata&7;
     16'h14:if(!control[0])source_epoch<=wdata;else bresp<=2;
     16'h18:if(!control[0])clear_toggle<=~clear_toggle;else bresp<=2;
     16'h50:if(!control[0])base0<=wdata;else bresp<=2;
     16'h54:if(!control[0])base1<=wdata;else bresp<=2;
     16'h58:if(!control[0])base2<=wdata;else bresp<=2;
     16'h20:if(!busy&&wdata!=0&&wdata!=request_seq)begin request_seq<=wdata;request_toggle<=~request_toggle;end else bresp<=2;
     default:bresp<=2;
    endcase
   end
   if(s_axi_rvalid&&s_axi_rready)s_axi_rvalid<=0;
   if(s_axi_arvalid&&s_axi_arready)begin
    s_axi_rvalid<=1;
    case(s_axi_araddr[15:2])
     0:s_axi_rdata<=32'h52344401;
     1:s_axi_rdata<=2;
     2:s_axi_rdata<=11; // text + source tags + atomic scene rendering
     3:s_axi_rdata<={16'd720,16'd1280};
     4:s_axi_rdata<=control;5:s_axi_rdata<=source_epoch;
     6:s_axi_rdata<=clear_toggle;
     8:s_axi_rdata<=request_seq;
     9:s_axi_rdata<=applied1;
     10:s_axi_rdata<={29'b0,memory_fault,ff1,busy};
     12:s_axi_rdata<=stat_cache[127:96];13:s_axi_rdata<=stat_cache[95:64];
     14:s_axi_rdata<=stat_cache[63:32];15:s_axi_rdata<=stat_cache[31:0];
     16:s_axi_rdata<=unique_frames;
     17:s_axi_rdata<=committed_frames;18:s_axi_rdata<=memory_errors;
     19:s_axi_rdata<={29'b0,valid_slots};
     20:s_axi_rdata<=base0;21:s_axi_rdata<=base1;22:s_axi_rdata<=base2;
     24:s_axi_rdata<=tag0[63:32];25:s_axi_rdata<=tag0[31:0];
     26:s_axi_rdata<=tag1[63:32];27:s_axi_rdata<=tag1[31:0];
     28:s_axi_rdata<=tag2[63:32];29:s_axi_rdata<=tag2[31:0];
     30:s_axi_rdata<=scan_tag[63:32];31:s_axi_rdata<=scan_tag[31:0];
     default:s_axi_rdata<=0;
    endcase
   end
  end
 end
endmodule
