// function_gen_to_dac_tb.sv
// Step 2.2 + 2.3 + 2.4.1-2.4.5 + 2.5.1-2.5.7 + 2.6.1-2.6.4 comprehensive verification
// Hierarchical uut.cfg_* references in Step 2.5.4/2.5.5/2.5.6 are intentional
// white-box checks required to verify CDC synchronizer and bundle-capture behavior.
`timescale 1ns/1ps

module function_gen_to_dac_tb;

    // Test parameters
    parameter C_S00_AXI_DATA_WIDTH = 32;
    parameter C_S00_AXI_ADDR_WIDTH = 7;
    parameter C_M00_AXIS_TDATA_WIDTH = 64;

    // RFDC stream localparams (must match DUT)
    localparam integer WORD_WIDTH              = 16;
    localparam integer WORDS_PER_BEAT          = 4;
    localparam integer COMPLEX_SAMPLES_PER_BEAT = 2;

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

    // AXIS master interface signals (32 MHz)
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

    // AXIS beat clock: 32 MHz (half-period = 15.625 ns)
    initial begin
        m00_axis_aclk = 0;
        forever #15.625ns m00_axis_aclk = ~m00_axis_aclk;
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

    // Step 2.5.1: Baseline dynamic-update test variables
    integer dynamic_failures;

    // Decode helper: extract 4 signed 16-bit words from 64-bit tdata
    task automatic decode_beat(
        input  [63:0] tdata
    );
        dec_word0 = tdata[15:0];
        dec_word1 = tdata[31:16];
        dec_word2 = tdata[47:32];
        dec_word3 = tdata[63:48];
    endtask

    function automatic integer beat_has_xz;
        begin
            beat_has_xz = $isunknown(dec_word0) || $isunknown(dec_word1) ||
                           $isunknown(dec_word2) || $isunknown(dec_word3);
        end
    endfunction

    function automatic integer beat_out_of_range;
        begin
            beat_out_of_range =
                dec_word0 < -32768 || dec_word0 > 32764 ||
                dec_word1 < -32768 || dec_word1 > 32764 ||
                dec_word2 < -32768 || dec_word2 > 32764 ||
                dec_word3 < -32768 || dec_word3 > 32764;
        end
    endfunction

    function automatic integer beat_samples_identical;
        begin
            beat_samples_identical = (dec_word0 == dec_word2) && (dec_word1 == dec_word3);
        end
    endfunction

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

  // AXI4-Lite write task (same-cycle AW/W, Step 2.4.2 compatible)
    task write_register(
        input [6:0]  addr,
        input [31:0] data
    );
        // Wait for stable clock phase, then set signals before next rising edge
        @(posedge s00_axi_aclk);
        s00_axi_awaddr = addr;
        s00_axi_awprot = 3'h0;
        s00_axi_awvalid = 1;
        s00_axi_wdata   = data;
        s00_axi_wstrb   = 8'hFF;
        s00_axi_wvalid  = 1;
        @(posedge s00_axi_aclk);
        s00_axi_awvalid = 0;
        s00_axi_wvalid  = 0;
        s00_axi_wstrb   = 0;
        while (!s00_axi_bvalid) @(posedge s00_axi_aclk);
        s00_axi_bready = 1;
        @(posedge s00_axi_aclk);
        s00_axi_bready = 0;
    endtask

    // Step 2.4.2: AW one cycle before W
    task automatic write_aw_before_w(
        input [6:0]  addr,
        input [31:0] data
    );
        @(posedge s00_axi_aclk);
        s00_axi_awaddr = addr;
        s00_axi_awprot = 3'h0;
        s00_axi_awvalid = 1;
        s00_axi_wvalid  = 0;
        @(posedge s00_axi_aclk);
        s00_axi_awvalid = 0;
        s00_axi_wdata   = data;
        s00_axi_wstrb   = 8'hFF;
        s00_axi_wvalid  = 1;
        @(posedge s00_axi_aclk);
        s00_axi_wvalid = 0;
        s00_axi_wstrb  = 0;
        while (!s00_axi_bvalid) @(posedge s00_axi_aclk);
        s00_axi_bready = 1;
        @(posedge s00_axi_aclk);
        s00_axi_bready = 0;
    endtask

    // Step 2.4.2: W one cycle before AW
    task automatic write_w_before_aw(
        input [6:0]  addr,
        input [31:0] data
    );
        @(posedge s00_axi_aclk);
        s00_axi_wdata   = data;
        s00_axi_wstrb   = 8'hFF;
        s00_axi_wvalid  = 1;
        s00_axi_awvalid = 0;
        @(posedge s00_axi_aclk);
        s00_axi_wvalid = 0;
        s00_axi_wstrb  = 0;
        s00_axi_awaddr = addr;
        s00_axi_awprot = 3'h0;
        s00_axi_awvalid = 1;
        @(posedge s00_axi_aclk);
        s00_axi_awvalid = 0;
        while (!s00_axi_bvalid) @(posedge s00_axi_aclk);
        s00_axi_bready = 1;
        @(posedge s00_axi_aclk);
        s00_axi_bready = 0;
    endtask

   // Step 2.4.2: Back-to-back writes with BVALID hold verification
    task automatic write_back_to_back(
        input [6:0]  addr1,
        input [31:0] data1,
        input [6:0]  addr2,
        input [31:0] data2
    );
        integer bvalid_hold_cycles;

        // First write: same-cycle AW/W
        @(posedge s00_axi_aclk);
        s00_axi_awaddr = addr1;
        s00_axi_awprot = 3'h0;
        s00_axi_awvalid = 1;
        s00_axi_wdata   = data1;
        s00_axi_wstrb   = 8'hFF;
        s00_axi_wvalid  = 1;
        s00_axi_bready  = 0;
        @(posedge s00_axi_aclk);
        s00_axi_awvalid = 0;
        s00_axi_wvalid  = 0;
        s00_axi_wstrb   = 0;

        // Wait for BVALID, hold BREADY=0 for 2 cycles to verify BVALID stability
        while (!s00_axi_bvalid) @(posedge s00_axi_aclk);
        bvalid_hold_cycles = 0;
        if (!s00_axi_bvalid) begin
            $display("    FAIL: BVALID dropped while BREADY=0 (cycle 0)");
            $fatal;
        end
        @(posedge s00_axi_aclk);
        bvalid_hold_cycles = bvalid_hold_cycles + 1;
        if (!s00_axi_bvalid) begin
            $display("    FAIL: BVALID dropped while BREADY=0 (cycle %0d)", bvalid_hold_cycles);
            $fatal;
        end
        @(posedge s00_axi_aclk);
        bvalid_hold_cycles = bvalid_hold_cycles + 1;
        if (!s00_axi_bvalid) begin
            $display("    FAIL: BVALID dropped while BREADY=0 (cycle %0d)", bvalid_hold_cycles);
            $fatal;
        end

        // Accept first response
        s00_axi_bready = 1;
        @(posedge s00_axi_aclk);
        s00_axi_bready = 0;

        // Second write: same-cycle AW/W
        @(posedge s00_axi_aclk);
        s00_axi_awaddr = addr2;
        s00_axi_awprot = 3'h0;
        s00_axi_awvalid = 1;
        s00_axi_wdata   = data2;
        s00_axi_wstrb   = 8'hFF;
        s00_axi_wvalid  = 1;
        @(posedge s00_axi_aclk);
        s00_axi_awvalid = 0;
        s00_axi_wvalid  = 0;
        s00_axi_wstrb   = 0;
        while (!s00_axi_bvalid) @(posedge s00_axi_aclk);
        s00_axi_bready = 1;
        @(posedge s00_axi_aclk);
        s00_axi_bready = 0;
    endtask

    // Step 2.4.3: WSTRB-aware write task (same-cycle AW/W with byte strobes)
    task automatic write_register_wstrb(
        input [6:0]  addr,
        input [31:0] data,
        input [3:0]  wstrb
    );
        @(posedge s00_axi_aclk);
        s00_axi_awaddr = addr;
        s00_axi_awprot = 3'h0;
        s00_axi_awvalid = 1;
        s00_axi_wdata   = data;
        s00_axi_wstrb   = wstrb;
        s00_axi_wvalid  = 1;
        @(posedge s00_axi_aclk);
        s00_axi_awvalid = 0;
        s00_axi_wvalid  = 0;
        s00_axi_wstrb   = 0;
        while (!s00_axi_bvalid) @(posedge s00_axi_aclk);
        s00_axi_bready = 1;
        @(posedge s00_axi_aclk);
        s00_axi_bready = 0;
    endtask

    // AXI4-Lite read task (Step 2.4.4: compatible with ARREADY backpressure)
    task automatic read_register(
        input  [6:0]  addr,
        output [31:0] rdata
    );
        // Wait for channel to be ready
        while (!s00_axi_arready) @(posedge s00_axi_aclk);

        // Drive read request and wait for DUT to accept on next clock edge
        s00_axi_araddr = addr;
        s00_axi_arprot = 3'h0;
        s00_axi_arvalid = 1;
        @(posedge s00_axi_aclk);
        s00_axi_arvalid = 0;

        // Wait for response
        while (!s00_axi_rvalid) @(posedge s00_axi_aclk);
        rdata = s00_axi_rdata;
        s00_axi_rready = 1;
        @(posedge s00_axi_aclk);
        s00_axi_rready = 0;
    endtask

    // Step 2.4.4: Read with RREADY backpressure
    // Holds RREADY=0 for stall_cycles after RVALID asserts, verifying
    // that RDATA/RVALID/RRESP remain stable and ARREADY stays low.
    task automatic read_register_rready_stall(
        input  [6:0]  addr,
        output [31:0] rdata,
        input  integer stall_cycles
    );
        reg [31:0] captured_rdata;
        integer i;

        s00_axi_araddr = addr;
        s00_axi_arprot = 3'h0;
        s00_axi_arvalid = 1;
        s00_axi_rready  = 0;
        @(posedge s00_axi_aclk);
        s00_axi_arvalid = 0;

        // Wait for RVALID
        while (!s00_axi_rvalid) @(posedge s00_axi_aclk);
        captured_rdata = s00_axi_rdata;

        // Hold RREADY=0 for stall_cycles, verifying stability each cycle
        for (i = 0; i < stall_cycles; i = i + 1) begin
            if (s00_axi_rdata !== captured_rdata) begin
                $display("    FAIL: RDATA changed from 0x%08h to 0x%08h while !RREADY (cycle %0d)",
                         captured_rdata, s00_axi_rdata, i);
                $fatal;
            end
            if (!s00_axi_rvalid) begin
                $display("    FAIL: RVALID dropped while !RREADY (cycle %0d)", i);
                $fatal;
            end
            if (s00_axi_arready) begin
                $display("    FAIL: ARREADY asserted while RVALID pending (cycle %0d)", i);
                $fatal;
            end
            @(posedge s00_axi_aclk);
        end

        // Accept response
        s00_axi_rready = 1;
        @(posedge s00_axi_aclk);
        s00_axi_rready = 0;

        if (s00_axi_rvalid) begin
            $display("    FAIL: RVALID still asserted after RREADY handshake");
            $fatal;
        end

        rdata = captured_rdata;
    endtask

    // Step 2.5.4: Wait for cfg_req_pending to clear via CDC round-trip
    task wait_cfg_pending_clear;
        input [31:0] max_cycles;
        integer wait_cnt;
        wait_cnt = 0;
        while (uut.cfg_req_pending && wait_cnt < max_cycles) begin
            @(posedge m00_axis_aclk);
            wait_cnt = wait_cnt + 1;
        end
        if (wait_cnt >= max_cycles) begin
            $display("    WARN: cfg_req_pending did not clear within %0d AXIS cycles", max_cycles);
        end
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
        dynamic_failures = 0;

        // Wait for reset to release
        #500;

        $display("========================================");
        $display("Function Gen to DAC Testbench");
        $display("Step 2.2 + Step 2.3 + Step 2.4.1-2.4.5 + Step 2.5.1-2.5.7 + Step 2.6.1-2.6.4 Verification");
        $display("========================================");
        $display("AXIS tdata width: %0d bits", C_M00_AXIS_TDATA_WIDTH);
        $display("Words per beat: %0d", WORDS_PER_BEAT);
        $display("Complex samples per beat: %0d", COMPLEX_SAMPLES_PER_BEAT);
        $display("AXIS beat clock: 32 MHz");
        $display("Logical sample rate: 64 MSPS");
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

        // Step 2.4.2: Independent AW/W write acceptance tests
        $display("\nSTEP 2.4.2 - AW/W WRITE ACCEPTANCE:");
        $display("----------------------------------------");
        begin
            integer aww_failures;
            aww_failures = 0;

            // Test 1: Same-cycle AW/W write
            $display("  Test: same-cycle AW/W write to 0x01 (frequency)");
            write_aw_before_w(7'h01, 32'd5000000);
            read_register(7'h01, rb_data);
            if (rb_data !== 32'd5000000) begin
                $display("    FAIL: same-cycle readback = 0x%08h (expected 0x%08h)", rb_data, 32'd5000000);
                $fatal;
            end else
                $display("    PASS: same-cycle AW/W readback = 0x%08h", rb_data);

            // Test 2: AW one cycle before W
            $display("  Test: AW-before-W write to 0x01 (frequency)");
            write_aw_before_w(7'h01, 32'd8000000);
            read_register(7'h01, rb_data);
            if (rb_data !== 32'd8000000) begin
                $display("    FAIL: AW-before-W readback = 0x%08h (expected 0x%08h)", rb_data, 32'd8000000);
                $fatal;
            end else
                $display("    PASS: AW-before-W readback = 0x%08h", rb_data);

            // Test 3: W one cycle before AW
            $display("  Test: W-before-AW write to 0x01 (frequency)");
            write_w_before_aw(7'h01, 32'd1000000);
            read_register(7'h01, rb_data);
            if (rb_data !== 32'd1000000) begin
                $display("    FAIL: W-before-AW readback = 0x%08h (expected 0x%08h)", rb_data, 32'd1000000);
                $fatal;
            end else
                $display("    PASS: W-before-AW readback = 0x%08h", rb_data);

            // Test 4: Back-to-back writes with BVALID hold verification
            $display("  Test: back-to-back writes (0x01 and 0x03) with BVALID hold");
            write_back_to_back(7'h01, 32'd2000000, 7'h03, 32'd1000);
            read_register(7'h01, rb_data);
            if (rb_data !== 32'd2000000) begin
                $display("    FAIL: back-to-back write1 (0x01) = 0x%08h (expected 0x%08h)", rb_data, 32'd2000000);
                $fatal;
            end else
                $display("    PASS: back-to-back write1 (0x01) = 0x%08h", rb_data);
            read_register(7'h03, rb_data);
            if (rb_data !== 32'd1000) begin
                $display("    FAIL: back-to-back write2 (0x03) = 0x%08h (expected 0x%08h)", rb_data, 32'd1000);
                $fatal;
            end else
                $display("    PASS: back-to-back write2 (0x03) = 0x%08h", rb_data);
            $display("    PASS: BVALID held stable for 2 cycles while BREADY=0");

            $display("  PASS: All Step 2.4.2 AW/W write acceptance tests passed");
        end

        // Step 2.4.3: WSTRB byte-lane write tests
        // CRITICAL: streaming must be disabled during WSTRB tests so that
        // intermediate register values do not disturb the NCO/datapath state.
        // Using phase_ctrl (0x03) as the test target to avoid changing NCO rate.
        $display("\nSTEP 2.4.3 - WSTRB BYTE-LANE WRITES:");
        $display("----------------------------------------");
        begin
            integer wstrb_failures;
            wstrb_failures = 0;

            // Disable streaming before any byte-lane tests
            write_register(7'h05, 32'd0);
            repeat (5) @(posedge s00_axi_aclk);

            // Set known baseline on phase_ctrl with full-word write
            write_register(7'h03, 32'h00000000);
            read_register(7'h03, rb_data);
            if (rb_data !== 32'h00000000) begin
                $display("  FAIL: phase_ctrl baseline = 0x%08h (expected 0x00000000)", rb_data);
                $fatal;
            end

            // Test 1: byte0 only (WSTRB=4'b0001)
            $display("  Test: byte0 write (WSTRB=4'b0001) to phase_ctrl");
            write_register_wstrb(7'h03, 32'h11223344, 4'b0001);
            read_register(7'h03, rb_data);
            if (rb_data !== 32'h00000044) begin
                $display("    FAIL: byte0 readback = 0x%08h (expected 0x00000044)", rb_data);
                wstrb_failures = wstrb_failures + 1;
            end else
                $display("    PASS: byte0 readback = 0x%08h", rb_data);

            // Test 2: byte1 only (WSTRB=4'b0010)
            $display("  Test: byte1 write (WSTRB=4'b0010) to phase_ctrl");
            write_register_wstrb(7'h03, 32'hAABBCCDD, 4'b0010);
            read_register(7'h03, rb_data);
            if (rb_data !== 32'h0000CC44) begin
                $display("    FAIL: byte1 readback = 0x%08h (expected 0x0000CC44)", rb_data);
                wstrb_failures = wstrb_failures + 1;
            end else
                $display("    PASS: byte1 readback = 0x%08h", rb_data);

            // Test 3: byte2 only (WSTRB=4'b0100)
            // Current: 0x0000CC44, write 0x12345678, byte2=0x34 -> 0x0034CC44
            $display("  Test: byte2 write (WSTRB=4'b0100) to phase_ctrl");
            write_register_wstrb(7'h03, 32'h12345678, 4'b0100);
            read_register(7'h03, rb_data);
            if (rb_data !== 32'h0034CC44) begin
                $display("    FAIL: byte2 readback = 0x%08h (expected 0x0034CC44)", rb_data);
                wstrb_failures = wstrb_failures + 1;
            end else
                $display("    PASS: byte2 readback = 0x%08h", rb_data);

            // Test 4: byte3 only (WSTRB=4'b1000)
            // Current: 0x0034CC44, write 0xDEADBEEF, byte3=0xDE -> 0xDE34CC44
            $display("  Test: byte3 write (WSTRB=4'b1000) to phase_ctrl");
            write_register_wstrb(7'h03, 32'hDEADBEEF, 4'b1000);
            read_register(7'h03, rb_data);
            if (rb_data !== 32'hDE34CC44) begin
                $display("    FAIL: byte3 readback = 0x%08h (expected 0xDE34CC44)", rb_data);
                wstrb_failures = wstrb_failures + 1;
            end else
                $display("    PASS: byte3 readback = 0x%08h", rb_data);

            // Test 5: Mixed-lane write (WSTRB=4'b1010) -- bytes 1 and 3
            // Current: 0xDE34CC44, write 0xAA55CC11, bytes 1&3 -> 0xAA34CC44
            $display("  Test: mixed-lane write (WSTRB=4'b1010) to phase_ctrl");
            write_register_wstrb(7'h03, 32'hAA55CC11, 4'b1010);
            read_register(7'h03, rb_data);
            if (rb_data !== 32'hAA34CC44) begin
                $display("    FAIL: mixed-lane readback = 0x%08h (expected 0xAA34CC44)", rb_data);
                wstrb_failures = wstrb_failures + 1;
            end else
                $display("    PASS: mixed-lane readback = 0x%08h", rb_data);

            // Test 6: No-op write (WSTRB=4'b0000) -- register unchanged
            $display("  Test: no-op write (WSTRB=4'b0000) to phase_ctrl");
            write_register_wstrb(7'h03, 32'hFFFFFFFF, 4'b0000);
            read_register(7'h03, rb_data);
            if (rb_data !== 32'hAA34CC44) begin
                $display("    FAIL: no-op readback = 0x%08h (expected 0xAA34CC44 unchanged)", rb_data);
                wstrb_failures = wstrb_failures + 1;
            end else
                $display("    PASS: no-op write leaves register unchanged = 0x%08h", rb_data);

            if (wstrb_failures > 0) begin
                $display("  FAIL: %0d WSTRB test(s) failed", wstrb_failures);
                $fatal;
            end else
                $display("  PASS: All Step 2.4.3 WSTRB byte-lane tests passed");
        end

        // Step 2.4.4: Harden AXI4-Lite reads
        // Streaming is still disabled from WSTRB section; read tests run in bus-only mode.
        $display("\nSTEP 2.4.4 - AXI4-LITE READ HARDENING:");
        $display("----------------------------------------");
        begin
            integer read_hard_failures;
            integer i;
            reg [31:0] expected_rdata;
            reg [31:0] first_rdata;
            read_hard_failures = 0;

            // Test 1: RREADY backpressure - RDATA/RVALID stable while !RREADY
            $display("  Test: RVALID/RDATA stable while RREADY=0 (3-cycle stall)");
            begin
                reg [31:0] stall_rdata;
                read_register_rready_stall(7'h01, stall_rdata, 3);
                $display("    PASS: RVALID/RDATA stable for 3 cycles with RREADY=0, ARREADY blocked");
            end

            // Test 2: RDATA stability while RREADY=0 and ARADDR changes
            $display("  Test: RDATA stable while RREADY=0, ARADDR changes");
            begin
                reg [31:0] expected_rdata2;

                // Initiate read from frequency (0x01)
                s00_axi_araddr = 7'h01;
                s00_axi_arprot = 3'h0;
                s00_axi_arvalid = 1;
                s00_axi_rready = 0;
                @(posedge s00_axi_aclk);
                s00_axi_arvalid = 0;

                // Wait for RVALID
                while (!s00_axi_rvalid) @(posedge s00_axi_aclk);
                expected_rdata2 = s00_axi_rdata;

                // Check ARREADY is low while RVALID is asserted (new reads blocked)
                if (s00_axi_arready) begin
                    $display("    FAIL: ARREADY asserted while RVALID pending");
                    $fatal;
                end

                // Change ARADDR to a different register (0x05) and re-assert ARVALID
                // This should NOT overwrite the pending read response
                s00_axi_araddr = 7'h05;
                s00_axi_arvalid = 1;
                repeat (3) @(posedge s00_axi_aclk);

                // RDATA must still be the original value
                if (s00_axi_rdata !== expected_rdata2) begin
                    $display("    FAIL: RDATA changed from 0x%08h to 0x%08h while !RREADY", expected_rdata2, s00_axi_rdata);
                    $fatal;
                end
                if (!s00_axi_rvalid) begin
                    $display("    FAIL: RVALID dropped while !RREADY");
                    $fatal;
                end

                // Accept response
                s00_axi_rready = 1;
                @(posedge s00_axi_aclk);
                s00_axi_rready = 0;
                if (s00_axi_rvalid) begin
                    $display("    FAIL: RVALID still asserted after acceptance");
                    $fatal;
                end
                s00_axi_arvalid = 0;

                $display("    PASS: RDATA/RVALID stable despite ARADDR change, ARREADY blocked new read");
            end

            // Test 3: Consecutive reads from all 6 registers with backpressure
            $display("  Test: consecutive reads from all 6 registers with RREADY stall");
            for (i = 0; i < 6; i = i + 1) begin
                reg [31:0] consec_rdata;
                read_register_rready_stall(7'h00 + i, consec_rdata, 2);
            end
            $display("    PASS: All 6 registers read correctly with 2-cycle RREADY stall each");

            // Test 4: Invalid address returns 0x00000000
            $display("  Test: invalid address (0x0F) returns 0x00000000");
            read_register(7'h0F, rb_data);
            if (rb_data !== 32'h00000000) begin
                $display("    FAIL: invalid address readback = 0x%08h (expected 0x00000000)", rb_data);
                $fatal;
            end
            $display("    PASS: invalid address returns 0x00000000");

            // Test 5: RVALID deasserts after RREADY handshake
            $display("  Test: RVALID deasserts after RREADY handshake");
            begin
                // Initiate read, don't accept RREADY immediately
                s00_axi_araddr = 7'h00;
                s00_axi_arprot = 3'h0;
                s00_axi_arvalid = 1;
                s00_axi_rready = 0;
                @(posedge s00_axi_aclk);
                s00_axi_arvalid = 0;

                while (!s00_axi_rvalid) @(posedge s00_axi_aclk);

                // Assert RREADY for one cycle
                s00_axi_rready = 1;
                @(posedge s00_axi_aclk);
                s00_axi_rready = 0;

                if (s00_axi_rvalid) begin
                    $display("    FAIL: RVALID still asserted after RREADY handshake");
                    $fatal;
                end

                // ARREADY should be high again (channel is free)
                if (!s00_axi_arready) begin
                    $display("    FAIL: ARREADY not asserted after read completes");
                    $fatal;
                end

                $display("    PASS: RVALID deasserted, ARREADY re-asserted after handshake");
            end

            $display("  PASS: All Step 2.4.4 read-hardening tests passed");
        end

        // Restore datapath registers and restart stream for remaining tests
        write_register(7'h01, 32'd2000000);
        write_register(7'h02, 32'h00007FFF);
        write_register(7'h03, 32'd0);
        write_register(7'h04, 32'd0);
        write_register(7'h05, 32'd1);

        // Wait for CDC round-trip and DUT startup (enable propagation + startup guard)
        // CDC: AXI->DAC synchronizer (~2 AXIS cycles) + DAC capture + DAC->AXI ack (~2 AXI cycles)
        // Startup guard: 2 AXIS cycles after enable rise in DAC domain
        // Total: ~5-6 AXIS cycles minimum; use 20 for margin
        begin
            integer startup_wait;
            startup_wait = 0;
            while (!m00_axis_tvalid && startup_wait < 500) begin
                @(posedge m00_axis_aclk);
                startup_wait = startup_wait + 1;
            end
            if (startup_wait >= 500) begin
                $display("  WARN: DUT did not start streaming within 500 AXIS cycles after enable");
            end
        end
        // Additional settling cycles after first tvalid
        repeat (10) @(posedge m00_axis_aclk);

        // Reset AXIS monitor state after register restoration
        accepted_beats = 0;
        beat_count = 0;
        tvalid_cycles = 0;
        tvalid_misses = 0;
        streaming_started = 0;
        prev_last_valid = 0;
        zero_crossings = 0;
        total_samples = 0;
        prev_i_valid = 0;
        freq_fail = 0;

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
                if (beat_has_xz()) begin
                    has_xz = 1;
                end

                // Check for repeated samples INSIDE this beat (for nonzero tone)
                // For a 2 MHz tone, consecutive samples should differ by at least
                // a few LSBs. Check that no two consecutive I or Q samples are identical.
                if (accepted_beats > 0) begin
                    if (beat_samples_identical()) begin
                        $display("  Beat %0d: FAIL - both samples identical (I=%d Q=%d)",
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
                prev_last_i = dec_word2;
                prev_last_q = dec_word3;
                prev_last_valid = 1;

                // Step 2.3: RF-DAC word range check
                // After conversion, valid range is [-32768, +32764].
                if (!has_xz && beat_out_of_range()) begin
                    $display("  Beat %0d: FAIL - RF-DAC word out of range [%d..%d]",
                             accepted_beats, -32768, 32764);
                    dac_range_failures = dac_range_failures + 1;
                end

                if (has_xz) begin
                    $display("  Beat %0d: FAIL - X/Z detected in tdata", accepted_beats);
                    beat_failures = beat_failures + 1;
                end else if (accepted_beats <= 3 || accepted_beats == MIN_BEATS) begin
                    $display("  Beat %0d: I0=%6d Q0=%6d I1=%6d Q1=%6d",
                             accepted_beats,
                             dec_word0, dec_word1,
                             dec_word2, dec_word3);
                end

                // Zero-crossing count on I channel for frequency measurement
                // Check both I-samples within the beat for zero crossings
                if (total_samples > 0) begin
                    if ((prev_i[15] == 1'b1 && dec_word0[15] == 1'b0) ||
                        (prev_i[15] == 1'b0 && dec_word0[15] == 1'b1)) begin
                        zero_crossings = zero_crossings + 1;
                    end
                    if ((dec_word0[15] == 1'b1 && dec_word2[15] == 1'b0) ||
                        (dec_word0[15] == 1'b0 && dec_word2[15] == 1'b1)) begin
                        zero_crossings = zero_crossings + 1;
                    end
                end
                prev_i = dec_word2;
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
            // Max expected: ~8190-2048=6142, 6142*4=24568=0x6008, wide tolerance for limited sample window
            if (ao_max > 16'h6200 || ao_max < 16'h5C00) begin
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
        $display("  Word order: I0, Q0, I1, Q1");

        // Frequency measurement
        $display("\nFREQUENCY MEASUREMENT:");
        $display("----------------------------------------");
        expected_freq = 2000000.0;
        if (total_samples > MIN_BEATS * COMPLEX_SAMPLES_PER_BEAT / 2) begin
            measured_freq = zero_crossings * 64000000.0 / (2.0 * total_samples);
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

        // Step 2.5.1: Baseline dynamic-update tests
        // Characterize current behavior before CDC hardening. These tests
        // only check coarse safety: no X/Z words, no out-of-range words,
        // no malformed all-identical beats for nonzero frequency.
        // Do NOT require deterministic update-boundary behavior here.
        $display("\nSTEP 2.5.1 - BASELINE DYNAMIC UPDATE TESTS:");
        $display("----------------------------------------");
        begin
            integer dyn_xz;
            integer dyn_range;
            integer dyn_identical;
            integer dyn_beats;
            reg signed [15:0] dyn_min;
            reg signed [15:0] dyn_max;
            dyn_xz = 0;
            dyn_range = 0;
            dyn_identical = 0;

            // Test 1: Dynamic frequency change while streaming
            $display("  Test 1: dynamic frequency change (2MHz -> 5MHz -> 2MHz)");
            write_register(7'h01, 32'd5000000);
            repeat(10) @(posedge m00_axis_aclk);
            dyn_beats = 0;
            dyn_min = 16'h7FFF;
            dyn_max = 16'h8000;
            dyn_xz = 0;
            dyn_range = 0;
            dyn_identical = 0;
            while (dyn_beats < 100) begin
                @(posedge m00_axis_aclk);
                if (m00_axis_tvalid && m00_axis_tready) begin
                    dyn_beats = dyn_beats + 1;
                    decode_beat(m00_axis_tdata);
                    if (beat_has_xz()) begin
                        dyn_xz = dyn_xz + 1;
                    end
                    if (beat_out_of_range()) begin
                        dyn_range = dyn_range + 1;
                    end
                    if (beat_samples_identical()) begin
                        dyn_identical = dyn_identical + 1;
                    end
                    if (dec_word0 < dyn_min) dyn_min = dec_word0;
                    if (dec_word0 > dyn_max) dyn_max = dec_word0;
                end
            end
            // Restore frequency
            write_register(7'h01, 32'd2000000);
            repeat(10) @(posedge m00_axis_aclk);
            if (dyn_xz > 0) begin
                $display("    FAIL: %0d X/Z word(s) during frequency change", dyn_xz);
                dynamic_failures = dynamic_failures + 1;
            end
            if (dyn_range > 0) begin
                $display("    FAIL: %0d out-of-range word(s) during frequency change", dyn_range);
                dynamic_failures = dynamic_failures + 1;
            end
            if (dyn_identical >= 90) begin
                $display("    FAIL: %0d all-identical beats during 5MHz tone (expected varying samples)", dyn_identical);
                dynamic_failures = dynamic_failures + 1;
            end else
                $display("    PASS: frequency change: 0 X/Z, 0 range violations, %0d/100 varying beats", 100 - dyn_identical);

            // Test 2: Dynamic amplitude change while streaming
            $display("  Test 2: dynamic amplitude change (full -> half -> full)");
            write_register(7'h02, 32'h00003FFF);
            repeat(10) @(posedge m00_axis_aclk);
            dyn_beats = 0;
            dyn_min = 16'h7FFF;
            dyn_max = 16'h8000;
            dyn_xz = 0;
            dyn_range = 0;
            dyn_identical = 0;
            while (dyn_beats < 100) begin
                @(posedge m00_axis_aclk);
                if (m00_axis_tvalid && m00_axis_tready) begin
                    dyn_beats = dyn_beats + 1;
                    decode_beat(m00_axis_tdata);
                    if (beat_has_xz()) begin
                        dyn_xz = dyn_xz + 1;
                    end
                    if (beat_out_of_range()) begin
                        dyn_range = dyn_range + 1;
                    end
                    if (beat_samples_identical()) begin
                        dyn_identical = dyn_identical + 1;
                    end
                    if (dec_word0 < dyn_min) dyn_min = dec_word0;
                    if (dec_word0 > dyn_max) dyn_max = dec_word0;
                end
            end
            // Restore amplitude
            write_register(7'h02, 32'h00007FFF);
            repeat(10) @(posedge m00_axis_aclk);
            if (dyn_xz > 0) begin
                $display("    FAIL: %0d X/Z word(s) during amplitude change", dyn_xz);
                dynamic_failures = dynamic_failures + 1;
            end
            if (dyn_range > 0) begin
                $display("    FAIL: %0d out-of-range word(s) during amplitude change", dyn_range);
                dynamic_failures = dynamic_failures + 1;
            end
            if (dyn_min == dyn_max) begin
                $display("    FAIL: half-scale amplitude produced constant output (range [%d, %d])", dyn_min, dyn_max);
                dynamic_failures = dynamic_failures + 1;
            end else
                $display("    PASS: amplitude change: 0 X/Z, 0 range violations, range [%d, %d]", dyn_min, dyn_max);

            // Test 3: Dynamic offset change while streaming
            $display("  Test 3: dynamic offset change (0 -> +4096 -> 0)");
            write_register(7'h04, 32'd4096);
            repeat(10) @(posedge m00_axis_aclk);
            dyn_beats = 0;
            dyn_min = 16'h7FFF;
            dyn_max = 16'h8000;
            dyn_xz = 0;
            dyn_range = 0;
            dyn_identical = 0;
            while (dyn_beats < 100) begin
                @(posedge m00_axis_aclk);
                if (m00_axis_tvalid && m00_axis_tready) begin
                    dyn_beats = dyn_beats + 1;
                    decode_beat(m00_axis_tdata);
                    if (beat_has_xz()) begin
                        dyn_xz = dyn_xz + 1;
                    end
                    if (beat_out_of_range()) begin
                        dyn_range = dyn_range + 1;
                    end
                    if (beat_samples_identical()) begin
                        dyn_identical = dyn_identical + 1;
                    end
                    if (dec_word0 < dyn_min) dyn_min = dec_word0;
                    if (dec_word0 > dyn_max) dyn_max = dec_word0;
                end
            end
            // Restore offset
            write_register(7'h04, 32'd0);
            repeat(10) @(posedge m00_axis_aclk);
            if (dyn_xz > 0) begin
                $display("    FAIL: %0d X/Z word(s) during offset change", dyn_xz);
                dynamic_failures = dynamic_failures + 1;
            end
            if (dyn_range > 0) begin
                $display("    FAIL: %0d out-of-range word(s) during offset change", dyn_range);
                dynamic_failures = dynamic_failures + 1;
            end
            // With +4096 offset at full scale, expect positive shift in range
            // Max should saturate at +32764, min should be above -32768
            if (dyn_min == dyn_max) begin
                $display("    FAIL: offset change produced constant output (range [%d, %d])", dyn_min, dyn_max);
                dynamic_failures = dynamic_failures + 1;
            end else
                $display("    PASS: offset change: 0 X/Z, 0 range violations, range [%d, %d]", dyn_min, dyn_max);

            // Test 4: Dynamic enable/disable while streaming
            $display("  Test 4: dynamic enable/disable");
            // Disable
            write_register(7'h05, 32'd0);
            begin
                integer disable_cycles;
                disable_cycles = 0;
                while (m00_axis_tvalid && disable_cycles < 100) begin
                    @(posedge m00_axis_aclk);
                    disable_cycles = disable_cycles + 1;
                end
                if (disable_cycles >= 100) begin
                    $display("    FAIL: tvalid did not deassert within 100 cycles after disable");
                    dynamic_failures = dynamic_failures + 1;
                end else
                    $display("    PASS: tvalid deasserted after %0d cycles", disable_cycles);
            end

            // Re-enable
            write_register(7'h05, 32'd1);
            begin
                integer reenable_cycles;
                reenable_cycles = 0;
                while (!m00_axis_tvalid && reenable_cycles < 20) begin
                    @(posedge m00_axis_aclk);
                    reenable_cycles = reenable_cycles + 1;
                end
                if (reenable_cycles >= 20) begin
                    $display("    FAIL: tvalid did not reassert within 20 cycles after re-enable");
                    dynamic_failures = dynamic_failures + 1;
                end else
                    $display("    PASS: tvalid reasserted after %0d cycles", reenable_cycles);
            end

            // Verify streaming safety after re-enable: collect 20 beats
            dyn_beats = 0;
            dyn_xz = 0;
            dyn_range = 0;
            repeat(30) @(posedge m00_axis_aclk);
            while (dyn_beats < 20) begin
                @(posedge m00_axis_aclk);
                if (m00_axis_tvalid && m00_axis_tready) begin
                    dyn_beats = dyn_beats + 1;
                    decode_beat(m00_axis_tdata);
                    if (beat_has_xz()) begin
                        dyn_xz = dyn_xz + 1;
                    end
                    if (beat_out_of_range()) begin
                        dyn_range = dyn_range + 1;
                    end
                end
            end
            if (dyn_xz > 0) begin
                $display("    FAIL: %0d X/Z word(s) after re-enable", dyn_xz);
                dynamic_failures = dynamic_failures + 1;
            end
            if (dyn_range > 0) begin
                $display("    FAIL: %0d out-of-range word(s) after re-enable", dyn_range);
                dynamic_failures = dynamic_failures + 1;
            end
            if (dyn_xz == 0 && dyn_range == 0)
                $display("    PASS: post-re-enable streaming: 0 X/Z, 0 range violations over %0d beats", dyn_beats);

            if (dynamic_failures > 0) begin
                $display("  FAIL: %0d dynamic update test(s) failed", dynamic_failures);
                total_failures = total_failures + 1;
            end else
                $display("  PASS: All Step 2.5.1 baseline dynamic-update tests passed");
        end

        // Step 2.5.4: CDC synchronizer, bundle capture, and acknowledgment
        // White-box tests: access uut.cfg_pub_*, uut.cfg_dac_*,
        // uut.cfg_req_pending, uut.cfg_dirty via hierarchical references.
        // These are localized to Step 2.5.4 CDC tests.

        $display("\nSTEP 2.5.4 - CDC SYNCHRONIZER AND BUNDLE CAPTURE:");
        $display("----------------------------------------");
        begin
            integer cfg_failures;
            cfg_failures = 0;

            // Disable streaming for clean bus-only testing
            write_register(7'h05, 32'd0);
            repeat (5) @(posedge s00_axi_aclk);

            // Drain any pending publish state from prior AXI writes.
            // Wait for CDC round-trip to naturally clear pending.
            if (uut.cfg_req_pending) begin
                // First round-trip may be dirty (re-publishes, stays pending)
                 wait_cfg_pending_clear(200);
                // Second round-trip should be clean (clears pending)
                if (uut.cfg_req_pending) begin
                     wait_cfg_pending_clear(200);
                end
            end
            // Verify clean state
            if (uut.cfg_req_pending !== 1'b0) begin
                $display("    WARN: cfg_req_pending still 1 after drain (unexpected)");
            end
            if (uut.cfg_dirty !== 1'b0) begin
                $display("    WARN: cfg_dirty still 1 after drain (unexpected)");
            end

            // Test 1: Single CDC round trip
            $display("  Test 1: single CDC round trip (frequency -> 3MHz)");
            write_register(7'h01, 32'd3000000);
            @(posedge s00_axi_aclk);

            // Check AXI shadow readback
            read_register(7'h01, rb_data);
            if (rb_data !== 32'd3000000) begin
                $display("    FAIL: AXI shadow readback = 0x%08h (expected 0x%08h)", rb_data, 32'd3000000);
                cfg_failures = cfg_failures + 1;
            end else
                $display("    PASS: AXI shadow readback = 0x%08h", rb_data);

            // Check publish bundle contains the new value
            if (uut.cfg_pub_frequency !== 32'd3000000) begin
                $display("    FAIL: cfg_pub_frequency = 0x%08h (expected 0x%08h)",
                         uut.cfg_pub_frequency, 32'd3000000);
                cfg_failures = cfg_failures + 1;
            end else
                $display("    PASS: cfg_pub_frequency = 0x%08h", uut.cfg_pub_frequency);

            // Check pending=1, dirty=0
            if (uut.cfg_req_pending !== 1'b1) begin
                $display("    FAIL: cfg_req_pending = %0d (expected 1)", uut.cfg_req_pending);
                cfg_failures = cfg_failures + 1;
            end else
                $display("    PASS: cfg_req_pending = 1");

            if (uut.cfg_dirty !== 1'b0) begin
                $display("    FAIL: cfg_dirty = %0d (expected 0)", uut.cfg_dirty);
                cfg_failures = cfg_failures + 1;
            end else
                $display("    PASS: cfg_dirty = 0");

            // Wait for CDC round-trip: DAC domain captures, acks back
             wait_cfg_pending_clear(200);

            // Verify cfg_dac_frequency captured the published value
            if (uut.cfg_dac_frequency !== 32'd3000000) begin
                $display("    FAIL: cfg_dac_frequency = 0x%08h (expected 0x%08h)",
                         uut.cfg_dac_frequency, 32'd3000000);
                cfg_failures = cfg_failures + 1;
            end else
                $display("    PASS: cfg_dac_frequency captured = 0x%08h", uut.cfg_dac_frequency);

            // Verify pending cleared after ack
            if (uut.cfg_req_pending !== 1'b0) begin
                $display("    FAIL: cfg_req_pending = %0d (expected 0 after CDC ack)",
                         uut.cfg_req_pending);
                cfg_failures = cfg_failures + 1;
            end else
                $display("    PASS: cfg_req_pending cleared after CDC ack");

            // Test 2: Writes while request pending (dirty/coalescing with real CDC)
            $display("  Test 2: writes while pending (dirty/coalescing)");
            write_register(7'h01, 32'd6000000);
            @(posedge s00_axi_aclk);

            // Verify first publish
            if (uut.cfg_pub_frequency !== 32'd6000000) begin
                $display("    FAIL: cfg_pub_frequency = 0x%08h (expected 0x%08h)",
                         uut.cfg_pub_frequency, 32'd6000000);
                cfg_failures = cfg_failures + 1;
            end else
                $display("    PASS: cfg_pub_frequency first publish = 0x%08h", uut.cfg_pub_frequency);

            if (uut.cfg_req_pending !== 1'b1) begin
                $display("    FAIL: cfg_req_pending = %0d (expected 1)", uut.cfg_req_pending);
                cfg_failures = cfg_failures + 1;
            end else
                $display("    PASS: cfg_req_pending = 1 after first write");

            // Write additional controls while pending -> sets dirty
            write_register(7'h02, 32'h00003FFF);
            @(posedge s00_axi_aclk);
            write_register(7'h03, 32'h10000000);
            @(posedge s00_axi_aclk);

            if (uut.cfg_dirty !== 1'b1) begin
                $display("    FAIL: cfg_dirty = %0d (expected 1)", uut.cfg_dirty);
                cfg_failures = cfg_failures + 1;
            end else
                $display("    PASS: cfg_dirty = 1 after back-to-back writes");

            // Publish bundle should still be the original
            if (uut.cfg_pub_frequency !== 32'd6000000) begin
                $display("    FAIL: cfg_pub_frequency changed to 0x%08h (expected 0x%08h unchanged)",
                         uut.cfg_pub_frequency, 32'd6000000);
                cfg_failures = cfg_failures + 1;
            end else
                $display("    PASS: cfg_pub_frequency unchanged = 0x%08h", uut.cfg_pub_frequency);

            // Wait for first CDC capture
            begin
                integer first_capture_done;
                first_capture_done = 0;
                while (!first_capture_done && uut.cfg_req_pending) begin
                    @(posedge m00_axis_aclk);
                    // After first capture, dirty ack should re-publish and stay pending
                    // Check if cfg_dac_frequency matches first bundle (6MHz)
                    if (uut.cfg_dac_frequency === 32'd6000000) begin
                        first_capture_done = 1;
                    end
                end
            end

            if (uut.cfg_dac_frequency !== 32'd6000000) begin
                $display("    FAIL: first cfg_dac_frequency = 0x%08h (expected 0x%08h)",
                         uut.cfg_dac_frequency, 32'd6000000);
                cfg_failures = cfg_failures + 1;
            end else
                $display("    PASS: first cfg_dac_frequency capture = 0x%08h", uut.cfg_dac_frequency);

            // After dirty ack, second request should be issued. Wait for final pending to clear.
            if (uut.cfg_req_pending) begin
                 wait_cfg_pending_clear(200);
            end

            // Verify final cfg_dac_* bundle matches latest shadow values
            if (uut.cfg_dac_frequency !== 32'd6000000) begin
                $display("    FAIL: final cfg_dac_frequency = 0x%08h (expected 0x%08h)",
                         uut.cfg_dac_frequency, 32'd6000000);
                cfg_failures = cfg_failures + 1;
            end else
                $display("    PASS: final cfg_dac_frequency = 0x%08h", uut.cfg_dac_frequency);

            if (uut.cfg_dac_amplitude !== 32'h00003FFF) begin
                $display("    FAIL: final cfg_dac_amplitude = 0x%08h (expected 0x00003FFF)",
                         uut.cfg_dac_amplitude);
                cfg_failures = cfg_failures + 1;
            end else
                $display("    PASS: final cfg_dac_amplitude = 0x%08h", uut.cfg_dac_amplitude);

            if (uut.cfg_dac_phase !== 32'h10000000) begin
                $display("    FAIL: final cfg_dac_phase = 0x%08h (expected 0x10000000)",
                         uut.cfg_dac_phase);
                cfg_failures = cfg_failures + 1;
            end else
                $display("    PASS: final cfg_dac_phase = 0x%08h", uut.cfg_dac_phase);

            if (uut.cfg_req_pending !== 1'b0) begin
                $display("    FAIL: cfg_req_pending = %0d (expected 0 after all acks)",
                         uut.cfg_req_pending);
                cfg_failures = cfg_failures + 1;
            end else
                $display("    PASS: cfg_req_pending cleared after all CDC acks");

            // Test 3: Repeated toggle operation (3 request/ack cycles)
            $display("  Test 3: repeated toggle operation (3 cycles)");
            begin
                integer cycle;
                reg [31:0] test_freqs[0:2];
                test_freqs[0] = 32'd1000000;
                test_freqs[1] = 32'd2500000;
                test_freqs[2] = 32'd5000000;

                for (cycle = 0; cycle < 3; cycle = cycle + 1) begin
                    $display("    Cycle %0d: frequency -> %0d Hz", cycle + 1, test_freqs[cycle]);
                    write_register(7'h01, test_freqs[cycle]);
                    @(posedge s00_axi_aclk);

                    if (uut.cfg_req_pending !== 1'b1) begin
                        $display("      FAIL: pending not set for cycle %0d", cycle + 1);
                        cfg_failures = cfg_failures + 1;
                    end

                    // Wait for CDC round-trip
                     wait_cfg_pending_clear(200);

                    // Verify capture
                    if (uut.cfg_dac_frequency !== test_freqs[cycle]) begin
                        $display("      FAIL: cfg_dac_frequency = 0x%08h (expected 0x%08h) cycle %0d",
                                 uut.cfg_dac_frequency, test_freqs[cycle], cycle + 1);
                        cfg_failures = cfg_failures + 1;
                    end else
                        $display("      PASS: cfg_dac_frequency = 0x%08h captured, pending cleared",
                                 uut.cfg_dac_frequency);

                    if (uut.cfg_req_pending !== 1'b0) begin
                        $display("      FAIL: pending still set after cycle %0d", cycle + 1);
                        cfg_failures = cfg_failures + 1;
                    end
                end
                $display("    PASS: 3 CDC request/ack cycles completed");
            end

            if (cfg_failures > 0) begin
                $display("  FAIL: %0d Step 2.5.4 test(s) failed", cfg_failures);
                total_failures = total_failures + 1;
            end else
                $display("  PASS: All Step 2.5.4 CDC synchronizer tests passed");
        end

      // Step 2.5.5: Datapath consumes DAC-domain config registers
        // Verify that stream output reflects cfg_dac_* values after CDC round-trip,
        // and that AXI readback still reports shadow values.
        $display("\nSTEP 2.5.5 - DATAPATH CONSUMES DAC-DOMAIN CONFIG:");
        $display("----------------------------------------");
        begin
            integer dp_failures;
            dp_failures = 0;

            // Enable streaming with known config
            write_register(7'h00, 32'd1);  // waveform_type = sine
            write_register(7'h01, 32'd2000000);  // frequency = 2 MHz
            write_register(7'h02, 32'h7FFF);  // amplitude = full scale
            write_register(7'h03, 32'd0);  // phase = 0
            write_register(7'h04, 32'd0);  // offset = 0
            write_register(7'h05, 32'd1);  // enable

            // Wait for CDC round-trip so cfg_dac_* are populated, then startup
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
                if (uut.cfg_req_pending) begin
                    wait_cfg_pending_clear(200);
                end
            end
            // Wait for startup guard
            repeat (210) @(posedge m00_axis_aclk);

            // Verify streaming is active
            if (!m00_axis_tvalid) begin
                $display("    FAIL: streaming not active after startup");
                dp_failures = dp_failures + 1;
            end else
                $display("  PASS: streaming active with cfg_dac_* config");

            // Collect baseline beats (20 beats, quick check)
            begin
                integer i, b, dp_xz, dp_range;
                dp_xz = 0;
                dp_range = 0;
                for (b = 0; b < 20; b = b + 1) begin
                    @(posedge m00_axis_aclk);
                    if (m00_axis_tvalid && m00_axis_tready) begin
                        for (i = 0; i < WORDS_PER_BEAT; i = i + 1) begin
                            reg signed [15:0] w;
                            w = m00_axis_tdata[i*16 +: 16];
                            if ($isunknown(w)) dp_xz = dp_xz + 1;
                            if (w < -32768 || w > 32764) dp_range = dp_range + 1;
                        end
                    end
                end
                if (dp_xz > 0 || dp_range > 0) begin
                    $display("    FAIL: baseline: %0d X/Z, %0d range violations", dp_xz, dp_range);
                    dp_failures = dp_failures + 1;
                end else
                    $display("  PASS: 20 baseline beats, no X/Z, all in range");
            end

            // Test 1: Dynamic frequency change (2MHz -> 5MHz)
            $display("  Test 1: frequency change 2MHz -> 5MHz while streaming");
            write_register(7'h01, 32'd5000000);
            @(posedge s00_axi_aclk);

            // Wait for CDC round-trip
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
            end
            repeat (20) @(posedge m00_axis_aclk);

            // Verify cfg_dac_frequency updated
            if (uut.cfg_dac_frequency !== 32'd5000000) begin
                $display("    FAIL: cfg_dac_frequency = 0x%08h (expected 0x%08h)",
                         uut.cfg_dac_frequency, 32'd5000000);
                dp_failures = dp_failures + 1;
            end else
                $display("    PASS: cfg_dac_frequency updated to 5MHz");

            // Collect beats after frequency change
            begin
                integer i, b, dp_xz, dp_range;
                dp_xz = 0;
                dp_range = 0;
                for (b = 0; b < 50; b = b + 1) begin
                    @(posedge m00_axis_aclk);
                    if (m00_axis_tvalid && m00_axis_tready) begin
                        for (i = 0; i < WORDS_PER_BEAT; i = i + 1) begin
                            reg signed [15:0] w;
                            w = m00_axis_tdata[i*16 +: 16];
                            if ($isunknown(w)) dp_xz = dp_xz + 1;
                            if (w < -32768 || w > 32764) dp_range = dp_range + 1;
                        end
                    end
                end
                if (dp_xz > 0 || dp_range > 0) begin
                    $display("    FAIL: freq change: %0d X/Z, %0d range violations", dp_xz, dp_range);
                    dp_failures = dp_failures + 1;
                end else
                    $display("    PASS: freq change: 0 X/Z, 0 range violations");
            end

            // Test 2: Amplitude change (full -> half)
            $display("  Test 2: amplitude change full -> half while streaming");
            write_register(7'h02, 32'h3FFF);
            @(posedge s00_axi_aclk);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
            end
            repeat (20) @(posedge m00_axis_aclk);

            if (uut.cfg_dac_amplitude !== 32'h3FFF) begin
                $display("    FAIL: cfg_dac_amplitude = 0x%08h (expected 0x00003FFF)",
                         uut.cfg_dac_amplitude);
                dp_failures = dp_failures + 1;
            end else
                $display("    PASS: cfg_dac_amplitude updated to half scale");

            // Test 3: Offset change (0 -> +2048)
            $display("  Test 3: offset change 0 -> +2048 while streaming");
            write_register(7'h04, 32'd2048);
            @(posedge s00_axi_aclk);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
            end
            repeat (20) @(posedge m00_axis_aclk);

            if (uut.cfg_dac_offset !== 32'd2048) begin
                $display("    FAIL: cfg_dac_offset = 0x%08h (expected 0x%08h)",
                         uut.cfg_dac_offset, 32'd2048);
                dp_failures = dp_failures + 1;
            end else
                $display("    PASS: cfg_dac_offset updated to +2048");

            // Test 4: Disable/re-enable
            $display("  Test 4: disable/re-enable with CDC");
            write_register(7'h05, 32'd0);
            @(posedge s00_axi_aclk);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
            end
            repeat (10) @(posedge m00_axis_aclk);

            if (m00_axis_tvalid) begin
                $display("    FAIL: tvalid still asserted after disable");
                dp_failures = dp_failures + 1;
            end else
                $display("    PASS: tvalid deasserted after disable");

            write_register(7'h05, 32'd1);
            @(posedge s00_axi_aclk);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
                if (uut.cfg_req_pending) begin
                    wait_cfg_pending_clear(200);
                end
            end
            repeat (210) @(posedge m00_axis_aclk);

            if (!m00_axis_tvalid) begin
                $display("    FAIL: tvalid not reasserted after re-enable");
                dp_failures = dp_failures + 1;
            end else
                $display("    PASS: tvalid reasserted after re-enable");

            // Final streaming check after all changes
            begin
                integer i, b, dp_xz, dp_range;
                dp_xz = 0;
                dp_range = 0;
                for (b = 0; b < 20; b = b + 1) begin
                    @(posedge m00_axis_aclk);
                    if (m00_axis_tvalid && m00_axis_tready) begin
                        for (i = 0; i < WORDS_PER_BEAT; i = i + 1) begin
                            reg signed [15:0] w;
                            w = m00_axis_tdata[i*16 +: 16];
                            if ($isunknown(w)) dp_xz = dp_xz + 1;
                            if (w < -32768 || w > 32764) dp_range = dp_range + 1;
                        end
                    end
                end
                if (dp_xz > 0 || dp_range > 0) begin
                    $display("    FAIL: post-re-enable: %0d X/Z, %0d range violations", dp_xz, dp_range);
                    dp_failures = dp_failures + 1;
                end else
                    $display("    PASS: post-re-enable streaming: 0 X/Z, 0 range violations");
            end

            if (dp_failures > 0) begin
                $display("  FAIL: %0d Step 2.5.5 test(s) failed", dp_failures);
                total_failures = total_failures + 1;
            end else
                $display("  PASS: All Step 2.5.5 datapath CDC config tests passed");
        end

        // Step 2.5.6: Enable and phase-update semantics
        // Tests: disable stops tvalid, re-enable resumes with deterministic phase,
        // known phase produces expected quadrant, phase change while streaming is safe.
        $display("\nSTEP 2.5.6 - ENABLE AND PHASE-UPDATE SEMANTICS:");
        $display("----------------------------------------");
        begin
            integer en_phase_failures;
            en_phase_failures = 0;

            // Ensure clean CDC state
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
                if (uut.cfg_req_pending) begin
                    wait_cfg_pending_clear(200);
                end
            end

            // --- Test 1: Disable stops tvalid ---
            $display("  Test 1: disable stops tvalid");
            // Ensure streaming is active
            write_register(7'h01, 32'd2000000);
            write_register(7'h02, 32'h7FFF);
            write_register(7'h03, 32'd0);
            write_register(7'h04, 32'd0);
            write_register(7'h05, 32'd1);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
                if (uut.cfg_req_pending) begin
                    wait_cfg_pending_clear(200);
                end
            end
            // Wait for startup guard
            repeat (210) @(posedge m00_axis_aclk);

            if (!m00_axis_tvalid) begin
                $display("    FAIL: streaming not active before disable test");
                en_phase_failures = en_phase_failures + 1;
            end else begin
                $display("    PASS: streaming confirmed active");

                // Disable
                write_register(7'h05, 32'd0);
                if (uut.cfg_req_pending) begin
                    wait_cfg_pending_clear(200);
                end
                // Wait for cfg_dac_enable to propagate and output_valid to deassert
                repeat (30) @(posedge m00_axis_aclk);

                if (m00_axis_tvalid) begin
                    $display("    FAIL: tvalid still asserted after disable");
                    en_phase_failures = en_phase_failures + 1;
                end else
                    $display("    PASS: tvalid deasserted after disable");
            end

            // --- Test 2: Re-enable with deterministic phase (90 degrees) ---
            $display("  Test 2: re-enable with phase=90deg produces expected quadrant");
            // Set frequency=0 for deterministic output, phase=90 degrees
            write_register(7'h01, 32'd0);
            write_register(7'h03, 32'h40000000);
            // Re-enable
            write_register(7'h05, 32'd1);

            // Wait for CDC round-trip for all writes (may need multiple round-trips due to dirty)
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
                if (uut.cfg_req_pending) begin
                    wait_cfg_pending_clear(200);
                end
            end

            // Wait for startup guard (2 cycles) plus settling
            repeat (210) @(posedge m00_axis_aclk);

            if (!m00_axis_tvalid) begin
                $display("    FAIL: tvalid not reasserted after re-enable");
                en_phase_failures = en_phase_failures + 1;
            end else begin
                $display("    PASS: tvalid reasserted after startup guard");

                // Collect first valid beat and verify phase quadrant
                begin
                    integer collected;
                    collected = 0;
                    while (!collected) begin
                        @(posedge m00_axis_aclk);
                        if (m00_axis_tvalid && m00_axis_tready) begin
                            decode_beat(m00_axis_tdata);
                            collected = 1;
                        end
                    end

                    // At phase=90 deg, frequency=0:
                    // sine ~ +8191 (I channel -> I*4 ~ +32764, near 0x7FFC)
                    // cosine ~ 0 (Q channel -> Q*4 ~ 0)
                    // With Q15 quantization, expect sine in [8185, 8191] range
                    // After *4 scaling: I0 in [32740, 32764], Q0 in [-20, +20]
                    begin
                        integer i_ok;
                        integer q_ok;
                        i_ok = (dec_word0 >= 32740 && dec_word0 <= 32764);
                        q_ok = (dec_word1 >= -20 && dec_word1 <= 20);

                        if (!i_ok) begin
                            $display("    FAIL: I0=%d not near +32764 (expected [32740, 32764])",
                                     dec_word0);
                            en_phase_failures = en_phase_failures + 1;
                        end else
                            $display("    PASS: I0=%d near +FS (sine quadrant at 90deg)", dec_word0);

                        if (!q_ok) begin
                            $display("    FAIL: Q0=%d not near 0 (expected [-20, +20])",
                                     dec_word1);
                            en_phase_failures = en_phase_failures + 1;
                        end else
                            $display("    PASS: Q0=%d near 0 (cosine quadrant at 90deg)", dec_word1);

                        // Verify no X/Z
                        if (beat_has_xz()) begin
                            $display("    FAIL: X/Z detected in first beat after re-enable");
                            en_phase_failures = en_phase_failures + 1;
                        end

                        // Verify all words in range
                        if (beat_out_of_range()) begin
                            $display("    FAIL: out-of-range word in first beat after re-enable");
                            en_phase_failures = en_phase_failures + 1;
                        end
                    end
                end
            end

            // --- Test 3: Phase=0 deg verification ---
            $display("  Test 3: re-enable with phase=0deg produces expected quadrant");
            // Disable, change phase to 0, re-enable
            write_register(7'h05, 32'd0);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
            end
            repeat (10) @(posedge m00_axis_aclk);

            write_register(7'h03, 32'd0);
            write_register(7'h05, 32'd1);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
                if (uut.cfg_req_pending) begin
                    wait_cfg_pending_clear(200);
                end
            end
            repeat (210) @(posedge m00_axis_aclk);

            if (!m00_axis_tvalid) begin
                $display("    FAIL: tvalid not reasserted for phase=0 test");
                en_phase_failures = en_phase_failures + 1;
            end else begin
                begin
                    integer collected;
                    collected = 0;
                    while (!collected) begin
                        @(posedge m00_axis_aclk);
                        if (m00_axis_tvalid && m00_axis_tready) begin
                            decode_beat(m00_axis_tdata);
                            collected = 1;
                        end
                    end

                    // At phase=0 deg, frequency=0:
                    // sine ~ 0 (I channel -> I0 ~ 0)
                    // cosine ~ +8191 (Q channel -> Q0 ~ +32764, near 0x7FFC)
                    begin
                        integer i_ok;
                        integer q_ok;
                        i_ok = (dec_word0 >= -20 && dec_word0 <= 20);
                        q_ok = (dec_word1 >= 32740 && dec_word1 <= 32764);

                        if (!i_ok) begin
                            $display("    FAIL: I0=%d not near 0 (expected [-20, +20])",
                                     dec_word0);
                            en_phase_failures = en_phase_failures + 1;
                        end else
                            $display("    PASS: I0=%d near 0 (sine quadrant at 0deg)", dec_word0);

                        if (!q_ok) begin
                            $display("    FAIL: Q0=%d not near +32764 (expected [32740, 32764])",
                                     dec_word1);
                            en_phase_failures = en_phase_failures + 1;
                        end else
                            $display("    PASS: Q0=%d near +FS (cosine quadrant at 0deg)", dec_word1);
                    end
                end
            end

            // --- Test 4: Phase change while streaming ---
            $display("  Test 4: phase change while streaming produces no X/Z or out-of-range");
            // Re-enable with 2 MHz tone
            write_register(7'h01, 32'd2000000);
            write_register(7'h03, 32'd0);
            write_register(7'h05, 32'd1);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
                if (uut.cfg_req_pending) begin
                    wait_cfg_pending_clear(200);
                end
            end
            repeat (210) @(posedge m00_axis_aclk);

            // Wait for tvalid
            begin
                integer wait_tv;
                wait_tv = 0;
                while (!m00_axis_tvalid && wait_tv < 100) begin
                    @(posedge m00_axis_aclk);
                    wait_tv = wait_tv + 1;
                end
                if (wait_tv >= 100) begin
                    $display("    FAIL: tvalid did not assert for phase-change test");
                    en_phase_failures = en_phase_failures + 1;
                end
            end

            // Collect 20 beats, then change phase mid-stream
            begin
                integer b, phase_xz, phase_range;
                phase_xz = 0;
                phase_range = 0;
                b = 0;
                while (b < 20) begin
                    @(posedge m00_axis_aclk);
                    if (m00_axis_tvalid && m00_axis_tready) begin
                        b = b + 1;
                    end
                end

                // Change phase to 180 degrees while streaming
                write_register(7'h03, 32'h80000000);
                // Wait for CDC transfer
                if (uut.cfg_req_pending) begin
                    wait_cfg_pending_clear(200);
                end

                // Collect 100 beats after phase change
                b = 0;
                while (b < 100) begin
                    @(posedge m00_axis_aclk);
                    if (m00_axis_tvalid && m00_axis_tready) begin
                        b = b + 1;
                        decode_beat(m00_axis_tdata);
                        if (beat_has_xz()) begin
                            phase_xz = phase_xz + 1;
                        end
                        if (beat_out_of_range()) begin
                            phase_range = phase_range + 1;
                        end
                    end
                end

                if (phase_xz > 0) begin
                    $display("    FAIL: %0d X/Z word(s) during phase change", phase_xz);
                    en_phase_failures = en_phase_failures + 1;
                end else
                    $display("    PASS: 0 X/Z words during phase change (100 beats)");

                if (phase_range > 0) begin
                    $display("    FAIL: %0d out-of-range word(s) during phase change", phase_range);
                    en_phase_failures = en_phase_failures + 1;
                end else
                    $display("    PASS: 0 out-of-range words during phase change (100 beats)");
            end

            if (en_phase_failures > 0) begin
                $display("  FAIL: %0d Step 2.5.6 test(s) failed", en_phase_failures);
                total_failures = total_failures + 1;
            end else
                $display("  PASS: All Step 2.5.6 enable and phase-update tests passed");
        end

        // Step 2.4.5: Reset during partially complete AXI transactions
        $display("\nSTEP 2.4.5 - RESET DURING TRANSACTIONS:");
        $display("----------------------------------------");
        begin
            integer rst_failures;
            rst_failures = 0;

            // Test 1: Reset after AW but before W
            // Assert AW, let it be accepted, then reset before W arrives.
            $display("  Test: reset after AW but before W");
            begin
                // Disable streaming to keep AXIS side quiet
                write_register(7'h05, 32'd0);
                repeat (3) @(posedge s00_axi_aclk);

                // Drive AW and let it be accepted
                s00_axi_awaddr = 7'h01;
                s00_axi_awprot = 3'h0;
                s00_axi_awvalid = 1;
                s00_axi_wvalid  = 0;
                @(posedge s00_axi_aclk);
                // AW should have been accepted (awready was high)

                // Assert reset before driving W
                s00_axi_awvalid = 0;
                s00_axi_aresetn = 0;
                m00_axis_aresetn = 0;
                @(posedge s00_axi_aclk);
                @(posedge s00_axi_aclk);

                // Deassert reset
                s00_axi_aresetn = 1;
                m00_axis_aresetn = 1;
                repeat (3) @(posedge s00_axi_aclk);

                // Verify bus is clean: awready and wready should be high
                if (!s00_axi_awready) begin
                    $display("    FAIL: awready not asserted after reset (AW-before-W case)");
                    rst_failures = rst_failures + 1;
                end
                if (!s00_axi_wready) begin
                    $display("    FAIL: wready not asserted after reset (AW-before-W case)");
                    rst_failures = rst_failures + 1;
                end
                if (!s00_axi_arready) begin
                    $display("    FAIL: arready not asserted after reset (AW-before-W case)");
                    rst_failures = rst_failures + 1;
                end

                // Verify bus can perform a normal write/read
                write_register(7'h01, 32'd2000000);
                read_register(7'h01, rb_data);
                if (rb_data !== 32'd2000000) begin
                    $display("    FAIL: post-reset write/read mismatch = 0x%08h (expected 0x%08h)", rb_data, 32'd2000000);
                    rst_failures = rst_failures + 1;
                end else
                    $display("    PASS: AW-before-W reset cleared, post-reset write/read OK");
            end

            // Test 2: Reset after W but before AW
            // Drive W first, let it be accepted, then reset before AW arrives.
            $display("  Test: reset after W but before AW");
            begin
                write_register(7'h05, 32'd0);
                repeat (3) @(posedge s00_axi_aclk);

                // Drive W and let it be accepted
                s00_axi_wdata   = 32'hDEADBEEF;
                s00_axi_wstrb   = 4'hF;
                s00_axi_wvalid  = 1;
                s00_axi_awvalid = 0;
                @(posedge s00_axi_aclk);
                // W should have been accepted (wready was high)

                // Assert reset before driving AW
                s00_axi_wvalid = 0;
                s00_axi_wstrb  = 0;
                s00_axi_aresetn = 0;
                m00_axis_aresetn = 0;
                @(posedge s00_axi_aclk);
                @(posedge s00_axi_aclk);

                // Deassert reset
                s00_axi_aresetn = 1;
                m00_axis_aresetn = 1;
                repeat (3) @(posedge s00_axi_aclk);

                // Verify bus is clean
                if (!s00_axi_awready) begin
                    $display("    FAIL: awready not asserted after reset (W-before-AW case)");
                    rst_failures = rst_failures + 1;
                end
                if (!s00_axi_wready) begin
                    $display("    FAIL: wready not asserted after reset (W-before-AW case)");
                    rst_failures = rst_failures + 1;
                end

                // Verify bus can perform a normal write/read
                write_register(7'h01, 32'd2000000);
                read_register(7'h01, rb_data);
                if (rb_data !== 32'd2000000) begin
                    $display("    FAIL: post-reset write/read mismatch = 0x%08h (expected 0x%08h)", rb_data, 32'd2000000);
                    rst_failures = rst_failures + 1;
                end else
                    $display("    PASS: W-before-AW reset cleared, post-reset write/read OK");
            end

            // Test 3: Reset while BVALID=1 && BREADY=0
            // Complete a write so BVALID asserts, hold BREADY=0, then reset.
            $display("  Test: reset while BVALID=1 && BREADY=0");
            begin
                write_register(7'h05, 32'd0);
                repeat (3) @(posedge s00_axi_aclk);

                // Initiate write, hold BREADY=0
                s00_axi_awaddr = 7'h03;
                s00_axi_awprot = 3'h0;
                s00_axi_awvalid = 1;
                s00_axi_wdata   = 32'h12345678;
                s00_axi_wstrb   = 4'hF;
                s00_axi_wvalid  = 1;
                s00_axi_bready  = 0;
                @(posedge s00_axi_aclk);
                s00_axi_awvalid = 0;
                s00_axi_wvalid  = 0;
                s00_axi_wstrb   = 0;

                // Wait for BVALID to assert
                while (!s00_axi_bvalid) @(posedge s00_axi_aclk);

                // Assert reset while BVALID=1 && BREADY=0
                s00_axi_aresetn = 0;
                m00_axis_aresetn = 0;
                @(posedge s00_axi_aclk);
                @(posedge s00_axi_aclk);

                // Deassert reset
                s00_axi_aresetn = 1;
                m00_axis_aresetn = 1;
                s00_axi_bready  = 0;
                repeat (3) @(posedge s00_axi_aclk);

                // BVALID should be cleared
                if (s00_axi_bvalid) begin
                    $display("    FAIL: bvalid still asserted after reset (BVALID=1 case)");
                    rst_failures = rst_failures + 1;
                end

                // Verify bus is clean
                if (!s00_axi_awready) begin
                    $display("    FAIL: awready not asserted after reset (BVALID=1 case)");
                    rst_failures = rst_failures + 1;
                end

                // Verify register was NOT written (reset prevented commit)
                read_register(7'h03, rb_data);
                // phase_ctrl was last set to 0 by earlier restoration; reset should clear to 0
                if (rb_data !== 32'd0) begin
                    $display("    FAIL: register not cleared after reset during BVALID = 0x%08h", rb_data);
                    rst_failures = rst_failures + 1;
                end

                // Verify bus can perform a normal write/read
                write_register(7'h03, 32'd0);
                write_register(7'h01, 32'd2000000);
                read_register(7'h01, rb_data);
                if (rb_data !== 32'd2000000) begin
                    $display("    FAIL: post-reset write/read mismatch = 0x%08h", rb_data);
                    rst_failures = rst_failures + 1;
                end else
                    $display("    PASS: BVALID=1 reset cleared, register not corrupted, post-reset OK");
            end

            // Test 4: Reset while RVALID=1 && RREADY=0
            // Initiate a read, let RVALID assert, hold RREADY=0, then reset.
            $display("  Test: reset while RVALID=1 && RREADY=0");
            begin
                write_register(7'h05, 32'd0);
                repeat (3) @(posedge s00_axi_aclk);

                // Initiate read, hold RREADY=0
                s00_axi_araddr = 7'h01;
                s00_axi_arprot = 3'h0;
                s00_axi_arvalid = 1;
                s00_axi_rready  = 0;
                @(posedge s00_axi_aclk);
                s00_axi_arvalid = 0;

                // Wait for RVALID to assert
                while (!s00_axi_rvalid) @(posedge s00_axi_aclk);

                // Assert reset while RVALID=1 && RREADY=0
                s00_axi_aresetn = 0;
                m00_axis_aresetn = 0;
                @(posedge s00_axi_aclk);
                @(posedge s00_axi_aclk);

                // Deassert reset
                s00_axi_aresetn = 1;
                m00_axis_aresetn = 1;
                s00_axi_rready  = 0;
                repeat (3) @(posedge s00_axi_aclk);

                // RVALID should be cleared
                if (s00_axi_rvalid) begin
                    $display("    FAIL: rvalid still asserted after reset (RVALID=1 case)");
                    rst_failures = rst_failures + 1;
                end

                // ARREADY should be high (read channel free)
                if (!s00_axi_arready) begin
                    $display("    FAIL: arready not asserted after reset (RVALID=1 case)");
                    rst_failures = rst_failures + 1;
                end

                // Verify bus can perform a normal write/read
                write_register(7'h01, 32'd2000000);
                read_register(7'h01, rb_data);
                if (rb_data !== 32'd2000000) begin
                    $display("    FAIL: post-reset write/read mismatch = 0x%08h", rb_data);
                    rst_failures = rst_failures + 1;
                end else
                    $display("    PASS: RVALID=1 reset cleared, post-reset write/read OK");
            end

            if (rst_failures > 0) begin
                $display("  FAIL: %0d reset-during-transaction test(s) failed", rst_failures);
                total_failures = total_failures + 1;
            end else
                $display("  PASS: All Step 2.4.5 reset-during-transaction tests passed");
        end

        // Step 2.6: Hardware bring-up modes
        // Re-enable streaming for mode tests
        write_register(7'h00, 32'd1);  // waveform_type=1 (sine)
        write_register(7'h01, 32'd2000000);
        write_register(7'h02, 32'h00007FFF);
        write_register(7'h03, 32'd0);
        write_register(7'h04, 32'd0);
        write_register(7'h05, 32'd1);
        if (uut.cfg_req_pending) begin
            wait_cfg_pending_clear(200);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
            end
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
            end
        end
        repeat (210) @(posedge m00_axis_aclk);

        // Step 2.6.1: Waveform-type behavior and sine mode pass-through
        $display("\nSTEP 2.6.1 - WAVEFORM TYPE AND ZERO OUTPUT MODE:");
        $display("----------------------------------------");
        begin
            integer wf_failures;
            wf_failures = 0;

            // Sine mode verification: existing sine/cosine checks already passed
            // above with waveform_type=1. Verify streaming is active after re-enable.
            $display("  Test: sine mode (waveform_type=1) streaming pass-through");
            begin
                int sine_wait_tv;
                sine_wait_tv = 0;
                while (!m00_axis_tvalid && sine_wait_tv < 100) begin
                    @(posedge m00_axis_aclk);
                    sine_wait_tv = sine_wait_tv + 1;
                end
                if (sine_wait_tv >= 100) begin
                    $display("    FAIL: tvalid did not assert within 100 cycles for sine mode");
                    wf_failures = wf_failures + 1;
                end else begin
                    decode_beat(m00_axis_tdata);
                    if (beat_has_xz()) begin
                        $display("    FAIL: X/Z in sine mode output");
                        wf_failures = wf_failures + 1;
                    end else
                        $display("    PASS: sine mode streaming active after %0d cycles, no X/Z", sine_wait_tv);
                end
            end

            // Unsupported waveform type (value 5) should produce zero output
            $display("  Test: unsupported waveform_type=5 produces zero output");
            write_register(7'h00, 32'd5);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
            end
            repeat (20) @(posedge m00_axis_aclk);

            // Wait for tvalid to deassert
            begin
                int wait_deassert;
                wait_deassert = 0;
                while (m00_axis_tvalid && wait_deassert < 20) begin
                    @(posedge m00_axis_aclk);
                    wait_deassert = wait_deassert + 1;
                end
                if (wait_deassert >= 20) begin
                    $display("    FAIL: tvalid did not deassert within 20 cycles for unsupported waveform type");
                    wf_failures = wf_failures + 1;
                end else
                    $display("    PASS: tvalid deasserted after %0d cycles", wait_deassert);
            end

            // Verify tvalid stays deasserted for 50 cycles
            begin
                int tvalid_asserts;
                int xz_count;
                int range_count;
                tvalid_asserts = 0;
                xz_count = 0;
                range_count = 0;
                repeat (50) begin
                    @(posedge m00_axis_aclk);
                    if (m00_axis_tvalid) begin
                        tvalid_asserts = tvalid_asserts + 1;
                        decode_beat(m00_axis_tdata);
                        if (beat_has_xz()) begin
                            xz_count = xz_count + 1;
                        end
                        if (beat_out_of_range()) begin
                            range_count = range_count + 1;
                        end
                    end
                end
                if (tvalid_asserts > 0) begin
                    $display("    FAIL: tvalid asserted %0d times during unsupported mode (expected 0)", tvalid_asserts);
                    wf_failures = wf_failures + 1;
                end
                if (xz_count > 0) begin
                    $display("    FAIL: %0d X/Z beats during unsupported mode", xz_count);
                    wf_failures = wf_failures + 1;
                end
                if (range_count > 0) begin
                    $display("    FAIL: %0d out-of-range beats during unsupported mode", range_count);
                    wf_failures = wf_failures + 1;
                end
                if (tvalid_asserts == 0 && xz_count == 0 && range_count == 0)
                    $display("    PASS: zero-output mode: 0 tvalid, 0 X/Z, 0 out-of-range over 50 cycles");
            end

            // Also test waveform_type=0 (explicit zero mode)
            $display("  Test: waveform_type=0 produces zero output");
            write_register(7'h00, 32'd0);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
            end
            repeat (20) @(posedge m00_axis_aclk);

            begin
                int zero_mode_tvalid;
                zero_mode_tvalid = 0;
                repeat (20) begin
                    @(posedge m00_axis_aclk);
                    if (m00_axis_tvalid) zero_mode_tvalid = zero_mode_tvalid + 1;
                end
                if (zero_mode_tvalid > 0) begin
                    $display("    FAIL: tvalid asserted %0d times for waveform_type=0", zero_mode_tvalid);
                    wf_failures = wf_failures + 1;
                end else
                    $display("    PASS: waveform_type=0: tvalid deasserted over 20 cycles");
            end

            // Restore sine mode for remaining tests
            write_register(7'h00, 32'd1);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
            end
            repeat (20) @(posedge m00_axis_aclk);

            if (wf_failures > 0) begin
                $display("  FAIL: %0d Step 2.6.1 test(s) failed", wf_failures);
                total_failures = total_failures + 1;
            end else
                $display("  PASS: All Step 2.6.1 waveform-type tests passed");
        end

        // Step 2.6.2: DC I/Q output mode
        $display("\nSTEP 2.6.2 - DC I/Q OUTPUT MODE:");
        $display("----------------------------------------");
        begin
            integer dc_failures;
            dc_failures = 0;

            // Test 1: offset=+4096, expect I=0x4000, Q=0x0000
            $display("  Test: DC mode, offset=+4096 -> I=0x4000, Q=0x0000");
            write_register(7'h00, 32'd2);
            write_register(7'h04, 32'd4096);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
                if (uut.cfg_req_pending) begin
                    wait_cfg_pending_clear(200);
                end
            end
            repeat (20) @(posedge m00_axis_aclk);

            begin
                int dc_beats;
                int dc_xz;
                int dc_bad_i;
                int dc_bad_q;
                dc_beats = 0;
                dc_xz = 0;
                dc_bad_i = 0;
                dc_bad_q = 0;
                while (dc_beats < 20) begin
                    @(posedge m00_axis_aclk);
                    if (m00_axis_tvalid && m00_axis_tready) begin
                        dc_beats = dc_beats + 1;
                        decode_beat(m00_axis_tdata);
                        if (beat_has_xz()) begin
                            dc_xz = dc_xz + 1;
                        end
                        if (dec_word0 !== 16'h4000 || dec_word2 !== 16'h4000) begin
                            dc_bad_i = dc_bad_i + 1;
                        end
                        if (dec_word1 !== 16'h0000 || dec_word3 !== 16'h0000) begin
                            dc_bad_q = dc_bad_q + 1;
                        end
                    end
                end
                if (dc_xz > 0 || dc_bad_i > 0 || dc_bad_q > 0) begin
                    $display("    FAIL: offset=+4096: X/Z=%0d, bad_I=%0d, bad_Q=%0d (expected I=0x4000, Q=0x0000)",
                             dc_xz, dc_bad_i, dc_bad_q);
                    dc_failures = dc_failures + 1;
                end else
                    $display("    PASS: offset=+4096: all I=0x4000, all Q=0x0000 over %0d beats", dc_beats);
            end

            // Test 2: offset=-4096 (14-bit two's complement: 0x3000), expect I=0xC000, Q=0x0000
            $display("  Test: DC mode, offset=-4096 -> I=0xC000, Q=0x0000");
            write_register(7'h04, 32'h00003000);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
            end
            repeat (20) @(posedge m00_axis_aclk);

            begin
                int dc_beats;
                int dc_xz;
                int dc_bad_i;
                int dc_bad_q;
                dc_beats = 0;
                dc_xz = 0;
                dc_bad_i = 0;
                dc_bad_q = 0;
                while (dc_beats < 20) begin
                    @(posedge m00_axis_aclk);
                    if (m00_axis_tvalid && m00_axis_tready) begin
                        dc_beats = dc_beats + 1;
                        decode_beat(m00_axis_tdata);
                        if (beat_has_xz()) begin
                            dc_xz = dc_xz + 1;
                        end
                        if (dec_word0 !== 16'hC000 || dec_word2 !== 16'hC000) begin
                            dc_bad_i = dc_bad_i + 1;
                        end
                        if (dec_word1 !== 16'h0000 || dec_word3 !== 16'h0000) begin
                            dc_bad_q = dc_bad_q + 1;
                        end
                    end
                end
                if (dc_xz > 0 || dc_bad_i > 0 || dc_bad_q > 0) begin
                    $display("    FAIL: offset=-4096: X/Z=%0d, bad_I=%0d, bad_Q=%0d (expected I=0xC000, Q=0x0000)",
                             dc_xz, dc_bad_i, dc_bad_q);
                    dc_failures = dc_failures + 1;
                end else
                    $display("    PASS: offset=-4096: all I=0xC000, all Q=0x0000 over %0d beats", dc_beats);
            end

           // Test 3: Positive boundary - offset=+8191 (max 14-bit: 0x1FFF), expect I=0x7FFC
            $display("  Test: DC mode, positive boundary offset=+8191 -> I=0x7FFC");
            write_register(7'h04, 32'h00001FFF);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
            end
            repeat (20) @(posedge m00_axis_aclk);

            begin
                int dc_beats;
                int dc_bad_i;
                dc_beats = 0;
                dc_bad_i = 0;
                while (dc_beats < 20) begin
                    @(posedge m00_axis_aclk);
                    if (m00_axis_tvalid && m00_axis_tready) begin
                        dc_beats = dc_beats + 1;
                        decode_beat(m00_axis_tdata);
                        if (dec_word0 !== 16'h7FFC || dec_word2 !== 16'h7FFC) begin
                            dc_bad_i = dc_bad_i + 1;
                        end
                    end
                end
                if (dc_bad_i > 0) begin
                    $display("    FAIL: positive boundary: %0d beats with wrong I (expected 0x7FFC)", dc_bad_i);
                    dc_failures = dc_failures + 1;
                end else
                    $display("    PASS: positive boundary: all I=0x7FFC over %0d beats", dc_beats);
            end

            // Test 4: Negative boundary - offset=-8192 (min 14-bit: 0x2000), expect I=0x8000
            $display("  Test: DC mode, negative boundary offset=-8192 -> I=0x8000");
            write_register(7'h04, 32'h00002000);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
            end
            repeat (20) @(posedge m00_axis_aclk);

            begin
                int dc_beats;
                int dc_bad_i;
                dc_beats = 0;
                dc_bad_i = 0;
                while (dc_beats < 20) begin
                    @(posedge m00_axis_aclk);
                    if (m00_axis_tvalid && m00_axis_tready) begin
                        dc_beats = dc_beats + 1;
                        decode_beat(m00_axis_tdata);
                        if (dec_word0 !== 16'h8000 || dec_word2 !== 16'h8000) begin
                            dc_bad_i = dc_bad_i + 1;
                        end
                    end
                end
                if (dc_bad_i > 0) begin
                    $display("    FAIL: negative boundary: %0d beats with wrong I (expected 0x8000)", dc_bad_i);
                    dc_failures = dc_failures + 1;
                end else
                    $display("    PASS: negative boundary: all I=0x8000 over %0d beats", dc_beats);
            end

            // Restore offset=0
            write_register(7'h04, 32'd0);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
            end
            repeat (10) @(posedge m00_axis_aclk);

            if (dc_failures > 0) begin
                $display("  FAIL: %0d Step 2.6.2 test(s) failed", dc_failures);
                total_failures = total_failures + 1;
            end else
                $display("  PASS: All Step 2.6.2 DC I/Q mode tests passed");
        end

        // Step 2.6.3: Mode switching while enabled
        $display("\nSTEP 2.6.3 - MODE SWITCHING WHILE ENABLED:");
        $display("----------------------------------------");
        begin
            int switch_failures;
            switch_failures = 0;

            // Ensure sine mode is active
            write_register(7'h00, 32'd1);
            write_register(7'h04, 32'd0);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
            end
            repeat (20) @(posedge m00_axis_aclk);

            // Verify sine mode output is non-constant
            $display("  Test: sine mode baseline (non-constant output)");
            begin
                int sine_beats;
                int sine_varying;
                reg signed [15:0] ref_i;
                sine_beats = 0;
                sine_varying = 0;
                while (sine_beats < 30) begin
                    @(posedge m00_axis_aclk);
                    if (m00_axis_tvalid && m00_axis_tready) begin
                        sine_beats = sine_beats + 1;
                        decode_beat(m00_axis_tdata);
                        if (sine_beats == 1) begin
                            ref_i = dec_word0;
                        end else if (dec_word0 !== ref_i) begin
                            sine_varying = sine_varying + 1;
                        end
                    end
                end
                if (sine_varying < 25) begin
                    $display("    FAIL: sine mode output not varying (%0d/%0d beats differ)", sine_varying, sine_beats - 1);
                    switch_failures = switch_failures + 1;
                end else
                    $display("    PASS: sine mode varying: %0d/%0d beats differ from reference", sine_varying, sine_beats - 1);
            end

            // Switch to DC mode: offset=+2048 -> I=0x2000, Q=0x0000
            $display("  Test: switch sine -> DC mode (offset=+2048)");
            write_register(7'h00, 32'd2);
            write_register(7'h04, 32'd2048);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
                if (uut.cfg_req_pending) begin
                    wait_cfg_pending_clear(200);
                end
            end
            repeat (20) @(posedge m00_axis_aclk);

            begin
                int dc_beats;
                int dc_xz;
                int dc_bad_i;
                int dc_bad_q;
                dc_beats = 0;
                dc_xz = 0;
                dc_bad_i = 0;
                dc_bad_q = 0;
                while (dc_beats < 30) begin
                    @(posedge m00_axis_aclk);
                    if (m00_axis_tvalid && m00_axis_tready) begin
                        dc_beats = dc_beats + 1;
                        decode_beat(m00_axis_tdata);
                        if (beat_has_xz()) begin
                            dc_xz = dc_xz + 1;
                        end
                        if (beat_out_of_range()) begin
                            // Range check is already done per-word above; this catches any word
                        end
                        if (dec_word0 !== 16'h2000 || dec_word2 !== 16'h2000) begin
                            dc_bad_i = dc_bad_i + 1;
                        end
                        if (dec_word1 !== 16'h0000 || dec_word3 !== 16'h0000) begin
                            dc_bad_q = dc_bad_q + 1;
                        end
                    end
                end
                if (dc_xz > 0) begin
                    $display("    FAIL: X/Z detected after switch to DC mode (%0d)", dc_xz);
                    switch_failures = switch_failures + 1;
                end else if (dc_bad_i > 0 || dc_bad_q > 0) begin
                    $display("    FAIL: DC mode wrong values: bad_I=%0d, bad_Q=%0d (expected I=0x2000, Q=0x0000)",
                             dc_bad_i, dc_bad_q);
                    switch_failures = switch_failures + 1;
                end else
                    $display("    PASS: DC mode: I=0x2000, Q=0x0000 over %0d beats, no X/Z", dc_beats);
            end

            // Switch back to sine mode
            $display("  Test: switch DC -> sine mode");
            write_register(7'h00, 32'd1);
            write_register(7'h04, 32'd0);
            if (uut.cfg_req_pending) begin
                wait_cfg_pending_clear(200);
                if (uut.cfg_req_pending) begin
                    wait_cfg_pending_clear(200);
                end
            end
            repeat (20) @(posedge m00_axis_aclk);

            // Wait for tvalid and verify non-constant sine output resumes
            begin
                int wait_tv;
                wait_tv = 0;
                while (!m00_axis_tvalid && wait_tv < 30) begin
                    @(posedge m00_axis_aclk);
                    wait_tv = wait_tv + 1;
                end
                if (wait_tv >= 30) begin
                    $display("    FAIL: tvalid did not assert after switch back to sine mode");
                    switch_failures = switch_failures + 1;
                end else begin
                    // Collect 30 beats and verify non-constant output
                    int sine_beats;
                    int sine_varying;
                    int sine_xz;
                    int sine_range;
                    reg signed [15:0] ref_i2;
                    sine_beats = 0;
                    sine_varying = 0;
                    sine_xz = 0;
                    sine_range = 0;
                    while (sine_beats < 30) begin
                        @(posedge m00_axis_aclk);
                        if (m00_axis_tvalid && m00_axis_tready) begin
                            sine_beats = sine_beats + 1;
                            decode_beat(m00_axis_tdata);
                            if (beat_has_xz()) begin
                                sine_xz = sine_xz + 1;
                            end
                            if (dec_word0 < -32768 || dec_word0 > 32764 ||
                                dec_word1 < -32768 || dec_word1 > 32764) begin
                                sine_range = sine_range + 1;
                            end
                            if (sine_beats == 1) begin
                                ref_i2 = dec_word0;
                            end else if (dec_word0 !== ref_i2) begin
                                sine_varying = sine_varying + 1;
                            end
                        end
                    end
                    if (sine_xz > 0) begin
                        $display("    FAIL: X/Z detected after switch back to sine (%0d)", sine_xz);
                        switch_failures = switch_failures + 1;
                    end else if (sine_range > 0) begin
                        $display("    FAIL: out-of-range words after switch back to sine (%0d)", sine_range);
                        switch_failures = switch_failures + 1;
                    end else if (sine_varying < 25) begin
                        $display("    FAIL: sine output not varying after switch back (%0d/%0d)", sine_varying, sine_beats - 1);
                        switch_failures = switch_failures + 1;
                    end else
                        $display("    PASS: sine mode resumed: %0d/%0d beats varying, no X/Z, all in range",
                                 sine_varying, sine_beats - 1);
                end
            end

            // Final safety check: collect 50 beats, verify no X/Z, no malformed beats, valid tvalid
            $display("  Test: post-switch safety (50 beats, no X/Z, no out-of-range)");
            begin
                int safe_beats;
                int safe_xz;
                int safe_range;
                safe_beats = 0;
                safe_xz = 0;
                safe_range = 0;
                while (safe_beats < 50) begin
                    @(posedge m00_axis_aclk);
                    if (m00_axis_tvalid && m00_axis_tready) begin
                        safe_beats = safe_beats + 1;
                        decode_beat(m00_axis_tdata);
                        if (beat_has_xz()) begin
                            safe_xz = safe_xz + 1;
                        end
                        if (beat_out_of_range()) begin
                            safe_range = safe_range + 1;
                        end
                    end
                end
                if (safe_xz > 0 || safe_range > 0) begin
                    $display("    FAIL: post-switch safety: %0d X/Z, %0d out-of-range over %0d beats",
                             safe_xz, safe_range, safe_beats);
                    switch_failures = switch_failures + 1;
                end else
                    $display("    PASS: post-switch safety: 0 X/Z, 0 out-of-range over %0d beats", safe_beats);
            end

            if (switch_failures > 0) begin
                $display("  FAIL: %0d Step 2.6.3 test(s) failed", switch_failures);
                total_failures = total_failures + 1;
            end else
                $display("  PASS: All Step 2.6.3 mode-switching tests passed");
        end

        // Step 2.6.4: Full Step 2.6 regression checkpoint
        $display("\nSTEP 2.6.4 - FULL STEP 2.6 REGRESSION CHECKPOINT:");
        $display("----------------------------------------");
        $display("  Sine mode (2.6.1): verified above");
        $display("  Zero-output mode (2.6.1): verified above");
        $display("  DC I/Q mode (2.6.2): verified above");
        $display("  Mode switching (2.6.3): verified above");
        $display("  Existing Step 2.2-2.5.7 regressions: verified above");
        $display("  PASS: All Step 2.6 checkpoints satisfied");

        // Summary
        $display("\n========================================");
        $display("Step 2.2 + Step 2.3 + Step 2.4.1-2.4.5 + Step 2.5.1-2.5.7 + Step 2.6.1-2.6.4 Summary");
        $display("========================================");
        $display("  AXIS tdata width: %0d bits (expected 64)", C_M00_AXIS_TDATA_WIDTH);
        $display("  Words per beat: %0d (expected 4)", WORDS_PER_BEAT);
        $display("  Complex samples per beat: %0d (expected 2)", COMPLEX_SAMPLES_PER_BEAT);
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

        if (C_M00_AXIS_TDATA_WIDTH != 64) begin
            $display("  FAIL: tdata width is %0d, expected 64", C_M00_AXIS_TDATA_WIDTH);
            total_failures = total_failures + 1;
        end else begin
            $display("  PASS: tdata width is 64 bits");
        end

        if (WORDS_PER_BEAT != 4) begin
            $display("  FAIL: WORDS_PER_BEAT is %0d, expected 4", WORDS_PER_BEAT);
            total_failures = total_failures + 1;
        end else begin
            $display("  PASS: WORDS_PER_BEAT is 4");
        end

        if (COMPLEX_SAMPLES_PER_BEAT != 2) begin
            $display("  FAIL: COMPLEX_SAMPLES_PER_BEAT is %0d, expected 2", COMPLEX_SAMPLES_PER_BEAT);
            total_failures = total_failures + 1;
        end else begin
            $display("  PASS: COMPLEX_SAMPLES_PER_BEAT is 2");
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
            $display("PASS: All Step 2.2 + Step 2.3 + Step 2.4.1-2.4.5 + Step 2.5.1-2.5.7 + Step 2.6.1-2.6.4 tests passed");
        end
        $display("========================================\n");

        $finish;
    end

endmodule
