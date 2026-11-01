`timescale 1ns/1ps
// Raster threshold interpolator. Centres: W/6,W/2,5W/6 (and H equivalents).
// setup latches frame configuration; ready rises within 32 clocks. Width must
// be >=64, height >=1. x/y identify the CURRENT raster pixel, starting at 0,0.
// Only pixel_advance advances weights. The current gray pixel has no added
// pipeline delay: threshold is combinational from registered row coefficients.
// Q24 reciprocal steps retain fractional centres; final output rounds nearest.
module qr_threshold_interp(
 input wire aclk,aresetn,setup,pixel_advance,
 input wire [71:0] thresholds,input wire [15:0] width,height,x,y,
 output wire [7:0] threshold,output reg ready
);
 reg [71:0] grid;
 reg [15:0] w,h;
 reg [1:0] state;
 reg [5:0] div_count;
 reg [25:0] numerator_x,numerator_y,quotient_x,quotient_y;
 reg [16:0] remainder_x,remainder_y;
 wire [17:0] trial_x={remainder_x,numerator_x[25]};
 wire [17:0] trial_y={remainder_y,numerator_y[25]};
 reg [25:0] step_x,step_y;
 // A legal raster position is strictly below 3*2^24; the prefetched row
 // is at most height, so all positions fit 26 bits (including height=1).
 reg [25:0] pos_x,pos_y,fetch_pos;
 reg [1:0] fetch_state;
 reg [23:0] row_node[0:2],next_node[0:2];
 reg signed [24:0] row_slope[0:1],next_slope[0:1];
 reg [16:0] ax,ay;
 reg ix,iy;
 wire [17:0] next_x_weights=weights(pos_x+step_x);
 reg [23:0] base;
 reg signed [24:0] slope;
 wire signed [42:0] product=slope*$signed({1'b0,ax});
 wire signed [42:0] horizontal=$signed({1'b0,base,16'd0})+product;
 wire signed [42:0] rounded=horizontal+43'sd2147483648;
 // Convex weights keep the interpolated value in [0,255]; nearest rounding
 // cannot overflow eight bits. No saturating carry chain is needed here.
 assign threshold = !ready ? grid[7:0] : rounded[39:32];
 integer i;
 // Position is 3*coordinate/dimension in Q24. All edge intervals clamp.
 function [17:0] weights;
 input [25:0] pos;
 reg [16:0] alpha;reg index;
 begin
  if(pos<=26'd8388608)begin index=0;alpha=0;end
  else if(pos>=26'd41943040)begin index=1;alpha=17'd65536;end
  else if(pos<26'd25165824)begin index=0;alpha=(pos-26'd8388608)>>8;end
  else begin index=1;alpha=(pos-26'd25165824)>>8;end
  weights={index,alpha};
 end endfunction
 function [23:0] vertical;
 input [7:0] a,b;input [16:0] alpha;
 reg signed [8:0] delta;
 reg signed [26:0] result;
 begin
  delta=$signed({1'b0,b})-$signed({1'b0,a});
  result=$signed({1'b0,a,16'd0})+delta*$signed({1'b0,alpha});
  vertical=result[23:0];
 end endfunction
 always @* begin
  {iy,ay}=weights(fetch_pos);
  base=row_node[ix];slope=row_slope[ix];
 end
 always @(posedge aclk)begin
  if(!aresetn)begin
   grid<=0;w<=64;h<=1;state<=0;ready<=0;fetch_state<=0;
   pos_x<=0;pos_y<=0;fetch_pos<=0;step_x<=0;step_y<=0;ix<=0;ax<=0;
   numerator_x<=0;numerator_y<=0;quotient_x<=0;quotient_y<=0;
   remainder_x<=0;remainder_y<=0;div_count<=0;
   for(i=0;i<3;i=i+1)begin row_node[i]<=0;next_node[i]<=0;end
   for(i=0;i<2;i=i+1)begin row_slope[i]<=0;next_slope[i]<=0;end
  end else if(setup)begin
   grid<=thresholds;w<=width<64?16'd64:width;h<=height==0?16'd1:height;
   ready<=0;state<=1;div_count<=25;fetch_state<=0;ix<=0;ax<=0;
   numerator_x<=26'd50331648;numerator_y<=26'd50331648;
   quotient_x<=0;quotient_y<=0;remainder_x<=0;remainder_y<=0;
  end else begin
   if(state==1)begin
    numerator_x<=numerator_x<<1;numerator_y<=numerator_y<<1;
    if(trial_x>=w)begin remainder_x<=trial_x-w;quotient_x<={quotient_x[24:0],1'b1};end
    else begin remainder_x<=trial_x;quotient_x<={quotient_x[24:0],1'b0};end
    if(trial_y>=h)begin remainder_y<=trial_y-h;quotient_y<={quotient_y[24:0],1'b1};end
    else begin remainder_y<=trial_y;quotient_y<={quotient_y[24:0],1'b0};end
    if(div_count==0)state<=2;else div_count<=div_count-1'b1;
   end else if(state==2)begin
    step_x<=quotient_x;step_y<=quotient_y;pos_x<=0;pos_y<=0;ix<=0;ax<=0;
    for(i=0;i<3;i=i+1)row_node[i]<={grid[8*i+:8],16'd0};
    for(i=0;i<2;i=i+1)row_slope[i]<=($signed({1'b0,grid[8*(i+1)+:8]})-$signed({1'b0,grid[8*i+:8]}))<<<16;
    fetch_pos<=quotient_y;fetch_state<=1;state<=3;
   end else if(state==3&&!ready&&fetch_state==0)ready<=1;
   // Precompute the following row while >=64 current pixels are consumed.
   // These stages may run during AXIS stalls; current coefficients never change.
   if(fetch_state==1)begin
    for(i=0;i<3;i=i+1)next_node[i]<=vertical(grid[8*(3*iy+i)+:8],grid[8*(3*iy+3+i)+:8],ay);
    fetch_state<=2;
   end else if(fetch_state==2)begin
    for(i=0;i<2;i=i+1)next_slope[i]<=$signed({1'b0,next_node[i+1]})-$signed({1'b0,next_node[i]});
    fetch_state<=0;
   end
   if(ready&&pixel_advance)begin
    if(x==w-1'b1)begin
     pos_x<=0;ix<=0;ax<=0;
     if(y==h-1'b1)begin ready<=0;state<=0;end
     else begin
      pos_y<=pos_y+step_y;
      for(i=0;i<3;i=i+1)row_node[i]<=next_node[i];
      for(i=0;i<2;i=i+1)row_slope[i]<=next_slope[i];
      fetch_pos<=pos_y+(step_y<<1);fetch_state<=1;
     end
    end else begin pos_x<=pos_x+step_x;{ix,ax}<=next_x_weights;end
   end
  end
 end
endmodule
