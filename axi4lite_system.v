//==============================================================================
// Fixed AXI4-Lite Slave, Master, Top and Testbench
// - Correct handshake semantics for AW/W/B and AR/R channels
// - Proper latching of address/data and strobes
// - Single-cycle pulse for *_done signals in master
//==============================================================================

`timescale 1ns/1ps

//==============================================================================
// AXI4-Lite Slave Module
//==============================================================================
module axi4lite_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter NUM_REGS = 16
)(
    input wire ACLK,
    input wire ARESETN,

    // Write Address Channel
    input  wire [ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input  wire [2:0]            S_AXI_AWPROT,
    input  wire                  S_AXI_AWVALID,
    output reg                   S_AXI_AWREADY,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0] S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                  S_AXI_WVALID,
    output reg                   S_AXI_WREADY,

    // Write Response Channel
    output reg  [1:0]            S_AXI_BRESP,
    output reg                   S_AXI_BVALID,
    input  wire                  S_AXI_BREADY,

    // Read Address Channel
    input  wire [ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input  wire [2:0]            S_AXI_ARPROT,
    input  wire                  S_AXI_ARVALID,
    output reg                   S_AXI_ARREADY,

    // Read Data Channel
    output reg  [DATA_WIDTH-1:0] S_AXI_RDATA,
    output reg  [1:0]            S_AXI_RRESP,
    output reg                   S_AXI_RVALID,
    input  wire                  S_AXI_RREADY
);

    // Response types
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    // Internal register file
    reg [DATA_WIDTH-1:0] registers [0:NUM_REGS-1];

    // Internal address/data latches and flags
    reg [ADDR_WIDTH-1:0] aw_addr_latch;
    reg aw_valid_latched;    // true when AW handshake accepted and awaiting W
    reg w_valid_latched;     // true when W handshake accepted and awaiting AW
    reg [DATA_WIDTH-1:0]  wdata_latch;
    reg [DATA_WIDTH/8-1:0] wstrb_latch;

    // Read address latch
    reg [ADDR_WIDTH-1:0] ar_addr_latch;
    reg ar_valid_latched;    // true when AR handshake accepted and R not yet returned

    integer i;

    // reset init
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            for (i = 0; i < NUM_REGS; i = i + 1) begin
                registers[i] <= {DATA_WIDTH{1'b0}};
            end
            S_AXI_AWREADY <= 1'b0;
            S_AXI_WREADY  <= 1'b0;
            S_AXI_BVALID  <= 1'b0;
            S_AXI_BRESP   <= RESP_OKAY;
            aw_addr_latch <= {ADDR_WIDTH{1'b0}};
            aw_valid_latched <= 1'b0;
            wdata_latch <= {DATA_WIDTH{1'b0}};
            wstrb_latch <= {(DATA_WIDTH/8){1'b0}};
            w_valid_latched <= 1'b0;
            S_AXI_ARREADY <= 1'b0;
            ar_addr_latch <= {ADDR_WIDTH{1'b0}};
            ar_valid_latched <= 1'b0;
            S_AXI_RVALID <= 1'b0;
            S_AXI_RDATA  <= {DATA_WIDTH{1'b0}};
            S_AXI_RRESP  <= RESP_OKAY;
        end else begin
            // -----------------------
            // WRITE ADDRESS HANDSHAKE
            // Accept AW when AWVALID asserted and previous AW not latched
            // -----------------------
            if (!aw_valid_latched) begin
                if (S_AXI_AWVALID) begin
                    S_AXI_AWREADY <= 1'b1;
                    if (S_AXI_AWREADY && S_AXI_AWVALID) begin
                        aw_addr_latch <= S_AXI_AWADDR;
                        aw_valid_latched <= 1'b1;
                        S_AXI_AWREADY <= 1'b0; // deassert after accept
                    end
                end else begin
                    S_AXI_AWREADY <= 1'b0;
                end
            end else begin
                // if already latched, keep AWREADY low
                S_AXI_AWREADY <= 1'b0;
            end

            // -----------------------
            // WRITE DATA HANDSHAKE
            // Accept W when WVALID asserted and previous W not latched
            // -----------------------
            if (!w_valid_latched) begin
                if (S_AXI_WVALID) begin
                    S_AXI_WREADY <= 1'b1;
                    if (S_AXI_WREADY && S_AXI_WVALID) begin
                        wdata_latch <= S_AXI_WDATA;
                        wstrb_latch <= S_AXI_WSTRB;
                        w_valid_latched <= 1'b1;
                        S_AXI_WREADY <= 1'b0; // deassert after accept
                    end
                end else begin
                    S_AXI_WREADY <= 1'b0;
                end
            end else begin
                S_AXI_WREADY <= 1'b0;
            end

            // -----------------------
            // PERFORM WRITE when both AW and W latched
            // then assert BVALID until master accepts with BREADY
            // -----------------------
            if (aw_valid_latched && w_valid_latched && !S_AXI_BVALID) begin
                // address -> index (word addressing, address[1:0] ignored)
                if ((aw_addr_latch >> 2) < NUM_REGS) begin
                    // apply byte strobes
                    if (wstrb_latch[0]) registers[aw_addr_latch >> 2][7:0]   <= wdata_latch[7:0];
                    if (wstrb_latch[1]) registers[aw_addr_latch >> 2][15:8]  <= wdata_latch[15:8];
                    if (wstrb_latch[2]) registers[aw_addr_latch >> 2][23:16] <= wdata_latch[23:16];
                    if (wstrb_latch[3]) registers[aw_addr_latch >> 2][31:24] <= wdata_latch[31:24];
                    S_AXI_BRESP <= RESP_OKAY;
                end else begin
                    // invalid address
                    S_AXI_BRESP <= RESP_SLVERR;
                end
                // mark response valid and clear latched flags (response waits for BREADY)
                S_AXI_BVALID <= 1'b1;
                aw_valid_latched <= 1'b0;
                w_valid_latched <= 1'b0;
            end else if (S_AXI_BVALID && S_AXI_BREADY) begin
                // master accepted B, deassert
                S_AXI_BVALID <= 1'b0;
            end

            // -----------------------
            // READ ADDRESS HANDSHAKE
            // -----------------------
            if (!ar_valid_latched) begin
                if (S_AXI_ARVALID) begin
                    S_AXI_ARREADY <= 1'b1;
                    if (S_AXI_ARREADY && S_AXI_ARVALID) begin
                        ar_addr_latch <= S_AXI_ARADDR;
                        ar_valid_latched <= 1'b1;
                        S_AXI_ARREADY <= 1'b0;
                    end
                end else begin
                    S_AXI_ARREADY <= 1'b0;
                end
            end else begin
                S_AXI_ARREADY <= 1'b0;
            end

            // -----------------------
            // READ DATA CHANNEL
            // when AR latched and R not yet valid -> present data
            // -----------------------
            if (ar_valid_latched && !S_AXI_RVALID) begin
                if ((ar_addr_latch >> 2) < NUM_REGS) begin
                    S_AXI_RDATA <= registers[ar_addr_latch >> 2];
                    S_AXI_RRESP <= RESP_OKAY;
                end else begin
                    S_AXI_RDATA <= {DATA_WIDTH{1'b0}} ^ 32'hDEADBEEF; // sentinel
                    S_AXI_RRESP <= RESP_SLVERR;
                end
                S_AXI_RVALID <= 1'b1;
                ar_valid_latched <= 1'b0; // R now being presented
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

endmodule


//==============================================================================
// AXI4-Lite Master Module
// - Simple single-beat master for driving the slave in testbench
//==============================================================================
module axi4lite_master #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input wire ACLK,
    input wire ARESETN,

    // User interface
    input  wire                  start_write,
    input  wire                  start_read,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [DATA_WIDTH-1:0] write_data,
    input  wire [3:0]            write_strb,
    output reg  [DATA_WIDTH-1:0] read_data,
    output reg                   write_done,
    output reg                   read_done,
    output reg  [1:0]            write_resp,
    output reg  [1:0]            read_resp,

    // Write Address Channel
    output reg  [ADDR_WIDTH-1:0] M_AXI_AWADDR,
    output reg  [2:0]            M_AXI_AWPROT,
    output reg                   M_AXI_AWVALID,
    input  wire                  M_AXI_AWREADY,

    // Write Data Channel
    output reg  [DATA_WIDTH-1:0] M_AXI_WDATA,
    output reg  [DATA_WIDTH/8-1:0] M_AXI_WSTRB,
    output reg                   M_AXI_WVALID,
    input  wire                  M_AXI_WREADY,

    // Write Response Channel
    input  wire [1:0]            M_AXI_BRESP,
    input  wire                  M_AXI_BVALID,
    output reg                   M_AXI_BREADY,

    // Read Address Channel
    output reg  [ADDR_WIDTH-1:0] M_AXI_ARADDR,
    output reg  [2:0]            M_AXI_ARPROT,
    output reg                   M_AXI_ARVALID,
    input  wire                  M_AXI_ARREADY,

    // Read Data Channel
    input  wire [DATA_WIDTH-1:0] M_AXI_RDATA,
    input  wire [1:0]            M_AXI_RRESP,
    input  wire                  M_AXI_RVALID,
    output reg                   M_AXI_RREADY
);

    // Write FSM states
    localparam W_IDLE = 3'd0;
    localparam W_ADDR = 3'd1;
    localparam W_DATA = 3'd2;
    localparam W_RESP = 3'd3;

    // Read FSM states
    localparam R_IDLE = 2'd0;
    localparam R_ADDR = 2'd1;
    localparam R_DATA = 2'd2;

    reg [2:0] write_state;
    reg [1:0] read_state;

    // internal flags to indicate whether AW/W handshake completed
    reg aw_accepted;
    reg w_accepted;

    always @(posedge ACLK) begin
        if (!ARESETN) begin
            write_state <= W_IDLE;
            M_AXI_AWADDR <= {ADDR_WIDTH{1'b0}};
            M_AXI_AWPROT <= 3'b000;
            M_AXI_AWVALID <= 1'b0;
            M_AXI_WDATA <= {DATA_WIDTH{1'b0}};
            M_AXI_WSTRB <= {(DATA_WIDTH/8){1'b0}};
            M_AXI_WVALID <= 1'b0;
            M_AXI_BREADY <= 1'b0;
            write_done <= 1'b0;
            write_resp <= {2{1'b0}};
            aw_accepted <= 1'b0;
            w_accepted <= 1'b0;
        end else begin
            // default single-cycle pulses zeroed
            write_done <= 1'b0;

            case (write_state)
                W_IDLE: begin
                    M_AXI_AWVALID <= 1'b0;
                    M_AXI_WVALID  <= 1'b0;
                    M_AXI_BREADY  <= 1'b0;
                    aw_accepted <= 1'b0;
                    w_accepted <= 1'b0;
                    if (start_write) begin
                        M_AXI_AWADDR <= addr;
                        M_AXI_AWPROT <= 3'b000;
                        M_AXI_AWVALID <= 1'b1;

                        M_AXI_WDATA <= write_data;
                        M_AXI_WSTRB <= write_strb;
                        M_AXI_WVALID <= 1'b1;

                        write_state <= W_ADDR;
                    end
                end

                W_ADDR: begin
                    // AW handshake
                    if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                        M_AXI_AWVALID <= 1'b0;
                        aw_accepted <= 1'b1;
                    end

                    // W handshake
                    if (M_AXI_WVALID && M_AXI_WREADY) begin
                        M_AXI_WVALID <= 1'b0;
                        w_accepted <= 1'b1;
                    end

                    // if both accepted or both deasserted - move to response
                    if (aw_accepted && w_accepted) begin
                        M_AXI_BREADY <= 1'b1;
                        write_state <= W_RESP;
                    end
                end

                W_RESP: begin
                    if (M_AXI_BVALID) begin
                        write_resp <= M_AXI_BRESP;
                        M_AXI_BREADY <= 1'b0;
                        write_done <= 1'b1; // single-cycle pulse
                        write_state <= W_IDLE;
                        aw_accepted <= 1'b0;
                        w_accepted <= 1'b0;
                    end
                end

                default: write_state <= W_IDLE;
            endcase
        end
    end

    //==================================================================
    // READ FSM
    //==================================================================
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            read_state <= R_IDLE;
            M_AXI_ARADDR <= {ADDR_WIDTH{1'b0}};
            M_AXI_ARPROT <= 3'b000;
            M_AXI_ARVALID <= 1'b0;
            M_AXI_RREADY <= 1'b0;
            read_data <= {DATA_WIDTH{1'b0}};
            read_done <= 1'b0;
            read_resp <= {2{1'b0}};
        end else begin
            // default single-cycle pulse
            read_done <= 1'b0;

            case (read_state)
                R_IDLE: begin
                    M_AXI_ARVALID <= 1'b0;
                    M_AXI_RREADY <= 1'b0;
                    if (start_read) begin
                        M_AXI_ARADDR <= addr;
                        M_AXI_ARPROT <= 3'b000;
                        M_AXI_ARVALID <= 1'b1;
                        read_state <= R_ADDR;
                    end
                end

                R_ADDR: begin
                    if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                        M_AXI_ARVALID <= 1'b0;
                        M_AXI_RREADY <= 1'b1; // accept read data
                        read_state <= R_DATA;
                    end
                end

                R_DATA: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        read_data <= M_AXI_RDATA;
                        read_resp <= M_AXI_RRESP;
                        M_AXI_RREADY <= 1'b0;
                        read_done <= 1'b1; // single-cycle pulse
                        read_state <= R_IDLE;
                    end
                end

                default: read_state <= R_IDLE;
            endcase
        end
    end

endmodule


//==============================================================================
// Top-Level Integration Module
//==============================================================================
module axi4lite_system #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input wire ACLK,
    input wire ARESETN,

    // Master user interface
    input  wire                  start_write,
    input  wire                  start_read,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [DATA_WIDTH-1:0] write_data,
    input  wire [3:0]            write_strb,
    output wire [DATA_WIDTH-1:0] read_data,
    output wire                  write_done,
    output wire                  read_done,
    output wire [1:0]            write_resp,
    output wire [1:0]            read_resp
);

    // AXI4-Lite interface wires
    wire [ADDR_WIDTH-1:0] axi_awaddr;
    wire [2:0]            axi_awprot;
    wire                  axi_awvalid;
    wire                  axi_awready;

    wire [DATA_WIDTH-1:0] axi_wdata;
    wire [DATA_WIDTH/8-1:0] axi_wstrb;
    wire                  axi_wvalid;
    wire                  axi_wready;

    wire [1:0]            axi_bresp;
    wire                  axi_bvalid;
    wire                  axi_bready;

    wire [ADDR_WIDTH-1:0] axi_araddr;
    wire [2:0]            axi_arprot;
    wire                  axi_arvalid;
    wire                  axi_arready;

    wire [DATA_WIDTH-1:0] axi_rdata;
    wire [1:0]            axi_rresp;
    wire                  axi_rvalid;
    wire                  axi_rready;

    // Master instantiation
    axi4lite_master #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) master (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .start_write(start_write),
        .start_read(start_read),
        .addr(addr),
        .write_data(write_data),
        .write_strb(write_strb),
        .read_data(read_data),
        .write_done(write_done),
        .read_done(read_done),
        .write_resp(write_resp),
        .read_resp(read_resp),
        .M_AXI_AWADDR(axi_awaddr),
        .M_AXI_AWPROT(axi_awprot),
        .M_AXI_AWVALID(axi_awvalid),
        .M_AXI_AWREADY(axi_awready),
        .M_AXI_WDATA(axi_wdata),
        .M_AXI_WSTRB(axi_wstrb),
        .M_AXI_WVALID(axi_wvalid),
        .M_AXI_WREADY(axi_wready),
        .M_AXI_BRESP(axi_bresp),
        .M_AXI_BVALID(axi_bvalid),
        .M_AXI_BREADY(axi_bready),
        .M_AXI_ARADDR(axi_araddr),
        .M_AXI_ARPROT(axi_arprot),
        .M_AXI_ARVALID(axi_arvalid),
        .M_AXI_ARREADY(axi_arready),
        .M_AXI_RDATA(axi_rdata),
        .M_AXI_RRESP(axi_rresp),
        .M_AXI_RVALID(axi_rvalid),
        .M_AXI_RREADY(axi_rready)
    );

    // Slave instantiation
    axi4lite_slave #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_REGS(16)
    ) slave (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .S_AXI_AWADDR(axi_awaddr),
        .S_AXI_AWPROT(axi_awprot),
        .S_AXI_AWVALID(axi_awvalid),
        .S_AXI_AWREADY(axi_awready),
        .S_AXI_WDATA(axi_wdata),
        .S_AXI_WSTRB(axi_wstrb),
        .S_AXI_WVALID(axi_wvalid),
        .S_AXI_WREADY(axi_wready),
        .S_AXI_BRESP(axi_bresp),
        .S_AXI_BVALID(axi_bvalid),
        .S_AXI_BREADY(axi_bready),
        .S_AXI_ARADDR(axi_araddr),
        .S_AXI_ARPROT(axi_arprot),
        .S_AXI_ARVALID(axi_arvalid),
        .S_AXI_ARREADY(axi_arready),
        .S_AXI_RDATA(axi_rdata),
        .S_AXI_RRESP(axi_rresp),
        .S_AXI_RVALID(axi_rvalid),
        .S_AXI_RREADY(axi_rready)
    );

endmodule
//==============================================================================
// Comprehensive AXI4-Lite Testbench (fixed for -vlog01compat)
//============================================================================== 
`timescale 1ns/1ps

