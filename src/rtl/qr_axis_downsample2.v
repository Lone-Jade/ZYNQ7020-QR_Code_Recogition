`timescale 1ns/1ps

/* Streaming 2x2 box-filter downsampler for Gray8 AXI video.
 *
 * Every four source pixels produce one averaged output pixel.  The first
 * source row of each pair is retained as horizontal pair sums; the second
 * row completes the average.  This keeps arbitrary-position and rotated QR
 * structure while reducing the software detector's pixel load by 4x. */
module qr_axis_downsample2 #(
    parameter integer INPUT_WIDTH  = 800,
    parameter integer INPUT_HEIGHT = 600,
    parameter integer MAX_WIDTH    = 1280,
    parameter integer ENABLE_DOWNSAMPLE = 1
) (
    input  wire       aclk,
    input  wire       aresetn,
    input  wire [7:0] s_axis_tdata,
    input  wire       s_axis_tkeep,
    input  wire       s_axis_tvalid,
    output wire       s_axis_tready,
    input  wire       s_axis_tuser,
    input  wire       s_axis_tlast,
    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tkeep,
    output wire       m_axis_tvalid,
    input  wire       m_axis_tready,
    output wire       m_axis_tuser,
    output wire       m_axis_tlast
);
    generate if (ENABLE_DOWNSAMPLE == 0) begin : gen_full_resolution
        // Experiment mode: preserve every Gray8 pixel and AXI video boundary.
        assign s_axis_tready = m_axis_tready;
        assign m_axis_tdata = s_axis_tdata;
        assign m_axis_tkeep = s_axis_tkeep;
        assign m_axis_tvalid = s_axis_tvalid;
        assign m_axis_tuser = s_axis_tuser;
        assign m_axis_tlast = s_axis_tlast;
    end else begin : gen_box_downsample
    localparam integer X_BITS = $clog2(MAX_WIDTH);
    localparam integer Y_BITS = 16;

    reg [8:0] first_row_pair_sum [0:(MAX_WIDTH/2)-1];
    reg [7:0] horizontal_first;
    reg [X_BITS-1:0] x_count;
    reg [Y_BITS-1:0] y_count;
    reg [7:0] out_data;
    reg out_valid;
    reg out_user;
    reg out_last;

    wire output_slot_free = !out_valid || m_axis_tready;
    wire input_fire = s_axis_tvalid && s_axis_tready;
    wire [X_BITS-1:0] sample_x = s_axis_tuser ? {X_BITS{1'b0}} : x_count;
    wire [Y_BITS-1:0] sample_y = s_axis_tuser ? {Y_BITS{1'b0}} : y_count;
    wire [8:0] horizontal_pair = {1'b0, horizontal_first} +
                                 {1'b0, s_axis_tdata};
    wire [10:0] box_sum = {2'b00, first_row_pair_sum[sample_x >> 1]} +
                          {2'b00, horizontal_pair};

    assign s_axis_tready = output_slot_free;
    assign m_axis_tdata = out_data;
    assign m_axis_tkeep = 1'b1;
    assign m_axis_tvalid = out_valid;
    assign m_axis_tuser = out_user;
    assign m_axis_tlast = out_last;

    always @(posedge aclk) begin
        if (!aresetn) begin
            horizontal_first <= 8'd0;
            x_count <= {X_BITS{1'b0}};
            y_count <= {Y_BITS{1'b0}};
            out_data <= 8'd0;
            out_valid <= 1'b0;
            out_user <= 1'b0;
            out_last <= 1'b0;
        end else begin
            if (out_valid && m_axis_tready)
                out_valid <= 1'b0;

            if (input_fire) begin
                if (!sample_x[0]) begin
                    horizontal_first <= s_axis_tdata;
                end else if (!sample_y[0]) begin
                    first_row_pair_sum[sample_x >> 1] <= horizontal_pair;
                end else begin
                    out_data <= box_sum[9:2];
                    out_valid <= 1'b1;
                    out_user <= (sample_x == 1 && sample_y == 1);
                    out_last <= s_axis_tlast || (sample_x == INPUT_WIDTH-1);
                end

                if (s_axis_tlast || sample_x == INPUT_WIDTH-1) begin
                    x_count <= {X_BITS{1'b0}};
                    if (sample_y == INPUT_HEIGHT-1)
                        y_count <= {Y_BITS{1'b0}};
                    else
                        y_count <= sample_y + 1'b1;
                end else begin
                    x_count <= sample_x + 1'b1;
                    y_count <= sample_y;
                end
            end
        end
    end

    wire unused = s_axis_tkeep;
    end endgenerate
endmodule
