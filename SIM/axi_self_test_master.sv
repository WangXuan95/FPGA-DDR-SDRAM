
//--------------------------------------------------------------------------------------------------------
// Module  : axi_self_test_master
// Type    : synthesizable
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: write increase data to AXI4 slave,
//           then read data and check whether they are increasing
//--------------------------------------------------------------------------------------------------------

module axi_self_test_master #(
    parameter       A_WIDTH_TEST = 26,
    parameter       A_WIDTH      = 26,
    parameter       D_WIDTH      = 16,
    parameter       D_LEVEL      = 1,
    parameter [7:0] WBURST_LEN   = 8'd7,
    parameter [7:0] RBURST_LEN   = 8'd7
)(
    input  wire               rstn,
    input  wire               clk,
    output wire               awvalid,
    input  wire               awready,
    output reg  [A_WIDTH-1:0] awaddr,
    output wire [        7:0] awlen,
    output wire               wvalid,
    input  wire               wready,
    output wire               wlast,
    output wire [D_WIDTH-1:0] wdata,
    input  wire               bvalid,
    output wire               bready,
    output wire               arvalid,
    input  wire               arready,
    output reg  [A_WIDTH-1:0] araddr,
    output wire [        7:0] arlen,
    input  wire               rvalid,
    output wire               rready,
    input  wire               rlast,
    input  wire [D_WIDTH-1:0] rdata,
    output reg                error,
    output reg  [       15:0] error_cnt
);

initial {awaddr, araddr} = '0;
initial {error, error_cnt} = '0;

wire       aw_end;
reg        awaddr_carry = '0;
reg  [7:0] w_cnt = '0;
enum logic [2:0] {INIT, AW, W, B, AR, R} stat = INIT;

generate if(A_WIDTH_TEST<A_WIDTH)
    assign aw_end = awaddr[A_WIDTH_TEST];
else
    assign aw_end = awaddr_carry;
endgenerate

assign awvalid = stat==AW;
assign awlen = WBURST_LEN;
assign wvalid = stat==W;
assign wlast = w_cnt==WBURST_LEN;
assign wdata = (D_WIDTH)'(awaddr);
assign bready = 1'b1;
assign arvalid = stat==AR;
assign arlen = RBURST_LEN;
assign rready = 1'b1;

wire [A_WIDTH:0] araddr_next = {1'b0,araddr} + (A_WIDTH+1)'(1<<D_LEVEL);

always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        {awaddr_carry, awaddr} <= '0;
        w_cnt <= 8'd0;
        araddr <= '0;
        stat <= INIT;
    end else begin
        case(stat)
            INIT: begin
                {awaddr_carry, awaddr} <= '0;
                w_cnt <= 8'd0;
                araddr <= '0;
                stat <= AW;
            end
            AW: if(awready) begin
                w_cnt <= 8'd0;
                stat <= W;
            end
            W: if(wready) begin
                {awaddr_carry, awaddr} <= {awaddr_carry, awaddr} + (A_WIDTH+1)'(1<<D_LEVEL);
                w_cnt <= w_cnt + 8'd1;
                if(wlast)
                    stat <= B;
            end
            B: if(bvalid) begin
                stat <= aw_end ? AR : AW;
            end
            AR: if(arready) begin
                stat <= R;
            end
            R: if(rvalid) begin
                araddr <= araddr_next[A_WIDTH-1:0];
                if(rlast) begin
                    stat <= AR;
                    if(araddr_next[A_WIDTH_TEST])
                        araddr <= '0;
                end
            end
        endcase
    end

// ------------------------------------------------------------
//  read and write mismatch detect
// ------------------------------------------------------------
wire [D_WIDTH-1:0] rdata_idle = (D_WIDTH)'(araddr);
always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        error <= 1'b0;
        error_cnt <= 16'd0;
    end else begin
        error <= rvalid && rready && rdata!=rdata_idle;
        if(error)
            error_cnt <= error_cnt + 16'd1;
    end

endmodule
