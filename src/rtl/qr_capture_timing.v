`timescale 1ns/1ps
// Passive event observation. Every event crosses as a toggle; timestamps and
// counters are recorded in one 100 MHz domain, never in the video data path.
module qr_capture_timing (
 (* X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *)
 (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 aclk CLK" *) input wire aclk,
 (* X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW" *)
 (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 aresetn RST" *) input wire aresetn,
 input wire cam_clk,cam_resetn,cam_vsync,source_sof,accepted_sof,eof_toggle,arm,
 input wire [1:0] gate_state,
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
 reg vsync_d,eof_d,arm_d;reg [5:0] toggles;
 always @(posedge cam_clk or negedge cam_resetn)begin
  if(!cam_resetn)begin vsync_d<=0;eof_d<=0;arm_d<=0;toggles<=0;end
  else begin
   vsync_d<=cam_vsync;eof_d<=eof_toggle;arm_d<=arm;
   if(cam_vsync&&!vsync_d)toggles[0]<=~toggles[0];
   if(source_sof)toggles[1]<=~toggles[1];
   if(accepted_sof)toggles[2]<=~toggles[2];
   if(eof_toggle!=eof_d)toggles[3]<=~toggles[3];
   if(arm&&!arm_d)toggles[4]<=~toggles[4];
   if(!arm&&arm_d)toggles[5]<=~toggles[5];
  end
 end
 (* ASYNC_REG="TRUE" *) reg [5:0] sync0,sync1;
 (* ASYNC_REG="TRUE" *) reg [1:0] state0,state1;
 reg [5:0] seen;wire [5:0] event_bits=sync1^seen;
 reg [63:0] tick,stamp[0:5],previous_raw,older_raw,previous_gate;
 reg [31:0] count[0:5],generation,raw_at_gate;
 integer i;
 always @(posedge aclk)begin
  if(!aresetn)begin
   sync0<=0;sync1<=0;seen<=0;state0<=0;state1<=0;tick<=0;generation<=0;
   previous_raw<=0;older_raw<=0;previous_gate<=0;raw_at_gate<=0;
   for(i=0;i<6;i=i+1)begin stamp[i]<=0;count[i]<=0;end
  end else begin
   sync0<=toggles;sync1<=sync0;seen<=sync1;state0<=gate_state;state1<=state0;tick<=tick+1;
   if(|event_bits)generation<=generation+1;
   for(i=0;i<6;i=i+1)if(event_bits[i])begin stamp[i]<=tick;count[i]<=count[i]+1;end
   if(event_bits[0])begin older_raw<=previous_raw;previous_raw<=stamp[0];end
   if(event_bits[2])begin previous_gate<=stamp[2];raw_at_gate<=count[0]+event_bits[0];end
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
     0:s_axi_rdata<=32'hAC040001;1:s_axi_rdata<=1;2:s_axi_rdata<=generation;3:s_axi_rdata<=100000000;
     4:s_axi_rdata<=count[0];5:s_axi_rdata<=count[1];6:s_axi_rdata<=count[2];7:s_axi_rdata<=count[3];
     8:s_axi_rdata<=stamp[0][31:0];9:s_axi_rdata<=stamp[0][63:32];
     10:s_axi_rdata<=stamp[1][31:0];11:s_axi_rdata<=stamp[1][63:32];
     12:s_axi_rdata<=stamp[2][31:0];13:s_axi_rdata<=stamp[2][63:32];
     14:s_axi_rdata<=stamp[3][31:0];15:s_axi_rdata<=stamp[3][63:32];
     16:s_axi_rdata<=stamp[4][31:0];17:s_axi_rdata<=stamp[4][63:32];
     18:s_axi_rdata<=stamp[5][31:0];19:s_axi_rdata<=stamp[5][63:32];
     20:s_axi_rdata<={30'd0,state1};21:s_axi_rdata<=raw_at_gate;
     22:s_axi_rdata<=previous_raw[31:0];23:s_axi_rdata<=previous_raw[63:32];
     24:s_axi_rdata<=older_raw[31:0];25:s_axi_rdata<=older_raw[63:32];
     26:s_axi_rdata<=previous_gate[31:0];27:s_axi_rdata<=previous_gate[63:32];
     28:s_axi_rdata<=count[4];29:s_axi_rdata<=count[5];
     default:s_axi_rdata<=0;
    endcase
   end
  end
 end
 wire unused=^s_axi_awaddr^s_axi_awprot^s_axi_wdata^s_axi_wstrb^s_axi_arprot;
endmodule
