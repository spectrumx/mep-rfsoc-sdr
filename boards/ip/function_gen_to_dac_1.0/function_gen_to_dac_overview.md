# function_gen_to_dac Overview

## RFDC DAC Connection Overview

This block is expected to connect directly to the Zynq UltraScale+ RF Data Converter DAC AXI4-Stream input for DAC 0. The intended RFDC DAC configuration is:

| RFDC setting | Value |
|---|---|
| DAC tile/block | DAC 0 |
| Analog Output Data | Real |
| Interpolation Mode | 40 |
| Samples per AXI4-Stream Cycle | 10 |
| Datapath Mode | DUC 0 to Fs/2 |
| Mixer Type | Fine |
| Mixer Mode | I/Q -> Real |
| Decoder Mode | SNR Optimized |
| DAC Sampling Rate | 2048 MHz |
| RFDC reference clock | 491.52 MHz |

The most important implication for `function_gen_to_dac_1_0` is that the output bus is not an arbitrary AXI4-Stream packet interface. It must match the RFDC-generated DAC stream port exactly: data width, word order, signedness, sample cadence, and control-signal expectations must agree with the RFDC IP configuration.

Rate implications:

- The DAC analog sample rate is 2048 MSPS.
- With 40x interpolation, the fabric-side complex waveform rate into the DUC is `2048 MHz / 40 = 51.2 MSPS`.
- The RFDC core expects complex I/Q input samples for this mixer configuration.
- A stream word is 16 bits.
- Each complex sample is made from two interleaved 16-bit words: one I word and one Q word.
- One complex I/Q sample is therefore 32 bits total.
- The RFDC core automatically configures this DAC AXI4-Stream input to a 160-bit `tdata` bus and reports a required AXIS clock of 10.240 MHz.
- A 160-bit AXIS beat contains `160 / 16 = 10` words.
- Since I and Q words are interleaved, those 10 words represent `10 / 2 = 5` complex I/Q samples per AXIS cycle.
- At 10.240 MHz, the stream supplies `10.240 MHz * 5 = 51.2 MSPS` complex samples, which is consistent with the 2048 MSPS DAC rate and 40x interpolation.

Bus-structure implications:

- The required `m00_axis_tdata` width is 160 bits.
- Each 160-bit AXIS beat is made of 10 interleaved 16-bit words.
- The 10 words should be treated as 5 complex samples per beat, not 10 independent real samples.
- Each complex sample contributes one 16-bit I word and one 16-bit Q word.
- The intended structure is interleaved I/Q words, for example `I0, Q0, I1, Q1, I2, Q2, I3, Q3, I4, Q4`, subject to the exact bit ordering used by the RFDC-generated interface.
- AMD PG269 describes RF-DAC PL data streams as 16-bit little-endian words. For the HDL packer, that means the low byte of each 16-bit word should occupy the lower byte lane of that word.
- AMD PG269 also states that for RF-DAC I/Q input streams, even-numbered stream samples are I data and odd-numbered stream samples are Q data. The HDL and testbench should name and check the words explicitly.
- PG269's example-design digital data format describes each RF-DAC/RF-ADC word interface as 16-bit two's-complement. The RF-DAC itself has 14-bit resolution on a 16-bit digital signal-processing path, with RF-DAC values MSB-aligned into the 16-bit word. For RF-DAC samples this corresponds to a signed 14-bit value shifted left by two bits:
  - Maximum positive RF-DAC code: `+8191 -> 16'h7ffc`
  - Positive one: `+1 -> 16'h0004`
  - Zero: `0 -> 16'h0000`
  - Negative one: `-1 -> 16'hfffc`
  - Minimum negative RF-DAC code: `-8192 -> 16'h8000`

