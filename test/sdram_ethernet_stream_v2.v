// ==========================================================================
// ETHERNET IMAGE STREAMING v2 → SDRAM → VGA
// Board: DE2i-150 | PHY: Marvell 88E1111 MII 100Mbps
// Ảnh 320×240 RGB565 qua UDP → SDRAM → VGA 640×480 @60Hz
// NÂNG CẤP: Triple Buffer + DCFIFO IP + Burst Write Mode
// ==========================================================================
module sdram_ethernet_stream_v2(
	//////////// CLOCK //////////
	input           CLOCK_50,
	input           CLOCK2_50,
	input           CLOCK3_50,
	//////////// LED //////////
	output [8:0]    LEDG,
	output [17:0]   LEDR,
	//////////// KEY //////////
	input  [3:0]    KEY,
	//////////// SW //////////
	input  [17:0]   SW,
	//////////// SEG7 //////////
	output [6:0]    HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
	//////////// VGA //////////
	output [7:0]    VGA_B,
	output          VGA_BLANK_N,
	output          VGA_CLK,
	output [7:0]    VGA_G,
	output          VGA_HS,
	output [7:0]    VGA_R,
	output          VGA_SYNC_N,
	output          VGA_VS,
	//////////// Ethernet //////////
	output          ENET_GTX_CLK,
	input           ENET_INT_N,
	input           ENET_LINK100,
	output          ENET_MDC,
	inout           ENET_MDIO,
	output          ENET_RST_N,
	input           ENET_RX_CLK,
	input           ENET_RX_COL,
	input           ENET_RX_CRS,
	input  [3:0]    ENET_RX_DATA,
	input           ENET_RX_DV,
	input           ENET_RX_ER,
	input           ENET_TX_CLK,
	output [3:0]    ENET_TX_DATA,
	output          ENET_TX_EN,
	output          ENET_TX_ER,
	//////////// SDRAM //////////
	output [12:0]   DRAM_ADDR,
	output [1:0]    DRAM_BA,
	output          DRAM_CAS_N,
	output          DRAM_CKE,
	output          DRAM_CLK,
	output          DRAM_CS_N,
	inout  [31:0]   DRAM_DQ,
	output [3:0]    DRAM_DQM,
	output          DRAM_RAS_N,
	output          DRAM_WE_N,
	//////////// Fan //////////
	inout           FAN_CTRL
);

// ==========================================================================
// 1. PLL: 50MHz → 100MHz + 100MHz(-3ns) + 25MHz + 25MHz(-10ns)
// ==========================================================================
wire clk, clk_sdram, vga_clk, vga_clk_dac, pll_locked;
sdram_pll pll_inst (
	.inclk0(CLOCK_50), .c0(clk), .c1(clk_sdram), .c2(vga_clk), .c3(vga_clk_dac), .locked(pll_locked)
);
assign DRAM_CLK   = clk_sdram;
assign VGA_CLK    = vga_clk_dac;  
assign VGA_SYNC_N = 1'b0;
assign FAN_CTRL   = 1'bz;

