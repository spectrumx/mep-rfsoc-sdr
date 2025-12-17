///////////////////////////////////////////////////////////////////////////////
// function_gen_to_dac_1.0.v
//
// Function Generator to DAC Block
//
// This module generates waveforms and outputs them to a DAC via AXI4-Stream
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

module function_gen_to_dac_1_0 #
(
    // Parameters of Axi Slave Bus Interface S00_AXI
    parameter integer C_S00_AXI_DATA_WIDTH    = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH    = 7,

    // Parameters of Output AXIS Master Bus Interface M00_AXIS
    parameter integer C_M00_AXIS_TDATA_WIDTH  = 160,  // 10 samples × 16 bits = 160 bits (5 I/Q pairs)
    parameter integer C_M00_AXIS_TKEEP_WIDTH  = 20   // 160 bits / 8 = 20 bytes
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

    // Ports of AXIS Master Bus Interface M00_AXIS
    input wire m00_axis_aclk,
    input wire m00_axis_aresetn,
    output wire m00_axis_tvalid,
    output wire [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata,
    output wire [C_M00_AXIS_TKEEP_WIDTH-1 : 0] m00_axis_tkeep,
    output wire m00_axis_tuser,
    output wire m00_axis_tlast,
    input wire m00_axis_tready
);

    // Local parameters
    localparam integer WAVEFORM_TYPES = 4;
    localparam integer MAX_FREQUENCY = 100000000; // 100 MHz max
    localparam integer CLOCK_FREQUENCY = 156250000; // 156.25 MHz
    localparam integer SAMPLES_PER_PACKET = 10; // 10 samples × 16 bits = 160 bits
    
    // Function generator control registers
    reg [31:0] waveform_type_ctrl;
    reg [31:0] frequency_ctrl;
    reg [31:0] amplitude_ctrl;
    reg [31:0] phase_ctrl;
    reg [31:0] offset_ctrl;
    reg [31:0] enable_ctrl;
    
    // Waveform generator signals
    wire [13:0] waveform_sine_out;
    wire [13:0] waveform_cosine_out;
    wire waveform_valid_out;

    // Amplitude-scaled versions of waveform outputs.
    // amplitude_ctrl encodes the number of right shifts:
    // 0 = original signal, 1 = signal/2, 2 = signal/4, etc.
    wire [15:0] scaled_sine;
    wire [15:0] scaled_cosine;
    
    // Sample buffer for packing into AXI4-Stream
    reg [15:0] sample_buffer [0:SAMPLES_PER_PACKET-1];
    reg [3:0] sample_count;
    reg buffer_ready;
    
    // AXI4-Stream output
    reg [C_M00_AXIS_TDATA_WIDTH-1:0] output_data;
    reg [C_M00_AXIS_TKEEP_WIDTH-1:0] output_keep;
    reg output_valid;
    reg output_last;
    
    // Instantiate waveform generator
    lut_waveform_gen #(
        .CLOCK_FREQUENCY(CLOCK_FREQUENCY),
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
    
    // AXI4-Stream output
    assign m00_axis_tvalid = output_valid;
    assign m00_axis_tdata = output_data;
    assign m00_axis_tkeep = output_keep;
    assign m00_axis_tuser = 1'b0;
    assign m00_axis_tlast = output_last;
    
    // AXI4-Lite interface
    assign s00_axi_awready = 1'b1;
    assign s00_axi_wready = 1'b1;
    assign s00_axi_bresp = 2'b00;
    assign s00_axi_arready = 1'b1;
    assign s00_axi_rresp = 2'b00;
    
    // Write response valid signal
    reg bvalid_reg;
    always @(posedge s00_axi_aclk) begin
        if (!s00_axi_aresetn) begin
            bvalid_reg <= 1'b0;
        end else begin
            // Assert bvalid when both write address and write data are accepted
            if (s00_axi_awvalid && s00_axi_awready && s00_axi_wvalid && s00_axi_wready && !bvalid_reg) begin
                bvalid_reg <= 1'b1;
            end else if (s00_axi_bvalid && s00_axi_bready) begin
                bvalid_reg <= 1'b0;
            end
        end
    end
    
    assign s00_axi_bvalid = bvalid_reg;
    
    // Register write logic
    always @(posedge s00_axi_aclk or negedge s00_axi_aresetn) begin
        if (!s00_axi_aresetn) begin
            waveform_type_ctrl <= 32'h0;
            frequency_ctrl <= 32'h0;
            amplitude_ctrl <= 32'h0;
            phase_ctrl <= 32'h0;
            offset_ctrl <= 32'h0;
            enable_ctrl <= 32'h0;
        end else if (s00_axi_awvalid && s00_axi_wvalid) begin
            case (s00_axi_awaddr)
                32'h0000_0000: waveform_type_ctrl <= s00_axi_wdata;
                32'h0000_0004: frequency_ctrl <= s00_axi_wdata;
                32'h0000_0008: amplitude_ctrl <= s00_axi_wdata;
                32'h0000_000C: phase_ctrl <= s00_axi_wdata;
                32'h0000_0010: offset_ctrl <= s00_axi_wdata;
                32'h0000_0014: enable_ctrl <= s00_axi_wdata;
                default: begin
                    // Do nothing
                end
            endcase
        end
    end
    
    // Register read logic and read data valid signal
    reg rvalid_reg;
    always @(posedge s00_axi_aclk or negedge s00_axi_aresetn) begin
        if (!s00_axi_aresetn) begin
            s00_axi_rdata <= 32'h0;
            rvalid_reg <= 1'b0;
        end else begin
            // Update read data when address is accepted
            if (s00_axi_arvalid && s00_axi_arready) begin
                case (s00_axi_araddr)
                    32'h0000_0000: s00_axi_rdata <= waveform_type_ctrl;
                    32'h0000_0004: s00_axi_rdata <= frequency_ctrl;
                    32'h0000_0008: s00_axi_rdata <= amplitude_ctrl;
                    32'h0000_000C: s00_axi_rdata <= phase_ctrl;
                    32'h0000_0010: s00_axi_rdata <= offset_ctrl;
                    32'h0000_0014: s00_axi_rdata <= enable_ctrl;
                    default: s00_axi_rdata <= 32'h0;
                endcase
            end
            
            // Assert rvalid when read address is accepted, clear when read data is accepted
            if (rvalid_reg && s00_axi_rready) begin
                // Clear rvalid when data is accepted
                rvalid_reg <= 1'b0;
            end else if (s00_axi_arvalid && s00_axi_arready) begin
                // Assert rvalid when address is accepted
                rvalid_reg <= 1'b1;
            end
        end
    end
    
    assign s00_axi_rvalid = rvalid_reg;
    
    // Amplitude scaling logic
    assign scaled_sine   = ({2'b00, waveform_sine_out}   >> amplitude_ctrl[3:0]);
    assign scaled_cosine = ({2'b00, waveform_cosine_out} >> amplitude_ctrl[3:0]);

    // Sample buffer and AXI4-Stream packing logic
    always @(posedge m00_axis_aclk or negedge m00_axis_aresetn) begin
        if (!m00_axis_aresetn) begin
            sample_count <= 4'h0;
            buffer_ready <= 1'b0;
            output_valid <= 1'b0;
            output_last <= 1'b0;
            output_keep <= {C_M00_AXIS_TKEEP_WIDTH{1'b1}}; // All bytes valid
        end else begin
            // Pack buffer into output_data when ready and clear buffer_ready
            if (buffer_ready) begin
                output_data <= {
                    sample_buffer[9], sample_buffer[8], sample_buffer[7], sample_buffer[6], sample_buffer[5],
                    sample_buffer[4], sample_buffer[3], sample_buffer[2], sample_buffer[1], sample_buffer[0]
                };
                output_valid <= 1'b1;
                output_last <= 1'b1;
                buffer_ready <= 1'b0;
            end else if (m00_axis_tready && output_valid) begin
                // Clear valid when data is accepted
                output_valid <= 1'b0;
                output_last <= 1'b0;
            end
            
            // Collect samples when enabled and valid (and not already ready)
            if (enable_ctrl[0] && waveform_valid_out && !buffer_ready && !output_valid) begin
                // Pack (optionally amplitude-scaled) sine and cosine into 16-bit values
                sample_buffer[sample_count] <= scaled_sine;
                sample_buffer[sample_count + 1] <= scaled_cosine;
                
                if (sample_count == (SAMPLES_PER_PACKET - 2)) begin
                    // Buffer is full after storing these two samples
                    sample_count <= 4'h0;
                    buffer_ready <= 1'b1;
                end else begin
                    sample_count <= sample_count + 2;
                end
            end
        end
    end
    
endmodule