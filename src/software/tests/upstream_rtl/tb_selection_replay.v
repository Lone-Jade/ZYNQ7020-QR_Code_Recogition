`timescale 1ns/1ps
module tb_selection_replay;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,fs=0,fe=0,valid=0;reg [15:0] x=0,y=0,m=0,e=0,addr=0;reg direction=0,branch=0;
 reg [65:0] events[0:32767];wire [31:0] data[0:5];
 reg [2047:0] input_path,output_path;integer count,k,n,f,j;integer outs[0:5];integer traces[0:5];
 genvar q;
 generate for(q=0;q<5;q=q+1)begin:g
  localparam SCORE=q==3?145:q==4?150:0;
  qr_finder_roi #(.LEG_MAX_MODULES(32),.WEIGHTED_SCORE(1),.FUSION_ENABLE(1),
   .FINDER_DEDUP(q>0),.IOU_DEDUP(q>1),.SCORE_MIN(SCORE)) dut(
   .aclk(clk),.aresetn(rst),.frame_start(fs),.frame_end(fe),.frame_seq(32'd42),.epoch(32'd7),.config_seq(32'd1),
   .width(16'd1280),.height(16'd720),.threshold(8'd100),.threshold_source(32'd0),.frame_error(1'b0),.threshold_metadata(128'd0),
   .cand_valid(valid),.cand_ready(),.cand_x(x),.cand_y(y),.cand_module_q8(m),.cand_direction(direction),.cand_error(e),.cand_branch(branch),
   .ro_address(addr),.ro_data(data[q]),.busy());
  always @(posedge clk)if(rst&&dut.state==32&&dut.quality_done)
   $fwrite(traces[q],"%02x %04x %04x %04x %04x %08x %08x %08x %02x %02x %02x %04x %08x\n",dut.quality_score,dut.pending_minx,dut.pending_miny,dut.pending_maxx,dut.pending_maxy,dut.pending_p0,dut.pending_p1,dut.pending_p2,dut.pending_id0,dut.pending_id1,dut.pending_id2,dut.pending_dedup_module,dut.pending_flags);
 end endgenerate
 qr_finder_roi_original #(.LEG_MAX_MODULES(32),.WEIGHTED_SCORE(1),.FUSION_ENABLE(1)) original(
   .aclk(clk),.aresetn(rst),.frame_start(fs),.frame_end(fe),.frame_seq(32'd42),.epoch(32'd7),.config_seq(32'd1),
   .width(16'd1280),.height(16'd720),.threshold(8'd100),.threshold_source(32'd0),.frame_error(1'b0),.threshold_metadata(128'd0),
   .cand_valid(valid),.cand_ready(),.cand_x(x),.cand_y(y),.cand_module_q8(m),.cand_direction(direction),.cand_error(e),.cand_branch(branch),
   .ro_address(addr),.ro_data(data[5]),.busy());
 initial begin
  if(!$value$plusargs("input=%s",input_path)||!$value$plusargs("output=%s",output_path)||!$value$plusargs("count=%d",count))$fatal(1,"args");
  if(count>32768)$fatal(1,"input too large");
  $readmemh(input_path,events,0,count-1);
  for(j=0;j<6;j=j+1)begin outs[j]=$fopen($sformatf("%0s.%0d.words",output_path,j),"w");traces[j]=$fopen($sformatf("%0s.%0d.candidates",output_path,j),"w");end
  repeat(4)@(negedge clk);rst=1;@(negedge clk);fs=1;@(negedge clk);fs=0;
  for(k=0;k<count;k=k+1)begin
   @(negedge clk);valid=1;{branch,direction,e,m,y,x}=events[k];
  end
  @(negedge clk);valid=0;fe=1;@(negedge clk);fe=0;addr=16'hA000;#1;n=0;
  while((data[0][0]||data[1][0]||data[2][0]||data[3][0]||data[4][0]||data[5][0])&&n<2000000)begin @(negedge clk);n=n+1;end
  if(n>=2000000)$fatal(1,"publication timeout");
  for(k=0;k<496;k=k+1)begin addr=16'hA000+4*k;#1;for(j=0;j<6;j=j+1)$fwrite(outs[j],"%08x\n",data[j]);end
  for(k=0;k<64;k=k+1)begin addr=16'h0100+4*k;#1;for(j=0;j<6;j=j+1)$fwrite(outs[j],"%08x\n",data[j]);end
  for(j=0;j<6;j=j+1)begin $fclose(outs[j]);$fclose(traces[j]);end
  $display("SELECTION_REPLAY_PASS cycles=%0d",n);$finish;
 end
 initial begin #30000000;$fatal(1,"global timeout");end
endmodule