// ==========================================================================
// 2. PHY RESET + MDIO (MDIO_INIT force 100Mbps)
// ==========================================================================
reg [21:0] rst_cnt = 0;
reg phy_rst_n = 0;
always @(posedge CLOCK_50) begin
	if (rst_cnt < 22'd2_000_000) begin rst_cnt <= rst_cnt + 1; phy_rst_n <= 0; end
	else phy_rst_n <= 1;
end
assign ENET_RST_N   = phy_rst_n;
assign ENET_GTX_CLK = 1'b0;
assign ENET_TX_DATA = 4'd0;
assign ENET_TX_EN   = 1'b0;
assign ENET_TX_ER   = 1'b0;

wire mdio_out, mdio_en, mdio_done;
mdio_init phy_mdio_config (
	.clk(CLOCK_50), .rst_n(phy_rst_n),
	.mdc(ENET_MDC), .mdio_out(mdio_out), .mdio_en(mdio_en), .done(mdio_done)
);
assign ENET_MDIO = mdio_en ? mdio_out : 1'bz;

// ==========================================================================
// 3. TRIPLE BUFFER MANAGEMENT
// Frame 0: Bank 0 | Frame 1: Bank 1 | Frame 2: Bank 2
// ==========================================================================
reg [1:0] wr_frame = 0;       // Frame Ethernet đang ghi
reg [1:0] ready_frame_eth = 0; // Frame vừa ghi xong, chờ VGA đọc
reg [1:0] rd_frame = 0;       // Frame VGA đang đọc

// Sync rd_frame từ SDRAM domain (100MHz) -> Ethernet domain (25MHz) để tìm frame rảnh
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [1:0] rd_frame_eth_s1, rd_frame_eth_s2;
always @(posedge ENET_RX_CLK) begin
    rd_frame_eth_s1 <= rd_frame;
    rd_frame_eth_s2 <= rd_frame_eth_s1;
end
wire [1:0] rd_frame_sync = rd_frame_eth_s2;

// ==========================================================================
// 4. ETHERNET RX FSM (MII 100Mbps)
// Giao thức: [Magic 55 AA] [Offset 3B] [Pixels...]
// ==========================================================================
reg [1:0]  rx_state = 0; 
reg [11:0] rx_byte_cnt = 0;
reg [3:0]  prev_nib = 0;
reg        rx_nib_hi = 0;
reg [7:0]  pkt_cnt = 0;
reg [23:0] hdr_offset = 0;
wire [23:0] full_offset = {hdr_offset[23:8], ENET_RX_DATA, prev_nib};

reg [23:0] pixels_temp = 0;          
reg [1:0]  pix_idx = 0; 
reg [18:0] wr_sdram_addr = 0; // Word offset trong frame (18-bit)

// --- Tín hiệu DCFIFO ---
wire        fifo_wr;          
wire [51:0] fifo_din;         // {bank[1:0], offset[17:0], data[31:0]}
wire        fifo_full;        
reg         fifo_rd = 0;      
wire [51:0] fifo_dout;        
wire        fifo_empty;       
wire [7:0]  fifo_rdusedw;     

// DCFIFO Instantiation
dcfifo #(
    .intended_device_family ("Cyclone IV GX"),
    .lpm_numwords           (256),
    .lpm_showahead          ("ON"),
    .lpm_type               ("dcfifo"),
    .lpm_width              (52),
    .lpm_widthu             (8),
    .overflow_checking      ("ON"),
    .underflow_checking     ("ON"),
    .use_eab                ("ON")
) eth_dcfifo (
    .wrclk   (ENET_RX_CLK),
    .rdclk   (clk),
    .wrreq   (fifo_wr),
    .rdreq   (fifo_rd),
    .data    (fifo_din),
    .q       (fifo_dout),
    .wrfull  (fifo_full),
    .rdempty (fifo_empty),
    .rdusedw (fifo_rdusedw),
    .aclr    (~pll_locked)
);

assign fifo_din = {wr_frame, wr_sdram_addr[17:0], {ENET_RX_DATA, prev_nib}, pixels_temp};
assign fifo_wr  = (rx_state == 2 && rx_byte_cnt >= 47 && pix_idx == 3 && rx_nib_hi == 1 && !fifo_full);

