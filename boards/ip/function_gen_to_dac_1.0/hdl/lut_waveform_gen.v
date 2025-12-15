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
    // Clock frequency in Hz (default 156.25 MHz = 156250000)
    parameter integer CLOCK_FREQUENCY = 156250000,
    
    // Phase accumulator width (determines frequency resolution)
    parameter integer PHASE_WIDTH = 32,
    
    // Output data width (output precision)
    parameter integer DATA_WIDTH = 14,
    
    // Lookup table address width (determines table size: 2^LUT_ADDR_WIDTH entries)
    parameter integer LUT_ADDR_WIDTH = 12  // 4096 entries
)
(
    input wire clk,
    input wire rst_n,
    
    // Frequency control (32-bit unsigned integer, units: Hz)
    input wire [31:0] frequency,
    
    // Phase offset (32-bit, normalized to 2^PHASE_WIDTH)
    input wire [PHASE_WIDTH-1:0] phase_offset,
    
    // Output sine and cosine values (unsigned, DATA_WIDTH bits, range 0 to 16383)
    output reg [DATA_WIDTH-1:0] sine_out,
    output reg [DATA_WIDTH-1:0] cosine_out,
    
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
    
    // Calculate: frequency * 2^PHASE_WIDTH / CLOCK_FREQUENCY
    assign phase_increment_64 = (frequency * (64'd1 << PHASE_WIDTH)) / CLOCK_FREQUENCY;
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
    // phase=0 corresponds to sin(0)=0, giving sine_out=8192 (center value)
    wire [PHASE_WIDTH-1:0] phase_unsigned;
    assign phase_unsigned = phase_accum + phase_offset;
    
    // Extract LUT address from phase (use upper bits for table index)
    // Phase is 0 to 2^PHASE_WIDTH-1 representing 0 to 2π
    // LUT address is phase[PHASE_WIDTH-1:PHASE_WIDTH-LUT_ADDR_WIDTH]
    wire [LUT_ADDR_WIDTH-1:0] lut_addr;
    assign lut_addr = phase_unsigned[PHASE_WIDTH-1:PHASE_WIDTH-LUT_ADDR_WIDTH];
    
    // Lookup table for sine values
    // Table contains 2^LUT_ADDR_WIDTH entries
    // Each entry is a signed (DATA_WIDTH+1)-bit value ranging from -8191 to +8191
    // This allows the output to be centered at 8192 in the unsigned 0-16383 range
    reg signed [DATA_WIDTH:0] sine_lut [0:(1<<LUT_ADDR_WIDTH)-1];
    reg signed [DATA_WIDTH:0] cosine_lut [0:(1<<LUT_ADDR_WIDTH)-1];
    
    // Variables for LUT initialization
    integer i;
    real angle;
    real sine_val, cosine_val;
    integer sine_int, cosine_int;
    
    // Initialize lookup tables
    initial begin
        for (i = 0; i < (1 << LUT_ADDR_WIDTH); i = i + 1) begin
            // Calculate angle: i * 2π / (2^LUT_ADDR_WIDTH)
            // Sine and cosine values scaled to range -8191 to +8191
            // This allows output to be centered at 8192 in unsigned 0-16383 range
            angle = (i * 2.0 * 3.14159265358979323846) / (1 << LUT_ADDR_WIDTH);
            sine_val = $sin(angle) * ((1 << (DATA_WIDTH-1)) - 1);  // Scale to -8191 to +8191
            cosine_val = $cos(angle) * ((1 << (DATA_WIDTH-1)) - 1);
            
            sine_int = $rtoi(sine_val);
            cosine_int = $rtoi(cosine_val);
            
            sine_lut[i] = sine_int;
            cosine_lut[i] = cosine_int;
        end
    end
    
    // Lookup table read (registered for timing)
    reg [LUT_ADDR_WIDTH-1:0] lut_addr_reg;
    wire [DATA_WIDTH:0] sine_unsigned_temp, cosine_unsigned_temp;
    
    // Convert signed LUT values (-8191 to +8191) to unsigned (1 to 16383)
    // by adding 8192 (which is 1 << (DATA_WIDTH-1))
    // Center value is 8192, range is 1 to 16383 (stays within 14-bit unsigned bounds)
    assign sine_unsigned_temp = sine_lut[lut_addr_reg] + (1 << (DATA_WIDTH-1));
    assign cosine_unsigned_temp = cosine_lut[lut_addr_reg] + (1 << (DATA_WIDTH-1));
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lut_addr_reg <= {LUT_ADDR_WIDTH{1'b0}};
            sine_out <= 0;
            cosine_out <= 0;
            valid_out <= 1'b0;
        end else begin
            lut_addr_reg <= lut_addr;
            // Convert to unsigned 14-bit by taking lower DATA_WIDTH bits
            // LUT values are -8192 to +8192, adding 8192 gives 0 to 16384
            sine_out <= sine_unsigned_temp[DATA_WIDTH-1:0];
            cosine_out <= cosine_unsigned_temp[DATA_WIDTH-1:0];
            valid_out <= 1'b1;
        end
    end

endmodule

