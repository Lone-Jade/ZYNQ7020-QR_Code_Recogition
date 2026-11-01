`timescale 1ns/1ps

/* HDMI raster/AXI sink derived from the board-verified ov5640_1 design.
 * A smaller centred video window gives the VDMA time to refill its line
 * buffer while the 1280x720 camera/recognition path remains unchanged. */
module qr_hdmi_video_timing #(
    parameter integer H_ACTIVE = 800,
    parameter integer H_FP = 40,
    parameter integer H_SYNC = 128,
    parameter integer H_BP = 88,
    parameter integer V_ACTIVE = 600,
    parameter integer V_FP = 1,
    parameter integer V_SYNC = 4,
    parameter integer V_BP = 23,
    parameter integer VIDEO_WIDTH = H_ACTIVE,
    parameter integer VIDEO_HEIGHT = V_ACTIVE,
    parameter integer H_SYNC_POL = 1,
    parameter integer V_SYNC_POL = 1
) (
    input  wire        pixel_clk,
    input  wire        rst,
    input  wire [15:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tuser,
    input  wire        s_axis_tlast,
    input  wire [31:0] osd_commit,
    output wire [31:0] osd_bram_addr,
    output wire        osd_bram_en,
    input  wire [31:0] osd_bram_data,
    output reg  [23:0] hdmi_d,
    output reg         hdmi_de,
    output reg         hdmi_hs,
    output reg         hdmi_vs,
    output wire        hdmi_clk,
    output wire [31:0] debug_status,
    output wire [31:0] debug_counts
);
    localparam integer H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
    localparam integer V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;
    localparam integer VIDEO_X = (H_ACTIVE - VIDEO_WIDTH) / 2;
    localparam integer VIDEO_Y = (V_ACTIVE - VIDEO_HEIGHT) / 2;
    localparam integer OSD_X = H_ACTIVE - 412;
    localparam integer OSD_Y = 12;

    reg [11:0] h;
    reg [11:0] v;
    reg frame_locked;
    reg ever_locked;
    reg underflow_seen;
    reg tlast_error_seen;
    reg unexpected_sof_seen;
    reg [11:0] first_underflow_x;
    reg [11:0] first_underflow_y;
    reg [15:0] underflow_cycles;
    reg [11:0] max_locked_y;
    (* ASYNC_REG = "TRUE" *) reg [31:0] osd_commit_meta, osd_commit_sync;
    reg [23:0] osd_sequence;
    reg osd_active_bank;
    reg [3:0] osd_line_mask;
    reg [2:0] osd_text_row;
    reg [4:0] osd_cell_y;
    reg [5:0] osd_text_col;
    reg [3:0] osd_cell_x;
    reg [5:0] osd_word_pixels;
    reg [31:0] osd_bram_addr_reg;
    wire active_video = (h < H_ACTIVE) && (v < V_ACTIVE);
    wire camera_window = (h >= VIDEO_X) && (h < VIDEO_X + VIDEO_WIDTH) &&
                         (v >= VIDEO_Y) && (v < VIDEO_Y + VIDEO_HEIGHT);
    wire camera_window_start = (h == VIDEO_X) && (v == VIDEO_Y);
    wire [11:0] camera_x = h - VIDEO_X;
    wire [11:0] camera_y = v - VIDEO_Y;
    wire osd_region = (h >= OSD_X) && (h < OSD_X + 400) &&
                      (v >= OSD_Y) && (v < OSD_Y + 100);
    wire osd_border = osd_region && ((h == OSD_X) || (h == OSD_X + 399) ||
                      (v == OSD_Y) || (v == OSD_Y + 99));
    wire text_region = (h >= OSD_X + 8) && (h < OSD_X + 392) &&
                       (v >= OSD_Y + 5) && (v < OSD_Y + 95);
    wire [2:0] text_row = osd_text_row;
    wire [5:0] text_col = osd_text_col;
    wire [7:0] current_char_index = text_row * 32 + text_col;
    /* BRAM_PORT uses byte addresses, matching the AXI BRAM controller.  The
     * address is advanced once per four characters instead of dividing the
     * live raster counters, keeping the BRAM address path fully registered. */
    assign osd_bram_addr = osd_bram_addr_reg;
    assign osd_bram_en = 1'b1;

    assign hdmi_clk = ~pixel_clk;
    assign debug_status = {ever_locked, underflow_seen,
                           tlast_error_seen, unexpected_sof_seen,
                           first_underflow_y, first_underflow_x};
    assign debug_counts = {4'd0, max_locked_y, underflow_cycles};
    assign s_axis_tready = frame_locked
                         ? camera_window
                         : (s_axis_tuser ? camera_window_start : 1'b1);

    function [23:0] rgb565_to_888(input [15:0] pixel);
        begin
            rgb565_to_888 = {
                {pixel[4:0], pixel[4:2]},
                {pixel[10:5], pixel[10:9]},
                {pixel[15:11], pixel[15:13]}
            };
        end
    endfunction

    function [34:0] font_glyph(input [7:0] ch);
        begin
            case (ch)
              "0":font_glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
              "1":font_glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
              "2":font_glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
              "3":font_glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
              "4":font_glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
              "5":font_glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
              "6":font_glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
              "7":font_glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
              "8":font_glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
              "9":font_glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
              "A":font_glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
              "B":font_glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
              "C":font_glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
              "D":font_glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
              "E":font_glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
              "F":font_glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
              "G":font_glyph={5'b01111,5'b10000,5'b10000,5'b10111,5'b10001,5'b10001,5'b01111};
              "H":font_glyph={5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
              "I":font_glyph={5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
              "J":font_glyph={5'b00001,5'b00001,5'b00001,5'b00001,5'b10001,5'b10001,5'b01110};
              "K":font_glyph={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
              "L":font_glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
              "M":font_glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
              "N":font_glyph={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
              "O":font_glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
              "P":font_glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
              "Q":font_glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10101,5'b10010,5'b01101};
              "R":font_glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
              "S":font_glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
              "T":font_glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
              "U":font_glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
              "V":font_glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
              "W":font_glyph={5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010};
              "X":font_glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
              "Y":font_glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
              "Z":font_glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b11111};
              /* Lowercase payload bytes retain their original characters.
               * Five-column x-height letters use the last five rows; stems
               * and descenders occupy the full seven-row cell. */
              "a":font_glyph={5'b00000,5'b00000,5'b01110,5'b00001,5'b01111,5'b10001,5'b01111};
              "b":font_glyph={5'b10000,5'b10000,5'b10110,5'b11001,5'b10001,5'b10001,5'b11110};
              "c":font_glyph={5'b00000,5'b00000,5'b01110,5'b10000,5'b10000,5'b10001,5'b01110};
              "d":font_glyph={5'b00001,5'b00001,5'b01101,5'b10011,5'b10001,5'b10001,5'b01111};
              "e":font_glyph={5'b00000,5'b00000,5'b01110,5'b10001,5'b11111,5'b10000,5'b01110};
              "f":font_glyph={5'b00110,5'b01001,5'b01000,5'b11100,5'b01000,5'b01000,5'b01000};
              "g":font_glyph={5'b00000,5'b01111,5'b10001,5'b10001,5'b01111,5'b00001,5'b01110};
              "h":font_glyph={5'b10000,5'b10000,5'b10110,5'b11001,5'b10001,5'b10001,5'b10001};
              "i":font_glyph={5'b00100,5'b00000,5'b01100,5'b00100,5'b00100,5'b00100,5'b01110};
              "j":font_glyph={5'b00010,5'b00000,5'b00110,5'b00010,5'b00010,5'b10010,5'b01100};
              "k":font_glyph={5'b10000,5'b10000,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010};
              "l":font_glyph={5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
              "m":font_glyph={5'b00000,5'b00000,5'b11010,5'b10101,5'b10101,5'b10101,5'b10101};
              "n":font_glyph={5'b00000,5'b00000,5'b10110,5'b11001,5'b10001,5'b10001,5'b10001};
              "o":font_glyph={5'b00000,5'b00000,5'b01110,5'b10001,5'b10001,5'b10001,5'b01110};
              "p":font_glyph={5'b00000,5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000};
              "q":font_glyph={5'b00000,5'b01111,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001};
              "r":font_glyph={5'b00000,5'b00000,5'b10110,5'b11001,5'b10000,5'b10000,5'b10000};
              "s":font_glyph={5'b00000,5'b00000,5'b01111,5'b10000,5'b01110,5'b00001,5'b11110};
              "t":font_glyph={5'b01000,5'b01000,5'b11100,5'b01000,5'b01000,5'b01001,5'b00110};
              "u":font_glyph={5'b00000,5'b00000,5'b10001,5'b10001,5'b10001,5'b10011,5'b01101};
              "v":font_glyph={5'b00000,5'b00000,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
              "w":font_glyph={5'b00000,5'b00000,5'b10001,5'b10001,5'b10101,5'b10101,5'b01010};
              "x":font_glyph={5'b00000,5'b00000,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001};
              "y":font_glyph={5'b00000,5'b10001,5'b10001,5'b10001,5'b01111,5'b00001,5'b01110};
              "z":font_glyph={5'b00000,5'b00000,5'b11111,5'b00010,5'b00100,5'b01000,5'b11111};
              "!":font_glyph={5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00000,5'b00100};
              8'h22:font_glyph={5'b01010,5'b01010,5'b01010,5'b00000,5'b00000,5'b00000,5'b00000};
              "#":font_glyph={5'b01010,5'b01010,5'b11111,5'b01010,5'b11111,5'b01010,5'b01010};
              "$":font_glyph={5'b00100,5'b01111,5'b10100,5'b01110,5'b00101,5'b11110,5'b00100};
              "%":font_glyph={5'b11001,5'b11010,5'b00100,5'b01000,5'b10110,5'b00110,5'b00000};
              "&":font_glyph={5'b01100,5'b10010,5'b10100,5'b01000,5'b10101,5'b10010,5'b01101};
              8'h27:font_glyph={5'b00100,5'b00100,5'b01000,5'b00000,5'b00000,5'b00000,5'b00000};
              "(":font_glyph={5'b00010,5'b00100,5'b01000,5'b01000,5'b01000,5'b00100,5'b00010};
              ")":font_glyph={5'b01000,5'b00100,5'b00010,5'b00010,5'b00010,5'b00100,5'b01000};
              "*":font_glyph={5'b00000,5'b10101,5'b01110,5'b11111,5'b01110,5'b10101,5'b00000};
              "+":font_glyph={5'b00000,5'b00100,5'b00100,5'b11111,5'b00100,5'b00100,5'b00000};
              ",":font_glyph={5'b00000,5'b00000,5'b00000,5'b00000,5'b00110,5'b00100,5'b01000};
              ".":font_glyph={5'b00000,5'b00000,5'b00000,5'b00000,5'b00000,5'b00110,5'b00110};
              "/":font_glyph={5'b00001,5'b00010,5'b00100,5'b00100,5'b01000,5'b10000,5'b00000};
              ";":font_glyph={5'b00000,5'b00110,5'b00110,5'b00000,5'b00110,5'b00100,5'b01000};
              "<":font_glyph={5'b00001,5'b00010,5'b00100,5'b01000,5'b00100,5'b00010,5'b00001};
              "=":font_glyph={5'b00000,5'b00000,5'b11111,5'b00000,5'b11111,5'b00000,5'b00000};
              "?":font_glyph={5'b01110,5'b10001,5'b00010,5'b00100,5'b00100,5'b00000,5'b00100};
              "@":font_glyph={5'b01110,5'b10001,5'b10111,5'b10101,5'b10111,5'b10000,5'b01110};
              "[":font_glyph={5'b01110,5'b01000,5'b01000,5'b01000,5'b01000,5'b01000,5'b01110};
              8'h5c:font_glyph={5'b10000,5'b01000,5'b00100,5'b00100,5'b00010,5'b00001,5'b00000};
              "]":font_glyph={5'b01110,5'b00010,5'b00010,5'b00010,5'b00010,5'b00010,5'b01110};
              "^":font_glyph={5'b00100,5'b01010,5'b10001,5'b00000,5'b00000,5'b00000,5'b00000};
              "_":font_glyph={5'b00000,5'b00000,5'b00000,5'b00000,5'b00000,5'b00000,5'b11111};
              "`":font_glyph={5'b01000,5'b00100,5'b00010,5'b00000,5'b00000,5'b00000,5'b00000};
              "{":font_glyph={5'b00010,5'b00100,5'b00100,5'b01000,5'b00100,5'b00100,5'b00010};
              "}":font_glyph={5'b01000,5'b00100,5'b00100,5'b00010,5'b00100,5'b00100,5'b01000};
              "~":font_glyph={5'b00000,5'b00000,5'b01001,5'b10110,5'b00000,5'b00000,5'b00000};
              "-":font_glyph={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
              "|":font_glyph={5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
              ">":font_glyph={5'b10000,5'b01000,5'b00100,5'b00010,5'b00100,5'b01000,5'b10000};
              ":":font_glyph={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
              " ":font_glyph=35'd0;
              default:font_glyph={5'b01110,5'b10001,5'b00010,5'b00100,5'b00100,5'b00000,5'b00100};
            endcase
        end
    endfunction

    wire [7:0] osd_character = (osd_bram_data >>
                                 (current_char_index[1:0] * 8));
    wire [3:0] cell_x = osd_cell_x;
    wire [4:0] cell_y = osd_cell_y;
    wire [2:0] font_x = (cell_x - 1) >> 1;
    wire [2:0] font_y = (cell_y - 2) >> 1;
    wire [34:0] glyph = font_glyph(osd_character);
    wire line_valid = (text_row == 0) ||
                      ((text_row <= 4) && osd_line_mask[text_row - 1]);
    wire glyph_on = text_region && line_valid && text_col < 32 &&
                    cell_x >= 1 && cell_x < 11 && cell_y >= 2 &&
                    cell_y < 16 && glyph[(6-font_y)*5+(4-font_x)];
    wire [2:0] newest_row = osd_line_mask[3] ? 4 : osd_line_mask[2] ? 3 :
                            osd_line_mask[1] ? 2 : osd_line_mask[0] ? 1 : 0;
    wire [23:0] glyph_color = (text_row == 0) ? 24'h5ED6C3 :
                                (text_row == newest_row) ? 24'hE6B85C : 24'hFFFFFF;
    wire [23:0] osd_pixel = glyph_on ? glyph_color :
                             osd_border ? 24'h5ED6C3 : 24'h101718;

    always @(posedge pixel_clk) begin
        if (rst) begin
            h <= 0;
            v <= 0;
            frame_locked <= 1'b0;
            ever_locked <= 1'b0;
            underflow_seen <= 1'b0;
            tlast_error_seen <= 1'b0;
            unexpected_sof_seen <= 1'b0;
            first_underflow_x <= 0;
            first_underflow_y <= 0;
            underflow_cycles <= 0;
            max_locked_y <= 0;
            osd_commit_meta <= 0;
            osd_commit_sync <= 0;
            osd_sequence <= 0;
            osd_active_bank <= 0;
            osd_line_mask <= 0;
            osd_text_row <= 0;
            osd_cell_y <= 0;
            osd_text_col <= 0;
            osd_cell_x <= 0;
            osd_word_pixels <= 0;
            osd_bram_addr_reg <= 0;
            hdmi_d <= 24'd0;
            hdmi_de <= 1'b0;
            hdmi_hs <= !H_SYNC_POL;
            hdmi_vs <= !V_SYNC_POL;
        end else begin
            osd_commit_meta <= osd_commit;
            osd_commit_sync <= osd_commit_meta;
            if ((h == 0) && (v == 0) &&
                (osd_commit_sync[31:8] != osd_sequence)) begin
                osd_sequence <= osd_commit_sync[31:8];
                osd_line_mask <= osd_commit_sync[7:4];
                osd_active_bank <= osd_commit_sync[0];
            end
            /* Character coordinates advance with the raster. This avoids
             * synthesizing /12, /18 and modulo networks in the pixel path. */
            if (h == H_TOTAL - 1) begin
                if (v == OSD_Y + 4) begin
                    osd_text_row <= 0;
                    osd_cell_y <= 0;
                end else if ((v >= OSD_Y + 5) && (v < OSD_Y + 94)) begin
                    if (osd_cell_y == 17) begin
                        osd_cell_y <= 0;
                        osd_text_row <= osd_text_row + 1'b1;
                    end else begin
                        osd_cell_y <= osd_cell_y + 1'b1;
                    end
                end
            end
            if (h == OSD_X + 7) begin
                osd_text_col <= 0;
                osd_cell_x <= 0;
            end else if ((h >= OSD_X + 8) && (h < OSD_X + 391)) begin
                if (osd_cell_x == 11) begin
                    osd_cell_x <= 0;
                    osd_text_col <= osd_text_col + 1'b1;
                end else begin
                    osd_cell_x <= osd_cell_x + 1'b1;
                end
            end
            if ((v >= OSD_Y + 5) && (v < OSD_Y + 95)) begin
                if (h == OSD_X + 7) begin
                    osd_bram_addr_reg <= {23'd0,osd_active_bank,8'b0} +
                                         {24'd0,osd_text_row,5'b0};
                    osd_word_pixels <= 47;
                end else if ((h >= OSD_X + 8) && (h < OSD_X + 391)) begin
                    if (osd_word_pixels == 0) begin
                        osd_bram_addr_reg <= osd_bram_addr_reg + 4;
                        osd_word_pixels <= 47;
                    end else begin
                        osd_word_pixels <= osd_word_pixels - 1'b1;
                    end
                end
            end
            hdmi_de <= active_video;
            hdmi_hs <= ((h >= H_ACTIVE + H_FP) &&
                        (h < H_ACTIVE + H_FP + H_SYNC))
                     ? H_SYNC_POL : !H_SYNC_POL;
            hdmi_vs <= ((v >= V_ACTIVE + V_FP) &&
                        (v < V_ACTIVE + V_FP + V_SYNC))
                     ? V_SYNC_POL : !V_SYNC_POL;
            hdmi_d <= osd_region ? osd_pixel : 24'h000000;

            /* Diagnostics are observation-only: they do not alter stream
             * ready/valid behavior or the generated HDMI raster. */
            if (frame_locked && camera_window && !s_axis_tvalid) begin
                if (!underflow_seen) begin
                    first_underflow_x <= camera_x;
                    first_underflow_y <= camera_y;
                end
                underflow_seen <= 1'b1;
                if (underflow_cycles != 16'hffff)
                    underflow_cycles <= underflow_cycles + 1'b1;
            end

            if (s_axis_tvalid && s_axis_tready) begin
                if (!frame_locked) begin
                    if (s_axis_tuser && camera_window_start) begin
                        if (s_axis_tlast != (VIDEO_WIDTH == 1)) begin
                            frame_locked <= 1'b0;
                        end else begin
                            hdmi_d <= osd_region ? osd_pixel : rgb565_to_888(s_axis_tdata);
                            frame_locked <= !((VIDEO_WIDTH == 1) &&
                                              (VIDEO_HEIGHT == 1));
                            ever_locked <= 1'b1;
                        end
                    end
                end else if (camera_window) begin
                    if (camera_y > max_locked_y)
                        max_locked_y <= camera_y;
                    if (s_axis_tuser)
                        unexpected_sof_seen <= 1'b1;
                    if (s_axis_tlast != (camera_x == VIDEO_WIDTH - 1))
                        tlast_error_seen <= 1'b1;
                    if (s_axis_tuser ||
                        (s_axis_tlast != (camera_x == VIDEO_WIDTH - 1))) begin
                        frame_locked <= 1'b0;
                    end else begin
                        hdmi_d <= osd_region ? osd_pixel : rgb565_to_888(s_axis_tdata);
                        if ((camera_x == VIDEO_WIDTH - 1) &&
                            (camera_y == VIDEO_HEIGHT - 1))
                            frame_locked <= 1'b0;
                    end
                end
            end

            if (h == H_TOTAL - 1) begin
                h <= 0;
                if (v == V_TOTAL - 1)
                    v <= 0;
                else
                    v <= v + 1'b1;
            end else begin
                h <= h + 1'b1;
            end
        end
    end
endmodule