```text
20-byte RFDC DAC AXI4-Stream beat map

One 160-bit m00_axis beat = 20 bytes = 10 16-bit words = 5 interleaved I/Q samples

Beat   Stream bytes   B0      B1      B2      B3      B4      B5      B6      B7      B8      B9      B10     B11     B12     B13     B14     B15     B16     B17     B18     B19
----   ------------   ------  ------  ------  ------  ------  ------  ------  ------  ------  ------  ------  ------  ------  ------  ------  ------  ------  ------  ------  ------
  0      0..19        I0[7:0] I0[15:8] Q0[7:0] Q0[15:8] I1[7:0] I1[15:8] Q1[7:0] Q1[15:8] I2[7:0] I2[15:8] Q2[7:0] Q2[15:8] I3[7:0] I3[15:8] Q3[7:0] Q3[15:8] I4[7:0] I4[15:8] Q4[7:0] Q4[15:8]
  1     20..39        I5[7:0] I5[15:8] Q5[7:0] Q5[15:8] I6[7:0] I6[15:8] Q6[7:0] Q6[15:8] I7[7:0] I7[15:8] Q7[7:0] Q7[15:8] I8[7:0] I8[15:8] Q8[7:0] Q8[15:8] I9[7:0] I9[15:8] Q9[7:0] Q9[15:8]
  2     40..59        I10[7:0] I10[15:8] Q10[7:0] Q10[15:8] I11[7:0] I11[15:8] Q11[7:0] Q11[15:8] I12[7:0] I12[15:8] Q12[7:0] Q12[15:8] I13[7:0] I13[15:8] Q13[7:0] Q13[15:8] I14[7:0] I14[15:8] Q14[7:0] Q14[15:8]
 ...     ...          ...     ...      ...     ...      ...     ...      ...     ...      ...     ...      ...     ...      ...     ...      ...     ...      ...     ...      ...     ...

Legend:
  I* = 16-bit in-phase word for complex sample *
  Q* = 16-bit quadrature word for complex sample *
  Each word is a signed two's-complement RF-DAC word.
  RF-DAC 14-bit sample values are MSB-aligned into the 16-bit word; the two LSBs are zero for exact 14-bit DAC codes.
  Each 16-bit word is little-endian: the low byte is carried first in the lower byte lane.
  With this map, B0 is the least-significant byte of I0, B1 is the most-significant byte of I0, B2 is the least-significant byte of Q0, and so on.
  Even-numbered stream words are I data; odd-numbered stream words are Q data.
  The RFDC DAC stream should be treated as continuous sample data, not packet data.
  The generated RFDC DAC 0 interface should still be checked for bit-vector indexing, but the RFDC word byte order is little-endian.
```

Current HDL comparison:

- The current HDL sets `C_M00_AXIS_TDATA_WIDTH = 160` and `C_M00_AXIS_TKEEP_WIDTH = 20`, which matches the RFDC-reported bus width.
- The current comments are partly consistent with the RFDC contract when read as "5 I/Q pairs", but misleading when read as "10 samples x 16 bits". The HDL should consistently describe this as 5 complex I/Q samples per AXIS beat.
- The current waveform generator clock constant is `156250000`, but the RFDC-derived complex sample rate is 51.2 MSPS and the required AXIS beat clock is 10.240 MHz. This means programmed frequencies will be wrong unless the NCO advances once per complex sample at the 51.2 MSPS logical sample rate, not once per 10.240 MHz AXIS beat without generating the 5 in-beat sample phases.
- The current testbench drives `m00_axis_aclk` at 156.25 MHz. It should instead model the RFDC-required 10.240 MHz AXIS clock for this configuration.
- The current packer collects one sine/cosine pair per `m00_axis_aclk` cycle, waits until 5 pairs are collected, and then emits one 160-bit beat. At a 10.240 MHz AXIS clock, this implementation would only emit one beat every 5 AXIS cycles, which is too slow by 5x. The block should generate and pack all 5 complex samples for each AXIS beat.
- The current I/Q words are unsigned 14-bit values widened to 16 bits. This does not match PG269's signed two's-complement RF-DAC word format or the 14-bit-to-16-bit MSB alignment requirement.
- The current `tkeep` and `tlast` signals come from a packet-style AXIS template. PG269 describes the RF-DAC PL data path as continuous data streams into gearbox FIFOs, and the RF-DAC user-interface examples expose `tdata`, `tvalid`, and `tready`. The generated RFDC DAC 0 interface should be checked, but the function generator should not rely on packet boundaries or byte strobes for the DAC stream.

Near-term decision: lock the HDL and testbench to the RFDC-generated contract of 160-bit `tdata`, 10.240 MHz AXIS clock, 10 interleaved little-endian signed 16-bit words per beat, 5 complex I/Q samples per beat, and 14-bit RF-DAC codes MSB-aligned into the 16-bit words.

## Purpose

