`timescale 1ns/1ps
// One accepted pixel per clock; black=1. Histories advance only on pixel_valid.
// Candidate latency: four clocks after input acceptance (legacy: one clock).
// H/V share stage boundaries and remain independent, including simultaneous hits.
module qr_finder_stream #(parameter MAX_WIDTH=1280)(
 input wire aclk,aresetn,pixel_valid,frame_start,black,
 input wire [15:0] x,y,min_module,max_module,tolerance_q8,
 output reg h_valid,v_valid,
 output reg [15:0] h_x,h_y,h_module_q8,h_error,
 output reg [15:0] v_x,v_y,v_module_q8,v_error
);
 localparam ADDRESS_WIDTH=$clog2(MAX_WIDTH);
 reg hc;reg [15:0] hl,ha,hb,hc2,hd;reg [3:0] hcolors;
 (* ram_style="block" *) reg [84:0] columns[0:MAX_WIDTH-1];
 reg [84:0] vs;
 reg scan_valid,scan_start,scan_black;reg [15:0] sx,sy,smin,smax,stol;
 wire vcolor=vs[84];wire [3:0] vcolors=vs[83:80];
 wire [15:0] vl=vs[79:64],va=vs[63:48],vb=vs[47:32],vc=vs[31:16],vd=vs[15:0];
 wire column_we=aresetn&&scan_valid&&(sx<MAX_WIDTH);
 wire [ADDRESS_WIDTH-1:0] column_address=sx[ADDRESS_WIDTH-1:0];
 reg [84:0] column_data;
 always @* begin
  if(sy==0) column_data={scan_black,4'd0,16'd1,64'd0};
  else if(vcolor==scan_black) column_data={vcolor,vcolors,(vl==65535?vl:vl+16'd1),va,vb,vc,vd};
  else column_data={scan_black,vcolors[2:0],vcolor,16'd1,vb,vc,vd,vl};
 end
 // Dedicated simple-dual-port RAM process. Neither memory nor its read-output
 // register has a reset. The valid pipeline discards reads during reset and
 // each y=0 pixel lazily initializes its column, exactly as the legacy scanner.
 always @(posedge aclk) begin
  if(pixel_valid&&x<MAX_WIDTH) vs<=columns[x[ADDRESS_WIDTH-1:0]];
  if(column_we) columns[column_address]<=column_data;
 end
 always @(posedge aclk) begin
  if(!aresetn)begin scan_valid<=0;scan_start<=0;scan_black<=0;sx<=0;sy<=0;smin<=0;smax<=0;stol<=0;end
  else begin
   scan_valid<=pixel_valid;
   if(pixel_valid)begin
    scan_start<=frame_start;scan_black<=black;sx<=x;sy<=y;smin<=min_module;smax<=max_module;stol<=tolerance_q8;
   end
  end
 end
 always @(posedge aclk) begin
  if(!aresetn)begin hc<=0;hl<=0;ha<=0;hb<=0;hc2<=0;hd<=0;hcolors<=0;end
  else if(scan_valid)begin
   if(scan_start||sx==0)begin hc<=scan_black;hl<=1;ha<=0;hb<=0;hc2<=0;hd<=0;hcolors<=0;end
   else if(hc==scan_black)begin if(hl!=65535)hl<=hl+1'b1;end
   else begin ha<=hb;hb<=hc2;hc2<=hd;hd<=hl;hcolors<={hcolors[2:0],hc};hl<=1;hc<=scan_black;end
  end
 end
 // Stage 0 snapshots the five completed runs before histories are advanced.
 reg [1:0] p0_valid;
 reg [15:0] p0_run[0:9],p0_x[0:1],p0_y[0:1];
 reg [15:0] p0_min,p0_max,p0_tol;
 // Stage 1 balances the five-run total, and independently scales each run.
 reg [1:0] p1_valid;
 reg [31:0] p1_total[0:1],p1_run7[0:9],p1_min,p1_max;
 reg [15:0] p1_x[0:1],p1_y[0:1],p1_tol;
 // Stage 2 computes independent absolute errors and the tolerance product.
 // ALL operands below deliberately stay 32 bits: legacy multiplication,
 // error shifting, rounding and truncation are part of the source contract.
 reg [1:0] p2_valid,p2_range;
 reg [31:0] p2_error[0:9],p2_bound[0:1],p2_bound3[0:1];
 reg [15:0] p2_x[0:1],p2_y[0:1],p2_module[0:1];
 reg [31:0] scaled_total;
 integer i,d;
 function [31:0] difference;
 input [31:0] a,b;
 begin difference=(a>b)?a-b:b-a;end
 endfunction
 always @(posedge aclk)begin
  if(!aresetn)begin
   p0_valid<=0;p1_valid<=0;p2_valid<=0;p2_range<=0;h_valid<=0;v_valid<=0;
   h_x<=0;h_y<=0;h_module_q8<=0;h_error<=0;v_x<=0;v_y<=0;v_module_q8<=0;v_error<=0;
  end else begin
   p0_valid[0]<=scan_valid&&!scan_start&&(sx!=0)&&(hc!=scan_black)&&(hcolors==4'b1010)&&hc;
   p0_valid[1]<=scan_valid&&(sx<MAX_WIDTH)&&(sy!=0)&&(vcolor!=scan_black)&&(vcolors==4'b1010)&&vcolor;
   p0_run[0]<=ha;p0_run[1]<=hb;p0_run[2]<=hc2;p0_run[3]<=hd;p0_run[4]<=hl;
   p0_run[5]<=va;p0_run[6]<=vb;p0_run[7]<=vc;p0_run[8]<=vd;p0_run[9]<=vl;
   p0_x[0]<=sx-hl-hd-(hc2>>1);p0_y[0]<=sy;
   p0_x[1]<=sx;p0_y[1]<=sy-vl-vd-(vc>>1);
   p0_min<=smin;p0_max<=smax;p0_tol<=stol;
   p1_valid<=p0_valid;p1_min<=32'd7*p0_min;p1_max<=32'd7*p0_max;p1_tol<=p0_tol;
   for(i=0;i<10;i=i+1)p1_run7[i]<=32'd7*p0_run[i];
   for(d=0;d<2;d=d+1)begin
    p1_total[d]<=({16'd0,p0_run[5*d]}+{16'd0,p0_run[5*d+1]})+
                  ({16'd0,p0_run[5*d+2]}+{16'd0,p0_run[5*d+3]})+{16'd0,p0_run[5*d+4]};
    p1_x[d]<=p0_x[d];p1_y[d]<=p0_y[d];
    p2_range[d]<=(p1_total[d]>=p1_min)&&(p1_total[d]<=p1_max);
    p2_bound[d]<=p1_total[d]*p1_tol;
    p2_bound3[d]<=32'd3*p1_total[d]*p1_tol;
    p2_x[d]<=p1_x[d];p2_y[d]<=p1_y[d];
    p2_module[d]<=(p1_total[d]*32'd256+32'd3)/32'd7;
    for(i=0;i<5;i=i+1)begin
     if(i==2)p2_error[5*d+i]<=difference(p1_run7[5*d+i],32'd3*p1_total[d]);
     else p2_error[5*d+i]<=difference(p1_run7[5*d+i],p1_total[d]);
    end
   end
   p2_valid<=p1_valid;
   h_valid<=p2_valid[0]&&p2_range[0]&&
      (p2_error[0]*32'd256<=p2_bound[0])&&(p2_error[1]*32'd256<=p2_bound[0])&&
      (p2_error[2]*32'd256<=p2_bound3[0])&&(p2_error[3]*32'd256<=p2_bound[0])&&
      (p2_error[4]*32'd256<=p2_bound[0]);
   v_valid<=p2_valid[1]&&p2_range[1]&&
      (p2_error[5]*32'd256<=p2_bound[1])&&(p2_error[6]*32'd256<=p2_bound[1])&&
      (p2_error[7]*32'd256<=p2_bound3[1])&&(p2_error[8]*32'd256<=p2_bound[1])&&
      (p2_error[9]*32'd256<=p2_bound[1]);
   // Payload registers are independent of the pattern-comparison CE path.
   // Consumers use valid; no payload is meaningful on an invalid cycle.
   h_x<=p2_x[0];h_y<=p2_y[0];h_module_q8<=p2_module[0];
   h_error<=p2_error[0]+p2_error[1]+p2_error[2]+p2_error[3]+p2_error[4];
   v_x<=p2_x[1];v_y<=p2_y[1];v_module_q8<=p2_module[1];
   v_error<=p2_error[5]+p2_error[6]+p2_error[7]+p2_error[8]+p2_error[9];
  end
 end
endmodule
