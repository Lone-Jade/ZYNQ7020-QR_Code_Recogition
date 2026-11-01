`timescale 1ns/1ps
// Uniform threshold experiments. Source tags and raw node values are retained.
// MODE 1: large centre; 2: five-window union; 4: mean of five independent Otsus.
module qr_otsu_sampled #(parameter integer MODE=1)(
 input wire aclk,aresetn,frame_start,frame_end,frame_error,pixel_valid,
 input wire [7:0] gray,input wire [15:0] x,y,width,height,
 input wire [31:0] frame_seq,config_seq,
 output wire result_valid,output wire [7:0] result_threshold,
 output wire [71:0] result_thresholds,output wire [8:0] result_mask,
 output wire [31:0] result_frame,result_config
);
 generate if(MODE==1||MODE==2)begin:uniform
  wire centre_selected;wire [4:0] selected;wire [7:0] scalar;
  qr_sample_windows windows(.x(x),.y(y),.width(width),.height(height),
   .centre_selected(centre_selected),.selected(selected));
  qr_otsu_threshold solver(.aclk(aclk),.aresetn(aresetn),.frame_start(frame_start),
   .frame_end(frame_end),.frame_error(frame_error),.pixel_valid(pixel_valid),
   .stat_selected(MODE==1?centre_selected:|selected),.gray(gray),
   .frame_seq(frame_seq),.config_seq(config_seq),.result_valid(result_valid),
   .result_threshold(scalar),.result_frame(result_frame),.result_config(result_config));
  assign result_threshold=scalar;
  assign result_thresholds={9{scalar}};
  assign result_mask=9'h1ff;
 end else begin:mean_five
  wire valid;wire [71:0] nodes;wire [8:0] mask;
  wire [10:0] total={3'd0,nodes[7:0]}+{3'd0,nodes[15:8]}+
   {3'd0,nodes[23:16]}+{3'd0,nodes[31:24]}+{3'd0,nodes[39:32]};
  qr_otsu_five solver(.aclk(aclk),.aresetn(aresetn),.frame_start(frame_start),
   .frame_end(frame_end),.frame_error(frame_error),.pixel_valid(pixel_valid),
   .gray(gray),.x(x),.y(y),.width(width),.height(height),.frame_seq(frame_seq),
   .config_seq(config_seq),.result_valid(valid),.result_thresholds(nodes),
   .result_mask(mask),.result_frame(result_frame),.result_config(result_config));
  // An incomplete set must not change its composition from frame to frame.
  // Retain the preceding valid whole group (manual 200 before first result).
  assign result_valid=valid&&mask[4:0]==5'b11111;
  assign result_threshold=(total+11'd2)/11'd5; // nearest integer
  assign result_thresholds=nodes;
  assign result_mask=mask;
 end endgenerate
endmodule
