// ==========================================================================
// ETHERNET IMAGE STREAMING → SDRAM → VGA
// Board: DE2i-150 | PHY: Marvell 88E1111 MII 100Mbps
// Ảnh 320×240 RGB332 qua UDP → SDRAM → VGA 640×480 @60Hz
// Code cốt lõi (SDRAM FSM + VGA) lấy SÁT NGUYÊN XI từ bài 2 đã chạy OK.
// ==========================================================================
module sdram_ethernet_stream(
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
// 1. PLL: 50MHz → 100MHz + 100MHz(-3ns) + 25MHz
// ==========================================================================
wire clk, clk_sdram, vga_clk, vga_clk_dac, pll_locked;
sdram_pll pll_inst (
	.inclk0(CLOCK_50), .c0(clk), .c1(clk_sdram), .c2(vga_clk), .c3(vga_clk_dac), .locked(pll_locked)
);
assign DRAM_CLK   = clk_sdram;
assign VGA_CLK    = vga_clk_dac;  // Lệch pha -10ns so với vga_clk → DAC lấy mẫu khi data đã sẵn sàng
assign VGA_SYNC_N = 1'b0;
assign FAN_CTRL   = 1'bz;

// ==========================================================================
// 2. PHY RESET + MDIO
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
// 3. ETHERNET RX → Pixel Buffer (Domain: ENET_RX_CLK 25MHz)
//    FSM tự động dò đuôi Preamble (SFD=0xD5) để chốt Byte 0 (MAC Dest).
//    Giao thức: [MAC=14] [IP=20] [UDP=8] [Magic = 55 AA] [Offset=3] [Pixels]
// ==========================================================================
reg [1:0]  rx_state = 0; // 0: Chờ SFD, 1: Đọc Header, 2: Đọc Payload 
reg [11:0] rx_byte_cnt = 0;
reg [3:0]  prev_nib = 0;
reg        rx_nib_hi = 0;
reg [7:0]  pkt_cnt = 0;

// Header 3-byte pixel offset
reg [23:0] hdr_offset = 0;
wire [23:0] full_offset = {hdr_offset[23:8], ENET_RX_DATA, prev_nib};

// Pixel assembly 4-to-1 word
reg [23:0] pixels_temp = 0;          
reg [1:0]  pix_idx = 0; 

// Kết quả ghi vào FIFO
reg [18:0] wr_sdram_addr = 0;    
reg [50:0] eth_fifo [0:127]; /* ramstyle = "M9K" */
reg [6:0]  fifo_wptr = 0;
reg [6:0]  fifo_rptr = 0;

// DOUBLE FRAME BUFFER: Swap toàn bộ bức ảnh để loại bỏ hiệu ứng "vẽ từng dòng"
// RGB565: 640×480 / 2 pixels_per_word = 153,600 words/frame (18 bit)
// Frame A: SDRAM word 0x00000 – 0x257FF  (bit[18]=0)
// Frame B: SDRAM word 0x40000 – 0x657FF  (bit[18]=1)
reg wr_frame = 0;      // Frame mà Ethernet đang ghi vào
reg rd_frame_eth = 0;  // Frame mà VGA sẽ đọc (domain ETH, cần CDC sync)

wire [6:0] rptr_gray = fifo_rptr ^ (fifo_rptr >> 1);
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [6:0] rptr_gray_s1=0, rptr_gray_s2=0;
always @(posedge ENET_RX_CLK) begin
    rptr_gray_s1 <= rptr_gray;
    rptr_gray_s2 <= rptr_gray_s1;
end
reg [6:0] rptr_bin;
always @(*) begin
	rptr_bin[6] = rptr_gray_s2[6];
	rptr_bin[5] = rptr_bin[6]  ^ rptr_gray_s2[5];
	rptr_bin[4] = rptr_bin[5]  ^ rptr_gray_s2[4];
	rptr_bin[3] = rptr_bin[4]  ^ rptr_gray_s2[3];
	rptr_bin[2] = rptr_bin[3]  ^ rptr_gray_s2[2];
	rptr_bin[1] = rptr_bin[2]  ^ rptr_gray_s2[1];
	rptr_bin[0] = rptr_bin[1]  ^ rptr_gray_s2[0];
end
wire fifo_full = ((fifo_wptr[6] != rptr_bin[6]) && (fifo_wptr[5:0] == rptr_bin[5:0]));
assign LEDR[0] = fifo_full;

always @(posedge ENET_RX_CLK) begin
	if (!ENET_RX_DV) begin
		if (rx_state == 2) pkt_cnt <= pkt_cnt + 1; 
		rx_state  <= 0;
		pix_idx   <= 0;
        rx_nib_hi <= 0;
	end else begin
		if (rx_state == 0) begin
			if (ENET_RX_DATA == 4'hD && prev_nib == 4'h5) begin
				rx_state    <= 1;     // Đã vào MAC Header!
				rx_byte_cnt <= 0;
				rx_nib_hi   <= 0;
			end
			prev_nib <= ENET_RX_DATA;
		end 
        else begin
			if (rx_nib_hi == 0) begin
				prev_nib  <= ENET_RX_DATA; 
				rx_nib_hi <= 1;
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
                    else if (rx_byte_cnt == 45) hdr_offset[15:8]  <= {ENET_RX_DATA, prev_nib};
                    else if (rx_byte_cnt == 46) begin
                        hdr_offset[7:0] <= {ENET_RX_DATA, prev_nib};
                        pix_idx <= 0;
                        // DOUBLE FRAME BUFFER SWAP:
                        // Khi PC gửi packet đầu tiên của frame mới (offset=0),
                        // swap buffer: VGA chuyển sang đọc frame vừa hoàn thành,
                        // Ethernet bắt đầu ghi vào frame còn lại.
                        if (full_offset == 24'd0) begin
                            rd_frame_eth <= wr_frame;           // VGA đọc frame hoàn chỉnh
                            wr_frame <= ~wr_frame;               // ETH ghi sang frame kia
                            wr_sdram_addr <= {~wr_frame, 18'd0}; // Địa chỉ đầu frame mới
                        end else begin
                            wr_sdram_addr <= {wr_frame, full_offset[18:1]}; // ÷2: 2 pixel/word
                        end
                    end
                    else if (rx_byte_cnt >= 47) begin
                        if (pix_idx == 0) begin
                            pixels_temp[7:0] <= {ENET_RX_DATA, prev_nib};
                            pix_idx <= 1;
                        end else if (pix_idx == 1) begin
                            pixels_temp[15:8] <= {ENET_RX_DATA, prev_nib};
                            pix_idx <= 2;
                        end else if (pix_idx == 2) begin
                            pixels_temp[23:16] <= {ENET_RX_DATA, prev_nib};
                            pix_idx <= 3;
                        end else begin
                            // GHI TRỰC TIẾP VÀO FIFO TRONG 1 NHỊP DUY NHẤT ĐỂ TRÁNH MẤT OFFSET ĐẦU
                            if (!fifo_full) begin
                                eth_fifo[fifo_wptr] <= {wr_sdram_addr, {ENET_RX_DATA, prev_nib}, pixels_temp};
                                fifo_wptr <= fifo_wptr + 1'b1;
                            end
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

// ===================================================================
// VẪN DÙNG GRAY CODE ĐỂ ĐẢM BẢO AN TOÀN CROSS-DOMAIN
wire [6:0] fifo_wptr_gray = fifo_wptr ^ (fifo_wptr >> 1);
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [6:0] wptr_gray_s1=0, wptr_gray_s2=0;

always @(posedge clk) begin
	wptr_gray_s1 <= fifo_wptr_gray;
	wptr_gray_s2 <= wptr_gray_s1;
end

reg [6:0] wptr_bin;
always @(*) begin
	wptr_bin[6] = wptr_gray_s2[6];
	wptr_bin[5] = wptr_bin[6] ^ wptr_gray_s2[5];
	wptr_bin[4] = wptr_bin[5] ^ wptr_gray_s2[4];
	wptr_bin[3] = wptr_bin[4] ^ wptr_gray_s2[3];
	wptr_bin[2] = wptr_bin[3] ^ wptr_gray_s2[2];
	wptr_bin[1] = wptr_bin[2] ^ wptr_gray_s2[1];
	wptr_bin[0] = wptr_bin[1] ^ wptr_gray_s2[0];
end

wire fifo_empty = (fifo_rptr == wptr_bin);

// PIPELINE M9K BRAM READ ĐÚNG CHUẨN 2 CHU KỲ
reg [50:0] fifo_out;
reg eth_pending = 0;
reg [18:0] eth_addr = 0;
reg [31:0] eth_data = 0;
reg read_in_progress = 0;

always @(posedge clk) begin
    fifo_out <= eth_fifo[fifo_rptr];

	if (!fifo_empty && !eth_pending && !read_in_progress) begin
		read_in_progress <= 1'b1;
	end
	else if (read_in_progress) begin
        // Trích xuất CHÍNH XÁC 19 bit địa chỉ (18 bit word + 1 bit frame)
		eth_addr <= fifo_out[50:32]; 
		eth_data <= fifo_out[31:0];
		eth_pending <= 1'b1;
        read_in_progress <= 1'b0;
		fifo_rptr <= fifo_rptr + 1'b1;
	end

	if (eth_clear) eth_pending <= 1'b0;
end
reg eth_clear = 0;

// ==========================================================================
// 5. VGA TIMING (25MHz) — COPY NGUYÊN XI TỪ BÀI 2
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

wire h_active = (h_cnt < H_VISIBLE);
wire v_active = (v_cnt < V_VISIBLE);

reg vga_hs_r, vga_vs_r;
always @(posedge vga_clk) begin
	vga_hs_r <= ~((h_cnt >= H_VISIBLE+H_FRONT) && (h_cnt < H_VISIBLE+H_FRONT+H_SYNC_W));
	vga_vs_r <= ~((v_cnt >= V_VISIBLE+V_FRONT) && (v_cnt < V_VISIBLE+V_FRONT+V_SYNC_W));
end
assign VGA_HS = vga_hs_r;
assign VGA_VS = vga_vs_r;

// Trigger fetch dòng mới
reg h_cnt_zero_vga;
always @(posedge vga_clk) h_cnt_zero_vga <= (h_cnt == 0);

(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg h_zero_s1=0, h_zero_s2=0, h_zero_s3=0;
always @(posedge clk) begin
    h_zero_s1 <= h_cnt_zero_vga;
    h_zero_s2 <= h_zero_s1;
    h_zero_s3 <= h_zero_s2;
end
wire start_fetch = (h_zero_s3 == 0 && h_zero_s2 == 1);

// Sync v_cnt:
reg [10:0] v_cnt_latched;
always @(posedge vga_clk) begin
    if (h_cnt == 1) v_cnt_latched <= v_cnt;
end

(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [10:0] v_cnt_s1=0, v_cnt_s2=0;
always @(posedge clk) begin
    v_cnt_s1 <= v_cnt_latched;
    v_cnt_s2 <= v_cnt_s1;
end

// DOUBLE FRAME BUFFER: Sync rd_frame từ ETH clock (25MHz) → SDRAM clock (100MHz)
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg rd_frame_s1=0, rd_frame_s2=0;
always @(posedge clk) begin
    rd_frame_s1 <= rd_frame_eth;
    rd_frame_s2 <= rd_frame_s1;
end

// V-SYNC LOCKED SWAP: Chỉ tráo buffer trong Vertical Blanking Interval
// Khi VGA đang ở vùng blanking (dòng 480-524), swap mới được phép xảy ra.
// Trong suốt vùng active (dòng 0-479), rd_frame bị "đóng băng" → không bao giờ rung hình.
reg rd_frame = 0;
always @(posedge clk) begin
    if (v_cnt_s2 >= V_VISIBLE)  // V_VISIBLE = 480
        rd_frame <= rd_frame_s2;
end

wire [10:0] fetch_line = (v_cnt_s2 == V_TOTAL-1) ? 11'd0 : (v_cnt_s2 + 1);
wire write_to_buf_B  = fetch_line[0];
wire read_from_buf_B = v_cnt[0];

// ==========================================================================
// THUẬT TOÁN LATCH CHỐNG MẤT DÒNG
// ==========================================================================
reg fetch_req = 0;
always @(posedge clk or negedge pll_locked) begin
    if (!pll_locked) fetch_req <= 0;
    else begin
        if (start_fetch && fetch_line < 480) fetch_req <= 1'b1;
        if (state == 5'd11 && disp_words_read == 0) fetch_req <= 1'b0; // ST_DISP_ACT
    end
end


// ==========================================================================
// 6. RGB565 HIGH COLOR DOUBLE LINE BUFFER 320 WORDS (M9K)
// 2 pixels/word × 320 words = 640 pixels/line
// ==========================================================================
(* ramstyle = "M9K" *) reg [31:0] line_buf_A [0:319];
(* ramstyle = "M9K" *) reg [31:0] line_buf_B [0:319];

reg [8:0]  buf_wr_ptr;
reg        buf_wr_en;
reg [31:0] buf_wr_data;

always @(posedge clk) begin
	if (buf_wr_en) begin
		if (write_to_buf_B) line_buf_B[buf_wr_ptr] <= buf_wr_data;
		else                line_buf_A[buf_wr_ptr] <= buf_wr_data;
	end
end

// Read port (VGA 25MHz) — 2 pixels per word
wire [8:0] rd_idx = h_cnt[9:1];
reg [31:0] rd_data_A, rd_data_B;
always @(posedge vga_clk) begin
	rd_data_A <= line_buf_A[rd_idx];
	rd_data_B <= line_buf_B[rd_idx];
end

wire [31:0] pixel_word = read_from_buf_B ? rd_data_B : rd_data_A;

// ====================================
// RGB565 HIGH COLOR (65,536 màu)
// Mỗi word 32-bit = 2 pixel: [Pixel1: 31:16] [Pixel0: 15:0]
// RGB565: [15:11]=R(5b) [10:5]=G(6b) [4:0]=B(5b)
// ====================================
reg h_pixel_sel;
always @(posedge vga_clk) h_pixel_sel <= h_cnt[0]; // Delay 1 clock khớp BRAM latency

wire [15:0] pixel_565 = h_pixel_sel ? pixel_word[31:16] : pixel_word[15:0];
wire [7:0] r8 = {pixel_565[15:11], pixel_565[15:13]}; // 5→8 bit
wire [7:0] g8 = {pixel_565[10:5],  pixel_565[10:9]};  // 6→8 bit
wire [7:0] b8 = {pixel_565[4:0],   pixel_565[4:2]};   // 5→8 bit

reg h_act_d1, v_act_d1;
always @(posedge vga_clk) begin h_act_d1 <= h_active; v_act_d1 <= v_active; end
wire disp_act = h_act_d1 && v_act_d1;

// VGA OUTPUT REGISTERED: Khóa dữ liệu vào flip-flop trước khi ra chân FPGA
// Loại bỏ glitch tổ hợp (combinational glitch) gây nhiễu sóng trên VGA
reg [7:0] vga_r_reg, vga_g_reg, vga_b_reg;
reg       vga_blank_reg;
always @(posedge vga_clk) begin
    vga_r_reg     <= disp_act ? r8 : 8'd0;
    vga_g_reg     <= disp_act ? g8 : 8'd0;
    vga_b_reg     <= disp_act ? b8 : 8'd0;
    vga_blank_reg <= disp_act;
end

assign VGA_BLANK_N = vga_blank_reg;
assign VGA_R = vga_r_reg;
assign VGA_G = vga_g_reg;
assign VGA_B = vga_b_reg;

// ==========================================================================
// 7. SDRAM FSM (100MHz)
//    COPY FSM INIT + DISPLAY NGUYÊN TỪ BÀI 2
//    Thêm WRITE states cho Ethernet fill thay vì ROM fill
// ==========================================================================
reg [31:0] dq_out;
reg        dq_oe = 0;
wire [31:0] dq_in = DRAM_DQ;
assign DRAM_DQ = dq_oe ? dq_out : 32'bz;

localparam CMD_NOP=4'b0111, CMD_ACT=4'b0011, CMD_RD=4'b0101,
           CMD_WR=4'b0100, CMD_PRE=4'b0010, CMD_REF=4'b0001, CMD_LMR=4'b0000;

reg        DRAM_CKE_r, DRAM_CS_N_r, DRAM_RAS_N_r, DRAM_CAS_N_r, DRAM_WE_N_r;
reg [12:0] DRAM_ADDR_r;
reg [1:0]  DRAM_BA_r;
reg [3:0]  DRAM_DQM_r;
assign DRAM_CKE=DRAM_CKE_r; assign DRAM_CS_N=DRAM_CS_N_r;
assign DRAM_RAS_N=DRAM_RAS_N_r; assign DRAM_CAS_N=DRAM_CAS_N_r;
assign DRAM_WE_N=DRAM_WE_N_r;
assign DRAM_ADDR=DRAM_ADDR_r; assign DRAM_BA=DRAM_BA_r; assign DRAM_DQM=DRAM_DQM_r;

task send_cmd; input [3:0] cmd; begin
	{DRAM_CS_N_r, DRAM_RAS_N_r, DRAM_CAS_N_r, DRAM_WE_N_r} <= cmd;
end endtask

localparam INIT_WAIT=20000, tRP=2, tRFC=7, tMRD=2, tRCD=2, CAS_LAT=2;
localparam MODE_REG = 13'b000_0_00_010_0_000;

localparam [4:0]
	ST_RESET=0, ST_INIT_WAIT=1, ST_INIT_PRE=2, ST_INIT_PRE_W=3,
	ST_INIT_REF=4, ST_INIT_REF_W=5, ST_INIT_LM=6, ST_INIT_LM_W=7,
	ST_IDLE=8,
	ST_REFRESH=9, ST_REFRESH_W=10,
	ST_DISP_ACT=11, ST_DISP_ACT_W=12, ST_DISP_RD=13, ST_DISP_CAS_W=14,
	ST_DISP_CAP=15, ST_DISP_PRE=16, ST_DISP_PRE_W=17,
	ST_ETH_ACT=18, ST_ETH_ACT_W=19, ST_ETH_WR=20, ST_ETH_PRE=21, ST_ETH_PRE_W=22, ST_ETH_WR_REC=23;

reg [4:0]  state = ST_RESET;
reg [15:0] wait_cnt = 0;
reg [9:0]  refresh_cnt = 0;
localparam REFRESH_IV = 780;

// Display tracking (copy từ bài 2)
reg [18:0] disp_addr;
reg [8:0]  disp_sdram_col;
reg [8:0]  disp_words_read;

// ETH Write tracking
reg [8:0]  eth_sdram_col;

always @(posedge clk or negedge pll_locked) begin
	if (!pll_locked) begin
		state <= ST_RESET;
		DRAM_CKE_r <= 0; send_cmd(CMD_NOP);
		DRAM_BA_r <= 0; DRAM_ADDR_r <= 0; DRAM_DQM_r <= 4'b1111;
		dq_oe <= 0; buf_wr_en <= 0;
		refresh_cnt <= 0; eth_clear <= 0;
	end else begin
		send_cmd(CMD_NOP);
		dq_oe     <= 0;
		buf_wr_en <= 0;
		eth_clear <= 0;

		if (refresh_cnt < REFRESH_IV) refresh_cnt <= refresh_cnt + 1;

		case (state)
			// ===== INIT (COPY NGUYÊN TỪ BÀI 2) =====
			ST_RESET: begin DRAM_CKE_r<=1; DRAM_DQM_r<=0; wait_cnt<=0; state<=ST_INIT_WAIT; end
			ST_INIT_WAIT: begin
				if(wait_cnt==INIT_WAIT[15:0]) begin wait_cnt<=0; state<=ST_INIT_PRE; end
				else wait_cnt<=wait_cnt+1;
			end
			ST_INIT_PRE: begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_INIT_PRE_W; end
			ST_INIT_PRE_W: begin
				if(wait_cnt==tRP[15:0]) begin wait_cnt<=0; state<=ST_INIT_REF; end
				else wait_cnt<=wait_cnt+1;
			end
			ST_INIT_REF: begin send_cmd(CMD_REF); wait_cnt<=0; state<=ST_INIT_REF_W; end
			ST_INIT_REF_W: begin
				if(wait_cnt==tRFC[15:0]) begin wait_cnt<=0; state<=ST_INIT_LM; end
				else wait_cnt<=wait_cnt+1;
			end
			ST_INIT_LM: begin
				send_cmd(CMD_LMR); DRAM_BA_r<=0; DRAM_ADDR_r<=MODE_REG;
				wait_cnt<=0; state<=ST_INIT_LM_W;
			end
			ST_INIT_LM_W: begin
				if(wait_cnt==tMRD[15:0]) state<=ST_IDLE;
				else wait_cnt<=wait_cnt+1;
			end

			// ===== IDLE (Dò dòng mới của VGA hoặc gói nạp Ethernet) =====
			ST_IDLE: begin
				if (fetch_req) begin
					// VẼ NGUYÊN BẢN FULL SẮC NÉT 640x480!
					// ƯU TIÊN SỐ 1: Bắt lệnh vẽ bị dồn lại bằng Latch (fetch_req)
					disp_addr       <= {rd_frame, 18'd0} + fetch_line * 320;
					disp_words_read <= 0;
					buf_wr_ptr      <= 0;
					state           <= ST_DISP_ACT; // Luôn múc dữ liệu thay vì nhường cho cái khác
				end
				else if (refresh_cnt >= REFRESH_IV) begin
					refresh_cnt <= 0;
					state <= ST_REFRESH;
				end
				else if (eth_pending) begin
					state <= ST_ETH_ACT;
				end
			end

			// ===== REFRESH (COPY NGUYÊN TỪ BÀI 2) =====
			ST_REFRESH: begin send_cmd(CMD_REF); wait_cnt<=0; state<=ST_REFRESH_W; end
			ST_REFRESH_W: begin
				if(wait_cnt==tRFC[15:0]) begin wait_cnt<=0; state<=ST_IDLE; end
				else wait_cnt<=wait_cnt+1;
			end

			// ===== DISPLAY READ (COPY NGUYÊN TỪ BÀI 2) =====
			ST_DISP_ACT: begin
				disp_sdram_col <= disp_addr[8:0];
				send_cmd(CMD_ACT); DRAM_ADDR_r <= {3'd0, disp_addr[18:9]};
				wait_cnt<=0; state<=ST_DISP_ACT_W;
			end
			ST_DISP_ACT_W: begin
				if(wait_cnt==tRCD[15:0]) begin wait_cnt<=0; state<=ST_DISP_RD; end
				else wait_cnt<=wait_cnt+1;
			end
			ST_DISP_RD: begin
				send_cmd(CMD_RD);
				DRAM_ADDR_r <= {4'd0, disp_sdram_col}; DRAM_ADDR_r[10] <= 0;
				disp_sdram_col  <= disp_sdram_col + 1;
				disp_addr       <= disp_addr + 1;
				disp_words_read <= disp_words_read + 1;
				wait_cnt <= 0; state <= ST_DISP_CAS_W;
			end
			ST_DISP_CAS_W: begin
				if(wait_cnt==CAS_LAT[15:0]) state<=ST_DISP_CAP;
				else wait_cnt<=wait_cnt+1;
			end
			ST_DISP_CAP: begin
				buf_wr_data <= dq_in;
				buf_wr_en   <= 1;
				buf_wr_ptr  <= buf_wr_ptr + 1;
				if (disp_words_read == 320) state <= ST_DISP_PRE;
				else if (disp_sdram_col == 0) state <= ST_DISP_PRE;
				else state <= ST_DISP_RD;
			end
			ST_DISP_PRE: begin
				send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_DISP_PRE_W;
			end
			ST_DISP_PRE_W: begin
				if(wait_cnt==tRP[15:0]) begin
					if(disp_words_read>=320) state<=ST_IDLE;
					else state<=ST_DISP_ACT;
				end else wait_cnt<=wait_cnt+1;
			end

			// ===== ETHERNET WRITE (Tương tự bài 2 fill, nhưng 1 word) =====
			ST_ETH_ACT: begin
				eth_sdram_col <= eth_addr[8:0];
				send_cmd(CMD_ACT); DRAM_ADDR_r <= {3'd0, eth_addr[18:9]};
				wait_cnt<=0; state<=ST_ETH_ACT_W;
			end
			ST_ETH_ACT_W: begin
				if(wait_cnt==tRCD[15:0]) begin wait_cnt<=0; state<=ST_ETH_WR; end
				else wait_cnt<=wait_cnt+1;
			end
			ST_ETH_WR: begin
				send_cmd(CMD_WR);
				DRAM_ADDR_r <= {4'd0, eth_sdram_col};
				DRAM_ADDR_r[10] <= 0; // Không auto precharge
                DRAM_DQM_r <= 4'b0000; // Bảo đảm DQM cho phép write 32-bit
				dq_out <= eth_data;
				dq_oe  <= 1;
				eth_clear <= 1;
				wait_cnt <= 0;
				state <= ST_ETH_WR_REC;
			end
			ST_ETH_WR_REC: begin
				dq_oe <= 1; // Giữ nguyên data thêm 1 chu kỳ phục hồi
				if (wait_cnt >= 2) state <= ST_ETH_PRE;
				else wait_cnt <= wait_cnt + 1;
			end
			ST_ETH_PRE: begin
				send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_ETH_PRE_W;
			end
			ST_ETH_PRE_W: begin
				if(wait_cnt==tRP[15:0]) begin wait_cnt<=0; state<=ST_IDLE; end
				else wait_cnt<=wait_cnt+1;
			end

			default: state <= ST_IDLE;
		endcase
	end
end

// ==========================================================================
// 8. DEBUG LED + HEX
// ==========================================================================
assign LEDG[0] = phy_rst_n;
assign LEDG[1] = ~ENET_LINK100;
assign LEDG[2] = ENET_RX_DV;
assign LEDG[3] = mdio_done;
assign LEDG[4] = pll_locked;
assign LEDG[5] = (state >= ST_IDLE);
assign LEDG[6] = eth_pending;
reg [23:0] blink = 0;
always @(posedge ENET_RX_CLK) blink <= blink + 1;
assign LEDG[7] = blink[23];
assign LEDG[8] = blink[22];
assign LEDR[17:1] = 17'd0; // Bỏ ngỏ LEDR[0] cho mạch FIFO FULL_WARNING

function [6:0] seg7; input [3:0] hex;
	case(hex)
		4'h0:seg7=7'b1000000; 4'h1:seg7=7'b1111001; 4'h2:seg7=7'b0100100;
		4'h3:seg7=7'b0110000; 4'h4:seg7=7'b0011001; 4'h5:seg7=7'b0010010;
		4'h6:seg7=7'b0000010; 4'h7:seg7=7'b1111000; 4'h8:seg7=7'b0000000;
		4'h9:seg7=7'b0010000; 4'hA:seg7=7'b0001000; 4'hB:seg7=7'b0000011;
		4'hC:seg7=7'b1000110; 4'hD:seg7=7'b0100001; 4'hE:seg7=7'b0000110;
		4'hF:seg7=7'b0001110; default:seg7=7'b1111111;
	endcase
endfunction

assign HEX7 = 7'b0000110; // E
assign HEX6 = 7'b0000111; // t
assign HEX5 = seg7(pkt_cnt[7:4]);
assign HEX4 = seg7(pkt_cnt[3:0]);
assign HEX3 = seg7({3'd0, state[4]});
assign HEX2 = seg7(state[3:0]);
assign HEX1 = seg7(eth_addr[11:8]); // Hiển thị địa chỉ cao hơn để xem tiến trình
assign HEX0 = seg7(eth_addr[7:4]);

endmodule
