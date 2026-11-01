`timescale 1ns/1ps
// Two row banks convert the byte-per-pixel QR stream into a 32-bit AXIS.
// RGB mode is a row plane layout: [2*width RGB bytes][width QR bytes].
// Header/footer rows contain zero RGB followed by the unchanged QR guard.
// READY depends only on registered ownership, never downstream READY.
module qr_capture_row_pack #(
 parameter integer RGB_ENABLE=0,
 parameter integer MAX_WIDTH=1280
)(
 input wire aclk,aresetn,
 input wire [7:0] s_gray,input wire [15:0] s_rgb,input wire s_guard,
 input wire [15:0] s_width,
 input wire s_valid,output wire s_ready,input wire s_last,s_user,
 output wire [31:0] m_data,output wire [3:0] m_keep,
 output wire m_valid,input wire m_ready,output wire m_last,m_user,
 output reg [31:0] stall_count,error_count,output reg [1:0] peak_rows
);
 localparam WORDS=MAX_WIDTH/4,RAW_WORDS=MAX_WIDTH/2;
 (* ram_style="block" *) reg [31:0] gray_mem[0:2*WORDS-1];
 // Only the RGB build instantiates RGB RAM.
 wire [31:0] raw_q;
 reg [31:0] gray_q;
 reg [1:0] full;
 reg wr_bank,rd_bank;
 reg [15:0] wr_x,width_bank0,width_bank1;
 reg user_bank0,user_bank1;
 reg [31:0] gray_pack;
 reg [15:0] raw_half;
 wire fire=s_valid&&s_ready;
 wire fresh=s_user;
 wire [15:0] write_x=fresh?16'd0:wr_x;
 wire [31:0] gray_next=(write_x[1:0]==0)?{24'd0,s_gray}:
   (gray_pack|({24'd0,s_gray}<<(write_x[1:0]*8)));
 wire gray_we=fire&&(write_x[1:0]==3||s_last);
 wire [15:0] gray_wa=(wr_bank?WORDS:0)+(write_x>>2);
 wire [15:0] raw_wa=(wr_bank?RAW_WORDS:0)+(write_x>>1);
 wire [15:0] raw_in=s_guard?16'd0:s_rgb;
 wire [31:0] raw_next={raw_in,(write_x[0]?raw_half:16'd0)};
 wire raw_we=fire&&(write_x[0]||s_last);
 reg rd_active,rd_raw;
 reg [15:0] rd_word,rd_width;
 reg rd_sof;
 reg out_valid,out_last,out_user,out_raw;
 wire advance=!out_valid||m_ready;
 wire issue=rd_active&&advance;
 wire [15:0] gray_ra=(rd_bank?WORDS:0)+rd_word;
 wire [15:0] raw_ra=(rd_bank?RAW_WORDS:0)+rd_word;
 wire raw_end=rd_word==(rd_width>>1)-1'b1;
 wire row_end=!rd_raw&&rd_word==(rd_width>>2)-1'b1;
 wire [1:0] occupied={1'b0,full[0]}+{1'b0,full[1]};
 assign s_ready=!full[wr_bank];
 assign m_data=out_raw?raw_q:gray_q;
 assign m_keep=4'b1111;
 assign m_valid=out_valid;
 assign m_last=out_last;
 assign m_user=out_user;
 always @(posedge aclk)begin
  if(gray_we)gray_mem[gray_wa]<=gray_next;
  if(issue&&!rd_raw)gray_q<=gray_mem[gray_ra];
 end
 generate if(RGB_ENABLE)begin:rgb_ram
  (* ram_style="block" *) reg [31:0] raw_mem[0:2*RAW_WORDS-1];
  reg [31:0] q;
  assign raw_q=q;
  always @(posedge aclk)begin
   if(raw_we)raw_mem[raw_wa]<=raw_next;
   if(issue&&rd_raw)q<=raw_mem[raw_ra];
  end
 end else begin:no_rgb_ram
  assign raw_q=0;
 end endgenerate
 always @(posedge aclk)begin
  if(!aresetn)begin
   full<=0;wr_bank<=0;rd_bank<=0;wr_x<=0;width_bank0<=0;width_bank1<=0;
   user_bank0<=0;user_bank1<=0;gray_pack<=0;raw_half<=0;
   rd_active<=0;rd_raw<=0;rd_word<=0;rd_width<=0;rd_sof<=0;
   out_valid<=0;out_last<=0;out_user<=0;out_raw<=0;
   stall_count<=0;error_count<=0;peak_rows<=0;
  end else begin
   if(occupied>peak_rows)peak_rows<=occupied;
   if(s_valid&&!s_ready)stall_count<=stall_count+1'b1;
   if(fire)begin
    if((fresh&&wr_x!=0)||s_width==0||s_width>MAX_WIDTH||s_width[1:0]!=0||
       s_last!=(write_x==s_width-1'b1))error_count<=error_count+1'b1;
    gray_pack<=gray_next;
    if(!write_x[0])raw_half<=raw_in;
    if(write_x==0)begin
     if(wr_bank)begin width_bank1<=s_width;user_bank1<=s_user;end
     else begin width_bank0<=s_width;user_bank0<=s_user;end
    end
    if(s_last)begin full[wr_bank]<=1;wr_bank<=!wr_bank;wr_x<=0;end
    else wr_x<=write_x+1'b1;
   end
   if(!rd_active&&full[rd_bank])begin
    rd_active<=1;rd_raw<=RGB_ENABLE!=0;rd_word<=0;
    rd_width<=rd_bank?width_bank1:width_bank0;
    rd_sof<=rd_bank?user_bank1:user_bank0;
   end
   if(advance)begin
    out_valid<=issue;
    if(issue)begin
     out_raw<=rd_raw;out_last<=row_end;out_user<=rd_sof&&rd_word==0&&(rd_raw||!RGB_ENABLE);
     if(row_end)begin
      full[rd_bank]<=0;rd_bank<=!rd_bank;rd_active<=0;rd_word<=0;
     end else if(rd_raw&&raw_end)begin rd_raw<=0;rd_word<=0;end
     else rd_word<=rd_word+1'b1;
    end
   end
  end
 end
endmodule
