`timescale 1ns/1ps

/* Frame-aligned gate for a DVP source which cannot be back-pressured.
 *
 * In the default one-shot mode arm must go low between captures.  With
 * CONTINUOUS=1, an asserted arm forwards every complete frame and only uses
 * WAIT_SOF to preserve frame alignment between consecutive images. */
module qr_camera_frame_gate #(
    parameter integer LINES = 600,
    parameter integer CONTINUOUS = 0
) (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        arm_async,
    input  wire [15:0] s_axis_tdata,
    input  wire [1:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tuser,
    input  wire        s_axis_tlast,
    output wire [15:0] m_axis_tdata,
    output wire [1:0]  m_axis_tkeep,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tuser,
    output wire        m_axis_tlast,
    output reg         frame_active,
    output reg         frame_done_toggle,
    output wire [1:0]  state_debug,
    output wire        arm_debug
);
    localparam WAIT_ARM = 2'd0;
    localparam WAIT_SOF = 2'd1;
    localparam FORWARD  = 2'd2;
    localparam WAIT_LOW = 2'd3;

    (* ASYNC_REG = "TRUE" *) reg [1:0] arm_sync;
    reg [1:0] state;
    assign state_debug=state;
    assign arm_debug=arm_sync[1];
    reg [15:0] line_count;
    wire start_beat = (state == WAIT_SOF) && s_axis_tuser;
    wire pass_beat = (state == FORWARD) || start_beat;
    wire stream_fire = s_axis_tvalid && s_axis_tready;

    assign m_axis_tdata = s_axis_tdata;
    assign m_axis_tkeep = s_axis_tkeep;
    assign m_axis_tuser = s_axis_tuser;
    assign m_axis_tlast = s_axis_tlast;
    assign m_axis_tvalid = s_axis_tvalid && pass_beat;
    /* Dropped pixels must never back-pressure the DVP receiver. */
    assign s_axis_tready = pass_beat ? m_axis_tready : 1'b1;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            arm_sync <= 2'b00;
            state <= WAIT_ARM;
            line_count <= 16'd0;
            frame_active <= 1'b0;
            frame_done_toggle <= 1'b0;
        end else begin
            arm_sync <= {arm_sync[0], arm_async};
            case (state)
                WAIT_ARM: begin
                    frame_active <= 1'b0;
                    line_count <= 16'd0;
                    if (arm_sync[1])
                        state <= WAIT_SOF;
                end
                WAIT_SOF: begin
                    if (!arm_sync[1])
                        state <= WAIT_ARM;
                    else if (stream_fire && s_axis_tuser) begin
                        frame_active <= 1'b1;
                        line_count <= s_axis_tlast ? 16'd1 : 16'd0;
                        if (s_axis_tlast && LINES == 1) begin
                            frame_active <= 1'b0;
                            frame_done_toggle <= ~frame_done_toggle;
                            state <= CONTINUOUS ? WAIT_SOF : WAIT_LOW;
                        end else begin
                            state <= FORWARD;
                        end
                    end
                end
                FORWARD: begin
                    /* If the independent QR tap dropped a frame, the next
                     * SOF is the only safe point to resume forwarding. */
                    if (stream_fire && s_axis_tuser) begin
                        line_count <= s_axis_tlast ? 16'd1 : 16'd0;
                    end else if (stream_fire && s_axis_tlast) begin
                        if (line_count == LINES-1) begin
                            frame_active <= 1'b0;
                            frame_done_toggle <= ~frame_done_toggle;
                            state <= CONTINUOUS ? WAIT_SOF : WAIT_LOW;
                        end else begin
                            line_count <= line_count + 1'b1;
                        end
                    end
                end
                default: begin /* WAIT_LOW */
                    frame_active <= 1'b0;
                    if (!arm_sync[1])
                        state <= WAIT_ARM;
                end
            endcase
        end
    end
endmodule
