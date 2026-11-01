`timescale 1ns/1ps
// Passive DDR transaction observer. Tags belong to actual DMA start addresses,
// never to a live source counter. Each accepted AW is paired with its B response.
// A slot becomes valid only after the final burst returns OKAY. This monitor
// observes; Dynamic Genlock in the VDMA owns the actual triple-buffer schedule.
module r4_display_memory_guard(
 input wire clk,resetn,clear,
 input wire [31:0] base0,base1,base2,
 input wire [64:0] stream_user,input wire stream_valid,stream_ready,
 input wire [31:0] awaddr,input wire [7:0] awlen,input wire [2:0] awsize,
 input wire awvalid,awready,input wire [1:0] bresp,input wire bvalid,bready,
 input wire [31:0] araddr,input wire arvalid,arready,
 output reg [63:0] tag0,tag1,tag2,scan_tag,
 output reg read_tag_push,
 output reg [2:0] valid_slots,
 output reg [31:0] unique_frames,completed_frames,errors,
 output reg fault,output reg safe_video
);
 localparam BYTES=1280*720*2;
 reg [63:0] source_tag;
 reg clear_seen;
 wire clear_pulse=clear!=clear_seen;
 always @(posedge clk)if(!resetn)clear_seen<=0;else clear_seen<=clear;
 reg [1:0] write_slot,read_slot;
 reg write_active,read_active;
 // VDMA uses a single write ID. More than 16 outstanding transactions is
 // treated as a configuration error, not silently overwritten bookkeeping.
 reg [3:0] wr,rd;reg [4:0] count;
 reg [2:0] response_fifo[0:15];
 wire push=awvalid&&awready,pop=bvalid&&bready;
 wire [1:0] slot=(awaddr>=base0&&awaddr<base0+BYTES)?0:
                         (awaddr>=base1&&awaddr<base1+BYTES)?1:
                         (awaddr>=base2&&awaddr<base2+BYTES)?2:3;
 wire [31:0] selected_base=slot==0?base0:slot==1?base1:base2;
 wire last_burst=slot!=3&&(awaddr+(({24'b0,awlen}+1)<<awsize)==selected_base+BYTES);
 wire first_burst=slot!=3&&awaddr==selected_base;
 wire [1:0] read_index=araddr==base0?0:araddr==base1?1:araddr==base2?2:3;
 wire [63:0] read_tag=read_index==0?tag0:read_index==1?tag1:tag2;
 always @(posedge clk)begin
  if(!resetn||clear_pulse)begin
   tag0<=0;tag1<=0;tag2<=0;scan_tag<=0;valid_slots<=0;unique_frames<=0;completed_frames<=0;
   errors<=0;fault<=0;safe_video<=0;source_tag<=0;wr<=0;rd<=0;count<=0;
   read_tag_push<=0;write_slot<=3;read_slot<=3;write_active<=0;read_active<=0;
  end else begin
   read_tag_push<=0;
   if(stream_valid&&stream_ready&&stream_user[0])source_tag<=stream_user[64:1];
   case({push,pop})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:;endcase
   if(push)begin
    response_fifo[wr]<={last_burst,slot};wr<=wr+1'b1;
    if(slot==3||(count==16&&!pop))begin fault<=1;errors<=errors+1'b1;safe_video<=0;end
    if(first_burst)begin
     write_slot<=slot;write_active<=1;valid_slots[slot]<=0;
     case(slot)0:tag0<=(stream_valid&&stream_ready&&stream_user[0])?stream_user[64:1]:source_tag;1:tag1<=source_tag;2:tag2<=source_tag;endcase
     if(read_active&&read_slot==slot)begin fault<=1;errors<=errors+1'b1;safe_video<=0;end
    end
   end
   if(pop)begin
    rd<=rd+1'b1;
    if(count==0||bresp!=0)begin fault<=1;errors<=errors+1'b1;safe_video<=0;end
    else if(response_fifo[rd][2])begin
     valid_slots[response_fifo[rd][1:0]]<=!fault;
     write_active<=0;completed_frames<=completed_frames+1'b1;
    end
   end
   if(arvalid&&arready&&read_index!=3)begin
    read_slot<=read_index;read_active<=1;
    if(!valid_slots[read_index]||(write_active&&write_slot==read_index))begin
     fault<=1;errors<=errors+1'b1;safe_video<=0;
    end else if(!fault)begin
     scan_tag<=read_tag;read_tag_push<=1;safe_video<=1;
     if(scan_tag!=read_tag)unique_frames<=unique_frames+1'b1;
    end
   end
   // An address that is not a frame base is a normal later burst. The reader
   // retains ownership until its next base address or channel reset/clear.
  end
 end
endmodule
