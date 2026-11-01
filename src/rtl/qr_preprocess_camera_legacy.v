`timescale 1ns/1ps

// Static QR pre-processing block.
// One RGB565 pixel is accepted for every AXI-stream handshake.  The output
// stream is one byte per pixel (Gray8 or 0/255 binary), while the finder
// scanner records horizontal 1:1:3:1:1 candidates in a 32 KiB table.
module qr_preprocess_camera_legacy #(
    parameter integer CANDIDATE_COUNT_MAX = 2048,
    parameter integer GRAY_OUTPUT_DIVISOR = 1
) (
    input  wire         aclk,
    input  wire         aresetn,

    input  wire [15:0]  s_axi_awaddr,
    input  wire [2:0]   s_axi_awprot,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [15:0]  s_axi_araddr,
    input  wire [2:0]   s_axi_arprot,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,

    input  wire [15:0]  s_axis_video_tdata,
    input  wire [1:0]   s_axis_video_tkeep,
    input  wire         s_axis_video_tvalid,
    output wire         s_axis_video_tready,
    input  wire         s_axis_video_tlast,
    input  wire         s_axis_video_tuser,

    output wire [7:0]   m_axis_image_tdata,
    output wire         m_axis_image_tkeep,
    output wire         m_axis_image_tvalid,
    input  wire         m_axis_image_tready,
    output wire         m_axis_image_tlast,
    output wire         m_axis_image_tuser,

    output wire         irq,
    output wire [15:0] capture_width
);

    localparam [31:0] VERSION_VALUE = 32'h0001_0100;
    localparam [15:0] CANDIDATE_BASE = 16'h1000;
    localparam [15:0] CANDIDATE_LAST = 16'h8FFC;

    reg        enable_reg;
    reg        debug_binary_reg;
    reg        swap_rb_reg;
    reg        irq_enable_reg;
    reg [15:0] width_reg;
    reg [15:0] height_reg;
    assign capture_width=width_reg;
    reg [7:0]  threshold_reg;
    reg [31:0] frame_id_reg;
    reg [31:0] active_frame_id_reg;
    reg [31:0] completed_frame_id_reg;
    reg [15:0] min_module_reg;
    reg [15:0] max_module_reg;
    reg [7:0]  finder_tolerance_q8_reg;

    reg        frame_done_reg;
    reg        busy_reg;
    reg        overflow_reg;
    reg        axis_error_reg;
    reg        frame_valid_reg;
    reg        irq_frame_reg;
    reg        irq_overflow_reg;

    reg [15:0] awaddr_hold;
    reg        aw_hold;
    reg [31:0] wdata_hold;
    reg [3:0]  wstrb_hold;
    reg        w_hold;
    reg        bvalid_reg;
    reg        rvalid_reg;
    reg [31:0] rdata_reg;

    // Two frame banks keep the last completed candidate list stable while
    // the next frame is being scanned. Each word bank remains simple dual-port RAM.
    reg [31:0] candidate_mem0 [0:4095];
    reg [31:0] candidate_mem1 [0:4095];
    reg [31:0] candidate_mem2 [0:4095];
    reg [31:0] candidate_mem3 [0:4095];
    reg [11:0] candidate_count_reg;
    reg [11:0] completed_candidate_count_reg;
    reg candidate_write_bank_reg;
    reg completed_candidate_bank_reg;
    reg frame_finish_pending_reg;
    reg [31:0] horizontal_hits_reg;
    reg [31:0] processed_pixels_reg;
    reg        candidate_pending_valid;
    reg [31:0] candidate_pending_frame;
    reg [31:0] candidate_pending_xy;
    reg [15:0] candidate_pending_total;
    reg [31:0] candidate_pending_flags;

    reg [15:0] x_count;
    reg [15:0] y_count;
    reg        run_color;
    reg [15:0] run_length;
    reg [15:0] run0, run1, run2, run3, run4;
    reg        col0, col1, col2, col3, col4;

    reg        pixel_pipe_valid;
    reg [7:0]  gray_pixel_pipe;
    reg        binary_pixel_pipe;
    reg [1:0]  pixel_keep_pipe;
    reg        pixel_last_pipe;
    reg        pixel_user_pipe;
    wire pixel_pipe_accept = enable_reg &&
                             (!pixel_pipe_valid || m_axis_image_tready);
    wire stream_fire = pixel_pipe_valid && m_axis_image_tready;
    wire [4:0] r5_raw = s_axis_video_tdata[15:11];
    wire [5:0] g6_raw = s_axis_video_tdata[10:5];
    wire [4:0] b5_raw = s_axis_video_tdata[4:0];
    wire [4:0] r5 = swap_rb_reg ? b5_raw : r5_raw;
    wire [4:0] b5 = swap_rb_reg ? r5_raw : b5_raw;
    wire [7:0] r8 = {r5, r5[4:2]};
    wire [7:0] g8 = {g6_raw, g6_raw[5:4]};
    wire [7:0] b8 = {b5, b5[4:2]};
    wire [17:0] gray_sum_in = (r8 * 8'd77) + (g8 * 8'd150) +
                              (b8 * 8'd29);
    wire black_pixel = binary_pixel_pipe;
    // Debug binary follows the validation-library contract: dark=255, light=0.
    wire [7:0] image_pixel = debug_binary_reg ?
                             (black_pixel ? 8'hFF : 8'h00) : gray_pixel_pipe;

    assign m_axis_image_tdata  = image_pixel;
    assign m_axis_image_tkeep  = 1'b1;
    assign m_axis_image_tvalid = pixel_pipe_valid;
    assign m_axis_image_tlast = pixel_last_pipe;
    assign m_axis_image_tuser = pixel_user_pipe;
    assign s_axis_video_tready = pixel_pipe_accept;

    assign s_axi_awready = !aw_hold && !bvalid_reg;
    assign s_axi_wready  = !w_hold && !bvalid_reg;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bvalid  = bvalid_reg;
    assign s_axi_arready = !rvalid_reg;
    assign s_axi_rdata   = rdata_reg;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rvalid  = rvalid_reg;
    assign irq = irq_enable_reg && (irq_frame_reg || irq_overflow_reg || axis_error_reg);

    function automatic [15:0] absdiff16(input [15:0] a, input [15:0] b);
        begin absdiff16 = (a >= b) ? (a - b) : (b - a); end
    endfunction

    function automatic pattern_ok(
        input [15:0] a, input [15:0] b, input [15:0] c,
        input [15:0] d, input [15:0] e,
        input        ca, input cb, input cc, input cd, input ce,
        input [7:0]  tolerance_q8
    );
        reg [18:0] total;
        reg [19:0] total3;
        reg [21:0] total9;
        reg [20:0] a14, b14, c14, d14, e14;
        reg [18:0] min_total, max_total;
        begin
            total = a + b + c + d + e;
            total3 = {1'b0,total} + ({1'b0,total} << 1);
            total9 = {3'd0,total} + ({3'd0,total} << 3);
            a14 = ({5'd0,a} << 4) - ({5'd0,a} << 1);
            b14 = ({5'd0,b} << 4) - ({5'd0,b} << 1);
            c14 = ({5'd0,c} << 4) - ({5'd0,c} << 1);
            d14 = ({5'd0,d} << 4) - ({5'd0,d} << 1);
            e14 = ({5'd0,e} << 4) - ({5'd0,e} << 1);
            min_total = ({3'd0,min_module_reg} << 3) - min_module_reg;
            max_total = ({3'd0,max_module_reg} << 3) - max_module_reg;
            pattern_ok = (a != 0 && b != 0 && c != 0 && d != 0 && e != 0 &&
                          ca && !cb && cc && !cd && ce && total >= 7 &&
                          total >= min_total && total <= max_total &&
                          a14 >= total && a14 <= total3 &&
                          b14 >= total && b14 <= total3 &&
                          d14 >= total && d14 <= total3 &&
                          e14 >= total && e14 <= total3 &&
                          c14 >= total3 && c14 <= total9);
        end
    endfunction

    function automatic [15:0] pattern_score(
        input [15:0] a, input [15:0] b, input [15:0] c,
        input [15:0] d, input [15:0] e
    );
        reg [15:0] total;
        reg [15:0] m;
        reg [31:0] err;
        begin
            total = a+b+c+d+e; m = (total * 32'd9363) >> 16;
            err = absdiff16(a,m)+absdiff16(b,m)+absdiff16(d,m)+absdiff16(e,m)+absdiff16(c,m*3);
            pattern_score = (err >= 16'hFFFF) ? 16'd0 : (16'hFFFF - err[15:0]);
        end
    endfunction

    wire pixel_transition = (black_pixel != run_color);
    wire expected_tlast = (x_count == width_reg - 1'b1);
    wire line_boundary = pixel_last_pipe || expected_tlast;
    wire [15:0] transition_total = run1 + run2 + run3 + run4 + run_length;
    wire [15:0] end_run_length = (run_length == 16'hFFFF) ? run_length : run_length + 1'b1;
    wire [15:0] end_total = run1 + run2 + run3 + run4 + end_run_length;
    wire transition_match = pattern_ok(run1, run2, run3, run4, run_length,
                                       col1, col2, col3, col4, run_color,
                                       finder_tolerance_q8_reg);
    wire end_match = pattern_ok(run1, run2, run3, run4, end_run_length,
                                col1, col2, col3, col4, run_color,
                                finder_tolerance_q8_reg);
    wire candidate_event = (pixel_transition && transition_match) ||
                           (!pixel_transition && line_boundary && end_match);
    wire [15:0] candidate_total = pixel_transition ? transition_total : end_total;
    wire [15:0] candidate_x = pixel_transition ?
                              (x_count - (transition_total >> 1)) :
                              ((x_count + 1'b1) - (end_total >> 1));
    wire [15:0] candidate_module_q8 = (candidate_total * 32'd9363) >> 8;
    wire [15:0] pending_candidate_module_q8 =
        (candidate_pending_total * 32'd9363) >> 8;

    wire [12:0] ar_word_index = (s_axi_araddr >= CANDIDATE_BASE) ?
                                 ((s_axi_araddr - CANDIDATE_BASE) >> 2) : 13'd0;
    wire ar_candidate_range = (s_axi_araddr >= CANDIDATE_BASE) &&
                               (s_axi_araddr <= CANDIDATE_LAST);

    reg [31:0] write_word;
    always @(posedge aclk) begin
        if (!aresetn) begin
            enable_reg <= 1'b0; debug_binary_reg <= 1'b0; swap_rb_reg <= 1'b0;
            irq_enable_reg <= 1'b0; width_reg <= 16'd800; height_reg <= 16'd600;
            threshold_reg <= 8'd128; frame_id_reg <= 32'd0;
            active_frame_id_reg <= 32'd0; completed_frame_id_reg <= 32'd0;
            min_module_reg <= 16'd2; max_module_reg <= 16'd64;
            finder_tolerance_q8_reg <= 8'd128;
            frame_done_reg <= 1'b0; busy_reg <= 1'b0; overflow_reg <= 1'b0;
            axis_error_reg <= 1'b0; frame_valid_reg <= 1'b0;
            irq_frame_reg <= 1'b0; irq_overflow_reg <= 1'b0;
            awaddr_hold <= 16'd0; aw_hold <= 1'b0; wdata_hold <= 32'd0;
            wstrb_hold <= 4'd0; w_hold <= 1'b0; bvalid_reg <= 1'b0;
            rvalid_reg <= 1'b0; rdata_reg <= 32'd0; candidate_count_reg <= 12'd0;
            completed_candidate_count_reg <= 12'd0;
            candidate_write_bank_reg <= 1'b1;
            completed_candidate_bank_reg <= 1'b0;
            frame_finish_pending_reg <= 1'b0;
            horizontal_hits_reg <= 32'd0; processed_pixels_reg <= 32'd0;
            candidate_pending_valid <= 1'b0;
            candidate_pending_frame <= 32'd0; candidate_pending_xy <= 32'd0;
            candidate_pending_total <= 16'd0; candidate_pending_flags <= 32'd0;
            x_count <= 16'd0; y_count <= 16'd0; run_color <= 1'b0; run_length <= 16'd0;
            run0 <= 0; run1 <= 0; run2 <= 0; run3 <= 0; run4 <= 0;
            col0 <= 0; col1 <= 0; col2 <= 0; col3 <= 0; col4 <= 0;
            pixel_pipe_valid <= 1'b0; gray_pixel_pipe <= 8'd0;
            binary_pixel_pipe <= 1'b0;
            pixel_keep_pipe <= 2'd0; pixel_last_pipe <= 1'b0;
            pixel_user_pipe <= 1'b0;
        end else begin
            candidate_pending_valid <= 1'b0;
            if (candidate_pending_valid && !overflow_reg) begin
                if (candidate_count_reg < CANDIDATE_COUNT_MAX) begin
                    candidate_mem0[{candidate_write_bank_reg,candidate_count_reg[10:0]}] <= candidate_pending_frame;
                    candidate_mem1[{candidate_write_bank_reg,candidate_count_reg[10:0]}] <= candidate_pending_xy;
                    candidate_mem2[{candidate_write_bank_reg,candidate_count_reg[10:0]}] <= {
                        16'h8000, pending_candidate_module_q8
                    };
                    candidate_mem3[{candidate_write_bank_reg,candidate_count_reg[10:0]}] <= candidate_pending_flags;
                    candidate_count_reg <= candidate_count_reg + 1'b1;
                end else begin
                    overflow_reg <= 1'b1; irq_overflow_reg <= 1'b1;
                    frame_valid_reg <= 1'b0;
                end
            end
            if (frame_finish_pending_reg) begin
                completed_frame_id_reg <= active_frame_id_reg;
                completed_candidate_bank_reg <= candidate_write_bank_reg;
                completed_candidate_count_reg <= candidate_count_reg +
                    (candidate_pending_valid && !overflow_reg &&
                     candidate_count_reg < CANDIDATE_COUNT_MAX ? 12'd1 : 12'd0);
                frame_finish_pending_reg <= 1'b0;
            end
            if (pixel_pipe_accept) begin
                pixel_pipe_valid <= s_axis_video_tvalid && enable_reg;
                if (s_axis_video_tvalid && enable_reg) begin
                    gray_pixel_pipe <= gray_sum_in[15:8];
                    binary_pixel_pipe <= (gray_sum_in[15:8] < threshold_reg);
                    pixel_keep_pipe <= s_axis_video_tkeep;
                    pixel_last_pipe <= s_axis_video_tlast;
                    pixel_user_pipe <= s_axis_video_tuser;
                end
            end
            if (s_axi_awvalid && s_axi_awready) begin awaddr_hold <= s_axi_awaddr; aw_hold <= 1'b1; end
            if (s_axi_wvalid && s_axi_wready) begin wdata_hold <= s_axi_wdata; wstrb_hold <= s_axi_wstrb; w_hold <= 1'b1; end
            if (bvalid_reg && s_axi_bready) bvalid_reg <= 1'b0;

            if ((aw_hold || (s_axi_awvalid && s_axi_awready)) &&
                (w_hold || (s_axi_wvalid && s_axi_wready)) && !bvalid_reg) begin
                write_word = (w_hold ? wdata_hold : s_axi_wdata);
                case (aw_hold ? awaddr_hold : s_axi_awaddr)
                    12'h000: begin
                        if (wstrb_hold[0] || (!w_hold && s_axi_wstrb[0])) begin
                            enable_reg <= write_word[0];
                            if (write_word[1]) begin
                                frame_done_reg <= 1'b0; overflow_reg <= 1'b0; axis_error_reg <= 1'b0;
                                frame_valid_reg <= 1'b0; candidate_count_reg <= 12'd0;
                                completed_candidate_count_reg <= 12'd0;
                                frame_finish_pending_reg <= 1'b0;
                                horizontal_hits_reg <= 32'd0; processed_pixels_reg <= 32'd0;
            candidate_pending_valid <= 1'b0;
            candidate_pending_frame <= 32'd0; candidate_pending_xy <= 32'd0;
            candidate_pending_total <= 16'd0; candidate_pending_flags <= 32'd0;
                                busy_reg <= 1'b0; irq_frame_reg <= 1'b0; irq_overflow_reg <= 1'b0;
                                x_count <= 16'd0; y_count <= 16'd0;
                                run_color <= 1'b0; run_length <= 16'd0;
                                run0 <= 0; run1 <= 0; run2 <= 0; run3 <= 0; run4 <= 0;
                                col0 <= 0; col1 <= 0; col2 <= 0; col3 <= 0; col4 <= 0;
                                pixel_pipe_valid <= 1'b0;
                                candidate_pending_valid <= 1'b0;
                            end
                            debug_binary_reg <= write_word[2]; swap_rb_reg <= write_word[3]; irq_enable_reg <= write_word[4];
                        end
                    end
                    12'h008: if (wstrb_hold[0] || (!w_hold && s_axi_wstrb[0])) width_reg <= write_word[15:0];
                    12'h00C: if (wstrb_hold[0] || (!w_hold && s_axi_wstrb[0])) height_reg <= write_word[15:0];
                    12'h010: if (wstrb_hold[0] || (!w_hold && s_axi_wstrb[0])) threshold_reg <= write_word[7:0];
                    12'h018: if (wstrb_hold[0] || (!w_hold && s_axi_wstrb[0])) frame_id_reg <= write_word;
                    12'h01C: begin
                        if (write_word[0]) begin frame_done_reg <= 1'b0; irq_frame_reg <= 1'b0; end
                        if (write_word[1]) begin overflow_reg <= 1'b0; irq_overflow_reg <= 1'b0; end
                        if (write_word[2]) axis_error_reg <= 1'b0;
                    end
                    12'h02C: if (wstrb_hold[0] || (!w_hold && s_axi_wstrb[0])) min_module_reg <= write_word[15:0];
                    12'h030: if (wstrb_hold[0] || (!w_hold && s_axi_wstrb[0])) max_module_reg <= write_word[15:0];
                    12'h034: if (wstrb_hold[0] || (!w_hold && s_axi_wstrb[0])) finder_tolerance_q8_reg <= write_word[7:0];
                    default: begin end
                endcase
                aw_hold <= 1'b0; w_hold <= 1'b0; bvalid_reg <= 1'b1;
            end

            if (s_axi_arvalid && s_axi_arready) begin
                rvalid_reg <= 1'b1;
                if (ar_candidate_range) begin
                    case (ar_word_index[1:0])
                        2'd0: rdata_reg <= candidate_mem0[{completed_candidate_bank_reg,ar_word_index[12:2]}];
                        2'd1: rdata_reg <= candidate_mem1[{completed_candidate_bank_reg,ar_word_index[12:2]}];
                        2'd2: rdata_reg <= candidate_mem2[{completed_candidate_bank_reg,ar_word_index[12:2]}];
                        default: rdata_reg <= candidate_mem3[{completed_candidate_bank_reg,ar_word_index[12:2]}];
                    endcase
                end else begin
                    case (s_axi_araddr)
                        12'h000: rdata_reg <= {27'd0,irq_enable_reg,swap_rb_reg,debug_binary_reg,1'b0,enable_reg};
                        12'h004: rdata_reg <= {27'd0,frame_valid_reg,axis_error_reg,overflow_reg,frame_done_reg,busy_reg};
                        12'h008: rdata_reg <= {16'd0,width_reg};
                        12'h00C: rdata_reg <= {16'd0,height_reg};
                        12'h010: rdata_reg <= {24'd0,threshold_reg};
                        12'h014: rdata_reg <= {20'd0,completed_candidate_count_reg};
                        12'h018: rdata_reg <= frame_id_reg;
                        12'h01C: rdata_reg <= {29'd0,axis_error_reg,irq_overflow_reg,irq_frame_reg};
                        12'h020: rdata_reg <= VERSION_VALUE;
                        12'h024: rdata_reg <= horizontal_hits_reg;
                        12'h028: rdata_reg <= processed_pixels_reg;
                        12'h02C: rdata_reg <= {16'd0,min_module_reg};
                        12'h030: rdata_reg <= {16'd0,max_module_reg};
                        12'h034: rdata_reg <= {24'd0,finder_tolerance_q8_reg};
                        12'h038: rdata_reg <= completed_frame_id_reg;
                        // Read-only bitstream geometry tag.  A new camera ELF
                        // rejects an old or differently configured bitstream.
                        12'h03C: rdata_reg <= GRAY_OUTPUT_DIVISOR;
                        default: rdata_reg <= 32'd0;
                    endcase
                end
            end
            if (rvalid_reg && s_axi_rready) rvalid_reg <= 1'b0;

            if (stream_fire) begin
                if (pixel_user_pipe) begin
                    if (busy_reg || (pixel_keep_pipe != 2'b11) ||
                        (pixel_last_pipe != (width_reg == 16'd1))) begin
                        axis_error_reg <= 1'b1;
                    end
                    x_count <= pixel_last_pipe ? 16'd0 : 16'd1; y_count <= 16'd0; busy_reg <= 1'b1;
                    frame_done_reg <= 1'b0; irq_frame_reg <= 1'b0;
                    overflow_reg <= 1'b0; irq_overflow_reg <= 1'b0; candidate_count_reg <= 12'd0;
                    horizontal_hits_reg <= 32'd0; processed_pixels_reg <= 32'd1;
                    frame_id_reg <= frame_id_reg + 1'b1;
                    active_frame_id_reg <= frame_id_reg + 1'b1;
                    candidate_write_bank_reg <= ~completed_candidate_bank_reg;
                    frame_valid_reg <= !busy_reg && (pixel_keep_pipe == 2'b11) &&
                                       (pixel_last_pipe == (width_reg == 16'd1));
                    run_color <= black_pixel; run_length <= 16'd1;
                    run0 <= 0; run1 <= 0; run2 <= 0; run3 <= 0; run4 <= 0;
                    col0 <= 0; col1 <= 0; col2 <= 0; col3 <= 0; col4 <= 0;
                end else begin
                    processed_pixels_reg <= processed_pixels_reg + 1'b1;
                    if (!busy_reg || (pixel_keep_pipe != 2'b11) ||
                        (pixel_last_pipe != expected_tlast)) begin
                        axis_error_reg <= 1'b1;
                        frame_valid_reg <= 1'b0;
                    end
                    if (candidate_event && !overflow_reg) begin
                        horizontal_hits_reg <= horizontal_hits_reg + 1'b1;
                        candidate_pending_valid <= 1'b1;
                        candidate_pending_frame <= active_frame_id_reg;
                        candidate_pending_xy <= {y_count,candidate_x};
                        candidate_pending_total <= candidate_total;
                        candidate_pending_flags <= {
                            29'd0,axis_error_reg,debug_binary_reg,swap_rb_reg
                        };
                    end
                    if (black_pixel == run_color) begin
                        if (run_length != 16'hFFFF) run_length <= run_length + 1'b1;
                    end else begin
                        run0 <= run1; run1 <= run2; run2 <= run3; run3 <= run4; run4 <= run_length;
                        col0 <= col1; col1 <= col2; col2 <= col3; col3 <= col4; col4 <= run_color;
                        run_color <= black_pixel; run_length <= 16'd1;
                    end
                    if (line_boundary) begin
                        x_count <= 16'd0;
                        run_color <= 1'b0; run_length <= 16'd0;
                        run0 <= 0; run1 <= 0; run2 <= 0; run3 <= 0; run4 <= 0;
                        col0 <= 0; col1 <= 0; col2 <= 0; col3 <= 0; col4 <= 0;
                        if (y_count == height_reg-1) begin
                            y_count <= 16'd0; busy_reg <= 1'b0; frame_done_reg <= 1'b1; irq_frame_reg <= 1'b1;
                            frame_finish_pending_reg <= 1'b1;
                        end else y_count <= y_count + 1'b1;
                    end else x_count <= x_count + 1'b1;
                end
            end
        end
    end
endmodule
