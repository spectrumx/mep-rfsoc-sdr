# function_gen_to_dac Overview

## RFDC DAC Connection Overview

`function_gen_to_dac_1.0` is packaged as a Vivado block-design IP that is controlled over AXI4-Lite and drives a Zynq UltraScale+ RF Data Converter DAC AXI4-Stream input. The active IP contract is the migrated RFDC configuration below.

| RFDC setting | Value |
|---|---|
| DAC tile/block | DAC 0 |
| Analog Output Data | Real |
| Interpolation Mode | 16 |
| Samples per AXI4-Stream Cycle | 4 |
| Datapath Mode | DUC 0 to Fs/2 |
| Mixer Type | Fine |
| Mixer Mode | I/Q -> Real |
| Decoder Mode | SNR Optimized |
| DAC Sampling Rate | 1024 MHz |
| RFDC reference clock | 491.52 MHz |

Rate and stream implications:

- Fabric-side complex sample rate: `1024 MSPS / 16 = 64 MSPS`.
- RFDC samples per AXI4-Stream cycle means 4 total signed 16-bit RFDC stream words per accepted AXIS beat.
- Each complex sample is an interleaved I/Q pair, so one beat carries 2 complex samples.
- Required `m00_axis_tdata` width: `4 words * 16 bits = 64 bits`.
- Required AXIS beat clock: `64 MSPS / 2 complex samples per beat = 32 MHz`.
- The stream is continuous sample data, not a packet interface. Packet-only ports are intentionally absent: no `tlast`, no `tkeep`, no `tuser`.

## Beat Map

The active word order is `I0, Q0, I1, Q1`. Each word is a signed two's-complement RF-DAC word. RF-DAC 14-bit sample values are saturated to `[-8192,+8191]`, then MSB-aligned into the 16-bit stream word by shifting left two bits.

```text
8-byte RFDC DAC AXI4-Stream beat map

One 64-bit m00_axis beat = 8 bytes = 4 signed 16-bit words = 2 interleaved I/Q samples

Beat   Stream bytes   B0      B1       B2      B3       B4      B5       B6      B7
----   ------------   ------  -------  ------  -------  ------  -------  ------  -------
  0      0..7         I0[7:0] I0[15:8] Q0[7:0] Q0[15:8] I1[7:0] I1[15:8] Q1[7:0] Q1[15:8]
  1      8..15        I2[7:0] I2[15:8] Q2[7:0] Q2[15:8] I3[7:0] I3[15:8] Q3[7:0] Q3[15:8]
  2     16..23        I4[7:0] I4[15:8] Q4[7:0] Q4[15:8] I5[7:0] I5[15:8] Q5[7:0] Q5[15:8]

Legend:
  I* = 16-bit in-phase word for complex sample *
  Q* = 16-bit quadrature word for complex sample *
  Each 16-bit word is little-endian within its word lane.
```

Representative RF-DAC word values:

- Maximum positive RF-DAC code: `+8191 -> 16'h7ffc`
- Positive one: `+1 -> 16'h0004`
- Zero: `0 -> 16'h0000`
- Negative one: `-1 -> 16'hfffc`
- Minimum negative RF-DAC code: `-8192 -> 16'h8000`

## Current HDL Structure

The top-level module is `hdl/function_gen_to_dac_v1.0.v`.

Interfaces:

- `S00_AXI`: 32-bit AXI4-Lite slave register interface.
- `M00_AXIS`: AXI4-Stream master intended to feed the RFDC DAC-side stream path.

Active stream constants:

- `C_M00_AXIS_TDATA_WIDTH = 64`
- `WORDS_PER_BEAT = 4`
- `COMPLEX_SAMPLES_PER_BEAT = 2`
- `LOGICAL_SAMPLE_RATE = 64000000`
- `m00_axis_aclk` package frequency metadata: `32000000`

The HDL instantiates two `lut_waveform_gen` lanes. The second lane advances by one logical complex-sample phase offset so each accepted AXIS beat carries two consecutive I/Q samples. Sine/cosine and DC modes use the same `I0,Q0,I1,Q1` packing.

## Register Map

The current HDL and package metadata use compact byte offsets. These offsets are intentionally documented exactly as implemented.

| Offset | Register | Use |
|---:|---|---|
| `0x00` | `WAVEFORM_TYPE` | `0` zero output, `1` sine/cosine, `2` DC I/Q. Other values produce zero output. |
| `0x01` | `FREQUENCY` | Output frequency in Hz for sine/cosine mode. |
| `0x02` | `AMPLITUDE` | Q15 amplitude scale. `0x0000` mutes waveform component, `0x7FFF` is near full scale. |
| `0x03` | `PHASE` | 32-bit phase offset in phase-accumulator units. |
| `0x04` | `OFFSET` | Signed 14-bit RF-DAC code in bits `[13:0]`; used as I in DC mode, with Q set to zero. |
| `0x05` | `ENABLE` | Bit 0 enables stream output. |

Configuration registers are written in `s00_axi_aclk` and transferred to the DAC clock domain with a request/acknowledge CDC bundle. The V4.4 simulation checkpoint fixed the publish/coalescing path so same-cycle writes are not lost when a prior request is pending.

## Package Metadata

The IP package exports:

- VLNV: `user.org:user:function_gen_to_dac:1.0`
- AXI4-Lite interface: `S00_AXI`
- RFDC-facing stream interface: `M00_AXIS`
- `M00_AXIS` physical ports: `m00_axis_tdata[63:0]`, `m00_axis_tvalid`, `m00_axis_tready`
- `M00_AXIS` metadata: `TDATA_NUM_BYTES = 8`, no packet-only ports
- `M00_AXIS_CLK.FREQ_HZ = 32000000`
- Fixed model parameter `C_M00_AXIS_TDATA_WIDTH = 64`

## Verification State

The migrated IP has these saved checkpoints:

- `hdl/sim_lut_waveform_gen_results.txt`: standalone LUT simulation passed at 64 MSPS.
- `hdl/v4_4_results.txt`: top-level simulation passed at 64-bit stream width, 4 words per beat, 2 complex samples per beat, 32 MHz AXIS, and 64 MSPS logical rate.
- `hdl/v5_3_results.txt`: RFDC connectivity simulation passed with `I0,Q0,I1,Q1` decoding and no packet-only stream ports.
- `v6_5_results.txt`: Vivado package validation found the IP in the catalog, created a BD cell, and confirmed `M00_AXIS` metadata and `m00_axis_tdata[63:0]`.

Future agents should treat `freq_migration.md` as the active checklist until it is closed.
