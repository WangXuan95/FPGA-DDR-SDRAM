
//--------------------------------------------------------------------------------------------------------
// Module  : fpga_top
// Type    : synthesizable, FPGA's top, IP's example design
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: an example of ddr_sdram_ctrl,
//           use UART command to read/write DDR
//--------------------------------------------------------------------------------------------------------

module fpga_top (
    input  wire        clk50m,
    
    output wire        uart_tx,
    input  wire        uart_rx,
    
    output wire        ddr_ck_p, ddr_ck_n,
    output wire        ddr_cke,
    output wire        ddr_cs_n, ddr_ras_n, ddr_cas_n, ddr_we_n,
    output wire [ 1:0] ddr_ba,
    output wire [12:0] ddr_a,
    output wire [ 0:0] ddr_dm,
    inout       [ 0:0] ddr_dqs,
    inout       [ 7:0] ddr_dq
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
//   AXI4 parameters
// -------------------------------------------------------------------------------------
localparam  A_WIDTH = BA_BITS+ROW_BITS+COL_BITS+DQ_LEVEL-1;
localparam  D_WIDTH = (8<<DQ_LEVEL);

// -------------------------------------------------------------------------------------
//   driving clock and reset
// -------------------------------------------------------------------------------------
wire               clk300m;
wire               locked;

// -------------------------------------------------------------------------------------
//   AXI4 interface
// -------------------------------------------------------------------------------------
wire               rstn;
wire               clk;
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
wire [3:0] subwire0;
altpll  altpll_i(  .inclk ( {1'b0, clk50m} ),  .clk ( {subwire0, clk300m} ),  .locked ( locked ),  .activeclock (),  .areset (1'b0),  .clkbad (),  .clkena ({6{1'b1}}),  .clkloss (),  .clkswitch (1'b0),  .configupdate (1'b0),  .enable0 (),  .enable1 (),  .extclk (),  .extclkena ({4{1'b1}}),  .fbin (1'b1),  .fbmimicbidir (),  .fbout (),  .fref (),  .icdrclk (),  .pfdena (1'b1),  .phasecounterselect ({4{1'b1}}),  .phasedone (),  .phasestep (1'b1),  .phaseupdown (1'b1),  .pllena (1'b1),  .scanaclr (1'b0),  .scanclk (1'b0),  .scanclkena (1'b1),  .scandata (1'b0),  .scandataout (),  .scandone (),  .scanread (1'b0),  .scanwrite (1'b0),  .sclkout0 (),  .sclkout1 (),  .vcooverrange (),  .vcounderrange ());
defparam  altpll_i.bandwidth_type = "AUTO",  altpll_i.clk0_divide_by = 1,  altpll_i.clk0_duty_cycle = 50,  altpll_i.clk0_multiply_by = 6,  altpll_i.clk0_phase_shift = "0",  altpll_i.compensate_clock = "CLK0",  altpll_i.inclk0_input_frequency = 20000,  altpll_i.intended_device_family = "Cyclone IV E",  altpll_i.lpm_hint = "CBX_MODULE_PREFIX=pll",  altpll_i.lpm_type = "altpll",  altpll_i.operation_mode = "NORMAL",  altpll_i.pll_type = "AUTO",  altpll_i.port_activeclock = "PORT_UNUSED",  altpll_i.port_areset = "PORT_UNUSED",  altpll_i.port_clkbad0 = "PORT_UNUSED",  altpll_i.port_clkbad1 = "PORT_UNUSED",  altpll_i.port_clkloss = "PORT_UNUSED",  altpll_i.port_clkswitch = "PORT_UNUSED",  altpll_i.port_configupdate = "PORT_UNUSED",  altpll_i.port_fbin = "PORT_UNUSED",  altpll_i.port_inclk0 = "PORT_USED",  altpll_i.port_inclk1 = "PORT_UNUSED",  altpll_i.port_locked = "PORT_USED",  altpll_i.port_pfdena = "PORT_UNUSED",  altpll_i.port_phasecounterselect = "PORT_UNUSED",  altpll_i.port_phasedone = "PORT_UNUSED",  altpll_i.port_phasestep = "PORT_UNUSED",  altpll_i.port_phaseupdown = "PORT_UNUSED",  altpll_i.port_pllena = "PORT_UNUSED",  altpll_i.port_scanaclr = "PORT_UNUSED",  altpll_i.port_scanclk = "PORT_UNUSED",  altpll_i.port_scanclkena = "PORT_UNUSED",  altpll_i.port_scandata = "PORT_UNUSED",  altpll_i.port_scandataout = "PORT_UNUSED",  altpll_i.port_scandone = "PORT_UNUSED",  altpll_i.port_scanread = "PORT_UNUSED",  altpll_i.port_scanwrite = "PORT_UNUSED",  altpll_i.port_clk0 = "PORT_USED",  altpll_i.port_clk1 = "PORT_UNUSED",  altpll_i.port_clk2 = "PORT_UNUSED",  altpll_i.port_clk3 = "PORT_UNUSED",  altpll_i.port_clk4 = "PORT_UNUSED",  altpll_i.port_clk5 = "PORT_UNUSED",  altpll_i.port_clkena0 = "PORT_UNUSED",  altpll_i.port_clkena1 = "PORT_UNUSED",  altpll_i.port_clkena2 = "PORT_UNUSED",  altpll_i.port_clkena3 = "PORT_UNUSED",  altpll_i.port_clkena4 = "PORT_UNUSED",  altpll_i.port_clkena5 = "PORT_UNUSED",  altpll_i.port_extclk0 = "PORT_UNUSED",  altpll_i.port_extclk1 = "PORT_UNUSED",  altpll_i.port_extclk2 = "PORT_UNUSED",  altpll_i.port_extclk3 = "PORT_UNUSED",  altpll_i.self_reset_on_loss_lock = "OFF",  altpll_i.width_clock = 5;


// -------------------------------------------------------------------------------------
//   AXI4 master for testing
// -------------------------------------------------------------------------------------
uart2axi4 #(
    .CLK_FREQ    ( 75000000    ),        // clk is 75MHz
    .BAUD_RATE   ( 115200      ),        // UART baud rate = 115200
    .PARITY      ( "NONE"      ),        // no parity
    .BYTE_WIDTH  ( D_WIDTH / 8 ),
    .A_WIDTH     ( A_WIDTH     )
) u_uart2axi4 (
    .rstn        ( rstn        ),
    .clk         ( clk         ),
    // AXI4 master ----------------------
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
    // UART ----------------------
    .i_uart_rx   ( uart_rx     ),
    .o_uart_tx   ( uart_tx     )
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
) u_ddr_ctrl (
    .rstn_async  ( locked      ),
    .drv_clk     ( clk300m     ),
    .rstn        ( rstn        ),
    .clk         ( clk         ),
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
