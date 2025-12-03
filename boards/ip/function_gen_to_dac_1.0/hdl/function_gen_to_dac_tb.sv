// function_gen_to_dac_tb.sv
`timescale 1ns/1ps

module function_gen_to_dac_tb;

    // Test parameters
    parameter C_S00_AXI_DATA_WIDTH = 32;
    parameter C_S00_AXI_ADDR_WIDTH = 7;
    parameter C_M00_AXIS_TDATA_WIDTH = 256;
    parameter C_M00_AXIS_TKEEP_WIDTH = 32;
    
    // Clock and reset signals
    reg s00_axi_aclk;
    reg s00_axi_aresetn;
    
    // AXI4-Lite write interface signals
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
    
    // AXI4-Lite read interface signals
    reg [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr;
    reg [2 : 0] s00_axi_arprot;
    reg s00_axi_arvalid;
    wire s00_axi_arready;
    wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata;
    wire [1 : 0] s00_axi_rresp;
    wire s00_axi_rvalid;
    reg s00_axi_rready;
    
    // AXIS master interface signals
    reg m00_axis_aclk;
    reg m00_axis_aresetn;
    wire m00_axis_tvalid;
    wire [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata;
    wire [C_M00_AXIS_TKEEP_WIDTH-1 : 0] m00_axis_tkeep;
    wire m00_axis_tuser;
    wire m00_axis_tlast;
    reg m00_axis_tready;
    
    // DUT instantiation
    function_gen_to_dac_1_0 uut (
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
        .m00_axis_tkeep(m00_axis_tkeep),
        .m00_axis_tuser(m00_axis_tuser),
        .m00_axis_tlast(m00_axis_tlast),
        .m00_axis_tready(m00_axis_tready)
    );

    // Clock generation for AXI4-Lite (S00_AXI) (156.25MHz)
    initial begin
        s00_axi_aclk = 0;
        forever #3.2ns s00_axi_aclk = ~s00_axi_aclk;  // Toggle  every .32ns
    end

    // Clock generation for AXI4-Stream (M00_AXIS) (156.25 MHz)
    initial begin
        m00_axis_aclk = 0;
        forever #3.2ns m00_axis_aclk = ~m00_axis_aclk;  // Toggle 
    end

    // Reset generation
    initial begin
        s00_axi_aresetn = 0;
        m00_axis_aresetn = 0;
        #20;
        s00_axi_aresetn = 1;
        m00_axis_aresetn = 1;
    end
    
    // Test sequence
    initial begin
        // Initialize signals
        s00_axi_awaddr = 0;
        s00_axi_awprot = 0;
        s00_axi_wstrb = 0;
        s00_axi_bready = 0;

        s00_axi_wdata = 0;
        s00_axi_awvalid = 0;
        s00_axi_wvalid = 0;

        s00_axi_araddr = 0;
        s00_axi_arprot = 0;
        s00_axi_arvalid = 0;
        s00_axi_rready = 0;
        m00_axis_tready = 1;
        
        // Wait for reset
        #100;
        
        // Test register write operations
        $display("Starting register write tests...");
        
        // Test 1: Write waveform type register (0x0000_0000)
        $display("Test 1: Writing waveform type register");
        write_register(32'h0000_0000, 32'h00000001); // Sine wave
        #10;
        read_and_verify_register(32'h0000_0000, 32'h00000001);
        #10;
        
        // Test 2: Write frequency register (0x0000_0004)
        $display("Test 2: Writing frequency register");
        write_register(32'h0000_0004, 32'h00001234);
        #10;
        read_and_verify_register(32'h0000_0004, 32'h00001234);
        #10;
        
        // Test 3: Write amplitude register (0x0000_0008)
        $display("Test 3: Writing amplitude register");
        write_register(32'h0000_0008, 32'h00005678);
        #10;
        read_and_verify_register(32'h0000_0008, 32'h00005678);
        #10;
        
        // Test 4: Write phase register (0x0000_000C)
        $display("Test 4: Writing phase register");
        write_register(32'h0000_000C, 32'h00009ABC);
        #10;
        read_and_verify_register(32'h0000_000C, 32'h00009ABC);
        #10;
        
        // Test 5: Write offset register (0x0000_0010)
        $display("Test 5: Writing offset register");
        write_register(32'h0000_0010, 32'h0000DEFF);
        #10;
        read_and_verify_register(32'h0000_0010, 32'h0000DEFF);
        #10;
        
        // Test 6: Write enable register (0x0000_0014)
        $display("Test 6: Writing enable register");
        write_register(32'h0000_0014, 32'h00000001);
        #10;
        read_and_verify_register(32'h0000_0014, 32'h00000001);
        #10;
        
        // Test 7: Write multiple registers in sequence
        $display("Test 7: Writing multiple registers");
        write_register(32'h0000_0000, 32'h00000003); // Triangle wave
        write_register(32'h0000_0004, 32'h00005555); // Frequency
        write_register(32'h0000_0008, 32'h0000AAAA); // Amplitude
        #10;
        read_and_verify_register(32'h0000_0000, 32'h00000003);
        read_and_verify_register(32'h0000_0004, 32'h00005555);
        read_and_verify_register(32'h0000_0008, 32'h0000AAAA);
        #10;
        
        // Test 8: Write invalid address (should not affect anything)
        $display("Test 8: Writing to invalid register address");
        write_register(32'h0000_0018, 32'h12345678); // Invalid address
        #10;
        read_and_verify_register(32'h0000_0000, 32'h00000003); // Should remain unchanged
        #10;
        
        $display("All register write tests completed successfully!");
        $finish;
    end
    
    // Write register function
    task write_register;
        input [31:0] addr;
        input [31:0] data;
        begin
            s00_axi_awaddr = addr;
            s00_axi_awprot = 3'h0;  // Write address not protected
            s00_axi_awvalid = 1;
            
            // Wait for ready
            @(posedge s00_axi_aclk);
            while (!s00_axi_awready) @(posedge s00_axi_aclk); // Wait until ready
            s00_axi_wdata = data;
            s00_axi_wstrb = 8'hFF; // Write all bytes
            s00_axi_wvalid = 1;

            // Wait for WREADY
            @(posedge s00_axi_aclk);
            while (!s00_axi_wready) @(posedge s00_axi_aclk); // Wait until ready
            @(posedge s00_axi_aclk);
            s00_axi_wvalid = 1'b0;
            s00_axi_awvalid = 1'b0;
            s00_axi_wstrb = 1'b0;

            // Wait for BVALID and respond
            // bvalid is asserted on the clock edge after both awready and wready are asserted
            @(posedge s00_axi_aclk);
            while (!s00_axi_bvalid) @(posedge s00_axi_aclk);
            s00_axi_bready = 1'b1;
            @(posedge s00_axi_aclk);
            s00_axi_bready = 1'b0;
        end
    endtask
    
    // Read and verify register function
    task read_and_verify_register;
        input [31:0] addr;
        input [31:0] expected_data;
        begin
            // Set address and assert arvalid (set before clock edge to ensure setup time)
            @(negedge s00_axi_aclk);
            s00_axi_araddr = addr;
            s00_axi_arvalid = 1;
            
            // Wait for address to be accepted (both arvalid and arready high on posedge)
            @(posedge s00_axi_aclk);
            while (!(s00_axi_arready && s00_axi_arvalid)) @(posedge s00_axi_aclk);
            
            // Address accepted on this posedge, clear arvalid on next clock edge
            @(posedge s00_axi_aclk);
            s00_axi_arvalid = 0;
            
            // Wait for valid data
            while (!s00_axi_rvalid) @(posedge s00_axi_aclk);
            
            // Verify data
            if (s00_axi_rdata == expected_data) begin
                $display("  Register read successful: addr=0x%08h, data=0x%08h", addr, s00_axi_rdata);
            end else begin
                $display("  ERROR: Register read failed: addr=0x%08h, expected=0x%08h, got=0x%08h", 
                         addr, expected_data, s00_axi_rdata);
            end
            
            // Assert rready to accept data
            s00_axi_rready = 1;
            @(posedge s00_axi_aclk);
            s00_axi_rready = 0;
        end
    endtask
    
endmodule