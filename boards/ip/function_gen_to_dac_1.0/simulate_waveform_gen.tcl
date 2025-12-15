###############################################################################
# Simulation Setup Script for waveform generator IP Testbench
# 
# This script sets up and launches a behavioral simulation for either
# cordic_waveform_gen_tb or lut_waveform_gen_tb testbench.
#
# Usage:
#   - From Vivado Tcl console: source simulate_waveform_gen.tcl
#   - From command line: vivado -mode batch -source simulate_waveform_gen.tcl
#
# Configuration:
#   - Set the waveform_type variable below to "cordic" or "lut"
###############################################################################

# Configuration: Select waveform generator type
# Options: "cordic" or "lut"
set waveform_type "lut"

puts "Selected waveform generator type: $waveform_type"

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

# Add HDL files to sources_1 fileset based on selected type
if {$waveform_type == "cordic"} {
    set hdl_files [list \
        [file join $hdl_dir cordic_waveform_gen.v] \
    ]
    set testbench_file [file join $hdl_dir cordic_waveform_gen_tb.sv]
    set top_module "cordic_waveform_gen_tb"
    set wcfg_name "cordic_waveform_gen_tb"
} else {
    set hdl_files [list \
        [file join $hdl_dir lut_waveform_gen.v] \
    ]
    set testbench_file [file join $hdl_dir lut_waveform_gen_tb.sv]
    set top_module "lut_waveform_gen_tb"
    set wcfg_name "lut_waveform_gen_tb"
}

add_files -fileset sources_1 -norecurse $hdl_files

# Create or get sim_1 fileset
if {[get_filesets sim_1 -quiet] == ""} {
    create_fileset -simset sim_1
}

# Set source set and add testbench
set_property SOURCE_SET sources_1 [get_filesets sim_1]
add_files -fileset sim_1 -norecurse $testbench_file

# Set testbench as top module
set_property top $top_module [get_filesets sim_1]
set_property top_lib {} [get_filesets sim_1]

# Add wave configuration file to simulation fileset if it exists
set wcfg_file [file join $ip_dir sim ${wcfg_name}_behav.wcfg]
if {[file exists $wcfg_file]} {
    puts "Adding waveform configuration to project: $wcfg_file"
    add_files -fileset sim_1 -norecurse $wcfg_file
    # Set as the active wave configuration view (will open automatically)
    set_property xsim.view $wcfg_file [get_filesets sim_1]
}

# Update compilation order
update_compile_order -fileset sim_1

# Launch behavioral simulation
puts "Launching behavioral simulation..."
launch_simulation -simset sim_1 -mode behavioral

# Open waveform configuration (should already be open from xsim.view, but ensure it's loaded)
if {[file exists $wcfg_file]} {
    puts "Loading waveform configuration: $wcfg_file"
    # Use catch to handle case where it's already open
    catch {open_wave_config $wcfg_file}
} else {
    puts "Warning: Waveform configuration file not found at: $wcfg_file"
    puts "Please manually add signals to the waveform viewer."
}

# Run simulation with a time limit (safety timeout)
# Testbench should complete in 1000ns, using 5us as a safe limit
puts "Running simulation (timeout: 5us)..."
run 5us

# Wait a moment for log to be written
after 500


