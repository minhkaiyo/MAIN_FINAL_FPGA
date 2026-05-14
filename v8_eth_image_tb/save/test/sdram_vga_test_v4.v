// sdram_vga_test_v4.v
// EXACT 1:1 CLONE OF WORKING vga_sdram_test_fixed.v
// Date: 2026-05-11

module sdram_vga_test_v4 (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,

    // SDRAM
    output wire [12:0] DRAM_ADDR,
    output wire [1:0]  DRAM_BA,
    output wire        DRAM_CAS_N, DRAM_CKE, DRAM_CLK, DRAM_CS_N,
    inout  wire [31:0] DRAM_DQ,
    output wire [3:0]  DRAM_DQM,
    output wire        DRAM_RAS_N, DRAM_WE_N,

    // VGA
    output wire [7:0]  VGA_B, VGA_G, VGA_R,
    output wire        VGA_BLANK_N, VGA_CLK, VGA_HS, VGA_SYNC_N, VGA_VS,

    output wire [8:0]  LEDG,

    // Gigabit Ethernet
    output wire ENET_GTX_CLK, ENET_MDC,
    inout  wire ENET_MDIO,
    output wire ENET_RST_N,
    input  wire ENET_RX_CLK,
    input  wire [3:0] ENET_RX_DATA,
    input  wire ENET_RX_DV,
    output wire [3:0] ENET_TX_DATA,
    output wire ENET_TX_EN
);

// ---------------------------------------------------------------------------
// 1. Clocking
// ---------------------------------------------------------------------------
wire clk, clk_sdram, vga_clk, vga_clk_dac, locked;
sdram_pll pll_inst (
    .inclk0(CLOCK_50), .c0(clk), .c1(clk_sdram), .c2(vga_clk), .c3(vga_clk_dac), .locked(locked)
);

wire clk_125, clk_125_90, pll_125_locked;
pll_125 pll_125_inst (
    .inclk0(CLOCK_50), .c0(clk_125), .c1(clk_125_90), .locked(pll_125_locked)
);

assign DRAM_CLK   = clk_sdram;
assign VGA_CLK    = vga_clk_dac;
assign VGA_SYNC_N = 1'b0;

// ---------------------------------------------------------------------------
// 2. Ethernet & Parser
// ---------------------------------------------------------------------------
wire phy_ready;
phy_init_88e1111 phy_init_inst (
    .clk(CLOCK_50), .rst_n(KEY[0]),
    .phy_rst_n(ENET_RST_N), .mdc(ENET_MDC), .mdio(ENET_MDIO), .configured(phy_ready)
);

wire [7:0] rx_axis_tdata; wire rx_axis_tvalid, rx_axis_tlast;
eth_mac_1g_rgmii_fifo #(.TARGET("ALTERA"), .RX_FIFO_DEPTH(4096)) mac_inst (
    .gtx_clk(clk_125), .gtx_clk90(clk_125_90), .gtx_rst(~KEY[0]),
    .logic_clk(clk_125), .logic_rst(~KEY[0]),
    .rx_axis_tdata(rx_axis_tdata), .rx_axis_tvalid(rx_axis_tvalid), .rx_axis_tready(1'b1), .rx_axis_tlast(rx_axis_tlast),
    .rgmii_rx_clk(ENET_RX_CLK), .rgmii_rxd(ENET_RX_DATA), .rgmii_rx_ctl(ENET_RX_DV),
    .rgmii_tx_clk(ENET_GTX_CLK), .rgmii_txd(ENET_TX_DATA), .rgmii_tx_ctl(ENET_TX_EN),
    .cfg_rx_enable(1'b1), .cfg_tx_enable(1'b1)
);

reg [3:0] parser_fsm = 0; reg [11:0] p_byte_cnt = 0;
reg [15:0] row_idx; reg [31:0] w_data; reg [17:0] w_addr; reg [1:0] w_byte_idx; reg w_valid;

always @(posedge clk_125) begin
    w_valid <= 0;
    if (rx_axis_tlast) begin parser_fsm <= 0; p_byte_cnt <= 0; w_byte_idx <= 0; end
    else if (rx_axis_tvalid) begin
        case (parser_fsm)
            0: begin parser_fsm <= 1; p_byte_cnt <= 1; end // Eth Header
            1: if (p_byte_cnt == 13) begin parser_fsm <= 2; p_byte_cnt <= 0; end else p_byte_cnt <= p_byte_cnt + 1;
            2: if (p_byte_cnt == 19) begin parser_fsm <= 3; p_byte_cnt <= 0; end else p_byte_cnt <= p_byte_cnt + 1; // IP Header
            3: if (p_byte_cnt == 7)  begin parser_fsm <= 4; p_byte_cnt <= 0; end else p_byte_cnt <= p_byte_cnt + 1; // UDP Header
            4: begin // Data
                if (p_byte_cnt == 0)      begin row_idx[15:8] <= rx_axis_tdata; p_byte_cnt <= 1; end
                else if (p_byte_cnt == 1) begin w_addr <= {row_idx[15:8], rx_axis_tdata} * 18'd160; p_byte_cnt <= 2; end
                else begin
                    w_data <= {w_data[23:0], rx_axis_tdata};
                    if (w_byte_idx == 3) begin w_valid <= 1; w_byte_idx <= 0; end
                    else w_byte_idx <= w_byte_idx + 1;
                    if (w_valid) w_addr <= w_addr + 1;
                end
            end
        endcase
    end
