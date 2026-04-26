///////////////////////////////////////////////////////////////////////////////
// lut_waveform_gen.v
//
// Lookup Table (LUT) based Waveform Generator
//
// This module generates sine and cosine waveforms using a lookup table.
// It uses a phase accumulator (NCO) to generate the phase, then uses the
// phase to index into a precomputed sine/cosine lookup table.
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

module lut_waveform_gen #
(
    // Logical sample rate (NCO clock) in Hz (default 51.2 MSPS = 51200000)
    parameter integer CLOCK_FREQUENCY = 51200000,

    // Phase accumulator width (determines frequency resolution)
    parameter integer PHASE_WIDTH = 32,

    // Output data width (output precision)
    parameter integer DATA_WIDTH = 14,

    // Lookup table address width (determines table size: 2^LUT_ADDR_WIDTH entries)
    parameter integer LUT_ADDR_WIDTH = 12, // 4096 entries

    // Number of logical sample steps the phase accumulator advances per clock cycle.
    // Default 1: one sample per clock. Set to 5 for 51.2 MSPS at 10.240 MHz AXIS clock.
    parameter integer SAMPLES_PER_CLOCK = 1
)
(
    input wire clk,
    input wire rst_n,
    
    // Frequency control (32-bit unsigned integer, units: Hz)
    input wire [31:0] frequency,
    
    // Phase offset (32-bit, normalized to 2^PHASE_WIDTH)
    input wire [PHASE_WIDTH-1:0] phase_offset,

    // Per-instance phase step offset in units of one logical sample step.
    // Used when SAMPLES_PER_CLOCK > 1 to generate consecutive samples from
    // multiple instances. Default 0.
    input wire [PHASE_WIDTH-1:0] phase_step_offset,

    // Output sine and cosine values (signed, DATA_WIDTH bits)
    // Range: -8192 to +8191. Positive peak clamped to +8191, negative peak to -8192.
    output reg signed [DATA_WIDTH-1:0] sine_out,
    output reg signed [DATA_WIDTH-1:0] cosine_out,
    
    // Output valid signal
    output reg valid_out
);

    // Phase accumulator register
    reg [PHASE_WIDTH-1:0] phase_accum;
    
    // Phase increment calculation using fixed-point multiplication
    // phase_increment = (frequency * 2^PHASE_WIDTH) / CLOCK_FREQUENCY
    // Use 64-bit intermediate to avoid overflow
    wire [63:0] phase_increment_64;
    wire [PHASE_WIDTH-1:0] phase_increment;
    
    // Calculate: frequency * SAMPLES_PER_CLOCK * 2^PHASE_WIDTH / CLOCK_FREQUENCY
    assign phase_increment_64 = (frequency * SAMPLES_PER_CLOCK * (64'd1 << PHASE_WIDTH)) / CLOCK_FREQUENCY;
    assign phase_increment = phase_increment_64[PHASE_WIDTH-1:0];
    
    // Phase accumulator update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_accum <= {PHASE_WIDTH{1'b0}};
        end else begin
            phase_accum <= phase_accum + phase_increment;
        end
    end
    
   // Phase with offset
    // phase=0 corresponds to sin(0)=0 (sine_out=0), cos(0)=1 (cosine_out≈+8191)
    // phase_step_offset adds an extra offset in units of one logical sample step
    wire [PHASE_WIDTH-1:0] phase_unsigned;
    assign phase_unsigned = phase_accum + phase_offset + phase_step_offset;
    
    // Extract LUT address from phase (use upper bits for table index)
    // Phase is 0 to 2^PHASE_WIDTH-1 representing 0 to 2π
    // LUT address is phase[PHASE_WIDTH-1:PHASE_WIDTH-LUT_ADDR_WIDTH]
    wire [LUT_ADDR_WIDTH-1:0] lut_addr;
    assign lut_addr = phase_unsigned[PHASE_WIDTH-1:PHASE_WIDTH-LUT_ADDR_WIDTH];
    
    // Lookup table for sine and cosine values
    // Table contains 2^LUT_ADDR_WIDTH entries
    // Each entry is a signed DATA_WIDTH-bit value ranging from -8192 to +8191
    //
    // Endpoint behavior:
    //   - Positive peak (cos(0), sin(π/2)): clamped to +8191 (max signed 14-bit)
    //   - Negative peak (cos(π), sin(3π/2)): clamped to -8192 (min signed 14-bit)
    //   - cos(0) = 8192 mathematically, clamped to +8191 to fit signed 14-bit range
    //   - LUT quantization means most indices never hit exact ±8192; clamping only
    //     affects index 0 for cosine and index 3072 for cosine (π radians)
    reg signed [DATA_WIDTH-1:0] sine_lut [0:(1<<LUT_ADDR_WIDTH)-1];
    reg signed [DATA_WIDTH-1:0] cosine_lut [0:(1<<LUT_ADDR_WIDTH)-1];
    
    // Variables for LUT initialization
    integer i;
    real angle;
    real sine_val, cosine_val;
    integer sine_int, cosine_int;
    
    // Initialize lookup tables
    initial begin
        for (i = 0; i < (1 << LUT_ADDR_WIDTH); i = i + 1) begin
            // Calculate angle: i * 2π / (2^LUT_ADDR_WIDTH)
            // Sine and cosine values scaled to signed 14-bit range -8192 to +8191
            angle = (i * 2.0 * 3.14159265358979323846) / (1 << LUT_ADDR_WIDTH);
            sine_val = $sin(angle) * (1 << (DATA_WIDTH-1));
            cosine_val = $cos(angle) * (1 << (DATA_WIDTH-1));

            sine_int = $rtoi(sine_val);
            cosine_int = $rtoi(cosine_val);

            // Clamp to signed 14-bit range [-8192, +8191]
            if (sine_int > ((1 << (DATA_WIDTH-1)) - 1)) sine_int = (1 << (DATA_WIDTH-1)) - 1;
            if (sine_int < -(1 << (DATA_WIDTH-1))) sine_int = -(1 << (DATA_WIDTH-1));
            if (cosine_int > ((1 << (DATA_WIDTH-1)) - 1)) cosine_int = (1 << (DATA_WIDTH-1)) - 1;
            if (cosine_int < -(1 << (DATA_WIDTH-1))) cosine_int = -(1 << (DATA_WIDTH-1));

            sine_lut[i] = sine_int;
            cosine_lut[i] = cosine_int;
        end
    end
    
    // Lookup table read (registered for timing)
    reg [LUT_ADDR_WIDTH-1:0] lut_addr_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lut_addr_reg <= {LUT_ADDR_WIDTH{1'b0}};
            sine_out <= 0;
            cosine_out <= 0;
            valid_out <= 1'b0;
        end else begin
            lut_addr_reg <= lut_addr;
            // Output signed 14-bit LUT values directly
            sine_out <= sine_lut[lut_addr_reg];
            cosine_out <= cosine_lut[lut_addr_reg];
            valid_out <= 1'b1;
        end
    end

endmodule

