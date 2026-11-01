`timescale 1ns/1ps
module tb_r4_fork;
 reg clk=0;always #5 clk=~clk;
 reg resetn=0,en=1,clear=0;
 reg [15:0] data=0;reg valid=0,sof=0,last=0;
 wire [15:0] dd,qd;wire [64:0] du,qu;
 wire dv,dl,qv,ql,df,qf,ready;reg qrready=1,dr=1;
 wire [31:0] drops,qdrops,done,qdone,frames;wire [4:0] dp,qp;
 r4_camera_fork #(.AW(4),.WIDTH(8),.HEIGHT(4)) dut(
 .clk(clk),.resetn(resetn),.epoch(32'hfeed0123),.display_enable(en),.display_clear(clear),
 .s_data(data),.s_valid(valid),.s_sof(sof),.s_last(last),.s_ready(ready),
 .display_data(dd),.display_user(du),.display_valid(dv),.display_last(dl),.display_ready(dr),
 .qr_data(qd),.qr_user(qu),.qr_valid(qv),.qr_last(ql),.qr_ready(qrready),
 .display_fault(df),.qr_fault(qf),.display_dropped(drops),.qr_dropped(qdrops),
 .display_completed(done),.qr_completed(qdone),.display_peak(dp),.qr_peak(qp),.source_frames(frames));
 integer f,x,y,k,dc=0,dfull=0,dcframe=0;reg [15:0] held;reg holding=0;
 always @(posedge clk)if(resetn)begin
  if(!ready)$fatal(1,"source backpressure");
  if(holding && (!dv||dd!=held))$fatal(1,"withdrew stalled display beat");
  holding<=dv&&!dr;held<=dd;
  if(dv&&dr)begin
   if(du[0])begin if(dc!=0)$fatal(1,"display truncated normal frame");dcframe=du[32:1];end
   if(du[64:33]!=32'hfeed0123||du[32:1]!=dcframe)$fatal(1,"source tag pairing");
   if(dd!=(dcframe*100+dc)||dl!=(dc%8==7))$fatal(1,"display pixel/line corrupted %d %d",dd,dc);
   dc=dc+1;if(dc==32)begin dc=0;dfull=dfull+1;end
  end
 end
 initial begin
  repeat(4)@(negedge clk);resetn=1;
  for(f=1;f<=12;f=f+1)begin
   qrready=(f<3||f>5);
   for(y=0;y<4;y=y+1)for(x=0;x<8;x=x+1)begin
    @(negedge clk);valid=1;sof=(x==0&&y==0);last=x==7;data=f*100+y*8+x;
    @(negedge clk);valid=0;sof=0;last=0;
    dr=($urandom_range(0,3)!=0);
   end
   dr=1;repeat(16)@(negedge clk);
  end
  qrready=1;repeat(80)@(negedge clk);
  if(dfull!=12||done!=12||drops!=0||frames!=12||qdrops==0||qdone>=done)$fatal(1,"counts d=%d qr=%d drop=%d",done,qdone,qdrops);
  $display("R4_FORK_PASS independent stalls, QR overflow, full RGB and source tags: %d frames",dfull);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
