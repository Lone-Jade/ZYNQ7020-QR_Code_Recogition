`timescale 1ns/1ps
// Disjoint, equal-area sampling windows. Coordinates scale with frame size.
// At 1280x720 each window is 300x200; larger centre is 640x360.
module qr_sample_windows(
 input wire [15:0] x,y,width,height,
 output wire centre_selected,output wire [4:0] selected
);
 wire [31:0] xx=x*32'd1280, yy=y*32'd720;
 wire left_sel=xx>=width*32'd100 && xx<width*32'd400;
 wire right_sel=xx>=width*32'd800 && xx<width*32'd1100;
 wire top_sel=yy>=height*32'd40 && yy<height*32'd240;
 wire bottom_sel=yy>=height*32'd400 && yy<height*32'd600;
 assign selected[0]=left_sel&&top_sel;
 assign selected[1]=right_sel&&top_sel;
 assign selected[2]=left_sel&&bottom_sel;
 assign selected[3]=right_sel&&bottom_sel;
 assign selected[4]=xx>=width*32'd450&&xx<width*32'd750&&
                    yy>=height*32'd220&&yy<height*32'd420;
 assign centre_selected=({16'd0,x}<<2)>=width&&({16'd0,x}<<2)<width*32'd3&&
                        ({16'd0,y}<<2)>=height&&({16'd0,y}<<2)<height*32'd3;
endmodule
