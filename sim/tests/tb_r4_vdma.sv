`timescale 1ns/1ps
// Uses the actual generated AMD AXI VDMA v6.3 core, not a behavioral scheduler.
module tb_r4_vdma;
 reg c=0,p=0;always #5 c=~c;always #6.734 p=~p;
 reg rst=0;
 reg [8:0] ca=0,ra=0;reg cav=0,cwv=0,crv=0;reg [31:0] cd=0;
 wire car,cwr,cbv,crar,crvalid;wire[31:0] crdata;wire[1:0] cbresp,crresp;
 reg [15:0] sd=0;reg sv=0,su=0,sl=0;wire sr;
 wire [15:0] od;wire ov,ou,ol;wire[1:0] ok;reg ready=1;
 wire [31:0] wa,ar;wire[7:0] wl,al;wire [2:0] wz,az;
 wire wav,wv,wlast,br,arv,rready;wire [63:0] wd;wire [7:0] ws;
 reg war=0,wr=0,bv=0,arr=0,rv=0,rl=0;reg [63:0] rdata=0;
 wire wi,ri;wire[5:0] wp,rp;
 system_display_vdma_0 dut(
 .s_axi_lite_aclk(c),.m_axi_mm2s_aclk(c),.m_axis_mm2s_aclk(p),.m_axi_s2mm_aclk(c),.s_axis_s2mm_aclk(c),.axi_resetn(rst),
 .s_axi_lite_awvalid(cav),.s_axi_lite_awready(car),.s_axi_lite_awaddr(ca),.s_axi_lite_wvalid(cwv),.s_axi_lite_wready(cwr),.s_axi_lite_wdata(cd),
 .s_axi_lite_bresp(cbresp),.s_axi_lite_bvalid(cbv),.s_axi_lite_bready(1'b1),
 .s_axi_lite_arvalid(crv),.s_axi_lite_arready(crar),.s_axi_lite_araddr(ra),.s_axi_lite_rvalid(crvalid),.s_axi_lite_rready(1'b1),.s_axi_lite_rdata(crdata),.s_axi_lite_rresp(crresp),
 .mm2s_frame_ptr_out(rp),.s2mm_frame_ptr_out(wp),
 .m_axi_mm2s_araddr(ar),.m_axi_mm2s_arlen(al),.m_axi_mm2s_arsize(az),.m_axi_mm2s_arvalid(arv),.m_axi_mm2s_arready(arr),
 .m_axi_mm2s_rdata(rdata),.m_axi_mm2s_rresp(2'b0),.m_axi_mm2s_rlast(rl),.m_axi_mm2s_rvalid(rv),.m_axi_mm2s_rready(rready),
 .m_axis_mm2s_tdata(od),.m_axis_mm2s_tkeep(ok),.m_axis_mm2s_tuser(ou),.m_axis_mm2s_tvalid(ov),.m_axis_mm2s_tready(ready),.m_axis_mm2s_tlast(ol),
 .m_axi_s2mm_awaddr(wa),.m_axi_s2mm_awlen(wl),.m_axi_s2mm_awsize(wz),.m_axi_s2mm_awvalid(wav),.m_axi_s2mm_awready(war),
 .m_axi_s2mm_wdata(wd),.m_axi_s2mm_wstrb(ws),.m_axi_s2mm_wlast(wlast),.m_axi_s2mm_wvalid(wv),.m_axi_s2mm_wready(wr),
 .m_axi_s2mm_bresp(2'b0),.m_axi_s2mm_bvalid(bv),.m_axi_s2mm_bready(br),
 .s_axis_s2mm_tdata(sd),.s_axis_s2mm_tkeep(2'b11),.s_axis_s2mm_tuser(su),.s_axis_s2mm_tvalid(sv),.s_axis_s2mm_tready(sr),.s_axis_s2mm_tlast(sl),
 .mm2s_introut(ri),.s2mm_introut(wi));
 reg [63:0] mem[0:2047];reg wactive=0,ractive=0;
 integer wiaddr,riaddr,wb,rb,rn,wn,i;
 always @(negedge c)begin
  war=rst&&!wactive&&!bv&&$urandom_range(0,3)!=0;
  wr=rst&&wactive&&$urandom_range(0,3)!=0;
  arr=rst&&!ractive&&!rv&&$urandom_range(0,3)!=0;
 end
 always @(posedge c)if(rst)begin
  if(bv&&br)bv<=0;
  if(wav&&war)begin wactive<=1;wiaddr=wa>>3;wn=wl;wb=0;if(wz!=3)$fatal(1,"write width");end
  if(wv&&wr)begin
   
   for(i=0;i<8;i=i+1)if(ws[i])mem[wiaddr+wb][i*8+:8]=wd[i*8+:8];
   if(wlast!=(wb==wn))$fatal(1,"DDR write burst mismatch");
   if(wlast)begin wactive<=0;bv<=1;end else wb=wb+1;
  end
  if(arv&&arr)begin ractive<=1;riaddr=ar>>3;rn=al;rb=0;if(az!=3)$fatal(1,"read width");end
  if(rv&&rready)begin rv<=0;if(rl)ractive<=0;else rb=rb+1;end
  if(ractive&&!rv&&$urandom_range(0,3)!=0)begin rdata<=mem[riaddr+rb];rl<=rb==rn;rv<=1;end
 end
 task write_reg(input[8:0] addr,input[31:0] value);begin
  @(negedge c);ca=addr;cd=value;cav=1;cwv=1;
  fork
   begin wait(car);@(negedge c);cav=0;end
   begin wait(cwr);@(negedge c);cwv=0;end
  join
  wait(cbv);if(cbresp!=0)$fatal(1,"VDMA AXI response");@(negedge c);
 end endtask
 task read_reg(input[8:0] addr,output[31:0] value);begin
  @(negedge c);ra=addr;crv=1;wait(crar);@(negedge c);crv=0;wait(crvalid);value=crdata;@(negedge c);
 end endtask
 task send_frame(input[15:0] value,input integer count);integer j;begin
  for(j=0;j<count;j=j+1)begin
   @(negedge c);sd=value;su=j==0;sl=j%8==7;sv=1;
   do @(posedge c);while(!sr);
   @(negedge c);sv=0;su=0;sl=0;repeat(3)@(negedge c);
  end
  repeat(60)@(negedge c);
 end endtask
 integer pixels=0,frames=0,unique_count=0,last_value=0,frame_value=0,stall=0;
 always @(negedge p)begin
  if(stall>0)begin ready=0;stall=stall-1;end
  else ready=$urandom_range(0,5)!=0;
 end
 always @(posedge p)if(rst&&ov&&ready)begin
  if(ou)begin
   
   if(pixels!=0)$fatal(1,"partial frame at HDMI");
   frame_value=od;
   if(frame_value<1||frame_value>20||frame_value<last_value)$fatal(1,"uninitialized/regressing display %d",od);
   if(frame_value!=last_value)unique_count=unique_count+1;
   last_value=frame_value;
  end
  if(od!=frame_value||ok!=3||ol!=(pixels%8==7))$fatal(1,"torn/mixed frame %d at pixel %d",od,pixels);
  pixels=pixels+1;
  if(pixels==32)begin pixels=0;frames=frames+1;if(frames==8)stall=400;end
 end
 reg [31:0] status;integer n;
 initial begin
  for(i=0;i<2048;i=i+1)mem[i]=64'hbad0bad0bad0bad0;
  repeat(20)@(negedge c);rst=1;repeat(20)@(negedge c);
  write_reg('h30,4);repeat(50)@(negedge c);
  write_reg('hac,'h1000);write_reg('hb0,'h2000);write_reg('hb4,'h3000);
  write_reg('ha8,16);write_reg('ha4,16);write_reg('h30,'h1508b);write_reg('ha0,4);repeat(200)@(negedge c);
  read_reg('h34,status);if(status&1)$fatal(1,"S2MM not RUN before source admission");
  fork
   begin for(n=1;n<=20;n=n+1)send_frame(n,32);end
   begin
    wait(wi);read_reg('h34,status);write_reg('h5c,'h1000);write_reg('h60,'h2000);write_reg('h64,'h3000);
    write_reg('h58,16);write_reg('h54,16);write_reg('h00,'h1508b);write_reg('h50,4);
   end
  join
  repeat(1500)@(negedge c);
  read_reg('h34,status);if(status&'h8ff0)$fatal(1,"normal write DMA error %h",status);
  read_reg('h04,status);if(status&'h8ff0)$fatal(1,"normal read DMA error %h",status);
  if(unique_count<10||frames<20)$fatal(1,"not enough independent full/repeated frames %d %d",unique_count,frames);
  // Truncated last source frame never completes its store. No later SOF is
  // admitted (same sticky-fault policy as the R4 display fork).
  send_frame(21,16);repeat(1500)@(negedge c);
  if(last_value>20)$fatal(1,"partial source frame published");
  $display("R4_VDMA_PASS actual vendor dynamic Genlock, randomized DDR/stream stalls, held reader, complete/repeated frames: %d/%d",unique_count,frames);
  $finish;
 end
 initial begin #1000000;$fatal(1,"VDMA test timeout");end
endmodule
