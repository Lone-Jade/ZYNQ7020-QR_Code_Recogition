`timescale 1ns/1ps
module tb_r4_identity;
 reg c=0,p=0;always #5 c=~c;always #7 p=~p;
 reg resetn=0,push=0,start=0;reg [63:0] tag=0;
 wire [63:0] scan;wire [31:0] count;wire fault;
 r4_scan_identity dut(.aclk(c),.aresetn(resetn),.clear_toggle(1'b0),
 .push(push),.fetched_tag(tag),.pixel_clk(p),.pixel_resetn(resetn),
 .pixel_start(start),.scan_tag(scan),.unique_frames(count),.fault(fault));
 reg [63:0] expected[0:255];reg [63:0] previous=0;
 reg [31:0] previous_gray=0;
 integer written=0,read_count=0,unique_count=0,i;
 always @(negedge p)start=resetn&&!dut.empty&&($urandom_range(0,5)!=0);
 always @(posedge c)if(resetn&&push)begin
  if(dut.full)$fatal(1,"test producer violated capacity");
  expected[written]=tag;written=written+1;
 end
 always @(posedge p)if(resetn)begin
  if($countones(dut.count_gray^previous_gray)>1)$fatal(1,"unregistered/non-Gray count transition");
  previous_gray=dut.count_gray;
  if(start)begin
   if(read_count>=written)$fatal(1,"read before write");
   if(previous!=expected[read_count])unique_count=unique_count+1;
   previous=expected[read_count];read_count=read_count+1;
   #1;if(dut.shown_tag!==previous)$fatal(1,"prefetch/wrap/back-to-back tag mismatch");
  end
 end
 initial begin
  repeat(5)@(negedge c);resetn=1;
  for(i=0;i<200;i=i+1)begin
   @(negedge c);push=0;
   while(dut.full)@(negedge c);
   tag={32'h12345678,32'(i/3+1)};push=1;
   @(negedge c);push=0;
  end
  wait(read_count==200);repeat(12)@(negedge c);
  if(fault||count!=unique_count||scan!=previous)$fatal(1,"identity/count/ownership final mismatch");
  $display("R4_IDENTITY_PASS: 200 asynchronous tags, repeats, pointer wraps, consecutive reads, registered Gray count");$finish;
 end
 initial begin #200000;$fatal(1,"identity timeout");end
endmodule
