`timescale 1 ns/1 ns

module uart2axi4 #(
    parameter  A_WIDTH    = 26,
    parameter  D_WIDTH    = 16
) (
    input  wire               aresetn,
    input  wire               aclk,
    
    output wire               awvalid,
    input  wire               awready,
    output reg  [A_WIDTH-1:0] awaddr,
    output reg  [        7:0] awlen,
    output wire               wvalid,
    input  wire               wready,
    output wire               wlast,
    output wire [D_WIDTH-1:0] wdata,
    input  wire               bvalid,
    output wire               bready,
    output wire               arvalid,
    input  wire               arready,
    output reg  [A_WIDTH-1:0] araddr,
    output reg  [        7:0] arlen,
    input  wire               rvalid,
    output wire               rready,
    input  wire               rlast,
    input  wire [D_WIDTH-1:0] rdata,
    
    input  wire               uart_rx,
    output wire               uart_tx
);

function automatic logic isW(input [7:0] c);
    return c==8'h57 || c==8'h77;
endfunction

function automatic logic isR(input [7:0] c);
    return c==8'h52 || c==8'h72;
endfunction

function automatic logic isSpace(input [7:0] c);
    return c==8'h20 || c==8'h09;
endfunction

function automatic logic isNewline(input [7:0] c);
    return c==8'h0D || c==8'h0A;
endfunction

function automatic logic [3:0] isHex(input [7:0] c);
    if(c>=8'h30 && c<= 8'h39)
        return 1'b1;
    else if(c>=8'h41 && c<=8'h46 || c>=8'h61 && c<=8'h66)
        return 1'b1;
    else
        return 1'b0;
endfunction

function automatic logic [3:0] getHex(input [7:0] c);
    if(c>=8'h30 && c<= 8'h39)
        return c[3:0];
    else if(c>=8'h41 && c<=8'h46 || c>=8'h61 && c<=8'h66)
        return c[3:0] + 8'h9;
    else
        return 4'd0;
endfunction

localparam V_WIDTH = A_WIDTH>D_WIDTH ? (A_WIDTH>8?A_WIDTH:8) : (D_WIDTH>8?D_WIDTH:8);

wire       rx_valid;
wire [7:0] rx_data;

reg               rw;     // 0:write   1:read
reg [V_WIDTH-1:0] value;
reg [        7:0] value_cnt;
reg               wbuf_wen;
reg [        7:0] wbuf_waddr;
reg [D_WIDTH-1:0] wbuf_wdata;
reg [        7:0] wbuf_raddr;
wire[        7:0] wbuf_raddr_n = stat == AXI_W && wready ? wbuf_raddr + 8'd1 : wbuf_raddr;
wire[D_WIDTH-1:0] wbuf_rdata;
enum logic [3:0] {IDLE, INVALID, GADDR, GRLEN, GWDATA, AXI_AR, AXI_R, AXI_AW, AXI_W, AXI_B} stat;

assign awvalid = stat == AXI_AW;
assign wvalid = stat == AXI_W;
assign wlast = wbuf_raddr == wbuf_waddr;
assign wdata = wbuf_rdata;
assign bready = stat == AXI_B;
assign arvalid = stat == AXI_AR;

always @ (posedge aclk or negedge aresetn)
    if(~aresetn) begin
        awaddr <= '0;
        awlen <= '0;
        araddr <= '0;
        arlen <= '0;
        rw <= 1'b0;
        value <= '0;
        value_cnt <= '0;
        wbuf_wen <= 1'b0;
        wbuf_waddr <= '0;
        wbuf_wdata <= '0;
        wbuf_raddr <= '0;
        stat <= IDLE;
    end else begin
        wbuf_wen <= 1'b0;
        case(stat)
            IDLE: if(rx_valid) begin
                value <= '0;
                value_cnt <= '0;
                wbuf_raddr <= '0;
                if( isW(rx_data) ) begin
                    rw <= 1'b0;
                    stat <= GADDR;
                end else if( isR(rx_data) ) begin
                    rw <= 1'b1;
                    stat <= GADDR;
                end else if( ~isNewline(rx_data) ) begin
                    stat <= INVALID;
                end
            end
            GADDR: if(rx_valid) begin
                if( isNewline(rx_data) ) begin
                    value <= '0;
                    stat <= IDLE;
                end else if( isSpace(rx_data) ) begin
                    value <= '0;
                    if(rw) begin
                        araddr <= value[A_WIDTH-1:0];
                        stat <= GRLEN;
                    end else begin
                        awaddr <= value[A_WIDTH-1:0];
                        stat <= GWDATA;
                    end
                end else if( isHex(rx_data) ) begin
                    value <= { value[V_WIDTH-5:0], getHex(rx_data) };
                end else begin
                    stat <= INVALID;
                end
            end
            GRLEN: if(rx_valid) begin
                if( isNewline(rx_data) ) begin
                    value <= '0;
                    arlen <= value[7:0];
                    stat <= AXI_AR;
                end else if( isHex(rx_data) ) begin
                    value <= { value[V_WIDTH-5:0], getHex(rx_data) };
                end else begin
                    stat <= INVALID;
                end
            end
            GWDATA: if(rx_valid) begin
                if( isNewline(rx_data) ) begin
                    wbuf_wen <= 1'b1;
                    wbuf_waddr <= value_cnt;
                    wbuf_wdata <= value[D_WIDTH-1:0];
                    awlen <= value_cnt;
                    stat <= AXI_AW;
                end else if( isSpace(rx_data) ) begin
                    value <= '0;
                    value_cnt <= value_cnt + 8'd1;
                    wbuf_wen <= 1'b1;
                    wbuf_waddr <= value_cnt;
                    wbuf_wdata <= value[D_WIDTH-1:0];
                end else if( isHex(rx_data) ) begin
                    value <= { value[V_WIDTH-5:0], getHex(rx_data) };
                end else begin
                    stat <= INVALID;
                end
            end
            INVALID: if( rx_valid ) begin
                if ( isNewline(rx_data) )
                    stat <= IDLE;
            end
            AXI_AR: if(arready) begin
                stat <= AXI_R;
            end
            AXI_R: if(rvalid & rready & rlast) begin
                stat <= IDLE;
            end
            AXI_AW: if(awready) begin
                stat <= AXI_W;
            end
            AXI_W: if(wready) begin
                wbuf_raddr <= wbuf_raddr + 8'd1;
                if(wbuf_raddr==awlen)
                    stat <= AXI_B;
            end
            AXI_B: if(bvalid) begin
                stat <= IDLE;
            end
            default: stat<=IDLE;
        endcase
    end

ram_for_axi4write #(
    .ADDR_LEN    ( 8            ),
    .DATA_LEN    ( D_WIDTH      )
) ram_for_axi4write_i (
    .clk         ( aclk         ),
    .wr_req      ( wbuf_wen     ),
    .wr_addr     ( wbuf_waddr   ),
    .wr_data     ( wbuf_wdata   ),
    .rd_addr     ( wbuf_raddr_n ),
    .rd_data     ( wbuf_rdata   )
);

uart_rx#(
    .CLK_DIV     ( 162          ),
    .CLK_PART    ( 6            )
) uart_rx_i (
    .rstn        ( aresetn      ),
    .clk         ( aclk         ),
    .rx          ( uart_rx      ),
    .rvalid      ( rx_valid     ),
    .rdata       ( rx_data      ) 
);

axis2uarttx #(
    .CLK_DIV     ( 651          ),
    .DATA_WIDTH  ( D_WIDTH      ),
    .FIFO_ASIZE  ( 10           )
) uart_tx_i (
    .aresetn     ( aresetn      ),
    .aclk        ( aclk         ),
    .tvalid      ( rvalid       ),
    .tready      ( rready       ),
    .tlast       ( rlast        ),
    .tdata       ( rdata        ),
    .uart_tx     ( uart_tx      )
);

endmodule








module ram_for_axi4write #(
    parameter ADDR_LEN = 12,
    parameter DATA_LEN = 8
) (
    input  logic clk,
    input  logic wr_req,
    input  logic [ADDR_LEN-1:0] rd_addr, wr_addr,
    output logic [DATA_LEN-1:0] rd_data,
    input  logic [DATA_LEN-1:0] wr_data
);

localparam  RAM_SIZE = (1<<ADDR_LEN);

logic [DATA_LEN-1:0] mem [RAM_SIZE];

initial rd_data = 0;

always @ (posedge clk)
    rd_data <= mem[rd_addr];

always @ (posedge clk)
    if(wr_req)
        mem[wr_addr] <= wr_data;

endmodule
