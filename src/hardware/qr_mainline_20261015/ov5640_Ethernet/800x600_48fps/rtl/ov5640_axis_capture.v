`timescale 1ns/1ps
// OV5640 DVP RGB565 receiver. The sensor presents one byte per PCLK;
// two consecutive bytes form one RGB565 pixel (high byte first).
module ov5640_axis_capture #(
    parameter integer PIXELS = 640,
    parameter integer LINES  = 480,
    /* 深度保持 5（32 像素 / 64 字节）不变：这是 ov5640_1 那份**已上板验证**的位流
     * 所用的值。曾经试过加深到 10，实测反而让 S2MM 不再往 DDR 写数据，所以还原。 */
    parameter integer FIFO_ADDR_WIDTH = 5
) (
    input  wire        rst,
    input  wire        cam_pclk,
    input  wire [7:0]  cam_d,
    input  wire        cam_href,
    input  wire        cam_vsync,
    output wire [15:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tuser,
    output wire        m_axis_tlast
);
    localparam integer FIFO_DEPTH = (1 << FIFO_ADDR_WIDTH);

    reg byte_phase;
    reg [7:0] high_byte;
    reg first_pixel;
    reg prev_vsync;
    reg line_done;
    reg [10:0] x_count;
    reg [9:0]  y_count;

    reg [15:0] fifo_data [0:FIFO_DEPTH-1];
    reg        fifo_user [0:FIFO_DEPTH-1];
    reg        fifo_last [0:FIFO_DEPTH-1];
    reg [FIFO_ADDR_WIDTH-1:0] read_pointer;
    reg [FIFO_ADDR_WIDTH-1:0] write_pointer;
    reg [FIFO_ADDR_WIDTH:0] fifo_count;

    wire fifo_pop = (fifo_count != 0) && m_axis_tready;
    wire pixel_complete = cam_href && !cam_vsync && !line_done && byte_phase;
    wire fifo_push = pixel_complete &&
                     ((fifo_count != FIFO_DEPTH) || fifo_pop);

    assign m_axis_tvalid = (fifo_count != 0);
    assign m_axis_tdata = fifo_data[read_pointer];
    assign m_axis_tuser = fifo_user[read_pointer];
    assign m_axis_tlast = fifo_last[read_pointer];

    always @(posedge cam_pclk) begin
        if (rst) begin
            byte_phase      <= 1'b0;
            high_byte       <= 8'h00;
            first_pixel     <= 1'b1;
            prev_vsync      <= 1'b0;
            line_done       <= 1'b0;
            x_count         <= 11'd0;
            y_count         <= 10'd0;
            read_pointer    <= {FIFO_ADDR_WIDTH{1'b0}};
            write_pointer   <= {FIFO_ADDR_WIDTH{1'b0}};
            fifo_count      <= {(FIFO_ADDR_WIDTH+1){1'b0}};
        end else begin
            // OV5640 DVP VSYNC is active high.  A rising edge starts the
            // vertical blanking interval; the first following HREF pixel is
            // tagged as start-of-frame.
            if (cam_vsync && !prev_vsync) begin
                byte_phase <= 1'b0;
                first_pixel <= 1'b1;
                x_count <= 0;
                y_count <= 0;
                line_done <= 1'b0;
                read_pointer <= {FIFO_ADDR_WIDTH{1'b0}};
                write_pointer <= {FIFO_ADDR_WIDTH{1'b0}};
                fifo_count <= {(FIFO_ADDR_WIDTH+1){1'b0}};
            end else begin
                case ({fifo_push, fifo_pop})
                    2'b10: fifo_count <= fifo_count + 1'b1;
                    2'b01: fifo_count <= fifo_count - 1'b1;
                    default: fifo_count <= fifo_count;
                endcase
                if (fifo_pop)
                    read_pointer <= read_pointer + 1'b1;
                if (fifo_push) begin
                    fifo_data[write_pointer] <= {high_byte, cam_d};
                    fifo_user[write_pointer] <= first_pixel;
                    fifo_last[write_pointer] <= (x_count == PIXELS-1);
                    write_pointer <= write_pointer + 1'b1;
                end

                /* DVP has no backpressure.  Always consume the incoming byte
                 * stream; the small FIFO absorbs temporary AXI tready stalls. */
                if (!cam_href || cam_vsync) begin
                    byte_phase <= 1'b0;
                    line_done <= 1'b0;
                    x_count <= 0;
                end else if (!line_done) begin
                    if (!byte_phase) begin
                        high_byte <= cam_d;
                        byte_phase <= 1'b1;
                    end else begin
                        byte_phase <= 1'b0;
                        first_pixel <= 1'b0;
                        if (x_count == PIXELS-1) begin
                            x_count <= 0;
                            line_done <= 1'b1;
                            if (y_count != LINES-1)
                                y_count <= y_count + 1'b1;
                        end else begin
                            x_count <= x_count + 1'b1;
                        end
                    end
                end
            end
            prev_vsync <= cam_vsync;
        end
    end
endmodule
