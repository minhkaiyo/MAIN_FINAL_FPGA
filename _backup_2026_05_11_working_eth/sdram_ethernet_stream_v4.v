// sdram_ethernet_stream_v4.v
`timescale 1ns / 1ps

module sdram_ethernet_stream_v4 (
    input  wire CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [17:0] SW,
    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,
    output wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
    
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

// ==========================================================================
// 1. PLLs
// ==========================================================================
wire clk, clk_sdram, vga_clk, vga_clk_dac, pll_sdram_locked;
sdram_pll pll_sdram_inst (
    .inclk0(CLOCK_50), .c0(clk), .c1(clk_sdram),
    .c2(vga_clk), .c3(vga_clk_dac), .locked(pll_sdram_locked)
);

wire clk_125, clk_125_90, pll_125_locked;
pll_125 pll_125_inst (
    .inclk0(CLOCK_50), .c0(clk_125), .c1(clk_125_90), .locked(pll_125_locked)
);

assign DRAM_CLK = clk_sdram; // SDRAM clock từ sdram_pll, cùng PLL với VGA
assign VGA_CLK  = vga_clk_dac;
assign VGA_SYNC_N = 1'b0;

// ==========================================================================
// 2. PHY INIT
// ==========================================================================
wire phy_ready;
phy_init_88e1111 phy_init (
    .clk(CLOCK_50), .rst_n(KEY[0]),
    .phy_rst_n(ENET_RST_N), .mdc(ENET_MDC), .mdio(ENET_MDIO),
    .configured(phy_ready)
);

wire rst = ~KEY[0];
wire mac_rst = rst | !phy_ready | !pll_125_locked;

// ==========================================================================
// 3. MAC CORE
// ==========================================================================
wire [7:0] rx_axis_tdata;
wire rx_axis_tvalid, rx_axis_tlast;
wire [1:0] mac_speed;

eth_mac_1g_rgmii_fifo #(
    .TARGET("ALTERA"),
    .RX_FIFO_DEPTH(4096),
    .RX_FRAME_FIFO(1),
    .RX_DROP_BAD_FRAME(0)
) mac_inst (
    .gtx_clk(clk_125), .gtx_clk90(clk_125), .gtx_rst(mac_rst), 
    .logic_clk(clk_125), .logic_rst(mac_rst),
    .rx_axis_tdata(rx_axis_tdata), .rx_axis_tvalid(rx_axis_tvalid), .rx_axis_tready(1'b1), .rx_axis_tlast(rx_axis_tlast),
    .rgmii_rx_clk(ENET_RX_CLK),
    .rgmii_rxd(ENET_RX_DATA), .rgmii_rx_ctl(ENET_RX_DV),
    .rgmii_tx_clk(ENET_GTX_CLK), .rgmii_txd(ENET_TX_DATA), .rgmii_tx_ctl(ENET_TX_EN),
    .cfg_rx_enable(1'b1), .cfg_tx_enable(1'b1), // BAT BUOC PHAI BAT ENABLE DE MAC HOAT DONG
    .speed(mac_speed)
);

// ==========================================================================
// 4. UDP RAW PARSER -> 32-BIT WORD (ABSOLUTE LINE ADDRESSING)
// ==========================================================================
reg [3:0] dbg_fsm = 0;
reg [11:0] byte_cnt = 0;
reg [31:0] word_data = 0;
reg [17:0] word_addr = 0;
reg [1:0]  byte_idx = 0;
reg word_valid = 0;
reg frame_start_pulse = 0;
reg [31:0] frame_id = 0;
reg [31:0] debug_pkt_cnt = 0;
reg [15:0] row_idx = 0;

// Forward declaration
wire fifo_full;

always @(posedge clk_125) begin
    if (mac_rst) begin
        dbg_fsm <= 0; byte_cnt <= 0; word_addr <= 0; byte_idx <= 0; 
        word_valid <= 0; frame_start_pulse <= 0; debug_pkt_cnt <= 0;
    end else begin
        word_valid <= 0; frame_start_pulse <= 0;
        
        // Tăng địa chỉ SAU KHI FIFO đã chốt (word_valid = giá trị từ chu kỳ TRƯỚC)
        if (word_valid && word_addr < 76799) begin
            word_addr <= word_addr + 1;
        end
        
        if (rx_axis_tvalid) begin
            // Xử lý dữ liệu BÌNH THƯỜNG kể cả khi có tlast
            case (dbg_fsm)
                0: begin dbg_fsm <= 1; byte_cnt <= 1; end
                1: begin if(byte_cnt == 13) begin dbg_fsm <= 2; byte_cnt <= 0; end else byte_cnt <= byte_cnt + 1; end
                2: begin if(byte_cnt == 19) begin dbg_fsm <= 3; byte_cnt <= 0; end else byte_cnt <= byte_cnt + 1; end
                3: begin if(byte_cnt == 7)  begin dbg_fsm <= 4; byte_cnt <= 0; end else byte_cnt <= byte_cnt + 1; end
                4: begin 
                    if (byte_cnt == 0) begin
                        row_idx[15:8] <= rx_axis_tdata;
                        byte_cnt <= byte_cnt + 1;
                    end else if (byte_cnt == 1) begin
                        row_idx[7:0] <= rx_axis_tdata;
                        
                        // y == 0 => Frame mới
                        if ({row_idx[15:8], rx_axis_tdata} == 16'd0) begin
                            frame_start_pulse <= 1;
                            frame_id <= frame_id + 1;
                        end
                        
                        // GHIM TỌA ĐỘ TUYỆT ĐỐI: y * 160
                        if ({row_idx[15:8], rx_axis_tdata} < 16'd480) begin
                            word_addr <= ({2'b0, row_idx[15:8], rx_axis_tdata} << 7)
                                       + ({2'b0, row_idx[15:8], rx_axis_tdata} << 5);
                        end else begin
                            word_addr <= 18'h3FFFF;
                        end
                        
                        byte_idx <= 0;
                        byte_cnt <= byte_cnt + 1;
                    end else if (byte_cnt < 642) begin
                        // 640 byte Pixel
                        if (byte_idx == 3) begin
                            word_data <= {word_data[23:0], rx_axis_tdata};
                            word_valid <= 1;
                            byte_idx <= 0;
                            // KHÔNG tăng word_addr ở đây! Để FIFO chốt đúng addr trước
                        end else begin
                            word_data <= {word_data[23:0], rx_axis_tdata};
                            byte_idx <= byte_idx + 1;
                        end
                        byte_cnt <= byte_cnt + 1;
                    end
                end
            endcase
            
            // Xử lý reset khi kết thúc gói tin
            if (rx_axis_tlast) begin
                dbg_fsm <= 0; 
                debug_pkt_cnt <= debug_pkt_cnt + 1;
                byte_idx <= 0;
            end
        end
    end
end

// ==========================================================================
// 5. TRIPLE BUFFER MANAGEMENT
// ==========================================================================
reg [1:0] wr_frame = 0, ready_frame_eth = 0;
reg [1:0] rd_frame = 0;

wire fifo_wr = word_valid & !fifo_full & (word_addr < 76800);
wire [51:0] fifo_din  = {wr_frame, word_addr, word_data};

(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [1:0] rd_frame_eth_s1, rd_frame_eth_s2;
always @(posedge clk_125) begin
    rd_frame_eth_s1 <= rd_frame;
    rd_frame_eth_s2 <= rd_frame_eth_s1;
end
wire [1:0] rd_frame_sync = rd_frame_eth_s2;

always @(posedge clk_125) begin
    if (frame_start_pulse) begin
        ready_frame_eth <= wr_frame;
        if      (wr_frame != 2'd0 && rd_frame_sync != 2'd0) wr_frame <= 2'd0;
        else if (wr_frame != 2'd1 && rd_frame_sync != 2'd1) wr_frame <= 2'd1;
        else                                                 wr_frame <= 2'd2;
    end
end

// ==========================================================================
// 6. DCFIFO (Cross domain: clk_125 -> SDRAM FSM)
// ==========================================================================
wire        fifo_empty;
wire [51:0] fifo_dout;
wire [12:0] fifo_rdusedw; // Tăng width cho 8192
reg         fifo_rd = 0;

// Nâng cấp DCFIFO lên 8192 từ (tương đương 32KB RAM) để triệt tiêu lỗi Full Buffer.
// Đổi rdclk sang clk_125 để FSM SDRAM chạy ở tốc độ cực đại.
dcfifo #(
    .intended_device_family("Cyclone IV GX"),
    .lpm_numwords(8192), .lpm_showahead("ON"),
    .lpm_type("dcfifo"), .lpm_width(52), .lpm_widthu(13),
    .overflow_checking("ON"), .underflow_checking("ON"), .use_eab("ON")
) eth_dcfifo_inst (
    .wrclk(clk_125), .rdclk(clk), // wrclk=125MHz(ETH), rdclk=100MHz(SDRAM)
    .wrreq(fifo_wr), .rdreq(fifo_rd),
    .data(fifo_din), .q(fifo_dout),
    .wrfull(fifo_full), .rdempty(fifo_empty),
    .rdusedw(fifo_rdusedw), .aclr(~pll_sdram_locked)
);

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
// Pipeline VGA sync 1 bac cho khop pixel data (theo mau bai 3)
reg vga_hs_r, vga_vs_r;
always @(posedge vga_clk) begin
    vga_hs_r <= ~((h_cnt >= H_VISIBLE+H_FRONT) && (h_cnt < H_VISIBLE+H_FRONT+H_SYNC_W));
    vga_vs_r <= ~((v_cnt >= V_VISIBLE+V_FRONT) && (v_cnt < V_VISIBLE+V_FRONT+V_SYNC_W));
end
assign VGA_HS = vga_hs_r;
assign VGA_VS = vga_vs_r;

reg h_cnt_zero_vga; always @(posedge vga_clk) h_cnt_zero_vga <= (h_cnt==0);
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg h_zero_s1=0,h_zero_s2=0,h_zero_s3=0;
always @(posedge clk) begin h_zero_s1<=h_cnt_zero_vga; h_zero_s2<=h_zero_s1; h_zero_s3<=h_zero_s2; end
wire start_fetch = (h_zero_s3==0 && h_zero_s2==1);

reg [10:0] v_cnt_latched; always @(posedge vga_clk) if (h_cnt==1) v_cnt_latched<=v_cnt;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [10:0] v_cnt_s1=0,v_cnt_s2=0;
always @(posedge clk) begin v_cnt_s1<=v_cnt_latched; v_cnt_s2<=v_cnt_s1; end

(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [1:0] ready_s1,ready_s2;
always @(posedge clk) begin ready_s1<=ready_frame_eth; ready_s2<=ready_s1; end
always @(posedge clk) if (v_cnt_s2>=V_VISIBLE) rd_frame<=ready_s2;

wire [10:0] fetch_line = (v_cnt_s2==V_TOTAL-1) ? 11'd0 : (v_cnt_s2+1);
wire write_to_buf_B  = fetch_line[0];
wire read_from_buf_B = v_cnt[0];

// ==========================================================================
// 8. DOUBLE LINE BUFFER (VGA)
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
// Pipeline pixel select (delay 1 clk de khop voi registered line buffer read)
reg [1:0] h_cnt_d1;
always @(posedge vga_clk) h_cnt_d1 <= h_cnt[1:0];

// Byte order DUNG CHUAN bai 3: byte 0 truoc, byte 3 sau
wire [7:0] pixel_byte = (h_cnt_d1 == 2'd0) ? pixel_word[7:0]   :
                        (h_cnt_d1 == 2'd1) ? pixel_word[15:8]  :
                        (h_cnt_d1 == 2'd2) ? pixel_word[23:16] :
                                             pixel_word[31:24] ;

// Tach ma mau RGB332 (tuong thich ca Grayscale va Color)
wire [2:0] r3 = pixel_byte[7:5];
wire [2:0] g3 = pixel_byte[4:2];
wire [1:0] b2 = pixel_byte[1:0];

// Bit-expansion tu 3/2 bit len 8 bit (chuan bai 3)
wire [7:0] r8 = {r3, r3, r3[2:1]};
wire [7:0] g8 = {g3, g3, g3[2:1]};
wire [7:0] b8 = {b2, b2, b2, b2};

// Display active pipeline (delay 1 bac, khop voi line buffer read)
reg h_act_d1, v_act_d1;
always @(posedge vga_clk) begin
    h_act_d1 <= (h_cnt < H_VISIBLE);
    v_act_d1 <= (v_cnt < V_VISIBLE);
end
wire disp_act = h_act_d1 && v_act_d1;

assign VGA_BLANK_N = disp_act;
assign VGA_R = disp_act ? r8 : 8'd0;
assign VGA_G = disp_act ? g8 : 8'd0;
assign VGA_B = disp_act ? b8 : 8'd0;

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
always @(posedge clk or negedge pll_sdram_locked) begin
    if (!pll_sdram_locked) fetch_req<=0;
    else begin
        if (start_fetch && fetch_line<480) fetch_req<=1'b1;
        if (state==ST_DISP_ACT && disp_words_read==0) fetch_req<=1'b0;
    end
end

always @(posedge clk or negedge pll_sdram_locked) begin
    if (!pll_sdram_locked) begin
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
        ST_INIT_PRE_W: if(wait_cnt>=1) begin wait_cnt<=0; state<=ST_INIT_REF; end else wait_cnt<=wait_cnt+1;  // tRP=2clk: 1(PRE) + 1(wait) = 2
        ST_INIT_REF:   begin send_cmd(CMD_REF); wait_cnt<=0; state<=ST_INIT_REF_W; end
        ST_INIT_REF_W: if(wait_cnt>=6) begin wait_cnt<=0; if(!init_ref_done) begin init_ref_done<=1; state<=ST_INIT_REF; end else state<=ST_INIT_LM; end else wait_cnt<=wait_cnt+1; // tRFC=7clk: 1(REF) + 6(wait) = 7
        ST_INIT_LM:    begin send_cmd(CMD_LMR); DRAM_BA_r<=0; DRAM_ADDR_r<=MODE_REG; wait_cnt<=0; state<=ST_INIT_LM_W; end
        ST_INIT_LM_W:  if(wait_cnt>=1) state<=ST_IDLE; else wait_cnt<=wait_cnt+1; // tMRD=2clk: 1(LMR) + 1(wait) = 2
        ST_IDLE: begin
            if      (fetch_req) begin disp_addr<={fetch_line[10:0], 7'd0} + {2'd0, fetch_line[10:0], 5'd0}; disp_words_read<=0; buf_wr_ptr<=0; state<=ST_DISP_ACT; end
            else if (refresh_cnt>=REFRESH_IV) begin refresh_cnt<=0; state<=ST_REFRESH; end
            else if (!fifo_empty && fifo_rdusedw>=BURST_THRESHOLD) begin burst_bank<=fifo_dout[51:50]; burst_row<=fifo_dout[49:41]; state<=ST_ETH_BURST_ACT; end
        end
        ST_REFRESH:        begin send_cmd(CMD_REF); wait_cnt<=0; state<=ST_REFRESH_W; end
        ST_REFRESH_W:      if(wait_cnt>=6) begin wait_cnt<=0; state<=ST_IDLE; end else wait_cnt<=wait_cnt+1; // tRFC=7: 1+6=7
        ST_DISP_ACT:       begin send_cmd(CMD_ACT); DRAM_BA_r<=rd_frame; DRAM_ADDR_r<={4'd0,disp_addr[17:9]}; wait_cnt<=0; state<=ST_DISP_ACT_W; end
        ST_DISP_ACT_W:     if(wait_cnt>=1) begin wait_cnt<=0; state<=ST_DISP_RD; end else wait_cnt<=wait_cnt+1; // tRCD=2: 1(ACT)+1(wait)=2
        ST_DISP_RD:        begin send_cmd(CMD_RD); DRAM_ADDR_r<={4'd0,disp_addr[8:0]}; DRAM_ADDR_r[10]<=0; disp_addr<=disp_addr+1; disp_words_read<=disp_words_read+1; wait_cnt<=0; state<=ST_DISP_CAS_W; end
        ST_DISP_CAS_W:     if(wait_cnt>=1) state<=ST_DISP_CAP; else wait_cnt<=wait_cnt+1; // CAS=2: 1(RD)+1(wait)=2, data ready on next clk
        ST_DISP_CAP:       begin buf_wr_data<=dq_in; buf_wr_en<=1; buf_wr_ptr<=buf_wr_ptr+1; if(disp_words_read==160||disp_addr[8:0]==0) state<=ST_DISP_PRE; else state<=ST_DISP_RD; end
        ST_DISP_PRE:       begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_DISP_PRE_W; end
        ST_DISP_PRE_W:     if(wait_cnt>=1) begin if(disp_words_read>=160) state<=ST_IDLE; else state<=ST_DISP_ACT; end else wait_cnt<=wait_cnt+1; // tRP=2: 1+1=2
        ST_ETH_BURST_ACT:  begin send_cmd(CMD_ACT); DRAM_BA_r<=burst_bank; DRAM_ADDR_r<={4'd0,burst_row}; wait_cnt<=0; burst_count<=0; state<=ST_ETH_BURST_ACT_W; end
        ST_ETH_BURST_ACT_W:if(wait_cnt>=1) state<=ST_ETH_BURST_WR; else wait_cnt<=wait_cnt+1; // tRCD=2: 1+1=2
        ST_ETH_BURST_WR:   begin send_cmd(CMD_WR); DRAM_BA_r<=burst_bank; DRAM_ADDR_r<={4'd0,fifo_dout[40:32]}; DRAM_ADDR_r[10]<=0; DRAM_DQM_r<=0; dq_out<=fifo_dout[31:0]; dq_oe<=1; burst_count<=burst_count+1; fifo_rd<=1; state<=ST_ETH_BURST_WAIT; end
        ST_ETH_BURST_WAIT: begin dq_oe<=0; state<=ST_ETH_BURST_CHECK; end
        ST_ETH_BURST_CHECK:if(fifo_empty||burst_count>=BURST_MAX||fifo_dout[51:50]!=burst_bank||fifo_dout[49:41]!=burst_row) begin wait_cnt<=0; state<=ST_ETH_BURST_WR_W; end else state<=ST_ETH_BURST_WR;
        ST_ETH_BURST_WR_W: begin dq_oe<=0; if(wait_cnt>=2) state<=ST_ETH_BURST_PRE; else wait_cnt<=wait_cnt+1; end
        ST_ETH_BURST_PRE:  begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_ETH_BURST_PRE_W; end
        ST_ETH_BURST_PRE_W:if(wait_cnt>=1) state<=ST_IDLE; else wait_cnt<=wait_cnt+1; // tRP=2: 1+1=2
        default: state<=ST_IDLE;
        endcase
    end
end

// ==========================================================================
// 10. DIAGNOSTICS
// ==========================================================================
assign LEDG[0] = pll_125_locked;
assign LEDG[1] = pll_sdram_locked;
assign LEDG[2] = phy_ready;
assign LEDG[8] = (state == ST_IDLE);

assign LEDR[17] = fifo_full;
assign LEDR[16] = fifo_empty;
assign LEDR[0]  = rx_axis_tvalid;
assign LEDR[15:1] = 0;

assign HEX0 = s7(frame_id[3:0]); assign HEX1 = s7(frame_id[7:4]); assign HEX2 = s7(frame_id[11:8]); assign HEX3 = s7(frame_id[15:12]);
assign HEX4 = s7(debug_pkt_cnt[3:0]); assign HEX5 = s7(debug_pkt_cnt[7:4]); 
assign HEX6 = s7(debug_pkt_cnt[11:8]); assign HEX7 = s7(debug_pkt_cnt[15:12]);

function [6:0] s7; input [3:0] h; case(h) 4'h0:s7=7'b1000000; 4'h1:s7=7'b1111001; 4'h2:s7=7'b0100100; 4'h3:s7=7'b0110000; 4'h4:s7=7'b0011001; 4'h5:s7=7'b0010010; 4'h6:s7=7'b0000010; 4'h7:s7=7'b1111000; 4'h8:s7=7'b0000000; 4'h9:s7=7'b0010000; 4'hA:s7=7'b0001000; 4'hB:s7=7'b0000011; 4'hC:s7=7'b1000110; 4'hD:s7=7'b0100001; 4'hE:s7=7'b0000110; 4'hF:s7=7'b0001110; default:s7=7'b1111111; endcase endfunction

endmodule
