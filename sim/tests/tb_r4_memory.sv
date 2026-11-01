`timescale 1ns/1ps
module tb_r4_memory;
 reg clk=0,pc=0;always #5 clk=~clk;always #7 pc=~pc;
 reg rst=0,clear=0;reg [64:0] user=0;reg sv=0;
 reg [31:0] aw=0,ar=0;reg [7:0] len=1;reg av=0,ready=0,bv=0,arv=0;
 reg [1:0] resp=0;reg start=0;
 wire [63:0] t0,t1,t2,fetch,scan;wire [2:0] valid;wire[31:0] uf,cf,err,actual;wire fault,safe,push,idfault;
 r4_display_memory_guard g(.clk(clk),.resetn(rst),.clear(clear),.base0(32'h1000000),.base1(32'h1200000),.base2(32'h1400000),
 .stream_user(user),.stream_valid(sv),.stream_ready(1'b1),.awaddr(aw),.awlen(len),.awsize(3'd3),
 .awvalid(av),.awready(ready),.bresp(resp),.bvalid(bv),.bready(1'b1),.araddr(ar),.arvalid(arv),.arready(1'b1),
 .tag0(t0),.tag1(t1),.tag2(t2),.scan_tag(fetch),.read_tag_push(push),.valid_slots(valid),.unique_frames(uf),.completed_frames(cf),.errors(err),.fault(fault),.safe_video(safe));
 r4_scan_identity id(.aclk(clk),.aresetn(rst),.clear_toggle(clear),.push(push),.fetched_tag(fetch),
 .pixel_clk(pc),.pixel_resetn(rst),.pixel_start(start),.scan_tag(scan),.unique_frames(actual),.fault(idfault));
 task source(input[31:0] n);begin @(negedge clk);user={32'hdeadbeef,n,1'b1};sv=1;@(negedge clk);sv=0;end endtask
 task burst(input[31:0] addr);begin
  @(negedge clk);aw=addr;av=1;ready=0;repeat($urandom_range(1,5))@(negedge clk);ready=1;
  @(negedge clk);av=0;ready=0;repeat($urandom_range(1,8))@(negedge clk);bv=1;
  @(negedge clk);bv=0;
 end endtask
 task read_frame(input[31:0] addr);begin
  @(negedge clk);ar=addr;arv=1;@(negedge clk);arv=0;
  repeat(10)@(negedge pc);start=1;@(negedge pc);start=0;repeat(12)@(negedge clk);
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;
  source(1);burst(32'h1000000);
  if(valid!=0)$fatal(1,"partial frame published");
  burst(32'h1000000+1843200-16);
  if(valid!=1||cf!=1||t0!=64'hdeadbeef00000001)$fatal(1,"DDR commit or tag failed");
  read_frame(32'h1000000);read_frame(32'h1000000);
  if(actual!=1||scan!=t0||fault||idfault)$fatal(1,"repeat counted or fetch/scan tag mismatched");
  source(2);burst(32'h1200000);burst(32'h1200000+1843200-16);read_frame(32'h1200000);
  source(3);burst(32'h1400000);burst(32'h1400000+1843200-16);read_frame(32'h1400000);
  if(actual!=3||cf!=3||fault||idfault)$fatal(1,"normal triple-buffer identity mismatch");
  // Controlled read/write overlap must be detected and safe video withdrawn.
  source(4);burst(32'h1400000);
  if(!fault||safe||err!=1)$fatal(1,"overlap not rejected");
  $display("R4_MEMORY_PASS: DDR response commit, source tags per buffer, async scanout identity, repeats, overlap rejection");$finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