`function_gen_to_dac_1_0` is intended to be packaged as a Vivado block-design IP for an RFSoC design. The block should be controlled by software over AXI4-Lite and should drive an RF Data Converter DAC path over AXI4-Stream with generated waveform samples.

At a high level, the target behavior is:

1. Software writes control registers for waveform type, frequency, amplitude, phase, offset, and enable.
2. The HDL generates a numerically controlled waveform in the DAC sample clock domain.
3. The waveform samples are packed into the AXI4-Stream word format expected by the RFDC DAC configuration.
4. The stream remains valid, continuous, and correctly formatted under reset, enable/disable, and AXIS backpressure conditions.

## Current HDL Structure

The current top-level module is `hdl/function_gen_to_dac_v1.0.v`.

Interfaces:

- `S00_AXI`: 32-bit AXI4-Lite slave register interface.
- `M00_AXIS`: AXI4-Stream master intended to feed the DAC-side stream path.

Current control registers:

| Address | Register | Current use |
|---:|---|---|
| `0x00` | `waveform_type_ctrl` | Stored, but not used by the generator. |
| `0x04` | `frequency_ctrl` | Drives `lut_waveform_gen.frequency`. |
| `0x08` | `amplitude_ctrl` | Used as a right-shift count. |
| `0x0C` | `phase_ctrl` | Drives `lut_waveform_gen.phase_offset`. |
| `0x10` | `offset_ctrl` | Stored, but not used. |
| `0x14` | `enable_ctrl` | Bit 0 enables sample collection into the AXIS packer. |

Waveform generation:

- `lut_waveform_gen` uses a 32-bit phase accumulator.
- Frequency is provided in Hz.
- Phase increment is calculated as `(frequency * 2^32) / 156250000`.
- The upper phase bits index a 4096-entry sine/cosine lookup table.
- The LUT currently produces unsigned 14-bit values centered around `8192`.
- The RFDC target format is signed two's-complement 16-bit words containing 14-bit RF-DAC sample values shifted left by two bits, so the LUT output format must be changed before connecting to the DAC.

AXIS packing:

- `SAMPLES_PER_PACKET` is currently fixed at 10.
- The top-level packs alternating sine/cosine values into ten 16-bit words.
- The resulting stream word is 160 bits wide:
  - `{sample_buffer[9], ..., sample_buffer[0]}`
- `tkeep` is all ones, but this is packet-style AXIS metadata and may not exist on the generated RFDC DAC stream interface.
- `tuser` is tied to `0`.
- `tlast` is asserted with each packed 160-bit output word, but the RFDC DAC stream should be treated as a continuous sample stream rather than packetized transfers.

## Current Simulation State

Existing simulations:

- `sim_lut_waveform_gen.bash` runs `lut_waveform_gen_tb.sv`.
- `sim_function_gen_to_dac.bash` runs `function_gen_to_dac_tb.sv`.

`lut_waveform_gen_tb.sv` currently verifies:

- A 2 MHz requested frequency.
- Roughly two rising center crossings over the test window.
- Sine/cosine amplitude spans most of the 14-bit unsigned range.

The captured LUT simulation result passes those checks.

`function_gen_to_dac_tb.sv` currently verifies:

- AXI4-Lite writes and reads for waveform type, frequency, amplitude, and enable.
- The simulation waits after enable is asserted.

The captured top-level simulation result passes those checks, but this is still a shallow test. It does not verify AXIS output beats, RF-DAC word format, stream continuity, frequency accuracy at the output interface, reset behavior, disabled behavior, or backpressure behavior.

## RFSoC Integration Concerns

### 1. DAC sample format does not match PG269

The LUT currently emits unsigned offset-binary-like 14-bit samples centered at `8192`. PG269 documents the RF-DAC word interface as 16-bit two's-complement, with 14-bit RF-DAC resolution MSB-aligned into the 16-bit word. The current HDL therefore sends the wrong numeric format for the RFDC DAC input.

Required target format for this configuration:

- 160-bit `tdata` per AXIS beat.
- Ten 16-bit little-endian words per beat.
- Five interleaved complex I/Q samples per beat.
- Even-numbered words are I; odd-numbered words are Q.
- Each word is signed two's-complement.
- 14-bit RF-DAC values are MSB-aligned into the 16-bit word, equivalent to shifting a signed 14-bit sample left by two bits.

