
//--------------------------------------------------------------------------------------------------------
// Module  : top
// Type    : synthesizable, FPGA's top, IP's example design
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: an example of ddr_sdram_ctrl,
//           write increase data to DDR,
//           then read data and check whether they are increasing
//--------------------------------------------------------------------------------------------------------

module top (
    input  wire        clk50m,

    output wire        ddr_ck_p, ddr_ck_n,
    output wire        ddr_cke,
    output wire        ddr_cs_n, ddr_ras_n, ddr_cas_n, ddr_we_n,
    output wire [ 1:0] ddr_ba,
    output wire [12:0] ddr_a,
    inout       [ 7:0] ddr_dq,
    inout       [ 0:0] ddr_dqs,
    output wire [ 0:0] ddr_dm,
    
    output wire        error,
    output wire [15:0] error_cnt
);

// -------------------------------------------------------------------------------------
//   DDR-SDRAM parameters
// -------------------------------------------------------------------------------------
localparam  BA_BITS  = 2;
localparam  ROW_BITS = 13;
localparam  COL_BITS = 11;
localparam  DQ_LEVEL = 1;
localparam  DQ_BITS  = (4<<DQ_LEVEL);
localparam  DQS_BITS = ((1<<DQ_LEVEL)+1)/2;

// -------------------------------------------------------------------------------------
//   meta AXI4 parameters
// -------------------------------------------------------------------------------------
localparam  A_WIDTH = BA_BITS+ROW_BITS+COL_BITS+DQ_LEVEL-1;
localparam  D_WIDTH = (8<<DQ_LEVEL);

// -------------------------------------------------------------------------------------
//   driving clock and reset
// -------------------------------------------------------------------------------------
wire               clk300m;
wire               rstn;

// -------------------------------------------------------------------------------------
//   meta AXI4 interface
// -------------------------------------------------------------------------------------
wire               aresetn;
wire               aclk;
wire               awvalid;
wire               awready;
wire [A_WIDTH-1:0] awaddr;
wire [        7:0] awlen;
wire               wvalid;
wire               wready;
wire               wlast;
wire [D_WIDTH-1:0] wdata;
wire               bvalid;
wire               bready;
wire               arvalid;
wire               arready;
wire [A_WIDTH-1:0] araddr;
wire [        7:0] arlen;
wire               rvalid;
wire               rready;
wire               rlast;
wire [D_WIDTH-1:0] rdata;

// -------------------------------------------------------------------------------------
//   PLL for generating 300MHz clock
// -------------------------------------------------------------------------------------
pll pll_i(
    .inclk0      ( clk50m      ),
    .c0          ( clk300m     ),
    .locked      ( rstn        )
);

// -------------------------------------------------------------------------------------
//   meta AXI4 master for testing
// -------------------------------------------------------------------------------------
axi_self_test_master #(
    .A_WIDTH_TEST( A_WIDTH     ),
    .A_WIDTH     ( A_WIDTH     ),
    .D_WIDTH     ( D_WIDTH     ),
    .D_LEVEL     ( DQ_LEVEL    ),
    .WBURST_LEN  ( 8'd15       ),
    .RBURST_LEN  ( 8'd15       )
) axi_m_i (
    .aresetn     ( aresetn     ),
    .aclk        ( aclk        ),
    .awvalid     ( awvalid     ),
    .awready     ( awready     ),
    .awaddr      ( awaddr      ),
    .awlen       ( awlen       ),
    .wvalid      ( wvalid      ),
    .wready      ( wready      ),
    .wlast       ( wlast       ),
    .wdata       ( wdata       ),
    .bvalid      ( bvalid      ),
    .bready      ( bready      ),
    .arvalid     ( arvalid     ),
    .arready     ( arready     ),
    .araddr      ( araddr      ),
    .arlen       ( arlen       ),
    .rvalid      ( rvalid      ),
    .rready      ( rready      ),
    .rlast       ( rlast       ),
    .rdata       ( rdata       ),
    .error       ( error       ),
    .error_cnt   ( error_cnt   )
);

// -------------------------------------------------------------------------------------
//   DDR-SDRAM controller
// -------------------------------------------------------------------------------------
ddr_sdram_ctrl #(
    .READ_BUFFER ( 1           ),
    .BA_BITS     ( BA_BITS     ),
    .ROW_BITS    ( ROW_BITS    ),
    .COL_BITS    ( COL_BITS    ),
    .DQ_LEVEL    ( DQ_LEVEL    ),  // x8
    .tREFC       ( 10'd512     ),
    .tW2I        ( 8'd7        ),
    .tR2I        ( 8'd7        )
) ddr_ctrl_i(
    .rstn_async  ( rstn        ),
    .clk         ( clk300m     ),
    .aresetn     ( aresetn     ),
    .aclk        ( aclk        ),
    .awvalid     ( awvalid     ),
    .awready     ( awready     ),
    .awaddr      ( awaddr      ),
    .awlen       ( awlen       ),
    .wvalid      ( wvalid      ),
    .wready      ( wready      ),
    .wlast       ( wlast       ),
    .wdata       ( wdata       ),
    .bvalid      ( bvalid      ),
    .bready      ( bready      ),
    .arvalid     ( arvalid     ),
    .arready     ( arready     ),
    .araddr      ( araddr      ),
    .arlen       ( arlen       ),
    .rvalid      ( rvalid      ),
    .rready      ( rready      ),
    .rlast       ( rlast       ),
    .rdata       ( rdata       ),
    .ddr_ck_p    ( ddr_ck_p    ),
    .ddr_ck_n    ( ddr_ck_n    ),
    .ddr_cke     ( ddr_cke     ),
    .ddr_cs_n    ( ddr_cs_n    ),
    .ddr_ras_n   ( ddr_ras_n   ),
    .ddr_cas_n   ( ddr_cas_n   ),
    .ddr_we_n    ( ddr_we_n    ),
    .ddr_ba      ( ddr_ba      ),
    .ddr_a       ( ddr_a       ),
    .ddr_dq      ( ddr_dq      ),
    .ddr_dqs     ( ddr_dqs     ),
    .ddr_dm      ( ddr_dm      )
);

endmodule
