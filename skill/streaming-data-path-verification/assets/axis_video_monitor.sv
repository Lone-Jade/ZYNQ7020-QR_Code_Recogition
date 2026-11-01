`timescale 1ns/1ps
// Simulation monitor: one pixel/beat, all byte lanes present, scalar SOF.
module axis_video_monitor #(
    parameter integer DATA_WIDTH = 16,
    parameter integer WIDTH = 4,
    parameter integer HEIGHT = 2,
    parameter integer ALLOW_RESET_ABORT = 0
) (
    input wire clk, reset_n, valid, ready,
    input wire [DATA_WIDTH-1:0] data,
    input wire [DATA_WIDTH/8-1:0] keep,
    input wire user, last,
    output integer accepted_beats = 0,
    output integer completed_frames = 0,
    output integer pixel_index = 0
);
    localparam integer BUNDLE_WIDTH = DATA_WIDTH + DATA_WIDTH/8 + 2;
    reg stalled = 0;
    reg [BUNDLE_WIDTH-1:0] held = 0;
    wire [BUNDLE_WIDTH-1:0] bundle = {data, keep, user, last};
    initial begin
        if (DATA_WIDTH <= 0 || DATA_WIDTH % 8 != 0 || WIDTH <= 0 || HEIGHT <= 0)
            $fatal(1, "AXIS_MONITOR_CONFIG");
    end
    always @(posedge clk) begin
        if (reset_n === 1'b0) begin
            if (!ALLOW_RESET_ABORT && (pixel_index != 0 || stalled))
                $fatal(1, "AXIS_RESET_ABORT");
            accepted_beats = 0;
            completed_frames = 0;
            pixel_index = 0;
            stalled = 0;
        end else begin
            if (reset_n !== 1'b1 || (valid !== 1'b0 && valid !== 1'b1) ||
                (ready !== 1'b0 && ready !== 1'b1)) $fatal(1, "AXIS_UNKNOWN_CONTROL");
            if (valid && (^bundle === 1'bx)) $fatal(1, "AXIS_UNKNOWN_PAYLOAD");
            if (stalled && (valid !== 1'b1 || bundle !== held))
                $fatal(1, "AXIS_STALL_STABILITY");
            if (valid && ready) begin
                if (keep !== {DATA_WIDTH/8{1'b1}}) $fatal(1, "AXIS_KEEP_PROFILE");
                if (user !== (pixel_index == 0)) $fatal(1, "AXIS_SOF_POSITION");
                if (last !== (pixel_index % WIDTH == WIDTH-1)) $fatal(1, "AXIS_EOL_POSITION");
                accepted_beats = accepted_beats + 1;
                pixel_index = pixel_index + 1;
                if (pixel_index == WIDTH * HEIGHT) begin
                    completed_frames = completed_frames + 1;
                    pixel_index = 0;
                end
            end
            stalled = valid && !ready;
            if (stalled) held = bundle;
        end
    end
endmodule
