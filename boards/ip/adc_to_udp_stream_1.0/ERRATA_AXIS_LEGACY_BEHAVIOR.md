# S01 AXI4-Stream Legacy TREADY Behavior Errata

This IP has a known non-standard behavior on its S01 AXI4-Stream input. The IP preserves a legacy always-ready source contract because downstream packet byte ordering depends on that behavior.

## Affected IP

- IP: `adc_to_udp_stream`
- HDL: `hdl/adc_to_udp_stream_v1_0.v`
- Interface: S01 AXI4-Stream slave input
- Affected signals: `s01_axis_tvalid`, `s01_axis_tready`, `s01_axis_tdata`

## Non-Standard Behavior

The S01 input does not fully follow the usual AXI4-Stream assumption that every cycle with `TVALID && TREADY` is stored and later emitted.

In this IP:

- `s01_axis_tready` is tied high.
- FIFO write enables are gated by `s01_axis_tvalid`, selected FIFO readiness, and ping-pong buffer selection.
- The source-visible receive counter advances on `s01_axis_tvalid && s01_axis_tready`. Because `s01_axis_tready` is tied high, this is equivalent to counting valid source beats.
- FIFO write enables are still blocked during internal reset-busy and ping-pong buffer-selection windows even though `s01_axis_tready` remains high.

This means an upstream source can see `s01_axis_tvalid && s01_axis_tready`, advance to the next word, and still have the current word intentionally not written into the payload FIFO.

Cycles where `s01_axis_tvalid` is low are not written into either FIFO and are not counted by `received_counter_s01`.

## Practical Impact

Do not use S01 `TREADY` as proof that a sample was stored.

For an upstream AXI4-Stream master, this IP behaves like an always-ready sink that can internally discard valid words during specific buffer-management windows. A standards-focused AXI4-Stream monitor may report this as an accepted-transfer accounting problem because `TREADY` does not indicate whether the selected FIFO will store the beat.

The output packet byte stream is the supported behavior. The legacy packet checker must continue to pass with:

- Packet indexes 1, 2, and 3 present.
- `pkt_byte_count = 8298` for each packet.
- `Total failing bytes: 0 out of 8192` for each packet payload.
- `Input stimulus complete: 16584 samples driven`.

If strict S01 accepted-transfer behavior conflicts with those packet bytes, the packet-byte behavior has priority for this IP.

## Integration Guidance

Use this IP only where the upstream source can tolerate the legacy always-ready/drop-window behavior.

Avoid designs that require any of the following from S01:

- Lossless storage of every `TVALID && TREADY` beat.
- Backpressure from this IP during internal non-storing windows.
- External accounting that treats the S01 receive counter as equivalent to payload FIFO write count.
- AXI4-Stream compliance checks that require every accepted S01 beat to appear in the M00 packet payload.

When connecting a source that cannot tolerate dropped beats, add buffering, gating, or a protocol adapter outside this IP. Do not infer lossless transfer from `s01_axis_tready`.

The S01 source should still drive `s01_axis_tvalid` correctly. Low-`TVALID` cycles are ignored by the IP.

## Verification Guidance

The packet-byte regression is the primary compatibility check:

```bash
./sim_check_udp_packet.bash
```

Expected packet evidence:

- Three packets are checked.
- Each packet reports `pkt_byte_count = 8298`.
- Each packet reports `Total failing bytes: 0 out of 8192`.
- The input stimulus summary reports `16584 samples driven`.

The AXIS scaffold regression should also pass:

```bash
./sim_adc_to_udp_stream_axis.bash
```

Expected AXIS evidence:

- `PASS: AXIS M00 characterization test passed (0 failures).`
- `verified_packets=3`.
- `stall_done header=1 radio=1 payload=1 final=1`.

AXI4-Stream-focused tests may also be useful, but failures that only report the accepted-transfer mismatch described above should be treated as this documented erratum rather than as a packet-format failure.

## HDL Reference Points

In `hdl/adc_to_udp_stream_v1_0.v`, review:

- `s01_axis_tready` assignment.
- `received_counter_s01` update logic.
- `fifo_0_write_en_s01` and `fifo_1_write_en_s01` assignments.

Those sections define the observable behavior described here.
