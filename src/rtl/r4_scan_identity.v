`timescale 1ns/1ps
// Ordered sideband for VDMA read prefetch. A DDR AR at a frame base enqueues
// that buffer's tag; the tag is consumed only when the HDMI sink actually
// accepts that frame's SOF. Counting AR requests alone would overcount preview.
module r4_scan_identity(
 input wire aclk,aresetn,clear_toggle,
 input wire push,input wire [63:0] fetched_tag,
 input wire pixel_clk,pixel_resetn,pixel_start,
 output reg [63:0] scan_tag,output reg [31:0] unique_frames,
 output wire fault
);
 (* ram_style="block" *) reg [63:0] tags[0:7];
 reg [63:0] prefetched_tag;
 reg [3:0] wr,rd,wgray,rgray;
 (* ASYNC_REG="TRUE" *) reg [3:0] rg0,rg1,wg0,wg1;
 (* ASYNC_REG="TRUE" *) reg cl0,cl1,rf0,rf1;
 reg base_clear,pixel_clear,write_fault,read_fault;
 wire [3:0] next_wr=wr+1'b1,next_rd=rd+1'b1;
 wire full=((next_wr>>1)^next_wr)=={~rg1[3:2],rg1[1:0]};
 wire empty=rgray==wg1;
 reg [63:0] shown_tag;
 reg [31:0] shown_count;
 // Register Gray encoding in its source domain; no XOR glitches cross clocks.
 reg [31:0] count_gray;
 wire [31:0] next_count=shown_count+1'b1;
 (* ASYNC_REG="TRUE" *) reg [31:0] cg0,cg1;
 reg tag_toggle;
 (* ASYNC_REG="TRUE" *) reg tt0,tt1;
 reg tag_seen;
 function [31:0] decode_gray;input [31:0] g;integer i;begin
 decode_gray[31]=g[31];for(i=30;i>=0;i=i-1)decode_gray[i]=decode_gray[i+1]^g[i];end endfunction
 assign fault=write_fault||rf1;
 // Synchronous dual-clock BRAM read. The Gray pointer synchronizers ensure
 // written data is stable before non-empty is visible in the pixel domain.
 always @(posedge pixel_clk)prefetched_tag<=tags[(pixel_start&&!empty)?next_rd[2:0]:rd[2:0]];
 always @(posedge aclk)begin
  if(!aresetn)begin wr<=0;wgray<=0;rg0<=0;rg1<=0;base_clear<=0;write_fault<=0;
   rf0<=0;rf1<=0;cg0<=0;cg1<=0;unique_frames<=0;tt0<=0;tt1<=0;tag_seen<=0;scan_tag<=0;
  end else begin
   rg0<=rgray;rg1<=rg0;rf0<=read_fault;rf1<=rf0;cg0<=count_gray;cg1<=cg0;
   tt0<=tag_toggle;tt1<=tt0;unique_frames<=decode_gray(cg1);
   if(tt1!=tag_seen)begin scan_tag<=shown_tag;tag_seen<=tt1;end
   if(clear_toggle!=base_clear)begin
    base_clear<=clear_toggle;wr<=0;wgray<=0;write_fault<=0;scan_tag<=0;
   end else if(push)begin
    if(full)write_fault<=1;
    else begin tags[wr[2:0]]<=fetched_tag;wr<=next_wr;wgray<=(next_wr>>1)^next_wr;end
   end
  end
 end
 always @(posedge pixel_clk)begin
  if(!pixel_resetn)begin rd<=0;rgray<=0;wg0<=0;wg1<=0;cl0<=0;cl1<=0;pixel_clear<=0;
   read_fault<=0;shown_tag<=0;shown_count<=0;count_gray<=0;tag_toggle<=0;
  end else begin
   wg0<=wgray;wg1<=wg0;cl0<=clear_toggle;cl1<=cl0;
   if(cl1!=pixel_clear)begin
    pixel_clear<=cl1;rd<=0;rgray<=0;read_fault<=0;shown_tag<=0;shown_count<=0;count_gray<=0;tag_toggle<=~tag_toggle;
   end else if(pixel_start)begin
    if(empty)read_fault<=1;
    else begin
     rd<=next_rd;rgray<=(next_rd>>1)^next_rd;
     if(shown_tag!=prefetched_tag)begin shown_count<=next_count;count_gray<=next_count^(next_count>>1);end
     shown_tag<=prefetched_tag;tag_toggle<=~tag_toggle;
    end
   end
  end
 end
endmodule
