`timescale 1ns/1ps
module tb_r4_osd;
 reg clk=0;always #5 clk=~clk;
 reg pc=0;always #7 pc=~pc;
 reg resetn=0;
 reg [15:0] rgb=0;reg [10:0] x=0;reg [9:0] y=0;reg de=1,hs=0,vs=0;
 wire [15:0] out;wire ode,oh,ov;
 reg [15:0] aw=0,ar=0;reg av=0,wv=0,br=0,arv=0,rr=1;
 reg [31:0] wd=0;reg [3:0] ws=15;
 wire ary,wry,bv,arr,rv;wire [1:0] bp,rp;wire [31:0] rd;
 r4_display_osd dut(.aclk(clk),.aresetn(resetn),.pixel_clk(pc),.pixel_resetn(resetn),
 .pixel_rgb(rgb),.pixel_x(x),.pixel_y(y),.pixel_de(de),.pixel_hs(hs),.pixel_vs(vs),
 .out_rgb(out),.out_de(ode),.out_hs(oh),.out_vs(ov),.capture_enable(),.source_epoch(),.clear_toggle(),
 .display_fault(1'b0),.cam_clk(pc),.cam_resetn(resetn),.base0(),.base1(),.base2(),
 .tag0(64'd0),.tag1(64'd0),.tag2(64'd0),.scan_tag(64'd0),.valid_slots(3'd0),
 .memory_fault(1'b0),.safe_video(1'b1),.memory_errors(32'd0),.committed_frames(32'd0),.source_frames(32'd0),.display_frames(32'd0),.display_drops(32'd0),.qr_drops(32'd0),.unique_frames(32'd0),
 .s_axi_awaddr(aw),.s_axi_awprot(3'd0),.s_axi_awvalid(av),.s_axi_awready(ary),
 .s_axi_wdata(wd),.s_axi_wstrb(ws),.s_axi_wvalid(wv),.s_axi_wready(wry),
 .s_axi_bresp(bp),.s_axi_bvalid(bv),.s_axi_bready(br),
 .s_axi_araddr(ar),.s_axi_arprot(3'd0),.s_axi_arvalid(arv),.s_axi_arready(arr),
 .s_axi_rdata(rd),.s_axi_rresp(rp),.s_axi_rvalid(rv),.s_axi_rready(rr));
 task write(input[15:0] addr,input[31:0] value,input[1:0] response);
 begin
  @(negedge clk);aw=addr;av=1;while(!ary)@(negedge clk);
  @(negedge clk);av=0;repeat(2)@(negedge clk);wd=value;wv=1;
  while(!wry)@(negedge clk);@(negedge clk);wv=0;
  wait(bv);if(bp!=response)$fatal(1,"AXI response %h %d",addr,bp);
  repeat(3)@(negedge clk);br=1;@(negedge clk);br=0;
 end endtask
 integer i,j;reg [15:0] exp0,exp1,exp2;reg [2:0] t0,t1,t2;
 reg scenecheck=0;reg check=0;reg [4:0] row;reg ink;
 always @(posedge pc)begin
  if(check)begin
   row=0;ink=0;
   if((y>=16&&y<30&&x>=880&&x<890)||
      (scenecheck&&y>=100&&y<114&&x>=206&&x<216))begin
    case(scenecheck&&x<880?(y-100)/2:(y-16)/2)0:row=14;1:row=17;2:row=17;3:row=31;4:row=17;5:row=17;6:row=17;endcase
    ink=row[4-((scenecheck&&x<880?x-206:x-880)/2)];
   end
   if(scenecheck&&x>=100&&x<200&&y>=100&&y<200&&(x<102||x>=198||y<102||y>=198))ink=1;
   if(scenecheck&&x>=700&&x<760&&y>=300&&y<360&&(x<702||x>=758||y<302||y>=358))ink=1;
   ink=ink&&de;
   exp2=exp1;exp1=exp0;exp0=ink?16'h07e0:rgb;
   t2=t1;t1=t0;t0={de,hs,vs};
   #1;if(out!==exp2||{ode,oh,ov}!==t2)$fatal(1,"transparency/alignment x=%d y=%d got=%h exp=%h",x,y,out,exp2);
  end
 end
 initial begin
  repeat(5)@(negedge clk);resetn=1;write(16'h10,7,0);
  for(i=0;i<32;i=i+1)write(16'h100+4*i,i==0?32'h20202041:32'h20202020,0);
  write(16'h20,1,0);
  write(16'h100,32'h42424242,2); // committed bank immutable
  repeat(10)@(negedge pc);if(dut.applied_seq!=0)$fatal(1,"changed outside vblank");
  x=0;y=720;@(negedge pc);y=0;
  repeat(12)@(negedge pc);if(dut.applied_seq!=1)$fatal(1,"no commit ack");
  // Prime all stages before checking and exercise glyph, spacers and non-OSD areas.
  x=0;y=0;rgb=16'h1234;repeat(5)@(negedge pc);
  exp0=rgb;exp1=rgb;exp2=rgb;t0=4;t1=4;t2=4;check=1;
  for(j=0;j<40;j=j+1)for(i=860;i<1280;i=i+1)begin
   @(negedge pc);x=i;y=j;rgb=$urandom;de=(i<1278);hs=i[1];vs=j[1];
  end
  @(negedge pc);check=0;
  // Commit all rectangles/labels together; slot 7 exercises the full bank.
  write(16'h200,32'h00640064,0);write(16'h204,32'h00c800c8,0);
  write(16'h208,32'h006400ce,0);write(16'h20c,1,0);
  write(16'h270,32'h012c02bc,0);write(16'h274,32'h016802f8,0);
  write(16'h278,32'h01900064,0);write(16'h27c,1,0);
  for(i=32;i<160;i=i+1)write(16'h1000+4*i,i==32?32'h20202041:32'h20202020,0);
  // HUD A is also copied, since a scene replaces every character bank.
  for(i=0;i<32;i=i+1)write(16'h1000+4*i,i==0?32'h20202041:32'h20202020,0);
  write(16'h20,2,0);write(16'h200,0,2);
  if(dut.active_desc[3]!==0)$fatal(1,"descriptor changed before vblank");
  repeat(10)@(negedge pc);x=0;y=720;@(negedge pc);y=0;
  repeat(12)@(negedge pc);if(dut.applied_seq!=2||dut.active_desc[31]!=1)$fatal(1,"scene commit failed");
  scenecheck=1;x=0;y=0;rgb=16'h1234;de=1;hs=0;vs=0;repeat(5)@(negedge pc);
  exp0=rgb;exp1=rgb;exp2=rgb;t0=4;t1=4;t2=4;check=1;
  for(j=90;j<215;j=j+1)for(i=90;i<610;i=i+1)begin
   @(negedge pc);x=i;y=j;rgb=$urandom;de=i[0];hs=i[1];vs=j[1];
  end
  for(j=295;j<365;j=j+1)for(i=690;i<770;i=i+1)begin
   @(negedge pc);x=i;y=j;rgb=$urandom;de=1;hs=i[1];vs=j[1];
  end
  @(negedge pc);check=0;
  // Watchdog removes all layers after three seconds without scene commits.
  for(i=0;i<181;i=i+1)begin x=0;y=720;@(negedge pc);y=0;@(negedge pc);end
  x=100;y=100;rgb=16'h1234;de=1;repeat(6)@(negedge pc);
  if(out!==16'h1234)$fatal(1,"stale scene did not expire");
  $display("R4_OSD_PASS transparent pixels, green glyphs, matched RGB/DE/HS/VS, AXI stalls, vblank atomic commit");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
