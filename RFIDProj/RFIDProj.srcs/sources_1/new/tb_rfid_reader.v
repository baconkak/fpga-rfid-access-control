`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 09:27:12 PM
// Design Name: 
// Module Name: tb_rfid_reader
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps

module tb_rfid_reader();

    reg         clk;
    reg         rst;
    reg         scan_trig;
    reg         reg_mode;
    reg  [15:0] card_atqa;
    reg  [31:0] card_uid;
    reg  [7:0]  card_sak;

    wire [3:0]  state_led;
    wire        led_green;
    wire        led_red;
    wire        led_blue;
    wire [7:0]  rf_cmd_out;

    // เรียกใช้โมดูลหลัก โดยย่อเวลา Lockout เหลือ 20 Clock เพื่อให้ดูกราฟง่าย
    rfid_reader_top #(
        .LOCK_CYCLES(20)
    ) uut (
        .clk(clk),
        .rst(rst),
        .scan_trig(scan_trig),
        .reg_mode(reg_mode),
        .card_atqa(card_atqa),
        .card_uid(card_uid),
        .card_sak(card_sak),
        .state_led(state_led),
        .led_green(led_green),
        .led_red(led_red),
        .led_blue(led_blue),
        .rf_cmd_out(rf_cmd_out)
    );

    // สร้าง Clock 125 MHz (คาบเวลา 8 ns)
    always #4 clk = ~clk;

    // Task ช่วยจำลองการแตะบัตร 1 ครั้ง
    task tap_card(input [15:0] atqa, input [31:0] uid, input [7:0] sak);
        begin
            card_atqa = atqa;
            card_uid  = uid;
            card_sak  = sak;
            #16 scan_trig = 1;
            #16 scan_trig = 0;
            #100; // รอให้ FSM ประมวลผลเสร็จ
        end
    endtask

    initial begin
        // ค่าเริ่มต้น
        clk = 0; rst = 1; scan_trig = 0; reg_mode = 0;
        card_atqa = 0; card_uid = 0; card_sak = 0;
        #24 rst = 0;
        #20;

        // กรณีที่ 1: แตะบัตรที่ถูกต้อง (UID: 904B0296, ATQA: 0004, SAK: 08) -> ต้องได้ไฟเขียว
        tap_card(16'h0004, 32'h904B0296, 8'h08);

        // กรณีที่ 2: แตะบัตรปลอม/ไม่มีสิทธิ์ 3 ครั้งติดกัน -> ครั้งที่ 3 ต้องเข้าโหมด S_LOCKED (state = 10)
        tap_card(16'h0004, 32'h11223344, 8'h08); // ผิดครั้งที่ 1
        tap_card(16'h0004, 32'hDEADBEEF, 8'h08); // ผิดครั้งที่ 2
        tap_card(16'h0004, 32'h99887766, 8'h08); // ผิดครั้งที่ 3 -> ล็อก!

        // รอให้พ้นช่วงเวลา Lockout (20 Clocks = 160 ns)
        #200;

        // กรณีที่ 3: เปิดโหมดลงทะเบียน (reg_mode = 1) แล้วแตะบัตรใบใหม่ (CAFEBABE)
        reg_mode = 1;
        tap_card(16'h0004, 32'hCAFEBABE, 8'h08);
        reg_mode = 0;

        // กรณีที่ 4: ลองแตะบัตร CAFEBABE ในโหมดปกติ -> ต้องผ่าน (ไฟเขียวติด)
        tap_card(16'h0004, 32'hCAFEBABE, 8'h08);

        #100 $finish;
    end

endmodule
