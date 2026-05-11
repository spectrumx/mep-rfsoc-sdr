# adc_to_udp_stream AXIS Legacy Behavior Errata

Date: 2026-05-11

## Summary

The `adc_to_udp_stream_v1_0` IP intentionally preserves the legacy packet-byte behavior verified by `hdl/sim_check_udp_packet.bash`. This creates a known incompatibility with strict AXI4-Stream S01 accepted-transfer semantics.

Preserving legacy behavior has priority for this IP. Do not change `hdl/check_udp_packet_tb.sv` or `hdl/sim_check_udp_packet.bash` to hide this behavior.

## Affected Interface

Input AXI4-Stream slave interface:

- `s01_axis_tvalid`
- `s01_axis_tready`
- `s01_axis_tdata`

## Behavior

In the legacy-priority implementation:

- `s01_axis_tready` is tied high.
- `received_counter_s01` advances when `s01_axis_tvalid` is asserted.
- FIFO write enables still suppress storage during selected FIFO reset-busy and ping-pong buffer-selection windows.

As a result, an upstream AXIS source can observe `s01_axis_tvalid && s01_axis_tready` while the corresponding word is not stored into the payload FIFO. This is not strict AXI4-Stream accepted-transfer behavior.

Relevant HDL locations:

- `hdl/adc_to_udp_stream_v1_0.v`: S01 receive counter update.
- `hdl/adc_to_udp_stream_v1_0.v`: `s01_axis_tready` assignment.
- `hdl/adc_to_udp_stream_v1_0.v`: `fifo_0_write_en_s01` and `fifo_1_write_en_s01` assignments.

## Why This Is Intentional

The manual golden packet checker expects the historical packet payload sequence:

- Packet indexes 1, 2, and 3 report `pkt_byte_count = 8298`.
- Packet indexes 1, 2, and 3 report `Total failing bytes: 0 out of 8192`.

A strict C6 implementation that deasserted `s01_axis_tready` during non-storing FIFO reset-busy windows changed the source-visible sample advancement. That made the AXIS accepted-sample model pass, but shifted the manual packet checker payload earlier by `0x54` 16-bit samples:

- Packet 1 expected first payload word `0x104c`, actual `0x0ff8`.
- Packet 2 expected first payload word `0x204c`, actual `0x1ff8`.
- Packet 3 expected first payload word `0x304c`, actual `0x2ff8`.

The project decision is to preserve the legacy packet-byte behavior and document any AXIS strict-acceptance verification issue.

## Verification Guidance

Codex must not run Xilinx tools in the normal development environment.

For a Xilinx-capable agent, run these from `hdl` after sourcing Vivado 2024.1 settings:

1. `./sim_check_udp_packet.bash`
   - Preserve logs as `axis_packet_legacy_priority_xvlog.log`, `axis_packet_legacy_priority_xelab.log`, and `axis_packet_legacy_priority_xsim.log`.
   - This is the priority gate.
2. `./sim_adc_to_udp_stream_axis.bash`
   - Preserve logs as `axis_s01_legacy_priority_xvlog.log`, `axis_s01_legacy_priority_xelab.log`, and `axis_s01_legacy_priority_xsim.log`.
   - If this fails only because strict accepted-transfer expectations conflict with the legacy behavior above, document the failing evidence and do not modify HDL, test benches, scripts, or constraints.
3. `./sim_adc_to_udp_stream_axi.bash`
   - Preserve logs as `axis_s01_legacy_priority_axi_xvlog.log`, `axis_s01_legacy_priority_axi_xelab.log`, and `axis_s01_legacy_priority_axi_xsim.log`.

## Do Not Fix In Xilinx-Agent Pass

If AXIS verification reports that an S01 accepted transfer was not stored, treat it as this erratum unless packet-byte regression also fails. Preserve the command, exit status, first failing line, relevant counters, and exact log filenames.

Only Codex should make source changes after reviewing the preserved evidence.
