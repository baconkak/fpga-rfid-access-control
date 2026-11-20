## System Clock (125 MHz)
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { clk }];

## Buttons (BTN0 = Reset, BTN1 = Manual Scan Trigger)
set_property -dict { PACKAGE_PIN D19 IOSTANDARD LVCMOS33 } [get_ports { btn0_rst }];
set_property -dict { PACKAGE_PIN D20 IOSTANDARD LVCMOS33 } [get_ports { btn1_scan }];

## Switch (SW0 = Register Mode)
set_property -dict { PACKAGE_PIN M20 IOSTANDARD LVCMOS33 } [get_ports { sw0_reg }];

## LEDs (LD0 - LD3 = State Machine Status)
set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN N16 IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

## RGB LED (LD4 = Access Result)
set_property -dict { PACKAGE_PIN N15 IOSTANDARD LVCMOS33 } [get_ports { led4_r }];
set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 } [get_ports { led4_g }];
set_property -dict { PACKAGE_PIN L15 IOSTANDARD LVCMOS33 } [get_ports { led4_b }];