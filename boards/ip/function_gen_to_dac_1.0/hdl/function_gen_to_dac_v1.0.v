////////////////////////////////////////////////////////////////////////////////
// function_gen_to_dac_v1.0.v
//
// Function Generator to RF-DAC Block
//
// Generates sine/cosine waveforms and outputs them to an RF-DAC via AXI4-Stream.
//
// RFDC stream contract:
//   - m00_axis_tdata: 160 bits (10 signed 16-bit words)
//   - 10 words per beat = 5 interleaved complex samples (I0,Q0,I1,Q1,...,I4,Q4)
//   - m00_axis_aclk: 10.240 MHz AXIS beat clock
//   - Logical complex sample rate: 51.2 MSPS
//   - One beat emitted every AXIS clock cycle when enabled
//
// Implementation: 5 lut_waveform_gen instances, each advancing 5 phase steps
// per clock (SAMPLES_PER_CLOCK=5), with phase_step_offset 0..4 to produce
// 5 consecutive samples from one beat.
//
// Startup: a 2-cycle pipeline flush ensures the first accepted beat contains
// five distinct consecutive samples, not stale reset-state values.
//
// Backpressure: under backpressure (tvalid && !tready), the waveform generators
// continue advancing internally. Dropped samples cause the output waveform to
// jump in phase when streaming resumes. This preserves wall-clock phase
// continuity at the cost of sample continuity during stalls.
//
////////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

