`timescale 1ns/1ps
// START is paired AW/W consumption; DONE is rising completion IRQ.
// Both boundaries share one clock; AXI/control and IRQ generation are included.
module qr_fitness_timing (
 (* X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *)
 (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 aclk CLK" *) input wire aclk,
 (* X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW" *)
 (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 aresetn RST" *) input wire aresetn,
 input wire tap_resetn,tap_awvalid,tap_awready,tap_wvalid,tap_wready,tap_irq,
 input wire [31:0] tap_awaddr,
 input wire [31:0] tap_wdata,
 input wire [3:0] tap_wstrb,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *) input wire [15:0] s_axi_awaddr,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *) input wire [2:0] s_axi_awprot,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *) input wire s_axi_awvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *) output wire s_axi_awready,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WDATA" *) input wire [31:0] s_axi_wdata,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *) input wire [3:0] s_axi_wstrb,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WVALID" *) input wire s_axi_wvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WREADY" *) output wire s_axi_wready,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BRESP" *) output wire [1:0] s_axi_bresp,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BVALID" *) output reg s_axi_bvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BREADY" *) input wire s_axi_bready,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *) input wire [15:0] s_axi_araddr,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *) input wire [2:0] s_axi_arprot,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *) input wire s_axi_arvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *) output wire s_axi_arready,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RDATA" *) output reg [31:0] s_axi_rdata,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RRESP" *) output wire [1:0] s_axi_rresp,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RVALID" *) output reg s_axi_rvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RREADY" *) input wire s_axi_rready
);
 // Read-only AXI-Lite transaction tap: never drives the observed bus.
 // HLS permits one write outstanding. Four-entry independent AW/W FIFOs
 // additionally tolerate reordered address/data arrivals without coupling them.
 reg [15:0] aq[0:3];reg [35:0] wq[0:3];
 reg [1:0] ar,aw,wr,ww;reg [2:0] ac,wc;
 wire pop=(ac!=0)&&(wc!=0);
 wire push_a=tap_awvalid&&tap_awready;
 wire push_w=tap_wvalid&&tap_wready;
 wire accept_a=push_a&&((ac<4)||pop);
 wire accept_w=push_w&&((wc<4)||pop);
 reg [31:0] op,epoch,frame,config_id,job,errors,ordinal,generation;
 reg [31:0] done_op,done_epoch,done_frame,done_config,done_job,done_ordinal;
 reg busy,irq_d;reg [63:0] tick,started,ended,cycles,last_start;
 function [31:0] merge;
  input [31:0] old_value,new_value;input [3:0] strb;
  integer n;begin merge=old_value;for(n=0;n<4;n=n+1)if(strb[n])merge[n*8+:8]=new_value[n*8+:8];end
 endfunction
 always @(posedge aclk)begin
  if(!aresetn)begin
   ar<=0;aw<=0;wr<=0;ww<=0;ac<=0;wc<=0;op<=0;epoch<=0;frame<=0;config_id<=0;job<=0;
   errors<=0;ordinal<=0;generation<=0;done_op<=0;done_epoch<=0;done_frame<=0;done_config<=0;done_job<=0;done_ordinal<=0;
   busy<=0;irq_d<=0;tick<=0;started<=0;ended<=0;cycles<=0;last_start<=0;
  end else begin
   tick<=tick+1;irq_d<=tap_irq;
   if(!tap_resetn)begin
    ar<=0;aw<=0;wr<=0;ww<=0;ac<=0;wc<=0;busy<=0;irq_d<=0;
    op<=0;epoch<=0;frame<=0;config_id<=0;job<=0;
   end else begin
    if(push_a&&!accept_a)errors[0]<=1;
    if(push_w&&!accept_w)errors[1]<=1;
    if(accept_a)begin aq[aw]<=tap_awaddr[15:0];aw<=aw+1;end
    if(accept_w)begin wq[ww]<={tap_wstrb,tap_wdata};ww<=ww+1;end
    case({accept_a,pop})2'b10:ac<=ac+1;2'b01:ac<=ac-1;default:ac<=ac;endcase
    case({accept_w,pop})2'b10:wc<=wc+1;2'b01:wc<=wc-1;default:wc<=wc;endcase
    if(pop)begin
     ar<=ar+1;wr<=wr+1;
     case(aq[ar])
      16'h001c:op<=merge(op,wq[wr][31:0],wq[wr][35:32]);
      16'h00a4:epoch<=merge(epoch,wq[wr][31:0],wq[wr][35:32]);
      16'h00ac:frame<=merge(frame,wq[wr][31:0],wq[wr][35:32]);
      16'h00b4:config_id<=merge(config_id,wq[wr][31:0],wq[wr][35:32]);
      16'h00bc:job<=merge(job,wq[wr][31:0],wq[wr][35:32]);
      // INVALIDATE is polled with the completion IRQ masked during recovery.
      // It has no HP reads and is outside LOAD/SCORE/GRID timing; waiting for
      // its nonexistent IRQ would poison the next real job's busy/error state.
      16'h0000:if(wq[wr][32]&&wq[wr][0]&&op!=2)begin
       if(busy)errors[2]<=1;
       busy<=1;started<=tick;ordinal<=ordinal+1;
      end
      default:begin end
     endcase
    end
    if(tap_irq&&!irq_d&&busy)begin
     busy<=0;ended<=tick;cycles<=tick-started;last_start<=started;
     done_op<=op;done_epoch<=epoch;done_frame<=frame;done_config<=config_id;done_job<=job;done_ordinal<=ordinal;
     generation<=generation+1;
    end
   end
  end
 end
 reg awheld,wheld;
 assign s_axi_awready=!awheld&&!s_axi_bvalid;
 assign s_axi_wready=!wheld&&!s_axi_bvalid;
 assign s_axi_bresp=2'b00;
 assign s_axi_arready=!s_axi_rvalid;
 assign s_axi_rresp=2'b00;
 always @(posedge aclk)begin
  if(!aresetn)begin awheld<=0;wheld<=0;s_axi_bvalid<=0;s_axi_rvalid<=0;s_axi_rdata<=0;end
  else begin
   if(s_axi_awvalid&&s_axi_awready)awheld<=1;
   if(s_axi_wvalid&&s_axi_wready)wheld<=1;
   if(awheld&&wheld)begin awheld<=0;wheld<=0;s_axi_bvalid<=1;end
   if(s_axi_bvalid&&s_axi_bready)s_axi_bvalid<=0;
   if(s_axi_rvalid&&s_axi_rready)s_axi_rvalid<=0;
   if(s_axi_arvalid&&s_axi_arready)begin
    s_axi_rvalid<=1;
    case(s_axi_araddr[15:2])
     0:s_axi_rdata<=32'hAC04F002;1:s_axi_rdata<=2;2:s_axi_rdata<=3;3:s_axi_rdata<=100000000;
     4:s_axi_rdata<=generation;5:s_axi_rdata<=done_op;6:s_axi_rdata<=done_job;7:s_axi_rdata<=done_epoch;
     8:s_axi_rdata<=done_frame;9:s_axi_rdata<=done_config;10:s_axi_rdata<=done_ordinal;11:s_axi_rdata<=errors;
     12:s_axi_rdata<=last_start[31:0];13:s_axi_rdata<=last_start[63:32];14:s_axi_rdata<=ended[31:0];15:s_axi_rdata<=ended[63:32];
     16:s_axi_rdata<=cycles[31:0];17:s_axi_rdata<=cycles[63:32];default:s_axi_rdata<=0;
    endcase
   end
  end
 end
 wire unused=^s_axi_awaddr^s_axi_awprot^s_axi_wdata^s_axi_wstrb^s_axi_arprot;
endmodule
