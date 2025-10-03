# MEP-SDR Project Initialization Script
# This script sets up a Vivado project for the MEP-SDR design on RFSoC4x2 board

set project_name "mep-sdr"
set ip_dir "../../ip"
set board_dir "../../../extern/RFSoC4x2-BSP/board_files"
set constraints_file "./constraints.xdc"

# Set board repository path BEFORE creating the project
# This is critical for board part recognition
if {[file exists $board_dir]} {
    puts "Setting board repository path to: $board_dir"
    set_param board.repoPaths [list $board_dir]
    puts "Board repository path set successfully"
} else {
    puts "ERROR: Board files not found at $board_dir"
    puts "Please initialize submodules with: git submodule update --init --recursive"
    exit 1
}

# Create the Vivado project
# - Project name: mep-sdr
# - Target part: xczu48dr-ffvg1517-2-e (RFSoC4x2)
create_project ${project_name} ./${project_name} -part xczu48dr-ffvg1517-2-e

# Configure project properties
# Set the board part (now that repository path is set)
puts "Setting board part to: realdigital.org:rfsoc4x2:part0:1.0"
set_property board_part realdigital.org:rfsoc4x2:part0:1.0 [current_project]
puts "Board part set successfully"
set_property target_language Verilog [current_project]
set_property  ip_repo_paths ${ip_dir} [current_project]

# Update IP catalog to include custom IP cores
update_ip_catalog

# Add constraint files for timing and pin assignments
add_files -fileset constrs_1 -norecurse ${constraints_file}

# Source the block design creation script
source ./block_design.tcl