always @(posedge ENET_RX_CLK) begin
	if (!ENET_RX_DV) begin
		if (rx_state == 2) pkt_cnt <= pkt_cnt + 1; 
		rx_state  <= 0; pix_idx   <= 0; rx_nib_hi <= 0;
	end else begin
		if (rx_state == 0) begin
			if (ENET_RX_DATA == 4'hD && prev_nib == 4'h5) begin
				rx_state <= 1; rx_byte_cnt <= 0; rx_nib_hi <= 0;
			end
			prev_nib <= ENET_RX_DATA;
		end 
        else begin
			if (rx_nib_hi == 0) begin
				prev_nib  <= ENET_RX_DATA; rx_nib_hi <= 1;
			end else begin
				rx_nib_hi <= 0;
                if (rx_byte_cnt == 42) begin
                    if ({ENET_RX_DATA, prev_nib} != 8'h55) rx_state <= 0; 
                end
                else if (rx_byte_cnt == 43) begin
                    if ({ENET_RX_DATA, prev_nib} != 8'hAA) rx_state <= 0;
                    else rx_state <= 2; 
                end
                else if (rx_state == 2) begin
                    if (rx_byte_cnt == 44) hdr_offset[23:16] <= {ENET_RX_DATA, prev_nib};
                    else if (rx_byte_cnt == 45) hdr_offset[15:8] <= {ENET_RX_DATA, prev_nib};
                    else if (rx_byte_cnt == 46) begin
                        hdr_offset[7:0] <= {ENET_RX_DATA, prev_nib};
                        pix_idx <= 0;
                        if (full_offset == 24'd0) begin
                            ready_frame_eth <= wr_frame; // Frame vừa xong -> sẵn sàng
                            // Tìm frame rảnh (Triple buffer swap)
                            if      (wr_frame != 2'd0 && rd_frame_sync != 2'd0) wr_frame <= 2'd0;
                            else if (wr_frame != 2'd1 && rd_frame_sync != 2'd1) wr_frame <= 2'd1;
                            else                                                  wr_frame <= 2'd2;
                            wr_sdram_addr <= 19'd0;
                        end else begin
                            wr_sdram_addr <= full_offset[18:1]; 
                        end
                    end
                    else if (rx_byte_cnt >= 47) begin
                        if (pix_idx == 0) begin pixels_temp[7:0] <= {ENET_RX_DATA, prev_nib}; pix_idx <= 1; end
                        else if (pix_idx == 1) begin pixels_temp[15:8] <= {ENET_RX_DATA, prev_nib}; pix_idx <= 2; end
                        else if (pix_idx == 2) begin pixels_temp[23:16] <= {ENET_RX_DATA, prev_nib}; pix_idx <= 3; end
                        else begin
                            wr_sdram_addr <= wr_sdram_addr + 1'b1;
                            pix_idx <= 0;
                        end
                    end
                end
				rx_byte_cnt <= rx_byte_cnt + 1;
			end
		end
	end
end

// ==========================================================================
// 5. VGA TIMING & SYNC
// ==========================================================================
localparam H_VISIBLE=640, H_FRONT=16, H_SYNC_W=96, H_BACK=48, H_TOTAL=800;
localparam V_VISIBLE=480, V_FRONT=10, V_SYNC_W=2,  V_BACK=33, V_TOTAL=525;

reg [9:0]  h_cnt = 0;
reg [10:0] v_cnt = 0;
always @(posedge vga_clk) begin
	if (h_cnt == H_TOTAL-1) begin
		h_cnt <= 0;
		v_cnt <= (v_cnt == V_TOTAL-1) ? 0 : v_cnt + 1;
	end else h_cnt <= h_cnt + 1;
end
assign VGA_HS = ~((h_cnt >= H_VISIBLE+H_FRONT) && (h_cnt < H_VISIBLE+H_FRONT+H_SYNC_W));
assign VGA_VS = ~((v_cnt >= V_VISIBLE+V_FRONT) && (v_cnt < V_VISIBLE+V_FRONT+V_SYNC_W));

reg h_cnt_zero_vga;
always @(posedge vga_clk) h_cnt_zero_vga <= (h_cnt == 0);
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) 
reg h_zero_s1=0, h_zero_s2=0, h_zero_s3=0;
always @(posedge clk) begin h_zero_s1 <= h_cnt_zero_vga; h_zero_s2 <= h_zero_s1; h_zero_s3 <= h_zero_s2; end
wire start_fetch = (h_zero_s3 == 0 && h_zero_s2 == 1);

reg [10:0] v_cnt_latched;
always @(posedge vga_clk) if (h_cnt == 1) v_cnt_latched <= v_cnt;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) 
reg [10:0] v_cnt_s1=0, v_cnt_s2=0;
always @(posedge clk) begin v_cnt_s1 <= v_cnt_latched; v_cnt_s2 <= v_cnt_s1; end

// TRIPLE BUFFER VGA SWAP (V-Blank)
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [1:0] ready_frame_s1, ready_frame_s2;
always @(posedge clk) begin ready_frame_s1 <= ready_frame_eth; ready_frame_s2 <= ready_frame_s1; end

always @(posedge clk) begin
    if (v_cnt_s2 >= V_VISIBLE) rd_frame <= ready_frame_s2;
end

wire [10:0] fetch_line = (v_cnt_s2 == V_TOTAL-1) ? 11'd0 : (v_cnt_s2 + 1);
wire write_to_buf_B  = fetch_line[0];
wire read_from_buf_B = v_cnt[0];

wire [31:0] dq_in = DRAM_DQ;
reg fetch_req = 0;
always @(posedge clk or negedge pll_locked) begin
    if (!pll_locked) fetch_req <= 0;
    else begin
        if (start_fetch && fetch_line < 480) fetch_req <= 1'b1;
        if (state == 11 && disp_words_read == 0) fetch_req <= 1'b0; // ST_DISP_ACT
    end
end

// ==========================================================================
// 6. DOUBLE LINE BUFFER (RGB565)
// ==========================================================================
(* ramstyle = "M9K" *) reg [31:0] line_buf_A [0:319];
(* ramstyle = "M9K" *) reg [31:0] line_buf_B [0:319];
reg [8:0]  buf_wr_ptr; reg buf_wr_en; reg [31:0] buf_wr_data;
always @(posedge clk) begin
	if (buf_wr_en) begin
		if (write_to_buf_B) line_buf_B[buf_wr_ptr] <= buf_wr_data;
		else                line_buf_A[buf_wr_ptr] <= buf_wr_data;
	end
end
wire [7:0] rd_idx = h_cnt[9:2]; // 2x horizontal: 640 VGA pixels -> 160 words
reg [31:0] rd_data_A, rd_data_B;
always @(posedge vga_clk) begin rd_data_A <= line_buf_A[rd_idx]; rd_data_B <= line_buf_B[rd_idx]; end

wire [31:0] pixel_word = read_from_buf_B ? rd_data_B : rd_data_A;
reg h_pixel_sel; always @(posedge vga_clk) h_pixel_sel <= h_cnt[1]; // 2x horizontal: mỗi pixel hiển thị 2 lần
wire [15:0] pixel_565 = h_pixel_sel ? pixel_word[31:16] : pixel_word[15:0];
wire [7:0] r8 = {pixel_565[15:11], pixel_565[15:13]};
wire [7:0] g8 = {pixel_565[10:5],  pixel_565[10:9]};
wire [7:0] b8 = {pixel_565[4:0],   pixel_565[4:2]};

reg disp_act_reg; always @(posedge vga_clk) disp_act_reg <= (h_cnt < H_VISIBLE && v_cnt < V_VISIBLE);
reg [7:0] vga_r_reg, vga_g_reg, vga_b_reg; reg vga_blank_reg;
always @(posedge vga_clk) begin
    vga_r_reg <= disp_act_reg ? r8 : 8'd0; vga_g_reg <= disp_act_reg ? g8 : 8'd0; vga_b_reg <= disp_act_reg ? b8 : 8'd0;
    vga_blank_reg <= disp_act_reg;
end
assign VGA_BLANK_N = vga_blank_reg; assign VGA_R = vga_r_reg; assign VGA_G = vga_g_reg; assign VGA_B = vga_b_reg;

// ==========================================================================
// 7. SDRAM FSM (BURST WRITE & TRIPLE BUFFER)
// ==========================================================================
reg [31:0] dq_out; reg dq_oe = 0; assign DRAM_DQ = dq_oe ? dq_out : 32'bz;
localparam CMD_NOP=4'b0111, CMD_ACT=4'b0011, CMD_RD=4'b0101, CMD_WR=4'b0100, CMD_PRE=4'b0010, CMD_REF=4'b0001, CMD_LMR=4'b0000;
reg DRAM_CKE_r, DRAM_CS_N_r, DRAM_RAS_N_r, DRAM_CAS_N_r, DRAM_WE_N_r; reg [12:0] DRAM_ADDR_r; reg [1:0] DRAM_BA_r; reg [3:0] DRAM_DQM_r;
assign DRAM_CKE=DRAM_CKE_r; assign DRAM_CS_N=DRAM_CS_N_r; assign DRAM_RAS_N=DRAM_RAS_N_r; assign DRAM_CAS_N=DRAM_CAS_N_r; assign DRAM_WE_N=DRAM_WE_N_r; assign DRAM_ADDR=DRAM_ADDR_r; assign DRAM_BA=DRAM_BA_r; assign DRAM_DQM=DRAM_DQM_r;

task send_cmd; input [3:0] cmd; begin {DRAM_CS_N_r, DRAM_RAS_N_r, DRAM_CAS_N_r, DRAM_WE_N_r} <= cmd; end endtask

localparam INIT_WAIT=20000, tRP=2, tRFC=7, tMRD=2, tRCD=2, CAS_LAT=2;
localparam MODE_REG = 13'b000_0_00_010_0_000;
localparam [4:0] ST_RESET=0, ST_INIT_WAIT=1, ST_INIT_PRE=2, ST_INIT_PRE_W=3, ST_INIT_REF=4, ST_INIT_REF_W=5, ST_INIT_LM=6, ST_INIT_LM_W=7, ST_IDLE=8, ST_REFRESH=9, ST_REFRESH_W=10, ST_DISP_ACT=11, ST_DISP_ACT_W=12, ST_DISP_RD=13, ST_DISP_CAS_W=14, ST_DISP_CAP=15, ST_DISP_PRE=16, ST_DISP_PRE_W=17, ST_ETH_BURST_ACT=18, ST_ETH_BURST_ACT_W=19, ST_ETH_BURST_WR=20, ST_ETH_BURST_WAIT=21, ST_ETH_BURST_CHECK=22, ST_ETH_BURST_WR_W=23, ST_ETH_BURST_PRE=24, ST_ETH_BURST_PRE_W=25;

reg [4:0] state = ST_RESET; reg [15:0] wait_cnt = 0; reg [9:0] refresh_cnt = 0; localparam REFRESH_IV = 780;
reg [17:0] disp_addr; reg [9:0] disp_words_read;
reg [1:0] burst_bank; reg [8:0] burst_row; reg [6:0] burst_count;
localparam BURST_THRESHOLD = 8, BURST_MAX = 64;

always @(posedge clk or negedge pll_locked) begin
	if (!pll_locked) begin
		state <= ST_RESET; DRAM_CKE_r <= 0; send_cmd(CMD_NOP); DRAM_BA_r <= 0; DRAM_ADDR_r <= 0; DRAM_DQM_r <= 4'b1111; dq_oe <= 0; buf_wr_en <= 0; refresh_cnt <= 0; fifo_rd <= 0;
	end else begin
		send_cmd(CMD_NOP); dq_oe <= 0; buf_wr_en <= 0; fifo_rd <= 0;
		if (refresh_cnt < REFRESH_IV) refresh_cnt <= refresh_cnt + 1;
		case (state)
			ST_RESET: begin DRAM_CKE_r<=1; DRAM_DQM_r<=0; wait_cnt<=0; state<=ST_INIT_WAIT; end
			ST_INIT_WAIT: if(wait_cnt==INIT_WAIT[15:0]) begin wait_cnt<=0; state<=ST_INIT_PRE; end else wait_cnt<=wait_cnt+1;
			ST_INIT_PRE: begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_INIT_PRE_W; end
			ST_INIT_PRE_W: if(wait_cnt==tRP[15:0]) begin wait_cnt<=0; state<=ST_INIT_REF; end else wait_cnt<=wait_cnt+1;
			ST_INIT_REF: begin send_cmd(CMD_REF); wait_cnt<=0; state<=ST_INIT_REF_W; end
			ST_INIT_REF_W: if(wait_cnt==tRFC[15:0]) begin wait_cnt<=0; state<=ST_INIT_LM; end else wait_cnt<=wait_cnt+1;
			ST_INIT_LM: begin send_cmd(CMD_LMR); DRAM_BA_r<=0; DRAM_ADDR_r<=MODE_REG; wait_cnt<=0; state<=ST_INIT_LM_W; end
			ST_INIT_LM_W: if(wait_cnt==tMRD[15:0]) state<=ST_IDLE; else wait_cnt<=wait_cnt+1;
			ST_IDLE: begin
				if (fetch_req) begin disp_addr <= fetch_line[10:1] * 10'd160; disp_words_read <= 0; buf_wr_ptr <= 0; state <= ST_DISP_ACT; end // 2x vertical: fetch_line/2 * 160 words/line
				else if (refresh_cnt >= REFRESH_IV) begin refresh_cnt <= 0; state <= ST_REFRESH; end
				else if (!fifo_empty && fifo_rdusedw >= BURST_THRESHOLD) begin burst_bank <= fifo_dout[51:50]; burst_row <= fifo_dout[49:41]; state <= ST_ETH_BURST_ACT; end
			end
			ST_REFRESH: begin send_cmd(CMD_REF); wait_cnt<=0; state<=ST_REFRESH_W; end
			ST_REFRESH_W: if(wait_cnt==tRFC[15:0]) begin wait_cnt<=0; state<=ST_IDLE; end else wait_cnt<=wait_cnt+1;
			ST_DISP_ACT: begin send_cmd(CMD_ACT); DRAM_BA_r <= rd_frame; DRAM_ADDR_r <= {4'd0, disp_addr[17:9]}; wait_cnt<=0; state<=ST_DISP_ACT_W; end
			ST_DISP_ACT_W: if(wait_cnt==tRCD[15:0]) begin wait_cnt<=0; state<=ST_DISP_RD; end else wait_cnt<=wait_cnt+1;
			ST_DISP_RD: begin send_cmd(CMD_RD); DRAM_ADDR_r <= {4'd0, disp_addr[8:0]}; DRAM_ADDR_r[10] <= 0; disp_addr <= disp_addr + 1; disp_words_read <= disp_words_read + 1; wait_cnt <= 0; state <= ST_DISP_CAS_W; end
			ST_DISP_CAS_W: if(wait_cnt==CAS_LAT[15:0]) state<=ST_DISP_CAP; else wait_cnt<=wait_cnt+1;
			ST_DISP_CAP: begin buf_wr_data <= dq_in; buf_wr_en <= 1; buf_wr_ptr <= buf_wr_ptr + 1; if (disp_words_read == 160 || disp_addr[8:0] == 0) state <= ST_DISP_PRE; else state <= ST_DISP_RD; end
			ST_DISP_PRE: begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_DISP_PRE_W; end
			ST_DISP_PRE_W: if(wait_cnt==tRP[15:0]) begin if(disp_words_read>=160) state<=ST_IDLE; else state<=ST_DISP_ACT; end else wait_cnt<=wait_cnt+1;
			ST_ETH_BURST_ACT: begin send_cmd(CMD_ACT); DRAM_BA_r <= burst_bank; DRAM_ADDR_r <= {4'd0, burst_row}; wait_cnt<=0; burst_count<=0; state<=ST_ETH_BURST_ACT_W; end
			ST_ETH_BURST_ACT_W: if(wait_cnt==tRCD[15:0]) state <= ST_ETH_BURST_WR; else wait_cnt <= wait_cnt + 1;
			ST_ETH_BURST_WR: begin send_cmd(CMD_WR); DRAM_BA_r <= burst_bank; DRAM_ADDR_r <= {4'd0, fifo_dout[40:32]}; DRAM_ADDR_r[10]<=0; DRAM_DQM_r<=0; dq_out<=fifo_dout[31:0]; dq_oe<=1; burst_count<=burst_count+1; fifo_rd<=1; state<=ST_ETH_BURST_WAIT; end
			ST_ETH_BURST_WAIT: begin dq_oe<=0; state<=ST_ETH_BURST_CHECK; end
			ST_ETH_BURST_CHECK: begin if(fifo_empty || burst_count>=BURST_MAX || fifo_dout[51:50]!=burst_bank || fifo_dout[49:41]!=burst_row) begin wait_cnt<=0; state<=ST_ETH_BURST_WR_W; end else state<=ST_ETH_BURST_WR; end
			ST_ETH_BURST_WR_W: begin dq_oe<=0; if(wait_cnt>=2) state<=ST_ETH_BURST_PRE; else wait_cnt<=wait_cnt+1; end
			ST_ETH_BURST_PRE: begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_ETH_BURST_PRE_W; end
			ST_ETH_BURST_PRE_W: if(wait_cnt==tRP[15:0]) state<=ST_IDLE; else wait_cnt<=wait_cnt+1;
			default: state <= ST_IDLE;
		endcase
	end
end

// ==========================================================================
// 8. DEBUG LED + HEX
// ==========================================================================
assign LEDG[0]=phy_rst_n; assign LEDG[1]=~ENET_LINK100; assign LEDG[2]=ENET_RX_DV; assign LEDG[3]=mdio_done; assign LEDG[4]=pll_locked; assign LEDG[5]=(state>=ST_IDLE); assign LEDG[6]=!fifo_empty; reg [23:0] blink=0; always @(posedge ENET_RX_CLK) blink<=blink+1; assign LEDG[7]=blink[23]; assign LEDG[8]=blink[22]; assign LEDR[0]=fifo_full; assign LEDR[1]=(burst_count>0); assign LEDR[17:2]=0;
function [6:0] seg7; input [3:0] hex; case(hex) 4'h0:seg7=7'b1000000; 4'h1:seg7=7'b1111001; 4'h2:seg7=7'b0100100; 4'h3:seg7=7'b0110000; 4'h4:seg7=7'b0011001; 4'h5:seg7=7'b0010010; 4'h6:seg7=7'b0000010; 4'h7:seg7=7'b1111000; 4'h8:seg7=7'b0000000; 4'h9:seg7=7'b0010000; 4'hA:seg7=7'b0001000; 4'hB:seg7=7'b0000011; 4'hC:seg7=7'b1000110; 4'hD:seg7=7'b0100001; 4'hE:seg7=7'b0000110; 4'hF:seg7=7'b0001110; default:seg7=7'b1111111; endcase endfunction
assign HEX7=seg7({2'd0, wr_frame}); assign HEX6=seg7({2'd0, rd_frame}); assign HEX5=seg7(pkt_cnt[7:4]); assign HEX4=seg7(pkt_cnt[3:0]); assign HEX3=seg7({3'd0, state[4]}); assign HEX2=seg7(state[3:0]); assign HEX1=seg7(burst_count[6:4]); assign HEX0=seg7(burst_count[3:0]);
endmodule
