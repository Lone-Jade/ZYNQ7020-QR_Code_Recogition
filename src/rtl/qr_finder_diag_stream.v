`timescale 1ns/1ps
// Two diagonal families on the original pixel lattice. A step is sqrt(2)
// original pixels; module/error outputs deliberately remain in step units.
// Min/max gates use physical length. The fusion stage normalizes H and scale.
module qr_finder_diag_stream #(parameter MAX_WIDTH=1280)(
 input wire aclk,aresetn,pixel_valid,frame_start,black,
 input wire [15:0] x,y,width,min_module,max_module,tolerance_q8,
 output wire d0_valid,d1_valid,
 output wire [15:0] d0_x,d0_y,d0_module_q8,d0_error,
 output wire [15:0] d1_x,d1_y,d1_module_q8,d1_error
);
 qr_finder_diag_lane #(.MAX_WIDTH(MAX_WIDTH),.DX(1)) down_right(
  .aclk(aclk),.aresetn(aresetn),.pixel_valid(pixel_valid),.frame_start(frame_start),.black(black),
  .x(x),.y(y),.width(width),.min_module(min_module),.max_module(max_module),.tolerance_q8(tolerance_q8),
  .valid(d0_valid),.center_x(d0_x),.center_y(d0_y),.module_q8(d0_module_q8),.error_sum(d0_error));
 qr_finder_diag_lane #(.MAX_WIDTH(MAX_WIDTH),.DX(-1)) down_left(
  .aclk(aclk),.aresetn(aresetn),.pixel_valid(pixel_valid),.frame_start(frame_start),.black(black),
  .x(x),.y(y),.width(width),.min_module(min_module),.max_module(max_module),.tolerance_q8(tolerance_q8),
  .valid(d1_valid),.center_x(d1_x),.center_y(d1_y),.module_q8(d1_module_q8),.error_sum(d1_error));
endmodule

module qr_finder_diag_lane #(parameter MAX_WIDTH=1280,parameter DX=1)(
 input wire aclk,aresetn,pixel_valid,frame_start,black,
 input wire [15:0] x,y,width,min_module,max_module,tolerance_q8,
 output reg valid,output reg [15:0] center_x,center_y,module_q8,error_sum
);
 localparam AW=$clog2(MAX_WIDTH);
 (* ram_style="block" *) reg [84:0] row_even[0:MAX_WIDTH-1];
 (* ram_style="block" *) reg [84:0] row_odd[0:MAX_WIDTH-1];
 reg [84:0] even_q,odd_q;
 reg sv,sblack,sboundary;reg [15:0] sx,sy,swidth,smin,smax,stol;
 wire [84:0] previous=sy[0]?even_q:odd_q;
 wire edge_pixel=(DX==1)?(x==0):(x+16'd1>=width);
 wire [15:0] predecessor=(DX==1)?x-16'd1:x+16'd1;
 wire [15:0] length=previous[79:64];
 wire [15:0] ra=previous[63:48],rb=previous[47:32],rc=previous[31:16],rd=previous[15:0];
 reg [84:0] next_history;
 always @*begin
  if(sboundary)next_history={sblack,4'd0,16'd1,64'd0};
  else if(previous[84]==sblack)
   next_history={previous[84:80],(length==65535?length:length+16'd1),previous[63:0]};
  else next_history={sblack,previous[82:80],previous[84],16'd1,rb,rc,rd,length};
 end
 // Distinct previous/current row banks avoid in-place x-1 read-after-write.
 // Arrays and RAM output have no reset; the first row and each diagonal edge
 // initialize history lazily. Every update follows an accepted pixel only.
 // Each RAM has its own unreset registered read port. Selecting between
 // arrays inside one output register prevents BRAM inference in Vivado.
 always @(posedge aclk)begin
  if(pixel_valid&&x<MAX_WIDTH&&!edge_pixel)even_q<=row_even[predecessor[AW-1:0]];
  if(aresetn&&sv&&sx<MAX_WIDTH&&!sy[0])row_even[sx[AW-1:0]]<=next_history;
 end
 always @(posedge aclk)begin
  if(pixel_valid&&x<MAX_WIDTH&&!edge_pixel)odd_q<=row_odd[predecessor[AW-1:0]];
  if(aresetn&&sv&&sx<MAX_WIDTH&&sy[0])row_odd[sx[AW-1:0]]<=next_history;
 end
 always @(posedge aclk)begin
  if(!aresetn)begin sv<=0;sblack<=0;sboundary<=0;sx<=0;sy<=0;swidth<=0;smin<=0;smax<=0;stol<=0;end
  else begin
   sv<=pixel_valid;
   if(pixel_valid)begin
    sx<=x;sy<=y;swidth<=width;sblack<=black;sboundary<=edge_pixel||y==0||frame_start;
    smin<=min_module;smax<=max_module;stol<=tolerance_q8;
   end
  end
 end
 reg p0_valid,p1_valid,p2_valid,p2_range;
 reg [15:0] p0_run[0:4];reg [15:0] p0_x,p0_y,p0_min,p0_max,p0_tol;
 reg [31:0] p1_total,p1_run7[0:4],p1_min,p1_max;
 reg [15:0] p1_x,p1_y,p1_tol;
 reg [31:0] p2_error[0:4],p2_bound,p2_bound3;
 reg [15:0] p2_x,p2_y,p2_module;
 wire [16:0] back={1'b0,length}+{1'b0,rd}+{1'b0,(rc>>1)};
 wire [16:0] cx=(DX==1)?{1'b0,sx}-back:{1'b0,sx}+back;
 wire center_in_range=back<=sy && ((DX==1)?back<=sx:cx<{1'b0,swidth});
 wire [63:0] physical_total_q16={32'd0,p1_total}*64'd92682;
 wire [31:0] final_error=p2_error[0]+p2_error[1]+p2_error[2]+p2_error[3]+p2_error[4];
 function [31:0] difference;input [31:0] a,b;begin difference=a>b?a-b:b-a;end endfunction
 integer k;
 always @(posedge aclk)begin
  if(!aresetn)begin
   p0_valid<=0;p1_valid<=0;p2_valid<=0;p2_range<=0;valid<=0;
   center_x<=0;center_y<=0;module_q8<=0;error_sum<=0;
  end else begin
   p0_valid<=sv&&!sboundary&&(previous[84]!=sblack)&&previous[84]&&previous[83:80]==4'b1010&&center_in_range;
   p0_run[0]<=ra;p0_run[1]<=rb;p0_run[2]<=rc;p0_run[3]<=rd;p0_run[4]<=length;
   p0_x<=cx[15:0];p0_y<=sy-back;p0_min<=smin;p0_max<=smax;p0_tol<=stol;
   p1_valid<=p0_valid;p1_min<=32'd7*p0_min;p1_max<=32'd7*p0_max;p1_tol<=p0_tol;
   p1_x<=p0_x;p1_y<=p0_y;
   p1_total<=({16'd0,p0_run[0]}+{16'd0,p0_run[1]})+({16'd0,p0_run[2]}+{16'd0,p0_run[3]})+{16'd0,p0_run[4]};
   for(k=0;k<5;k=k+1)p1_run7[k]<=32'd7*p0_run[k];
   p2_valid<=p1_valid;
   p2_range<=physical_total_q16>={p1_min,16'd0}&&physical_total_q16<={p1_max,16'd0};
   p2_bound<=p1_total*p1_tol;p2_bound3<=32'd3*p1_total*p1_tol;
   p2_x<=p1_x;p2_y<=p1_y;p2_module<=(p1_total*32'd256+32'd3)/32'd7;
   for(k=0;k<5;k=k+1)p2_error[k]<=difference(p1_run7[k],k==2?32'd3*p1_total:p1_total);
   valid<=p2_valid&&p2_range&&
    p2_error[0]*32'd256<=p2_bound&&p2_error[1]*32'd256<=p2_bound&&
    p2_error[2]*32'd256<=p2_bound3&&p2_error[3]*32'd256<=p2_bound&&p2_error[4]*32'd256<=p2_bound;
   center_x<=p2_x;center_y<=p2_y;module_q8<=p2_module;
   error_sum<=final_error>65535?16'hffff:final_error[15:0];
  end
 end
endmodule
