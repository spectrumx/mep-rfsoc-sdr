###############################################################################
# Simulation Setup Script for adc_to_udp_stream IP Testbench
# 
# This script sets up and launches a behavioral simulation for the 
# adc_to_udp_stream_v1_0_tb testbench.
#
# Usage:
#   - From Vivado Tcl console with IP in catalog: source simulate_ip.tcl
#   - From Vivado Tcl console with direct path: source simulate_ip.tcl
#   - From command line: vivado -mode batch -source simulate_ip.tcl
###############################################################################

# Get the IP directory path
set ip_dir [file dirname [info script]]
set hdl_dir [file join $ip_dir hdl]

# Create project if not already in one
if {[current_project -quiet] == ""} {
    set proj_name "sim_temp"
    set proj_dir [file join $ip_dir $proj_name]
    create_project $proj_name $proj_dir -part xczu48dr-ffvg1517-2-e -force
    puts "Created temporary project for simulation"
}

# Add HDL files to sources_1 fileset
set hdl_files [list \
    [file join $hdl_dir adc_to_udp_stream_v1_0.v] \
    [file join $hdl_dir reset_clock_sync.v] \
    [file join $hdl_dir rising_edge_counter.v] \
    [file join $hdl_dir signal_clock_sync.v] \
]

add_files -fileset sources_1 -norecurse $hdl_files

# Add testbench to simulation fileset
set testbench_file [file join $hdl_dir adc_to_udp_stream_tb.sv]

# Create or get sim_1 fileset
if {[get_filesets sim_1 -quiet] == ""} {
    create_fileset -simset sim_1
}

# Set source set and add testbench
set_property SOURCE_SET sources_1 [get_filesets sim_1]
add_files -fileset sim_1 -norecurse $testbench_file

# Set testbench as top module
set_property top adc_to_udp_stream_v1_0_tb [get_filesets sim_1]
set_property top_lib {} [get_filesets sim_1]

# Update compilation order
update_compile_order -fileset sim_1

# Launch behavioral simulation
puts "Launching behavioral simulation..."
launch_simulation -simset sim_1 -mode behavioral

# Load waveform configuration from .wcfg file
set wcfg_file [file join $ip_dir sim adc_to_udp_stream_v1_0_tb_behav.wcfg]
if {[file exists $wcfg_file]} {
    puts "Loading waveform configuration from: $wcfg_file"
    open_wave_config $wcfg_file
} else {
    puts "Warning: Waveform configuration file not found at: $wcfg_file"
    puts "Please manually add signals to the waveform viewer."
}