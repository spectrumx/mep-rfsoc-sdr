#!/bin/bash
###############################################################################
# Run Simulation Script for function_gen_to_dac IP Testbench
# 
# This script launches Vivado in GUI mode, runs the simulation, and keeps
# the wave window open after simulation completes.
#
# Usage:
#   ./run_simulation.sh
#   or
#   bash run_simulation.sh
###############################################################################

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_SCRIPT="$SCRIPT_DIR/simulate_function_gen_to_dac.tcl"

# Check if the simulation script exists
if [ ! -f "$SIM_SCRIPT" ]; then
    echo "Error: Simulation script not found: $SIM_SCRIPT"
    exit 1
fi

# Check if vivado is in PATH
if ! command -v vivado &> /dev/null; then
    echo "Error: vivado command not found. Please ensure Vivado is in your PATH."
    exit 1
fi

echo "=========================================="
echo "Launching Vivado Simulation"
echo "=========================================="
echo "Script directory: $SCRIPT_DIR"
echo "Simulation script: $SIM_SCRIPT"
echo ""
echo "Vivado will open in GUI mode."
echo "The simulation will run automatically."
echo "The wave window will remain open after simulation completes."
echo "=========================================="
echo ""

# Change to the script directory so relative paths work correctly
cd "$SCRIPT_DIR"

# Launch Vivado in GUI mode with the simulation script
# The -source flag runs the TCL script, but Vivado stays open in GUI mode
vivado -mode gui -source "$SIM_SCRIPT"

# Note: Vivado will remain open after the script completes, keeping the wave window visible
# The user can manually close Vivado when done viewing the waveforms

