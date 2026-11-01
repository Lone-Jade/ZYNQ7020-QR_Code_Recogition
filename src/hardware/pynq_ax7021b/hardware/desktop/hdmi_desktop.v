`default_nettype none
`timescale 1ns/1ps
// Fixed 720p60 sink. A frame is consumed only from a correctly aligned SOF.
module hdmi_desktop (
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis, ASSOCIATED_RESET resetn, FREQ_HZ 74250000" *)
    input wire pixel_clk,
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *) input wire resetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TDATA" *) input wire [15:0] s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TVALID" *) input wire s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TREADY" *) output wire s_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TUSER" *) input wire s_axis_tuser,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TLAST" *) input wire s_axis_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TKEEP" *) input wire [1:0] s_axis_tkeep,
    output reg [15:0] raw_rgb,
    output reg [10:0] raw_x,output reg [9:0] raw_y,
    output reg raw_de, raw_hs, raw_vs,output reg raw_frame_start,
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 74250000" *) output wire hdmi_clk
);
    reg [10:0] h = 0;
    reg [9:0] v = 0;
    reg locked = 0;
    wire active = h < 1280 && v < 720;
    wire origin = h == 0 && v == 0;
    assign s_axis_tready = locked ? active : (s_axis_tuser ? origin : 1'b1);
    // Forward using ODDR for a clock on dedicated output resources.
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) clock_out (
        .Q(hdmi_clk), .C(pixel_clk), .CE(1'b1), .D1(1'b0), .D2(1'b1), .R(1'b0), .S(1'b0));
    always @(posedge pixel_clk) begin
        if (!resetn) begin
            h <= 0; v <= 0; locked <= 0;
            raw_frame_start<=0;raw_x<=0;raw_y<=0;raw_rgb <= 0; raw_de <= 0; raw_hs <= 0; raw_vs <= 0;
        end else begin
            raw_frame_start<=0;raw_x<=h;raw_y<=v;raw_de <= active;
            raw_hs <= h >= 1390 && h < 1430;
            raw_vs <= v >= 725 && v < 730;
            raw_rgb <= 0;
            if (active && locked && !s_axis_tvalid) locked <= 0;
            if (s_axis_tvalid && s_axis_tready) begin
                if ((locked || (s_axis_tuser && origin)) && active) begin
                    if (s_axis_tlast != (h == 1279) || s_axis_tkeep != 2'b11 ||
                        (locked && s_axis_tuser)) locked <= 0;
                    else begin
                        // Board byte lanes: low byte is red, high byte is blue.
                        raw_rgb <= s_axis_tdata;raw_frame_start<=s_axis_tuser&&origin;
                        locked <= !(h == 1279 && v == 719);
                    end
                end
            end
            if (h == 1649) begin
                h <= 0;
                v <= v == 749 ? 0 : v + 1'b1;
            end else h <= h + 1'b1;
        end
    end
endmodule

`default_nettype wire
