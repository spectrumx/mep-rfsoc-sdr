// function_gen_to_dac_rfdc_connectivity_tb.sv
//
// Step 3.2 package-level RFDC-facing connectivity check.
// This test intentionally instantiates the packaged top-level port set and
// connects M00_AXIS to an RFDC DAC input model with only tdata/tvalid/tready.
`timescale 1ns/1ps

module rfdc_dac0_axis_model #(
    parameter integer TDATA_WIDTH = 64
) (
    input  wire                  s_axis_aclk,
    input  wire                  s_axis_aresetn,
    input  wire                  s_axis_tvalid,
    input  wire [TDATA_WIDTH-1:0] s_axis_tdata,
    output reg                   s_axis_tready,
    input  wire                  check_dc_mode,
    input  wire signed [15:0]    expected_i_word,
    input  wire signed [15:0]    expected_q_word,
    output reg [31:0]            accepted_beats,
    output reg [31:0]            failures
);
    reg signed [15:0] word0;
    reg signed [15:0] word1;
    reg signed [15:0] word2;
    reg signed [15:0] word3;

    initial begin
        s_axis_tready = 1'b1;
        accepted_beats = 0;
        failures = 0;
    end

    always @(posedge s_axis_aclk) begin
        if (!s_axis_aresetn) begin
            s_axis_tready <= 1'b1;
            accepted_beats <= 0;
            failures <= 0;
            if (s_axis_tvalid !== 1'b0) begin
                $display("FAIL: RFDC model saw TVALID asserted during stream reset");
                failures <= failures + 1;
            end
        end else begin
            s_axis_tready <= 1'b1;
            if (s_axis_tvalid && s_axis_tready) begin
                if ($isunknown(s_axis_tdata)) begin
                    $display("FAIL: RFDC model accepted X/Z on TDATA");
                    failures <= failures + 1;
                end

                word0 = s_axis_tdata[15:0];
                word1 = s_axis_tdata[31:16];
                word2 = s_axis_tdata[47:32];
                word3 = s_axis_tdata[63:48];

                if (check_dc_mode) begin
                    if (word0 !== expected_i_word || word2 !== expected_i_word) begin
                        $display("FAIL: DC I words = %04h %04h expected %04h",
                                 word0, word2, expected_i_word);
                        failures <= failures + 1;
                    end
                    if (word1 !== expected_q_word || word3 !== expected_q_word) begin
                        $display("FAIL: DC Q words = %04h %04h expected %04h",
                                 word1, word3, expected_q_word);
                        failures <= failures + 1;
                    end
                end

                accepted_beats <= accepted_beats + 1;
            end
        end
    end
endmodule

module function_gen_to_dac_rfdc_connectivity_tb;
    parameter integer C_S00_AXI_DATA_WIDTH = 32;
    parameter integer C_S00_AXI_ADDR_WIDTH = 7;
    parameter integer C_M00_AXIS_TDATA_WIDTH = 64;

    localparam [6:0] REG_WAVEFORM_TYPE = 7'h00;
    localparam [6:0] REG_FREQUENCY     = 7'h04;
    localparam [6:0] REG_AMPLITUDE     = 7'h08;
    localparam [6:0] REG_PHASE         = 7'h0C;
    localparam [6:0] REG_OFFSET        = 7'h10;
    localparam [6:0] REG_ENABLE        = 7'h14;

    reg s00_axi_aclk;
    reg s00_axi_aresetn;
    reg [C_S00_AXI_ADDR_WIDTH-1:0] s00_axi_awaddr;
    reg [2:0] s00_axi_awprot;
    reg s00_axi_awvalid;
    wire s00_axi_awready;
    reg [C_S00_AXI_DATA_WIDTH-1:0] s00_axi_wdata;
    reg [(C_S00_AXI_DATA_WIDTH/8)-1:0] s00_axi_wstrb;
    reg s00_axi_wvalid;
    wire s00_axi_wready;
    wire [1:0] s00_axi_bresp;
    wire s00_axi_bvalid;
    reg s00_axi_bready;
    reg [C_S00_AXI_ADDR_WIDTH-1:0] s00_axi_araddr;
    reg [2:0] s00_axi_arprot;
    reg s00_axi_arvalid;
    wire s00_axi_arready;
    wire [C_S00_AXI_DATA_WIDTH-1:0] s00_axi_rdata;
    wire [1:0] s00_axi_rresp;
    wire s00_axi_rvalid;
    reg s00_axi_rready;

    reg m00_axis_aclk;
    reg m00_axis_aresetn;
    wire m00_axis_tvalid;
    wire [C_M00_AXIS_TDATA_WIDTH-1:0] m00_axis_tdata;
    wire m00_axis_tready;

    reg check_dc_mode;
    integer test_failures;
    integer wait_cycles;
    wire [31:0] rfdc_accepted_beats;
    wire [31:0] rfdc_failures;

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

    rfdc_dac0_axis_model #(
        .TDATA_WIDTH(C_M00_AXIS_TDATA_WIDTH)
    ) rfdc_dac0_model (
        .s_axis_aclk(m00_axis_aclk),
        .s_axis_aresetn(m00_axis_aresetn),
        .s_axis_tvalid(m00_axis_tvalid),
        .s_axis_tdata(m00_axis_tdata),
        .s_axis_tready(m00_axis_tready),
        .check_dc_mode(check_dc_mode),
        .expected_i_word(16'sh4000),
        .expected_q_word(16'sh0000),
        .accepted_beats(rfdc_accepted_beats),
        .failures(rfdc_failures)
    );

    initial begin
        s00_axi_aclk = 1'b0;
        forever #3.2ns s00_axi_aclk = ~s00_axi_aclk;
    end

    initial begin
        m00_axis_aclk = 1'b0;
        forever #15.625ns m00_axis_aclk = ~m00_axis_aclk;
    end

    task automatic axi_write(
        input [6:0] addr,
        input [31:0] data
    );
    begin
        @(posedge s00_axi_aclk);
        s00_axi_awaddr  <= addr;
        s00_axi_awprot  <= 3'h0;
        s00_axi_awvalid <= 1'b1;
        s00_axi_wdata   <= data;
        s00_axi_wstrb   <= 4'hF;
        s00_axi_wvalid  <= 1'b1;
        @(posedge s00_axi_aclk);
        s00_axi_awvalid <= 1'b0;
        s00_axi_wvalid  <= 1'b0;
        s00_axi_wstrb   <= 4'h0;
        while (!s00_axi_bvalid) @(posedge s00_axi_aclk);
        if (s00_axi_bresp !== 2'b00) begin
            $display("FAIL: AXI write BRESP = %b at addr 0x%02h", s00_axi_bresp, addr);
            test_failures = test_failures + 1;
        end
        s00_axi_bready <= 1'b1;
        @(posedge s00_axi_aclk);
        s00_axi_bready <= 1'b0;
    end
    endtask

    initial begin
        test_failures = 0;
        wait_cycles = 0;
        check_dc_mode = 1'b0;

        s00_axi_aresetn = 1'b0;
        m00_axis_aresetn = 1'b0;
        s00_axi_awaddr = {C_S00_AXI_ADDR_WIDTH{1'b0}};
        s00_axi_awprot = 3'h0;
        s00_axi_awvalid = 1'b0;
        s00_axi_wdata = {C_S00_AXI_DATA_WIDTH{1'b0}};
        s00_axi_wstrb = {(C_S00_AXI_DATA_WIDTH/8){1'b0}};
        s00_axi_wvalid = 1'b0;
        s00_axi_bready = 1'b0;
        s00_axi_araddr = {C_S00_AXI_ADDR_WIDTH{1'b0}};
        s00_axi_arprot = 3'h0;
        s00_axi_arvalid = 1'b0;
        s00_axi_rready = 1'b0;

        if ($bits(m00_axis_tdata) != 64) begin
            $display("FAIL: M00_AXIS TDATA width is %0d, expected 64", $bits(m00_axis_tdata));
            $fatal;
        end
        if ($bits(s00_axi_wstrb) != 4) begin
            $display("FAIL: S00_AXI WSTRB width is %0d, expected 4", $bits(s00_axi_wstrb));
            $fatal;
        end

        repeat (8) @(posedge s00_axi_aclk);
        s00_axi_aresetn <= 1'b1;
        repeat (4) @(posedge m00_axis_aclk);
        m00_axis_aresetn <= 1'b1;
        repeat (4) @(posedge m00_axis_aclk);

        if (m00_axis_tvalid !== 1'b0) begin
            $display("FAIL: M00_AXIS TVALID asserted before enable");
            test_failures = test_failures + 1;
        end

        axi_write(REG_WAVEFORM_TYPE, 32'd2);          // DC I/Q mode
        axi_write(REG_FREQUENCY, 32'd0);              // Frequency unused in DC mode
        axi_write(REG_AMPLITUDE, 32'h00007FFF);       // Full scale
        axi_write(REG_PHASE, 32'd0);                  // Phase unused in DC mode
        axi_write(REG_OFFSET, 32'd4096);              // I = +4096 << 2 = 0x4000
        axi_write(REG_ENABLE, 32'd1);                 // Enable

        check_dc_mode = 1'b1;
        while (rfdc_accepted_beats < 8 && wait_cycles < 200) begin
            @(posedge m00_axis_aclk);
            wait_cycles = wait_cycles + 1;
        end

        if (rfdc_accepted_beats < 8) begin
            $display("FAIL: RFDC model accepted only %0d beats after enable", rfdc_accepted_beats);
            test_failures = test_failures + 1;
        end

        if (rfdc_failures != 0) begin
            $display("FAIL: RFDC model reported %0d stream failures", rfdc_failures);
            test_failures = test_failures + rfdc_failures;
        end

        axi_write(REG_ENABLE, 32'd0);          // Disable
        repeat (4) @(posedge m00_axis_aclk);
        if (m00_axis_tvalid !== 1'b0) begin
            $display("FAIL: M00_AXIS TVALID remains asserted after disable");
            test_failures = test_failures + 1;
        end

        // Lightweight signed-frequency connectivity check: negative frequency
        // must not change AXIS width, lane packing, or handshake behavior.
        check_dc_mode = 1'b0;
        wait_cycles = 0;
        axi_write(REG_WAVEFORM_TYPE, 32'd1);          // sine/cos mode
        axi_write(REG_FREQUENCY, 32'hFFE17B80);       // -2,000,000 Hz
        axi_write(REG_AMPLITUDE, 32'h00007FFF);       // Full scale
        axi_write(REG_PHASE, 32'd0);
        axi_write(REG_OFFSET, 32'd0);
        axi_write(REG_ENABLE, 32'd1);
        while (rfdc_accepted_beats < 16 && wait_cycles < 300) begin
            @(posedge m00_axis_aclk);
            wait_cycles = wait_cycles + 1;
        end
        if (rfdc_accepted_beats < 16) begin
            $display("FAIL: RFDC model did not accept signed-frequency sine/cos beats");
            test_failures = test_failures + 1;
        end
        axi_write(REG_ENABLE, 32'd0);

        $display("RFDC DAC connectivity assumptions checked:");
        $display("  M00_AXIS width: %0d bits", $bits(m00_axis_tdata));
        $display("  Beat layout: I0, Q0, I1, Q1");
        $display("  M00_AXIS ports modeled: tdata/tvalid/tready only");
        $display("  AXIS clock period: 31.25 ns (32 MHz)");
        $display("  AXI-Lite clock period: 6.4 ns (156.25 MHz)");

        if (test_failures != 0) begin
            $display("RFDC connectivity test FAILED with %0d failures", test_failures);
            $fatal;
        end

        $display("RFDC connectivity test PASSED");
        $finish;
    end
endmodule
