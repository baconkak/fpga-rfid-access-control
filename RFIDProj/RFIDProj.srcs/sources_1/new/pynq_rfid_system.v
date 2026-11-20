`timescale 1ns / 1ps

module pynq_rfid_system(
    input  wire       clk,        // System Clock 125MHz บนบอร์ด PYNQ-Z2 (H16)
    input  wire       btn0_rst,   // ปุ่ม BTN0 บนบอร์ดสำหรับ Reset
    input  wire       btn1_scan,  // ปุ่ม BTN1 บนบอร์ด (กดแตะบัตรแทน VIO ก็ได้)
    input  wire       sw0_reg,    // สวิตช์ SW0 บนบอร์ด (0=โหมดสแกน, 1=โหมดลงทะเบียน)
    output wire [3:0] led,        // ไฟ LED 4 ดวง (LD0-LD3) แสดง State
    output wire       led4_r,     // ไฟ RGB สีแดง (LD4)
    output wire       led4_g,     // ไฟ RGB สีเขียว (LD4)
    output wire       led4_b      // ไฟ RGB สีน้ำเงิน (LD4)
);

    wire        vio_scan_trig;
    wire [15:0] vio_card_atqa;
    wire [31:0] vio_card_uid;
    wire [7:0]  vio_card_sak;
    wire [3:0]  w_state_led;
    wire [7:0]  w_rf_cmd_out;

    assign led = w_state_led;

    // เรียกใช้ VIO สำหรับควบคุมและดูค่าผ่านสาย USB
    vio_0 u_vio (
        .clk        (clk),
        .probe_in0  (w_state_led),
        .probe_in1  (w_rf_cmd_out),
        .probe_out0 (vio_scan_trig),
        .probe_out1 (vio_card_atqa),
        .probe_out2 (vio_card_uid),
        .probe_out3 (vio_card_sak)
    );

    // เรียกใช้วงจร RFID Reader หลัก (กดแตะบัตรได้ทั้งจาก VIO หรือปุ่ม BTN1 บนบอร์ด)
    rfid_reader_top #(
        .LOCK_CYCLES(1_250_000_000) // ล็อก 10 วินาที ที่ความถี่ 125MHz
    ) u_rfid (
        .clk        (clk),
        .rst        (btn0_rst),
        .scan_trig  (vio_scan_trig | btn1_scan),
        .reg_mode   (sw0_reg),
        .card_atqa  (vio_card_atqa),
        .card_uid   (vio_card_uid),
        .card_sak   (vio_card_sak),
        .state_led  (w_state_led),
        .led_green  (led4_g),
        .led_red    (led4_r),
        .led_blue   (led4_b),
        .rf_cmd_out (w_rf_cmd_out)
    );

endmodule