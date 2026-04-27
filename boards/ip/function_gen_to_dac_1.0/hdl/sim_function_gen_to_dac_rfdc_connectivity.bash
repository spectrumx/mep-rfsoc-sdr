#!/usr/bin/env bash
# Run from this directory: boards/ip/function_gen_to_dac_1.0/hdl/
# Requires Vivado 2024.1 tools from /opt/Xilinx/Vivado/2024.1/settings64.sh.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./sim_function_gen_to_dac_rfdc_connectivity.bash [--gui] [-h|--help]

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

rm -rf xsim.dir
rm -f ./*.jou ./*.log ./*.pb ./*.wdb ./vivado_pid*.str

xvlog -sv \
  lut_waveform_gen.v \
  function_gen_to_dac_v1.0.v \
  function_gen_to_dac_rfdc_connectivity_tb.sv

xelab -debug typical function_gen_to_dac_rfdc_connectivity_tb -s sim_function_gen_to_dac_rfdc_connectivity

if [[ "${USE_GUI}" -eq 1 ]]; then
  xsim sim_function_gen_to_dac_rfdc_connectivity -gui
else
  xsim sim_function_gen_to_dac_rfdc_connectivity -runall
fi
