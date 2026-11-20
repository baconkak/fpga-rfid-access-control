# Run from the repository root:
# vivado -mode batch -source scripts/create_project.tcl
# Add -tclargs build to also synthesize, implement and generate a bitstream.
set root [file normalize [file join [file dirname [info script]] ..]]
set output [file join $root build vivado]
if {[file exists [file join $output rfid_access.xpr]]} {
    error "Project already exists at $output. Open it, or choose a fresh checkout to recreate."
}
create_project rfid_access $output -part xc7z020clg400-1
set_property target_language Verilog [current_project]
set source_dir [file join $root RFIDProj RFIDProj.srcs sources_1 new]
add_files [list [file join $source_dir rfid_reader_top.v] \
                [file join $source_dir pynq_rfid_system.v]]
add_files -fileset constrs_1 [file join $root RFIDProj RFIDProj.srcs constrs_1 new pynq_z2.xdc]
add_files -fileset sim_1 [file join $root verification tb_rfid_access.v]
set_property top pynq_rfid_system [get_filesets sources_1]
set_property top tb_rfid_access [get_filesets sim_1]

# Recreate the original VIO configuration instead of committing generated IP.
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_0
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN {2} CONFIG.C_NUM_PROBE_OUT {4} \
    CONFIG.C_PROBE_IN0_WIDTH {4} CONFIG.C_PROBE_IN1_WIDTH {8} \
    CONFIG.C_PROBE_OUT0_WIDTH {1} CONFIG.C_PROBE_OUT1_WIDTH {16} \
    CONFIG.C_PROBE_OUT2_WIDTH {32} CONFIG.C_PROBE_OUT3_WIDTH {8} \
    CONFIG.C_PROBE_OUT0_INIT_VAL {0x0} \
    CONFIG.C_PROBE_OUT1_INIT_VAL {0x0004} \
    CONFIG.C_PROBE_OUT2_INIT_VAL {0x904B0296} \
    CONFIG.C_PROBE_OUT3_INIT_VAL {0x08}] [get_ips vio_0]
generate_target all [get_ips vio_0]
update_compile_order -fileset sources_1
puts "PROJECT_READY: [file join $output rfid_access.xpr]"

if {[llength $argv] > 0 && [lindex $argv 0] eq "build"} {
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
        error "Synthesis failed; inspect the build logs."
    }
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
        error "Implementation failed; inspect the build logs."
    }
    open_run impl_1
    report_timing_summary -file [file join $output timing_summary.rpt]
    report_utilization -file [file join $output utilization.rpt]
    puts "BITSTREAM_READY: [file join $output rfid_access.runs impl_1 pynq_rfid_system.bit]"
}
close_project
