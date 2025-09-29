# MEP-SDR Constraints File for RFSoC4x2 Board
# This file defines pin assignments, I/O standards, and timing constraints

# =============================================================================
# CLOCK CONSTRAINTS
# =============================================================================
# 10G Ethernet input clock (156.25 MHz differential clock)
set_property PACKAGE_PIN AA34 [get_ports diff_clock_rtl_clk_n]
set_property PACKAGE_PIN AA33 [get_ports diff_clock_rtl_clk_p]

# =============================================================================
# QSFP MODULE CONTROL SIGNALS
# =============================================================================
# QSFP interrupt signal (active low)
set_property PACKAGE_PIN AM22 [get_ports qsfp_intl_ls]
set_property IOSTANDARD LVCMOS18 [get_ports qsfp_intl_ls]

# QSFP low power mode control (bus signal)
set_property PACKAGE_PIN AN22 [get_ports {qsfp_lpmode_ls[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {qsfp_lpmode_ls[0]}]

# QSFP module select signal (bus signal)
set_property PACKAGE_PIN AK22 [get_ports {qsfp_modsell_ls[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {qsfp_modsell_ls[0]}]

# =============================================================================
# USER LED CONSTRAINTS
# =============================================================================
# LED 0 - Bus signal (indexed), LVCMOS18 I/O standard
set_property PACKAGE_PIN AR11 [get_ports {led_0[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_0[0]}]

# LED 1 - Single bit signal, LVCMOS18 I/O standard
set_property PACKAGE_PIN AW10 [get_ports led_1]
set_property IOSTANDARD LVCMOS18 [get_ports led_1]

# LED 2 - Single bit signal, LVCMOS18 I/O standard
set_property PACKAGE_PIN AT11 [get_ports led_2]
set_property IOSTANDARD LVCMOS18 [get_ports led_2]

# LED 3 - Single bit signal, LVCMOS18 I/O standard
set_property PACKAGE_PIN AU10 [get_ports led_3]
set_property IOSTANDARD LVCMOS18 [get_ports led_3]

# =============================================================================
# TIMING CONSTRAINTS - FALSE PATHS
# =============================================================================
# Define false paths between different clock domains to avoid timing violations
# These clocks operate independently and don't need to meet timing requirements

# False paths between RFADC clocks and TX output clocks
set_false_path -setup -from [get_clocks {RFADC0_CLK RFADC2_CLK}] -to [get_clocks *txoutclk_out*]
set_false_path -setup -from [get_clocks *txoutclk_out*] -to [get_clocks {RFADC0_CLK RFADC2_CLK}]

# False paths between RFADC clocks and PL clocks
set_false_path -setup -from [get_clocks *clk_pl_0*] -to [get_clocks {RFADC0_CLK RFADC2_CLK}]
set_false_path -setup -from [get_clocks {RFADC0_CLK RFADC2_CLK}] -to [get_clocks *clk_pl_0*]

# False paths between PL clocks and TX output clocks
set_false_path -setup -from [get_clocks *clk_pl_0*] -to [get_clocks *txoutclk_out*]
set_false_path -setup -from [get_clocks *txoutclk_out*] -to [get_clocks *clk_pl_0*]

# =============================================================================
# PPS (PULSE PER SECOND) SIGNAL
# =============================================================================
# PPS comparison input signal for timing synchronization
set_property PACKAGE_PIN AJ13 [get_ports pps_comp_in]
set_property IOSTANDARD LVCMOS18 [get_ports pps_comp_in]
# Disable dedicated clock routing for PPS signal (used as data, not clock)
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets pps_comp_in_IBUF_inst/O]