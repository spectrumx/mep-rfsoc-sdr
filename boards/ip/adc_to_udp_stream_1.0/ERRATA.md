# S01 AXI4-Stream Non-Standard TREADY Behavior

## Affected Interface

- IP: `adc_to_udp_stream`
- HDL: `hdl/adc_to_udp_stream_v1_0.v`
- Interface: S01 AXI4-Stream slave input
- Affected signals: `s01_axis_tvalid`, `s01_axis_tready`, `s01_axis_tdata`

## Non-Standard Behavior

The S01 input does not fully follow the AXI4-Stream convention that every cycle with `TVALID && TREADY` represents a beat that is accepted, stored, and later emitted.

In this IP:

- `s01_axis_tready` is tied high.
- FIFO writes are gated by `s01_axis_tvalid`, selected FIFO readiness, and ping-pong buffer selection.
- Internal reset-busy and buffer-management windows can prevent a valid beat from being written even while `s01_axis_tready` remains high.
- Low-`TVALID` cycles are ignored and are not written into either FIFO.
- `received_counter_s01` advances on `s01_axis_tvalid && s01_axis_tready`; because `s01_axis_tready` is tied high, it counts valid source beats, not confirmed FIFO writes.

The important integration consequence is that `s01_axis_tready` does not prove that a sample was stored.

## Integration Guidance

Use this IP only where the upstream source can tolerate non-storing windows while `s01_axis_tready` remains high.

Do not rely on S01 for:

- Lossless storage of every `TVALID && TREADY` beat.
- Backpressure during internal reset-busy or buffer-management windows.
- Receive-counter values that exactly match payload FIFO write count.
- AXI4-Stream compliance checks that require every accepted S01 beat to appear in the M00 packet payload.

If the upstream source cannot tolerate dropped beats, add buffering, gating, or a protocol adapter outside this IP. Treat `s01_axis_tready` as a source-advance signal, not as a confirmed-storage signal.
