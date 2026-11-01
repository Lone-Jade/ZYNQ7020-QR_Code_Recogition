`timescale 1ns/1ps
// Frame-local ROI geometry. Memories have explicit single write ports and no
// reset: validity belongs to counters/generation, never to resettable RAM data.
module qr_finder_roi #(
 parameter integer RAW_LIMIT=4096,CLUSTER_LIMIT=128,ROI_LIMIT=30,
 parameter integer PAYLOAD_BRAM=0,
 parameter integer POST_CYCLES=1538460,
 parameter integer LEG_MAX_MODULES=190,
 parameter integer WEIGHTED_SCORE=1,
 parameter integer FUSION_ENABLE=0,
 parameter integer SCORE_MIN=0,FINDER_DEDUP=0,IOU_DEDUP=0,IOU_UNION=0
)(
 input wire aclk,aresetn,frame_start,frame_end,
 input wire [31:0] frame_seq,epoch,config_seq,
 input wire [15:0] width,height,input wire [7:0] threshold,
 input wire [31:0] threshold_source,input wire frame_error,
 input wire [127:0] threshold_metadata,
 input wire cand_valid,output wire cand_ready,
 input wire [15:0] cand_x,cand_y,cand_module_q8,
 input wire cand_direction,input wire [15:0] cand_error,
 input wire cand_branch,
 input wire [15:0] ro_address,output reg [31:0] ro_data,output wire busy,output wire [1:0] raw_occupancy
);
 initial begin
  if(SCORE_MIN<0||SCORE_MIN>255||(SCORE_MIN!=0&&!WEIGHTED_SCORE))$error("Invalid normalized SCORE_MIN");
  if(LEG_MAX_MODULES!=32&&LEG_MAX_MODULES!=64&&LEG_MAX_MODULES!=190)$error("LEG_MAX_MODULES must be 32, 64 or 190");
 end
 localparam RAW_AW=(RAW_LIMIT>1)?$clog2(RAW_LIMIT):1;
 localparam CL_AW=(CLUSTER_LIMIT>1)?$clog2(CLUSTER_LIMIT):1;
 localparam MEM_AW=CL_AW+(FUSION_ENABLE?1:0);
 localparam CL_DEPTH=CLUSTER_LIMIT*(FUSION_ENABLE?2:1);
 localparam IDLE=0,LOAD=1,LOAD_WAIT=2,MATCH=3,MATCH_DRAIN=4,ADD=5,
  AVERAGE_LOAD=6,AVERAGE_SETUP=7,DIVIDE=8,AVERAGE_STORE=9,
  CENTER_LOAD=10,NEIGHBOR=11,NEIGHBOR_DRAIN=12,
  TRI_READ1=13,TRI_READ2=14,TRI_VECTOR=15,TRI_NORM=16,
  TRI_MUL_SETUP=17,TRI_MUL=18,TRI_CHECK=19,
  SELECT=20,SELECT_DONE=21,ANGLE=22,SAVE=23,PUBLISH=24,
  NEIGHBOR_CALC=25,NEIGHBOR_CHECK=26,NEIGHBOR_SELECT=27,NEIGHBOR_REPLACE=28,
  AVERAGE_QSTART=29,AVERAGE_QWAIT=30,TRI_QSTART=31,TRI_QWAIT=32,
  F_AVG_SWITCH=33,F_BEGIN=34,F_A_READ=35,F_A_LOAD=36,F_B_READ=37,F_B_CALC=38,F_DIST=39,F_MATCH=40,
  F_MA_READ=41,F_MA_LOAD=42,F_MB_READ=43,F_MB_LOAD=44,F_STORE=45,
  F_APPEND=46,F_AB_READ=47,F_AB_LOAD=48,F_AB_STORE=49,SELECT_NEW_START=50,SELECT_NEW_WAIT=51,COMPACT=52;
 localparam FLAG_COMPLETE=1,FLAG_AXIS=2,FLAG_RAW=4,FLAG_CLUSTER=8,FLAG_ROI=16,FLAG_TIMEOUT=32;
 reg [5:0] state;
 reg [1:0] raw_used,raw_ready;
 reg capture_bank,capture_active,process_bank,drop_active,drop_pending,process_drop;
 reg [12:0] raw_count[0:1];
 reg [31:0] seq_meta[0:1],epoch_meta[0:1],cfg_meta[0:1],source_meta[0:1],flags_meta[0:1];
 reg [1:0] result_bank_meta[0:1],drop_result_bank;
 reg [15:0] width_meta[0:1],height_meta[0:1];reg [7:0] threshold_meta[0:1];
 reg [127:0] grid_meta[0:1],drop_grid,work_grid;
 reg [31:0] drop_seq,drop_epoch,drop_cfg,drop_source;reg [7:0] drop_threshold;
 reg [31:0] descriptor[0:47];
 reg [31:0] owner_seq[0:2],owner_epoch[0:2],generation[0:2];
 reg [31:0] work_seq,work_epoch,work_cfg,work_source,work_flags;
 reg [15:0] work_width,work_height;reg [7:0] work_threshold;
 reg [12:0] work_raw_count,raw_index;reg [1:0] work_result_bank;
 reg [31:0] elapsed;
 reg [7:0] cluster_count,match_index,best_match,average_index,center_index,neighbor_index;
 reg [15:0] rx,ry,rm,re;reg rd,found_match,raw_branch,average_branch;
 reg [7:0] diagonal_count;
 wire [7:0] current_count=raw_branch?diagonal_count:cluster_count;
 wire [7:0] averaging_count=average_branch?diagonal_count:cluster_count;
 reg [7:0] fi,fj,fusion_a_count,fusion_matched;
 reg [12:0] raw_axis_count,raw_diagonal_count;
 reg [7:0] best_b[0:CLUSTER_LIMIT-1],best_a[0:CLUSTER_LIMIT-1];
 (* ram_style="distributed" *) reg [34:0] a_distance[0:CLUSTER_LIMIT-1],b_distance[0:CLUSTER_LIMIT-1];
 reg [CLUSTER_LIMIT-1:0] a_found,b_found,a_tie,b_tie,b_merged;
 reg [209:0] fa_record,fb_record;
 reg fusion_scale;
 reg [31:0] debug_frame,debug_raw,debug_clusters,debug_result;
 function [MEM_AW-1:0] claddr;input branch;input [7:0] index;
 begin claddr=(branch?CLUSTER_LIMIT:0)+index;end endfunction
 function [15:0] physical_module;input [15:0] steps;
 reg [47:0] v;begin v=steps*48'd92682+48'd32768;physical_module=(v>>16)>65535?16'hffff:v>>16;end endfunction
 function [9:0] cluster_radius;input [15:0] steps;input diagonal;
 reg [47:0] v;begin
  if(diagonal)v=(steps*48'd834138+48'd67108863)>>26;
  else v=(steps*48'd9+48'd1023)>>10;
  cluster_radius=v<2?10'd2:(v>1023?10'd1023:v[9:0]);
 end endfunction
 wire [15:0] fusion_min_module=fm(fa_record)<fm(cluster_q)?fm(fa_record):fm(cluster_q);
 wire [16:0] fusion_radius=({1'b0,fusion_min_module}+17'd255)>>8;
 wire [209:0] fusion_winner=(fb_record[198:191]>fa_record[198:191])?fb_record:fa_record;
 reg [209:0] fusion_record;
 always @*begin
  fusion_record=fusion_winner;fusion_record[209:208]=2'b11;
  if(fd(fa_record)==3||fd(fb_record)==3)fusion_record[158:157]=2'b11;
 end
 reg [34:0] best_distance;
 // Record: error32 | directions2 | hits13 | sum_m32 | sum_y32 |
 // sum_x32 | module16 | y16 | x16. Exactly one read and one write port.
 (* ram_style="distributed" *) reg [209:0] cluster_ram[0:CL_DEPTH-1];
 reg [MEM_AW-1:0] cluster_read_address,cluster_address_hold,cluster_write_address;
 reg cluster_write_enable;reg [209:0] cluster_write_data;
 wire [209:0] cluster_q=cluster_ram[cluster_address_hold];
 reg [209:0] best_record,average_record,c0,c1,c2;
 reg [1:0] average_field;
 reg [31:0] div_numerator,div_quotient,div_remainder;
 reg [12:0] div_denominator;reg [5:0] div_bit;
 wire [32:0] shifted_remainder={div_remainder,div_numerator[31]};
 reg m1_valid,m2_valid;
 reg signed [16:0] m_dx,m_dy,n_dx,n_dy;
 reg [9:0] m_radius;reg [19:0] m_radius_square;
 reg [34:0] m_distance,n_distance;
 reg [209:0] m_record1,m_record2;
 reg [7:0] m_id1,m_id2,n_id1;
 reg m_scale1,m_scale2,n_qual1;
 reg [7:0] neighbor_id[0:15];reg [34:0] neighbor_dist[0:15];
 reg [4:0] neighbor_count,pair_i,pair_j;
 reg [34:0] n_worst_distance;
 reg [7:0] id0,id1,id2,sorted0,sorted1,sorted2,tmp_id;
 reg signed [16:0] ux,uy,vx,vy;
 reg [34:0] norm_u,norm_v;reg signed [34:0] dot;
 reg [34:0] abs_dot,norm_min,norm_max;
 reg [15:0] module_min,module_max;
 reg [15:0] geom_module_min,geom_module_max;
 reg [31:0] min_module_square,max_module_square;
 reg [47:0] bound_a,bound_b,bound_ab;
 reg [63:0] leg_lower_bound,leg_upper_bound;
 reg [15:0] diag_geom_pass,diag_scale_reject;
 reg base_triangle_ok,scale_ok;
 reg [17:0] triple_hits;reg [35:0] triple_error;reg [29:0] score_error;
 reg [3:0] direction_score;reg triangle_ok;
 // Exact radix-4 products, two lanes in parallel. 35-bit operands take 18
 // iterations. No giant combinational square feeds the triangle comparator.
 reg [69:0] mul_a0,mul_a1,mul_three0,mul_three1,mul_acc0,mul_acc1;
 reg [34:0] mul_b0,mul_b1;reg [4:0] mul_step;
 reg [69:0] mul_add0,mul_add1;
 reg [15:0] out_minx[0:ROI_LIMIT-1],out_miny[0:ROI_LIMIT-1],out_maxx[0:ROI_LIMIT-1],out_maxy[0:ROI_LIMIT-1];
 reg [31:0] out_p0[0:ROI_LIMIT-1],out_p1[0:ROI_LIMIT-1],out_p2[0:ROI_LIMIT-1];
 reg [15:0] out_module[0:ROI_LIMIT-1],out_angle[0:ROI_LIMIT-1];
 reg [31:0] out_hits[0:ROI_LIMIT-1],out_flags[0:ROI_LIMIT-1];
 reg [7:0] out_id0[0:ROI_LIMIT-1],out_id1[0:ROI_LIMIT-1],out_id2[0:ROI_LIMIT-1];
 reg [127:0] out_score[0:ROI_LIMIT-1],pending_score,worst_score;
 reg [$clog2(ROI_LIMIT+1)-1:0] roi_count,save_index,select_index,worst_index;reg duplicate_found;
 reg [15:0] pending_minx,pending_miny,pending_maxx,pending_maxy,pending_module;
 reg [31:0] pending_hits,pending_flags,pending_p0,pending_p1,pending_p2;
 reg [7:0] pending_id0,pending_id1,pending_id2;
 reg signed [31:0] pending_ux,pending_uy,angle_x,angle_y,angle_acc;
 reg [4:0] angle_step;reg [8:0] publish_word;
 reg signed [31:0] p3x,p3y,bbox_minx,bbox_miny,bbox_maxx,bbox_maxy;
 reg [31:0] padding;reg [127:0] triangle_score;
 reg [31:0] publish_data;
 reg [31:0] out_parts[0:ROI_LIMIT-1],pending_parts;
 reg [7:0] out_direction[0:ROI_LIMIT-1],pending_direction;
 wire quality_done;wire [7:0] quality_h,quality_e,quality_score,quality_direction;
 wire [31:0] quality_parts;
 wire [9:0] sum_quality_h={2'd0,c0[198:191]}+{2'd0,c1[198:191]}+{2'd0,c2[198:191]};
 wire [9:0] sum_quality_e={2'd0,c0[206:199]}+{2'd0,c1[206:199]}+{2'd0,c2[206:199]};
 qr_roi_quality quality(.clk(aclk),.rstn(aresetn),
  .start(WEIGHTED_SCORE&&(state==AVERAGE_QSTART||state==TRI_QSTART)),.mode(state==TRI_QSTART),
  .hits(fh(average_record)),.module_q8(fm(average_record)),.error_sum(ferr(average_record)),
  .finder_diagonal(FUSION_ENABLE&&average_branch),
  .dot_square(mul_acc0),.norm_product(mul_acc1),.norm_min(norm_min),.norm_max(norm_max),
  .sum_h(sum_quality_h),.sum_e(sum_quality_e),.directions(direction_score),
  .done(quality_done),.finder_h(quality_h),.finder_e(quality_e),.score(quality_score),
  .parts(quality_parts),.direction_quality(quality_direction));

 localparam NEW_SELECTION=FINDER_DEDUP||IOU_DEDUP;
 localparam SEL_AW=$clog2(ROI_LIMIT+1);
 reg [15:0] pending_dedup_module,out_dedup_module[0:ROI_LIMIT-1];
 wire [SEL_AW-1:0] selector_index,selector_slot;
 wire selector_done,selector_accept;wire [2:0] selector_reason;
 reg [31:0] out_area[0:ROI_LIMIT-1],pending_cached_area;wire [31:0] selector_area;
 wire [31:0] selector_finder_compares,selector_iou_compares,selector_no_intersection,selector_cycles,selector_group_compares;
 wire [ROI_LIMIT-1:0] selector_remove;reg [ROI_LIMIT-1:0] commit_mask;
 reg [SEL_AW-1:0] compact_read,compact_write;
 reg [31:0] group_work,group_snapshot;
 reg [64:0] out_rank_key[0:ROI_LIMIT-1],pending_rank_key;
 reg pending_old_angle;reg [15:0] pending_saved_angle;
 wire [63:0] selector_box;wire selector_clipped;
 wire [SEL_AW-1:0] selector_representative;
 wire [31:0] selector_absorbed,selector_rescans;
 reg [31:0] pending_absorbed,pending_rescans;
 reg [31:0] merge_work,absorbed_work,rescan_work,members_work;
 reg [31:0] merge_snapshot,absorbed_snapshot,rescan_snapshot,members_snapshot;
 // Worst case: dense compaction, 16 CORDIC steps, SAVE and FSM transitions.
 wire union_commit_time=elapsed+ROI_LIMIT+32<POST_CYCLES;
 wire [328:0] selector_candidate={pending_score,pending_flags[0],pending_minx,pending_miny,pending_maxx,pending_maxy,pending_p0,pending_p1,pending_p2,pending_id0,pending_id1,pending_id2,pending_dedup_module};
 wire [328:0] selector_old={out_score[selector_index],out_flags[selector_index][0],out_minx[selector_index],out_miny[selector_index],out_maxx[selector_index],out_maxy[selector_index],out_p0[selector_index],out_p1[selector_index],out_p2[selector_index],out_id0[selector_index],out_id1[selector_index],out_id2[selector_index],out_dedup_module[selector_index]};
 qr_roi_selector #(.LIMIT(ROI_LIMIT),.FINDER_ENABLE(FINDER_DEDUP),.IOU_ENABLE(IOU_DEDUP),.UNION_ENABLE(IOU_UNION)) selector(
  .clk(aclk),.rstn(aresetn&&(state==SELECT_NEW_START||state==SELECT_NEW_WAIT)),
  .start(state==SELECT_NEW_START),.count(roi_count),.candidate(selector_candidate),.old_record(selector_old),
  .old_rank_key(out_rank_key[selector_index]),.merged_box(selector_box),.merged_clipped(selector_clipped),
  .representative_index(selector_representative),.absorbed_count(selector_absorbed),.rescan_count(selector_rescans),
  .old_cached_area(out_area[selector_index]),.candidate_area(selector_area),
  .read_index(selector_index),.done(selector_done),.accept(selector_accept),.slot(selector_slot),.reason(selector_reason),
  .finder_compares(selector_finder_compares),.iou_compares(selector_iou_compares),.no_intersection(selector_no_intersection),.cycles(selector_cycles),.group_compares(selector_group_compares),.remove_mask(selector_remove));
 // Independent read-only frame snapshot; existing descriptor/ROI bytes unchanged.
 reg [31:0] selection_generation,selection_epoch,selection_elapsed;
 reg [31:0] stat_work[0:15],stat_snapshot[0:15];
 reg [31:0] hist_work[0:15],hist_snapshot[0:15];
 integer stat_i;
 wire moving_record=state==COMPACT;
 wire table_write=state==SAVE||(moving_record&&compact_read<roi_count&&!commit_mask[compact_read]&&compact_write!=compact_read);
 wire [SEL_AW-1:0] table_address=moving_record?compact_write:save_index;
 // One unreset write port per table, shared by dense compaction and final save.
 always @(posedge aclk)if(aresetn&&table_write)begin
  out_rank_key[table_address]<=moving_record?out_rank_key[compact_read]:pending_rank_key;
  out_minx[table_address]<=moving_record?out_minx[compact_read]:pending_minx;
  out_miny[table_address]<=moving_record?out_miny[compact_read]:pending_miny;
  out_maxx[table_address]<=moving_record?out_maxx[compact_read]:pending_maxx;
  out_maxy[table_address]<=moving_record?out_maxy[compact_read]:pending_maxy;
  out_p0[table_address]<=moving_record?out_p0[compact_read]:pending_p0;
  out_p1[table_address]<=moving_record?out_p1[compact_read]:pending_p1;
  out_p2[table_address]<=moving_record?out_p2[compact_read]:pending_p2;
  out_module[table_address]<=moving_record?out_module[compact_read]:pending_module;
  out_angle[table_address]<=moving_record?out_angle[compact_read]:(IOU_UNION&&pending_old_angle?pending_saved_angle:angle_acc[15:0]);
  out_hits[table_address]<=moving_record?out_hits[compact_read]:pending_hits;
  out_flags[table_address]<=moving_record?out_flags[compact_read]:pending_flags;
  out_id0[table_address]<=moving_record?out_id0[compact_read]:pending_id0;
  out_id1[table_address]<=moving_record?out_id1[compact_read]:pending_id1;
  out_id2[table_address]<=moving_record?out_id2[compact_read]:pending_id2;
  out_score[table_address]<=moving_record?out_score[compact_read]:pending_score;
  out_parts[table_address]<=moving_record?out_parts[compact_read]:pending_parts;
  out_direction[table_address]<=moving_record?out_direction[compact_read]:pending_direction;
  out_dedup_module[table_address]<=moving_record?out_dedup_module[compact_read]:pending_dedup_module;
  out_area[table_address]<=moving_record?out_area[compact_read]:pending_cached_area;
 end
 integer i,b,read_bank,read_word,publish_roi;
 function [15:0] fx;input [209:0] q;begin fx=q[15:0];end endfunction
 function [15:0] fy;input [209:0] q;begin fy=q[31:16];end endfunction
 function [15:0] fm;input [209:0] q;begin fm=q[47:32];end endfunction
 function [12:0] fh;input [209:0] q;begin fh=q[156:144];end endfunction
 function [1:0] fd;input [209:0] q;begin fd=q[158:157];end endfunction
 function [31:0] ferr;input [209:0] q;begin ferr=q[190:159];end endfunction
 // Exact modulo 3 for arbitrary 32-bit frame IDs, including jumps/wrap.
 // 4^k == 1 (mod 3). Each tree node is a four-input truth table rather
 // than a wide constant-divider carry chain.
 function [1:0] add_mod3;input [1:0] a,b;begin case({a,b})
  4'b0001,4'b0100,4'b1010:add_mod3=1;
  4'b0010,4'b0101,4'b1000:add_mod3=2;
  default:add_mod3=0;
 endcase end endfunction
 function automatic [1:0] frame_bank3;input [31:0] value;
 reg [1:0] t0[0:15],t1[0:7],t2[0:3],t3[0:1];integer k;
 begin
  for(k=0;k<16;k=k+1)t0[k]=(value[2*k+:2]==3)?2'd0:value[2*k+:2];
  for(k=0;k<8;k=k+1)t1[k]=add_mod3(t0[2*k],t0[2*k+1]);
  for(k=0;k<4;k=k+1)t2[k]=add_mod3(t1[2*k],t1[2*k+1]);
  for(k=0;k<2;k=k+1)t3[k]=add_mod3(t2[2*k],t2[2*k+1]);
  frame_bank3=add_mod3(t3[0],t3[1]);
 end endfunction
 function [15:0] atan_turn;input [4:0] n;begin case(n)
  0:atan_turn=8192;1:atan_turn=4836;2:atan_turn=2555;3:atan_turn=1297;4:atan_turn=651;5:atan_turn=326;
  6:atan_turn=163;7:atan_turn=81;8:atan_turn=41;9:atan_turn=20;10:atan_turn=10;11:atan_turn=5;
  12:atan_turn=3;13:atan_turn=1;14:atan_turn=1;default:atan_turn=0;
 endcase end endfunction
 assign cand_ready=1'b1;assign busy=&raw_used;assign raw_occupancy=raw_used;
 // Separate unreset processes are essential for true block-RAM inference.
 (* ram_style="block" *) reg [65:0] raw0[0:RAW_LIMIT-1],raw1[0:RAW_LIMIT-1];
 reg [65:0] raw0_q,raw1_q;
 wire raw_read=state==LOAD && raw_index<work_raw_count && (work_flags&FLAG_AXIS)==0;
 wire raw_write=aresetn && capture_active && cand_valid && raw_count[capture_bank]<RAW_LIMIT;
 wire [65:0] raw_data={FUSION_ENABLE?cand_branch:1'b0,cand_error,cand_direction,cand_module_q8,cand_y,cand_x};
 always @(posedge aclk)begin
  if(raw_read)raw0_q<=raw0[raw_index[RAW_AW-1:0]];
  if(raw_write&&!capture_bank)raw0[raw_count[0][RAW_AW-1:0]]<=raw_data;
 end
 always @(posedge aclk)begin
  if(raw_read)raw1_q<=raw1[raw_index[RAW_AW-1:0]];
  if(raw_write&&capture_bank)raw1[raw_count[1][RAW_AW-1:0]]<=raw_data;
 end
 always @(posedge aclk)if(aresetn&&cluster_write_enable)
  cluster_ram[cluster_write_address]<=cluster_write_data;
 // Prefetch on the existing FSM transitions. The registered address isolates
 // indirect neighbor-id/state muxes from RAM data and scan arithmetic, while
 // MATCH continues to process one cluster per clock.
 always @(posedge aclk)begin
  if(!aresetn)cluster_address_hold<=0;
  else cluster_address_hold<=cluster_read_address;
 end
 // The optional BRAM payload has one registered read; the AXI owner adds
 // a legal wait cycle. Descriptor/gen remain their original register group.
 wire owner_matches=owner_seq[work_result_bank]==work_seq && owner_epoch[work_result_bank]==work_epoch;
 wire [1:0] incoming_result_bank=frame_bank3(frame_seq);
 wire new_same_bank=frame_start && incoming_result_bank==work_result_bank;
 wire payload_write=aresetn&&state==PUBLISH&&publish_word>=16&&owner_matches&&!new_same_bank;
 // Each external 2KiB bank contains a 64-byte descriptor plus up to 30 ROIs.
 // Internal payload stride is 512 words, with independent banks and 11-bit address.
 wire [10:0] payload_address=(work_result_bank*11'd512)+(publish_word-9'd16);
 wire [1:0] payload_read_bank=(ro_address-16'hA000)>>11;
 wire [8:0] payload_read_word=(ro_address&16'h07ff)>>2;
 wire [10:0] payload_read_address=(payload_read_bank*11'd512)+(payload_read_word-9'd16);
 wire payload_read_enable=ro_address>=16'hA000&&ro_address<16'hB800&&
  payload_read_word>=16&&payload_read_word<16+16*ROI_LIMIT;
 wire [31:0] payload_read_data;
 generate if(PAYLOAD_BRAM)begin:payload_block
  (* ram_style="block" *) reg [31:0] mem[0:1535];
  reg [31:0] q;
  assign payload_read_data=q;
  always @(posedge aclk)begin
   if(payload_write)mem[payload_address]<=publish_data;
   if(payload_read_enable)q<=mem[payload_read_address];
  end
 end else begin:payload_distributed
  (* ram_style="distributed" *) reg [31:0] mem[0:1535];
  assign payload_read_data=mem[payload_read_address];
  always @(posedge aclk)if(payload_write)mem[payload_address]<=publish_data;
 end endgenerate
 always @*begin
  ro_data=0;read_bank=0;read_word=0;
  if(ro_address>=16'hA000&&ro_address<16'hB800)begin
   read_bank=(ro_address-16'hA000)>>11;read_word=(ro_address&16'h07ff)>>2;
   if(read_word<16)ro_data=descriptor[read_bank*16+read_word];
   else if(read_word<16+16*ROI_LIMIT)ro_data=payload_read_data;
  end
  if(FUSION_ENABLE)case(ro_address)
   16'h0080:ro_data=32'h44470101;
   16'h0084:ro_data=debug_frame;16'h0088:ro_data=debug_raw;
   16'h008C:ro_data=debug_clusters;16'h0090:ro_data=debug_result;
   default:begin end
  endcase
  if(ro_address>=16'h0100&&ro_address<16'h0200)begin
   case(ro_address)
    16'h0100:ro_data=IOU_UNION?32'h524f4902:32'h524f4901;
    16'h0104:ro_data={29'd0,(WEIGHTED_SCORE!=0),(IOU_DEDUP!=0),(FINDER_DEDUP!=0)};
    16'h0108:ro_data=SCORE_MIN;
    16'h010C:ro_data=1;16'h0110:ro_data=2;16'h0114:ro_data=1;
    16'h0118:ro_data=5;16'h011C:ro_data=4;16'h0120:ro_data=2;16'h0124:ro_data=5;
    16'h0128:ro_data=selection_generation;16'h012C:ro_data=debug_frame;
    16'h0130:ro_data=selection_epoch;16'h0134:ro_data=selection_elapsed;16'h0138:ro_data=group_snapshot;
    16'h01C0:ro_data=IOU_UNION?32'h00000007:0; // enabled, strict comparison, bridge guard
    16'h01C4:ro_data=merge_snapshot;16'h01C8:ro_data=absorbed_snapshot;
    16'h01CC:ro_data=rescan_snapshot;16'h01D0:ro_data=members_snapshot;
    default:begin
     if(ro_address>=16'h0140&&ro_address<16'h0180)ro_data=stat_snapshot[(ro_address-16'h0140)>>2];
     if(ro_address>=16'h0180&&ro_address<16'h01C0)ro_data=hist_snapshot[(ro_address-16'h0180)>>2];
    end
   endcase
  end
  cluster_read_address=0;
  case(state)
   LOAD_WAIT:cluster_read_address=claddr(FUSION_ENABLE&&(process_bank?raw1_q[65]:raw0_q[65]),0);
   MATCH:cluster_read_address=claddr(raw_branch,match_index+1'b1);
   AVERAGE_LOAD:cluster_read_address=claddr(average_branch,average_index>=averaging_count?0:average_index);
   F_AVG_SWITCH:cluster_read_address=claddr(average_branch,0);
   AVERAGE_STORE:cluster_read_address=claddr(average_branch,average_index+1'b1);
   F_A_READ,F_MA_READ:cluster_read_address=claddr(0,fi);
   F_B_READ,F_MB_READ,F_AB_READ:cluster_read_address=claddr(1,fj);
   CENTER_LOAD:cluster_read_address=0;
   NEIGHBOR:cluster_read_address=neighbor_index[CL_AW-1:0];
   NEIGHBOR_CHECK,NEIGHBOR_REPLACE:cluster_read_address=neighbor_index+1'b1;
   NEIGHBOR_DRAIN:cluster_read_address=neighbor_id[0][CL_AW-1:0];
   TRI_READ1:cluster_read_address=(neighbor_count<2||pair_i>=neighbor_count-1)?
    center_index+1'b1:neighbor_id[pair_j][CL_AW-1:0];
   TRI_CHECK:cluster_read_address=(pair_j>=neighbor_count-1)?
    neighbor_id[pair_i+1'b1][CL_AW-1:0]:neighbor_id[pair_i][CL_AW-1:0];
   TRI_QWAIT,SELECT_NEW_START,SELECT_NEW_WAIT,SELECT_DONE,SAVE:cluster_read_address=neighbor_id[pair_i][CL_AW-1:0];
   default:cluster_read_address=0;
  endcase
  cluster_write_enable=0;cluster_write_address=0;cluster_write_data=0;
  if(state==ADD)begin
   if(found_match)begin
    cluster_write_enable=1;cluster_write_address=claddr(raw_branch,best_match);cluster_write_data=best_record;
    cluster_write_data[15:0]=(fx(best_record)*32'd3+rx+2)>>2;
    cluster_write_data[31:16]=(fy(best_record)*32'd3+ry+2)>>2;
    cluster_write_data[47:32]=(fm(best_record)*32'd3+rm+2)>>2;
    cluster_write_data[79:48]=best_record[79:48]+rx;
    cluster_write_data[111:80]=best_record[111:80]+ry;
    cluster_write_data[143:112]=best_record[143:112]+rm;
    cluster_write_data[156:144]=fh(best_record)+13'd1;
    cluster_write_data[158:157]=fd(best_record)|(rd?2'b10:2'b01);
    cluster_write_data[190:159]=ferr(best_record)+re;
   end else if(current_count<CLUSTER_LIMIT)begin
    cluster_write_enable=1;cluster_write_address=claddr(raw_branch,current_count);
    cluster_write_data={{16'b0,re},(rd?2'b10:2'b01),13'd1,{16'b0,rm},{16'b0,ry},{16'b0,rx},rm,ry,rx};
   end
  end else if(state==AVERAGE_STORE)begin
   cluster_write_enable=1;cluster_write_address=claddr(average_branch,average_index);cluster_write_data=average_record;
  end
  if(state==F_STORE)begin
   cluster_write_enable=1;cluster_write_address=claddr(0,fi);cluster_write_data=fusion_record;
  end
  if(state==F_AB_STORE&&cluster_count<CLUSTER_LIMIT)begin
   cluster_write_enable=1;cluster_write_address=claddr(0,cluster_count);cluster_write_data=fb_record;
  end
  abs_dot=dot<0?-dot:dot;norm_min=norm_u<norm_v?norm_u:norm_v;norm_max=norm_u>norm_v?norm_u:norm_v;
  module_min=fm(c0);module_max=fm(c0);
  if(fm(c1)<module_min)module_min=fm(c1);if(fm(c2)<module_min)module_min=fm(c2);
  if(fm(c1)>module_max)module_max=fm(c1);if(fm(c2)>module_max)module_max=fm(c2);
  base_triangle_ok=norm_u!=0&&norm_v!=0&&
   ({4'b0,mul_acc0}<<4)<={4'b0,mul_acc1}&&
   ({4'b0,norm_min}<<4)>=39'd9*norm_max&&
   10*geom_module_min>=7*geom_module_max&&{norm_min,16'b0}>=leg_lower_bound&&{norm_max,16'b0}<=leg_upper_bound;
  // The original 190 bound remains authoritative in generic mode.
  scale_ok=1'b1;
  if(LEG_MAX_MODULES==32)scale_ok={norm_max,16'b0}<=({32'd0,max_module_square}<<10);
  else if(LEG_MAX_MODULES==64)scale_ok={norm_max,16'b0}<=({32'd0,max_module_square}<<12);
  triangle_ok=base_triangle_ok&&scale_ok;
  triple_hits=fh(c0)+fh(c1)+fh(c2);triple_error=ferr(c0)+ferr(c1)+ferr(c2);
  score_error=triple_error>36'h3fffffff ? 30'h3fffffff : triple_error[29:0];
  direction_score=(fd(c0)==3)+(fd(c1)==3)+(fd(c2)==3);
  triangle_score={12'b0,direction_score,triple_hits,~abs_dot[31:0],~(norm_max[31:0]-norm_min[31:0]),~score_error};
  sorted0=id0;sorted1=id1;sorted2=id2;tmp_id=0;
  if(sorted0>sorted1)begin tmp_id=sorted0;sorted0=sorted1;sorted1=tmp_id;end
  if(sorted1>sorted2)begin tmp_id=sorted1;sorted1=sorted2;sorted2=tmp_id;end
  if(sorted0>sorted1)begin tmp_id=sorted0;sorted0=sorted1;sorted1=tmp_id;end
  p3x=$signed({1'b0,fx(c1)})+$signed({1'b0,fx(c2)})-$signed({1'b0,fx(c0)});
  p3y=$signed({1'b0,fy(c1)})+$signed({1'b0,fy(c2)})-$signed({1'b0,fy(c0)});
  bbox_minx=fx(c0);bbox_maxx=fx(c0);bbox_miny=fy(c0);bbox_maxy=fy(c0);
  if($signed({1'b0,fx(c1)})<bbox_minx)bbox_minx=fx(c1);if($signed({1'b0,fx(c2)})<bbox_minx)bbox_minx=fx(c2);
  if(p3x<bbox_minx)bbox_minx=p3x;if($signed({1'b0,fx(c1)})>bbox_maxx)bbox_maxx=fx(c1);
  if($signed({1'b0,fx(c2)})>bbox_maxx)bbox_maxx=fx(c2);if(p3x>bbox_maxx)bbox_maxx=p3x;
  if($signed({1'b0,fy(c1)})<bbox_miny)bbox_miny=fy(c1);if($signed({1'b0,fy(c2)})<bbox_miny)bbox_miny=fy(c2);
  if(p3y<bbox_miny)bbox_miny=p3y;if($signed({1'b0,fy(c1)})>bbox_maxy)bbox_maxy=fy(c1);
  if($signed({1'b0,fy(c2)})>bbox_maxy)bbox_maxy=fy(c2);if(p3y>bbox_maxy)bbox_maxy=p3y;
  padding=(12*module_max+255)>>8;if(padding<8)padding=8;
  bbox_minx=bbox_minx-$signed(padding);bbox_miny=bbox_miny-$signed(padding);
  bbox_maxx=bbox_maxx+$signed(padding)+1;bbox_maxy=bbox_maxy+$signed(padding)+1;
  case(mul_b0[1:0])0:mul_add0=0;1:mul_add0=mul_a0;2:mul_add0=mul_a0<<1;default:mul_add0=mul_three0;endcase
  case(mul_b1[1:0])0:mul_add1=0;1:mul_add1=mul_a1;2:mul_add1=mul_a1<<1;default:mul_add1=mul_three1;endcase
  publish_data=0;publish_roi=(publish_word-16)>>4;
  if(publish_word>=16&&publish_roi<roi_count)case(publish_word[3:0])
   0:publish_data={out_miny[publish_roi],out_minx[publish_roi]};1:publish_data={out_maxy[publish_roi],out_maxx[publish_roi]};
   2:publish_data=out_p0[publish_roi];3:publish_data=out_p1[publish_roi];4:publish_data=out_p2[publish_roi];
   5:publish_data={out_angle[publish_roi],out_module[publish_roi]};6:publish_data=out_hits[publish_roi];7:publish_data=out_flags[publish_roi];
   8:publish_data=WEIGHTED_SCORE?out_score[publish_roi][31:0]:0;
   9:publish_data=WEIGHTED_SCORE?out_parts[publish_roi]:0;
   10:publish_data=WEIGHTED_SCORE?(32'h53570100|{24'd0,out_direction[publish_roi]}):0;
   default:publish_data=0;
  endcase
 end
 always @(posedge aclk)begin
  if(!aresetn)begin
   merge_work<=0;absorbed_work<=0;rescan_work<=0;members_work<=0;
   merge_snapshot<=0;absorbed_snapshot<=0;rescan_snapshot<=0;members_snapshot<=0;
   selection_generation<=0;selection_epoch<=0;selection_elapsed<=0;group_work<=0;group_snapshot<=0;
   for(stat_i=0;stat_i<16;stat_i=stat_i+1)begin stat_work[stat_i]<=0;stat_snapshot[stat_i]<=0;hist_work[stat_i]<=0;hist_snapshot[stat_i]<=0;end
   state<=IDLE;raw_used<=0;raw_ready<=0;capture_active<=0;capture_bank<=0;process_bank<=0;
   drop_active<=0;drop_pending<=0;process_drop<=0;cluster_count<=0;roi_count<=0;elapsed<=0;
   raw_branch<=0;average_branch<=0;diagonal_count<=0;fi<=0;fj<=0;fusion_a_count<=0;fusion_matched<=0;
   raw_axis_count<=0;raw_diagonal_count<=0;a_found<=0;b_found<=0;a_tie<=0;b_tie<=0;b_merged<=0;
   debug_frame<=0;debug_raw<=0;debug_clusters<=0;debug_result<=0;
   match_index<=0;center_index<=0;neighbor_index<=0;pair_i<=0;pair_j<=0;work_result_bank<=0;publish_word<=0;
   m1_valid<=0;m2_valid<=0;diag_geom_pass<=0;diag_scale_reject<=0;
   for(i=0;i<2;i=i+1)begin raw_count[i]<=0;flags_meta[i]<=0;end
   for(i=0;i<48;i=i+1)descriptor[i]<=0;
   for(i=0;i<3;i=i+1)begin owner_seq[i]<=0;owner_epoch[i]<=0;generation[i]<=0;descriptor[i*16]<=1;end
   for(i=0;i<16;i=i+1)begin neighbor_dist[i]<=0;neighbor_id[i]<=0;end
  end else begin
   if(state==IDLE)begin
    group_work<=0;merge_work<=0;absorbed_work<=0;rescan_work<=0;members_work<=0;
    for(stat_i=0;stat_i<16;stat_i=stat_i+1)begin stat_work[stat_i]<=0;hist_work[stat_i]<=0;end
   end
   m1_valid<=0;m2_valid<=m1_valid;
   if(m1_valid)begin
    m_distance<=m_dx*m_dx+m_dy*m_dy;m_radius_square<=m_radius*m_radius;
    m_record2<=m_record1;m_id2<=m_id1;m_scale2<=m_scale1;
   end
   if(m2_valid&&m_scale2&&m_distance<=m_radius_square&&(!found_match||m_distance<best_distance))begin
    found_match<=1;best_match<=m_id2;best_distance<=m_distance;best_record<=m_record2;
   end
   if(frame_start)begin
    b=incoming_result_bank;generation[b]<=generation[b]+2;descriptor[b*16]<=generation[b]+3;
    owner_seq[b]<=frame_seq;owner_epoch[b]<=epoch;
    if(!raw_used[0]||!raw_used[1])begin
     capture_bank<=raw_used[0];capture_active<=1;drop_active<=0;raw_used[raw_used[0]]<=1;raw_ready[raw_used[0]]<=0;raw_count[raw_used[0]]<=0;
     seq_meta[raw_used[0]]<=frame_seq;epoch_meta[raw_used[0]]<=epoch;cfg_meta[raw_used[0]]<=config_seq;source_meta[raw_used[0]]<=threshold_source;
     width_meta[raw_used[0]]<=width;height_meta[raw_used[0]]<=height;threshold_meta[raw_used[0]]<=threshold;flags_meta[raw_used[0]]<=frame_error?FLAG_AXIS:0;
     grid_meta[raw_used[0]]<=threshold_metadata;
     result_bank_meta[raw_used[0]]<=incoming_result_bank;
    end else begin
     capture_active<=0;drop_active<=1;drop_seq<=frame_seq;drop_epoch<=epoch;drop_cfg<=config_seq;drop_source<=threshold_source;drop_threshold<=threshold;
     drop_grid<=threshold_metadata;
     drop_result_bank<=incoming_result_bank;
    end
   end
   if(capture_active&&cand_valid)begin
    if(raw_count[capture_bank]<RAW_LIMIT)raw_count[capture_bank]<=raw_count[capture_bank]+1;
    else flags_meta[capture_bank]<=flags_meta[capture_bank]|FLAG_RAW;
   end
   if(capture_active&&frame_end)begin
    capture_active<=0;raw_ready[capture_bank]<=1;
    if(frame_error)flags_meta[capture_bank]<=flags_meta[capture_bank]|FLAG_AXIS|((cand_valid&&raw_count[capture_bank]>=RAW_LIMIT)?FLAG_RAW:0);
   end
   if(drop_active&&frame_end)begin drop_active<=0;drop_pending<=1;end
   if(state!=IDLE&&state!=PUBLISH)elapsed<=elapsed+1;
   case(state)
    IDLE:if(drop_pending)begin
     drop_pending<=0;process_drop<=1;work_seq<=drop_seq;work_epoch<=drop_epoch;work_cfg<=drop_cfg;work_source<=drop_source;work_threshold<=drop_threshold;
     work_grid<=drop_grid;
     work_flags<=FLAG_AXIS|FLAG_RAW;work_raw_count<=0;work_result_bank<=drop_result_bank;roi_count<=0;cluster_count<=0;publish_word<=1;state<=PUBLISH;
     diag_geom_pass<=0;diag_scale_reject<=0;
    end else if(raw_ready!=0)begin
     process_drop<=0;process_bank<=!raw_ready[0];raw_ready[!raw_ready[0]]<=0;
     work_seq<=seq_meta[!raw_ready[0]];work_epoch<=epoch_meta[!raw_ready[0]];work_cfg<=cfg_meta[!raw_ready[0]];work_source<=source_meta[!raw_ready[0]];
     work_width<=width_meta[!raw_ready[0]];work_height<=height_meta[!raw_ready[0]];work_threshold<=threshold_meta[!raw_ready[0]];work_flags<=flags_meta[!raw_ready[0]];
     work_grid<=grid_meta[!raw_ready[0]];
     work_raw_count<=raw_count[!raw_ready[0]];work_result_bank<=result_bank_meta[!raw_ready[0]];
     raw_index<=0;cluster_count<=0;diagonal_count<=0;average_branch<=0;raw_branch<=0;raw_axis_count<=0;raw_diagonal_count<=0;roi_count<=0;elapsed<=0;state<=LOAD;
     diag_geom_pass<=0;diag_scale_reject<=0;
    end
    LOAD:if(raw_index>=work_raw_count||(work_flags&FLAG_AXIS)!=0)begin average_index<=0;average_branch<=0;state<=AVERAGE_LOAD;end else state<=LOAD_WAIT;
    LOAD_WAIT:begin {raw_branch,re,rd,rm,ry,rx}<=process_bank?raw1_q:raw0_q;
     if(FUSION_ENABLE&&(process_bank?raw1_q[65]:raw0_q[65]))raw_diagonal_count<=raw_diagonal_count+1;else raw_axis_count<=raw_axis_count+1;
     match_index<=0;found_match<=0;best_distance<=35'h7ffffffff;state<=MATCH;end
    MATCH:if(match_index>=current_count)state<=MATCH_DRAIN;
    else begin
     m1_valid<=1;m_dx<=$signed({1'b0,rx})-$signed({1'b0,fx(cluster_q)});m_dy<=$signed({1'b0,ry})-$signed({1'b0,fy(cluster_q)});
     m_radius<=cluster_radius(rm>fm(cluster_q)?rm:fm(cluster_q),FUSION_ENABLE&&raw_branch);
     m_record1<=cluster_q;m_id1<=match_index;m_scale1<=2*rm>=fm(cluster_q)&&2*fm(cluster_q)>=rm;match_index<=match_index+1;
    end
    MATCH_DRAIN:if(!m1_valid&&!m2_valid)state<=ADD;
    ADD:begin
     if(!found_match)begin
      if(current_count<CLUSTER_LIMIT)begin
       if(raw_branch)diagonal_count<=diagonal_count+1;else cluster_count<=cluster_count+1;
      end else work_flags<=work_flags|FLAG_CLUSTER;
     end
     raw_index<=raw_index+1;state<=LOAD;
    end
    AVERAGE_LOAD:if(average_index>=averaging_count)begin
     if(FUSION_ENABLE&&!average_branch&&diagonal_count!=0)begin average_branch<=1;average_index<=0;state<=F_AVG_SWITCH;end
     else if(FUSION_ENABLE)state<=F_BEGIN;
     else begin center_index<=0;state<=CENTER_LOAD;end
    end
    else begin average_record<=cluster_q;average_field<=0;state<=AVERAGE_SETUP;end
    AVERAGE_SETUP:begin
     div_numerator<=average_field==0?average_record[79:48]:average_field==1?average_record[111:80]:average_record[143:112];
     div_denominator<=fh(average_record);div_quotient<=0;div_remainder<=0;div_bit<=31;state<=DIVIDE;
    end
    DIVIDE:begin
     div_numerator<=div_numerator<<1;
     if(shifted_remainder>=div_denominator)begin div_remainder<=shifted_remainder-div_denominator;div_quotient<={div_quotient[30:0],1'b1};end
     else begin div_remainder<=shifted_remainder;div_quotient<={div_quotient[30:0],1'b0};end
     if(div_bit==0)begin
      if(average_field==0)average_record[15:0]<={div_quotient[14:0],shifted_remainder>=div_denominator};
      if(average_field==1)average_record[31:16]<={div_quotient[14:0],shifted_remainder>=div_denominator};
      if(average_field==2)average_record[47:32]<={div_quotient[14:0],shifted_remainder>=div_denominator};
      if(average_field==2)state<=WEIGHTED_SCORE?AVERAGE_QSTART:AVERAGE_STORE;else begin average_field<=average_field+1;state<=AVERAGE_SETUP;end
     end else div_bit<=div_bit-1;
    end
    AVERAGE_QSTART:state<=AVERAGE_QWAIT;
    AVERAGE_QWAIT:if(quality_done)begin
     average_record[198:191]<=quality_h;average_record[206:199]<=quality_e;
     average_record[207]<=average_branch;average_record[209:208]<=average_branch?2'b10:2'b01;
     if(FUSION_ENABLE&&average_branch)average_record[47:32]<=physical_module(fm(average_record));
     state<=AVERAGE_STORE;
    end
    AVERAGE_STORE:begin average_index<=average_index+1;state<=AVERAGE_LOAD;end
    F_AVG_SWITCH:state<=AVERAGE_LOAD;
    F_BEGIN:begin
     a_found<=0;b_found<=0;a_tie<=0;b_tie<=0;b_merged<=0;fi<=0;fj<=0;
     fusion_a_count<=cluster_count;fusion_matched<=0;
     state<=(cluster_count!=0&&diagonal_count!=0)?F_A_READ:F_APPEND;
    end
    F_A_READ:state<=F_A_LOAD;
    F_A_LOAD:begin fa_record<=cluster_q;fj<=0;state<=F_B_READ;end
    F_B_READ:state<=F_B_CALC;
    F_B_CALC:begin
     n_dx<=$signed({1'b0,fx(fa_record)})-$signed({1'b0,fx(cluster_q)});
     n_dy<=$signed({1'b0,fy(fa_record)})-$signed({1'b0,fy(cluster_q)});
     m_radius<=fusion_radius<2?10'd2:fusion_radius[9:0];
     fusion_scale<=2*fm(fa_record)>=fm(cluster_q)&&2*fm(cluster_q)>=fm(fa_record);
     state<=F_DIST;
    end
    F_DIST:begin n_distance<=n_dx*n_dx+n_dy*n_dy;m_radius_square<=m_radius*m_radius;state<=F_MATCH;end
    F_MATCH:begin
     if(fusion_scale&&n_distance<=m_radius_square)begin
      if(!a_found[fi]||n_distance<a_distance[fi])begin a_found[fi]<=1;a_distance[fi]<=n_distance;best_b[fi]<=fj;a_tie[fi]<=0;end
      else if(n_distance==a_distance[fi])a_tie[fi]<=1;
      if(!b_found[fj]||n_distance<b_distance[fj])begin b_found[fj]<=1;b_distance[fj]<=n_distance;best_a[fj]<=fi;b_tie[fj]<=0;end
      else if(n_distance==b_distance[fj])b_tie[fj]<=1;
     end
     if(fj+1>=diagonal_count)begin
      fj<=0;
      if(fi+1>=fusion_a_count)begin fi<=0;state<=F_MA_READ;end
      else begin fi<=fi+1;state<=F_A_READ;end
     end else begin fj<=fj+1;state<=F_B_READ;end
    end
    F_MA_READ:state<=F_MA_LOAD;
    F_MA_LOAD:begin
     fa_record<=cluster_q;fj<=best_b[fi];
     if(a_found[fi]&&!a_tie[fi]&&b_found[best_b[fi]]&&!b_tie[best_b[fi]]&&best_a[best_b[fi]]==fi)state<=F_MB_READ;
     else if(fi+1>=fusion_a_count)begin fj<=0;state<=F_APPEND;end
     else begin fi<=fi+1;state<=F_MA_READ;end
    end
    F_MB_READ:state<=F_MB_LOAD;
    F_MB_LOAD:begin fb_record<=cluster_q;state<=F_STORE;end
    F_STORE:begin
     b_merged[fj]<=1;fusion_matched<=fusion_matched+1;
     if(fi+1>=fusion_a_count)begin fj<=0;state<=F_APPEND;end
     else begin fi<=fi+1;state<=F_MA_READ;end
    end
    F_APPEND:if(fj>=diagonal_count)begin center_index<=0;state<=CENTER_LOAD;end
     else if(b_merged[fj])fj<=fj+1;
     else state<=F_AB_READ;
    F_AB_READ:state<=F_AB_LOAD;
    F_AB_LOAD:begin fb_record<=cluster_q;state<=F_AB_STORE;end
    F_AB_STORE:begin
     if(cluster_count<CLUSTER_LIMIT)cluster_count<=cluster_count+1;
     else work_flags<=work_flags|FLAG_CLUSTER;
     fj<=fj+1;state<=F_APPEND;
    end
    CENTER_LOAD:if(center_index>=cluster_count)begin publish_word<=1;state<=PUBLISH;end
    else begin c0<=cluster_q;id0<=center_index;neighbor_count<=0;neighbor_index<=0;state<=NEIGHBOR;for(i=0;i<16;i=i+1)neighbor_dist[i]<=35'h7ffffffff;end
    NEIGHBOR:if(neighbor_index>=cluster_count)state<=NEIGHBOR_DRAIN;
    else begin
     n_dx<=$signed({1'b0,fx(cluster_q)})-$signed({1'b0,fx(c0)});n_dy<=$signed({1'b0,fy(cluster_q)})-$signed({1'b0,fy(c0)});
     n_id1<=neighbor_index;n_qual1<=neighbor_index!=center_index&&10*fm(cluster_q)>=7*fm(c0)&&10*fm(c0)>=7*fm(cluster_q);
     state<=NEIGHBOR_CALC;
    end
    NEIGHBOR_CALC:begin n_distance<=n_dx*n_dx+n_dy*n_dy;state<=NEIGHBOR_CHECK;end
    NEIGHBOR_CHECK:if(n_qual1&&neighbor_count>=16)begin
     n_worst_distance<=neighbor_dist[0];worst_index<=0;select_index<=1;state<=NEIGHBOR_SELECT;
    end else begin
     if(n_qual1)begin neighbor_id[neighbor_count]<=n_id1;neighbor_dist[neighbor_count]<=n_distance;neighbor_count<=neighbor_count+1;end
     neighbor_index<=neighbor_index+1;state<=NEIGHBOR;
    end
    // Serial worst-distance search preserves the original lowest-slot tie
    // rule and removes the four-level wide comparator/mux feedback path.
    NEIGHBOR_SELECT:if(select_index>=16)state<=NEIGHBOR_REPLACE;
    else begin
     if(neighbor_dist[select_index]>n_worst_distance)begin n_worst_distance<=neighbor_dist[select_index];worst_index<=select_index;end
     select_index<=select_index+1;
    end
    NEIGHBOR_REPLACE:begin
     if(n_distance<n_worst_distance)begin neighbor_id[worst_index]<=n_id1;neighbor_dist[worst_index]<=n_distance;end
     neighbor_index<=neighbor_index+1;state<=NEIGHBOR;
    end
    NEIGHBOR_DRAIN:begin pair_i<=0;pair_j<=1;state<=TRI_READ1;end
    TRI_READ1:if(neighbor_count<2||pair_i>=neighbor_count-1)begin center_index<=center_index+1;state<=CENTER_LOAD;end
    else begin c1<=cluster_q;id1<=neighbor_id[pair_i];state<=TRI_READ2;end
    TRI_READ2:begin c2<=cluster_q;id2<=neighbor_id[pair_j];state<=TRI_VECTOR;end
    TRI_VECTOR:begin
     ux<=$signed({1'b0,fx(c1)})-$signed({1'b0,fx(c0)});uy<=$signed({1'b0,fy(c1)})-$signed({1'b0,fy(c0)});
     vx<=$signed({1'b0,fx(c2)})-$signed({1'b0,fx(c0)});vy<=$signed({1'b0,fy(c2)})-$signed({1'b0,fy(c0)});state<=TRI_NORM;
    end
    TRI_NORM:begin
     norm_u<=ux*ux+uy*uy;norm_v<=vx*vx+vy*vy;dot<=ux*vx+uy*vy;
     geom_module_min<=module_min;geom_module_max<=module_max;state<=TRI_MUL_SETUP;
    end
    TRI_MUL_SETUP:begin
     mul_a0<={35'd0,abs_dot};mul_b0<=abs_dot;mul_three0<=({35'd0,abs_dot}<<1)+abs_dot;
     mul_a1<={35'd0,norm_u};mul_b1<=norm_v;mul_three1<=({35'd0,norm_u}<<1)+norm_u;
     mul_acc0<=0;mul_acc1<=0;mul_step<=0;state<=TRI_MUL;
     min_module_square<=geom_module_min*geom_module_min;
     max_module_square<=geom_module_max*geom_module_max;
    end
    TRI_MUL:begin
     // 190^2 = 2^15+2^11+2^10+2^8+2^2. Each registered
     // stage has one carry-chain addition; all 48 product bits are retained.
     if(mul_step==0)begin
      leg_lower_bound<={26'd0,min_module_square,6'd0};
      bound_a<=({16'd0,max_module_square}<<15)+({16'd0,max_module_square}<<11);
      bound_b<=({16'd0,max_module_square}<<10)+({16'd0,max_module_square}<<8);
     end
     if(mul_step==1)bound_ab<=bound_a+bound_b;
     if(mul_step==2)leg_upper_bound<={16'd0,bound_ab}+({32'd0,max_module_square}<<2);
     mul_acc0<=mul_acc0+mul_add0;mul_acc1<=mul_acc1+mul_add1;
     mul_a0<=mul_a0<<2;mul_a1<=mul_a1<<2;mul_three0<=mul_three0<<2;mul_three1<=mul_three1<<2;
     mul_b0<=mul_b0>>2;mul_b1<=mul_b1>>2;
     if(mul_step==17)state<=TRI_CHECK;else mul_step<=mul_step+1;
    end
    TRI_CHECK:begin
     if(base_triangle_ok)begin
      diag_geom_pass<=diag_geom_pass+1'b1;
      if(!scale_ok)diag_scale_reject<=diag_scale_reject+1'b1;
     end
     if(pair_j>=neighbor_count-1)begin pair_i<=pair_i+1;pair_j<=pair_i+2;end else pair_j<=pair_j+1;
     if(triangle_ok)begin
      pending_score<=WEIGHTED_SCORE?128'd0:triangle_score;pending_id0<=sorted0;pending_id1<=sorted1;pending_id2<=sorted2;
      pending_dedup_module<=module_min;pending_module<=module_max;pending_hits<=triple_hits;pending_p0<={fy(c0),fx(c0)};pending_p1<={fy(c1),fx(c1)};pending_p2<={fy(c2),fx(c2)};
      pending_minx<=bbox_minx<0?0:bbox_minx;pending_miny<=bbox_miny<0?0:bbox_miny;
      pending_maxx<=bbox_maxx>work_width?work_width:bbox_maxx;pending_maxy<=bbox_maxy>work_height?work_height:bbox_maxy;
      pending_flags<=((bbox_minx<0||bbox_miny<0||bbox_maxx>work_width||bbox_maxy>work_height)?32'd1:32'd0) |
       (FUSION_ENABLE?(({31'd0,c0[207]}<<8)|({31'd0,c1[207]}<<9)|({31'd0,c2[207]}<<10)|
        ({30'd0,c0[209:208]}<<16)|({30'd0,c1[209:208]}<<18)|({30'd0,c2[209:208]}<<20)):32'd0);
      pending_ux<=ux;pending_uy<=uy;select_index<=0;worst_index<=0;worst_score<=out_score[0];duplicate_found<=0;state<=WEIGHTED_SCORE?TRI_QSTART:(NEW_SELECTION?SELECT_NEW_START:SELECT);
     end else state<=TRI_READ1;
    end
    TRI_QSTART:state<=TRI_QWAIT;
    TRI_QWAIT:if(quality_done)begin
     pending_score<={120'd0,quality_score};pending_parts<=quality_parts;pending_direction<=quality_direction;
     stat_work[0]<=stat_work[0]+1;hist_work[quality_score[7:4]]<=hist_work[quality_score[7:4]]+1;
     if(quality_score<SCORE_MIN)begin stat_work[1]<=stat_work[1]+1;state<=TRI_READ1;end
     else state<=NEW_SELECTION?SELECT_NEW_START:SELECT;
    end
    SELECT_NEW_START:begin
     pending_rank_key<=selector_candidate[200:136];pending_old_angle<=0;pending_absorbed<=0;pending_rescans<=0;
     state<=SELECT_NEW_WAIT;
    end
    SELECT_NEW_WAIT:if(selector_done)begin
     group_work<=group_work+selector_group_compares;
     stat_work[2]<=stat_work[2]+selector_finder_compares;
     stat_work[3]<=stat_work[3]+selector_iou_compares;
     stat_work[4]<=stat_work[4]+selector_no_intersection;
     stat_work[5]<=stat_work[5]+selector_cycles;
     if(selector_reason==1)stat_work[6]<=stat_work[6]+1;
     if(selector_reason==2)stat_work[7]<=stat_work[7]+1;
     if(selector_reason==3)stat_work[8]<=stat_work[8]+1;
     if(selector_reason==4)stat_work[9]<=stat_work[9]+1;
     if(selector_reason==5)stat_work[10]<=stat_work[10]+1;
     if(selector_reason==6)stat_work[11]<=stat_work[11]+1;
     if(selector_reason==5||selector_reason==6)work_flags<=work_flags|FLAG_ROI;
     if(selector_accept&&IOU_UNION&&!union_commit_time)begin
      work_flags<=work_flags|FLAG_TIMEOUT;roi_count<=0;publish_word<=1;state<=PUBLISH;
     end else if(selector_accept)begin
      if(IOU_UNION)begin
       {pending_minx,pending_miny,pending_maxx,pending_maxy}<=selector_box;
       pending_flags[0]<=selector_clipped;
       pending_absorbed<=selector_absorbed;pending_rescans<=selector_rescans;
       if(selector_representative<roi_count)begin
        pending_rank_key<=out_rank_key[selector_representative];
        pending_p0<=out_p0[selector_representative];pending_p1<=out_p1[selector_representative];pending_p2<=out_p2[selector_representative];
        pending_module<=out_module[selector_representative];pending_dedup_module<=out_dedup_module[selector_representative];
        pending_score<=out_score[selector_representative];pending_hits<=out_hits[selector_representative];
        pending_flags<={out_flags[selector_representative][31:1],selector_clipped};
        pending_parts<=out_parts[selector_representative];pending_direction<=out_direction[selector_representative];
        pending_id0<=out_id0[selector_representative];pending_id1<=out_id1[selector_representative];pending_id2<=out_id2[selector_representative];
        pending_old_angle<=1;pending_saved_angle<=out_angle[selector_representative];
       end
      end
      pending_cached_area<=selector_area;
      save_index<=selector_slot;
      if(pending_ux<0)begin angle_x<=-(pending_ux<<<12);angle_y<=-(pending_uy<<<12);angle_acc<=pending_uy<0?-32768:32768;end
      else begin angle_x<=pending_ux<<<12;angle_y<=pending_uy<<<12;angle_acc<=0;end
      angle_step<=0;
      if((selector_remove&(selector_remove-1'b1))!=0)begin
       commit_mask<=selector_remove;compact_read<=0;compact_write<=0;state<=COMPACT;
      end else state<=ANGLE;
     end else state<=TRI_READ1;
    end
    COMPACT:if(compact_read>=roi_count)begin
     roi_count<=compact_write;save_index<=compact_write;state<=ANGLE;
    end else begin
     if(!commit_mask[compact_read])begin
      compact_write<=compact_write+1;
     end
     compact_read<=compact_read+1;
    end
    SELECT:if(select_index>=roi_count)state<=SELECT_DONE;
    else begin
     if(out_id0[select_index]==pending_id0&&out_id1[select_index]==pending_id1&&out_id2[select_index]==pending_id2)duplicate_found<=1;
     if(out_score[select_index]<worst_score)begin worst_score<=out_score[select_index];worst_index<=select_index;end
     select_index<=select_index+1;
    end
    SELECT_DONE:if(duplicate_found)state<=TRI_READ1;
    else if(roi_count<ROI_LIMIT||pending_score>worst_score)begin
     save_index<=roi_count<ROI_LIMIT?roi_count:worst_index;
     if(pending_ux<0)begin angle_x<=-(pending_ux<<<12);angle_y<=-(pending_uy<<<12);angle_acc<=pending_uy<0?-32768:32768;end
     else begin angle_x<=pending_ux<<<12;angle_y<=pending_uy<<<12;angle_acc<=0;end
     angle_step<=0;state<=ANGLE;if(roi_count>=ROI_LIMIT)work_flags<=work_flags|FLAG_ROI;
    end else begin work_flags<=work_flags|FLAG_ROI;state<=TRI_READ1;end
    ANGLE:begin
     if(angle_y>=0)begin angle_x<=angle_x+(angle_y>>>angle_step);angle_y<=angle_y-(angle_x>>>angle_step);angle_acc<=angle_acc+$signed({1'b0,atan_turn(angle_step)});end
     else begin angle_x<=angle_x-(angle_y>>>angle_step);angle_y<=angle_y+(angle_x>>>angle_step);angle_acc<=angle_acc-$signed({1'b0,atan_turn(angle_step)});end
     if(angle_step==15)state<=SAVE;else angle_step<=angle_step+1;
    end
    SAVE:begin
     if(IOU_UNION&&pending_absorbed!=0)begin
      merge_work<=merge_work+1;absorbed_work<=absorbed_work+pending_absorbed;rescan_work<=rescan_work+pending_rescans;
      if(pending_absorbed+1>members_work)members_work<=pending_absorbed+1;
     end
     if(save_index==roi_count&&roi_count<ROI_LIMIT)roi_count<=roi_count+1;state<=TRI_READ1;
    end
    PUBLISH:if(!owner_matches||new_same_bank)begin if(!process_drop)raw_used[process_bank]<=0;state<=IDLE;end
    else if(publish_word==0)begin descriptor[work_result_bank*16]<=generation[work_result_bank]+2;
     merge_snapshot<=merge_work;absorbed_snapshot<=absorbed_work;rescan_snapshot<=rescan_work;members_snapshot<=members_work;
     selection_generation<=selection_generation+2;selection_epoch<=work_epoch;selection_elapsed<=elapsed;group_snapshot<=group_work;
     for(stat_i=0;stat_i<16;stat_i=stat_i+1)begin stat_snapshot[stat_i]<=stat_work[stat_i];hist_snapshot[stat_i]<=hist_work[stat_i];end
     stat_snapshot[12]<=roi_count;stat_snapshot[13]<=work_flags;stat_snapshot[14]<=work_raw_count;stat_snapshot[15]<=cluster_count;
     debug_frame<=work_seq;debug_raw<={3'd0,raw_diagonal_count,3'd0,raw_axis_count};
     debug_clusters<={16'd0,diagonal_count,fusion_a_count};debug_result<={16'd0,cluster_count,fusion_matched};if(!process_drop)raw_used[process_bank]<=0;state<=IDLE;end
    else begin
     b=work_result_bank*16+publish_word;
     if(publish_word<16)case(publish_word)
      1:descriptor[b]<=work_epoch;2:descriptor[b]<=work_seq;3:descriptor[b]<=work_cfg;4:descriptor[b]<=roi_count;
      5:descriptor[b]<=work_flags|FLAG_COMPLETE;6:descriptor[b]<={24'b0,work_threshold};7:descriptor[b]<=work_source;
      8:descriptor[b]<=work_raw_count;9:descriptor[b]<=cluster_count;
      10:descriptor[b]<=work_grid[31:0];11:descriptor[b]<=work_grid[63:32];
      12:descriptor[b]<=work_grid[95:64];13:descriptor[b]<=work_grid[127:96];
      14:descriptor[b]<={diag_scale_reject,diag_geom_pass};
      15:descriptor[b]<=32'h53430000|LEG_MAX_MODULES;default:descriptor[b]<=0;
     endcase
     if(publish_word==16+16*ROI_LIMIT-1)publish_word<=0;else publish_word<=publish_word+1;
    end
    default:state<=IDLE;
   endcase
   // Timeout wins over next-state assignments, as in the original protocol.
   if(state!=IDLE&&state!=PUBLISH&&elapsed>=POST_CYCLES-1)begin work_flags<=work_flags|FLAG_TIMEOUT;roi_count<=0;publish_word<=1;state<=PUBLISH;end
  end
 end
endmodule

// Exact round(255*num/den), saturated to [0,255]. One shared subtract
// chain; eight quotient bits, no combinational variable divider.
module qr_quality_ratio_u8(
 input wire clk,rstn,start,input wire [69:0] num,den,
 output reg done,output reg [7:0] value
);
 reg [1:0] state;reg [69:0] n,d;reg [78:0] remainder,divisor;
 reg [7:0] quotient;reg [2:0] bit_index;
 wire [79:0] trial={1'b0,remainder}-{1'b0,divisor};
 always @(posedge clk)begin
  if(!rstn)begin state<=0;done<=0;value<=0;n<=0;d<=0;remainder<=0;divisor<=0;quotient<=0;bit_index<=0;end
  else begin
   done<=0;
   case(state)
    0:if(start)begin
     if(den==0||num==0)begin value<=0;done<=1;end
     else if(num>=den)begin value<=255;done<=1;end
     else begin n<=num;d<=den;state<=1;end
    end
    1:begin remainder<=({1'b0,n,8'd0}-{9'd0,n});divisor<={2'd0,d,7'd0};state<=2;end
    2:begin remainder<=remainder+{9'd0,(d>>1)};quotient<=0;bit_index<=7;state<=3;end
    3:begin
     quotient[bit_index]<=!trial[79];
     if(!trial[79])remainder<=trial[78:0];
     divisor<=divisor>>1;
     if(bit_index==0)begin value<={quotient[7:1],!trial[79]};done<=1;state<=0;end
     else bit_index<=bit_index-1'b1;
    end
   endcase
  end
 end
endmodule

// mode=0: cache finder H/E. mode=1: score a geometrically accepted triple.
// A/B/E/H use equal weight 30, D weight 8, divisor 128.
module qr_roi_quality(
 input wire clk,rstn,start,mode,
 input wire [12:0] hits,input wire [15:0] module_q8,input wire [31:0] error_sum,
 input wire finder_diagonal,
 input wire [69:0] dot_square,norm_product,
 input wire [34:0] norm_min,norm_max,
 input wire [9:0] sum_h,sum_e,input wire [3:0] directions,
 output reg done,output reg [7:0] finder_h,finder_e,score,
 output reg [31:0] parts,output reg [7:0] direction_quality
);
 localparam IDLE=0,F_DEN0=1,F_DEN1=2,R_START=3,R_WAIT=4,T_BNUM=5,
  F_FINISH=6,T_SUM=7,T_WEIGHT=8,T_TOTAL=9,T_FINISH=10;
 reg [3:0] state;reg [1:0] phase;
 reg [28:0] hm;reg [34:0] eden_partial,eden;
 reg [40:0] ferr_scaled;reg [20:0] hnum;reg [19:0] hden;
 reg [34:0] ndiff;reg [38:0] bden,bnum;
 reg [69:0] rnum,rden;
 wire rdone;wire [7:0] rval;
 reg [7:0] qa,qb,qh,qe,qd;
 reg [9:0] qsum;reg [14:0] w30,total;
 qr_quality_ratio_u8 ratio(.clk(clk),.rstn(rstn),.start(state==R_START),
  .num(rnum),.den(rden),.done(rdone),.value(rval));
 always @(posedge clk)begin
  if(!rstn)begin
   state<=IDLE;done<=0;finder_h<=0;finder_e<=0;score<=0;parts<=0;direction_quality<=0;
   hm<=0;eden_partial<=0;eden<=0;ferr_scaled<=0;hnum<=0;hden<=0;ndiff<=0;bden<=0;bnum<=0;
   rnum<=0;rden<=0;phase<=0;qa<=0;qb<=0;qh<=0;qe<=0;qd<=0;qsum<=0;w30<=0;total<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(start)begin
     if(!mode)begin
      hm<=hits*module_q8;ferr_scaled<={error_sum,9'd0};
      hnum<={hits,8'd0};hden<=({3'd0,module_q8}<<2)+({3'd0,module_q8}<<1);
      if(finder_diagonal)hden<=({3'd0,module_q8}<<3)+({3'd0,module_q8}<<2);
      state<=F_DEN0;
     end else begin
      // Accepted triples guarantee dot_square*16 <= norm_product.
      rnum<=norm_product-(dot_square<<4);rden<=norm_product;
      ndiff<=norm_max-norm_min;bden<=({4'd0,norm_max}<<3)-{4'd0,norm_max};
      qh<=(sum_h+10'd1)/10'd3;qe<=(sum_e+10'd1)/10'd3;
      qd<=directions*8'd85;phase<=2;state<=T_BNUM;
     end
    end
    F_DEN0:begin eden_partial<=({6'd0,hm}<<5)+({6'd0,hm}<<4);state<=F_DEN1;end
    F_DEN1:begin eden<=eden_partial+{6'd0,hm};rnum<=hnum;rden<=hden;phase<=0;state<=R_START;end
    T_BNUM:begin bnum<=bden-({4'd0,ndiff}<<4);state<=R_START;end
    R_START:state<=R_WAIT;
    R_WAIT:if(rdone)begin
     case(phase)
      0:begin
       finder_h<=rval;
       rnum<=({6'd0,eden}>ferr_scaled)?({6'd0,eden}-ferr_scaled):41'd0;
       rden<=eden;phase<=1;state<=R_START;
      end
      1:begin finder_e<=rval;state<=F_FINISH;end
      2:begin qa<=rval;rnum<=bnum;rden<=bden;phase<=3;state<=R_START;end
      3:begin qb<=rval;state<=T_SUM;end
     endcase
    end
    F_FINISH:begin done<=1;state<=IDLE;end
    T_SUM:begin qsum<={2'd0,qa}+{2'd0,qb}+{2'd0,qe}+{2'd0,qh};state<=T_WEIGHT;end
    T_WEIGHT:begin w30<=({5'd0,qsum}<<5)-({5'd0,qsum}<<1);state<=T_TOTAL;end
    T_TOTAL:begin total<=w30+({7'd0,qd}<<3)+15'd64;state<=T_FINISH;end
    T_FINISH:begin score<=total[14:7];parts<={qh,qe,qb,qa};direction_quality<=qd;done<=1;state<=IDLE;end
   endcase
  end
 end
endmodule
