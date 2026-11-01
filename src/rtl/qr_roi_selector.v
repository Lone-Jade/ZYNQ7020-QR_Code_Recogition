`timescale 1ns/1ps
// Read-only query over the dense retained set. No write is allowed until done.
// Record [328:201]=score128, [200]=clipped, [199:136]=xmin,ymin,xmax,ymax,
// [135:40]=p0,p1,p2 (each {y16,x16}), [39:16]=sorted finder IDs, [15:0]=min physical module Q8.
module qr_roi_selector #(
 parameter LIMIT=30, FINDER_ENABLE=1, IOU_ENABLE=1, UNION_ENABLE=0,
 parameter TOL_NUM=1,TOL_DEN=2,MIN_PIXELS=1,SCALE_NUM=5,SCALE_DEN=4,
 parameter IOU_NUM=2,IOU_DEN=5,
 parameter AW=$clog2(LIMIT+1)
)(input wire clk,rstn,start,input wire [AW-1:0] count,
 input wire [328:0] candidate,input wire [328:0] old_record,
 input wire [64:0] old_rank_key,
 output wire [63:0] merged_box,output reg merged_clipped,
 output reg [AW-1:0] representative_index,
 output reg [31:0] absorbed_count,rescan_count,
 input wire [31:0] old_cached_area,output wire [31:0] candidate_area,
 output reg [AW-1:0] read_index,output reg done,accept,
 output reg [AW-1:0] slot,output reg [2:0] reason,
 output reg [31:0] finder_compares,iou_compares,no_intersection,group_compares,cycles,
 output wire [LIMIT-1:0] remove_mask);
 localparam IDLE=0,LOAD=1,PREP=2,CHECK=3,DECIDE=4,FINISH=5,
  PAIR_PIVOT=6,PIVOT_LATCH=7,PAIR_OTHER=8,OTHER_LATCH=9,PAIR_PREP=10,PAIR_CHECK=11,COMMIT_READY=12,EXPAND=13;
 reg [3:0] state;reg pass_iou;
 reg [328:0] pending,old,worst,growing,best,old_rank;
 reg [LIMIT-1:0] absorbed;
 assign merged_box=growing[199:136];
 wire [328:0] compare_old=UNION_ENABLE?old_rank:old;
 wire [328:0] overlap_pending=UNION_ENABLE?growing:pending;
 reg [95:0] pending_points,old_points,worst_points,best_points;
 reg [AW-1:0] worst_index,conflict_index;
 reg [LIMIT-1:0] conflicts;
 reg [AW-1:0] pivot_index,pair_index;
 reg [328:0] pivot;
 reg separated;
 assign remove_mask=accept?conflicts:{LIMIT{1'b0}};
 reg [8:0] near_matrix;reg scale_match,id_match;
 reg [31:0] pending_area,old_area,intersection;
 reg intersects;
 assign candidate_area=pending_area;
 wire [32:0] union_area={1'b0,pending_area}+{1'b0,old_area}-{1'b0,intersection};
 wire [63:0] intersection_scaled={32'd0,intersection}*IOU_DEN;
 wire [63:0] union_scaled={31'd0,union_area}*IOU_NUM;
 wire match_points=(near_matrix[0]&&near_matrix[4]&&near_matrix[8])||
  (near_matrix[0]&&near_matrix[5]&&near_matrix[7])||
  (near_matrix[1]&&near_matrix[3]&&near_matrix[8])||
  (near_matrix[1]&&near_matrix[5]&&near_matrix[6])||
  (near_matrix[2]&&near_matrix[3]&&near_matrix[7])||
  (near_matrix[2]&&near_matrix[4]&&near_matrix[6]);
 wire finder_match=FINDER_ENABLE&&(id_match||(scale_match&&match_points));
 wire iou_match=intersects&&intersection_scaled>union_scaled;
 function [AW-1:0] first_conflict;input [LIMIT-1:0] mask;integer k;begin
  first_conflict=0;
  for(k=LIMIT-1;k>=0;k=k-1)if(mask[k])first_conflict=k;
 end endfunction
 function boxes_separated;input [328:0] a,b;
 reg [16:0] ax,ay,bx,by,dx,dy;reg [15:0] aw,bw,ah,bh;begin
  ax={1'b0,a[199:184]}+{1'b0,a[167:152]};ay={1'b0,a[183:168]}+{1'b0,a[151:136]};
  bx={1'b0,b[199:184]}+{1'b0,b[167:152]};by={1'b0,b[183:168]}+{1'b0,b[151:136]};
  dx=ax>bx?ax-bx:bx-ax;dy=ay>by?ay-by:by-ay;
  aw=a[167:152]>a[199:184]?a[167:152]-a[199:184]:0;
  bw=b[167:152]>b[199:184]?b[167:152]-b[199:184]:0;
  ah=a[151:136]>a[183:168]?a[151:136]-a[183:168]:0;
  bh=b[151:136]>b[183:168]?b[151:136]-b[183:168]:0;
  boxes_separated=dx>(aw>bw?aw:bw)||dy>(ah>bh?ah:bh);
 end endfunction
 function [31:0] xy_key;input [31:0] point;begin xy_key={point[15:0],point[31:16]};end endfunction
 function [95:0] sorted_points;input [95:0] pts;reg [31:0] a,b,c,t;begin
  a=xy_key(pts[95:64]);b=xy_key(pts[63:32]);c=xy_key(pts[31:0]);
  if(a>b)begin t=a;a=b;b=t;end
  if(b>c)begin t=b;b=c;c=t;end
  if(a>b)begin t=a;a=b;b=t;end
  sorted_points={a,b,c};
 end endfunction
 function better;input [328:0] a,b;input [95:0] ap,bp;begin
  if(a[328:201]!=b[328:201])better=a[328:201]>b[328:201];
  else if(a[200]!=b[200])better=!a[200];
  else if(a[199:136]!=b[199:136])better=a[199:136]<b[199:136];
  else if(ap!=bp)better=ap<bp;
  else better=a[39:16]<b[39:16];
 end endfunction
 function [31:0] area;input [328:0] a;reg [15:0] w,h;begin
  w=a[167:152]>a[199:184]?a[167:152]-a[199:184]:0;
  h=a[151:136]>a[183:168]?a[151:136]-a[183:168]:0;
  area=w*h;
 end endfunction
 function [328:0] enclosing;input [328:0] a,b;begin
  enclosing=a;
  enclosing[199:184]=a[199:184]<b[199:184]?a[199:184]:b[199:184];
  enclosing[183:168]=a[183:168]<b[183:168]?a[183:168]:b[183:168];
  enclosing[167:152]=a[167:152]>b[167:152]?a[167:152]:b[167:152];
  enclosing[151:136]=a[151:136]>b[151:136]?a[151:136]:b[151:136];
 end endfunction
 function [31:0] intersection_area;input [328:0] a,b;reg [15:0] x0,y0,x1,y1,w,h;begin
  x0=a[199:184]>b[199:184]?a[199:184]:b[199:184];
  y0=a[183:168]>b[183:168]?a[183:168]:b[183:168];
  x1=a[167:152]<b[167:152]?a[167:152]:b[167:152];
  y1=a[151:136]<b[151:136]?a[151:136]:b[151:136];
  w=x1>x0?x1-x0:0;h=y1>y0?y1-y0:0;intersection_area=w*h;
 end endfunction
 function [8:0] point_matrix;input [328:0] a,b;reg [31:0] p,q;
 reg [31:0] radius,m;reg [16:0] dx,dy;integer i,j;begin
  m=a[15:0]<b[15:0]?a[15:0]:b[15:0];radius=(m*TOL_NUM)/(256*TOL_DEN);
  if(radius<MIN_PIXELS)radius=MIN_PIXELS;
  point_matrix=0;
  for(i=0;i<3;i=i+1)for(j=0;j<3;j=j+1)begin
   p=a[40+32*i+:32];q=b[40+32*j+:32];
   dx=p[15:0]>q[15:0]?{1'b0,p[15:0]}-{1'b0,q[15:0]}:{1'b0,q[15:0]}-{1'b0,p[15:0]};
   dy=p[31:16]>q[31:16]?{1'b0,p[31:16]}-{1'b0,q[31:16]}:{1'b0,q[31:16]}-{1'b0,p[31:16]};
   point_matrix[3*i+j]=(dx<=radius&&dy<=radius);
  end
 end endfunction
 initial begin
  if(TOL_DEN<=0||SCALE_DEN<=0||IOU_DEN<=0||IOU_NUM<0||IOU_NUM>=IOU_DEN)$error("Invalid ROI selector parameters");
 end
 always @(posedge clk)begin
  if(!rstn)begin state<=IDLE;done<=0;accept<=0;slot<=0;reason<=0;read_index<=0;finder_compares<=0;iou_compares<=0;no_intersection<=0;cycles<=0;group_compares<=0;conflicts<=0;end
  else begin
   done<=0;
   if(state!=IDLE&&state!=FINISH)cycles<=cycles+1;
   case(state)
    IDLE:if(start)begin
     growing<=candidate;best<=candidate;best_points<=sorted_points(candidate[135:40]);absorbed<=0;absorbed_count<=0;rescan_count<=0;
     merged_clipped<=candidate[200];representative_index<=count;
     pending<=candidate;pending_points<=sorted_points(candidate[135:40]);pending_area<=area(candidate);
     read_index<=0;worst_index<=0;conflicts<=0;pass_iou<=0;group_compares<=0;
     accept<=0;reason<=0;finder_compares<=0;iou_compares<=0;no_intersection<=0;cycles<=0;
     if(count==0)begin slot<=0;accept<=1;state<=FINISH;end else state<=LOAD;
    end
    LOAD:begin old<=old_record;old_rank<={old_record[328:201],old_rank_key,old_record[135:0]};state<=PREP;end
    PREP:begin
     old_points<=sorted_points(old[135:40]);near_matrix<=point_matrix(pending,old);
     scale_match<=pending[15:0]!=0&&old[15:0]!=0&&
      (pending[15:0]*SCALE_DEN<=old[15:0]*SCALE_NUM)&&(old[15:0]*SCALE_DEN<=pending[15:0]*SCALE_NUM);
     id_match<=pending[39:16]==old[39:16];
     old_area<=old_cached_area;intersection<=intersection_area(overlap_pending,old);
     intersects<=overlap_pending[167:152]>old[199:184]&&old[167:152]>overlap_pending[199:184]&&
      overlap_pending[151:136]>old[183:168]&&old[151:136]>overlap_pending[183:168]&&old_cached_area!=0&&pending_area!=0;
     state<=CHECK;
    end
    CHECK:begin
     if(!pass_iou)begin
      if(read_index==0||better(worst,compare_old,worst_points,old_points))begin worst<=compare_old;worst_points<=old_points;worst_index<=read_index;end
      if(FINDER_ENABLE)finder_compares<=finder_compares+1;
     end else if(UNION_ENABLE?!absorbed[read_index]:!conflicts[read_index])begin
      iou_compares<=iou_compares+1;
      if(!intersects)no_intersection<=no_intersection+1;
     end
     if(UNION_ENABLE&&pass_iou&&!absorbed[read_index]&&iou_match)begin
      growing<=enclosing(growing,old);absorbed[read_index]<=1;conflicts[read_index]<=1;
      merged_clipped<=merged_clipped|old[200];absorbed_count<=absorbed_count+1;rescan_count<=rescan_count+1;
      if(better(compare_old,best,old_points,best_points))begin best<=compare_old;best_points<=old_points;representative_index<=read_index;end
      state<=EXPAND;
     end else if((!pass_iou&&finder_match)||(pass_iou&&!UNION_ENABLE&&!conflicts[read_index]&&iou_match))begin
      if(!better(pending,compare_old,pending_points,old_points))begin reason<=pass_iou?2:1;state<=FINISH;end
      else begin
       conflicts[read_index]<=1;
       if(read_index+1>=count)begin
        if(!pass_iou&&IOU_ENABLE)begin pass_iou<=1;read_index<=0;state<=LOAD;end
        else state<=DECIDE;
       end else begin read_index<=read_index+1;state<=LOAD;end
      end
     end else if(read_index+1>=count)begin
      if(!pass_iou&&IOU_ENABLE)begin pass_iou<=1;read_index<=0;state<=LOAD;end
      else state<=DECIDE;
     end else begin read_index<=read_index+1;state<=LOAD;end
    end
    EXPAND:begin pending_area<=area(growing);read_index<=0;state<=LOAD;end
    DECIDE:begin
     if((conflicts&(conflicts-1'b1))!=0)begin pivot_index<=0;state<=PAIR_PIVOT;end
     else state<=COMMIT_READY;
    end
    PAIR_PIVOT:begin
     if(pivot_index>=count)state<=COMMIT_READY;
     else if(conflicts[pivot_index])begin read_index<=pivot_index;state<=PIVOT_LATCH;end
     else pivot_index<=pivot_index+1;
    end
    PIVOT_LATCH:begin pivot<=old_record;pair_index<=pivot_index+1;state<=PAIR_OTHER;end
    PAIR_OTHER:begin
     if(pair_index>=count)begin pivot_index<=pivot_index+1;state<=PAIR_PIVOT;end
     else if(conflicts[pair_index])begin read_index<=pair_index;state<=OTHER_LATCH;end
     else pair_index<=pair_index+1;
    end
    OTHER_LATCH:begin old<=old_record;state<=PAIR_PREP;end
    PAIR_PREP:begin
     near_matrix<=point_matrix(pivot,old);separated<=boxes_separated(pivot,old);
     group_compares<=group_compares+1;state<=PAIR_CHECK;
    end
    PAIR_CHECK:begin
     if(separated&&!(|near_matrix))begin reason<=3;state<=FINISH;end
     else begin pair_index<=pair_index+1;state<=PAIR_OTHER;end
    end
    COMMIT_READY:begin
     if(conflicts!=0)begin accept<=1;slot<=first_conflict(conflicts);reason<=4;end
     else if(count<LIMIT)begin accept<=1;slot<=count;reason<=0;end
     else if(better(pending,worst,pending_points,worst_points))begin accept<=1;slot<=worst_index;reason<=5;end
     else reason<=6;
     state<=FINISH;
    end
    FINISH:begin done<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
