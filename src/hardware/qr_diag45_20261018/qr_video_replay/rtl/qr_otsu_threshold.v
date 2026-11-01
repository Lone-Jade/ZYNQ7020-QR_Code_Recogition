`timescale 1ns/1ps
// Two SDP block RAM histograms. Capture has an exact newest-write bypass.
// All accepted samples commit before a bank is processed or cleared.
module qr_otsu_threshold(
 input wire aclk,aresetn,frame_start,frame_end,frame_error,pixel_valid,stat_selected,
 input wire [7:0] gray,
 input wire [31:0] frame_seq,config_seq,
 output reg result_valid,
 output reg [7:0] result_threshold,
 output reg [31:0] result_frame,result_config
);
 (* ram_style="block" *) reg [19:0] hist0[0:255],hist1[0:255];
 reg [19:0] rd_data0,rd_data1;
 reg capture_bank,process_bank,available0,available1,capture_valid;
 reg ready0,ready1;
 reg [19:0] count0,count1;reg [27:0] sum0,sum1;
 reg [31:0] capture_config,capture_seq,work_config,work_frame;
 reg [31:0] seq0,seq1,cfg0,cfg1;reg err0,err1,work_error;
 reg [7:0] clear_index,bin_index;
 reg [19:0] total,wback;reg [27:0] total_sum,sumback;
 reg [127:0] numerator,quotient,best_score;
 reg [64:0] remainder;
 reg [63:0] denominator,prod_a,prod_b;
 reg [47:0] delta_abs,square_multiplier;
 reg [95:0] square_multiplicand,square_product;
 reg [5:0] square_count;
 reg [7:0] best_threshold,divide_count;
 reg [3:0] state;
 localparam CLEAR_ALL=0,IDLE=1,DRAIN=2,READ_BIN=3,ACCUM=4,
  PRODUCTS=5,DELTA=6,SQUARE=7,DIVIDE=8,SCORE=9,FINISH=10,CLEAR_WORK=11,MULTIPLY=12;
 // Capture tags align with synchronous RAM outputs. The newest committed
 // value bypasses READ_FIRST collisions, including arbitrarily long repeats.
 reg cap_pending,cap_bank;reg [7:0] cap_address;
 reg last_write_valid,last_write_bank;reg [7:0] last_write_address;reg [19:0] last_write_data;
 wire cap_accept=pixel_valid&&stat_selected&&
  (frame_start?(capture_bank?available1:available0):capture_valid);
 wire [19:0] cap_raw=cap_bank?rd_data1:rd_data0;
 wire [19:0] cap_base=(last_write_valid&&last_write_bank==cap_bank&&last_write_address==cap_address)?last_write_data:cap_raw;
 wire [19:0] cap_increment=cap_base+20'd1;
 wire clear_all=state==CLEAR_ALL;
 wire clear_zero=clear_all||(state==CLEAR_WORK&&!process_bank);
 wire clear_one=clear_all||(state==CLEAR_WORK&&process_bank);
 wire we0=clear_zero||(cap_pending&&!cap_bank);
 wire we1=clear_one||(cap_pending&&cap_bank);
 wire [7:0] wa0=clear_zero?clear_index:cap_address;
 wire [7:0] wa1=clear_one?clear_index:cap_address;
 wire [19:0] wd0=clear_zero?20'd0:cap_increment;
 wire [19:0] wd1=clear_one?20'd0:cap_increment;
 wire re0=(cap_accept&&!capture_bank)||(state==READ_BIN&&!process_bank);
 wire re1=(cap_accept&&capture_bank)||(state==READ_BIN&&process_bank);
 wire [7:0] ra0=(cap_accept&&!capture_bank)?gray:bin_index;
 wire [7:0] ra1=(cap_accept&&capture_bank)?gray:bin_index;
 // One write port and one synchronous read port per physical bank.
 // Memory reset is a 256-cycle clear, not a reset loop on the array.
 always @(posedge aclk)begin
  if(we0)hist0[wa0]<=wd0;
  if(re0)rd_data0<=hist0[ra0];
 end
 always @(posedge aclk)begin
  if(we1)hist1[wa1]<=wd1;
  if(re1)rd_data1<=hist1[ra1];
 end
 wire [19:0] bin_count=process_bank?rd_data1:rd_data0;
 wire [19:0] next_weight=wback+bin_count;
 wire [27:0] next_sum=sumback+bin_count*bin_index;
 wire [64:0] shifted_rem={remainder[63:0],numerator[127]};
 wire [19:0] foreground_weight=total-wback;
 wire [95:0] square_next=square_product+(square_multiplier[0]?square_multiplicand:96'd0);
 always @(posedge aclk)begin
  if(!aresetn)begin
   state<=CLEAR_ALL;clear_index<=0;available0<=0;available1<=0;capture_valid<=0;capture_bank<=0;process_bank<=0;
   ready0<=0;ready1<=0;count0<=0;count1<=0;sum0<=0;sum1<=0;
   cap_pending<=0;cap_bank<=0;cap_address<=0;last_write_valid<=0;last_write_bank<=0;last_write_address<=0;last_write_data<=0;
   result_valid<=0;result_threshold<=200;result_frame<=0;result_config<=0;
   capture_config<=0;capture_seq<=0;work_config<=0;work_frame<=0;work_error<=0;
   seq0<=0;seq1<=0;cfg0<=0;cfg1<=0;err0<=0;err1<=0;
   bin_index<=0;total<=0;total_sum<=0;wback<=0;sumback<=0;
   numerator<=0;quotient<=0;remainder<=0;best_score<=0;denominator<=0;best_threshold<=0;divide_count<=0;
   prod_a<=0;prod_b<=0;delta_abs<=0;square_multiplier<=0;square_multiplicand<=0;square_product<=0;square_count<=0;
  end else begin
   result_valid<=0;
   // A stalled next pixel does not stall an already accepted writeback.
   cap_pending<=cap_accept;
   if(cap_accept)begin cap_bank<=capture_bank;cap_address<=gray;end
   last_write_valid<=cap_pending;
   if(cap_pending)begin last_write_bank<=cap_bank;last_write_address<=cap_address;last_write_data<=cap_increment;end
   if(frame_start)begin
    capture_config<=config_seq;capture_seq<=frame_seq;
    capture_valid<=capture_bank?available1:available0;
    // Never change counts on a bank still owned by processing.
    if(capture_bank&&available1)begin count1<=0;sum1<=0;available1<=0;end
    else if(!capture_bank&&available0)begin count0<=0;sum0<=0;available0<=0;end
   end
   if(cap_accept)begin
    if(capture_bank)begin count1<=frame_start?20'd1:count1+1'b1;sum1<=frame_start?{20'd0,gray}:sum1+gray;end
    else begin count0<=frame_start?20'd1:count0+1'b1;sum0<=frame_start?{20'd0,gray}:sum0+gray;end
   end
   if(frame_end)begin
    capture_valid<=0;
    if(frame_start?(capture_bank?available1:available0):capture_valid)begin
     if(capture_bank)begin ready1<=1;seq1<=frame_start?frame_seq:capture_seq;cfg1<=frame_start?config_seq:capture_config;err1<=frame_error;end
     else begin ready0<=1;seq0<=frame_start?frame_seq:capture_seq;cfg0<=frame_start?config_seq:capture_config;err0<=frame_error;end
    end
    capture_bank<=~capture_bank;
   end
   case(state)
    CLEAR_ALL:begin
     if(clear_index==255)begin clear_index<=0;available0<=1;available1<=1;state<=IDLE;end
     else clear_index<=clear_index+1'b1;
    end
    IDLE:if(ready0||ready1)begin
     process_bank<=!ready0;
     total<=ready0?count0:count1;total_sum<=ready0?sum0:sum1;
     work_config<=ready0?cfg0:cfg1;work_frame<=ready0?seq0:seq1;work_error<=ready0?err0:err1;
     if(ready0)ready0<=0;else ready1<=0;
     bin_index<=0;wback<=0;sumback<=0;best_score<=0;best_threshold<=0;state<=DRAIN;
    end
    DRAIN:if(!cap_pending||cap_bank!=process_bank)state<=READ_BIN;
    READ_BIN:state<=ACCUM;
    ACCUM:begin
     wback<=next_weight;sumback<=next_sum;
     if(next_weight!=0&&next_weight<total)state<=PRODUCTS;
     else if(bin_index==255)state<=FINISH;
     else begin bin_index<=bin_index+1'b1;state<=READ_BIN;end
    end
    PRODUCTS:begin
     prod_a<=total_sum*{44'd0,wback};
     prod_b<=sumback*{44'd0,total};
     denominator<={44'd0,wback}*{44'd0,foreground_weight};state<=DELTA;
    end
    DELTA:begin
     // 28-bit gray sum times 20-bit count is exactly 48 bits. A difference
     // of these unsigned products also fits 48 bits; no score is truncated.
     delta_abs<=(prod_a[47:0]>=prod_b[47:0])?(prod_a[47:0]-prod_b[47:0]):(prod_b[47:0]-prod_a[47:0]);state<=SQUARE;
    end
    SQUARE:begin
     square_multiplier<=delta_abs;square_multiplicand<={48'd0,delta_abs};square_product<=0;square_count<=0;state<=MULTIPLY;
    end
    MULTIPLY:begin
     square_product<=square_next;square_multiplier<=square_multiplier>>1;square_multiplicand<=square_multiplicand<<1;
     if(square_count==47)begin
      numerator<={16'd0,square_next,16'd0};quotient<=0;remainder<=0;divide_count<=0;state<=DIVIDE;
     end else square_count<=square_count+1'b1;
    end
    DIVIDE:begin
     numerator<={numerator[126:0],1'b0};
     if(shifted_rem>={1'b0,denominator})begin remainder<=shifted_rem-{1'b0,denominator};quotient<={quotient[126:0],1'b1};end
     else begin remainder<=shifted_rem;quotient<={quotient[126:0],1'b0};end
     if(divide_count==127)state<=SCORE;else divide_count<=divide_count+1'b1;
    end
    SCORE:begin
     if(quotient>best_score)begin best_score<=quotient;best_threshold<=bin_index;end
     if(bin_index==255)state<=FINISH;
     else begin bin_index<=bin_index+1'b1;state<=READ_BIN;end
    end
    FINISH:begin
     result_valid<=(best_score!=0)&&(work_config==config_seq)&&!work_error;
     result_threshold<=best_threshold;result_frame<=work_frame;result_config<=work_config;
     clear_index<=0;state<=CLEAR_WORK;
    end
    CLEAR_WORK:begin
     if(clear_index==255)begin
      if(process_bank)begin available1<=1;count1<=0;sum1<=0;end else begin available0<=1;count0<=0;sum0<=0;end
      clear_index<=0;state<=IDLE;
     end else clear_index<=clear_index+1'b1;
    end
    default:state<=CLEAR_ALL;
   endcase
  end
 end
endmodule
