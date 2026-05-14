// gigabit_video_pipeline_final.v
// Version 7.2: One-Row-Per-Line Architecture (Anti-Flicker)

module gigabit_video_pipeline_final (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [17:0] SW,

    // SDRAM Pins
    output wire [12:0] DRAM_ADDR,
    output wire [1:0]  DRAM_BA,
    output wire        DRAM_CAS_N, DRAM_CKE, DRAM_CKE_N, DRAM_CLK, DRAM_CS_N,
    inout  wire [31:0] DRAM_DQ,
    output wire [3:0]  DRAM_DQM,
    output wire        DRAM_RAS_N, DRAM_WE_N,

    // VGA
    output wire [7:0]  VGA_B, VGA_G, VGA_R,
    output wire        VGA_BLANK_N, VGA_CLK, VGA_HS, VGA_SYNC_N, VGA_VS,
    output wire [8:0]  LEDG,
    output wire [17:0] LEDR,
    output wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,

    // Gigabit Ethernet (RGMII)
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
// 1. Clock & PLL
// ---------------------------------------------------------------------------
wire clk_sys, clk_vga, clk_vga_dac, clk_125, clk_125_90, locked;
sdram_pll pll_inst (
    .inclk0(CLOCK_50), .c0(clk_sys), .c1(DRAM_CLK), .c2(clk_vga), .c3(clk_vga_dac), .locked(locked)
);

wire pll_eth_locked;
pll_125 eth_pll (
    .inclk0(CLOCK_50), .c0(clk_125), .c1(clk_125_90), .locked(pll_eth_locked)
);

assign VGA_CLK    = clk_vga_dac;
assign VGA_SYNC_N = 1'b0;

// ---------------------------------------------------------------------------
// 2. Ethernet & Parser
// ---------------------------------------------------------------------------
wire phy_ready;
phy_init_88e1111 phy_cfg (
    .clk(CLOCK_50), .rst_n(KEY[0]),
    .phy_rst_n(ENET_RST_N), .mdc(ENET_MDC), .mdio(ENET_MDIO), .configured(phy_ready)
);

wire [7:0] rx_tdata; wire rx_tvalid, rx_tlast, rx_error;
wire mac_rst = ~KEY[0] | !phy_ready | !locked;
wire [1:0] mac_speed;

eth_mac_1g_rgmii_fifo #(
    .TARGET("ALTERA"), .RX_FIFO_DEPTH(4096), .RX_FRAME_FIFO(1), .RX_DROP_BAD_FRAME(0)
) mac_inst (
    .gtx_clk(clk_125), .gtx_clk90(clk_125_90), .gtx_rst(mac_rst), 
    .logic_clk(clk_125), .logic_rst(mac_rst),
    .rx_axis_tdata(rx_tdata), .rx_axis_tvalid(rx_tvalid), .rx_axis_tready(1'b1), .rx_axis_tlast(rx_tlast),
    .rx_axis_tuser(rx_error),
    .rgmii_rx_clk(ENET_RX_CLK), .rgmii_rxd(ENET_RX_DATA), .rgmii_rx_ctl(ENET_RX_DV),
    .rgmii_tx_clk(ENET_GT_CLK), .rgmii_txd(ENET_TX_DATA), .rgmii_tx_ctl(ENET_TX_EN),
    .cfg_rx_enable(1'b1), .cfg_tx_enable(1'b1), .speed(mac_speed)
);

reg [3:0] dbg_fsm = 0; reg [11:0] byte_cnt = 0;
reg [31:0] word_data = 0; reg [21:0] word_addr = 0; reg [1:0] byte_idx = 0;
reg word_valid = 0; reg [15:0] row_idx = 0;
reg row_in_range = 0;
reg [31:0] raw_capture;
reg [15:0] udp_port_detect;
wire [5:0] skip_count = SW[0] ? 44 : 42;

always @(posedge clk_125) begin
    word_valid <= 0;
    if (rx_tlast) begin dbg_fsm <= 0; byte_idx <= 0; end
    else if (rx_tvalid) begin
        case (dbg_fsm)
            0: begin dbg_fsm <= 1; byte_cnt <= 1; end
            1: begin 
                if (byte_cnt == 36) udp_port_detect[15:8] <= rx_tdata;
                if (byte_cnt == 37) udp_port_detect[7:0]  <= rx_tdata;
                if(byte_cnt == skip_count-1) begin dbg_fsm <= 4; byte_cnt <= 0; end 
                else byte_cnt <= byte_cnt + 1; 
            end
            4: begin 
                if (byte_cnt == 0) raw_capture[31:24] <= rx_tdata;
                if (byte_cnt == 1) raw_capture[23:16] <= rx_tdata;
                if (byte_cnt == 2) raw_capture[15:8]  <= rx_tdata;
                if (byte_cnt == 3) raw_capture[7:0]   <= rx_tdata;

                if (byte_cnt == 0) begin row_idx[15:8] <= rx_tdata; byte_cnt <= 1; end
                else if (byte_cnt == 1) begin 
                    row_idx[7:0] <= rx_tdata;
                    if ({row_idx[15:8], rx_tdata} < 480) begin
                        word_addr <= {3'd0, rx_tdata[7:0], 10'd0}; // row_idx -> Row, 0 -> Column
                        row_in_range <= 1;
                    end else row_in_range <= 0;
                    byte_cnt <= 2; 
                end else if (row_in_range) begin
                    word_data <= {word_data[23:0], rx_tdata};
                    if (byte_idx == 3) begin word_valid <= 1; byte_idx <= 0; end
                    else byte_idx <= byte_idx + 1;
                    if (word_valid) word_addr <= word_addr + 1;
                end
            end
        endcase
    end
end

// --- Internal Test Pattern Generator (For Isolation Debug) ---
reg [9:0] test_h = 0; reg [8:0] test_v = 0;
reg test_word_valid; reg [21:0] test_word_addr; reg [31:0] test_word_data;
reg [3:0] test_slow_cnt;

always @(posedge clk_125) begin
    test_word_valid <= 0;
    if (SW[17]) begin
        if (test_slow_cnt == 10) begin
            test_slow_cnt <= 0;
            if (test_h == 159) begin
                test_h <= 0;
                test_v <= (test_v == 479) ? 0 : test_v + 1;
            end else test_h <= test_h + 1;
            
            test_word_valid <= 1;
            test_word_addr <= {3'd0, test_v, 10'd0} + test_h;
            // Tạo màu sắc rực rỡ: R=v, G=h, B=v+h
            test_word_data <= {test_v[7:0], test_h[7:0], (test_v[7:0] + test_h[7:0]), 8'hAA};
        end else test_slow_cnt <= test_slow_cnt + 1;
    end
end

wire fifo_wr_en = SW[17] ? test_word_valid : word_valid;
wire [21:0] fifo_wr_addr = SW[17] ? test_word_addr : word_addr;
wire [31:0] fifo_wr_data = SW[17] ? test_word_data : word_data;

wire fifo_empty; wire [53:0] fifo_q; wire [12:0] fifo_used; reg fifo_rd;
dcfifo #(.lpm_numwords(8192), .lpm_width(54), .lpm_widthu(13), .lpm_showahead("ON")) pipe_fifo (
    .wrclk(clk_125), .rdclk(clk_sys), 
    .wrreq(fifo_wr_en), .rdreq(fifo_rd),
    .data({fifo_wr_addr, fifo_wr_data}), .q(fifo_q), .rdempty(fifo_empty), .rdusedw(fifo_used)
);

// ---------------------------------------------------------------------------
// 3. VGA Controller
// ---------------------------------------------------------------------------
reg [9:0] h_pos = 0; reg [10:0] v_pos = 0;
always @(posedge clk_vga) begin
    if (h_pos == 799) begin h_pos <= 0; v_pos <= (v_pos == 524) ? 0 : v_pos + 1; end
    else h_pos <= h_pos + 1;
end
assign VGA_HS = ~((h_pos >= 656) && (h_pos < 752));
assign VGA_VS = ~((v_pos >= 490) && (v_pos < 492));

reg [2:0] fetch_trigger = 0; always @(posedge clk_sys) fetch_trigger <= {fetch_trigger[1:0], (h_pos == 1)};
wire do_fetch = (fetch_trigger[2:1] == 2'b01);
wire [10:0] line_to_fetch = (v_pos == 524) ? 0 : v_pos + 1;

(* ramstyle = "M9K" *) reg [31:0] vga_buf_0 [0:159];
(* ramstyle = "M9K" *) reg [31:0] vga_buf_1 [0:159];
reg [7:0] vga_wr_ptr; reg vga_wr_en; reg [31:0] vga_wr_data;
always @(posedge clk_sys) if (vga_wr_en)
    if (line_to_fetch[0]) vga_buf_1[vga_wr_ptr] <= vga_wr_data;
    else                  vga_buf_0[vga_wr_ptr] <= vga_wr_data;

wire [7:0] px_idx = h_pos[9:2]; reg [31:0] px_data_0, px_data_1;
always @(posedge clk_vga) begin px_data_0 <= vga_buf_0[px_idx]; px_data_1 <= vga_buf_1[px_idx]; end
wire [31:0] px_word = v_pos[0] ? px_data_1 : px_data_0;
reg [1:0] px_sub; always @(posedge clk_vga) px_sub <= h_pos[1:0];
wire [7:0] pixel = (px_sub==0)?px_word[7:0]:(px_sub==1)?px_word[15:8]:(px_sub==2)?px_word[23:16]:px_word[31:24];

assign VGA_BLANK_N = (h_pos < 640 && v_pos < 480);
wire [23:0] test_color = {h_pos[7:0], v_pos[7:0], 8'hFF};
assign {VGA_R, VGA_G, VGA_B} = SW[16] ? (VGA_BLANK_N ? test_color : 24'h0) : (VGA_BLANK_N ? {3{pixel}} : 24'h0);

// ---------------------------------------------------------------------------
// 4. SDRAM Controller (Rock Solid Version)
// ---------------------------------------------------------------------------
reg [3:0] sd_cmd; reg [12:0] sd_addr_r; reg [1:0] sd_ba_r;
assign {DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N} = sd_cmd;
assign DRAM_ADDR = sd_addr_r; assign DRAM_BA = sd_ba_r;
assign DRAM_CKE = 1'b1; assign DRAM_DQM = 4'b0000;
reg [31:0] sd_dq_out; reg sd_oe = 0; assign DRAM_DQ = sd_oe ? sd_dq_out : 32'bz;
reg [31:0] sd_dq_reg; always @(posedge clk_sys) sd_dq_reg <= DRAM_DQ; // DQ Registration

localparam S_IDLE=0, S_INIT=1, S_REF=2, S_READ=3, S_WRITE=4;
reg [4:0] st = S_INIT; reg [15:0] t_cnt; reg [9:0] ref_timer;
reg [21:0] cur_addr; reg [8:0] burst_cnt; reg [9:0] col_addr;

always @(posedge clk_sys or negedge locked) begin
    if (!locked) begin st <= S_INIT; sd_cmd <= 4'b0111; sd_oe <= 0; ref_timer <= 0; t_cnt <= 0; end
    else begin
        sd_cmd <= 4'b0111; sd_oe <= 0; vga_wr_en <= 0; fifo_rd <= 0;
        if (ref_timer < 780) ref_timer <= ref_timer + 1;
        case (st)
            S_INIT: begin
                t_cnt <= t_cnt + 1;
                if (t_cnt == 20000) begin sd_cmd <= 4'b0010; sd_addr_r <= 13'h0400; end // PRECHARGE ALL
                if (t_cnt == 20010) begin sd_cmd <= 4'b0001; end // REFRESH 1
                if (t_cnt == 20020) begin sd_cmd <= 4'b0001; end // REFRESH 2
                if (t_cnt == 20030) begin sd_cmd <= 4'b0000; sd_addr_r <= 13'h0030; end // MRS: CAS=3, Burst=1
                if (t_cnt == 20050) st <= S_IDLE;
            end
            S_IDLE: begin
                if (ref_timer >= 780) begin ref_timer <= 0; st <= S_REF; end
                else if (do_fetch && line_to_fetch < 480) begin
                    cur_addr <= {3'd0, line_to_fetch[8:0], 10'd0}; 
                    burst_cnt <= 0; vga_wr_ptr <= 0; st <= S_READ;
                end
                else if (!fifo_empty && fifo_used >= 32) begin
                    cur_addr <= fifo_q[53:32];
                    burst_cnt <= 0; st <= S_WRITE;
                end
            end
            S_REF: begin sd_cmd <= 4'b0001; t_cnt <= 0; st <= 10; end
            10: if (t_cnt == 8) st <= S_IDLE; else t_cnt <= t_cnt + 1;
            S_READ: begin // ACTIVE
                sd_cmd <= 4'b0011; sd_ba_r <= cur_addr[21:20]; sd_addr_r <= {3'd0, cur_addr[19:10]}; 
                col_addr <= cur_addr[9:0]; t_cnt <= 0; st <= 11;
            end
            11: if (t_cnt == 3) st <= 12; else t_cnt <= t_cnt + 1; // Wait tRCD
            12: begin // READ
                sd_cmd <= 4'b0101; sd_ba_r <= cur_addr[21:20]; sd_addr_r <= {3'd0, col_addr}; 
                col_addr <= col_addr + 1; burst_cnt <= burst_cnt + 1;
                t_cnt <= 0; st <= 13;
            end
            13: if (t_cnt == 3) st <= 14; else t_cnt <= t_cnt + 1; // Wait CAS=3
            14: begin 
                vga_wr_data <= sd_dq_reg; vga_wr_en <= 1; vga_wr_ptr <= vga_wr_ptr + 1;
                if (burst_cnt >= 160) st <= 15; else st <= 12;
            end
            15: begin sd_cmd <= 4'b0010; sd_ba_r <= cur_addr[21:20]; sd_addr_r <= 13'h0400; t_cnt <= 0; st <= 16; end // PRE ALL
            16: if (t_cnt == 3) st <= S_IDLE; else t_cnt <= t_cnt + 1; // Wait tRP
            S_WRITE: begin // ACTIVE
                sd_cmd <= 4'b0011; sd_ba_r <= cur_addr[21:20]; sd_addr_r <= {3'd0, cur_addr[19:10]}; 
                col_addr <= cur_addr[9:0]; t_cnt <= 0; st <= 17;
            end
            17: if (t_cnt == 3) st <= 18; else t_cnt <= t_cnt + 1; // Wait tRCD
            18: begin // WRITE
                sd_cmd <= 4'b0100; sd_ba_r <= cur_addr[21:20]; sd_addr_r <= {3'd0, col_addr}; 
                sd_dq_out <= fifo_q[31:0]; sd_oe <= 1;
                fifo_rd <= 1; col_addr <= col_addr + 1; burst_cnt <= burst_cnt + 1; st <= 19;
            end
            19: if (burst_cnt >= 32 || fifo_empty) st <= 20; else st <= 18;
            20: begin sd_cmd <= 4'b0010; sd_ba_r <= cur_addr[21:20]; sd_addr_r <= 13'h0400; t_cnt <= 0; st <= 21; end
            21: if (t_cnt == 3) st <= S_IDLE; else t_cnt <= t_cnt + 1;
            default: st <= S_IDLE;
        endcase
    end
