`timescale 1 ns / 1 ps

module adc_to_udp_stream_axi_tb;

    // Parameters matching DUT defaults used by existing ADC testbenches
    parameter integer C_S00_AXI_DATA_WIDTH   = 32;
    parameter integer C_S00_AXI_ADDR_WIDTH   = 7;
    parameter integer C_S01_AXIS_TDATA_WIDTH = 64;
    parameter integer C_M00_AXIS_TDATA_WIDTH = 64;
    parameter integer C_M00_AXIS_TKEEP_WIDTH = 8;
    parameter integer UDP_PORT               = 60133;

    // Register offset localparams (byte offsets, 7-bit values)
    localparam [6:0] REG_CTRL                    = 7'h00;
    localparam [6:0] REG_FREQUENCY_IDX           = 7'h04;
    localparam [6:0] REG_RECEIVED_COUNTER        = 7'h08;
    localparam [6:0] REG_ETH_DST_MAC_LSB         = 7'h0C;
    localparam [6:0] REG_ETH_DST_MAC_MSB         = 7'h10;
    localparam [6:0] REG_IP_SRC_ADDR             = 7'h14;
    localparam [6:0] REG_IP_DST_ADDR             = 7'h18;
    localparam [6:0] REG_IP_SRC_PORT             = 7'h1C;
    localparam [6:0] REG_IP_DST_PORT             = 7'h20;
    localparam [6:0] REG_SAMPLE_IDX_OFFSET_LSB   = 7'h24;
    localparam [6:0] REG_SAMPLE_IDX_OFFSET_MSB   = 7'h28;
    localparam [6:0] REG_PPS_COUNTER             = 7'h2C;
    localparam [6:0] REG_SAMPLE_RATE_NUM_LSB     = 7'h30;
    localparam [6:0] REG_SAMPLE_RATE_NUM_MSB     = 7'h34;
    localparam [6:0] REG_SAMPLE_RATE_DEN_LSB     = 7'h38;
    localparam [6:0] REG_SAMPLE_RATE_DEN_MSB     = 7'h3C;

    // S00 AXI4-Lite signals
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

    // S01 AXIS signals
    reg s01_axis_aclk;
    reg s01_axis_aresetn;
    reg s01_axis_tvalid;
    reg [C_S01_AXIS_TDATA_WIDTH-1:0] s01_axis_tdata;
    wire s01_axis_tready;

    // M00 AXIS signals
    reg m00_axis_aclk;
    reg m00_axis_aresetn;
    wire m00_axis_tvalid;
    wire [C_M00_AXIS_TDATA_WIDTH-1:0] m00_axis_tdata;
    wire [C_M00_AXIS_TKEEP_WIDTH-1:0] m00_axis_tkeep;
    wire m00_axis_tuser;
    wire m00_axis_tlast;
    reg m00_axis_tready;

    // PPS
    reg pps_comp;

    // DUT instantiation
    adc_to_udp_stream_v1_0 #(
        .C_S00_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S00_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH),
        .C_S01_AXIS_TDATA_WIDTH(C_S01_AXIS_TDATA_WIDTH),
        .C_M00_AXIS_TDATA_WIDTH(C_M00_AXIS_TDATA_WIDTH),
        .C_M00_AXIS_TKEEP_WIDTH(C_M00_AXIS_TKEEP_WIDTH),
        .UDP_PORT(UDP_PORT)
    ) dut (
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
        .s01_axis_aclk(s01_axis_aclk),
        .s01_axis_aresetn(s01_axis_aresetn),
        .s01_axis_tvalid(s01_axis_tvalid),
        .s01_axis_tdata(s01_axis_tdata),
        .s01_axis_tready(s01_axis_tready),
        .m00_axis_aclk(m00_axis_aclk),
        .m00_axis_aresetn(m00_axis_aresetn),
        .m00_axis_tvalid(m00_axis_tvalid),
        .m00_axis_tdata(m00_axis_tdata),
        .m00_axis_tkeep(m00_axis_tkeep),
        .m00_axis_tuser(m00_axis_tuser),
        .m00_axis_tlast(m00_axis_tlast),
        .m00_axis_tready(m00_axis_tready),
        .pps_comp(pps_comp)
    );

    // Clock generation: S00 156.25 MHz
    initial begin
        s00_axi_aclk = 0;
        forever #3.2ns s00_axi_aclk = ~s00_axi_aclk;
    end

    // Clock generation: S01 38.4 MHz
    initial begin
        s01_axis_aclk = 0;
        forever #13.02ns s01_axis_aclk = ~s01_axis_aclk;
    end

    // Clock generation: M00 156.25 MHz
    initial begin
        m00_axis_aclk = 0;
        forever #3.2ns m00_axis_aclk = ~m00_axis_aclk;
    end

    // Failure tracking
    integer total_failures;

    task fail_test;
        input string msg;
        begin
            total_failures = total_failures + 1;
            $display("FAIL: %s", msg);
        end
    endtask

    // Initialize all DUT inputs before reset release
    initial begin
        s00_axi_aresetn = 0;
        s01_axis_aresetn = 0;
        m00_axis_aresetn = 0;
        pps_comp = 0;

        s00_axi_awaddr = {C_S00_AXI_ADDR_WIDTH{1'b0}};
        s00_axi_awprot = 3'h0;
        s00_axi_awvalid = 0;
        s00_axi_wdata = {C_S00_AXI_DATA_WIDTH{1'b0}};
        s00_axi_wstrb = {(C_S00_AXI_DATA_WIDTH/8){1'b0}};
        s00_axi_wvalid = 0;
        s00_axi_bready = 0;
        s00_axi_araddr = {C_S00_AXI_ADDR_WIDTH{1'b0}};
        s00_axi_arprot = 3'h0;
        s00_axi_arvalid = 0;
        s00_axi_rready = 0;

        s01_axis_tvalid = 0;
        s01_axis_tdata = {C_S01_AXIS_TDATA_WIDTH{1'b0}};
        m00_axis_tready = 1;

        total_failures = 0;

        // Reset sequence: hold resets low, release after 200 ns
        #200;
        s00_axi_aresetn = 1;
        s01_axis_aresetn = 1;
        m00_axis_aresetn = 1;

        // Wait at least 10 S00 clock cycles before any AXI task
        repeat(10) @(posedge s00_axi_aclk);

        // Step 7: Verify register map and reset defaults
        expect_read(REG_CTRL, 32'h0000_0001, "REG_CTRL reset default");
        expect_read(REG_FREQUENCY_IDX, 32'h0000_0000, "REG_FREQUENCY_IDX reset default");
        expect_read(REG_ETH_DST_MAC_LSB, 32'hFFFF_FFFF, "REG_ETH_DST_MAC_LSB reset default");
        expect_read(REG_ETH_DST_MAC_MSB, 32'h0000_FFFF, "REG_ETH_DST_MAC_MSB reset default");
        expect_read(REG_SAMPLE_RATE_NUM_LSB, 32'h493E_0000, "REG_SAMPLE_RATE_NUM_LSB reset default");
        expect_read(REG_SAMPLE_RATE_NUM_MSB, 32'h0000_0000, "REG_SAMPLE_RATE_NUM_MSB reset default");
        expect_read(REG_SAMPLE_RATE_DEN_LSB, 32'h0000_0010, "REG_SAMPLE_RATE_DEN_LSB reset default");
        expect_read(REG_SAMPLE_RATE_DEN_MSB, 32'h0000_0000, "REG_SAMPLE_RATE_DEN_MSB reset default");

        // Invalid offset reads back zero
        expect_read(7'h01, 32'h0000_0000, "Invalid offset 0x01 reads zero");

        // Invalid write no-mutation: write to offset 0x01, verify REG_CTRL, FREQUENCY_IDX, and 0x01 unchanged
        axi_write_same_cycle(7'h01, 32'hFFFF_FFFE, 4'hF);
        expect_read(REG_CTRL, 32'h0000_0001, "REG_CTRL after invalid write");
        expect_read(REG_FREQUENCY_IDX, 32'h0000_0000, "REG_FREQUENCY_IDX after invalid write");
        expect_read(7'h01, 32'h0000_0000, "Invalid offset 0x01 after invalid write");

        $display("Step 7 register default checks completed.");

        // Step 8: Basic read/write behavior

        // C8.2: Full-word writable registers
        axi_write_same_cycle(REG_CTRL, 32'h0000_0000, 4'hF);
        expect_read(REG_CTRL, 32'h0000_0000, "REG_CTRL write 0");

        axi_write_same_cycle(REG_CTRL, 32'h0000_0001, 4'hF);
        expect_read(REG_CTRL, 32'h0000_0001, "REG_CTRL write 1");

        axi_write_same_cycle(REG_FREQUENCY_IDX, 32'h1357_9BDF, 4'hF);
        expect_read(REG_FREQUENCY_IDX, 32'h1357_9BDF, "REG_FREQUENCY_IDX write");

        axi_write_same_cycle(REG_IP_SRC_ADDR, 32'hC0A8_0464, 4'hF);
        expect_read(REG_IP_SRC_ADDR, 32'hC0A8_0464, "REG_IP_SRC_ADDR write");

        axi_write_same_cycle(REG_IP_DST_ADDR, 32'hC0A8_0465, 4'hF);
        expect_read(REG_IP_DST_ADDR, 32'hC0A8_0465, "REG_IP_DST_ADDR write");

        axi_write_same_cycle(REG_SAMPLE_IDX_OFFSET_LSB, 32'h89AB_CDEF, 4'hF);
        expect_read(REG_SAMPLE_IDX_OFFSET_LSB, 32'h89AB_CDEF, "REG_SAMPLE_IDX_OFFSET_LSB write");

        axi_write_same_cycle(REG_SAMPLE_IDX_OFFSET_MSB, 32'h0123_4567, 4'hF);
        expect_read(REG_SAMPLE_IDX_OFFSET_MSB, 32'h0123_4567, "REG_SAMPLE_IDX_OFFSET_MSB write");

        axi_write_same_cycle(REG_SAMPLE_RATE_NUM_LSB, 32'h5566_7788, 4'hF);
        expect_read(REG_SAMPLE_RATE_NUM_LSB, 32'h5566_7788, "REG_SAMPLE_RATE_NUM_LSB write");

        axi_write_same_cycle(REG_SAMPLE_RATE_NUM_MSB, 32'h1122_3344, 4'hF);
        expect_read(REG_SAMPLE_RATE_NUM_MSB, 32'h1122_3344, "REG_SAMPLE_RATE_NUM_MSB write");

        axi_write_same_cycle(REG_SAMPLE_RATE_DEN_LSB, 32'hDDEE_FF00, 4'hF);
        expect_read(REG_SAMPLE_RATE_DEN_LSB, 32'hDDEE_FF00, "REG_SAMPLE_RATE_DEN_LSB write");

        axi_write_same_cycle(REG_SAMPLE_RATE_DEN_MSB, 32'h99AA_BBCC, 4'hF);
        expect_read(REG_SAMPLE_RATE_DEN_MSB, 32'h99AA_BBCC, "REG_SAMPLE_RATE_DEN_MSB write");

        // C8.3: UDP port checks (high 16 bits ignored)
        axi_write_same_cycle(REG_IP_SRC_PORT, 32'hABCD_1234, 4'hF);
        expect_read(REG_IP_SRC_PORT, 32'h0000_1234, "REG_IP_SRC_PORT write");

        axi_write_same_cycle(REG_IP_DST_PORT, 32'hDCBA_BEEF, 4'hF);
        expect_read(REG_IP_DST_PORT, 32'h0000_BEEF, "REG_IP_DST_PORT write");

        // C8.4: Destination MAC staging
        axi_write_same_cycle(REG_ETH_DST_MAC_LSB, 32'hA1B2_C3D4, 4'hF);
        expect_read(REG_ETH_DST_MAC_LSB, 32'hFFFF_FFFF, "REG_ETH_DST_MAC_LSB staged not committed");

        axi_write_same_cycle(REG_ETH_DST_MAC_MSB, 32'h0000_1122, 4'hF);
        expect_read(REG_ETH_DST_MAC_MSB, 32'h0000_1122, "REG_ETH_DST_MAC_MSB after commit");
        expect_read(REG_ETH_DST_MAC_LSB, 32'hA1B2_C3D4, "REG_ETH_DST_MAC_LSB after commit");

        // C8.5: Read-only write-ignore
        axi_write_same_cycle(REG_RECEIVED_COUNTER, 32'hCAFE_BABE, 4'hF);
        expect_read(REG_RECEIVED_COUNTER, 32'h0000_0000, "REG_RECEIVED_COUNTER write ignored");

        axi_write_same_cycle(REG_PPS_COUNTER, 32'h0123_4567, 4'hF);
        expect_read(REG_PPS_COUNTER, 32'h0000_0000, "REG_PPS_COUNTER write ignored");

        $display("Step 8 basic read/write checks completed.");

        // Final pass/fail
        if (total_failures == 0) begin
            $display("PASS: all S00 AXI smoke tests passed (0 failures).");
        end else begin
            $display("FAIL: %0d test(s) failed.", total_failures);
        end

        if (total_failures != 0) begin
            $fatal(1);
        end

        $finish;
    end

    // Simulation watchdog timeout
    initial begin
        #50000; // 50 us watchdog
        $display("FAIL: simulation watchdog timeout.");
        total_failures = total_failures + 1;
        $fatal(1);
    end

    // Reusable AXI helper tasks

    // axi_write_same_cycle: assert AW and W in the same cycle
    task axi_write_same_cycle;
        input [C_S00_AXI_ADDR_WIDTH-1:0] addr;
        input [C_S00_AXI_DATA_WIDTH-1:0] data;
        input [(C_S00_AXI_DATA_WIDTH/8)-1:0] strb;
        begin
            integer timeout;
            s00_axi_awaddr = addr;
            s00_axi_awprot = 3'h0;
            s00_axi_awvalid = 1;
            s00_axi_wdata = data;
            s00_axi_wstrb = strb;
            s00_axi_wvalid = 1;

            timeout = 1000;
            while ((!s00_axi_awready || !s00_axi_wready) && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail_test("axi_write_same_cycle: timeout waiting for AW/W ready.");
            end

            @(posedge s00_axi_aclk);
            s00_axi_awvalid = 0;
            s00_axi_wvalid = 0;
            s00_axi_wstrb = 0;

            timeout = 1000;
            @(posedge s00_axi_aclk);
            while (!s00_axi_bvalid && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail_test("axi_write_same_cycle: timeout waiting for BVALID.");
            end
            if (s00_axi_bresp != 2'b00) begin
                fail_test("axi_write_same_cycle: BRESP != OKAY.");
            end
            s00_axi_bready = 1;
            @(posedge s00_axi_aclk);
            s00_axi_bready = 0;
        end
    endtask

    // axi_write_aw_before_w: assert AW first, wait for ready, then assert W
    task axi_write_aw_before_w;
        input [C_S00_AXI_ADDR_WIDTH-1:0] addr;
        input [C_S00_AXI_DATA_WIDTH-1:0] data;
        input [(C_S00_AXI_DATA_WIDTH/8)-1:0] strb;
        begin
            integer timeout;
            s00_axi_awaddr = addr;
            s00_axi_awprot = 3'h0;
            s00_axi_awvalid = 1;
            s00_axi_wvalid = 0;

            timeout = 1000;
            while (!s00_axi_awready && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail_test("axi_write_aw_before_w: timeout waiting for AWREADY.");
            end

            @(posedge s00_axi_aclk);
            s00_axi_awvalid = 0;

            s00_axi_wdata = data;
            s00_axi_wstrb = strb;
            s00_axi_wvalid = 1;

            timeout = 1000;
            while (!s00_axi_wready && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail_test("axi_write_aw_before_w: timeout waiting for WREADY.");
            end

            @(posedge s00_axi_aclk);
            s00_axi_wvalid = 0;
            s00_axi_wstrb = 0;

            timeout = 1000;
            @(posedge s00_axi_aclk);
            while (!s00_axi_bvalid && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail_test("axi_write_aw_before_w: timeout waiting for BVALID.");
            end
            if (s00_axi_bresp != 2'b00) begin
                fail_test("axi_write_aw_before_w: BRESP != OKAY.");
            end
            s00_axi_bready = 1;
            @(posedge s00_axi_aclk);
            s00_axi_bready = 0;
        end
    endtask

    // axi_write_w_before_aw: assert W first, wait for ready, then assert AW
    task axi_write_w_before_aw;
        input [C_S00_AXI_ADDR_WIDTH-1:0] addr;
        input [C_S00_AXI_DATA_WIDTH-1:0] data;
        input [(C_S00_AXI_DATA_WIDTH/8)-1:0] strb;
        begin
            integer timeout;
            s00_axi_wdata = data;
            s00_axi_wstrb = strb;
            s00_axi_wvalid = 1;
            s00_axi_awvalid = 0;

            timeout = 1000;
            while (!s00_axi_wready && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail_test("axi_write_w_before_aw: timeout waiting for WREADY.");
            end

            @(posedge s00_axi_aclk);
            s00_axi_wvalid = 0;
            s00_axi_wstrb = 0;

            s00_axi_awaddr = addr;
            s00_axi_awprot = 3'h0;
            s00_axi_awvalid = 1;

            timeout = 1000;
            while (!s00_axi_awready && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail_test("axi_write_w_before_aw: timeout waiting for AWREADY.");
            end

            @(posedge s00_axi_aclk);
            s00_axi_awvalid = 0;

            timeout = 1000;
            @(posedge s00_axi_aclk);
            while (!s00_axi_bvalid && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail_test("axi_write_w_before_aw: timeout waiting for BVALID.");
            end
            if (s00_axi_bresp != 2'b00) begin
                fail_test("axi_write_w_before_aw: BRESP != OKAY.");
            end
            s00_axi_bready = 1;
            @(posedge s00_axi_aclk);
            s00_axi_bready = 0;
        end
    endtask

    // axi_write_wstrb: write with strobe (uses same-cycle by default)
    task axi_write_wstrb;
        input [C_S00_AXI_ADDR_WIDTH-1:0] addr;
        input [C_S00_AXI_DATA_WIDTH-1:0] data;
        input [(C_S00_AXI_DATA_WIDTH/8)-1:0] strb;
        begin
            axi_write_same_cycle(addr, data, strb);
        end
    endtask

    // axi_write_hold_bready: write, then hold BREADY low for stall_cycles after BVALID
    task axi_write_hold_bready;
        input [C_S00_AXI_ADDR_WIDTH-1:0] addr;
        input [C_S00_AXI_DATA_WIDTH-1:0] data;
        input [(C_S00_AXI_DATA_WIDTH/8)-1:0] strb;
        input integer stall_cycles;
        begin
            integer timeout;
            integer i;
            s00_axi_awaddr = addr;
            s00_axi_awprot = 3'h0;
            s00_axi_awvalid = 1;
            s00_axi_wdata = data;
            s00_axi_wstrb = strb;
            s00_axi_wvalid = 1;
            s00_axi_bready = 0;

            timeout = 1000;
            while ((!s00_axi_awready || !s00_axi_wready) && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail_test("axi_write_hold_bready: timeout waiting for AW/W ready.");
            end

            @(posedge s00_axi_aclk);
            s00_axi_awvalid = 0;
            s00_axi_wvalid = 0;
            s00_axi_wstrb = 0;

            timeout = 1000;
            @(posedge s00_axi_aclk);
            while (!s00_axi_bvalid && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail_test("axi_write_hold_bready: timeout waiting for BVALID.");
            end

            // Hold Bready=0 for stall_cycles
            for (i = 0; i < stall_cycles; i = i + 1) begin
                if (!s00_axi_bvalid) begin
                    fail_test("axi_write_hold_bready: BVALID dropped during stall.");
                end
                @(posedge s00_axi_aclk);
            end

            if (s00_axi_bresp != 2'b00) begin
                fail_test("axi_write_hold_bready: BRESP != OKAY.");
            end
            s00_axi_bready = 1;
            @(posedge s00_axi_aclk);
            s00_axi_bready = 0;

            // Wait for BVALID to clear
            timeout = 1000;
            while (s00_axi_bvalid && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
        end
    endtask

    // axi_read: simple read
    task axi_read;
        input [C_S00_AXI_ADDR_WIDTH-1:0] addr;
        output [C_S00_AXI_DATA_WIDTH-1:0] rdata;
        begin
            integer timeout;
            s00_axi_araddr = addr;
            s00_axi_arprot = 3'h0;
            s00_axi_arvalid = 1;
            s00_axi_rready = 0;

            timeout = 1000;
            while (!s00_axi_arready && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail_test("axi_read: timeout waiting for ARREADY.");
            end

            @(posedge s00_axi_aclk);
            s00_axi_arvalid = 0;

            timeout = 1000;
            @(posedge s00_axi_aclk);
            while (!s00_axi_rvalid && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail_test("axi_read: timeout waiting for RVALID.");
            end

            if (s00_axi_rresp != 2'b00) begin
                fail_test("axi_read: RRESP != OKAY.");
            end
            rdata = s00_axi_rdata;

            s00_axi_rready = 1;
            @(posedge s00_axi_aclk);
            s00_axi_rready = 0;

            // Wait for RVALID to clear
            timeout = 1000;
            while (s00_axi_rvalid && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
        end
    endtask

    // expect_read: call axi_read, compare result, report PASS/FAIL
    task automatic expect_read;
        input [C_S00_AXI_ADDR_WIDTH-1:0] addr;
        input [C_S00_AXI_DATA_WIDTH-1:0] expected;
        input string label;
        begin
            reg [C_S00_AXI_DATA_WIDTH-1:0] actual;
            axi_read(addr, actual);
            if (actual !== expected) begin
                fail_test($sformatf("%s: offset 0x%02h expected 0x%08h actual 0x%08h", label, addr, expected, actual));
            end else begin
                $display("PASS: %s: 0x%08h", label, actual);
            end
        end
    endtask

    // axi_read_rready_stall: read, hold RREADY=0 for stall_cycles after RVALID
    task axi_read_rready_stall;
        input [C_S00_AXI_ADDR_WIDTH-1:0] addr;
        output [C_S00_AXI_DATA_WIDTH-1:0] rdata;
        input integer stall_cycles;
        begin
            integer timeout;
            integer i;
            reg [C_S00_AXI_DATA_WIDTH-1:0] captured_rdata;

            s00_axi_araddr = addr;
            s00_axi_arprot = 3'h0;
            s00_axi_arvalid = 1;
            s00_axi_rready = 0;

            timeout = 1000;
            while (!s00_axi_arready && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail_test("axi_read_rready_stall: timeout waiting for ARREADY.");
            end

            @(posedge s00_axi_aclk);
            s00_axi_arvalid = 0;

            timeout = 1000;
            @(posedge s00_axi_aclk);
            while (!s00_axi_rvalid && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail_test("axi_read_rready_stall: timeout waiting for RVALID.");
            end

            captured_rdata = s00_axi_rdata;

            // Hold RREADY=0 for stall_cycles
            for (i = 0; i < stall_cycles; i = i + 1) begin
                if (!s00_axi_rvalid) begin
                    fail_test("axi_read_rready_stall: RVALID dropped during stall.");
                end
                if (s00_axi_rdata != captured_rdata) begin
                    fail_test("axi_read_rready_stall: RDATA changed during stall.");
                end
                if (s00_axi_arready) begin
                    fail_test("axi_read_rready_stall: ARREADY asserted while response pending.");
                end
                @(posedge s00_axi_aclk);
            end

            if (s00_axi_rresp != 2'b00) begin
                fail_test("axi_read_rready_stall: RRESP != OKAY.");
            end

            s00_axi_rready = 1;
            @(posedge s00_axi_aclk);
            s00_axi_rready = 0;

            rdata = captured_rdata;

            // Wait for RVALID to clear
            timeout = 1000;
            while (s00_axi_rvalid && timeout > 0) begin
                @(posedge s00_axi_aclk);
                timeout = timeout - 1;
            end
        end
    endtask

endmodule
