// lut_waveform_gen_tb.sv
`timescale 1ns/1ps

module lut_waveform_gen_tb;

    // Test parameters
    parameter CLOCK_FREQUENCY = 51200000;  // 51.2 MSPS logical sample rate
    parameter PHASE_WIDTH = 32;
    parameter DATA_WIDTH = 14;
    parameter LUT_ADDR_WIDTH = 12;

    // Test duration: ~20000ns for ~1024 samples at 51.2 MSPS
    parameter TEST_FREQUENCY = 2000000;  // 2 MHz
    parameter TONE_TEST_DURATION_NS = 20000;

    // Clock and reset signals
    reg clk;
    reg rst_n;

    // DUT input signals
    reg [31:0] frequency;
    reg [PHASE_WIDTH-1:0] phase_offset;

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
        .sine_out(sine_out),
        .cosine_out(cosine_out),
        .valid_out(valid_out)
    );

    // Clock generation (51.2 MSPS => half-period = 97.65625 ns)
    initial begin
        clk = 0;
        forever #97.65625 clk = ~clk;
    end

    // Reset generation
    initial begin
        rst_n = 0;
        #200;
        rst_n = 1;
    end

    // Fail counter for summary
    integer test_failures;

    // Test sequence
    initial begin
        test_failures = 0;

        // Initialize signals
        frequency = 0;
        phase_offset = 0;

        // Wait for reset
        #500;

        $display("========================================");
        $display("LUT Waveform Generator Testbench");
        $display("========================================");
        $display("Logical Sample Rate: %0d Hz (%.2f MSPS)", CLOCK_FREQUENCY, CLOCK_FREQUENCY/1e6);
        $display("Test Frequency: %0d Hz (%.2f MHz)", TEST_FREQUENCY, TEST_FREQUENCY/1e6);
        $display("Expected Period: %.1f ns", 1e9/TEST_FREQUENCY);
        $display("LUT Size: %0d entries", 1 << LUT_ADDR_WIDTH);
        $display("Output format: signed %0d-bit, range -8192..+8191", DATA_WIDTH);
        $display("========================================\n");

        // ============================
        // TEST 1: 2 MHz tone
        // ============================
        $display("TEST 1: 2 MHz tone test");
        $display("----------------------------------------");
        frequency = TEST_FREQUENCY;
        phase_offset = 0;
        $display("Setting frequency to %0d Hz at time %0t ns", frequency, $time);

        // Wait for valid output
        @(posedge clk);
        while (!valid_out) @(posedge clk);
        $display("Valid output detected at time %0t ns", $time);

        begin
            automatic integer sample_count = 0;
            automatic integer sine_max = -16384;
            automatic integer sine_min = 16383;
            automatic integer cosine_max = -16384;
            automatic integer cosine_min = 16383;
            automatic integer zero_crossings = 0;
            automatic integer prev_sine = 0;
            automatic integer test_start_time;
            automatic real expected_periods;
            automatic integer sine_span;
            automatic integer cosine_span;

            test_start_time = $time;

            while (($time - test_start_time) < TONE_TEST_DURATION_NS) begin
                @(posedge clk);
                if (valid_out) begin
                    sample_count = sample_count + 1;

                    // Track min/max values (cast signed wire to integer for comparison)
                    if ($signed(sine_out) > sine_max) sine_max = $signed(sine_out);
                    if ($signed(sine_out) < sine_min) sine_min = $signed(sine_out);
                    if ($signed(cosine_out) > cosine_max) cosine_max = $signed(cosine_out);
                    if ($signed(cosine_out) < cosine_min) cosine_min = $signed(cosine_out);

                    // Detect zero crossings (sine crossing zero going upward)
                    if ((prev_sine < 0) && ($signed(sine_out) >= 0)) begin
                        zero_crossings = zero_crossings + 1;
                        $display("  Zero crossing #%0d at sample %0d: sine=%0d, cosine=%0d",
                                 zero_crossings, sample_count, $signed(sine_out), $signed(cosine_out));
                    end

                    prev_sine = $signed(sine_out);

                    // Print sample every 100 samples or at key points
                    if ((sample_count % 100 == 0) || (sample_count <= 5)) begin
                        $display("  Sample %0d: sine=%0d, cosine=%0d",
                                 sample_count, $signed(sine_out), $signed(cosine_out));
                    end
                end
            end

            $display("\n  Total samples: %0d", sample_count);
            $display("  Sine range: [%0d, %0d]", sine_min, sine_max);
            $display("  Cosine range: [%0d, %0d]", cosine_min, cosine_max);
            $display("  Zero crossings detected: %0d", zero_crossings);

            // At 51.2 MSPS, 2 MHz tone => 25.6 samples per period
            expected_periods = (sample_count * TEST_FREQUENCY) / CLOCK_FREQUENCY;
            $display("  Expected periods: %.1f", expected_periods);

            // Check 1a: Signed range check
            if ((sine_min < -8192) || (sine_max > 8191) || (cosine_min < -8192) || (cosine_max > 8191)) begin
                $display("  FAIL: Output range exceeds signed 14-bit bounds [-8192, +8191]");
                test_failures = test_failures + 1;
            end else begin
                $display("  PASS: Output range within [-8192, +8191]");
            end

            // Check 1b: Amplitude spans most of the range
            sine_span = sine_max - sine_min;
            cosine_span = cosine_max - cosine_min;
            if ((sine_span < 15000) || (cosine_span < 15000)) begin
                $display("  FAIL: Amplitude span too small (sine=%0d, cosine=%0d, expected >15000)", sine_span, cosine_span);
                test_failures = test_failures + 1;
            end else begin
                $display("  PASS: Amplitude span adequate (sine=%0d, cosine=%0d)", sine_span, cosine_span);
            end

            // Check 1c: Zero crossings
            if (zero_crossings >= 2) begin
                $display("  PASS: Detected %0d zero crossings (>= 2 expected)", zero_crossings);
            end else begin
                $display("  FAIL: Expected >= 2 zero crossings, got %0d", zero_crossings);
                test_failures = test_failures + 1;
            end

            // Check 1d: Both positive and negative values present
            if ((sine_min < 0) && (sine_max > 0) && (cosine_min < 0) && (cosine_max > 0)) begin
                $display("  PASS: Both positive and negative values present");
            end else begin
                $display("  FAIL: Missing positive or negative values (sine:[%0d,%0d], cosine:[%0d,%0d])",
                         sine_min, sine_max, cosine_min, cosine_max);
                test_failures = test_failures + 1;
            end
        end

        // ============================
        // TEST 2: Zero-frequency DC test
        // ============================
        $display("\nTEST 2: Zero-frequency DC test");
        $display("----------------------------------------");
        frequency = 0;
        phase_offset = 0;
        // Reassert reset to clear phase accumulator to known state
        rst_n = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        $display("Setting frequency to 0 Hz, reset phase at time %0t ns", $time);

        // Wait for valid output after reset
        @(posedge clk);
        while (!valid_out) @(posedge clk);

        begin
            automatic integer dc_sine_val = $signed(sine_out);
            automatic integer dc_cosine_val = $signed(cosine_out);
            automatic integer stable_count = 0;
            automatic integer k;

            $display("  Initial values: sine=%0d, cosine=%0d", dc_sine_val, dc_cosine_val);

            // Check stability over 20 samples
            for (k = 0; k < 20; k = k + 1) begin
                @(posedge clk);
                if (valid_out) begin
                    if (($signed(sine_out) == dc_sine_val) && ($signed(cosine_out) == dc_cosine_val)) begin
                        stable_count = stable_count + 1;
                    end
                end
            end

            $display("  Stable samples: %0d / 20", stable_count);
            $display("  DC sine value: %0d (expected ~0)", dc_sine_val);
            $display("  DC cosine value: %0d (expected ~+8191)", dc_cosine_val);

            // Check 2a: Stability
            if (stable_count == 20) begin
                $display("  PASS: Zero-frequency output is stable");
            end else begin
                $display("  FAIL: Zero-frequency output is not stable (%0d/20)", stable_count);
                test_failures = test_failures + 1;
            end

            // Check 2b: Sine near zero at phase 0
            if ((dc_sine_val >= -2) && (dc_sine_val <= 2)) begin
                $display("  PASS: DC sine value near zero (%0d)", dc_sine_val);
            end else begin
                $display("  FAIL: DC sine value not near zero (%0d)", dc_sine_val);
                test_failures = test_failures + 1;
            end

            // Check 2c: Cosine near full scale at phase 0 (clamped to +8191)
            if ((dc_cosine_val >= 8189) && (dc_cosine_val <= 8191)) begin
                $display("  PASS: DC cosine value near full scale (%0d)", dc_cosine_val);
            end else begin
                $display("  FAIL: DC cosine value not near full scale (%0d)", dc_cosine_val);
                test_failures = test_failures + 1;
            end
        end

        // ============================
        // Summary
        // ============================
        $display("\n========================================");
        $display("Test Results Summary");
        $display("========================================");
        $display("Logical Sample Rate: %0d Hz (%.2f MSPS)", CLOCK_FREQUENCY, CLOCK_FREQUENCY/1e6);
        $display("Output format: signed %0d-bit [-8192, +8191]", DATA_WIDTH);
        if (test_failures == 0) begin
            $display("PASS: All tests passed");
        end else begin
            $display("FAIL: %0d test(s) failed", test_failures);
            $fatal;
        end
        $display("========================================\n");

        $finish;
    end

endmodule