The bus width matches the RFDC-reported 160-bit interface, but the current unsigned sample format, generated rate, and beat-packing behavior do not match.

### 2. AXI4-Lite implementation is incomplete

The current register interface ties `awready`, `wready`, and `arready` high and updates registers only when `awvalid` and `wvalid` are high in the same cycle. AXI4-Lite allows write address and write data channels to arrive independently, so this can miss legal writes from a real AXI master.

Also:

- `wstrb` is ignored.
- No invalid-address error response is generated.
- The testbench writes `8'hFF` into a 4-bit strobe signal, which truncates but hides the interface width issue.

Next step: replace this with a standard AXI4-Lite slave register implementation or generate one from the Vivado IP packager template and adapt the register map.

### 3. Control registers cross clock domains unsafely

Registers are written in `s00_axi_aclk` but consumed in `m00_axis_aclk`. If these clocks are not the same physical clock in the block design, this is an unsafe CDC path.

Options:

- Require `s00_axi_aclk == m00_axis_aclk` and document/package the IP that way.
- Add proper CDC for control/status:
  - Synchronize single-bit enable.
  - Transfer multi-bit frequency, phase, amplitude, offset, and waveform type using a valid/toggle handshake.
  - Apply updates only at controlled sample boundaries to avoid waveform glitches.

For an RFSoC block-design IP, the safer design is to support separate AXI-Lite and DAC stream clocks with explicit CDC.

### 4. Waveform type and offset are not implemented

`waveform_type_ctrl` and `offset_ctrl` are currently stored but not used.

Planned behavior should be defined for at least:

- Sine.
- Cosine.
- DC.
- Possibly square, triangle, ramp, PRBS, or tone-pair modes.

Offset should be applied in signed sample space, with saturation or wrapping explicitly chosen, before the final 14-bit-to-16-bit RF-DAC word alignment.

### 5. Amplitude scaling is mathematically wrong for centered unsigned samples

Current scaling right-shifts the whole unsigned sample:

```verilog
scaled_sine = ({2'b00, waveform_sine_out} >> amplitude_ctrl[3:0]);
```

For a centered unsigned waveform, this changes both AC amplitude and DC center. A half-scale sine becomes centered near `4096`, not near the original midpoint.

Preferred approach:

1. Generate or convert the waveform to signed centered samples.
2. Apply signed gain.
3. Add offset if needed.
4. Saturate to the signed 14-bit RF-DAC sample range, `-8192..+8191`.
5. Shift the signed 14-bit sample left by two bits to form the 16-bit MSB-aligned RF-DAC word.
6. Pack the signed little-endian 16-bit words into the RFDC stream format.

### 6. LUT initialization may not be synthesis-ready

`lut_waveform_gen` initializes the sine/cosine tables with `real`, `$sin`, and `$rtoi` in an `initial` block. This is convenient for simulation, but it should be confirmed through Vivado synthesis.

More robust options:

- Generate a static Verilog ROM with integer constants.
- Use `$readmemh` with a checked-in memory file.
- Use Xilinx DDS Compiler if that better matches RFSoC timing and resource goals.

### 7. AXIS behavior needs tightening

The current packer emits a 160-bit beat after collecting ten 16-bit words and holds `tvalid` until `tready`.

Open issues:

- `output_data` and `sample_buffer` are not reset.
- `enable_ctrl` deassertion does not clear a partial in-progress beat.
- Backpressure stops sample collection while the phase accumulator continues, causing dropped waveform samples and phase discontinuity at the output.
- `tlast` is asserted on every output beat even though the RFDC DAC stream is not packet-oriented.
- `C_M00_AXIS_TDATA_WIDTH`, `C_M00_AXIS_TKEEP_WIDTH`, and `SAMPLES_PER_PACKET` can be configured inconsistently. For this RFDC contract, the useful invariant is 10 16-bit words per 160-bit beat.
- PG269 notes that RF-DAC FIFOs begin accepting data after power-up when `tready` asserts and that RF-DAC does not use `tvalid` to gate the data. The block-design integration should ensure valid, deterministic samples are present whenever the RFDC can accept them.

For a DAC-driving source, decide whether the stream must be continuous and whether backpressure is expected. If the RFDC DAC path does not apply backpressure in the final design, the testbench should still prove the block behaves sanely when `tready` toggles.
