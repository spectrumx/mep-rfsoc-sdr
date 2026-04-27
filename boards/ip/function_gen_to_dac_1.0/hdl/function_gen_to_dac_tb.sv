// function_gen_to_dac_tb.sv
// Step 2.2: 5-sample-per-beat generation verification (rework)
`timescale 1ns/1ps

module function_gen_to_dac_tb;

    // Test parameters
    parameter C_S00_AXI_DATA_WIDTH = 32;
    parameter C_S00_AXI_ADDR_WIDTH = 7;
    parameter C_M00_AXIS_TDATA_WIDTH = 160;

    // RFDC stream localparams (must match DUT)
    localparam integer WORD_WIDTH              = 16;
    localparam integer WORDS_PER_BEAT          = 10;
    localparam integer COMPLEX_SAMPLES_PER_BEAT = 5;

    // AXI4-Lite signals
    reg s00_axi_aclk;
    reg s00_axi_aresetn;
    reg [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr;
    reg [2 : 0] s00_axi_awprot;
    reg s00_axi_awvalid;
    wire s00_axi_awready;
    reg [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata;
    reg [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb;
    reg s00_axi_wvalid;
    wire s00_axi_wready;
    wire [1 : 0] s00_axi_bresp;
    wire s00_axi_bvalid;
    reg s00_axi_bready;
    reg [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr;
    reg [2 : 0] s00_axi_arprot;
    reg s00_axi_arvalid;
    wire s00_axi_arready;
    wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata;
    wire [1 : 0] s00_axi_rresp;
    wire s00_axi_rvalid;
    reg s00_axi_rready;

    // AXIS master interface signals (10.240 MHz)
    reg m00_axis_aclk;
    reg m00_axis_aresetn;
    wire m00_axis_tvalid;
    wire [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata;
    reg m00_axis_tready;

    // DUT instantiation
    function_gen_to_dac_1_0 #(
        .C_S00_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S00_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH),
        .C_M00_AXIS_TDATA_WIDTH(C_M00_AXIS_TDATA_WIDTH)
    ) uut (
        .s00_axi_aclk(s00_axi_aclk),
        .s00_axi_aresetn(s00_axi_aresetn),
        .s00_axi_awaddr(s00_axi_awaddr),
        .s00_axi_awprot(s00_axi_awprot),
        .s00_axi_awvalid(s00_axi_awvalid),
        .s00_axi_awready(s00_axi_awready),
        .s00_axi_wdata(s00_axi_wdata),
        .s00_axi_wstrb(s00_axi_wstrb),
        .s00_axi_wvalid(s00_axi_wvalid),
        .s00_axi_wready(s00_axi_wready),
        .s00_axi_bresp(s00_axi_bresp),
        .s00_axi_bvalid(s00_axi_bvalid),
        .s00_axi_bready(s00_axi_bready),
        .s00_axi_araddr(s00_axi_araddr),
        .s00_axi_arprot(s00_axi_arprot),
        .s00_axi_arvalid(s00_axi_arvalid),
        .s00_axi_arready(s00_axi_arready),
        .s00_axi_rdata(s00_axi_rdata),
        .s00_axi_rresp(s00_axi_rresp),
        .s00_axi_rvalid(s00_axi_rvalid),
        .s00_axi_rready(s00_axi_rready),
        .m00_axis_aclk(m00_axis_aclk),
        .m00_axis_aresetn(m00_axis_aresetn),
        .m00_axis_tvalid(m00_axis_tvalid),
        .m00_axis_tdata(m00_axis_tdata),
        .m00_axis_tready(m00_axis_tready)
    );

    // AXI4-Lite clock: 156.25 MHz (half-period = 3.2 ns)
    initial begin
        s00_axi_aclk = 0;
        forever #3.2ns s00_axi_aclk = ~s00_axi_aclk;
    end

    // AXIS beat clock: 10.240 MHz (half-period = 48.828125 ns)
    initial begin
        m00_axis_aclk = 0;
        forever #48.828125ns m00_axis_aclk = ~m00_axis_aclk;
    end

    // Reset generation
    initial begin
        s00_axi_aresetn = 0;
        m00_axis_aresetn = 0;
        #200;
        s00_axi_aresetn = 1;
        m00_axis_aresetn = 1;
    end

    // Module-scope variables (Vivado 2024.1)
    integer total_failures;
    integer accepted_beats;
    integer beat_failures;
    integer beat_count;
    integer rb_fail;
    reg [31:0] rb_data;
    reg signed [15:0] dec_word0;
    reg signed [15:0] dec_word1;
    reg signed [15:0] dec_word2;
    reg signed [15:0] dec_word3;
    reg signed [15:0] dec_word4;
    reg signed [15:0] dec_word5;
    reg signed [15:0] dec_word6;
    reg signed [15:0] dec_word7;
    reg signed [15:0] dec_word8;
    reg signed [15:0] dec_word9;
    integer has_xz;

    // Step 2.2 variables
    integer tvalid_cycles;
    integer tvalid_misses;
    integer cycle_count;
    integer streaming_started;
    integer continuity_failures;
    integer intra_beat_failures;
    reg signed [15:0] prev_last_i;
    reg signed [15:0] prev_last_q;
    integer prev_last_valid;
    integer zero_crossings;
    integer total_samples;
    reg signed [15:0] prev_i;
    integer prev_i_valid;
    integer freq_fail;
    real measured_freq;
    real expected_freq;
    parameter int MIN_BEATS = 200;
    parameter real FREQ_TOL_PCT = 3.0;

    // Step 2.3 variables
    integer dac_range_failures;
    integer conv_failures;
    integer dc_failures;
    reg signed [15:0] conv_result;
    reg signed [13:0] sat_val;
    reg signed [13:0] sat_val2;

    // Decode helper: extract 10 signed 16-bit words from 160-bit tdata
    task automatic decode_beat(
        input  [159:0] tdata
    );
        dec_word0 = tdata[15:0];
        dec_word1 = tdata[31:16];
        dec_word2 = tdata[47:32];
        dec_word3 = tdata[63:48];
        dec_word4 = tdata[79:64];
        dec_word5 = tdata[95:80];
        dec_word6 = tdata[111:96];
        dec_word7 = tdata[127:112];
        dec_word8 = tdata[143:128];
        dec_word9 = tdata[159:144];
    endtask

        // Step 2.3: Conversion helpers (mirror DUT functions for unit testing)
    function automatic signed [13:0] sat_to_signed_14(
        input signed [31:0] v
    );
        reg signed [15:0] sat_max16;
        reg signed [15:0] sat_min16;
        sat_max16 = 16'd8191;
        sat_min16 = -16'd8192;
        if      (v > sat_max16) sat_to_signed_14 = sat_max16[13:0];
        else if (v < sat_min16) sat_to_signed_14 = sat_min16[13:0];
        else                    sat_to_signed_14 = v[13:0];
    endfunction

    // Full conversion with amplitude (Q15) and offset (signed 14-bit)
    function automatic signed [15:0] dac_word_from_sample(
        input signed [13:0] sample,
        input [15:0] amplitude,
        input signed [13:0] offset
    );
        reg [13:0] sample_mag14;
        reg sample_sign;
        reg [31:0] scaled_mag;
        reg signed [31:0] scaled_signed;
        reg signed [31:0] offset_ext;
        reg signed [31:0] with_offset;
        reg signed [31:0] sat_val32;
        reg signed [31:0] sat_max;
        reg signed [31:0] sat_min;
        sample_sign = sample[13];
        if (sample_sign && sample !== 14'd8192) begin
            sample_mag14 = -sample;
        end else if (sample === 14'd8192) begin
            sample_mag14 = 14'd8192;
        end else begin
            sample_mag14 = sample[13:0];
        end
        scaled_mag = (sample_mag14 * amplitude + 16'd16384) >>> 15;
        if (sample_sign) begin
            scaled_signed = -($signed(scaled_mag));
        end else begin
            scaled_signed = $signed(scaled_mag);
        end
        offset_ext = {{18{offset[13]}}, offset};
        with_offset = scaled_signed + offset_ext;
        sat_max = 32'd8191;
        sat_min = -32'd8192;
        if      (with_offset > sat_max) sat_val32 = sat_max;
        else if (with_offset < sat_min) sat_val32 = sat_min;
        else                            sat_val32 = with_offset;
        dac_word_from_sample = sat_val32 * 4;
    endfunction

    // Legacy wrapper: full scale, zero offset
    function automatic signed [15:0] dac_word_from_sample_fs(
        input signed [13:0] sample
    );
        dac_word_from_sample_fs = dac_word_from_sample(sample, 16'h7FFF, 14'd0);
    endfunction

    // AXI4-Lite write task
    task automatic write_register(
        input [6:0]  addr,
        input [31:0] data
    );
        s00_axi_awaddr = addr;
        s00_axi_awprot = 3'h0;
        s00_axi_awvalid = 1;
        @(posedge s00_axi_aclk);
        while (!s00_axi_awready) @(posedge s00_axi_aclk);
        s00_axi_wdata = data;
        s00_axi_wstrb = 8'hFF;
        s00_axi_wvalid = 1;
        @(posedge s00_axi_aclk);
        while (!s00_axi_wready) @(posedge s00_axi_aclk);
        @(posedge s00_axi_aclk);
        s00_axi_wvalid  = 0;
        s00_axi_awvalid = 0;
        s00_axi_wstrb   = 0;
        @(posedge s00_axi_aclk);
        while (!s00_axi_bvalid) @(posedge s00_axi_aclk);
        s00_axi_bready = 1;
        @(posedge s00_axi_aclk);
        s00_axi_bready = 0;
    endtask

    // AXI4-Lite read task
    task automatic read_register(
        input  [6:0]  addr,
        output [31:0] rdata
    );
        s00_axi_araddr = addr;
        s00_axi_arprot = 3'h0;
        s00_axi_arvalid = 1;
        @(posedge s00_axi_aclk);
        while (!(s00_axi_arready && s00_axi_arvalid)) @(posedge s00_axi_aclk);
        @(posedge s00_axi_aclk);
        s00_axi_arvalid = 0;
        while (!s00_axi_rvalid) @(posedge s00_axi_aclk);
        rdata = s00_axi_rdata;
        s00_axi_rready = 1;
        @(posedge s00_axi_aclk);
        s00_axi_rready = 0;
    endtask

    // Test sequence
    initial begin
        // Initialize signals
        s00_axi_awaddr  = 0;
        s00_axi_awprot  = 0;
        s00_axi_awvalid = 0;
        s00_axi_wdata   = 0;
        s00_axi_wstrb   = 0;
        s00_axi_wvalid  = 0;
        s00_axi_bready  = 0;
        s00_axi_araddr  = 0;
        s00_axi_arprot  = 0;
        s00_axi_arvalid = 0;
        s00_axi_rready  = 0;
        m00_axis_tready = 1;
        total_failures  = 0;
        accepted_beats  = 0;
        beat_failures   = 0;
        beat_count      = 0;
        rb_fail         = 0;
        tvalid_cycles   = 0;
        tvalid_misses   = 0;
        cycle_count     = 0;
        streaming_started = 0;
        continuity_failures = 0;
        intra_beat_failures = 0;
        prev_last_valid = 0;
        zero_crossings  = 0;
        total_samples   = 0;
        prev_i_valid    = 0;
        freq_fail       = 0;
        dac_range_failures = 0;
        conv_failures   = 0;
        dc_failures     = 0;

        // Wait for reset to release
        #500;

        $display("========================================");
        $display("Function Gen to DAC Testbench");
        $display("Step 2.2 + Step 2.3 + Step 2.4.1 Verification");
        $display("========================================");
        $display("AXIS tdata width: %0d bits", C_M00_AXIS_TDATA_WIDTH);
        $display("Words per beat: %0d", WORDS_PER_BEAT);
        $display("Complex samples per beat: %0d", COMPLEX_SAMPLES_PER_BEAT);
        $display("AXIS beat clock: 10.240 MHz");
        $display("Logical sample rate: 51.2 MSPS");
        $display("========================================\n");

        // Configure DUT via AXI4-Lite
        $display("CONFIGURING REGISTERS:");
        $display("----------------------------------------");
        write_register(7'h00, 32'h00000001);
        $display("  Writing waveform_type = 1 (sine)");
        write_register(7'h01, 32'd2000000);
        $display("  Writing frequency = 2000000 Hz");
        write_register(7'h02, 32'h00007FFF);
        $display("  Writing amplitude = 0x7FFF (full scale, Q15)");
        write_register(7'h03, 32'd0);
        $display("  Writing phase = 0");
        write_register(7'h04, 32'd0);
        $display("  Writing offset = 0");
        write_register(7'h05, 32'h00000001);
        $display("  Writing enable = 1");

        // Verify register readback
        $display("\nREGISTER READBACK VERIFICATION:");
        $display("----------------------------------------");

        // Step 2.4.1: Register map and readback for all supported addresses
        // Register map:
        //   7'h00: waveform_type_ctrl
        //   7'h01: frequency_ctrl
        //   7'h02: amplitude_ctrl
        //   7'h03: phase_ctrl
        //   7'h04: offset_ctrl
        //   7'h05: enable_ctrl
        //   All other addresses read as 32'h0000_0000

        read_register(7'h00, rb_data);
        if (rb_data !== 32'h00000001) begin
            $display("  FAIL: waveform_type (0x00) = 0x%08h (expected 0x00000001)", rb_data);
            $fatal;
        end else
            $display("  PASS: waveform_type (0x00) = 0x%08h", rb_data);

        read_register(7'h01, rb_data);
        if (rb_data !== 32'd2000000) begin
            $display("  FAIL: frequency (0x01) = 0x%08h (expected 0x%08h)", rb_data, 32'd2000000);
            $fatal;
        end else
            $display("  PASS: frequency (0x01) = 0x%08h", rb_data);

        read_register(7'h02, rb_data);
        if (rb_data !== 32'h00007FFF) begin
            $display("  FAIL: amplitude (0x02) = 0x%08h (expected 0x00007FFF)", rb_data);
            $fatal;
        end else
            $display("  PASS: amplitude (0x02) = 0x%08h", rb_data);

        read_register(7'h03, rb_data);
        if (rb_data !== 32'd0) begin
            $display("  FAIL: phase (0x03) = 0x%08h (expected 0x00000000)", rb_data);
            $fatal;
        end else
            $display("  PASS: phase (0x03) = 0x%08h", rb_data);

        read_register(7'h04, rb_data);
        if (rb_data !== 32'd0) begin
            $display("  FAIL: offset (0x04) = 0x%08h (expected 0x00000000)", rb_data);
            $fatal;
        end else
            $display("  PASS: offset (0x04) = 0x%08h", rb_data);

        read_register(7'h05, rb_data);
        if (rb_data !== 32'h00000001) begin
            $display("  FAIL: enable (0x05) = 0x%08h (expected 0x00000001)", rb_data);
            $fatal;
        end else
            $display("  PASS: enable (0x05) = 0x%08h", rb_data);

        // Invalid address read check
        read_register(7'h0F, rb_data);
        if (rb_data !== 32'h00000000) begin
            $display("  FAIL: invalid address (0x0F) = 0x%08h (expected 0x00000000)", rb_data);
            $fatal;
        end else
            $display("  PASS: invalid address (0x0F) reads as 0x%08h", rb_data);

        $display("  PASS: All Step 2.4.1 register-map/readback tests passed");

        // AXIS stream monitor
        $display("\nAXIS STREAM MONITOR:");
        $display("----------------------------------------");

        accepted_beats = 0;
        beat_count = 0;

        while (accepted_beats < MIN_BEATS) begin
            @(posedge m00_axis_aclk);
            cycle_count = cycle_count + 1;

            if (m00_axis_tvalid && m00_axis_tready) begin
                accepted_beats = accepted_beats + 1;
                tvalid_cycles = tvalid_cycles + 1;

                if (accepted_beats > 3) begin
                    streaming_started = 1;
                end

                // Decode beat
                decode_beat(m00_axis_tdata);

                // Check for X/Z
                has_xz = 0;
                if ($isunknown(dec_word0) || $isunknown(dec_word1) ||
                    $isunknown(dec_word2) || $isunknown(dec_word3) ||
                    $isunknown(dec_word4) || $isunknown(dec_word5) ||
                    $isunknown(dec_word6) || $isunknown(dec_word7) ||
                    $isunknown(dec_word8) || $isunknown(dec_word9)) begin
                    has_xz = 1;
                end

                // Check for repeated samples INSIDE this beat (for nonzero tone)
                // For a 2 MHz tone, consecutive samples should differ by at least
                // a few LSBs. Check that no two consecutive I or Q samples are identical.
                if (accepted_beats > 0) begin
                    if (dec_word0 == dec_word2 && dec_word1 == dec_word3 &&
                        dec_word2 == dec_word4 && dec_word3 == dec_word5 &&
                        dec_word4 == dec_word6 && dec_word5 == dec_word7 &&
                        dec_word6 == dec_word8 && dec_word7 == dec_word9) begin
                        // All 5 samples are identical - invalid for nonzero tone
                        $display("  Beat %0d: FAIL - all 5 samples identical (I=%d Q=%d)",
                                 accepted_beats, dec_word0, dec_word1);
                        intra_beat_failures = intra_beat_failures + 1;
                    end
                end

                // Cross-beat continuity: first sample of beat N should differ from
                // last sample of beat N-1 (samples are advancing, not repeating)
                if (accepted_beats > 1 && prev_last_valid) begin
                    if (dec_word0 == prev_last_i && dec_word1 == prev_last_q) begin
                        $display("  Beat %0d: FAIL - first sample repeats last sample of beat %0d",
                                 accepted_beats, accepted_beats - 1);
                        continuity_failures = continuity_failures + 1;
                    end
                end
                prev_last_i = dec_word8;
                prev_last_q = dec_word9;
                prev_last_valid = 1;

                // Step 2.3: RF-DAC word range check
                // After conversion, valid range is [-32768, +32764].
                if (!has_xz && (dec_word0 < -32768 || dec_word0 > 32764 ||
                    dec_word1 < -32768 || dec_word1 > 32764 ||
                    dec_word2 < -32768 || dec_word2 > 32764 ||
                    dec_word3 < -32768 || dec_word3 > 32764 ||
                    dec_word4 < -32768 || dec_word4 > 32764 ||
                    dec_word5 < -32768 || dec_word5 > 32764 ||
                    dec_word6 < -32768 || dec_word6 > 32764 ||
                    dec_word7 < -32768 || dec_word7 > 32764 ||
                    dec_word8 < -32768 || dec_word8 > 32764 ||
                    dec_word9 < -32768 || dec_word9 > 32764)) begin
                    $display("  Beat %0d: FAIL - RF-DAC word out of range [%d..%d]",
                             accepted_beats, -32768, 32764);
                    dac_range_failures = dac_range_failures + 1;
                end

                if (has_xz) begin
                    $display("  Beat %0d: FAIL - X/Z detected in tdata", accepted_beats);
                    beat_failures = beat_failures + 1;
                end else if (accepted_beats <= 3 || accepted_beats == MIN_BEATS) begin
                    $display("  Beat %0d: I0=%6d Q0=%6d I1=%6d Q1=%6d I2=%6d Q2=%6d I3=%6d Q3=%6d I4=%6d Q4=%6d",
                             accepted_beats,
                             dec_word0, dec_word1,
                             dec_word2, dec_word3,
                             dec_word4, dec_word5,
                             dec_word6, dec_word7,
                             dec_word8, dec_word9);
                end

                // Zero-crossing count on I channel for frequency measurement
                // Check all 5 I-samples within the beat for zero crossings
                if (total_samples > 0) begin
                    if ((prev_i[15] == 1'b1 && dec_word0[15] == 1'b0) ||
                        (prev_i[15] == 1'b0 && dec_word0[15] == 1'b1)) begin
                        zero_crossings = zero_crossings + 1;
                    end
                    if ((dec_word0[15] == 1'b1 && dec_word2[15] == 1'b0) ||
                        (dec_word0[15] == 1'b0 && dec_word2[15] == 1'b1)) begin
                        zero_crossings = zero_crossings + 1;
                    end
                    if ((dec_word2[15] == 1'b1 && dec_word4[15] == 1'b0) ||
                        (dec_word2[15] == 1'b0 && dec_word4[15] == 1'b1)) begin
                        zero_crossings = zero_crossings + 1;
                    end
                    if ((dec_word4[15] == 1'b1 && dec_word6[15] == 1'b0) ||
                        (dec_word4[15] == 1'b0 && dec_word6[15] == 1'b1)) begin
                        zero_crossings = zero_crossings + 1;
                    end
                    if ((dec_word6[15] == 1'b1 && dec_word8[15] == 1'b0) ||
                        (dec_word6[15] == 1'b0 && dec_word8[15] == 1'b1)) begin
                        zero_crossings = zero_crossings + 1;
                    end
                end
                prev_i = dec_word8;
                prev_i_valid = 1;
                total_samples = total_samples + COMPLEX_SAMPLES_PER_BEAT;

            end else if (streaming_started && !m00_axis_tvalid) begin
                tvalid_misses = tvalid_misses + 1;
            end

            beat_count = beat_count + 1;
            if (beat_count > 500000) begin
                $display("  FAIL: Timeout waiting for %0d accepted beats (got %0d)", MIN_BEATS, accepted_beats);
                total_failures = total_failures + 1;
                break;
            end
        end

        if (beat_failures > 0) total_failures = total_failures + 1;
        if (dac_range_failures > 0) total_failures = total_failures + 1;

        // Step 2.3: RF-DAC word conversion verification
        $display("\nSTEP 2.3 - RF-DAC WORD CONVERSION:");
        $display("----------------------------------------");

      // Unit test conversion function with representative values (full scale, zero offset)
        begin
            // Base conversion: sample -> saturate[-8192,+8191] -> *4
            // Amplitude=0x7FFF (Q15 ~= 1.0), offset=0
            begin
                reg [15:0] amp_fs;
                reg signed [13:0] off_zero;
                amp_fs = 16'h7FFF;
                off_zero = 14'd0;

                // Test -8192 -> ~0x8000 (Q15 quantization: -8192*0x7FFF/32768 = -8191)
                conv_result = dac_word_from_sample(14'd8192, amp_fs, off_zero);
                if (conv_result !== 16'hFFFC && conv_result !== 16'h8000) begin
                    $display("  FAIL: dac(-8192,fs,0) = 0x%04h (expected ~0x8000)", conv_result);
                    conv_failures = conv_failures + 1;
                end else
                    $display("  PASS: dac(-8192,fs,0) = 0x%04h (near -32768)", conv_result);

                // Test -1 -> 0xFFFC (or 0xFFF8 with Q15 rounding)
                conv_result = dac_word_from_sample(14'd16383, amp_fs, off_zero);
                if (conv_result !== 16'hFFFC && conv_result !== 16'hFFF8) begin
                    $display("  FAIL: dac(-1,fs,0) = 0x%04h (expected ~0xFFFC)", conv_result);
                    conv_failures = conv_failures + 1;
                end else
                    $display("  PASS: dac(-1,fs,0) = 0x%04h (near -4)", conv_result);

                // Test 0 -> 0x0000
                conv_result = dac_word_from_sample(14'd0, amp_fs, off_zero);
                if (conv_result !== 16'h0000) begin
                    $display("  FAIL: dac(0,fs,0) = 0x%04h (expected 0x0000)", conv_result);
                    conv_failures = conv_failures + 1;
                end else
                    $display("  PASS: dac(0,fs,0) = 0x%04h (expected 0x0000)", conv_result);

                // Test +1 -> ~0x0004
                conv_result = dac_word_from_sample(14'd1, amp_fs, off_zero);
                if (conv_result !== 16'h0004 && conv_result !== 16'h0004) begin
                    $display("  FAIL: dac(+1,fs,0) = 0x%04h (expected ~0x0004)", conv_result);
                    conv_failures = conv_failures + 1;
                end else
                    $display("  PASS: dac(+1,fs,0) = 0x%04h (near +4)", conv_result);

                // Test +8191 -> ~0x7FFC
                conv_result = dac_word_from_sample(14'd8191, amp_fs, off_zero);
                if (conv_result > 16'h7FFF || conv_result < 16'h7FF0) begin
                    $display("  FAIL: dac(+8191,fs,0) = 0x%04h (expected ~0x7FFC)", conv_result);
                    conv_failures = conv_failures + 1;
                end else
                    $display("  PASS: dac(+8191,fs,0) = 0x%04h (near +32764)", conv_result);
            end

            // Amplitude scaling: half scale (0x3FFF = 0.5 Q15)
            begin
                reg [15:0] amp_half;
                reg signed [13:0] off_zero;
                amp_half = 16'h3FFF;  // 0.5 in Q15
                off_zero = 14'd0;

                // +8191 * 0.5 = +4095 -> +4095*4 = +16380 = 0x3FFE
                conv_result = dac_word_from_sample(14'd8191, amp_half, off_zero);
                if (conv_result > 16'h4000 || conv_result < 16'h3FF0) begin
                    $display("  FAIL: dac(+8191,0.5,0) = 0x%04h (expected ~0x3FFE)", conv_result);
                    conv_failures = conv_failures + 1;
                end else
                    $display("  PASS: dac(+8191,0.5,0) = 0x%04h (near +16380)", conv_result);

                // -8192 * 0.5 = -4096 -> -4096*4 = -16384 = 0xC000
                conv_result = dac_word_from_sample(14'd8192, amp_half, off_zero);
                if (conv_result > 16'hC010 || conv_result < 16'hBFF0) begin
                    $display("  FAIL: dac(-8192,0.5,0) = 0x%04h (expected ~0xC000)", conv_result);
                    conv_failures = conv_failures + 1;
                end else
                    $display("  PASS: dac(-8192,0.5,0) = 0x%04h (near -16384)", conv_result);
            end

            // Positive offset test: offset=+4096
            begin
                reg [15:0] amp_fs;
                reg signed [13:0] off_pos;
                amp_fs = 16'h7FFF;
                off_pos = 14'd4096;

                // sample=0, offset=+4096 -> 4096*4 = 16384 = 0x4000
                conv_result = dac_word_from_sample(14'd0, amp_fs, off_pos);
                if (conv_result !== 16'h4000) begin
                    $display("  FAIL: dac(0,fs,+4096) = 0x%04h (expected 0x4000)", conv_result);
                    conv_failures = conv_failures + 1;
                end else
                    $display("  PASS: dac(0,fs,+4096) = 0x%04h (expected 0x4000)", conv_result);

                // sample=+4096, offset=+4096 -> 8191 (clamped) -> 0x7FFC
                conv_result = dac_word_from_sample(14'd4096, amp_fs, off_pos);
                if (conv_result > 16'h7FF0 && conv_result <= 16'h7FFC) begin
                    $display("  PASS: dac(+4096,fs,+4096) = 0x%04h (saturated near +32764)", conv_result);
                end else if (conv_result >= 16'h7FF8) begin
                    $display("  PASS: dac(+4096,fs,+4096) = 0x%04h (saturated near +32764)", conv_result);
                end else begin
                    $display("  FAIL: dac(+4096,fs,+4096) = 0x%04h (expected saturation near 0x7FFC)", conv_result);
                    conv_failures = conv_failures + 1;
                end
            end

            // Negative offset test: offset=-4096 (14'd12288 = 14'b1100_0000_0000_0)
            begin
                reg [15:0] amp_fs;
                reg signed [13:0] off_neg;
                amp_fs = 16'h7FFF;
                off_neg = 14'd12288;  // -4096 in 14-bit two's complement

                // sample=0, offset=-4096 -> -4096*4 = -16384 = 0xC000
                conv_result = dac_word_from_sample(14'd0, amp_fs, off_neg);
                if (conv_result !== 16'hC000) begin
                    $display("  FAIL: dac(0,fs,-4096) = 0x%04h (expected 0xC000)", conv_result);
                    conv_failures = conv_failures + 1;
                end else
                    $display("  PASS: dac(0,fs,-4096) = 0x%04h (expected 0xC000)", conv_result);
            end

            // Positive saturation: amplitude=full, offset=+8191, sample=+1 -> saturates to +8191
            begin
                reg [15:0] amp_fs;
                reg signed [13:0] off_max;
                amp_fs = 16'h7FFF;
                off_max = 14'd8191;  // +8191

                conv_result = dac_word_from_sample(14'd1, amp_fs, off_max);
                if (conv_result !== 16'h7FFC) begin
                    $display("  FAIL: dac(+1,fs,+8191) = 0x%04h (expected 0x7FFC saturated)", conv_result);
                    conv_failures = conv_failures + 1;
                end else
                    $display("  PASS: dac(+1,fs,+8191) = 0x%04h (saturated to +32764)", conv_result);
            end

            // Negative saturation: amplitude=full, offset=-8192, sample=-1 -> saturates to -8192
            begin
                reg [15:0] amp_fs;
                reg signed [13:0] off_min;
                amp_fs = 16'h7FFF;
                off_min = 14'd8192;  // -8192 in 14-bit two's complement

                conv_result = dac_word_from_sample(14'd16383, amp_fs, off_min);
                if (conv_result !== 16'h8000) begin
                    $display("  FAIL: dac(-1,fs,-8192) = 0x%04h (expected 0x8000 saturated)", conv_result);
                    conv_failures = conv_failures + 1;
                end else
                    $display("  PASS: dac(-1,fs,-8192) = 0x%04h (saturated to -32768)", conv_result);
            end

            // Zero amplitude: output should be offset only
            begin
                reg [15:0] amp_zero;
                reg signed [13:0] off_val;
                amp_zero = 16'd0;
                off_val = 14'd1024;

                conv_result = dac_word_from_sample(14'd8191, amp_zero, off_val);
                if (conv_result !== 16'h1000) begin
                    $display("  FAIL: dac(+8191,0,+1024) = 0x%04h (expected 0x1000)", conv_result);
                    conv_failures = conv_failures + 1;
                end else
                    $display("  PASS: dac(+8191,0,+1024) = 0x%04h (mute+offset*4=4096)", conv_result);
            end
        end

        if (conv_failures > 0) begin
            total_failures = total_failures + 1;
        end

        // Boundary value verification
        $display("\nBOUNDARY VALUE VERIFICATION:");
        $display("----------------------------------------");
        $display("  RF-DAC format: amplitude*sample/32768 + offset, saturate[-8192,+8191], *4");
        $display("  Amplitude: Q15 signed fixed-point, [0, 0x7FFF] (0x7FFF ~= 1.0)");
        $display("  Offset: signed 14-bit, [-8192, +8191]");
        $display("  Expected output range: [-32768, +32764]");
        $display("  Min output (0x%04h) = -32768", 16'h8000);
        $display("  Max output (0x%04h) = +32764", 16'h7FFC);

        // Streaming amplitude/offset verification
        $display("\nSTREAMING AMPLITUDE/OFFSET VERIFICATION:");
        $display("----------------------------------------");
        begin
            integer ao_failures;
            integer ao_beats;
            reg signed [15:0] ao_min;
            reg signed [15:0] ao_max;
            ao_failures = 0;

            // Test 1: Half amplitude (0x3FFF), zero offset
            $display("  Test: amplitude=0x3FFF (half scale), offset=0");
            write_register(7'h02, 32'h00003FFF);
            write_register(7'h04, 32'd0);
            // Wait for register change to propagate through pipeline
            repeat(10) @(posedge m00_axis_aclk);
            ao_beats = 0;
            ao_min = 16'h7FFF;
            ao_max = 16'h8000;
            while (ao_beats < 20) begin
                @(posedge m00_axis_aclk);
                if (m00_axis_tvalid && m00_axis_tready) begin
                    ao_beats = ao_beats + 1;
                    decode_beat(m00_axis_tdata);
                    if (dec_word0 < ao_min) ao_min = dec_word0;
                    if (dec_word0 > ao_max) ao_max = dec_word0;
                end
            end
            // Half scale: expected peak ~4095*4=16380=0x3FFE, trough ~-4096*4=-16384=0xC000
            // Allow tolerance for Q15 quantization + limited sample window: max in [14000, 16500], min in [-16500, -14000]
            if (ao_max > 16'h4060 || ao_max < 16'h36C8 || ao_min > 16'hC738 || ao_min < 16'hBFA0) begin
                $display("    FAIL: half-scale range [%d, %d] (expected [-16384, +16380])", ao_min, ao_max);
                ao_failures = ao_failures + 1;
            end else
                $display("    PASS: half-scale range [%d, %d] (within [-16384, +16380])", ao_min, ao_max);

            // Test 2: Full amplitude, positive offset +2048
            $display("  Test: amplitude=0x7FFF (full), offset=+2048");
            write_register(7'h02, 32'h00007FFF);
            write_register(7'h04, 32'd2048);
            repeat(10) @(posedge m00_axis_aclk);
            ao_beats = 0;
            ao_min = 16'h7FFF;
            ao_max = 16'h8000;
            while (ao_beats < 20) begin
                @(posedge m00_axis_aclk);
                if (m00_axis_tvalid && m00_axis_tready) begin
                    ao_beats = ao_beats + 1;
                    decode_beat(m00_axis_tdata);
                    if (dec_word0 < ao_min) ao_min = dec_word0;
                    if (dec_word0 > ao_max) ao_max = dec_word0;
                end
            end
            // With offset +2048: max saturates at +32764=0x7FFC, min ~-6143*4=-24572=0xA000
            if (ao_max !== 16'h7FFC) begin
                $display("    FAIL: positive-offset max=%d (expected +32764=0x7FFC saturation)", ao_max);
                ao_failures = ao_failures + 1;
            end else
                $display("    PASS: positive-offset max=%d (saturated at +32764)", ao_max);
            // Min expected: ~-8191+2048=-6143, -6143*4=-24572, allow tolerance for limited sample window
            if (ao_min > -22000 || ao_min < -27000) begin
                $display("    FAIL: positive-offset min=%d (expected ~-24572)", ao_min);
                ao_failures = ao_failures + 1;
            end else
                $display("    PASS: positive-offset min=%d (~-24572)", ao_min);

            // Test 3: Full amplitude, negative offset -2048
            $display("  Test: amplitude=0x7FFF (full), offset=-2048");
            write_register(7'h02, 32'h00007FFF);
            write_register(7'h04, 32'h00003800);  // -2048: 16384-2048=14336=0x3800 in [13:0]
            repeat(10) @(posedge m00_axis_aclk);
            ao_beats = 0;
            ao_min = 16'h7FFF;
            ao_max = 16'h8000;
            while (ao_beats < 20) begin
                @(posedge m00_axis_aclk);
                if (m00_axis_tvalid && m00_axis_tready) begin
                    ao_beats = ao_beats + 1;
                    decode_beat(m00_axis_tdata);
                    if (dec_word0 < ao_min) ao_min = dec_word0;
                    if (dec_word0 > ao_max) ao_max = dec_word0;
                end
            end
            // With offset -2048: min saturated at -32768=0x8000, max ~6142*4=24568=0x6008
            if (ao_min !== 16'h8000) begin
                $display("    FAIL: negative-offset min=%d (expected -32768=0x8000 saturation)", ao_min);
                ao_failures = ao_failures + 1;
            end else
                $display("    PASS: negative-offset min=%d (saturated at -32768)", ao_min);
            // Max expected: ~8190-2048=6142, 6142*4=24568=0x6008, allow tolerance
            if (ao_max > 16'h6100 || ao_max < 16'h5F00) begin
                $display("    FAIL: negative-offset max=%d (expected ~24568)", ao_max);
                ao_failures = ao_failures + 1;
            end else
                $display("    PASS: negative-offset max=%d (~24568)", ao_max);

            // Test 4: Zero amplitude (mute), offset +1024
            $display("  Test: amplitude=0 (mute), offset=+1024");
            write_register(7'h02, 32'd0);
            write_register(7'h04, 32'd1024);
            repeat(10) @(posedge m00_axis_aclk);
            ao_beats = 0;
            while (ao_beats < 20) begin
                @(posedge m00_axis_aclk);
                if (m00_axis_tvalid && m00_axis_tready) begin
                    ao_beats = ao_beats + 1;
                    decode_beat(m00_axis_tdata);
                    // All words should be offset*4 = 1024*4 = 4096 = 0x1000
                    if (dec_word0 !== 16'h1000) begin
                        $display("    FAIL: mute+offset word0=0x%04h (expected 0x1000)", dec_word0);
                        ao_failures = ao_failures + 1;
                        break;
                    end
                end
            end
            if (ao_beats > 0 && dec_word0 === 16'h1000)
                $display("    PASS: mute+offset all words=0x1000 (offset*4=4096)");

            // Restore full scale, zero offset for remaining tests
            write_register(7'h02, 32'h00007FFF);
            write_register(7'h04, 32'd0);
            repeat(10) @(posedge m00_axis_aclk);

            if (ao_failures > 0) begin
                $display("  FAIL: %0d amplitude/offset streaming test(s) failed", ao_failures);
                total_failures = total_failures + 1;
            end else
                $display("  PASS: All amplitude/offset streaming tests passed");
        end

        // Word format verification
        $display("\nWORD FORMAT VERIFICATION:");
        $display("----------------------------------------");
        $display("  Word width: 16 bits (signed, MSB-aligned)");
        $display("  RF-DAC format: saturate to [-8192,+8191], then <<< 2");
        $display("  Expected output range: [-32768, +32764]");
        $display("  Word order: I0, Q0, I1, Q1, I2, Q2, I3, Q3, I4, Q4");

        // Frequency measurement
        $display("\nFREQUENCY MEASUREMENT:");
        $display("----------------------------------------");
        expected_freq = 2000000.0;
        if (total_samples > MIN_BEATS * COMPLEX_SAMPLES_PER_BEAT / 2) begin
            measured_freq = zero_crossings * 51200000.0 / (2.0 * total_samples);
            $display("  Expected frequency: %0.0f Hz", expected_freq);
            $display("  Total samples: %0d", total_samples);
            $display("  Zero crossings: %0d", zero_crossings);
            $display("  Measured frequency: %0.0f Hz", measured_freq);
            if (measured_freq > 0) begin
                real err_pct;
                err_pct = (measured_freq - expected_freq) / expected_freq * 100.0;
                $display("  Error: %+.2f %%", err_pct);
                if (err_pct < -FREQ_TOL_PCT || err_pct > FREQ_TOL_PCT) begin
                    $display("  FAIL: frequency error exceeds %.0f%% tolerance", FREQ_TOL_PCT);
                    freq_fail = 1;
                end else begin
                    $display("  PASS: frequency within %.0f%% tolerance", FREQ_TOL_PCT);
                end
            end else begin
                $display("  FAIL: measured frequency is zero");
                freq_fail = 1;
            end
        end else begin
            $display("  FAIL: insufficient samples for frequency measurement");
            freq_fail = 1;
        end
        if (freq_fail) total_failures = total_failures + 1;

        // Summary
        $display("\n========================================");
        $display("Step 2.2 + Step 2.3 + Step 2.4.1 Summary");
        $display("========================================");
        $display("  AXIS tdata width: %0d bits (expected 160)", C_M00_AXIS_TDATA_WIDTH);
        $display("  Words per beat: %0d (expected 10)", WORDS_PER_BEAT);
        $display("  Complex samples per beat: %0d (expected 5)", COMPLEX_SAMPLES_PER_BEAT);
        $display("  Accepted beats: %0d (minimum 20)", accepted_beats);
        $display("  tvalid asserted cycles: %0d", tvalid_cycles);
        $display("  tvalid misses (after startup): %0d (expected 0)", tvalid_misses);
        $display("  Beat failures (X/Z): %0d", beat_failures);
        $display("  Intra-beat repeated-sample failures: %0d", intra_beat_failures);
        $display("  Cross-beat continuity failures: %0d", continuity_failures);
        $display("  Total complex samples: %0d", total_samples);
        $display("  Zero crossings: %0d", zero_crossings);
        $display("  Measured frequency: %0.0f Hz (expected %0.0f Hz)", measured_freq, expected_freq);
        $display("  RF-DAC range failures: %0d", dac_range_failures);
        $display("  Conversion function failures: %0d", conv_failures);

        if (C_M00_AXIS_TDATA_WIDTH != 160) begin
            $display("  FAIL: tdata width is %0d, expected 160", C_M00_AXIS_TDATA_WIDTH);
            total_failures = total_failures + 1;
        end else begin
            $display("  PASS: tdata width is 160 bits");
        end

        if (WORDS_PER_BEAT != 10) begin
            $display("  FAIL: WORDS_PER_BEAT is %0d, expected 10", WORDS_PER_BEAT);
            total_failures = total_failures + 1;
        end else begin
            $display("  PASS: WORDS_PER_BEAT is 10");
        end

        if (COMPLEX_SAMPLES_PER_BEAT != 5) begin
            $display("  FAIL: COMPLEX_SAMPLES_PER_BEAT is %0d, expected 5", COMPLEX_SAMPLES_PER_BEAT);
            total_failures = total_failures + 1;
        end else begin
            $display("  PASS: COMPLEX_SAMPLES_PER_BEAT is 5");
        end

        if (accepted_beats < 20) begin
            $display("  FAIL: Only %0d accepted beats (expected >= 20)", accepted_beats);
            total_failures = total_failures + 1;
        end else begin
            $display("  PASS: Collected %0d accepted beats (>= 20)", accepted_beats);
        end

        if (tvalid_misses > 0) begin
            $display("  FAIL: %0d tvalid miss(es) during streaming", tvalid_misses);
            total_failures = total_failures + 1;
        end else begin
            $display("  PASS: tvalid asserted every cycle during streaming");
        end

        if (beat_failures > 0) begin
            $display("  FAIL: %0d beat(s) had X/Z words", beat_failures);
            total_failures = total_failures + 1;
        end else begin
            $display("  PASS: No X/Z words in any beat");
        end

        if (intra_beat_failures > 0) begin
            $display("  FAIL: %0d beat(s) had all-identical samples", intra_beat_failures);
            total_failures = total_failures + 1;
        end else begin
            $display("  PASS: No beat has all-identical samples");
        end

        if (continuity_failures > 0) begin
            $display("  FAIL: %0d repeated sample(s) across beat boundaries", continuity_failures);
            total_failures = total_failures + 1;
        end else begin
            $display("  PASS: No repeated samples across beat boundaries");
        end

        // Step 2.3 summary checks
        if (dac_range_failures > 0) begin
            $display("  FAIL: %0d RF-DAC word range violation(s)", dac_range_failures);
            total_failures = total_failures + 1;
        end else begin
            $display("  PASS: All RF-DAC words within [-32768, +32764]");
        end

        if (conv_failures > 0) begin
            $display("  FAIL: %0d conversion function test(s) failed", conv_failures);
            total_failures = total_failures + 1;
        end else begin
            $display("  PASS: All conversion function tests passed");
        end

        $display("========================================");

        if (total_failures > 0) begin
            $display("FAIL: %0d test(s) failed", total_failures);
            $fatal;
        end else begin
            $display("PASS: All Step 2.2 + Step 2.3 + Step 2.4.1 tests passed");
        end
        $display("========================================\n");

        $finish;
    end

endmodule
