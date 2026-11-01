`timescale 1ns/1ps
module tb_hdmi_desktop;
    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0;
    reg [15:0] data = 16'hf800;
    reg valid = 0;
    wire ready;
    reg user = 1, last = 0;
    wire [23:0] rgb;
    wire de, hs, vs, outclk;
    integer x = 0, y = 0, beats = 0, pixels = 0, cycles = 0;
    integer hsync = 0, vsync = 0;
    reg nominal_done = 0, manual = 0;
    hdmi_desktop dut(clk, resetn, data, valid, ready, user, last, 2'b11,
        rgb, de, hs, vs, outclk);
    initial begin
        repeat (5) @(negedge clk);
        resetn = 1; valid = 1;
    end
    // AXIS producer holds each beat stable until accepted.
    always @(posedge clk) begin
        if (!manual && resetn && valid && ready) begin
            beats = beats + 1;
            if (x == 1279) begin x = 0; y = y == 719 ? 0 : y + 1; end
            else x = x + 1;
        end
        #1;
        if (!manual && resetn) begin
            cycles = cycles + 1;
            if (de) begin
                pixels = pixels + 1;
                if (rgb !== 24'h0000ff) $fatal(1, "RGB565 lane mapping or AXIS alignment failed");
            end
            if (hs) hsync = hsync + 1;
            if (vs) vsync = vsync + 1;
            if (cycles == 1650 * 750) begin
                if (pixels != 1280 * 720 || beats != 1280 * 720 ||
                    hsync != 40 * 750 || vsync != 5 * 1650)
                    $fatal(1, "Incorrect active, handshake or sync counts");
                $display("PASS: full 720p frame, RGB565, AXIS SOF/TLAST, blanking and sync widths");
                nominal_done = 1;
            end
        end
    end
    always @(negedge clk) begin
        if (!manual) begin
            user = (x == 0 && y == 0);
            last = (x == 1279);
        end
    end
    initial begin
        wait(nominal_done);
        @(negedge clk); manual = 1; resetn = 0;
        repeat (3) @(negedge clk);
        resetn = 1; valid = 1; user = 1; last = 0; data = 16'h07e0;
        @(posedge clk); #1;
        if (rgb !== 24'h00ff00 || !dut.locked) $fatal(1, "Green mapping / SOF recovery failed");
        @(negedge clk); user = 0; data = 16'h001f;
        @(posedge clk); #1;
        if (rgb !== 24'hff0000) $fatal(1, "Blue lane mapping failed");
        @(negedge clk); last = 1;
        @(posedge clk); #1;
        if (rgb !== 0 || dut.locked) $fatal(1, "Malformed TLAST not rejected");
        @(negedge clk); resetn = 0;
        repeat (3) @(negedge clk);
        resetn = 1; valid = 1; user = 1; last = 0; data = 16'hf800;
        @(posedge clk); #1;
        if (!dut.locked) $fatal(1, "Restart SOF rejected");
        @(negedge clk); user = 0; valid = 0;
        @(posedge clk); #1;
        if (rgb !== 0 || dut.locked) $fatal(1, "Underflow not blanked");
        $display("PASS: red/green/blue lanes, restart, malformed TLAST and underflow rejection");
        $finish;
    end
    initial begin #15000000; $fatal(1, "Simulation timed out"); end
endmodule