end

// Debug Signals
reg rx_seen = 0; always @(posedge clk_125) if (rx_tvalid) rx_seen <= 1;
reg [26:0] hb_cnt; always @(posedge clk_sys) hb_cnt <= hb_cnt + 1;
reg [24:0] rx_clk_cnt; always @(posedge ENET_RX_CLK) rx_clk_cnt <= rx_clk_cnt + 1;

assign LEDG[0] = phy_ready; assign LEDG[1] = rx_seen; assign LEDG[2] = word_valid;
assign LEDG[3] = fifo_empty; assign LEDG[4] = rx_error; assign LEDG[5] = locked;
assign LEDG[6] = pll_eth_locked; assign LEDG[7] = VGA_BLANK_N; assign LEDG[8] = hb_cnt[26];

assign LEDR[4:0] = st; assign LEDR[5] = do_fetch; assign LEDR[6] = fifo_rd;
assign LEDR[7] = vga_wr_en; assign LEDR[8] = sd_oe; assign LEDR[9] = (ref_timer >= 780);
assign LEDR[10] = rx_clk_cnt[24]; assign LEDR[15:11] = word_addr[4:0]; assign LEDR[17:16] = mac_speed;

// HEX Debug
function [6:0] sseg(input [3:0] val);
    case(val)
        4'h0: sseg = 7'b1000000; 4'h1: sseg = 7'b1111001; 4'h2: sseg = 7'b0100100; 4'h3: sseg = 7'b0110000;
        4'h4: sseg = 7'b0011001; 4'h5: sseg = 7'b0010010; 4'h6: sseg = 7'b0000010; 4'h7: sseg = 7'b1111000;
        4'h8: sseg = 7'b0000000; 4'h9: sseg = 7'b0010000; 4'hA: sseg = 7'b0001000; 4'hB: sseg = 7'b0000011;
        4'hC: sseg = 7'b1000110; 4'hD: sseg = 7'b0100001; 4'hE: sseg = 7'b0000110; 4'hF: sseg = 7'b0001110;
        default: sseg = 7'b1111111;
    endcase
endfunction

assign HEX7 = sseg(udp_port_detect[15:12]); assign HEX6 = sseg(udp_port_detect[11:8]);
assign HEX5 = sseg(udp_port_detect[7:4]);  assign HEX4 = sseg(udp_port_detect[3:0]);
assign HEX3 = sseg(raw_capture[31:28]);   assign HEX2 = sseg(raw_capture[27:24]);
assign HEX1 = sseg(raw_capture[23:20]);   assign HEX0 = sseg(raw_capture[19:16]);

endmodule
