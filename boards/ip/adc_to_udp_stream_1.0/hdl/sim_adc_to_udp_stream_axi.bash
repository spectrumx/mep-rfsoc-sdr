#!/usr/bin/env bash
# Run from this directory: boards/ip/adc_to_udp_stream_1.0/hdl/
# Requires Vivado 2024.1 tools from /opt/Xilinx/Vivado/2024.1/settings64.sh.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./sim_adc_to_udp_stream_axi.bash [--gui] [-h|--help]

Options:
  --gui       Launch xsim in GUI mode
  -h, --help  Show this help message
EOF
}

USE_GUI=0
for a in "$@"; do
  case "$a" in
    --gui)
      USE_GUI=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "error: unknown option: $a" >&2
      usage >&2
      exit 1
      ;;
    *)
      echo "error: unexpected argument: $a" >&2
      usage >&2
      exit 1
      ;;
  esac
done

VIVADO_SETTINGS="/opt/Xilinx/Vivado/2024.1/settings64.sh"
if [[ ! -f "${VIVADO_SETTINGS}" ]]; then
  echo "error: Vivado settings file not found: ${VIVADO_SETTINGS}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${VIVADO_SETTINGS}"

if ! command -v xvlog >/dev/null 2>&1; then
  echo "error: xvlog not found in PATH after sourcing ${VIVADO_SETTINGS}" >&2
  exit 1
fi

if ! command -v xelab >/dev/null 2>&1; then
  echo "error: xelab not found in PATH after sourcing ${VIVADO_SETTINGS}" >&2
  exit 1
fi

if ! command -v xsim >/dev/null 2>&1; then
  echo "error: xsim not found in PATH after sourcing ${VIVADO_SETTINGS}" >&2
  exit 1
fi

VIVADO_ROOT="${XILINX_VIVADO}"

XPM_DIR="${VIVADO_ROOT}/data/ip/xpm"
GLBL_V="${VIVADO_ROOT}/data/verilog/src/glbl.v"
XPM_CDC_SV="${XPM_DIR}/xpm_cdc/hdl/xpm_cdc.sv"
XPM_MEMORY_SV="${XPM_DIR}/xpm_memory/hdl/xpm_memory.sv"
XPM_FIFO_SV="${XPM_DIR}/xpm_fifo/hdl/xpm_fifo.sv"

if [[ ! -f "${GLBL_V}" || ! -f "${XPM_CDC_SV}" || ! -f "${XPM_MEMORY_SV}" || ! -f "${XPM_FIFO_SV}" ]]; then
  echo "error: could not find Vivado simulation sources under ${VIVADO_ROOT}/data" >&2
  exit 1
fi

# Clean stale Vivado/xsim artifacts from prior runs.
rm -rf xsim.dir
rm -f ./*.jou ./*.log ./*.pb ./*.wdb ./vivado_pid*.str

# Compile Vivado XPM primitives first, then supporting modules, DUT, and AXI testbench.
xvlog -sv \
  "${GLBL_V}" \
  "${XPM_CDC_SV}" \
  "${XPM_MEMORY_SV}" \
  "${XPM_FIFO_SV}" \
  reset_clock_sync.v \
  rising_edge_counter.v \
  signal_clock_sync.v \
  adc_to_udp_stream_v1_0.v \
  adc_to_udp_stream_axi_tb.sv

xelab -debug typical adc_to_udp_stream_axi_tb glbl -s sim_adc_to_udp_stream_axi

if [[ "${USE_GUI}" -eq 1 ]]; then
  xsim sim_adc_to_udp_stream_axi -gui
else
  xsim sim_adc_to_udp_stream_axi -runall
fi
