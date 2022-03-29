
//--------------------------------------------------------------------------------------------------------
// Module  : uart2axi4
// Type    : synthesizable
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: convert UART command to AXI4 read/write action
//--------------------------------------------------------------------------------------------------------

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










module uart_rx #(
    parameter CLK_DIV       = 108,  // UART baud rate = clk freq/(4*CLK_DIV)
                                    // modify CLK_DIV to change the UART baud
                                    // for example, when clk=50MHz, CLK_DIV=108, then baud=100MHz/(4*108)=115200
                                    // 115200 is a typical baud rate for UART
    parameter CLK_PART      = 4     // from 0 to 7
) (
    input  wire        clk, rstn,
    // uart rx input
    input  wire        rx,
    // user interface
    output wire        rvalid,
    output wire [7:0]  rdata
);

reg        done = 1'b0;
reg [ 7:0] data = 8'h0;
reg [ 2:0] supercnt=3'h0;
reg [31:0] cnt = 0;
reg [ 7:0] databuf = 8'h0;
reg [ 5:0] status=6'h0, shift=6'h0;
reg rxr=1'b1;
wire recvbit = (shift[1]&shift[0]) | (shift[0]&rxr) | (rxr&shift[1]) ;
wire [2:0] supercntreverse = {supercnt[0], supercnt[1], supercnt[2]};

assign rvalid = done;
assign rdata  = data;

always @ (posedge clk or negedge rstn)
    if(~rstn)
        rxr <= 1'b1;
    else
        rxr <= rx;

always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        done    <= 1'b0;
        data    <= 8'h0;
        status  <= 6'h0;
        shift   <= 6'h0;
        databuf <= 8'h0;
        cnt     <= 0;
    end else begin
        done <= 1'b0;
        if( (supercntreverse<CLK_PART) ? (cnt>=CLK_DIV) : (cnt>=CLK_DIV-1) ) begin
            if(status==0) begin
                if(shift == 6'b111_000)
                    status <= 1;
            end else begin
                if(status[5] == 1'b0) begin
                    if(status[1:0] == 2'b11)
                        databuf <= {recvbit, databuf[7:1]};
                    status <= status + 5'b1;
                end else begin
                    if(status<62) begin
                        status <= 62;
                        data <= databuf;
                        done <= 1'b1;
                    end else begin
                        status <= status + 6'd1;
                    end
                end
            end
            shift <= {shift[4:0], rxr};
            supercnt <= supercnt + 3'h1;
            cnt <= 0;
        end else
            cnt <= cnt + 1;
    end

endmodule










module axis2uarttx #(
    parameter CLK_DIV    = 434,
    parameter DATA_WIDTH = 32,
    parameter FIFO_ASIZE = 8
) (
    // AXI-stream (slave) side
    input  logic aclk, aresetn,
    input  logic tvalid, tlast,
    output logic tready,
    input  logic [DATA_WIDTH-1:0] tdata,
    // UART TX signal
    output logic uart_tx
);
localparam TX_WIDTH = (DATA_WIDTH+3) / 4;

function automatic logic [7:0] hex2ascii (input [3:0] hex);
    return {4'h3, hex} + ((hex<4'hA) ? 8'h0 : 8'h7) ;
endfunction

logic uart_txb;
logic [FIFO_ASIZE-1:0] fifo_rpt='0, fifo_wpt='0;
wire  [FIFO_ASIZE-1:0] fifo_wpt_next = fifo_wpt + {{(FIFO_ASIZE-1){1'b0}}, 1'b1};
wire  [FIFO_ASIZE-1:0] fifo_rpt_next = fifo_rpt + {{(FIFO_ASIZE-1){1'b0}}, 1'b1};
logic [31:0] cyccnt=0, hexcnt=0, txcnt=0;
logic [ 7:0] txshift = '1;
logic fifo_tlast;
logic [DATA_WIDTH-1:0] fifo_data;
logic endofline = 1'b0;
logic [TX_WIDTH*4-1:0] data='0;
wire  emptyn = (fifo_rpt != fifo_wpt);
assign  tready = (fifo_rpt != fifo_wpt_next) & aresetn;

always @ (posedge aclk or negedge aresetn)
    if(~aresetn)
        uart_tx <= 1'b1;
    else begin
        uart_tx <= uart_txb;
    end

always @ (posedge aclk or negedge aresetn)
    if(~aresetn)
        fifo_wpt <= '0;
    else begin
        if(tvalid & tready) fifo_wpt <= fifo_wpt_next;
    end

always @ (posedge aclk or negedge aresetn)
    if(~aresetn)
        cyccnt <= 0;
    else
        cyccnt <= (cyccnt<CLK_DIV-1) ? cyccnt+1 : 0;

always @ (posedge aclk or negedge aresetn)
    if(~aresetn) begin
        fifo_rpt  <= '0;
        endofline <= 1'b0;
        data      <= '0;
        uart_txb  <= 1'b1;
        txshift   <= '1;
        txcnt     <= 0;
        hexcnt    <= 0;
    end else begin
        if( hexcnt>(1+TX_WIDTH) ) begin
            uart_txb  <= 1'b1;
            endofline <= fifo_tlast;
            data                 <= '0;
            data[DATA_WIDTH-1:0] <= fifo_data;
            hexcnt <= hexcnt-1;
        end else if(hexcnt>0 || txcnt>0) begin
            if(cyccnt==CLK_DIV-1) begin
                if(txcnt>0) begin
                    {txshift, uart_txb} <= {1'b1, txshift};
                    txcnt <= txcnt-1;
                end else begin
                    uart_txb <= 1'b0;
                    hexcnt <= hexcnt-1;
                    if(hexcnt>1)
                        txshift <= hex2ascii(data[(hexcnt-2)*4+:4]);
                    else if(endofline)
                        txshift <= 8'h0A;
                    else
                        txshift <= 8'h20;
                    txcnt <= 11;
                end
            end
        end else if(emptyn) begin
            uart_txb <= 1'b1;
            hexcnt   <= 2 + TX_WIDTH;
            txcnt    <= 0;
            fifo_rpt <= fifo_rpt_next;
        end
    end

ram_for_axi_stream_to_uart_tx_fifo #(
    .ADDR_LEN  ( FIFO_ASIZE             ),
    .DATA_LEN  ( DATA_WIDTH + 1         )
) ram_for_uart_tx_fifo_inst (
    .clk       ( aclk                   ),
    .wr_req    ( tvalid & tready        ),
    .wr_addr   ( fifo_wpt               ),
    .wr_data   ( {tlast, tdata}         ),
    .rd_addr   ( fifo_rpt               ),
    .rd_data   ( {fifo_tlast,fifo_data} )
);

endmodule






module ram_for_axi_stream_to_uart_tx_fifo #(
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

