`timescale 1ns/1ps
// DVP cannot be backpressured. Every source beat is consumed, each subscriber
// owns a separate elastic FIFO. A failed subscriber discards through SOF;
// TVALID already presented is retained until accepted (no FIFO flush on fault).
module r4_fork_branch #(
 parameter AW=10, WIDTH=1280, HEIGHT=720, STICKY=0
)(
 input wire clk, resetn, enable, clear_fault,
 input wire [15:0] s_data, input wire s_valid,s_sof,s_last,
 input wire [63:0] s_tag,
 output wire [15:0] m_data, output wire [64:0] m_user,
 output wire m_last,m_valid,input wire m_ready,
 output reg fault,output reg [31:0] dropped,completed,
 output reg [AW:0] peak
);
 localparam DEPTH=1<<AW;
 (* ram_style="block" *) reg [81:0] memory[0:DEPTH-1];
 reg [AW-1:0] wr,rd;reg [AW:0] count;
 reg admitted;reg [10:0] x;reg [9:0] y;
 wire pop=m_valid&&m_ready;
 wire room=count<DEPTH || pop;
 wire start=s_valid&&s_sof;
 wire accept_start=start&&enable&&(!fault||!STICKY)&&!(STICKY&&admitted)&&room;
 wire take=s_valid&&(accept_start || (admitted&&!s_sof));
 wire geometry=s_last==(x==WIDTH-1);
 wire push=take&&room&&(s_sof||geometry);
 // Synchronous BRAM read is prefetched; output held when stalled.
 reg [81:0] ram_head,bypass_data;
 reg bypass;
 wire [81:0] head=bypass?bypass_data:ram_head;
 wire [AW-1:0] next_rd=rd+1'b1;
 assign {m_user,m_last,m_data}=head;
 // Keep the BRAM read register free of reset and bypass multiplexing. This
 // is a true synchronous simple-dual-port RAM; bypass covers read/write
 // collisions only when the FIFO was empty or consumed its sole element.
 always @(posedge clk)begin
  if(push)memory[wr]<={s_tag,s_sof,s_last,s_data};
  ram_head<=memory[pop?next_rd:rd];
 end
 assign m_valid=count!=0;
 always @(posedge clk) begin
  if(!resetn)begin wr<=0;rd<=0;count<=0;admitted<=0;x<=0;y<=0;fault<=0;dropped<=0;completed<=0;peak<=0;bypass<=0;bypass_data<=0;end
  else begin
   if(clear_fault)fault<=0;
   case({push,pop}) 2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:;endcase
   if(count>peak)peak<=count;
   if(push)wr<=wr+1'b1;
   if(pop)rd<=rd+1'b1;
   // Bypass a simultaneous write to the next head (read-during-write is explicit).
   if(count==0&&push || count==1&&pop&&push)begin bypass<=1;bypass_data<={s_tag,s_sof,s_last,s_data};end
   else if(pop)bypass<=0;
   if(start)begin
    admitted<=accept_start;x<=1;y<=0;
    if(!accept_start)begin dropped<=dropped+1'b1;end
    if(admitted)begin fault<=1;dropped<=dropped+1'b1;end
   end else if(take)begin
    if(!room||!geometry)begin admitted<=0;fault<=1;dropped<=dropped+1'b1;end
    else if(s_last)begin x<=0;if(y==HEIGHT-1)begin admitted<=0;completed<=completed+1'b1;end else y<=y+1'b1;end
    else x<=x+1'b1;
   end
   if(!enable)admitted<=0;
  end
 end
endmodule

module r4_camera_fork #(
 parameter AW=10,WIDTH=1280,HEIGHT=720
)(
 input wire clk,resetn,input wire [31:0] epoch,
 input wire display_enable,display_clear,
 input wire [15:0] s_data,input wire s_valid,s_sof,s_last,
 output wire s_ready,
 output wire [15:0] display_data,qr_data,
 output wire [64:0] display_user,qr_user,
 output wire display_valid,display_last,qr_valid,qr_last,
 input wire display_ready,qr_ready,
 output wire display_fault,qr_fault,
 output wire [31:0] display_dropped,qr_dropped,display_completed,qr_completed,
 output wire [AW:0] display_peak,qr_peak,
 output reg [31:0] source_frames
);
 assign s_ready=1'b1;
 reg [31:0] source_frame;
 wire [63:0] tag={epoch,source_frame+{31'b0,s_sof}};
 always @(posedge clk)if(!resetn)begin source_frame<=0;source_frames<=0;end
 else if(s_valid&&s_sof)begin source_frame<=source_frame+1'b1;source_frames<=source_frames+1'b1;end
 r4_fork_branch #(.AW(AW),.WIDTH(WIDTH),.HEIGHT(HEIGHT),.STICKY(1)) display(
 .clk(clk),.resetn(resetn),.enable(display_enable),.clear_fault(display_clear),
 .s_data(s_data),.s_valid(s_valid),.s_sof(s_sof),.s_last(s_last),.s_tag(tag),
 .m_data(display_data),.m_user(display_user),.m_last(display_last),.m_valid(display_valid),.m_ready(display_ready),
 .fault(display_fault),.dropped(display_dropped),.completed(display_completed),.peak(display_peak));
 r4_fork_branch #(.AW(AW),.WIDTH(WIDTH),.HEIGHT(HEIGHT)) qr(
 .clk(clk),.resetn(resetn),.enable(1'b1),.clear_fault(1'b0),
 .s_data(s_data),.s_valid(s_valid),.s_sof(s_sof),.s_last(s_last),.s_tag(tag),
 .m_data(qr_data),.m_user(qr_user),.m_last(qr_last),.m_valid(qr_valid),.m_ready(qr_ready),
 .fault(qr_fault),.dropped(qr_dropped),.completed(qr_completed),.peak(qr_peak));
endmodule
