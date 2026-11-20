//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 09:27:12 PM
// Design Name: 
// Module Name: rfid_reader_top
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

module rfid_reader_top #(
    parameter LOCK_CYCLES = 1_250_000_000 
)(
    input  wire        clk,          // System Clock 125 MHz (H16)
    input  wire        rst,          // ปุ่ม Reset (BTN0)
    input  wire        scan_trig,    // สัญญาณจำลองการแตะบัตร (จาก VIO หรือ BTN1)
    input  wire        reg_mode,     // สวิตช์โหมดลงทะเบียนบัตรใหม่ (SW0: 0=Scan, 1=Register)
    input  wire [15:0] card_atqa,    // ค่า ATQA จากบัตร (MIFARE 1K = 16'h0004)
    input  wire [31:0] card_uid,     // ค่า UID 4-byte จากบัตร (32'h904B0296)
    input  wire [7:0]  card_sak,     // ค่า SAK จากบัตร (MIFARE 1K = 8'h08)
    
    output reg  [3:0]  state_led,    // แสดงสถานะ FSM ปัจจุบัน (LD0 - LD3)
    output reg         led_green,    // ไฟเขียว: ผ่าน (LD4_G)
    output reg         led_red,      // ไฟแดง: ปฏิเสธ / ล็อกระบบ (LD4_R)
    output reg         led_blue,     // ไฟน้ำเงิน: โหมดลงทะเบียนบัตร (LD4_B)
    output reg  [7:0]  rf_cmd_out    // คำสั่งที่ Reader ส่งออกไปตามโปรโตคอล
);

    localparam [3:0] S_IDLE          = 4'd0,
                     S_SEND_REQA     = 4'd1,
                     S_WAIT_ATQA     = 4'd2,
                     S_SEND_ANTICOLL = 4'd3,
                     S_WAIT_UID      = 4'd4,
                     S_SEND_SELECT   = 4'd5,
                     S_WAIT_SAK      = 4'd6,
                     S_CHECK_ACCESS  = 4'd7,
                     S_GRANTED       = 4'd8,
                     S_DENIED        = 4'd9,
                     S_LOCKED        = 4'd10;

    localparam [7:0] CMD_REQA        = 8'h26,
                     CMD_ANTICOLL    = 8'h93,
                     CMD_SELECT      = 8'h70;

    reg [3:0]  state, next_state;
    reg [31:0] authorized_uid;
    reg [15:0] rx_atqa;
    reg [31:0] rx_uid;
    reg [7:0]  rx_sak;
    
    reg [1:0]  fail_count;
    reg [31:0] lock_timer;
    reg        trig_d1, trig_d2;
    wire       scan_pulse;

    // 2-Stage Synchronizer + Edge Detector (ป้องกันสัญญาณคลาดเคลื่อน)
    always @(posedge clk) begin
        if (rst) begin
            trig_d1 <= 1'b0;
            trig_d2 <= 1'b0;
        end else begin
            trig_d1 <= scan_trig;
            trig_d2 <= trig_d1;
        end
    end
    assign scan_pulse = trig_d1 & ~trig_d2;

    // 1. Sequential Block
    always @(posedge clk) begin
        if (rst) begin
            state          <= S_IDLE;
            authorized_uid <= 32'h904B0296;
            fail_count     <= 2'd0;
            lock_timer     <= 32'd0;
            rx_atqa        <= 16'd0;
            rx_uid         <= 32'd0;
            rx_sak         <= 8'd0;
        end else begin
            state <= next_state;

            // ล็อกค่าข้อมูลบัตรทันทีที่เริ่มแตะบัตร และอัปเดตตามสเตจ
            if (scan_pulse) begin
                rx_atqa <= card_atqa;
                rx_uid  <= card_uid;
                rx_sak  <= card_sak;
            end

            if (state == S_CHECK_ACCESS) begin
                if (reg_mode) begin
                    authorized_uid <= rx_uid;
                    fail_count     <= 2'd0;
                end else if (rx_atqa == 16'h0004 && rx_sak == 8'h08 && rx_uid == authorized_uid) begin
                    fail_count <= 2'd0;
                end else begin
                    fail_count <= fail_count + 2'd1;
                end
            end

            if (state == S_LOCKED) begin
                if (lock_timer < LOCK_CYCLES)
                    lock_timer <= lock_timer + 32'd1;
                else begin
                    lock_timer <= 32'd0;
                    fail_count <= 2'd0;
                end
            end else begin
                lock_timer <= 32'd0;
            end
        end
    end

    // 2. Combinational Block
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:          if (scan_pulse) next_state = S_SEND_REQA;
            S_SEND_REQA:     next_state = S_WAIT_ATQA;
            S_WAIT_ATQA:     next_state = (rx_atqa == 16'h0004) ? S_SEND_ANTICOLL : S_DENIED;
            S_SEND_ANTICOLL: next_state = S_WAIT_UID;
            S_WAIT_UID:      next_state = S_SEND_SELECT;
            S_SEND_SELECT:   next_state = S_WAIT_SAK;
            S_WAIT_SAK:      next_state = (rx_sak == 8'h08) ? S_CHECK_ACCESS : S_DENIED;
            
            S_CHECK_ACCESS: begin
                if (reg_mode)
                    next_state = S_GRANTED;
                else if (rx_uid == authorized_uid)
                    next_state = S_GRANTED;
                else if (fail_count >= 2'd2)
                    next_state = S_LOCKED;
                else
                    next_state = S_DENIED;
            end

            S_GRANTED: if (scan_pulse) next_state = S_SEND_REQA;
            S_DENIED:  if (scan_pulse) next_state = S_SEND_REQA;
            S_LOCKED:  if (lock_timer >= LOCK_CYCLES) next_state = S_IDLE;
            default:   next_state = S_IDLE;
        endcase
    end

    // 3. Output Logic
    always @(*) begin
        state_led  = state;
        led_green  = 1'b0;
        led_red    = 1'b0;
        led_blue   = reg_mode;
        rf_cmd_out = 8'h00;

        case (state)
            S_SEND_REQA:     rf_cmd_out = CMD_REQA;
            S_SEND_ANTICOLL: rf_cmd_out = CMD_ANTICOLL;
            S_SEND_SELECT:   rf_cmd_out = CMD_SELECT;
            S_GRANTED:       led_green  = 1'b1;
            S_DENIED:        led_red    = 1'b1;
            S_LOCKED:        led_red    = lock_timer[3];
        endcase
    end

endmodule