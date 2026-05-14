// sdram_ethernet_stream_v3.v
// Top Module: Direct GigE Vision Camera -> SDRAM -> VGA (No PC)
// Board: DE2i-150 | Camera: Mako G-040C | Protocol: GVSP Mono8
// Date: 2025-05-09

module sdram_ethernet_stream_v3(
    input           CLOCK_50, CLOCK2_50, CLOCK3_50,
    output [8:0]    LEDG,
    output [17:0]   LEDR,
    input  [3:0]    KEY,
    input  [17:0]   SW,
    output [6:0]    HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
    output [7:0]    VGA_B, VGA_G, VGA_R,
    output          VGA_BLANK_N, VGA_CLK, VGA_HS, VGA_SYNC_N, VGA_VS,
    output          ENET_GTX_CLK, ENET_MDC, ENET_RST_N,
    output [3:0]    ENET_TX_DATA,
    output          ENET_TX_EN, ENET_TX_ER,
    input           ENET_INT_N, ENET_LINK100,
    inout           ENET_MDIO,
    input           ENET_RX_CLK,
    input           ENET_RX_COL, ENET_RX_CRS,
    input  [3:0]    ENET_RX_DATA,
    input           ENET_RX_DV, ENET_RX_ER,
    input           ENET_TX_CLK,
    output [12:0]   DRAM_ADDR,
    output [1:0]    DRAM_BA,
    output          DRAM_CAS_N, DRAM_CKE, DRAM_CLK, DRAM_CS_N,
    inout  [31:0]   DRAM_DQ,
    output [3:0]    DRAM_DQM,
    output          DRAM_RAS_N, DRAM_WE_N,
    inout           FAN_CTRL
);

// ==========================================================================
// 1. PLL
// ==========================================================================
wire clk, clk_sdram, vga_clk, vga_clk_dac, pll_locked;
sdram_pll pll_inst (
    .inclk0(CLOCK_50), .c0(clk), .c1(clk_sdram),
    .c2(vga_clk), .c3(vga_clk_dac), .locked(pll_locked)
);
assign DRAM_CLK = clk_sdram;
assign VGA_CLK  = vga_clk_dac;
assign VGA_SYNC_N = 1'b0;
assign FAN_CTRL   = 1'bz;

// --- SỬA LỖI TX CLOCK (RGMII MODE) ---
// Trong RGMII, FPGA PHẢI CẤP xung TX (GTX_CLK) cho PHY.
// Tốc độ 100Mbps cần xung 25MHz.
reg clk_25_tx = 0;
always @(posedge CLOCK_50) clk_25_tx <= ~clk_25_tx;
assign ENET_GTX_CLK = clk_25_tx;

assign ENET_TX_ER   = 1'b0;

