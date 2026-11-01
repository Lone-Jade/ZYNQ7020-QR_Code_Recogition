`timescale 1ns/1ps
// Exact Q16 Otsu, external synchronous histogram read. Lowest threshold wins ties.
module qr_otsu_grid_solver(
 input wire aclk,aresetn,start,
 input wire [19:0] total_count,
 input wire [27:0] gray_sum,
 output wire bin_read,
 output reg [7:0] bin_index,
 input wire [19:0] bin_count,
 output reg done,valid,
 output reg [7:0] threshold
);
 localparam IDLE=0,READ_BIN=1,ACCUM=2,PRODUCTS=3,DELTA=4,SQUARE=5,MULTIPLY=6,DIVIDE=7,SCORE=8,FINISH=9;
 reg [3:0] state;
 reg [19:0] total,wback;reg [27:0] total_sum,sumback;
 reg [127:0] numerator,quotient,best_score;
 reg [64:0] remainder;reg [63:0] denominator,prod_a,prod_b;
 reg [47:0] delta_abs,square_multiplier;
 reg [95:0] square_multiplicand,square_product;
 reg [5:0] square_count;reg [7:0] best_threshold,divide_count;
 wire [19:0] next_weight=wback+bin_count;
 wire [27:0] next_sum=sumback+bin_count*bin_index;
 wire [64:0] shifted_rem={remainder[63:0],numerator[127]};
 wire [19:0] foreground_weight=total-wback;
 wire [95:0] square_next=square_product+(square_multiplier[0]?square_multiplicand:96'd0);
 assign bin_read=state==READ_BIN;
 always @(posedge aclk)begin
  if(!aresetn)begin
   state<=IDLE;done<=0;valid<=0;threshold<=0;bin_index<=0;total<=0;total_sum<=0;wback<=0;sumback<=0;
   numerator<=0;quotient<=0;best_score<=0;remainder<=0;denominator<=0;prod_a<=0;prod_b<=0;
   delta_abs<=0;square_multiplier<=0;square_multiplicand<=0;square_product<=0;square_count<=0;
   best_threshold<=0;divide_count<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(start)begin total<=total_count;total_sum<=gray_sum;bin_index<=0;wback<=0;sumback<=0;best_score<=0;best_threshold<=0;state<=READ_BIN;end
    READ_BIN:state<=ACCUM;
    ACCUM:begin
     wback<=next_weight;sumback<=next_sum;
     if(next_weight!=0&&next_weight<total)state<=PRODUCTS;
     else if(bin_index==255)state<=FINISH;
     else begin bin_index<=bin_index+1'b1;state<=READ_BIN;end
    end
    PRODUCTS:begin prod_a<=total_sum*{44'd0,wback};prod_b<=sumback*{44'd0,total};denominator<={44'd0,wback}*{44'd0,foreground_weight};state<=DELTA;end
    DELTA:begin delta_abs<=(prod_a[47:0]>=prod_b[47:0])?(prod_a[47:0]-prod_b[47:0]):(prod_b[47:0]-prod_a[47:0]);state<=SQUARE;end
    SQUARE:begin square_multiplier<=delta_abs;square_multiplicand<={48'd0,delta_abs};square_product<=0;square_count<=0;state<=MULTIPLY;end
    MULTIPLY:begin
     square_product<=square_next;square_multiplier<=square_multiplier>>1;square_multiplicand<=square_multiplicand<<1;
     if(square_count==47)begin numerator<={16'd0,square_next,16'd0};quotient<=0;remainder<=0;divide_count<=0;state<=DIVIDE;end
     else square_count<=square_count+1'b1;
    end
    DIVIDE:begin
     numerator<={numerator[126:0],1'b0};
     if(shifted_rem>={1'b0,denominator})begin remainder<=shifted_rem-{1'b0,denominator};quotient<={quotient[126:0],1'b1};end
     else begin remainder<=shifted_rem;quotient<={quotient[126:0],1'b0};end
     if(divide_count==127)state<=SCORE;else divide_count<=divide_count+1'b1;
    end
    SCORE:begin
     if(quotient>best_score)begin best_score<=quotient;best_threshold<=bin_index;end
     if(bin_index==255)state<=FINISH;else begin bin_index<=bin_index+1'b1;state<=READ_BIN;end
    end
    FINISH:begin done<=1;valid<=best_score!=0;threshold<=best_threshold;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule

// Three row regions share one arithmetic solver and two 768-bin SDP RAMs.
module qr_otsu_grid_lane #(parameter integer REGIONS=3)(
 input wire aclk,aresetn,cap_start,cap_accept,cap_bank,
 input wire [1:0] cap_row,
 input wire [7:0] gray,
 input wire work_start,work_bank,clear_all,clear_work,
 input wire [9:0] clear_address,
 output reg done,
 output reg [23:0] thresholds,
 output reg [2:0] mask,
 output wire pending
);
 (* ram_style="block" *) reg [19:0] hist0[0:REGIONS*256-1],hist1[0:REGIONS*256-1];
 reg [19:0] rd0,rd1;
 reg cap_pending,cb;reg [9:0] ca;
 reg last_valid,last_bank;reg [9:0] last_address;reg [19:0] last_data;
 reg [19:0] counts0[0:REGIONS-1],counts1[0:REGIONS-1];
 reg [27:0] sums0[0:REGIONS-1],sums1[0:REGIONS-1];
 reg [1:0] row;
 reg running,solver_start;
 wire solver_read,solver_done,solver_valid;wire [7:0] solver_bin,solver_threshold;
 wire [9:0] solver_address={row,solver_bin};
 wire [19:0] raw=cb?rd1:rd0;
 wire [19:0] base=(last_valid&&last_bank==cb&&last_address==ca)?last_data:raw;
 wire [19:0] increment=base+20'd1;
 wire clear0=(clear_all||(clear_work&&!work_bank))&&(clear_address<REGIONS*256);
 wire clear1=(clear_all||(clear_work&&work_bank))&&(clear_address<REGIONS*256);
 wire we0=clear0||(cap_pending&&!cb),we1=clear1||(cap_pending&&cb);
 wire re0=(cap_accept&&!cap_bank)||(solver_read&&!work_bank);
 wire re1=(cap_accept&&cap_bank)||(solver_read&&work_bank);
 wire [9:0] ra0=(cap_accept&&!cap_bank)?{cap_row,gray}:solver_address;
 wire [9:0] ra1=(cap_accept&&cap_bank)?{cap_row,gray}:solver_address;
 assign pending=cap_pending;
 always @(posedge aclk)begin
  if(we0)hist0[clear0?clear_address:ca]<=clear0?20'd0:increment;
  if(re0)rd0<=hist0[ra0];
 end
 always @(posedge aclk)begin
  if(we1)hist1[clear1?clear_address:ca]<=clear1?20'd0:increment;
  if(re1)rd1<=hist1[ra1];
 end
 qr_otsu_grid_solver solver(.aclk(aclk),.aresetn(aresetn),.start(solver_start),
  .total_count(work_bank?counts1[row]:counts0[row]),.gray_sum(work_bank?sums1[row]:sums0[row]),
  .bin_read(solver_read),.bin_index(solver_bin),.bin_count(work_bank?rd1:rd0),
  .done(solver_done),.valid(solver_valid),.threshold(solver_threshold));
 integer i;
 always @(posedge aclk)begin
  if(!aresetn)begin
   cap_pending<=0;cb<=0;ca<=0;last_valid<=0;last_bank<=0;last_address<=0;last_data<=0;
   row<=0;running<=0;solver_start<=0;done<=0;thresholds<=0;mask<=0;
   for(i=0;i<REGIONS;i=i+1)begin counts0[i]<=0;counts1[i]<=0;sums0[i]<=0;sums1[i]<=0;end
  end else begin
   cap_pending<=cap_accept;last_valid<=cap_pending;solver_start<=0;done<=0;
   if(cap_accept)begin cb<=cap_bank;ca<={cap_row,gray};end
   if(cap_pending)begin last_bank<=cb;last_address<=ca;last_data<=increment;end
   if(cap_start)for(i=0;i<REGIONS;i=i+1)begin
    if(cap_bank)begin counts1[i]<=0;sums1[i]<=0;end else begin counts0[i]<=0;sums0[i]<=0;end
   end
   if(cap_accept)begin
    if(cap_bank)begin counts1[cap_row]<=cap_start?20'd1:counts1[cap_row]+1'b1;sums1[cap_row]<=cap_start?{20'd0,gray}:sums1[cap_row]+gray;end
    else begin counts0[cap_row]<=cap_start?20'd1:counts0[cap_row]+1'b1;sums0[cap_row]<=cap_start?{20'd0,gray}:sums0[cap_row]+gray;end
   end
   if(work_start)begin row<=0;running<=1;mask<=0;thresholds<=0;solver_start<=1;end
   if(running&&solver_done)begin
    thresholds[row*8+:8]<=solver_threshold;mask[row]<=solver_valid;
    if(row==REGIONS-1)begin running<=0;done<=1;end else begin row<=row+1'b1;solver_start<=1;end
   end
  end
 end
endmodule
