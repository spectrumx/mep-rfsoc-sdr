#!/usr/bin/env bash
# Run from this directory: boards/ip/adc_to_udp_stream_1.0/hdl/
set -euo pipefail

VIVADO_SETTINGS="/opt/Xilinx/Vivado/2024.1/settings64.sh"
if [[ ! -f "${VIVADO_SETTINGS}" ]]; then
  echo "error: Vivado settings not found at ${VIVADO_SETTINGS}" >&2
  exit 1
fi
source "${VIVADO_SETTINGS}"

if ! command -v xvlog >/dev/null 2>&1; then
  echo "error: xvlog not found after sourcing Vivado settings" >&2
  exit 1
fi
if ! command -v xelab >/dev/null 2>&1; then
  echo "error: xelab not found after sourcing Vivado settings" >&2
  exit 1
fi
if ! command -v xsim >/dev/null 2>&1; then
  echo "error: xsim not found after sourcing Vivado settings" >&2
  exit 1
fi

usage() {
  cat <<'EOF'
Usage: ./sim_check_udp_packet_tvalid.bash [--gui] [-h|--help]

Options:
  --gui       Launch xsim in GUI mode using the check_udp_packet wave configuration
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

if [[ -n "${XILINX_VIVADO:-}" ]]; then
  VIVADO_ROOT="${XILINX_VIVADO}"
else
  XVLOG_BIN="$(readlink -f "$(command -v xvlog)")"
  VIVADO_ROOT="$(cd "$(dirname "${XVLOG_BIN}")/.." && pwd)"
fi

XPM_DIR="${VIVADO_ROOT}/data/ip/xpm"
GLBL_V="${VIVADO_ROOT}/data/verilog/src/glbl.v"
XPM_CDC_SV="${XPM_DIR}/xpm_cdc/hdl/xpm_cdc.sv"
XPM_MEMORY_SV="${XPM_DIR}/xpm_memory/hdl/xpm_memory.sv"
XPM_FIFO_SV="${XPM_DIR}/xpm_fifo/hdl/xpm_fifo.sv"
BASE_WCFG_FILE="./check_udp_packet_tb_sim.wcfg"
GENERATED_WCFG_FILE="./check_udp_packet_tvalid_tb_sim.generated.wcfg"

if [[ ! -f "${GLBL_V}" || ! -f "${XPM_CDC_SV}" || ! -f "${XPM_MEMORY_SV}" || ! -f "${XPM_FIFO_SV}" ]]; then
  echo "error: could not find Vivado simulation sources under ${VIVADO_ROOT}/data" >&2
  exit 1
fi

if [[ "${USE_GUI}" -eq 1 && ! -f "${BASE_WCFG_FILE}" ]]; then
  echo "error: GUI wave configuration not found: ${BASE_WCFG_FILE}" >&2
  exit 1
fi

# Clean stale Vivado/xsim artifacts from prior runs.
rm -rf xsim.dir
rm -f ./*.jou ./*.log ./*.pb ./*.wdb ./vivado_pid*.str

# Compile Vivado XPM primitives first so xpm_fifo_async resolves during elaboration.
xvlog -sv \
  "${GLBL_V}" \
  "${XPM_CDC_SV}" \
  "${XPM_MEMORY_SV}" \
  "${XPM_FIFO_SV}" \
  reset_clock_sync.v \
  rising_edge_counter.v \
  signal_clock_sync.v \
  adc_to_udp_stream_v1_0.v \
  check_udp_packet_tvalid_tb.sv

xelab -debug typical check_udp_packet_tvalid_tb glbl -s sim_check_udp_packet_tvalid

if [[ "${USE_GUI}" -eq 1 ]]; then
  sed \
    -e 's/sim_check_udp_packet\.wdb/sim_check_udp_packet_tvalid.wdb/g' \
    -e 's/top_module name="check_udp_packet_tb"/top_module name="check_udp_packet_tvalid_tb"/g' \
    -e 's#/check_udp_packet_tb#/check_udp_packet_tvalid_tb#g' \
    "${BASE_WCFG_FILE}" > "${GENERATED_WCFG_FILE}"
  xsim sim_check_udp_packet_tvalid -gui -view "${GENERATED_WCFG_FILE}"
else
  xsim sim_check_udp_packet_tvalid -runall
fi
