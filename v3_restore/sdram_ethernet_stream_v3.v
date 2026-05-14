// sdram_ethernet_stream_v3.v - SIMPLE VERSION
module sdram_ethernet_stream_v3(
    input           CLOCK_50,
    output [8:0]    LEDG,
    output [17:0]   LEDR,
    input  [3:0]    KEY,
    input  [17:0]   SW,
    output [6:0]    HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
    output [7:0]    VGA_B, VGA_G, VGA_R,
    output          VGA_BLANK_N, VGA_CLK, VGA_HS, VGA_SYNC_N, VGA_VS,
    output          ENET_GTX_CLK, ENET_MDC, ENET_RST_N,
    output [3:0]    ENET_TX_DATA,
    output          ENET_TX_EN,
    inout           ENET_MDIO,
    input           ENET_RX_CLK,
    input  [3:0]    ENET_RX_DATA,
    input           ENET_RX_DV, ENET_LINK100,
    output [12:0]   DRAM_ADDR,
    output [1:0]    DRAM_BA,
    output          DRAM_CAS_N, DRAM_CKE, DRAM_CLK, DRAM_CS_N,
    inout  [31:0]   DRAM_DQ,
    output [3:0]    DRAM_DQM,
    output          DRAM_RAS_N, DRAM_WE_N
);

wire clk, clk_sdram, vga_clk, vga_clk_dac, pll_locked;
sdram_pll pll_inst (
    .inclk0(CLOCK_50), .c0(clk), .c1(clk_sdram), .c2(vga_clk), .c3(vga_clk_dac), .locked(pll_locked)
);
assign DRAM_CLK = clk_sdram; assign VGA_CLK = vga_clk_dac; assign VGA_SYNC_N = 1'b0;

// 100Mbps PHY Config
reg clk_25_tx = 0; always @(posedge CLOCK_50) clk_25_tx <= ~clk_25_tx;
assign ENET_GTX_CLK = clk_25_tx;
assign ENET_RST_N = KEY[0];
wire mdio_done;
mdio_init phy_init (.clk(CLOCK_50), .rst_n(KEY[0]), .mdc(ENET_MDC), .mdio_en(mdio_en), .mdio_out(mdio_out), .done(mdio_done));
assign ENET_MDIO = mdio_en ? mdio_out : 1'bz;

// Simple Ethernet Receiver
wire [7:0] pixel_data; wire pixel_valid; wire [18:0] pixel_addr; wire frame_start;
gvsp_rx rx_inst (.clk_eth(ENET_RX_CLK), .rst_n(KEY[0]), .RX_DATA(ENET_RX_DATA), .RX_DV(ENET_RX_DV),
                 .pixel_data(pixel_data), .pixel_valid(pixel_valid), .pixel_addr(pixel_addr), .frame_start(frame_start));

// Pixel to Word (2 pixels = 1 word 32-bit)
reg [15:0] pix_lo; reg has_lo; reg [31:0] word_out; reg word_valid; reg [18:0] word_addr_sd;
always @(posedge ENET_RX_CLK) begin
    word_valid <= 0;
    if (frame_start) has_lo <= 0;
    if (pixel_valid) begin
        if (!has_lo) begin pix_lo <= {pixel_in[7:3], pixel_in[7:2], pixel_in[7:3]}; has_lo <= 1; end
        else begin word_out <= {{pixel_in[7:3], pixel_in[7:2], pixel_in[7:3]}, pix_lo}; 
                   word_addr_sd <= pixel_addr[18:1]; word_valid <= 1; has_lo <= 0; end
    end
end
wire [7:0] pixel_in = pixel_data;

// FIFO
wire fifo_empty; wire [50:0] fifo_q; reg fifo_rd;
dcfifo #(.lpm_width(51), .lpm_numwords(512), .lpm_showahead("ON")) pipe (
    .wrclk(ENET_RX_CLK), .rdclk(clk), .wrreq(word_valid), .rdreq(fifo_rd),
    .data({word_addr_sd, word_out}), .q(fifo_q), .rdempty(fifo_empty)
);

// VGA Timing
reg [9:0] h_cnt; reg [9:0] v_cnt;
always @(posedge vga_clk) if (h_cnt == 799) begin h_cnt <= 0; v_cnt <= (v_cnt==524)?0:v_cnt+1; end else h_cnt <= h_cnt + 1;
assign VGA_HS = ~(h_cnt >= 656 && h_cnt < 752); assign VGA_VS = ~(v_cnt >= 490 && v_cnt < 492);
assign VGA_BLANK_N = (h_cnt < 640 && v_cnt < 480);

