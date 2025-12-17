// lut_waveform_gen_tb.sv
`timescale 1ns/1ps

module lut_waveform_gen_tb;

    // Test parameters
    parameter CLOCK_FREQUENCY = 156250000;  // 156.25 MHz
    parameter PHASE_WIDTH = 32;
    parameter DATA_WIDTH = 14;
    parameter LUT_ADDR_WIDTH = 12;
    
    // Test duration: 1000ns
    // Frequency for 2 periods in 1000ns: 2 MHz
    parameter TEST_FREQUENCY = 2000000;  // 2 MHz
    
    // Clock and reset signals
    reg clk;
    reg rst_n;
    
    // DUT input signals
    reg [31:0] frequency;
    reg [PHASE_WIDTH-1:0] phase_offset;
    
    // DUT output signals
    wire [DATA_WIDTH-1:0] sine_out;
    wire [DATA_WIDTH-1:0] cosine_out;
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
    
    // Clock generation (156.25 MHz)
    initial begin
        clk = 0;
        forever #3.2ns clk = ~clk;  // Toggle every 3.2ns (156.25 MHz)
    end
    
    // Reset generation
    initial begin
        rst_n = 0;
        #20;
        rst_n = 1;
    end
    
    // Test sequence
    initial begin
        // Initialize signals
        frequency = 0;
        phase_offset = 0;
        
        // Wait for reset
        #100;
        
        $display("========================================");
        $display("LUT Waveform Generator Testbench");
        $display("========================================");
        $display("Clock Frequency: %0d Hz (%.2f MHz)", CLOCK_FREQUENCY, CLOCK_FREQUENCY/1e6);
        $display("Test Frequency: %0d Hz (%.2f MHz)", TEST_FREQUENCY, TEST_FREQUENCY/1e6);
        $display("Expected Period: %.1f ns", 1e9/TEST_FREQUENCY);
        $display("Test Duration: 1000 ns");
        $display("Expected Periods: 2");
        $display("LUT Size: %0d entries", 1 << LUT_ADDR_WIDTH);
        $display("========================================\n");
        
        // Set frequency for 2 periods in 1000ns
        frequency = TEST_FREQUENCY;
        phase_offset = 0;
        
        $display("Setting frequency to %0d Hz at time %0t ns", frequency, $time);
        $display("Waiting for LUT pipeline to fill (latency: 1 cycle)...\n");
        
        // Wait for valid output
        @(posedge clk);
        while (!valid_out) @(posedge clk);
        
        $display("Valid output detected at time %0t ns", $time);
        $display("Starting waveform monitoring...\n");
        
        // Monitor outputs for the test duration
        begin
            integer sample_count = 0;
            integer sine_max = 0;
            integer sine_min = 16383;
            integer cosine_max = 0;
            integer cosine_min = 16383;
            integer center_crossings = 0;
            reg [DATA_WIDTH-1:0] prev_sine = 0;
            integer center_value = 8192;  // Center value for unsigned 14-bit waveform
            
            while ($time < 1000) begin
                @(posedge clk);
                if (valid_out) begin
                    sample_count = sample_count + 1;
                    
                    // Track min/max values
                    if (sine_out > sine_max) sine_max = sine_out;
                    if (sine_out < sine_min) sine_min = sine_out;
                    if (cosine_out > cosine_max) cosine_max = cosine_out;
                    if (cosine_out < cosine_min) cosine_min = cosine_out;
                    
                    // Detect center crossings (sine crossing center value going upward)
                    if ((prev_sine < center_value) && (sine_out >= center_value)) begin
                        center_crossings = center_crossings + 1;
                        $display("  Center crossing detected at time %0t ns (sample %0d): sine=%0d, cosine=%0d", 
                                 $time, sample_count, sine_out, cosine_out);
                    end
                    
                    prev_sine = sine_out;
                    
                    // Print sample every 100 samples or at key points
                    if ((sample_count % 100 == 0) || (sample_count <= 10)) begin
                        $display("  Sample %0d at %0t ns: sine=%0d, cosine=%0d", 
                                 sample_count, $time, sine_out, cosine_out);
                    end
                end
            end
            
            $display("\n========================================");
            $display("Test Results Summary");
            $display("========================================");
            $display("Total samples: %0d", sample_count);
            $display("Sine range: [%0d, %0d]", sine_min, sine_max);
            $display("Cosine range: [%0d, %0d]", cosine_min, cosine_max);
            $display("Center crossings detected: %0d", center_crossings);
            $display("Expected center crossings: 2 (one per period)");
            
            if (center_crossings >= 2) begin
                $display("PASS: Detected at least 2 center crossings");
            end else begin
                $display("WARNING: Expected 2 center crossings, got %0d", center_crossings);
            end
            
            // Verify amplitude is reasonable (should span most of 14-bit unsigned range 0-16383)
            // Center is 8192, so expect range roughly 1 to 16383
            if ((sine_max > 15000) && (sine_min < 1000)) begin
                $display("PASS: Sine amplitude is reasonable");
            end else begin
                $display("WARNING: Sine amplitude may be too small (max=%0d, min=%0d)", sine_max, sine_min);
            end
            
            if ((cosine_max > 15000) && (cosine_min < 1000)) begin
                $display("PASS: Cosine amplitude is reasonable");
            end else begin
                $display("WARNING: Cosine amplitude may be too small (max=%0d, min=%0d)", cosine_max, cosine_min);
            end
            
            $display("========================================\n");
        end
        
        $display("Test completed at time %0t ns", $time);
        $finish;
    end
    
endmodule

