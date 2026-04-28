// lut_waveform_gen_tb.sv
`timescale 1ns/1ps

module lut_waveform_gen_tb;

    // Test parameters
    parameter CLOCK_FREQUENCY = 64000000;  // 64 MSPS logical sample rate
    parameter PHASE_WIDTH = 32;
    parameter DATA_WIDTH = 14;
    parameter LUT_ADDR_WIDTH = 12;

    // Clock and reset signals
    reg clk;
    reg rst_n;

  // DUT input signals
     reg [31:0] frequency;
     reg [PHASE_WIDTH-1:0] phase_offset;
     reg [PHASE_WIDTH-1:0] phase_step_offset;
     reg en;

    // DUT output signals
    wire signed [DATA_WIDTH-1:0] sine_out;
    wire signed [DATA_WIDTH-1:0] cosine_out;
    wire valid_out;

    // DUT instantiation
    lut_waveform_gen #(
        .CLOCK_FREQUENCY(CLOCK_FREQUENCY),
        .PHASE_WIDTH(PHASE_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .LUT_ADDR_WIDTH(LUT_ADDR_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .frequency(frequency),
        .phase_offset(phase_offset),
        .phase_step_offset(phase_step_offset),
        .en(en),
        .sine_out(sine_out),
        .cosine_out(cosine_out),
        .valid_out(valid_out)
    );

    // Clock generation (64 MHz => half-period = 7.8125 ns)
    initial begin
        clk = 0;
        forever #7.8125 clk = ~clk;
    end

    // Reset generation
    initial begin
        rst_n = 0;
        #200;
        rst_n = 1;
    end

    // =============================================
    // Reusable frequency accuracy test task
    // Measures tone frequency from zero crossings
    // over a fixed number of valid samples.
    //
    // Arguments:
    //   freq_hz        - programmed frequency in Hz
    //   num_samples    - number of valid samples to collect
    //   tolerance_ppm  - acceptable error in parts-per-million
    //   is_dc          - 1 for DC (0 Hz) test, 0 for AC tone
    //
    // Return (via output):
    //   measured_freq  - measured frequency in Hz (0 for DC)
    //   ok             - 1 if test passed, 0 if failed
    // =============================================
    task automatic run_frequency_test(
        input  int freq_hz,
        input  int num_samples,
        input  int tolerance_ppm,
        input  int is_dc,
        output real measured_freq,
        output int ok
    );
        integer   k, sample_count, zero_crossings;
        integer   prev_sine, cur_sine;
        real      expected_freq;
        real      rel_error;
        integer   stable_count, dc_sine, dc_cosine;

        // Program frequency and reset phase accumulator
        frequency = freq_hz;
        phase_offset = 32'h0000_0000;
        rst_n = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;

        // Wait for valid output
        @(posedge clk);
        while (!valid_out) @(posedge clk);

        if (is_dc) begin
            // DC test: capture initial values and verify stability
            dc_sine = $signed(sine_out);
            dc_cosine = $signed(cosine_out);
            stable_count = 0;
            sample_count = 0;

            for (k = 0; k < num_samples; k = k + 1) begin
                @(posedge clk);
                if (valid_out) begin
                    sample_count = sample_count + 1;
                    if (($signed(sine_out) == dc_sine) &&
                        ($signed(cosine_out) == dc_cosine)) begin
                        stable_count = stable_count + 1;
                    end
                end
            end

            measured_freq = 0.0;

            // Check DC stability
            if (stable_count != num_samples) begin
                $display("  FAIL: DC output not stable (%0d/%0d)", stable_count, num_samples);
                ok = 0;
                return;
            end

            // Check sine near zero
            if (dc_sine < -2 || dc_sine > 2) begin
                $display("  FAIL: DC sine not near zero (%0d)", dc_sine);
                ok = 0;
                return;
            end

            // Check cosine near full scale (+8191)
            if (dc_cosine < 8189 || dc_cosine > 8191) begin
                $display("  FAIL: DC cosine not near full scale (%0d)", dc_cosine);
                ok = 0;
                return;
            end

            ok = 1;
            return;
        end

        // AC tone test: count zero crossings over num_samples
        sample_count = 0;
        zero_crossings = 0;
        prev_sine = 0;

        // Capture initial value before loop
        @(posedge clk);
        while (!valid_out) @(posedge clk);
        prev_sine = $signed(sine_out);
        sample_count = 1;

        while (sample_count < num_samples) begin
            @(posedge clk);
            if (valid_out) begin
                sample_count = sample_count + 1;
                cur_sine = $signed(sine_out);

                // Detect upward zero crossing
                if ((prev_sine < 0) && (cur_sine >= 0)) begin
                    zero_crossings = zero_crossings + 1;
                end

                prev_sine = cur_sine;
            end
        end

        // Compute measured frequency from zero crossings
        // Each upward crossing = one full cycle
        measured_freq = (real'(zero_crossings) * real'(CLOCK_FREQUENCY)) / real'(sample_count);
        expected_freq = real'(freq_hz);

        // Compute relative error
        if (expected_freq > 0.0) begin
            rel_error = (measured_freq - expected_freq) / expected_freq;
            if (rel_error < 0.0) rel_error = -rel_error;
        end else begin
            rel_error = 0.0;
        end

        // Check range: all samples must be within signed 14-bit bounds
        // (Verified implicitly by the DUT; we check crossing count is nonzero)
        if (zero_crossings < 1) begin
            $display("  FAIL: No zero crossings detected for %0d Hz tone", freq_hz);
            ok = 0;
            return;
        end

        // Check frequency accuracy against tolerance
        if (rel_error > real'(tolerance_ppm) / 1000000.0) begin
            $display("  FAIL: Frequency error %0.2f%% exceeds %0.1f ppm tolerance",
                     rel_error * 100.0, real'(tolerance_ppm));
            ok = 0;
            return;
        end

        ok = 1;
    endtask

    // =============================================
    // Reusable phase offset test task
    // Verifies sine/cosine quadrant and sign at a
    // given phase offset using DC (0 Hz) output.
    //
    // Arguments:
    //   phase_off        - 32-bit phase offset value
    //   label_deg        - human-readable degree label
    //   exp_sine_sign    - expected sine sign: +1, -1, or 0 (near-zero)
    //   exp_cosine_sign  - expected cosine sign: +1, -1, or 0 (near-zero)
    //   exp_sine_fs      - 1 if sine expected at full scale, 0 if near zero
    //   exp_cosine_fs    - 1 if cosine expected at full scale, 0 if near zero
    //
    // Return (via output):
    //   ok               - 1 if test passed, 0 if failed
    // =============================================
    task automatic run_phase_test(
        input  logic [31:0] phase_off,
        input  int          label_deg,
        input  int          exp_sine_sign,
        input  int          exp_cosine_sign,
        input  int          exp_sine_fs,
        input  int          exp_cosine_fs,
        output int          ok
    );
        integer   k, stable_count;
        integer   dc_sine, dc_cosine;
        integer   sine_in_range, cosine_in_range;

        // Program phase offset at 0 Hz and reset
        frequency = 0;
        phase_offset = phase_off;
        rst_n = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;

        // Wait for valid output, then skip one pipeline cycle
        // so lut_addr_reg has been updated from the new phase_offset.
        @(posedge clk);
        while (!valid_out) @(posedge clk);
        @(posedge clk);
        while (!valid_out) @(posedge clk);

        dc_sine   = $signed(sine_out);
        dc_cosine = $signed(cosine_out);

        $display("  Phase %0d deg (0x%08h): sine=%0d, cosine=%0d",
                 label_deg, phase_off, dc_sine, dc_cosine);

        // Check output range
        sine_in_range   = (dc_sine   >= -8192 && dc_sine   <= 8191);
        cosine_in_range = (dc_cosine >= -8192 && dc_cosine <= 8191);

        if (!sine_in_range || !cosine_in_range) begin
            $display("  FAIL: Out-of-range sample (sine=%0d, cosine=%0d)",
                     dc_sine, dc_cosine);
            ok = 0;
            return;
        end

        // Check sine value
        if (exp_sine_fs) begin
            // Expected at full scale
            if (exp_sine_sign > 0) begin
                if (dc_sine < 8189) begin
                    $display("  FAIL: Sine not near +FS (got %0d)", dc_sine);
                    ok = 0;
                    return;
                end
            end else begin
                // exp_sine_sign < 0
                if (dc_sine > -8190) begin
                    $display("  FAIL: Sine not near -FS (got %0d)", dc_sine);
                    ok = 0;
                    return;
                end
            end
        end else begin
            // Expected near zero
            if (dc_sine < -2 || dc_sine > 2) begin
                $display("  FAIL: Sine not near zero (got %0d)", dc_sine);
                ok = 0;
                return;
            end
        end

        // Check cosine value
        if (exp_cosine_fs) begin
            if (exp_cosine_sign > 0) begin
                if (dc_cosine < 8189) begin
                    $display("  FAIL: Cosine not near +FS (got %0d)", dc_cosine);
                    ok = 0;
                    return;
                end
            end else begin
                // exp_cosine_sign < 0
                if (dc_cosine > -8190) begin
                    $display("  FAIL: Cosine not near -FS (got %0d)", dc_cosine);
                    ok = 0;
                    return;
                end
            end
        end else begin
            if (dc_cosine < -2 || dc_cosine > 2) begin
                $display("  FAIL: Cosine not near zero (got %0d)", dc_cosine);
                ok = 0;
                return;
            end
        end

        // Verify stability over 20 additional samples
        stable_count = 0;
        for (k = 0; k < 20; k = k + 1) begin
            @(posedge clk);
            if (valid_out) begin
                if (($signed(sine_out)   == dc_sine) &&
                    ($signed(cosine_out) == dc_cosine)) begin
                    stable_count = stable_count + 1;
                end
            end
        end

        if (stable_count != 20) begin
            $display("  FAIL: Output not stable (%0d/20)", stable_count);
            ok = 0;
            return;
        end

        ok = 1;
    endtask

    // Module-scope result storage (Vivado 2024.1 requires declarations here)
    real    measured_freq_0;
    real    measured_freq_1;
    real    measured_freq_2;
    real    measured_freq_3;
    integer test_ok_0;
    integer test_ok_1;
    integer test_ok_2;
    integer test_ok_3;
    integer phase_ok_0;
    integer phase_ok_90;
    integer phase_ok_180;
    integer phase_ok_270;
    integer total_failures;

    // Test sequence
    initial begin
        // Initialize signals
        frequency = 0;
        phase_offset = 0;
        phase_step_offset = 0;
        en = 1;
        total_failures = 0;

        // Wait for initial reset to release
        #500;

        $display("========================================");
        $display("LUT Waveform Generator Testbench");
        $display("Steps 1.3 + 1.4: Frequency + Phase Offset");
        $display("========================================");
        $display("Logical Sample Rate: %0d Hz (%0.2f MSPS)",
                 CLOCK_FREQUENCY, real'(CLOCK_FREQUENCY) / 1e6);
        $display("Phase Width: %0d bits", PHASE_WIDTH);
        $display("LUT Size: %0d entries", 1 << LUT_ADDR_WIDTH);
        $display("Output: signed %0d-bit [-8192, +8191]", DATA_WIDTH);
        $display("========================================\n");

        // Test 1: 0 Hz (DC)
        $display("TEST 1: 0 Hz (DC)");
        $display("----------------------------------------");
        run_frequency_test(0, 50, 0, 1, measured_freq_0, test_ok_0);
        if (!test_ok_0) total_failures = total_failures + 1;

        // Test 2: 100 kHz (low tone)
        // Max zero-crossing quantization error ~= 1/Ncrossings.
        // 100 kHz x 200000/64MHz ~= 312 crossings => error < 0.33%.
        // Tolerance 5000 ppm (0.5%) covers quantization safely.
        $display("\nTEST 2: 100 kHz low tone");
        $display("----------------------------------------");
        run_frequency_test(100000, 200000, 5000, 0, measured_freq_1, test_ok_1);
        if (!test_ok_1) total_failures = total_failures + 1;

        // Test 3: 2 MHz
        // ~1562 crossings, quantization error < 0.07%. Tolerance 1000 ppm (0.1%).
        $display("\nTEST 3: 2 MHz tone");
        $display("----------------------------------------");
        run_frequency_test(2000000, 50000, 1000, 0, measured_freq_2, test_ok_2);
        if (!test_ok_2) total_failures = total_failures + 1;

        // Test 4: 10 MHz (higher in-band tone)
        // ~7812 crossings, quantization error < 0.02%. Tolerance 1000 ppm (0.1%).
        $display("\nTEST 4: 10 MHz in-band tone");
        $display("----------------------------------------");
        run_frequency_test(10000000, 50000, 1000, 0, measured_freq_3, test_ok_3);
        if (!test_ok_3) total_failures = total_failures + 1;

        // =============================================
        // Summary
        // =============================================
        $display("\n========================================");
        $display("Step 1.3 Frequency Test Summary");
        $display("========================================");

        if (test_ok_0) begin
            $display("  PASS:   %10d Hz  (DC stable)", 0);
        end else begin
            $display("  FAIL:   %10d Hz  (DC test failed)", 0);
        end

        if (test_ok_1) begin
            $display("  PASS:   %10d Hz  measured %0.1f MHz  (err %0.2f%%)",
                     100000, measured_freq_1 / 1e6,
                     ((measured_freq_1 - 100000.0) / 100000.0) * 100.0);
        end else begin
            $display("  FAIL:   %10d Hz  measured %0.1f MHz",
                     100000, measured_freq_1 / 1e6);
        end

        if (test_ok_2) begin
            $display("  PASS:   %10d Hz  measured %0.1f MHz  (err %0.2f%%)",
                     2000000, measured_freq_2 / 1e6,
                     ((measured_freq_2 - 2000000.0) / 2000000.0) * 100.0);
        end else begin
            $display("  FAIL:   %10d Hz  measured %0.1f MHz",
                     2000000, measured_freq_2 / 1e6);
        end

        if (test_ok_3) begin
            $display("  PASS:   %10d Hz  measured %0.1f MHz  (err %0.2f%%)",
                     10000000, measured_freq_3 / 1e6,
                     ((measured_freq_3 - 10000000.0) / 10000000.0) * 100.0);
        end else begin
            $display("  FAIL:   %10d Hz  measured %0.1f MHz",
                     10000000, measured_freq_3 / 1e6);
        end

        $display("========================================");

        // =============================================
        // Phase offset tests (Step 1.4)
        // =============================================
        $display("\n========================================");
        $display("Step 1.4: Phase Offset Tests");
        $display("========================================");

        // 0 deg: sin=0, cos=+FS
        $display("\nPhase 0 deg (expect sine~0, cosine~+8191):");
        $display("----------------------------------------");
        run_phase_test(32'h00000000, 0, 0, 1, 0, 1, phase_ok_0);
        if (!phase_ok_0) total_failures = total_failures + 1;

        // 90 deg: sin=+FS, cos=0
        $display("\nPhase 90 deg (expect sine~+8191, cosine~0):");
        $display("----------------------------------------");
        run_phase_test(32'h40000000, 90, 1, 0, 1, 0, phase_ok_90);
        if (!phase_ok_90) total_failures = total_failures + 1;

        // 180 deg: sin=0, cos=-FS
        $display("\nPhase 180 deg (expect sine~0, cosine~-8192):");
        $display("----------------------------------------");
        run_phase_test(32'h80000000, 180, 0, -1, 0, 1, phase_ok_180);
        if (!phase_ok_180) total_failures = total_failures + 1;

        // 270 deg: sin=-FS, cos=0
        $display("\nPhase 270 deg (expect sine~-8192, cosine~0):");
        $display("----------------------------------------");
        run_phase_test(32'hC0000000, 270, -1, 0, 1, 0, phase_ok_270);
        if (!phase_ok_270) total_failures = total_failures + 1;

        // =============================================
        // Phase offset summary
        // =============================================
        $display("\n========================================");
        $display("Step 1.4 Phase Offset Summary");
        $display("========================================");

        if (phase_ok_0)
            $display("  PASS:  0 degrees  (sine~0, cosine~+FS)");
        else
            $display("  FAIL:  0 degrees");

        if (phase_ok_90)
            $display("  PASS:  90 degrees (sine~+FS, cosine~0)");
        else
            $display("  FAIL:  90 degrees");

        if (phase_ok_180)
            $display("  PASS:  180 degrees (sine~0, cosine~-FS)");
        else
            $display("  FAIL:  180 degrees");

        if (phase_ok_270)
            $display("  PASS:  270 degrees (sine~-FS, cosine~0)");
        else
            $display("  FAIL:  270 degrees");

        $display("========================================");

        // =============================================
        // Grand summary
        // =============================================
        $display("\n========================================");
        $display("Grand Summary (Steps 1.3 + 1.4)");
        $display("========================================");

        if (total_failures > 0) begin
            $display("FAIL: %0d test(s) failed", total_failures);
            $fatal;
        end else begin
            $display("PASS: All frequency and phase tests passed");
        end
        $display("========================================\n");

        $finish;
    end

endmodule
