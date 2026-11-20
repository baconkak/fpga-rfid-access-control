`timescale 1ns / 1ps

// Self-checking regression for the existing RTL; no vendor IP required.
module tb_rfid_access;
    localparam LOCK_CYCLES = 40;
    reg clk = 0;
    reg rst = 1;
    reg scan_trig = 0;
    reg reg_mode = 0;
    reg [15:0] card_atqa = 0;
    reg [31:0] card_uid = 0;
    reg [7:0] card_sak = 0;
    wire [3:0] state_led;
    wire led_green, led_red, led_blue;
    wire [7:0] rf_cmd_out;
    integer checks = 0;
    integer locked_cycles = 0;
    integer waited;
    integer trace_file;
    reg [2:0] commands_seen = 0;

    rfid_reader_top #(.LOCK_CYCLES(LOCK_CYCLES)) dut (
        .clk(clk), .rst(rst), .scan_trig(scan_trig), .reg_mode(reg_mode),
        .card_atqa(card_atqa), .card_uid(card_uid), .card_sak(card_sak),
        .state_led(state_led), .led_green(led_green), .led_red(led_red),
        .led_blue(led_blue), .rf_cmd_out(rf_cmd_out)
    );

    always #4 clk = ~clk;

    task check;
        input condition;
        input [8*120-1:0] description;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL: %0s (state=%0d, time=%0t)", description, state_led, $time);
                $fatal(1, "Regression failed");
            end
            checks = checks + 1;
            $display("PASS: %0s", description);
        end
    endtask

    task reset_core;
        begin
            @(negedge clk);
            rst = 1; scan_trig = 0; reg_mode = 0;
            repeat (3) @(negedge clk);
            rst = 0;
            repeat (2) @(negedge clk);
        end
    endtask

    task tap_card;
        input [15:0] atqa;
        input [31:0] uid;
        input [7:0] sak;
        begin
            @(negedge clk);
            card_atqa = atqa; card_uid = uid; card_sak = sak;
            scan_trig = 1;
            repeat (3) @(negedge clk);
            scan_trig = 0;
            repeat (12) @(negedge clk);
        end
    endtask

    // Sample after nonblocking updates to avoid races with the DUT.
    always @(posedge clk) begin
        #1;
        $fdisplay(trace_file, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                  $time, state_led, scan_trig, reg_mode,
                  led_green, led_red, led_blue, rf_cmd_out);
        if (state_led == 10) locked_cycles = locked_cycles + 1;
        case (state_led)
            1: begin
                if (rf_cmd_out !== 8'h26) $fatal(1, "REQA command mismatch");
                commands_seen[0] = 1;
            end
            3: begin
                if (rf_cmd_out !== 8'h93) $fatal(1, "ANTICOLL command mismatch");
                commands_seen[1] = 1;
            end
            5: begin
                if (rf_cmd_out !== 8'h70) $fatal(1, "SELECT command mismatch");
                commands_seen[2] = 1;
            end
        endcase
    end

    initial begin
        trace_file = $fopen("trace.csv", "w");
        if (!trace_file) $fatal(1, "Cannot create trace.csv");
        $fdisplay(trace_file, "time_ns,state,scan,register,green,red,blue,command");
        reset_core;
        check(state_led == 0 && !led_green && !led_red && !led_blue,
              "Reset enters IDLE with result LEDs off");

        tap_card(16'h0004, 32'h904B0296, 8'h08);
        check(state_led == 8 && led_green && !led_red, "Default authorized UID is granted");
        check(commands_seen == 3'b111, "REQA, ANTICOLL and SELECT command states are observed");

        tap_card(16'h0004, 32'h11223344, 8'h08);
        check(state_led == 9 && led_red && dut.fail_count == 1, "Wrong UID is denied and counted");
        tap_card(16'h0000, 32'h904B0296, 8'h08);
        check(state_led == 9 && dut.fail_count == 1, "Unsupported ATQA is denied without counting a UID failure");
        tap_card(16'h0004, 32'h904B0296, 8'h00);
        check(state_led == 9 && dut.fail_count == 1, "Unsupported SAK is denied without counting a UID failure");
        tap_card(16'h0004, 32'h904B0296, 8'h08);
        check(state_led == 8 && dut.fail_count == 0, "Successful access clears accumulated UID failures");

        tap_card(16'h0004, 32'h11223344, 8'h08);
        check(state_led == 9 && dut.fail_count == 1, "First consecutive wrong UID is denied");
        tap_card(16'h0004, 32'hDEADBEEF, 8'h08);
        check(state_led == 9 && dut.fail_count == 2, "Second consecutive wrong UID is denied");
        locked_cycles = 0;
        tap_card(16'h0004, 32'h99887766, 8'h08);
        check(state_led == 10 && dut.fail_count == 3, "Third consecutive wrong UID enters LOCKED");
        reg_mode = 1;
        tap_card(16'h0004, 32'h12345678, 8'h08);
        reg_mode = 0;
        check(state_led == 10 && !led_green, "Scan and enrollment requests are ignored while locked");
        waited = 0;
        while (state_led == 10 && waited < LOCK_CYCLES + 5) begin
            @(negedge clk);
            waited = waited + 1;
        end
        check(state_led == 0 && dut.fail_count == 0, "Lockout expires and clears failure count");
        check(locked_cycles == LOCK_CYCLES + 1, "Current lockout occupies LOCK_CYCLES plus one clock period");
        tap_card(16'h0004, 32'h12345678, 8'h08);
        check(state_led == 9, "Enrollment attempted during lockout did not replace authorized UID");

        reg_mode = 1;
        tap_card(16'h0004, 32'hCAFEBABE, 8'h08);
        check(state_led == 8 && led_blue && dut.fail_count == 0, "Registration accepts a valid card and clears failures");
        reg_mode = 0;
        tap_card(16'h0004, 32'hCAFEBABE, 8'h08);
        check(state_led == 8 && led_green && !led_blue, "Registered UID is granted in normal mode");
        tap_card(16'h0004, 32'h904B0296, 8'h08);
        check(state_led == 9, "Previous UID is denied after replacement");

        // Changing external card inputs after capture must not change this scan.
        @(negedge clk);
        card_atqa = 16'h0004; card_uid = 32'hCAFEBABE; card_sak = 8'h08;
        scan_trig = 1;
        repeat (3) @(negedge clk);
        card_atqa = 0; card_uid = 0; card_sak = 0;
        repeat (12) @(negedge clk);
        check(state_led == 8 && led_green, "Card inputs are latched for the active transaction");
        repeat (15) @(negedge clk);
        check(state_led == 8 && dut.fail_count == 0, "A held trigger does not retrigger the scan");
        scan_trig = 0;
        repeat (3) @(negedge clk);

        reset_core;
        tap_card(16'h0004, 32'hCAFEBABE, 8'h08);
        check(state_led == 9, "Registration is volatile and is cleared by reset");
        tap_card(16'h0004, 32'h904B0296, 8'h08);
        check(state_led == 8, "Reset restores the default authorized UID");
        tap_card(16'h0004, 32'h11111111, 8'h08);
        tap_card(16'h0004, 32'h22222222, 8'h08);
        tap_card(16'h0004, 32'h33333333, 8'h08);
        check(state_led == 10, "Lockout can be entered again after reset");
        reset_core;
        check(state_led == 0 && dut.fail_count == 0, "Reset exits lockout immediately");
        $display("ALL TESTS PASSED (%0d checks)", checks);
        $fclose(trace_file);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Regression watchdog timeout");
    end
endmodule
