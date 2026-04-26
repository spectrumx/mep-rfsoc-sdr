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

    // Function generator control registers
    reg [31:0] waveform_type_ctrl;
    reg [31:0] frequency_ctrl;
    reg [31:0] amplitude_ctrl;
    reg [31:0] phase_ctrl;
    reg [31:0] offset_ctrl;
    reg [31:0] enable_ctrl;

    // Waveform generator signals (signed 14-bit outputs)
    wire signed [13:0] waveform_sine_out;
    wire signed [13:0] waveform_cosine_out;
    wire waveform_valid_out;

    // 16-bit word buffer for packing into one AXIS beat (10 words = 5 complex samples)
    // Layout: word[0]=I0, word[1]=Q0, word[2]=I1, word[3]=Q1, ..., word[9]=Q4
    reg signed [WORD_WIDTH-1:0] word_buffer [0:WORDS_PER_BEAT-1];
    reg [3:0] word_count;
    reg buffer_full;

    // AXI4-Stream output registers
    reg [C_M00_AXIS_TDATA_WIDTH-1:0] output_data;
    reg output_valid;

    // Instantiate waveform generator
    // Clocked at m00_axis_aclk; each cycle produces one logical NCO sample.
    // CLOCK_FREQUENCY=51200000 sets the logical sample rate reference.
    lut_waveform_gen #(
        .CLOCK_FREQUENCY(LOGICAL_SAMPLE_RATE),
        .PHASE_WIDTH(32),
        .DATA_WIDTH(14),
        .LUT_ADDR_WIDTH(12)
    ) u_waveform_gen (
        .clk(m00_axis_aclk),
        .rst_n(m00_axis_aresetn),
        .frequency(frequency_ctrl),
        .phase_offset(phase_ctrl),
        .sine_out(waveform_sine_out),
        .cosine_out(waveform_cosine_out),
        .valid_out(waveform_valid_out)
    );

    // AXI4-Stream output assignments
    assign m00_axis_tvalid = output_valid;
    assign m00_axis_tdata  = output_data;

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

    // Sample collection and AXI4-Stream packing
    // Collects one I/Q pair per m00_axis_aclk cycle.
    // After WORDS_PER_BEAT words (5 complex samples), packs into one 160-bit beat.
    always @(posedge m00_axis_aclk or negedge m00_axis_aresetn) begin
        if (!m00_axis_aresetn) begin
            word_count   <= 4'h0;
            buffer_full  <= 1'b0;
            output_valid <= 1'b0;
        end else begin
            // When buffer is full, present packed beat on output
            if (buffer_full) begin
                output_data <= {
                    word_buffer[9], word_buffer[8], word_buffer[7], word_buffer[6],
                    word_buffer[5], word_buffer[4], word_buffer[3], word_buffer[2],
                    word_buffer[1], word_buffer[0]
                };
                output_valid <= 1'b1;
                buffer_full  <= 1'b0;
            end else if (output_valid && m00_axis_tready) begin
                output_valid <= 1'b0;
            end

            // Collect I/Q word pairs when enabled and waveform is valid
            if (enable_ctrl[0] && waveform_valid_out && !buffer_full && !output_valid) begin
                // Pack signed 14-bit LUT samples into signed 16-bit words
                // (Step 2.3 will add proper MSB-aligned DAC conversion)
                word_buffer[word_count]        <= {{2{waveform_sine_out[13]}}, waveform_sine_out};
                word_buffer[word_count + 1'b1] <= {{2{waveform_cosine_out[13]}}, waveform_cosine_out};

                if (word_count == WORDS_PER_BEAT - 2) begin
                    word_count  <= 4'h0;
                    buffer_full <= 1'b1;
                end else begin
                    word_count <= word_count + 2;
                end
            end
        end
    end

endmodule