end

wire f_empty; wire [49:0] f_dout; wire [12:0] f_used; reg f_rd;
dcfifo #(.lpm_numwords(8192), .lpm_width(50), .lpm_widthu(13), .lpm_showahead("ON")) eth_fifo (
    .wrclk(clk_125), .rdclk(clk), .wrreq(w_valid), .rdreq(f_rd),
    .data({w_addr, w_data}), .q(f_dout), .rdempty(f_empty), .rdusedw(f_used)
);

// ---------------------------------------------------------------------------
// 3. VGA Timing
// ---------------------------------------------------------------------------
reg [9:0] h_cnt = 0; reg [10:0] v_cnt = 0;
always @(posedge vga_clk) begin
    if (h_cnt == 799) begin h_cnt <= 0; v_cnt <= (v_cnt == 524) ? 0 : v_cnt + 1; end
    else h_cnt <= h_cnt + 1;
end
assign VGA_HS = ~((h_cnt >= 656) && (h_cnt < 752));
assign VGA_VS = ~((v_cnt >= 490) && (v_cnt < 492));

reg [2:0] h_sync_edge = 0; always @(posedge clk) h_sync_edge <= {h_sync_edge[1:0], (h_cnt == 1)};
wire start_fetch = (h_sync_edge[2:1] == 2'b01);
wire [10:0] fetch_line = (v_cnt == 524) ? 0 : v_cnt + 1;

(* ramstyle = "M9K" *) reg [31:0] line_buf_A [0:159];
(* ramstyle = "M9K" *) reg [31:0] line_buf_B [0:159];
reg [7:0] buf_wr_ptr; reg buf_wr_en; reg [31:0] buf_wr_data;
always @(posedge clk) if (buf_wr_en)
    if (fetch_line[0]) line_buf_B[buf_wr_ptr] <= buf_wr_data;
    else               line_buf_A[buf_wr_ptr] <= buf_wr_data;

wire [7:0] rd_idx = h_cnt[9:2];
reg [31:0] rd_data_A, rd_data_B;
always @(posedge vga_clk) begin rd_data_A <= line_buf_A[rd_idx]; rd_data_B <= line_buf_B[rd_idx]; end
wire [31:0] pixel_word = v_cnt[0] ? rd_data_B : rd_data_A;

reg [1:0] h_cnt_d1; always @(posedge vga_clk) h_cnt_d1 <= h_cnt[1:0];
wire [7:0] pixel_byte = (h_cnt_d1==0)?pixel_word[7:0]:(h_cnt_d1==1)?pixel_word[15:8]:(h_cnt_d1==2)?pixel_word[23:16]:pixel_word[31:24];

wire [7:0] r8 = {pixel_byte[7:5], pixel_byte[7:5], pixel_byte[7:6]};
wire [7:0] g8 = {pixel_byte[4:2], pixel_byte[4:2], pixel_byte[4:3]};
wire [7:0] b8 = {pixel_byte[1:0], pixel_byte[1:0], pixel_byte[1:0], pixel_byte[1:0]};

assign VGA_BLANK_N = (h_cnt < 640 && v_cnt < 480);
assign VGA_R = VGA_BLANK_N ? r8 : 0; assign VGA_G = VGA_BLANK_N ? g8 : 0; assign VGA_B = VGA_BLANK_N ? b8 : 0;

// ---------------------------------------------------------------------------
// 4. SDRAM FSM
// ---------------------------------------------------------------------------
reg [3:0] dram_cmd; reg [12:0] dram_addr_r; reg [1:0] dram_ba_r;
assign {DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N} = dram_cmd;
assign DRAM_ADDR = dram_addr_r; assign DRAM_BA = dram_ba_r;
assign DRAM_CKE = 1'b1; assign DRAM_DQM = 4'b0000;
reg [31:0] dq_out; reg dq_oe = 0; assign DRAM_DQ = dq_oe ? dq_out : 32'bz;
wire [31:0] dq_in = DRAM_DQ;

localparam CMD_NOP=4'b0111, CMD_ACT=4'b0011, CMD_RD=4'b0101, CMD_WR=4'b0100, CMD_PRE=4'b0010, CMD_REF=4'b0001;
reg [4:0] state = 0; reg [15:0] wait_cnt; reg [9:0] refresh_cnt;
reg [17:0] sd_addr; reg [8:0] words_cnt; reg [8:0] col_ptr;

always @(posedge clk or negedge locked) begin
    if (!locked) begin state <= 0; dram_cmd <= CMD_NOP; dq_oe <= 0; refresh_cnt <= 0; end
    else begin
        dram_cmd <= CMD_NOP; dq_oe <= 0; buf_wr_en <= 0; f_rd <= 0;
        if (refresh_cnt < 780) refresh_cnt <= refresh_cnt + 1;
        case (state)
            0: begin wait_cnt <= 0; state <= 1; end
            1: if (wait_cnt == 20000) state <= 2; else wait_cnt <= wait_cnt + 1;
            2: begin dram_cmd <= CMD_PRE; dram_addr_r[10] <= 1; wait_cnt <= 0; state <= 3; end
            3: if (wait_cnt == 2) state <= 4; else wait_cnt <= wait_cnt + 1;
            4: begin dram_cmd <= CMD_REF; wait_cnt <= 0; state <= 5; end
            5: if (wait_cnt == 7) state <= 6; else wait_cnt <= wait_cnt + 1;
            6: begin dram_cmd <= 4'b0000; dram_ba_r <= 0; dram_addr_r <= 13'b000_0_00_010_0_000; wait_cnt <= 0; state <= 7; end
            7: if (wait_cnt == 2) state <= 8; else wait_cnt <= wait_cnt + 1;
            8: begin // IDLE
                if (refresh_cnt >= 780) begin refresh_cnt <= 0; state <= 9; end
                else if (start_fetch && fetch_line < 480) begin sd_addr <= fetch_line * 18'd160; words_cnt <= 0; buf_wr_ptr <= 0; state <= 11; end
                else if (!f_empty && f_used >= 32) begin sd_addr <= f_dout[49:32]; words_cnt <= 0; state <= 18; end
            end
            9: begin dram_cmd <= CMD_REF; wait_cnt <= 0; state <= 10; end
            10: if (wait_cnt == 7) state <= 8; else wait_cnt <= wait_cnt + 1;
            11: begin dram_cmd <= CMD_ACT; dram_ba_r <= 0; dram_addr_r <= sd_addr[17:9]; col_ptr <= sd_addr[8:0]; wait_cnt <= 0; state <= 12; end
            12: if (wait_cnt == 2) state <= 13; else wait_cnt <= wait_cnt + 1;
            13: begin dram_cmd <= CMD_RD; dram_addr_r <= {4'd0, col_ptr}; col_ptr <= col_ptr + 1; sd_addr <= sd_addr + 1; words_cnt <= words_cnt + 1; wait_cnt <= 0; state <= 14; end
            14: if (wait_cnt == 2) state <= 15; else wait_cnt <= wait_cnt + 1;
            15: begin buf_wr_data <= dq_in; buf_wr_en <= 1; buf_wr_ptr <= buf_wr_ptr + 1; if (words_cnt >= 160 || col_ptr == 0) state <= 16; else state <= 13; end
            16: begin dram_cmd <= CMD_PRE; dram_addr_r[10] <= 1; wait_cnt <= 0; state <= 17; end
            17: if (wait_cnt == 2) begin if (words_cnt < 160) state <= 11; else state <= 8; end else wait_cnt <= wait_cnt + 1;
            18: begin dram_cmd <= CMD_ACT; dram_ba_r <= 0; dram_addr_r <= sd_addr[17:9]; col_ptr <= sd_addr[8:0]; wait_cnt <= 0; state <= 19; end
            19: if (wait_cnt == 2) state <= 20; else wait_cnt <= wait_cnt + 1;
            20: begin dram_cmd <= CMD_WR; dram_addr_r <= {4'd0, col_ptr}; dq_out <= f_dout[31:0]; dq_oe <= 1; f_rd <= 1; col_ptr <= col_ptr + 1; sd_addr <= sd_addr + 1; words_cnt <= words_cnt + 1; state <= 21; end
            21: if (words_cnt >= 32 || col_ptr == 0 || f_empty) state <= 22; else state <= 20;
            22: begin dram_cmd <= CMD_PRE; dram_addr_r[10] <= 1; wait_cnt <= 0; state <= 23; end
            23: if (wait_cnt == 2) state <= 8; else wait_cnt <= wait_cnt + 1;
            default: state <= 0;
        endcase
    end
end
endmodule
