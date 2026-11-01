`timescale 1ns/1ps
// Full-frame 3x3 Otsu. Cell index = row*3+column, packed little-cell-first.
// Threshold/mask group is atomic; a constant/empty cell has mask=0.
// New SOF must follow EOF; an aborted stream must assert aresetn (as in top).
module qr_otsu_grid(
 input wire aclk,aresetn,frame_start,frame_end,frame_error,pixel_valid,
 input wire [7:0] gray,
 input wire [15:0] x,y,width,height,
 input wire [31:0] frame_seq,config_seq,
 output reg result_valid,
 output reg [71:0] result_thresholds,
 output reg [8:0] result_mask,
 output reg [31:0] result_frame,result_config
);
 localparam INIT=0,IDLE=1,DRAIN=2,RUN=3,CLEAR=4;
 reg [2:0] state;
 reg [9:0] clear_address;
 reg cap_bank,process_bank,capture_valid,capture_error;
 reg available0,available1,ready0,ready1,err0,err1;
 reg [15:0] cap_width,cap_height;
 reg [31:0] seq0,seq1,cfg0,cfg1,capture_seq,capture_cfg,work_seq,work_cfg;
 reg work_error;
 reg [2:0] lane_finished;
 reg [71:0] group_thresholds;
 reg [8:0] group_mask;
 wire [15:0] w=frame_start?width:cap_width,h=frame_start?height:cap_height;
 wire dimensions_ok=(w!=0)&&(h!=0)&&(w<=1280)&&(h<=720);
 wire bank_free=cap_bank?available1:available0;
 wire start_accept=frame_start&&!capture_valid&&bank_free&&dimensions_ok;
 wire cap_accept=pixel_valid&&(frame_start?start_accept:capture_valid)&&(x<w)&&(y<h);
 wire [17:0] x3={2'd0,x}+({2'd0,x}<<1),y3={2'd0,y}+({2'd0,y}<<1);
 wire [1:0] col=(x3<{2'd0,w})?2'd0:(x3<({2'd0,w}<<1))?2'd1:2'd2;
 wire [1:0] row=(y3<{2'd0,h})?2'd0:(y3<({2'd0,h}<<1))?2'd1:2'd2;
 wire [2:0] pending,lane_done;
 wire [23:0] lane_thresholds[0:2];wire [2:0] lane_mask[0:2];
 wire launch=(state==DRAIN)&&!(|pending);
 genvar c;
 generate for(c=0;c<3;c=c+1)begin:lanes
  qr_otsu_grid_lane lane(.aclk(aclk),.aresetn(aresetn),.cap_start(start_accept),
   .cap_accept(cap_accept&&(col==c)),.cap_bank(cap_bank),.cap_row(row),.gray(gray),
   .work_start(launch),.work_bank(process_bank),.clear_all(state==INIT),
   .clear_work(state==CLEAR),.clear_address(clear_address),.done(lane_done[c]),
   .thresholds(lane_thresholds[c]),.mask(lane_mask[c]),.pending(pending[c]));
 end endgenerate
 integer i,j;
 always @(posedge aclk)begin
  if(!aresetn)begin
   state<=INIT;clear_address<=0;cap_bank<=0;process_bank<=0;capture_valid<=0;capture_error<=0;
   available0<=0;available1<=0;ready0<=0;ready1<=0;err0<=0;err1<=0;
   cap_width<=0;cap_height<=0;seq0<=0;seq1<=0;cfg0<=0;cfg1<=0;capture_seq<=0;capture_cfg<=0;
   work_seq<=0;work_cfg<=0;work_error<=0;lane_finished<=0;group_thresholds<=0;group_mask<=0;
   result_valid<=0;result_thresholds<=0;result_mask<=0;result_frame<=0;result_config<=0;
  end else begin
   result_valid<=0;
   if(frame_start)begin
    capture_valid<=start_accept;capture_error<=frame_error||(pixel_valid&&((x>=w)||(y>=h)));
    cap_width<=width;cap_height<=height;capture_seq<=frame_seq;capture_cfg<=config_seq;
    if(start_accept)begin if(cap_bank)available1<=0;else available0<=0;end
   end
   if(capture_valid&&frame_error)capture_error<=1;
   if(capture_valid&&pixel_valid&&((x>=w)||(y>=h)))capture_error<=1;
   if(frame_end)begin
    capture_valid<=0;
    if(frame_start?start_accept:capture_valid)begin
     if(cap_bank)begin ready1<=1;seq1<=frame_start?frame_seq:capture_seq;cfg1<=frame_start?config_seq:capture_cfg;err1<=frame_error||(frame_start?1'b0:capture_error)||(pixel_valid&&((x>=w)||(y>=h)));end
     else begin ready0<=1;seq0<=frame_start?frame_seq:capture_seq;cfg0<=frame_start?config_seq:capture_cfg;err0<=frame_error||(frame_start?1'b0:capture_error)||(pixel_valid&&((x>=w)||(y>=h)));end
    end
    cap_bank<=~cap_bank;
   end
   case(state)
    INIT:begin
     if(clear_address==767)begin clear_address<=0;available0<=1;available1<=1;state<=IDLE;end
     else clear_address<=clear_address+1'b1;
    end
    IDLE:if(ready0||ready1)begin
     process_bank<=!ready0;work_seq<=ready0?seq0:seq1;work_cfg<=ready0?cfg0:cfg1;work_error<=ready0?err0:err1;
     if(ready0)ready0<=0;else ready1<=0;
     lane_finished<=0;group_thresholds<=0;group_mask<=0;state<=DRAIN;
    end
    DRAIN:if(launch)state<=RUN;
    RUN:begin
     for(i=0;i<3;i=i+1)if(lane_done[i])begin
      lane_finished[i]<=1;
      for(j=0;j<3;j=j+1)begin
       group_thresholds[(j*3+i)*8+:8]<=lane_thresholds[i][j*8+:8];
       group_mask[j*3+i]<=lane_mask[i][j];
      end
     end
     // Wait one extra clock after final lane payload was latched.
     if(&lane_finished)begin
      result_valid<=!work_error&&(work_cfg==config_seq);
      result_thresholds<=group_thresholds;result_mask<=group_mask;result_frame<=work_seq;result_config<=work_cfg;
      clear_address<=0;state<=CLEAR;
     end
    end
    CLEAR:begin
     if(clear_address==767)begin
      if(process_bank)available1<=1;else available0<=1;
      clear_address<=0;state<=IDLE;
     end else clear_address<=clear_address+1'b1;
    end
    default:state<=INIT;
   endcase
  end
 end
endmodule
