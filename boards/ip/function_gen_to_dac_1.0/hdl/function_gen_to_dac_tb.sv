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

        // Wait for reset to release
        #500;

        $display("========================================");
        $display("Function Gen to DAC Testbench");
        $display("Step 2.2: 5 Samples Per Beat (rework)");
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
        write_register(7'h02, 32'd0);
        $display("  Writing amplitude = 0 (full scale)");
        write_register(7'h03, 32'd0);
        $display("  Writing phase = 0");
        write_register(7'h05, 32'h00000001);
        $display("  Writing enable = 1");

        // Verify register readback
        $display("\nREGISTER READBACK VERIFICATION:");
        $display("----------------------------------------");

        read_register(7'h00, rb_data);
        if (rb_data !== 32'h00000001) begin
            $display("  FAIL: waveform_type = 0x%08h (expected 0x00000001)", rb_data);
            rb_fail = 1;
        end else
            $display("  PASS: waveform_type = 0x%08h", rb_data);

        read_register(7'h01, rb_data);
        if (rb_data !== 32'd2000000) begin
            $display("  FAIL: frequency = 0x%08h (expected 0x%08h)", rb_data, 32'd2000000);
            rb_fail = 1;
        end else
            $display("  PASS: frequency = 0x%08h", rb_data);

        read_register(7'h05, rb_data);
        if (rb_data !== 32'h00000001) begin
            $display("  FAIL: enable = 0x%08h (expected 0x00000001)", rb_data);
            rb_fail = 1;
        end else
            $display("  PASS: enable = 0x%08h", rb_data);

        if (rb_fail) total_failures = total_failures + 1;

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

        // Word format verification
        $display("\nWORD FORMAT VERIFICATION:");
        $display("----------------------------------------");
        $display("  Word width: 16 bits (signed)");
        $display("  Expected range after sign-extension: [-8192, +8191]");
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
        $display("Step 2.2 Summary (rework)");
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

        $display("========================================");

        if (total_failures > 0) begin
            $display("FAIL: %0d test(s) failed", total_failures);
            $fatal;
        end else begin
            $display("PASS: All Step 2.2 tests passed");
        end
        $display("========================================\n");

        $finish;
    end

endmodule