// ==========================================================================
// 2. PHY RESET + MDIO (force 100Mbps)
// ==========================================================================
reg [23:0] rst_cnt = 0;
reg phy_rst_n = 0;
always @(posedge CLOCK_50)
    if (rst_cnt < 24'd10_000_000) begin rst_cnt <= rst_cnt+1; phy_rst_n <= 0; end
    else phy_rst_n <= 1;
assign ENET_RST_N = phy_rst_n;

wire mdio_out, mdio_en, mdio_done;
mdio_init phy_mdio (
    .clk(CLOCK_50), .rst_n(phy_rst_n),
    .mdc(ENET_MDC), .mdio_out(mdio_out), .mdio_en(mdio_en), .done(mdio_done)
);
assign ENET_MDIO = mdio_en ? mdio_out : 1'bz;

wire link_up = ~ENET_LINK100; // Active-LOW: 0 = 100Mbps link up

// ==========================================================================
// 3. TX MUX: ARP hoặc GVCP dùng chung eth_tx_mii
// ==========================================================================
wire        tx_busy;
wire [10:0] tx_len_arp,  tx_len_gvcp;
wire        tx_start_arp, tx_start_gvcp;
wire [10:0] buf_addr_tx;
wire [7:0]  buf_data_arp, buf_data_gvcp;

// ARP co uu tien cao hon GVCP
wire gvcp_done;

reg tx_is_arp = 0;
always @(posedge clk_25_tx) begin
    if (tx_start_arp) tx_is_arp <= 1'b1;
    else if (tx_start_gvcp) tx_is_arp <= 1'b0;
end

wire tx_start_mux  = tx_start_arp | tx_start_gvcp;
wire [10:0] tx_len_mux = tx_is_arp ? tx_len_arp : tx_len_gvcp;
wire [7:0]  buf_data_mux = tx_is_arp ? buf_data_arp : buf_data_gvcp;

eth_tx_mii tx_eng (
    .clk_25(clk_25_tx), .rst_n(phy_rst_n),
    .tx_len(tx_len_mux), .tx_start(tx_start_mux), .tx_busy(tx_busy),
    .buf_addr(buf_addr_tx), .buf_data(buf_data_mux),
    .MII_TX_DATA(ENET_TX_DATA), .MII_TX_EN(ENET_TX_EN)
);

arp_responder arp_mod (
    .clk_25(clk_25_tx), .rst_n(phy_rst_n), .link_up(link_up),
    .RX_DATA(ENET_RX_DATA), .RX_DV(ENET_RX_DV),
    .tx_start(tx_start_arp), .tx_len(tx_len_arp), .tx_busy(tx_busy),
    .buf_addr(buf_addr_tx), .buf_data(buf_data_arp)
);

wire [2:0] gvcp_state_dbg;
wire [3:0] gvcp_cmd_idx_dbg; // 4-bit

gvcp_init gvcp_mod (
    .clk_25(clk_25_tx), .rst_n(phy_rst_n),
    .link_up(link_up), .arp_done(mdio_done),
    .trigger(SW[0]),
    .done(gvcp_done),
    .gvcp_state_out(gvcp_state_dbg),
    .gvcp_cmd_idx(gvcp_cmd_idx_dbg),
    .tx_start(tx_start_gvcp), .tx_len(tx_len_gvcp), .tx_busy(tx_busy),
    .buf_addr(buf_addr_tx), .buf_data(buf_data_gvcp)
);

// ==========================================================================
// 4. GVSP RX + Pixel Convert
// ==========================================================================
wire        frame_start_gvsp, frame_done_gvsp;
wire [7:0]  pixel_mono;
wire        pixel_valid_gvsp;
wire [18:0] pixel_addr_gvsp;

gvsp_rx gvsp_mod (
    .clk_eth(ENET_RX_CLK), .rst_n(phy_rst_n),
    .RX_DATA(ENET_RX_DATA), .RX_DV(ENET_RX_DV),
    .frame_start(frame_start_gvsp), .frame_done(frame_done_gvsp),
    .pixel_data(pixel_mono), .pixel_valid(pixel_valid_gvsp),
    .pixel_addr(pixel_addr_gvsp), .pkt_count(gvsp_pkt_cnt)
);

wire [31:0] word_out_conv;
wire        word_valid_conv;
wire [18:0] word_addr_conv;
wire        frame_start_conv;

mono8_to_rgb565 conv_mod (
    .clk(ENET_RX_CLK), .rst_n(phy_rst_n),
    .pixel_in(pixel_mono), .pixel_valid(pixel_valid_gvsp),
    .frame_start(frame_start_gvsp),
    .word_out(word_out_conv), .word_valid(word_valid_conv),
    .word_addr(word_addr_conv), .frame_start_out(frame_start_conv)
);

// ==========================================================================
// 5. DCFIFO: Cross clock domain ETH (25MHz) -> SDRAM (100MHz)
// ==========================================================================
wire [51:0] fifo_din  = {wr_frame, word_addr_conv[17:0], word_out_conv};
wire        fifo_wr   = word_valid_conv & !fifo_full;
wire        fifo_full, fifo_empty;
wire [51:0] fifo_dout;
wire [7:0]  fifo_rdusedw;
reg         fifo_rd = 0;

dcfifo #(
    .intended_device_family("Cyclone IV GX"),
    .lpm_numwords(256), .lpm_showahead("ON"),
    .lpm_type("dcfifo"), .lpm_width(52), .lpm_widthu(8),
    .overflow_checking("ON"), .underflow_checking("ON"), .use_eab("ON")
) eth_dcfifo_v3 (
    .wrclk(ENET_RX_CLK), .rdclk(clk),
    .wrreq(fifo_wr), .rdreq(fifo_rd),
    .data(fifo_din), .q(fifo_dout),
    .wrfull(fifo_full), .rdempty(fifo_empty),
    .rdusedw(fifo_rdusedw), .aclr(~pll_locked)
);

