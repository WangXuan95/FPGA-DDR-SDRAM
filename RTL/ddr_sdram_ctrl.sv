
//--------------------------------------------------------------------------------------------------------
// Module  : ddr_sdram_ctrl
// Type    : synthesizable, IP's top
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: DDR-SDRAM (DDR1) controller
//           with AXI4 interface
//--------------------------------------------------------------------------------------------------------

module ddr_sdram_ctrl #(
    parameter   READ_BUFFER   = 1,
    parameter       BA_BITS   = 2,
    parameter       ROW_BITS  = 13,
    parameter       COL_BITS  = 11,
    parameter       DQ_LEVEL  = 1,  // DDR DQ_BITS = 4<<DQ_LEVEL, AXI4 DATA WIDTH = 8<<DQ_LEVEL, for example:
                                    // DQ_LEVEL = 0: DQ_BITS = 4  (x4)  , AXI DATA WIDTH = 8
                                    // DQ_LEVEL = 1: DQ_BITS = 8  (x8)  , AXI DATA WIDTH = 16    (default)
                                    // DQ_LEVEL = 2: DQ_BITS = 16 (x16) , AXI DATA WIDTH = 32
    parameter [9:0] tREFC     = 10'd256,
    parameter [7:0] tW2I      = 8'd7,
    parameter [7:0] tR2I      = 8'd7
) (
    // driving clock and reset
    input  wire                                           rstn_async,
    input  wire                                           clk,      // driving clock, typically 300~532MHz
    // user interface ( AXI4 )
    output reg                                            aresetn,
    output reg                                            aclk,     // freq = F(clk)/4
    input  wire                                           awvalid,
    output wire                                           awready,
    input  wire  [BA_BITS+ROW_BITS+COL_BITS+DQ_LEVEL-2:0] awaddr,   // byte address, not word address.
    input  wire                                    [ 7:0] awlen,
    input  wire                                           wvalid,
    output wire                                           wready,
    input  wire                                           wlast,
    input  wire                       [(8<<DQ_LEVEL)-1:0] wdata,
    output wire                                           bvalid,
    input  wire                                           bready,
    input  wire                                           arvalid,
    output wire                                           arready,
    input  wire  [BA_BITS+ROW_BITS+COL_BITS+DQ_LEVEL-2:0] araddr,   // byte address, not word address.
    input  wire                                    [ 7:0] arlen,
    output wire                                           rvalid,
    input  wire                                           rready,
    output wire                                           rlast,
    output wire                       [(8<<DQ_LEVEL)-1:0] rdata,
    // DDR-SDRAM interface
    output wire                                           ddr_ck_p, ddr_ck_n,  // freq = F(clk)/4
    output wire                                           ddr_cke,
    output reg                                            ddr_cs_n,
    output reg                                            ddr_ras_n,
    output reg                                            ddr_cas_n,
    output reg                                            ddr_we_n,
    output reg                  [            BA_BITS-1:0] ddr_ba,
    output reg                  [           ROW_BITS-1:0] ddr_a,
    output wire                 [((1<<DQ_LEVEL)+1)/2-1:0] ddr_dm,
    inout                       [((1<<DQ_LEVEL)+1)/2-1:0] ddr_dqs,
    inout                       [      (4<<DQ_LEVEL)-1:0] ddr_dq    
);

localparam DQS_BITS = ((1<<DQ_LEVEL)+1)/2;

reg        clk2 = '0;
reg        init_done = '0;
reg  [2:0] ref_idle = 3'd1, ref_real = '0;
reg  [9:0] ref_cnt = '0;
reg  [7:0] cnt = '0;
enum logic [3:0] {RESET, IDLE, CLEARDLL, REFRESH, WPRE, WRITE, WRESP, WWAIT, RPRE, READ, RRESP, RWAIT} stat = RESET;

reg  [7:0] burst_len = '0;
wire       burst_last = cnt==burst_len;
reg  [COL_BITS-2:0] col_addr = '0;

