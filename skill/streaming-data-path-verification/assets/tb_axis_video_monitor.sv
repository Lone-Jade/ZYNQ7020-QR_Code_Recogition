`timescale 1ns/1ps
module tb_axis_video_monitor;
    reg clk=0, reset_n=0, valid=0, ready=0, user=0, last=0;
    reg [15:0] data=0;
    reg [1:0] keep=3;
    wire integer accepted_beats, completed_frames, pixel_index;
    reg [15:0] lfsr=16'h19b7;
    integer cycle=0, trace_fd, i, wait_count, score=0;
    string fault="", trace_path="trace.csv";
    axis_video_monitor #(.WIDTH(4),.HEIGHT(2)) mon(.*);
    always #5 clk=~clk;
    always @(negedge clk) begin
        lfsr = {lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
        ready = (cycle > 6) && (lfsr[1:0] != 0);
    end
    always @(posedge clk) begin
        $fwrite(trace_fd,"%0d,%0d,%0d,%0d,0x%h,0x%h,%0d,%0d\n",
                cycle,reset_n,valid,ready,data,keep,user,last);
        cycle = cycle + 1;
        if (reset_n && valid && ready) begin
            if (data !== score[15:0]) $fatal(1,"SCOREBOARD_PAYLOAD");
            score = score + 1;
        end
    end
    initial begin
        if ($value$plusargs("FAULT=%s",fault)) begin end
        if ($value$plusargs("TRACE=%s",trace_path)) begin end
        trace_fd=$fopen(trace_path,"w");
        if (!trace_fd) $fatal(1,"TRACE_OPEN");
        $fwrite(trace_fd,"cycle,reset_n,valid,ready,data,keep,user,last\n");
        repeat(2) @(negedge clk);
        reset_n=1;
        for (i=0;i<24;i=i+1) begin
            @(negedge clk);
            valid=1; data=i; user=(i%8==0); last=(i%4==3);
            if (i==0 && fault=="sof") user=0;
            if (i==0 && fault=="last") last=1;
            if (i==0 && fault=="unknown") data=16'hxxxx;
            wait_count=0;
            begin : await_accept
                forever begin
                    @(posedge clk);
                    if (ready) disable await_accept;
                    @(negedge clk);
                    wait_count=wait_count+1;
                    if (i==0 && wait_count==1 && fault=="stall") data=16'hffff;
                end
            end
            @(negedge clk); valid=0;
        end
        repeat(2) @(negedge clk);
        if (accepted_beats!=24 || completed_frames!=3 || pixel_index!=0 || score!=24)
            $fatal(1,"AXIS_FINAL_COUNTS");
        $fclose(trace_fd);
        $display("AXIS_MONITOR_SELFTEST_PASS beats=24 frames=3 seed=19b7");
        $finish;
    end
    initial begin #200000; $fatal(1,"AXIS_SELFTEST_TIMEOUT"); end
endmodule