// Double Line Buffer
reg [2:0] fetch_trig; always @(posedge clk) fetch_trig <= {fetch_trig[1:0], (h_cnt==0)};
wire do_fetch = (fetch_trig[2:1] == 2'b01);
(* ramstyle="M9K" *) reg [31:0] lbuf0 [0:159], lbuf1 [0:159];
reg [7:0] lwr_ptr; reg lwr_en; reg [31:0] lwr_data;
always @(posedge clk) if (lwr_en) if (v_cnt[0]) lbuf1[lwr_ptr] <= lwr_data; else lbuf0[lwr_ptr] <= lwr_data;
wire [7:0] lrd_ptr = h_cnt[9:2]; reg [31:0] ld0, ld1;
always @(posedge vga_clk) begin ld0 <= lbuf0[lrd_ptr]; ld1 <= lbuf1[lrd_ptr]; end
wire [15:0] color = h_cnt[1] ? (v_cnt[0]?ld1[31:16]:ld0[31:16]) : (v_cnt[0]?ld1[15:0]:ld0[15:0]);
assign {VGA_R, VGA_G, VGA_B} = VGA_BLANK_N ? {color[15:11],3'd0, color[10:5],2'd0, color[4:0],3'd0} : 24'd0;

// SDRAM FSM (Single Buffer 0)
reg [3:0] sd_cmd; reg [12:0] sd_addr; reg [1:0] sd_ba;
assign {DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N} = sd_cmd;
assign DRAM_ADDR = sd_addr; assign DRAM_BA = sd_ba; assign DRAM_CKE = 1'b1; assign DRAM_DQM = 0;
reg [31:0] dq_o; reg dq_oe; assign DRAM_DQ = dq_oe ? dq_o : 32'bz;

localparam S_IDLE=0, S_INIT=1, S_REF=2, S_READ=3, S_WRITE=4;
reg [4:0] st = S_INIT; reg [15:0] t_cnt; reg [9:0] rtimer;
reg [18:0] cur_addr; reg [7:0] bcnt;

always @(posedge clk) begin
    sd_cmd <= 4'b0111; dq_oe <= 0; lwr_en <= 0; fifo_rd <= 0;
    if (rtimer < 780) rtimer <= rtimer + 1;
    case (st)
        S_INIT: begin t_cnt <= t_cnt + 1; if(t_cnt==20000) begin sd_cmd <= 4'b0010; sd_addr[10] <= 1; end 
                if(t_cnt==20020) begin sd_cmd <= 4'b0000; sd_addr <= 13'h0030; end if(t_cnt==20050) st <= S_IDLE; end
        S_IDLE: begin if(rtimer >= 780) begin rtimer <= 0; sd_cmd <= 4'b0001; st <= S_REF; t_cnt <= 0; end
                else if(do_fetch) begin cur_addr <= {v_cnt[8:0], 9'd0}; bcnt <= 0; lwr_ptr <= 0; st <= S_READ; end
                else if(!fifo_empty) begin cur_addr <= fifo_q[50:32]; bcnt <= 0; st <= S_WRITE; end end
        S_REF: if(t_cnt == 10) st <= S_IDLE; else t_cnt <= t_cnt + 1;
        S_READ: begin sd_cmd <= 4'b0011; sd_ba <= 0; sd_addr <= cur_addr[18:9]; t_cnt <= 0; st <= 10; end
        10: if(t_cnt == 2) st <= 11; else t_cnt <= t_cnt + 1;
        11: begin sd_cmd <= 4'b0101; sd_addr <= {4'd0, cur_addr[8:0]}; cur_addr <= cur_addr + 1; bcnt <= bcnt + 1; t_cnt <= 0; st <= 12; end
        12: if(t_cnt == 3) begin lwr_data <= DRAM_DQ; lwr_en <= 1; lwr_ptr <= lwr_ptr + 1; if(bcnt >= 160) st <= S_IDLE; else st <= 11; end else t_cnt <= t_cnt + 1;
        S_WRITE: begin sd_cmd <= 4'b0011; sd_ba <= 0; sd_addr <= cur_addr[18:9]; t_cnt <= 0; st <= 13; end
        13: if(t_cnt == 2) st <= 14; else t_cnt <= t_cnt + 1;
        14: begin sd_cmd <= 4'b0100; sd_addr <= {4'd0, cur_addr[8:0]}; dq_o <= fifo_q[31:0]; dq_oe <= 1; fifo_rd <= 1; st <= S_IDLE; end
    endcase
end

// Debug
assign LEDR[17] = ~ENET_LINK100; assign LEDG[0] = pll_locked; assign LEDG[1] = mdio_done;
assign HEX0 = {6'b111111, ~ENET_RX_DV};
endmodule