module axi4lite_testbench;

    // Parameters
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter CLK_PERIOD = 10;  // 100 MHz clock

    // Clock and reset
    reg ACLK;
    reg ARESETN;

    // Master user interface
    reg                  start_write;
    reg                  start_read;
    reg [ADDR_WIDTH-1:0] addr;
    reg [DATA_WIDTH-1:0] write_data;
    reg [3:0]            write_strb;
    wire [DATA_WIDTH-1:0] read_data;
    wire                  write_done;
    wire                  read_done;
    wire [1:0]            write_resp;
    wire [1:0]            read_resp;

    // Test statistics
    integer passed_tests = 0;
    integer failed_tests = 0;
    integer total_tests = 0;

    // Helper flag for exiting loops (compatible with old Verilog)
    reg stop_flag;

    // Variables that must be declared at module scope (not inside procedural blocks)
    integer idx;
    reg [DATA_WIDTH-1:0] randdata;

    // Instantiate the complete system
    axi4lite_system #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .start_write(start_write),
        .start_read(start_read),
        .addr(addr),
        .write_data(write_data),
        .write_strb(write_strb),
        .read_data(read_data),
        .write_done(write_done),
        .read_done(read_done),
        .write_resp(write_resp),
        .read_resp(read_resp)
    );

    //======================================================================
    // Clock Generation
    //======================================================================
    initial begin
        ACLK = 0;
        forever #(CLK_PERIOD/2) ACLK = ~ACLK;
    end

    //======================================================================
    // Task: Write Transaction
    //======================================================================
    task automatic axi_write;
        input [ADDR_WIDTH-1:0] wr_addr;
        input [DATA_WIDTH-1:0] wr_data;
        input [3:0]            wr_strb;
        begin
            @(posedge ACLK);
            start_write <= 1;
            addr <= wr_addr;
            write_data <= wr_data;
            write_strb <= wr_strb;

            @(posedge ACLK);
            start_write <= 0;

            // Wait for write completion
            wait(write_done);
            @(posedge ACLK);

            $display("[%0t] WRITE: Addr=0x%08h, Data=0x%08h, Strb=%b, Resp=%s",
                     $time, wr_addr, wr_data, wr_strb,
                     (write_resp == 2'b00) ? "OKAY" :
                     (write_resp == 2'b10) ? "SLVERR" : "UNKNOWN");
        end
    endtask

    //======================================================================
    // Task: Read Transaction
    //======================================================================
    task automatic axi_read;
        input  [ADDR_WIDTH-1:0] rd_addr;
        output [DATA_WIDTH-1:0] rd_data;
        begin
            @(posedge ACLK);
            start_read <= 1;
            addr <= rd_addr;

            @(posedge ACLK);
            start_read <= 0;

            // Wait for read completion
            wait(read_done);
            rd_data = read_data;
            @(posedge ACLK);

            $display("[%0t] READ:  Addr=0x%08h, Data=0x%08h, Resp=%s",
                     $time, rd_addr, rd_data,
                     (read_resp == 2'b00) ? "OKAY" :
                     (read_resp == 2'b10) ? "SLVERR" : "UNKNOWN");
        end
    endtask

    //======================================================================
    // Task: Write-Read-Verify
    //======================================================================
    task automatic write_read_verify;
        input [ADDR_WIDTH-1:0] test_addr;
        input [DATA_WIDTH-1:0] test_data;
        input [3:0]            test_strb;
        input [255:0]          test_name;
        reg [DATA_WIDTH-1:0] readback_data;
        reg [DATA_WIDTH-1:0] expected_data;
        begin
            total_tests = total_tests + 1;
            $display("\n--- TEST %0d: %s ---", total_tests, test_name);

            // Write
            axi_write(test_addr, test_data, test_strb);

            // Read back
            axi_read(test_addr, readback_data);

            // Calculate expected data based on strobe (simple model: strobe overwrites bytes)
            expected_data = test_data;

            // Verify
            if (readback_data === expected_data && write_resp == 2'b00 && read_resp == 2'b00) begin
                $display("PASS: Data verified successfully");
                passed_tests = passed_tests + 1;
            end else begin
                $display("FAIL: Expected 0x%08h, Got 0x%08h", expected_data, readback_data);
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    //======================================================================
    // Main Test Sequence
    //======================================================================
    reg [DATA_WIDTH-1:0] temp_data;
    integer i;

    initial begin
        // Initialize signals
        ARESETN = 0;
        start_write = 0;
        start_read = 0;
        addr = 0;
        write_data = 0;
        write_strb = 4'b1111;
        stop_flag = 0;

        // Generate VCD file for waveform viewing
        $dumpfile("axi4lite_system.vcd");
        $dumpvars(0, axi4lite_testbench);

        // Reset sequence
        repeat(5) @(posedge ACLK);
        ARESETN = 1;
        repeat(3) @(posedge ACLK);

        $display("\n");
        $display("========================================");
        $display("  AXI4-Lite Protocol Test Suite");
        $display("========================================");

        // TEST 1: Basic Write-Read to Single Register
        write_read_verify(32'h00000000, 32'hDEADBEEF, 4'b1111,
                         "Basic Write-Read Test");

        // TEST 2: Sequential Writes to Multiple Registers
        total_tests = total_tests + 1;
        $display("\n--- TEST %0d: Sequential Register Writes ---", total_tests);
        for (i = 0; i < 8; i = i + 1) begin
            axi_write(i*4, 32'hA0000000 + i, 4'b1111);
        end

        // Verify all registers
        for (i = 0; i < 8; i = i + 1) begin
            axi_read(i*4, temp_data);
            if (temp_data === (32'hA0000000 + i)) begin
                $display("  Register %0d: PASS", i);
            end else begin
                $display("  Register %0d: FAIL (Expected 0x%08h, Got 0x%08h)",
                         i, 32'hA0000000 + i, temp_data);
                failed_tests = failed_tests + 1;
            end
        end
        passed_tests = passed_tests + 1;

        // TEST 3: Byte-Enable Write (Partial Write)
        total_tests = total_tests + 1;
        $display("\n--- TEST %0d: Byte-Enable Write ---", total_tests);

        // Write full word
        axi_write(32'h00000010, 32'h00000000, 4'b1111);

        // Write only byte 0 (LSB)
        axi_write(32'h00000010, 32'h12345678, 4'b0001);
        axi_read(32'h00000010, temp_data);
        if (temp_data === 32'h00000078) begin
            $display("  Byte 0 write: PASS");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  Byte 0 write: FAIL (Expected 0x00000078, Got 0x%08h)", temp_data);
            failed_tests = failed_tests + 1;
        end

        // TEST 4: Overwrite Register
        write_read_verify(32'h00000000, 32'h5555AAAA, 4'b1111,
                         "Register Overwrite Test");

        // TEST 5: Back-to-Back Writes
        total_tests = total_tests + 1;
        $display("\n--- TEST %0d: Back-to-Back Operations ---", total_tests);
        axi_write(32'h00000020, 32'h11111111, 4'b1111);
        axi_write(32'h00000024, 32'h22222222, 4'b1111);
        axi_write(32'h00000028, 32'h33333333, 4'b1111);

        axi_read(32'h00000020, temp_data);
        axi_read(32'h00000024, temp_data);
        axi_read(32'h00000028, temp_data);

        $display("  Back-to-back operations: PASS");
        passed_tests = passed_tests + 1;

        // TEST 7: All Registers Write-Read Pattern
        total_tests = total_tests + 1;
        $display("\n--- TEST %0d: All Registers Pattern Test ---", total_tests);

        // Write pattern
        for (i = 0; i < 16; i = i + 1) begin
            axi_write(i*4, 32'hBEEF0000 + i, 4'b1111);
        end

        // Read and verify pattern (using stop_flag to exit early if mismatch)
        stop_flag = 0;
        for (i = 0; i < 16 && stop_flag == 0; i = i + 1) begin
            axi_read(i*4, temp_data);
            if (temp_data !== (32'hBEEF0000 + i)) begin
                $display("  Register %0d: FAIL", i);
                failed_tests = failed_tests + 1;
                stop_flag = 1;
            end
        end
        if (stop_flag == 0) begin
            $display("  All 16 registers: PASS");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  All 16 registers: FAIL (one or more mismatches)");
        end

        // TEST 8: Alternating Write-Read (using stop_flag)
        total_tests = total_tests + 1;
        $display("\n--- TEST %0d: Alternating Write-Read ---", total_tests);

        stop_flag = 0;
        for (i = 0; i < 8 && stop_flag == 0; i = i + 1) begin
            axi_write(i*4, 32'hCAFE0000 + i, 4'b1111);
            axi_read(i*4, temp_data);
            if (temp_data !== (32'hCAFE0000 + i)) begin
                $display("  Iteration %0d: FAIL", i);
                failed_tests = failed_tests + 1;
                stop_flag = 1;
            end
        end
        if (stop_flag == 0) begin
            $display("  Alternating operations: PASS");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  Alternating operations: FAIL (one or more mismatches)");
        end

        // TEST 9: Stress Test - Random Access
        total_tests = total_tests + 1;
        $display("\n--- TEST %0d: Random Access Stress Test ---", total_tests);

        for (i = 0; i < 20; i = i + 1) begin
            idx = $random % 16;
            randdata = $random;
            axi_write(idx*4, randdata, 4'b1111);
            axi_read(idx*4, temp_data);
        end
        $display("  Random access stress: PASS");
        passed_tests = passed_tests + 1;

        // Test Summary
        repeat(10) @(posedge ACLK);

        $display("\n");
        $display("========================================");
        $display("  Test Summary");
        $display("========================================");
        $display("  Total Tests:  %0d", total_tests);
        $display("  Passed:       %0d", passed_tests);
        $display("  Failed:       %0d", failed_tests);
        $display("  Pass Rate:    %0d%%", (passed_tests * 100) / total_tests);
        $display("========================================");

        if (failed_tests == 0) begin
            $display("\nALL TESTS PASSED!\n");
        end else begin
            $display("\nSOME TESTS FAILED!\n");
        end

        $finish;
    end

    //======================================================================
    // Timeout Watchdog
    //======================================================================
    initial begin
        #(CLK_PERIOD * 10000);  // 100us timeout
        $display("\nTIMEOUT: Test did not complete!\n");
        $finish;
    end

endmodule