// ==========================================================================
// 6. TRIPLE BUFFER MANAGEMENT
// ==========================================================================
reg [1:0] wr_frame = 0, ready_frame_eth = 0, rd_frame = 0;

(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [1:0] rd_frame_eth_s1, rd_frame_eth_s2;
always @(posedge ENET_RX_CLK) begin
    rd_frame_eth_s1 <= rd_frame;
    rd_frame_eth_s2 <= rd_frame_eth_s1;
end
wire [1:0] rd_frame_sync = rd_frame_eth_s2;

// Swap buffer khi frame_start
always @(posedge ENET_RX_CLK) begin
    if (frame_start_conv) begin
        ready_frame_eth <= wr_frame;
        if      (wr_frame != 2'd0 && rd_frame_sync != 2'd0) wr_frame <= 2'd0;
        else if (wr_frame != 2'd1 && rd_frame_sync != 2'd1) wr_frame <= 2'd1;
        else                                                 wr_frame <= 2'd2;
    end
end

// ==========================================================================
// 7. VGA TIMING
// ==========================================================================
localparam H_VISIBLE=640, H_FRONT=16, H_SYNC_W=96, H_BACK=48, H_TOTAL=800;
localparam V_VISIBLE=480, V_FRONT=10, V_SYNC_W=2,  V_BACK=33, V_TOTAL=525;
reg [9:0] h_cnt=0; reg [10:0] v_cnt=0;
always @(posedge vga_clk) begin
    if (h_cnt==H_TOTAL-1) begin h_cnt<=0; v_cnt<=(v_cnt==V_TOTAL-1)?0:v_cnt+1; end
    else h_cnt<=h_cnt+1;
end
assign VGA_HS = ~((h_cnt>=H_VISIBLE+H_FRONT) && (h_cnt<H_VISIBLE+H_FRONT+H_SYNC_W));
assign VGA_VS = ~((v_cnt>=V_VISIBLE+V_FRONT) && (v_cnt<V_VISIBLE+V_FRONT+V_SYNC_W));

// Cross domain: VGA -> SDRAM
reg h_cnt_zero_vga;
always @(posedge vga_clk) h_cnt_zero_vga <= (h_cnt==0);
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg h_zero_s1=0,h_zero_s2=0,h_zero_s3=0;
always @(posedge clk) begin h_zero_s1<=h_cnt_zero_vga; h_zero_s2<=h_zero_s1; h_zero_s3<=h_zero_s2; end
wire start_fetch = (h_zero_s3==0 && h_zero_s2==1);

reg [10:0] v_cnt_latched;
always @(posedge vga_clk) if (h_cnt==1) v_cnt_latched<=v_cnt;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [10:0] v_cnt_s1=0,v_cnt_s2=0;
always @(posedge clk) begin v_cnt_s1<=v_cnt_latched; v_cnt_s2<=v_cnt_s1; end

// VGA Triple buffer swap (V-Blank)
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [1:0] ready_s1,ready_s2;
always @(posedge clk) begin ready_s1<=ready_frame_eth; ready_s2<=ready_s1; end
always @(posedge clk) if (v_cnt_s2>=V_VISIBLE) rd_frame<=ready_s2;

wire [10:0] fetch_line = (v_cnt_s2==V_TOTAL-1) ? 11'd0 : (v_cnt_s2+1);
wire write_to_buf_B  = fetch_line[0];
wire read_from_buf_B = v_cnt[0];

// ==========================================================================
// 8. DOUBLE LINE BUFFER
// ==========================================================================
(* ramstyle="M9K" *) reg [31:0] line_buf_A [0:159];
(* ramstyle="M9K" *) reg [31:0] line_buf_B [0:159];
reg [8:0] buf_wr_ptr; reg buf_wr_en; reg [31:0] buf_wr_data;
always @(posedge clk) if (buf_wr_en)
    if (write_to_buf_B) line_buf_B[buf_wr_ptr] <= buf_wr_data;
    else                line_buf_A[buf_wr_ptr] <= buf_wr_data;

wire [7:0] rd_idx = (h_cnt < 640) ? h_cnt[9:2] : 8'd0;
reg [31:0] rd_data_A, rd_data_B;
always @(posedge vga_clk) begin rd_data_A<=line_buf_A[rd_idx]; rd_data_B<=line_buf_B[rd_idx]; end
wire [31:0] pixel_word = read_from_buf_B ? rd_data_B : rd_data_A;
reg h_pixel_sel; always @(posedge vga_clk) h_pixel_sel <= h_cnt[1];
wire [15:0] pixel_565 = h_pixel_sel ? pixel_word[31:16] : pixel_word[15:0];
wire [7:0] r8={pixel_565[15:11],pixel_565[15:13]};
wire [7:0] g8={pixel_565[10:5], pixel_565[10:9]};
wire [7:0] b8={pixel_565[4:0],  pixel_565[4:2]};
reg disp_act; always @(posedge vga_clk) disp_act<=(h_cnt<H_VISIBLE && v_cnt<V_VISIBLE);
reg [7:0] vr,vg,vb; reg vblank;
always @(posedge vga_clk) begin
    vr<=disp_act?r8:8'd0; vg<=disp_act?g8:8'd0; vb<=disp_act?b8:8'd0; vblank<=disp_act;
end
assign VGA_R=vr; assign VGA_G=vg; assign VGA_B=vb; assign VGA_BLANK_N=vblank;

// ==========================================================================
// 9. SDRAM FSM
// ==========================================================================
reg [31:0] dq_out; reg dq_oe=0; assign DRAM_DQ=dq_oe?dq_out:32'bz;
wire [31:0] dq_in=DRAM_DQ;
localparam CMD_NOP=4'b0111,CMD_ACT=4'b0011,CMD_RD=4'b0101,CMD_WR=4'b0100,CMD_PRE=4'b0010,CMD_REF=4'b0001,CMD_LMR=4'b0000;
reg DRAM_CKE_r,DRAM_CS_N_r,DRAM_RAS_N_r,DRAM_CAS_N_r,DRAM_WE_N_r;
reg [12:0] DRAM_ADDR_r; reg [1:0] DRAM_BA_r; reg [3:0] DRAM_DQM_r;
assign DRAM_CKE=DRAM_CKE_r; assign DRAM_CS_N=DRAM_CS_N_r;
assign DRAM_RAS_N=DRAM_RAS_N_r; assign DRAM_CAS_N=DRAM_CAS_N_r;
assign DRAM_WE_N=DRAM_WE_N_r; assign DRAM_ADDR=DRAM_ADDR_r;
assign DRAM_BA=DRAM_BA_r; assign DRAM_DQM=DRAM_DQM_r;
task send_cmd; input [3:0] cmd; begin {DRAM_CS_N_r,DRAM_RAS_N_r,DRAM_CAS_N_r,DRAM_WE_N_r}<=cmd; end endtask

localparam INIT_WAIT=20000,tRP=2,tRFC=7,tMRD=2,tRCD=2,CAS_LAT=2;
localparam MODE_REG=13'b000_0_00_010_0_000;
localparam [4:0] ST_RESET=0,ST_INIT_WAIT=1,ST_INIT_PRE=2,ST_INIT_PRE_W=3,
    ST_INIT_REF=4,ST_INIT_REF_W=5,ST_INIT_LM=6,ST_INIT_LM_W=7,ST_IDLE=8,
    ST_REFRESH=9,ST_REFRESH_W=10,ST_DISP_ACT=11,ST_DISP_ACT_W=12,
    ST_DISP_RD=13,ST_DISP_CAS_W=14,ST_DISP_CAP=15,ST_DISP_PRE=16,
    ST_DISP_PRE_W=17,ST_ETH_BURST_ACT=18,ST_ETH_BURST_ACT_W=19,
    ST_ETH_BURST_WR=20,ST_ETH_BURST_WAIT=21,ST_ETH_BURST_CHECK=22,
    ST_ETH_BURST_WR_W=23,ST_ETH_BURST_PRE=24,ST_ETH_BURST_PRE_W=25;

reg [4:0] state=ST_RESET; reg [15:0] wait_cnt=0; reg [9:0] refresh_cnt=0;
reg init_ref_done = 0;
localparam REFRESH_IV=780;
reg [17:0] disp_addr; reg [9:0] disp_words_read;
reg [1:0] burst_bank; reg [8:0] burst_row; reg [6:0] burst_count;
localparam BURST_THRESHOLD=8, BURST_MAX=64;

reg fetch_req=0;
always @(posedge clk or negedge pll_locked) begin
    if (!pll_locked) fetch_req<=0;
    else begin
        if (start_fetch && fetch_line<480) fetch_req<=1'b1;
        if (state==ST_DISP_ACT && disp_words_read==0) fetch_req<=1'b0;
    end
end

always @(posedge clk or negedge pll_locked) begin
    if (!pll_locked) begin
        state<=ST_RESET; DRAM_CKE_r<=0; send_cmd(CMD_NOP);
        DRAM_BA_r<=0; DRAM_ADDR_r<=0; DRAM_DQM_r<=4'b1111;
        dq_oe<=0; buf_wr_en<=0; refresh_cnt<=0; fifo_rd<=0; init_ref_done<=0;
    end else begin
        send_cmd(CMD_NOP); dq_oe<=0; buf_wr_en<=0; fifo_rd<=0;
        if (refresh_cnt<REFRESH_IV) refresh_cnt<=refresh_cnt+1;
        case (state)
        ST_RESET:      begin DRAM_CKE_r<=1; DRAM_DQM_r<=0; wait_cnt<=0; state<=ST_INIT_WAIT; end
        ST_INIT_WAIT:  if(wait_cnt==INIT_WAIT[15:0]) begin wait_cnt<=0; state<=ST_INIT_PRE; end else wait_cnt<=wait_cnt+1;
        ST_INIT_PRE:   begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_INIT_PRE_W; end
        ST_INIT_PRE_W: if(wait_cnt==tRP[15:0]) begin wait_cnt<=0; state<=ST_INIT_REF; end else wait_cnt<=wait_cnt+1;
        ST_INIT_REF:   begin send_cmd(CMD_REF); wait_cnt<=0; state<=ST_INIT_REF_W; end
        ST_INIT_REF_W: if(wait_cnt==tRFC[15:0]) begin wait_cnt<=0; if(!init_ref_done) begin init_ref_done<=1; state<=ST_INIT_REF; end else state<=ST_INIT_LM; end else wait_cnt<=wait_cnt+1;
        ST_INIT_LM:    begin send_cmd(CMD_LMR); DRAM_BA_r<=0; DRAM_ADDR_r<=MODE_REG; wait_cnt<=0; state<=ST_INIT_LM_W; end
        ST_INIT_LM_W:  if(wait_cnt==tMRD[15:0]) state<=ST_IDLE; else wait_cnt<=wait_cnt+1;
        ST_IDLE: begin
            if      (fetch_req) begin disp_addr<=fetch_line[10:1]*10'd160; disp_words_read<=0; buf_wr_ptr<=0; state<=ST_DISP_ACT; end
            else if (refresh_cnt>=REFRESH_IV) begin refresh_cnt<=0; state<=ST_REFRESH; end
            else if (!fifo_empty && fifo_rdusedw>=BURST_THRESHOLD) begin burst_bank<=fifo_dout[51:50]; burst_row<=fifo_dout[49:41]; state<=ST_ETH_BURST_ACT; end
        end
        ST_REFRESH:        begin send_cmd(CMD_REF); wait_cnt<=0; state<=ST_REFRESH_W; end
        ST_REFRESH_W:      if(wait_cnt==tRFC[15:0]) begin wait_cnt<=0; state<=ST_IDLE; end else wait_cnt<=wait_cnt+1;
        ST_DISP_ACT:       begin send_cmd(CMD_ACT); DRAM_BA_r<=rd_frame; DRAM_ADDR_r<={4'd0,disp_addr[17:9]}; wait_cnt<=0; state<=ST_DISP_ACT_W; end
        ST_DISP_ACT_W:     if(wait_cnt==tRCD[15:0]) begin wait_cnt<=0; state<=ST_DISP_RD; end else wait_cnt<=wait_cnt+1;
        ST_DISP_RD:        begin send_cmd(CMD_RD); DRAM_ADDR_r<={4'd0,disp_addr[8:0]}; DRAM_ADDR_r[10]<=0; disp_addr<=disp_addr+1; disp_words_read<=disp_words_read+1; wait_cnt<=0; state<=ST_DISP_CAS_W; end
        ST_DISP_CAS_W:     if(wait_cnt==CAS_LAT[15:0]) state<=ST_DISP_CAP; else wait_cnt<=wait_cnt+1;
        ST_DISP_CAP:       begin buf_wr_data<=dq_in; buf_wr_en<=1; buf_wr_ptr<=buf_wr_ptr+1; if(disp_words_read==160||disp_addr[8:0]==0) state<=ST_DISP_PRE; else state<=ST_DISP_RD; end
        ST_DISP_PRE:       begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_DISP_PRE_W; end
        ST_DISP_PRE_W:     if(wait_cnt==tRP[15:0]) begin if(disp_words_read>=160) state<=ST_IDLE; else state<=ST_DISP_ACT; end else wait_cnt<=wait_cnt+1;
        ST_ETH_BURST_ACT:  begin send_cmd(CMD_ACT); DRAM_BA_r<=burst_bank; DRAM_ADDR_r<={4'd0,burst_row}; wait_cnt<=0; burst_count<=0; state<=ST_ETH_BURST_ACT_W; end
        ST_ETH_BURST_ACT_W:if(wait_cnt==tRCD[15:0]) state<=ST_ETH_BURST_WR; else wait_cnt<=wait_cnt+1;
        ST_ETH_BURST_WR:   begin send_cmd(CMD_WR); DRAM_BA_r<=burst_bank; DRAM_ADDR_r<={4'd0,fifo_dout[40:32]}; DRAM_ADDR_r[10]<=0; DRAM_DQM_r<=0; dq_out<=fifo_dout[31:0]; dq_oe<=1; burst_count<=burst_count+1; fifo_rd<=1; state<=ST_ETH_BURST_WAIT; end
        ST_ETH_BURST_WAIT: begin dq_oe<=0; state<=ST_ETH_BURST_CHECK; end
        ST_ETH_BURST_CHECK:if(fifo_empty||burst_count>=BURST_MAX||fifo_dout[51:50]!=burst_bank||fifo_dout[49:41]!=burst_row) begin wait_cnt<=0; state<=ST_ETH_BURST_WR_W; end else state<=ST_ETH_BURST_WR;
        ST_ETH_BURST_WR_W: begin dq_oe<=0; if(wait_cnt>=2) state<=ST_ETH_BURST_PRE; else wait_cnt<=wait_cnt+1; end
        ST_ETH_BURST_PRE:  begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_ETH_BURST_PRE_W; end
        ST_ETH_BURST_PRE_W:if(wait_cnt==tRP[15:0]) state<=ST_IDLE; else wait_cnt<=wait_cnt+1;
        default: state<=ST_IDLE;
        endcase
    end
end

// ==========================================================================
// 10. DEBUG LED + HEX
// ==========================================================================
// Blink counter (chung nhan la PLL + clock dang hoat dong)
reg [25:0] blink = 0;
always @(posedge CLOCK_50) blink <= blink + 1;

// LEDG: Trang thai khoi dong (sang = OK)
// G0=pll_locked  G1=phy_rst_n  G2=mdio_done  G3=link_up
// G4=gvcp_done   G5=(state>=IDLE)  G6=!fifo_empty  G7=blink(heartbeat)  G8=RX_DV
wire [7:0] gvsp_pkt_cnt;
assign LEDG[0] = pll_locked;
assign LEDG[1] = phy_rst_n;
assign LEDG[4] = gvcp_done;
assign LEDG[3] = link_up;

// DEBUG CLOCK: Kiem tra xem chip PHY co cap xung 25MHz khong
reg [24:0] tx_clk_dbg_cnt = 0;
always @(posedge ENET_TX_CLK) tx_clk_dbg_cnt <= tx_clk_dbg_cnt + 1;
assign LEDG[7] = tx_clk_dbg_cnt[24];

reg [24:0] rx_clk_dbg_cnt = 0;
always @(posedge ENET_RX_CLK) rx_clk_dbg_cnt <= rx_clk_dbg_cnt + 1;
assign LEDG[6] = rx_clk_dbg_cnt[24];

assign LEDG[2] = mdio_done;
assign LEDG[5] = (state >= ST_IDLE);
assign LEDG[8] = blink[24]; // ~3Hz blink

// LEDR: Loi/Canh bao
assign LEDR[0] = fifo_full;
assign LEDR[1] = ENET_RX_DV;  // Nhap nhay khi co data RX
assign LEDR[17:2] = 0;

function [6:0] seg7; input [3:0] h; case(h)
    4'h0:seg7=7'b1000000; 4'h1:seg7=7'b1111001; 4'h2:seg7=7'b0100100;
    4'h3:seg7=7'b0110000; 4'h4:seg7=7'b0011001; 4'h5:seg7=7'b0010010;
    4'h6:seg7=7'b0000010; 4'h7:seg7=7'b1111000; 4'h8:seg7=7'b0000000;
    4'h9:seg7=7'b0010000; 4'hA:seg7=7'b0001000; 4'hB:seg7=7'b0000011;
    4'hC:seg7=7'b1000110; 4'hD:seg7=7'b0100001; 4'hE:seg7=7'b0000110;
    default:seg7=7'b0001110; endcase endfunction
// HEX7-6: wr_frame / rd_frame
// HEX5-4: SDRAM state (hex)
// HEX3-2: burst count
// HEX1-0: gvcp_done + fifo status
assign HEX7=seg7({2'd0,wr_frame}); assign HEX6=seg7({2'd0,rd_frame});
assign HEX5=seg7(state[4:1]);      assign HEX4=seg7({3'd0,state[0]});
assign HEX3=seg7({1'b0, gvcp_state_dbg});   assign HEX2=seg7(gvcp_cmd_idx_dbg);
assign HEX1=seg7({2'd0, pll_locked, phy_rst_n});
assign HEX0=seg7({2'd0, mdio_done, gvcp_done});

endmodule