wire [ROW_BITS-1:0] ddr_a_col;
generate if(COL_BITS>10) begin
    assign ddr_a_col = {col_addr[COL_BITS-2:9], burst_last, col_addr[8:0], 1'b0};
end else begin
    assign ddr_a_col = {burst_last, col_addr[8:0], 1'b0};
end endgenerate

wire read_accessible, read_respdone;
reg  output_enable='0, output_enable_d1='0, output_enable_d2='0;

reg                      o_v_a = '0;
reg  [(4<<DQ_LEVEL)-1:0] o_dh_a = '0;
reg  [(4<<DQ_LEVEL)-1:0] o_dl_a = '0;
reg                      o_v_b = '0;
reg  [(4<<DQ_LEVEL)-1:0] o_dh_b = '0;
reg                      o_dqs_c = '0;
reg  [(4<<DQ_LEVEL)-1:0] o_d_c = '0;
reg  [(4<<DQ_LEVEL)-1:0] o_d_d = '0;

reg                      i_v_a = '0;
reg                      i_l_a = '0;
reg                      i_v_b = '0;
reg                      i_l_b = '0;
reg                      i_v_c = '0;
reg                      i_l_c = '0;
reg                      i_dqs_c = '0;
reg  [(4<<DQ_LEVEL)-1:0] i_d_c = '0;
reg                      i_v_d = '0;
reg                      i_l_d = '0;
reg  [(8<<DQ_LEVEL)-1:0] i_d_d = '0;
reg                      i_v_e = '0;
reg                      i_l_e = '0;
reg  [(8<<DQ_LEVEL)-1:0] i_d_e = '0;

// -------------------------------------------------------------------------------------
//   constants defination and assignment
// -------------------------------------------------------------------------------------
localparam [ROW_BITS-1:0] DDR_A_DEFAULT      = (ROW_BITS)'('b0100_0000_0000);
localparam [ROW_BITS-1:0] DDR_A_MR0          = (ROW_BITS)'('b0001_0010_1001);
localparam [ROW_BITS-1:0] DDR_A_MR_CLEAR_DLL = (ROW_BITS)'('b0000_0010_1001);


initial ddr_cs_n = 1'b1;
initial ddr_ras_n = 1'b1;
initial ddr_cas_n = 1'b1;
initial ddr_we_n = 1'b1;
initial ddr_ba = '0;
initial ddr_a = DDR_A_DEFAULT;

initial {aresetn, aclk} = '0;


