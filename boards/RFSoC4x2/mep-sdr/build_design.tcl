set project_name "mep-sdr"

make_wrapper -files [get_files ./${project_name}/${project_name}.srcs/sources_1/bd/block_design/block_design.bd] -top
add_files -norecurse ./${project_name}/${project_name}.srcs/sources_1/bd/block_design/hdl/block_design_wrapper.v
set_property top block_design_wrapper [current_fileset]
update_compile_order -fileset sources_1
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1