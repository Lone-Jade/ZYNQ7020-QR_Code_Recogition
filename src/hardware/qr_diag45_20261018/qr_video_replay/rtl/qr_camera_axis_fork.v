`timescale 1ns/1ps

/* Keep the display stream independent of the QR processing stream.
 * OV5640 DVP cannot be back-pressured.  A stalled QR consumer may lose a
 * frame, but it must never hold the display input or the camera receiver. */
module qr_camera_axis_fork #(
    parameter integer QR_FIFO_ADDR_WIDTH = 6,
    parameter integer QR_SYNC_READ = 0
) (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire [15:0] s_axis_tdata,
    input  wire [1:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tuser,
    input  wire        s_axis_tlast,
    output wire [15:0] m0_axis_tdata,
    output wire [1:0]  m0_axis_tkeep,
    output wire        m0_axis_tvalid,
    input  wire        m0_axis_tready,
    output wire        m0_axis_tuser,
    output wire        m0_axis_tlast,
    output wire [15:0] m1_axis_tdata,
    output wire [1:0]  m1_axis_tkeep,
    output wire        m1_axis_tvalid,
    input  wire        m1_axis_tready,
    output wire        m1_axis_tuser,
    output wire        m1_axis_tlast
);
    reg [15:0] display_data;
    reg [1:0] display_keep;
    reg display_user;
    reg display_last;
    reg display_valid;
    localparam integer QR_FIFO_DEPTH = 1 << QR_FIFO_ADDR_WIDTH;
    reg [QR_FIFO_ADDR_WIDTH-1:0] qr_read_pointer;
    reg [QR_FIFO_ADDR_WIDTH-1:0] qr_write_pointer;
    reg [QR_FIFO_ADDR_WIDTH:0] qr_count;
    reg qr_drop_frame;
    reg [19:0] qr_output;
    reg qr_output_valid;

    wire display_free = !display_valid || m0_axis_tready;
    wire qr_pop = (qr_count != 0) && (QR_SYNC_READ ?
                  (!qr_output_valid || m1_axis_tready) : m1_axis_tready);
    wire qr_free = (qr_count != QR_FIFO_DEPTH) || qr_pop;
    wire input_fire = s_axis_tvalid && s_axis_tready;
    wire qr_push = input_fire && (!qr_drop_frame || s_axis_tuser) && qr_free;

    assign s_axis_tready = display_free;
    assign m0_axis_tdata = display_data;
    assign m0_axis_tkeep = display_keep;
    assign m0_axis_tuser = display_user;
    assign m0_axis_tlast = display_last;
    assign m0_axis_tvalid = display_valid;
    generate if (QR_SYNC_READ != 0) begin : buffered_read
        // Registered RAM read accommodates guard-row insertion stalls with
        // two lines of BRAM storage, without putting that latency on HDMI.
        assign {m1_axis_tuser, m1_axis_tlast, m1_axis_tkeep,
                m1_axis_tdata} = qr_output;
        assign m1_axis_tvalid = qr_output_valid;
        (* ram_style = "block" *) reg [19:0] qr_fifo [0:QR_FIFO_DEPTH-1];
        // RAM contents and its read register have no reset. The resettable
        // valid/pointers below hide stale data, including after a reset.
        always @(posedge aclk) begin
            if (aresetn && qr_push)
                qr_fifo[qr_write_pointer] <= {s_axis_tuser, s_axis_tlast,
                                             s_axis_tkeep, s_axis_tdata};
            if (aresetn && qr_pop)
                qr_output <= qr_fifo[qr_read_pointer];
        end
    end else begin : legacy_read
        (* ram_style = "distributed" *) reg [19:0] qr_fifo [0:QR_FIFO_DEPTH-1];
        always @(posedge aclk) begin
            if (aresetn && qr_push)
                qr_fifo[qr_write_pointer] <= {s_axis_tuser, s_axis_tlast,
                                             s_axis_tkeep, s_axis_tdata};
        end
        assign {m1_axis_tuser, m1_axis_tlast, m1_axis_tkeep,
                m1_axis_tdata} = qr_fifo[qr_read_pointer];
        assign m1_axis_tvalid = (qr_count != 0);
    end endgenerate

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            display_data <= 16'd0;
            display_keep <= 2'd0;
            display_user <= 1'b0;
            display_last <= 1'b0;
            display_valid <= 1'b0;
            qr_read_pointer <= {QR_FIFO_ADDR_WIDTH{1'b0}};
            qr_write_pointer <= {QR_FIFO_ADDR_WIDTH{1'b0}};
            qr_count <= {(QR_FIFO_ADDR_WIDTH+1){1'b0}};
            qr_drop_frame <= 1'b0;
            qr_output_valid <= 1'b0;
        end else begin
            if (display_valid && m0_axis_tready)
                display_valid <= 1'b0;
            case ({qr_push, qr_pop})
                2'b10: qr_count <= qr_count + 1'b1;
                2'b01: qr_count <= qr_count - 1'b1;
                default: qr_count <= qr_count;
            endcase
            if (qr_pop)
                qr_read_pointer <= qr_read_pointer + 1'b1;
            if (QR_SYNC_READ != 0) begin
                if (qr_pop) begin
                    qr_output_valid <= 1'b1;
                end else if (qr_output_valid && m1_axis_tready)
                    qr_output_valid <= 1'b0;
            end
            if (qr_push) begin
                qr_write_pointer <= qr_write_pointer + 1'b1;
            end
            if (input_fire) begin
                display_data <= s_axis_tdata;
                display_keep <= s_axis_tkeep;
                display_user <= s_axis_tuser;
                display_last <= s_axis_tlast;
                display_valid <= 1'b1;
                if (s_axis_tuser)
                    qr_drop_frame <= 1'b0;
                if ((!qr_drop_frame || s_axis_tuser) && !qr_free)
                    qr_drop_frame <= 1'b1;
            end
        end
    end
endmodule