module function_gen_to_dac_1_0 #
(
    // AXI4-Lite slave bus parameters
    parameter integer C_S00_AXI_DATA_WIDTH    = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH    = 7,

    // RFDC DAC AXI4-Stream master bus parameters
    parameter integer C_M00_AXIS_TDATA_WIDTH  = 160
)
(
    // Ports of Axi Slave Bus Interface S00_AXI
    input wire  s00_axi_aclk,
    input wire  s00_axi_aresetn,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
    input wire [2 : 0] s00_axi_awprot,
    input wire  s00_axi_awvalid,
    output wire  s00_axi_awready,
    input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
    input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
    input wire  s00_axi_wvalid,
    output wire  s00_axi_wready,
    output wire [1 : 0] s00_axi_bresp,
    output wire  s00_axi_bvalid,
    input wire  s00_axi_bready,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
    input wire [2 : 0] s00_axi_arprot,
    input wire  s00_axi_arvalid,
    output wire  s00_axi_arready,
    output reg [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
    output wire [1 : 0] s00_axi_rresp,
    output wire  s00_axi_rvalid,
    input wire  s00_axi_rready,

    // Ports of RFDC DAC AXI4-Stream Master M00_AXIS
    input wire m00_axis_aclk,
    input wire m00_axis_aresetn,
    output wire m00_axis_tvalid,
    output wire [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata,
    input wire m00_axis_tready
);

    // RFDC stream localparams
    localparam integer WORD_WIDTH              = 16;
    localparam integer WORDS_PER_BEAT          = 10;
    localparam integer COMPLEX_SAMPLES_PER_BEAT = 5;

    // Logical sample rate for the NCO (51.2 MSPS)
    localparam integer LOGICAL_SAMPLE_RATE     = 51200000;

    // Phase accumulator width (must match lut_waveform_gen)
    localparam integer PHASE_WIDTH             = 32;

    // Function generator control registers
    reg [31:0] waveform_type_ctrl;
    reg [31:0] frequency_ctrl;
    reg [31:0] amplitude_ctrl;
    reg [31:0] phase_ctrl;
    reg [31:0] offset_ctrl;
    reg [31:0] enable_ctrl;

    // Per-sample phase increment: freq * 2^PHASE_WIDTH / LOGICAL_SAMPLE_RATE
    wire [63:0] phase_inc_64;
    wire [31:0] phase_inc;
    assign phase_inc_64 = (frequency_ctrl * (64'd1 << PHASE_WIDTH)) / LOGICAL_SAMPLE_RATE;
    assign phase_inc = phase_inc_64[PHASE_WIDTH-1:0];

    // Phase step offsets for samples 0..4
    wire [31:0] phase_step0;
    wire [31:0] phase_step1;
    wire [31:0] phase_step2;
    wire [31:0] phase_step3;
    wire [31:0] phase_step4;
    assign phase_step0 = 32'd0;
    assign phase_step1 = phase_inc;
    assign phase_step2 = phase_inc + phase_inc;
    assign phase_step3 = phase_inc + phase_inc + phase_inc;
    assign phase_step4 = phase_inc + phase_inc + phase_inc + phase_inc;

    // Waveform generator outputs (signed 14-bit)
    wire signed [13:0] sine0;
    wire signed [13:0] cosine0;
    wire signed [13:0] sine1;
    wire signed [13:0] cosine1;
    wire signed [13:0] sine2;
    wire signed [13:0] cosine2;
    wire signed [13:0] sine3;
    wire signed [13:0] cosine3;
    wire signed [13:0] sine4;
    wire signed [13:0] cosine4;

    // Separate valid wires for each generator instance
    wire valid0;
    wire valid1;
    wire valid2;
    wire valid3;
    wire valid4;

    // Sample 0: current phase
    lut_waveform_gen #(
        .CLOCK_FREQUENCY(LOGICAL_SAMPLE_RATE),
        .PHASE_WIDTH(PHASE_WIDTH),
        .DATA_WIDTH(14),
        .LUT_ADDR_WIDTH(12),
        .SAMPLES_PER_CLOCK(COMPLEX_SAMPLES_PER_BEAT)
    ) u_wave0 (
        .clk(m00_axis_aclk),
        .rst_n(m00_axis_aresetn),
        .frequency(frequency_ctrl),
        .phase_offset(phase_ctrl),
        .phase_step_offset(phase_step0),
        .sine_out(sine0),
        .cosine_out(cosine0),
        .valid_out(valid0)
    );

    // Sample 1: phase + 1 step
    lut_waveform_gen #(
        .CLOCK_FREQUENCY(LOGICAL_SAMPLE_RATE),
        .PHASE_WIDTH(PHASE_WIDTH),
        .DATA_WIDTH(14),
        .LUT_ADDR_WIDTH(12),
        .SAMPLES_PER_CLOCK(COMPLEX_SAMPLES_PER_BEAT)
    ) u_wave1 (
        .clk(m00_axis_aclk),
        .rst_n(m00_axis_aresetn),
        .frequency(frequency_ctrl),
        .phase_offset(phase_ctrl),
        .phase_step_offset(phase_step1),
        .sine_out(sine1),
        .cosine_out(cosine1),
        .valid_out(valid1)
    );

    // Sample 2: phase + 2 steps
    lut_waveform_gen #(
        .CLOCK_FREQUENCY(LOGICAL_SAMPLE_RATE),
        .PHASE_WIDTH(PHASE_WIDTH),
        .DATA_WIDTH(14),
        .LUT_ADDR_WIDTH(12),
        .SAMPLES_PER_CLOCK(COMPLEX_SAMPLES_PER_BEAT)
    ) u_wave2 (
        .clk(m00_axis_aclk),
        .rst_n(m00_axis_aresetn),
        .frequency(frequency_ctrl),
        .phase_offset(phase_ctrl),
        .phase_step_offset(phase_step2),
        .sine_out(sine2),
        .cosine_out(cosine2),
        .valid_out(valid2)
    );

    // Sample 3: phase + 3 steps
    lut_waveform_gen #(
        .CLOCK_FREQUENCY(LOGICAL_SAMPLE_RATE),
        .PHASE_WIDTH(PHASE_WIDTH),
        .DATA_WIDTH(14),
        .LUT_ADDR_WIDTH(12),
        .SAMPLES_PER_CLOCK(COMPLEX_SAMPLES_PER_BEAT)
    ) u_wave3 (
        .clk(m00_axis_aclk),
        .rst_n(m00_axis_aresetn),
        .frequency(frequency_ctrl),
        .phase_offset(phase_ctrl),
        .phase_step_offset(phase_step3),
        .sine_out(sine3),
        .cosine_out(cosine3),
        .valid_out(valid3)
    );

    // Sample 4: phase + 4 steps
    lut_waveform_gen #(
        .CLOCK_FREQUENCY(LOGICAL_SAMPLE_RATE),
        .PHASE_WIDTH(PHASE_WIDTH),
        .DATA_WIDTH(14),
        .LUT_ADDR_WIDTH(12),
        .SAMPLES_PER_CLOCK(COMPLEX_SAMPLES_PER_BEAT)
    ) u_wave4 (
        .clk(m00_axis_aclk),
        .rst_n(m00_axis_aresetn),
        .frequency(frequency_ctrl),
        .phase_offset(phase_ctrl),
        .phase_step_offset(phase_step4),
        .sine_out(sine4),
        .cosine_out(cosine4),
        .valid_out(valid4)
    );

    // All generators share the same phase accumulator advancement, so
    // their valid signals should all transition at the same time.
    // Use valid0 as the representative pipeline-valid indicator.
    wire all_valid;
    assign all_valid = valid0 && valid1 && valid2 && valid3 && valid4;

    // Startup guard: suppress tvalid for first 2 cycles after enable goes high.
    // The LUT has a 2-cycle pipeline (lut_addr_reg latches current address,
    // then outputs are read from the latched address). When enable transitions
    // from 0 to 1, the first beat's LUT outputs may contain stale data from
    // the disabled state. A 2-cycle delay after enable ensures the pipeline
    // has flushed and all 5 generators produce distinct consecutive samples.
    reg enable_d1;
    wire enable_rise;
    reg [1:0] startup_count;
    wire startup_ok;

    assign enable_rise = enable_ctrl[0] && !enable_d1;

    always @(posedge m00_axis_aclk or negedge m00_axis_aresetn) begin
        if (!m00_axis_aresetn) begin
            enable_d1 <= 1'b0;
            startup_count <= 2'd0;
        end else begin
            enable_d1 <= enable_ctrl[0];
            if (enable_rise) begin
                startup_count <= 2'd0;
            end else if (enable_ctrl[0] && startup_count < 2'd2) begin
                startup_count <= startup_count + 1'b1;
            end
        end
    end
    assign startup_ok = (startup_count >= 2'd2);

    // AXI4-Stream output
    reg [C_M00_AXIS_TDATA_WIDTH-1:0] output_data;
    reg output_valid;

    assign m00_axis_tvalid = output_valid;
    assign m00_axis_tdata  = output_data;

    // Pack and output one beat per AXIS clock cycle
    always @(posedge m00_axis_aclk or negedge m00_axis_aresetn) begin
        if (!m00_axis_aresetn) begin
            output_data  <= {C_M00_AXIS_TDATA_WIDTH{1'b0}};
            output_valid <= 1'b0;
        end else begin
            // Pack 10 signed 16-bit words from 5 complex samples
            // Sign-extend 14-bit LUT values to 16-bit
            output_data <= {
                {{2{cosine4[13]}}, cosine4},   // word9  Q4
                {{2{sine4[13]}}, sine4},       // word8  I4
                {{2{cosine3[13]}}, cosine3},   // word7  Q3
                {{2{sine3[13]}}, sine3},       // word6  I3
                {{2{cosine2[13]}}, cosine2},   // word5  Q2
                {{2{sine2[13]}}, sine2},       // word4  I2
                {{2{cosine1[13]}}, cosine1},   // word3  Q1
                {{2{sine1[13]}}, sine1},       // word2  I1
                {{2{cosine0[13]}}, cosine0},   // word1  Q0
                {{2{sine0[13]}}, sine0}        // word0  I0
            };

            // Valid control: assert when enabled, startup guard has passed,
            // and all generators are valid
            if (!enable_ctrl[0] || !startup_ok) begin
                output_valid <= 1'b0;
            end else if (all_valid) begin
                output_valid <= 1'b1;
            end else begin
                output_valid <= 1'b0;
            end
        end
    end

    // AXI4-Lite interface (always-ready for now; hardened in Step 2.4)
    assign s00_axi_awready = 1'b1;
    assign s00_axi_wready  = 1'b1;
    assign s00_axi_bresp   = 2'b00;
    assign s00_axi_arready = 1'b1;
    assign s00_axi_rresp   = 2'b00;

    // Write response valid signal
    reg bvalid_reg;
    always @(posedge s00_axi_aclk) begin
        if (!s00_axi_aresetn) begin
            bvalid_reg <= 1'b0;
        end else begin
            if (s00_axi_awvalid && s00_axi_awready &&
                s00_axi_wvalid  && s00_axi_wready  && !bvalid_reg) begin
                bvalid_reg <= 1'b1;
            end else if (bvalid_reg && s00_axi_bready) begin
                bvalid_reg <= 1'b0;
            end
        end
    end

    assign s00_axi_bvalid = bvalid_reg;

    // Register write logic (7-bit address matching)
    always @(posedge s00_axi_aclk or negedge s00_axi_aresetn) begin
        if (!s00_axi_aresetn) begin
            waveform_type_ctrl <= 32'h0;
            frequency_ctrl     <= 32'h0;
            amplitude_ctrl     <= 32'h0;
            phase_ctrl         <= 32'h0;
            offset_ctrl        <= 32'h0;
            enable_ctrl        <= 32'h0;
        end else if (s00_axi_awvalid && s00_axi_wvalid) begin
            case (s00_axi_awaddr[6:0])
              7'h00: waveform_type_ctrl <= s00_axi_wdata;
              7'h01: frequency_ctrl     <= s00_axi_wdata;
              7'h02: amplitude_ctrl     <= s00_axi_wdata;
              7'h03: phase_ctrl         <= s00_axi_wdata;
              7'h04: offset_ctrl        <= s00_axi_wdata;
              7'h05: enable_ctrl        <= s00_axi_wdata;
              default: ;
            endcase
        end
    end

    // Register read logic
    reg rvalid_reg;
    always @(posedge s00_axi_aclk or negedge s00_axi_aresetn) begin
        if (!s00_axi_aresetn) begin
            s00_axi_rdata <= 32'h0;
            rvalid_reg    <= 1'b0;
        end else begin
            if (s00_axi_arvalid && s00_axi_arready) begin
                case (s00_axi_araddr[6:0])
                  7'h00: s00_axi_rdata <= waveform_type_ctrl;
                  7'h01: s00_axi_rdata <= frequency_ctrl;
                  7'h02: s00_axi_rdata <= amplitude_ctrl;
                  7'h03: s00_axi_rdata <= phase_ctrl;
                  7'h04: s00_axi_rdata <= offset_ctrl;
                  7'h05: s00_axi_rdata <= enable_ctrl;
                  default: s00_axi_rdata <= 32'h0;
                endcase
            end

            if (rvalid_reg && s00_axi_rready) begin
                rvalid_reg <= 1'b0;
            end else if (s00_axi_arvalid && s00_axi_arready) begin
                rvalid_reg <= 1'b1;
            end
        end
    end

    assign s00_axi_rvalid = rvalid_reg;

endmodule
