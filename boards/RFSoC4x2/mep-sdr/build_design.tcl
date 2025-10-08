# Build Design TCL Script for MEP-SDR Project
# This script performs synthesis, implementation, and bitstream generation

# Open project
set project_name "mep-sdr"
open_project ./${project_name}.xpr
open_bd_design ./${project_name}.srcs/sources_1/bd/block_design/block_design.bd

# Generate HDL wrapper for the block design
make_wrapper -files [get_files ./${project_name}.srcs/sources_1/bd/block_design/block_design.bd] -top

# Add the generated wrapper file to the project
add_files -norecurse ./${project_name}.srcs/sources_1/bd/block_design/hdl/block_design_wrapper.v

# Set the wrapper as the top-level module for synthesis
set_property top block_design_wrapper [current_fileset]

# Update the compilation order to ensure proper dependency resolution
update_compile_order -fileset sources_1

# Launch implementation run and generate bitstream
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
