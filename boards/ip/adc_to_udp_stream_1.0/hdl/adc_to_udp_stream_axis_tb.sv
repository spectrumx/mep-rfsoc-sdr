///////////////////////////////////////////////////////////////////////////////
// adc_to_udp_stream_axis_tb.sv
//
// Self-checking AXIS-focused scaffold for adc_to_udp_stream_v1_0.
// This testbench is separate from check_udp_packet_tb.sv so the original
// packet-byte checker can remain the manual golden steady-state regression.
///////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

module adc_to_udp_stream_axis_tb;

    parameter integer C_S00_AXI_DATA_WIDTH = 32;
    parameter integer C_S00_AXI_ADDR_WIDTH = 7;
    parameter integer C_S01_AXIS_TDATA_WIDTH = 64;
    parameter integer C_M00_AXIS_TDATA_WIDTH = 64;
    parameter integer C_M00_AXIS_TKEEP_WIDTH = 8;
    parameter integer UDP_PORT = 60133;

    localparam integer NUM_INPUT_BEATS = 4096 + 50;
    localparam integer WORDS_PER_PACKET = 4096;
    localparam integer EXPECTED_PKT_BYTES = 8298;
    localparam integer EXPECTED_PAYLOAD_BYTES = 8192;
    localparam integer PAYLOAD_BYTE_OFFSET = 106;

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

    reg s01_axis_aclk;
    reg s01_axis_aresetn;
    reg s01_axis_tvalid;
    reg [C_S01_AXIS_TDATA_WIDTH-1:0] s01_axis_tdata;
    wire s01_axis_tready;

    reg m00_axis_aclk;
    reg m00_axis_aresetn;
    wire m00_axis_tvalid;
    wire [C_M00_AXIS_TDATA_WIDTH-1:0] m00_axis_tdata;
    wire [C_M00_AXIS_TKEEP_WIDTH-1:0] m00_axis_tkeep;
    wire m00_axis_tuser;
    wire m00_axis_tlast;
    reg m00_axis_tready;

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
        .pps_comp(1'b1)
    );

    initial begin
        s00_axi_aclk = 1'b0;
        forever #3.2ns s00_axi_aclk = ~s00_axi_aclk;
    end

    initial begin
        s01_axis_aclk = 1'b0;
        forever #13.02ns s01_axis_aclk = ~s01_axis_aclk;
    end

    initial begin
        m00_axis_aclk = 1'b0;
        forever #3.2ns m00_axis_aclk = ~m00_axis_aclk;
    end

    initial begin
        s00_axi_aresetn = 1'b0;
        s01_axis_aresetn = 1'b0;
        m00_axis_aresetn = 1'b0;
        #20ns;
        s00_axi_aresetn = 1'b1;
        m00_axis_aresetn = 1'b1;
        s01_axis_aresetn = 1'b1;
    end

    reg [63:0] tdata_collected [0:2047];
    reg [7:0] tkeep_collected [0:2047];
    reg [7:0] pkt_byte_stream [0:16383];
    integer beat_count;
    integer pkt_byte_count;
    integer packet_index;
    integer drive_sample_count;
    integer accepted_s01_beats;
    integer completed_m00_beats;
    integer verified_packets;
    integer protocol_failures;
    integer byte_check_failures;
    integer input_done;
    integer test_done;
    integer m00_stall_cycles_remaining;
    integer header_stall_done;
    integer radio_stall_done;
    integer payload_stall_done;
    integer final_stall_done;

    reg prev_m00_tvalid;
    reg prev_m00_tready;
    reg [63:0] prev_m00_tdata;
    reg [7:0] prev_m00_tkeep;
    reg prev_m00_tlast;
    reg prev_m00_tuser;

    initial begin
        s00_axi_awaddr = {C_S00_AXI_ADDR_WIDTH{1'b0}};
        s00_axi_awprot = 3'h0;
        s00_axi_awvalid = 1'b0;
        s00_axi_wdata = {C_S00_AXI_DATA_WIDTH{1'b0}};
        s00_axi_wstrb = {(C_S00_AXI_DATA_WIDTH/8){1'b0}};
        s00_axi_wvalid = 1'b0;
        s00_axi_bready = 1'b1;
        s00_axi_araddr = {C_S00_AXI_ADDR_WIDTH{1'b0}};
        s00_axi_arprot = 3'h0;
        s00_axi_arvalid = 1'b0;
        s00_axi_rready = 1'b1;
        s01_axis_tvalid = 1'b0;
        s01_axis_tdata = {C_S01_AXIS_TDATA_WIDTH{1'b0}};
        m00_axis_tready = 1'b1;
        drive_sample_count = 0;
        accepted_s01_beats = 0;
        input_done = 0;
        test_done = 0;
    end

    // S00 AXI-Lite setup: match check_udp_packet_tb.sv (run in parallel with S01 driver)
    initial begin
        #100ns;
        s00_axi_awaddr  = 7'h00;
        s00_axi_wdata   = 32'h0;
        s00_axi_wstrb   = 4'hF;
        s00_axi_awvalid = 1'b1;
        s00_axi_wvalid  = 1'b1;
        @(posedge s00_axi_aclk);
        @(posedge s00_axi_aclk);
        s00_axi_awvalid = 1'b0;
        s00_axi_wvalid  = 1'b0;
    end

    // S01 driver: match check_udp_packet_tb.sv timing and data pattern
    initial begin
        s01_axis_tvalid = 1'b0;
        s01_axis_tdata  = 64'h0;
        @(posedge m00_axis_aresetn);
        #100ns;
        drive_sample_count = 0;
        drive_s01_continuous_v2(NUM_INPUT_BEATS);
        input_done = 1;
    end

    initial begin
        #500us;
        if (!test_done) begin
            $display("FAIL: AXIS scaffold timeout: verified_packets=%0d protocol_failures=%0d byte_check_failures=%0d",
                     verified_packets, protocol_failures, byte_check_failures);
            $finish;
        end
    end

    task automatic axi_write;
        input [C_S00_AXI_ADDR_WIDTH-1:0] addr;
        input [31:0] data;
        input [3:0] strb;
        begin
            @(posedge s00_axi_aclk);
            s00_axi_awaddr = addr;
            s00_axi_awvalid = 1'b1;
            s00_axi_wdata = data;
            s00_axi_wstrb = strb;
            s00_axi_wvalid = 1'b1;
            s00_axi_bready = 1'b1;

            while (s00_axi_awvalid || s00_axi_wvalid) begin
                @(posedge s00_axi_aclk);
                if (s00_axi_awvalid && s00_axi_awready) begin
                    s00_axi_awvalid = 1'b0;
                end
                if (s00_axi_wvalid && s00_axi_wready) begin
                    s00_axi_wvalid = 1'b0;
                end
            end

            while (!s00_axi_bvalid) begin
                @(posedge s00_axi_aclk);
            end
            @(posedge s00_axi_aclk);
            s00_axi_bready = 1'b0;
        end
    endtask

    task automatic next_s01_word;
        output [63:0] word;
        reg [15:0] s1;
        reg [15:0] s2;
        reg [15:0] s3;
        reg [15:0] s4;
        begin
            s1 = drive_sample_count[15:0];
            s2 = drive_sample_count[15:0] + 16'd1;
            s3 = drive_sample_count[15:0] + 16'd2;
            s4 = drive_sample_count[15:0] + 16'd3;
            word = {s4, s3, s2, s1};
            drive_sample_count = drive_sample_count + 4;
        end
    endtask

    task automatic drive_s01_continuous;
        input integer beats;
        integer sent;
        reg [63:0] word;
        begin
            sent = 0;
            next_s01_word(word);
            s01_axis_tdata = word;
            s01_axis_tvalid = 1'b1;
            while (sent < beats) begin
                @(posedge s01_axis_aclk);
                if (s01_axis_tready) begin
                    accepted_s01_beats = accepted_s01_beats + 1;
                    sent = sent + 1;
                    if (sent < beats) begin
                        next_s01_word(word);
                        s01_axis_tdata = word;
                    end
                end
            end
            s01_axis_tvalid = 1'b0;
        end
    endtask

    task automatic drive_s01_continuous_v2;
        // Matches check_udp_packet_tb.sv data driving exactly.
        input integer beats;
        integer i;
        reg [15:0] s1;
        reg [15:0] s2;
        reg [15:0] s3;
        reg [15:0] s4;
        begin
            for (i = 0; i < beats; i = i + 1) begin
                @(posedge s01_axis_aclk);
                s1 = drive_sample_count[15:0];
                s2 = drive_sample_count[15:0] + 16'd1;
                s3 = drive_sample_count[15:0] + 16'd2;
                s4 = drive_sample_count[15:0] + 16'd3;
                s01_axis_tdata = {s4, s3, s2, s1};
                s01_axis_tvalid = 1'b1;
                if (s01_axis_tready) begin
                    accepted_s01_beats = accepted_s01_beats + 1;
                    drive_sample_count = drive_sample_count + 4;
                end
            end
            @(posedge s01_axis_aclk);
            s01_axis_tvalid = 1'b0;
        end
    endtask

    task automatic drive_s01_with_bubbles;
        input integer beats;
        input integer bubble_period;
        input integer bubble_cycles;
        integer sent;
        integer gap;
        reg [63:0] word;
        begin
            sent = 0;
            while (sent < beats) begin
                if ((bubble_period > 0) && (sent > 0) && ((sent % bubble_period) == 0)) begin
                    s01_axis_tvalid = 1'b0;
                    for (gap = 0; gap < bubble_cycles; gap = gap + 1) begin
                        @(posedge s01_axis_aclk);
                    end
                end
                next_s01_word(word);
                drive_s01_hold_until_ready(word);
                sent = sent + 1;
            end
        end
    endtask

    task automatic drive_s01_hold_until_ready;
        input [63:0] word;
        begin
            s01_axis_tdata = word;
            s01_axis_tvalid = 1'b1;
            do begin
                @(posedge s01_axis_aclk);
            end while (!s01_axis_tready);
            accepted_s01_beats = accepted_s01_beats + 1;
            s01_axis_tvalid = 1'b0;
        end
    endtask

    initial begin
        beat_count = 0;
        pkt_byte_count = 0;
        packet_index = 0;
        completed_m00_beats = 0;
        verified_packets = 0;
        protocol_failures = 0;
        byte_check_failures = 0;
        prev_m00_tvalid = 1'b0;
        prev_m00_tready = 1'b0;
        prev_m00_tdata = 64'h0;
        prev_m00_tkeep = 8'h0;
        prev_m00_tlast = 1'b0;
        prev_m00_tuser = 1'b0;
        m00_stall_cycles_remaining = 0;
        header_stall_done = 0;
        radio_stall_done = 0;
        payload_stall_done = 0;
        final_stall_done = 0;
    end

    always @(posedge m00_axis_aclk or negedge m00_axis_aresetn) begin
        if (!m00_axis_aresetn) begin
            m00_axis_tready <= 1'b1;
            m00_stall_cycles_remaining <= 0;
            header_stall_done <= 0;
            radio_stall_done <= 0;
            payload_stall_done <= 0;
            final_stall_done <= 0;
        end else if (m00_stall_cycles_remaining > 0) begin
            m00_stall_cycles_remaining <= m00_stall_cycles_remaining - 1;
            if (m00_stall_cycles_remaining == 1) begin
                m00_axis_tready <= 1'b1;
            end
        end else begin
            m00_axis_tready <= 1'b1;
            if (!header_stall_done && (packet_index == 1) && (beat_count == 2)) begin
                header_stall_done <= 1;
                start_m00_stall("Ethernet/IP/UDP header", 4);
            end else if (!radio_stall_done && (packet_index == 1) && (beat_count == 8)) begin
                radio_stall_done <= 1;
                start_m00_stall("radio header", 4);
            end else if (!payload_stall_done && (packet_index == 2) && (beat_count == 20)) begin
                payload_stall_done <= 1;
                start_m00_stall("payload", 5);
            end else if (!final_stall_done && (packet_index == 2) && (beat_count == 1037)) begin
                final_stall_done <= 1;
                start_m00_stall("final transfer", 4);
            end
        end
    end

    task automatic start_m00_stall;
        input [8*32-1:0] label;
        input integer cycles;
        begin
            m00_axis_tready <= 1'b0;
            m00_stall_cycles_remaining <= cycles;
            $display("[AXIS] Starting M00 TREADY stall at packet=%0d beat=%0d location=%0s cycles=%0d time=%0t",
                     packet_index, beat_count, label, cycles, $time);
        end
    endtask

    always @(posedge m00_axis_aclk) begin
        if (!m00_axis_aresetn) begin
            beat_count <= 0;
            pkt_byte_count <= 0;
            packet_index <= 0;
            completed_m00_beats <= 0;
            prev_m00_tvalid <= 1'b0;
            prev_m00_tready <= 1'b0;
            prev_m00_tdata <= 64'h0;
            prev_m00_tkeep <= 8'h0;
            prev_m00_tlast <= 1'b0;
            prev_m00_tuser <= 1'b0;
        end else begin
            check_m00_stability();

            if (m00_axis_tvalid && m00_axis_tready) begin
                completed_m00_beats = completed_m00_beats + 1;
                tdata_collected[beat_count] = m00_axis_tdata;
                tkeep_collected[beat_count] = m00_axis_tkeep;

                if (m00_axis_tuser !== 1'b0) begin
                    protocol_failures = protocol_failures + 1;
                    $display("FAIL: M00 TUSER asserted at time %0t", $time);
                end
                if (m00_axis_tlast && (m00_axis_tkeep !== 8'h03)) begin
                    protocol_failures = protocol_failures + 1;
                    $display("FAIL: final M00 TKEEP expected 0x03, got 0x%02x at packet %0d",
                             m00_axis_tkeep, packet_index);
                end
                if (!m00_axis_tlast && (m00_axis_tkeep !== 8'hFF)) begin
                    protocol_failures = protocol_failures + 1;
                    $display("FAIL: non-final M00 TKEEP expected 0xff, got 0x%02x at packet %0d beat %0d",
                             m00_axis_tkeep, packet_index, beat_count);
                end

                if (m00_axis_tlast) begin
                    reconstruct_packet_bytes(beat_count);
                    if ((packet_index >= 1) && (packet_index <= 3)) begin
                        verify_payload_packet(packet_index);
                    end
                    packet_index = packet_index + 1;
                    beat_count <= 0;
                end else begin
                    beat_count <= beat_count + 1;
                end
            end

            prev_m00_tvalid <= m00_axis_tvalid;
            prev_m00_tready <= m00_axis_tready;
            prev_m00_tdata <= m00_axis_tdata;
            prev_m00_tkeep <= m00_axis_tkeep;
            prev_m00_tlast <= m00_axis_tlast;
            prev_m00_tuser <= m00_axis_tuser;
        end
    end

    task automatic check_m00_stability;
        begin
            if (prev_m00_tvalid && !prev_m00_tready) begin
                if ((m00_axis_tvalid !== prev_m00_tvalid) ||
                    (m00_axis_tdata !== prev_m00_tdata) ||
                    (m00_axis_tkeep !== prev_m00_tkeep) ||
                    (m00_axis_tlast !== prev_m00_tlast) ||
                    (m00_axis_tuser !== prev_m00_tuser)) begin
                    protocol_failures = protocol_failures + 1;
                    $display("FAIL: M00 changed while stalled at time %0t", $time);
                    $display("      prev valid=%0b data=0x%016x keep=0x%02x last=%0b user=%0b",
                             prev_m00_tvalid, prev_m00_tdata, prev_m00_tkeep,
                             prev_m00_tlast, prev_m00_tuser);
                    $display("      curr valid=%0b data=0x%016x keep=0x%02x last=%0b user=%0b",
                             m00_axis_tvalid, m00_axis_tdata, m00_axis_tkeep,
                             m00_axis_tlast, m00_axis_tuser);
                end
            end
        end
    endtask

    task automatic reconstruct_packet_bytes;
        input integer last_beat;
        integer b;
        integer lane;
        reg [7:0] cur_tkeep;
        reg [63:0] cur_tdata;
        begin
            pkt_byte_count = 0;
            for (b = 0; b <= last_beat; b = b + 1) begin
                cur_tkeep = tkeep_collected[b];
                cur_tdata = tdata_collected[b];
                for (lane = 0; lane < 8; lane = lane + 1) begin
                    if (cur_tkeep[lane]) begin
                        pkt_byte_stream[pkt_byte_count] = cur_tdata[lane*8 +: 8];
                        pkt_byte_count = pkt_byte_count + 1;
                    end
                end
            end
        end
    endtask

    task automatic verify_payload_packet;
        input integer pkt_num;
        integer b;
        integer fail_count;
        integer first_fail;
        reg [15:0] exp_word;
        reg [7:0] exp_byte;
        reg [7:0] act_byte;
        begin
            fail_count = 0;
            first_fail = -1;

            $display("[AXIS] ===== Packet %0d scaffold verification =====", pkt_num);
            $display("[AXIS] pkt_byte_count = %0d (expected = %0d)", pkt_byte_count, EXPECTED_PKT_BYTES);

            if (pkt_byte_count != EXPECTED_PKT_BYTES) begin
                fail_count = fail_count + 1;
                first_fail = -2;
            end

            for (b = 0; b < EXPECTED_PAYLOAD_BYTES; b = b + 1) begin
                exp_word = (pkt_num * WORDS_PER_PACKET) + 16'h004C + (b / 2);
                exp_byte = ((b % 2) == 0) ? exp_word[7:0] : exp_word[15:8];
                act_byte = pkt_byte_stream[PAYLOAD_BYTE_OFFSET + b];
                if (act_byte !== exp_byte) begin
                    fail_count = fail_count + 1;
                    if (first_fail == -1) begin
                        first_fail = b;
                    end
                end
            end

            if (fail_count == 0) begin
                $display("[AXIS] Packet %0d payload PASS", pkt_num);
            end else begin
                byte_check_failures = byte_check_failures + fail_count;
                if (first_fail >= 0) begin
                    exp_word = (pkt_num * WORDS_PER_PACKET) + 16'h004C + (first_fail / 2);
                    exp_byte = ((first_fail % 2) == 0) ? exp_word[7:0] : exp_word[15:8];
                    act_byte = pkt_byte_stream[PAYLOAD_BYTE_OFFSET + first_fail];
                    $display("FAIL: Packet %0d payload mismatches=%0d first_payload_byte=%0d expected=0x%02x actual=0x%02x",
                             pkt_num, fail_count, first_fail, exp_byte, act_byte);
                end else begin
                    $display("FAIL: Packet %0d byte count mismatch", pkt_num);
                end
            end

            verified_packets = verified_packets + 1;
            if (verified_packets == 3) begin
                finish_axis_test();
            end
        end
    endtask

    task automatic finish_axis_test;
        begin
            test_done = 1;
            if (!header_stall_done || !radio_stall_done || !payload_stall_done || !final_stall_done) begin
                protocol_failures = protocol_failures + 1;
                $display("FAIL: not all M00 stall scenarios executed: header=%0d radio=%0d payload=%0d final=%0d",
                         header_stall_done, radio_stall_done, payload_stall_done, final_stall_done);
            end
            $display("[AXIS] accepted_s01_beats=%0d completed_m00_beats=%0d verified_packets=%0d",
                     accepted_s01_beats, completed_m00_beats, verified_packets);
            $display("[AXIS] stall_done header=%0d radio=%0d payload=%0d final=%0d",
                     header_stall_done, radio_stall_done, payload_stall_done, final_stall_done);
            if ((protocol_failures == 0) && (byte_check_failures == 0)) begin
                $display("PASS: AXIS M00 characterization test passed (0 failures).");
            end else begin
                $display("FAIL: AXIS M00 characterization protocol_failures=%0d byte_check_failures=%0d",
                         protocol_failures, byte_check_failures);
            end
            $finish;
        end
    endtask

endmodule