// -------------------------------------------------------------------------------------
// generate reset sync with clk
// -------------------------------------------------------------------------------------
reg       rstn_clk   = '0;
reg [1:0] rstn_clk_l = '0;
always @ (posedge clk or negedge rstn_async)
    if(~rstn_async)
        {rstn_clk, rstn_clk_l} <= '0;
    else
        {rstn_clk, rstn_clk_l} <= {rstn_clk_l, 1'b1};

// -------------------------------------------------------------------------------------
// generate reset sync with aclk
// -------------------------------------------------------------------------------------
reg       rstn_aclk   = '0;
reg [1:0] rstn_aclk_l = '0;
always @ (posedge aclk or negedge rstn_async)
    if(~rstn_async)
        {rstn_aclk, rstn_aclk_l} <= '0;
    else
        {rstn_aclk, rstn_aclk_l} <= {rstn_aclk_l, 1'b1};

// -------------------------------------------------------------------------------------
//   generate clocks
// -------------------------------------------------------------------------------------
always @ (posedge clk or negedge rstn_clk)
    if(~rstn_clk)
        {aclk,clk2} <= 2'b00;
    else
        {aclk,clk2} <= {aclk,clk2} + 2'b01;

// -------------------------------------------------------------------------------------
//   generate user reset
// -------------------------------------------------------------------------------------
always @ (posedge aclk or negedge rstn_aclk)
    if(~rstn_aclk)
        aresetn <= 1'b0;
    else
        aresetn <= init_done;

// -------------------------------------------------------------------------------------
//   refresh wptr self increasement
// -------------------------------------------------------------------------------------
always @ (posedge aclk or negedge rstn_aclk)
    if(~rstn_aclk) begin
        ref_cnt <= '0;
        ref_idle <= 3'd1;
    end else begin
        if(init_done) begin
            if(ref_cnt<tREFC) begin
                ref_cnt <= ref_cnt + 10'd1;
            end else begin
                ref_cnt <= '0;
                ref_idle <= ref_idle + 3'd1;
            end
        end
    end

// -------------------------------------------------------------------------------------
//   generate DDR clock
// -------------------------------------------------------------------------------------
assign ddr_ck_p = ~aclk;
assign ddr_ck_n = aclk;
assign ddr_cke = ~ddr_cs_n;

// -------------------------------------------------------------------------------------
//   generate DDR DQ output behavior
// -------------------------------------------------------------------------------------
assign ddr_dm  = output_enable ? '0 : 'z;
assign ddr_dqs = output_enable ? {DQS_BITS{o_dqs_c}} : 'z;
assign ddr_dq  = output_enable ? o_d_d : 'z;

// -------------------------------------------------------------------------------------
//  assignment for user interface (meta AXI4 interface)
// -------------------------------------------------------------------------------------
assign awready = stat==IDLE && init_done && ref_real==ref_idle;
assign wready = stat==WRITE;
assign bvalid = stat==WRESP;
assign arready = stat==IDLE && init_done && ref_real==ref_idle && ~awvalid && read_accessible;

// -------------------------------------------------------------------------------------
//   main FSM for generating DDR-SDRAM behavior
// -------------------------------------------------------------------------------------
always @ (posedge aclk or negedge rstn_aclk)
    if(~rstn_aclk) begin
        ddr_cs_n <= 1'b1;
        ddr_ras_n <= 1'b1;
        ddr_cas_n <= 1'b1;
        ddr_we_n <= 1'b1;
        ddr_ba <= '0;
        ddr_a <= DDR_A_DEFAULT;
        col_addr <= '0;
        burst_len <= '0;
        init_done <= 1'b0;
        ref_real <= 3'd0;
        cnt <= 8'd0;
        stat <= RESET;
    end else begin
        case(stat)
            RESET: begin
                cnt <= cnt + 8'd1;
                if(cnt<8'd13) begin
                end else if(cnt<8'd50) begin
                    ddr_cs_n <= 1'b0;
                end else if(cnt<8'd51) begin
                    ddr_ras_n <= 1'b0;
                    ddr_we_n <= 1'b0;
                end else if(cnt<8'd53) begin
                    ddr_ras_n <= 1'b1;
                    ddr_we_n <= 1'b1;
                end else if(cnt<8'd54) begin
                    ddr_ras_n <= 1'b0;
                    ddr_cas_n <= 1'b0;
                    ddr_we_n <= 1'b0;
                    ddr_ba <= 'h1;
                    ddr_a <= '0;
                end else begin
                    ddr_ba <= '0;
                    ddr_a <= DDR_A_MR0;
                    stat <= IDLE;
                end
            end
            IDLE: begin
                ddr_ras_n <= 1'b1;
                ddr_cas_n <= 1'b1;
                ddr_we_n <= 1'b1;
                ddr_ba <= '0;
                ddr_a <= DDR_A_DEFAULT;
                cnt <= 8'd0;
                if(ref_real != ref_idle) begin
                    ref_real <= ref_real + 3'd1;
                    stat <= REFRESH;
                end else if(~init_done) begin
                    stat <= CLEARDLL;
                end else if(awvalid) begin
                    ddr_ras_n <= 1'b0;
                    {ddr_ba, ddr_a, col_addr} <= awaddr[BA_BITS+ROW_BITS+COL_BITS+DQ_LEVEL-2:DQ_LEVEL];
                    burst_len <= awlen;
                    stat <= WPRE;
                end else if(arvalid & read_accessible) begin
                    ddr_ras_n <= 1'b0;
                    {ddr_ba, ddr_a, col_addr} <= araddr[BA_BITS+ROW_BITS+COL_BITS+DQ_LEVEL-2:DQ_LEVEL];
                    burst_len <= arlen;
                    stat <= RPRE;
                end
            end
            CLEARDLL: begin
                ddr_ras_n <= cnt!=8'd0;
                ddr_cas_n <= cnt!=8'd0;
                ddr_we_n <= cnt!=8'd0;
                ddr_a <= cnt!=8'd0 ? DDR_A_DEFAULT : DDR_A_MR_CLEAR_DLL;
                cnt <= cnt + 8'd1;
                if(cnt==8'd255) begin
                    init_done <= 1'b1;
                    stat <= IDLE;
                end
            end
            REFRESH: begin
                cnt <= cnt + 8'd1;
                if(cnt<8'd1) begin
                    ddr_ras_n <= 1'b0;
                    ddr_we_n <= 1'b0;
                end else if(cnt<8'd3) begin
                    ddr_ras_n <= 1'b1;
                    ddr_we_n <= 1'b1;
                end else if(cnt<8'd4) begin
                    ddr_ras_n <= 1'b0;
                    ddr_cas_n <= 1'b0;
                end else if(cnt<8'd10) begin
                    ddr_ras_n <= 1'b1;
                    ddr_cas_n <= 1'b1;
                end else if(cnt<8'd11) begin
                    ddr_ras_n <= 1'b0;
                    ddr_cas_n <= 1'b0;
                end else if(cnt<8'd17) begin
                    ddr_ras_n <= 1'b1;
                    ddr_cas_n <= 1'b1;
                end else begin
                    stat <= IDLE;
                end
            end
            WPRE: begin
                ddr_ras_n <= 1'b1;
                cnt <= 8'd0;
                stat <= WRITE;
            end
            WRITE: begin
                ddr_a <= ddr_a_col;
                if(wvalid) begin
                    ddr_cas_n <= 1'b0;
                    ddr_we_n <= 1'b0;
                    col_addr <= col_addr + {{(COL_BITS-2){1'b0}}, 1'b1};
                    if(burst_last | wlast) begin
                        cnt <= '0;
                        stat <= WRESP;
                    end else begin
                        cnt <= cnt + 8'd1;
                    end
                end else begin
                    ddr_cas_n <= 1'b1;
                    ddr_we_n <= 1'b1;
                end
            end
            WRESP: begin
                ddr_cas_n <= 1'b1;
                ddr_we_n <= 1'b1;
                cnt <= cnt + 8'd1;
                if(bready)
                    stat <= WWAIT;
            end
            WWAIT: begin
                cnt <= cnt + 8'd1;
                if(cnt>=tW2I)
                    stat <= IDLE;
            end
            RPRE: begin
                ddr_ras_n <= 1'b1;
                cnt <= 8'd0;
                stat <= READ;
            end
            READ: begin
                ddr_cas_n <= 1'b0;
                ddr_a <= ddr_a_col;
                col_addr <= col_addr + {{(COL_BITS-2){1'b0}}, 1'b1};
                if(burst_last) begin
                    cnt <= '0;
                    stat <= RRESP;
                end else begin
                    cnt <= cnt + 8'd1;
                end
            end
            RRESP: begin 
                ddr_cas_n <= 1'b1;
                cnt <= cnt + 8'd1;
                if(read_respdone)
                    stat <= RWAIT;
            end
            RWAIT: begin
                cnt <= cnt + 8'd1;
                if(cnt>=tR2I)
                    stat <= IDLE;
            end
            default: stat <= IDLE;
        endcase
    end

// -------------------------------------------------------------------------------------
//   output enable generate
// -------------------------------------------------------------------------------------
always @ (posedge aclk or negedge aresetn)
    if(~aresetn) begin
        output_enable <= 1'b0;
        output_enable_d1 <= 1'b0;
        output_enable_d2 <= 1'b0;
    end else begin
        output_enable <= stat==WRITE || output_enable_d1 || output_enable_d2;
        output_enable_d1 <= stat==WRITE;
        output_enable_d2 <= output_enable_d1;
    end

// -------------------------------------------------------------------------------------
//   output data latches --- stage A
// -------------------------------------------------------------------------------------
always @ (posedge aclk or negedge aresetn)
    if(~aresetn) begin
        o_v_a <= 1'b0;
        {o_dh_a, o_dl_a} <= '0;
    end else begin
        o_v_a <= (stat==WRITE && wvalid);
        {o_dh_a, o_dl_a} <= wdata;
    end

// -------------------------------------------------------------------------------------
//   output data latches --- stage B
// -------------------------------------------------------------------------------------
always @ (posedge aclk or negedge aresetn)
    if(~aresetn) begin
        o_v_b <= 1'b0;
        o_dh_b <= '0;
    end else begin
        o_v_b <= o_v_a;
        o_dh_b <= o_dh_a;
    end

// -------------------------------------------------------------------------------------
//   dq and dqs generate for output (write)
// -------------------------------------------------------------------------------------
always @ (posedge clk2)
    if(~aclk) begin
        o_dqs_c <= 1'b0;
        o_d_c <= o_v_a ? o_dl_a : '0;
    end else begin
        o_dqs_c <= o_v_b;
        o_d_c <= o_v_b ? o_dh_b : '0;
    end

// -------------------------------------------------------------------------------------
//   dq delay for output (write)
// -------------------------------------------------------------------------------------
always @ (posedge clk)
    o_d_d <= o_d_c;

// -------------------------------------------------------------------------------------
//   dq sampling for input (read)
// -------------------------------------------------------------------------------------
always @ (posedge clk2) begin
    i_dqs_c <= ddr_dqs;
    i_d_c <= ddr_dq;
end

always @ (posedge clk2)
    if(i_dqs_c)
        i_d_d <= {ddr_dq, i_d_c};

always @ (posedge aclk or negedge aresetn)
    if(~aresetn) begin
        {i_v_a, i_v_b, i_v_c, i_v_d} <= '0;
        {i_l_a, i_l_b, i_l_c, i_l_d} <= '0;
    end else begin
        i_v_a <= stat==READ ? 1'b1 : 1'b0;
        i_l_a <= burst_last;
        i_v_b <= i_v_a;
        i_l_b <= i_l_a & i_v_a;
        i_v_c <= i_v_b;
        i_l_c <= i_l_b;
        i_v_d <= i_v_c;
        i_l_d <= i_l_c;
    end

always @ (posedge aclk or negedge aresetn)
    if(~aresetn) begin
        i_v_e <= 1'b0;
        i_l_e <= 1'b0;
        i_d_e <= '0;
    end else begin
        i_v_e <= i_v_d;
        i_l_e <= i_l_d;
        i_d_e <= i_d_d;
    end

// -------------------------------------------------------------------------------------
//   data buffer for read
// -------------------------------------------------------------------------------------
generate if(READ_BUFFER) begin

    localparam AWIDTH = 10;
    localparam DWIDTH = 1 + (8<<DQ_LEVEL);
    
    reg  [AWIDTH-1:0] wpt = '0, rpt = '0;
    reg               dvalid = '0, valid = '0;
    reg  [DWIDTH-1:0] datareg = '0;

    wire              rreq;
    reg  [DWIDTH-1:0] fifo_rdata;

    wire   emptyn  = rpt != wpt;

    wire   itready = rpt != (wpt + (AWIDTH)'(1));
    assign rvalid  = valid | dvalid;
    assign rreq    = emptyn & ( rready | ~rvalid );
    assign {rlast, rdata} = dvalid ? fifo_rdata : datareg;

    always @ (posedge aclk or negedge aresetn)
        if(~aresetn)
            wpt <= 0;
        else if(i_v_e & itready)
            wpt <= wpt + (AWIDTH)'(1);
        
    always @ (posedge aclk or negedge aresetn)
        if(~aresetn)
            rpt <= 0;
        else if(rreq & emptyn)
            rpt <= rpt + (AWIDTH)'(1);

    always @ (posedge aclk or negedge aresetn)
        if(~aresetn) begin
            dvalid <= 1'b0;
            valid  <= 1'b0;
            datareg <= 0;
        end else begin
            dvalid <= rreq;
            if(dvalid)
                datareg <= fifo_rdata;
            if(rready)
                valid <= 1'b0;
            else if(dvalid)
                valid <= 1'b1;
        end

    reg [DWIDTH-1:0] mem [(1<<AWIDTH)];

    always @ (posedge aclk)
        if(i_v_e)
            mem[wpt] <= {i_l_e, i_d_e};

    always @ (posedge aclk)
        fifo_rdata <= mem[rpt];
    
    assign read_accessible = ~rvalid;
    assign read_respdone = rvalid;
end else begin
    assign rvalid = i_v_e;
    assign rlast = i_l_e;
    assign rdata = i_d_e;
    assign read_accessible = 1'b1;
    assign read_respdone = i_l_e;
end endgenerate

endmodule
