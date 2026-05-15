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
    output wire        VGA_BLANK_N, 
`ifdef SIMULATION
    input              VGA_CLK,
`else
    output wire        VGA_CLK,
`endif
    output wire        VGA_HS, VGA_SYNC_N, VGA_VS,
    
    // Gigabit Ethernet
`ifdef SIMULATION
    input              ENET_GTX_CLK,
`else
    output wire        ENET_GTX_CLK,
`endif
    output wire        ENET_MDC,
    inout  wire ENET_MDIO,
    output wire ENET_RST_N,
    input  wire ENET_RX_CLK,
    input  wire [3:0] ENET_RX_DATA,
    input  wire ENET_RX_DV,
    output wire [3:0] ENET_TX_DATA,
    output wire ENET_TX_EN
    
`ifdef SIMULATION
    , input clk,
    input clk_125
`endif
);

`include "lib/Sdram_Control/Sdram_Params.h"

// ==========================================================================
// 1. PLLs
// ==========================================================================
`ifndef SIMULATION
wire clk, clk_sdram, vga_clk, vga_clk_dac, pll_sdram_locked;
wire clk_125, clk_125_90, pll_125_locked;

sdram_pll pll_sdram_inst (
    .inclk0(CLOCK_50), .c0(clk), .c1(clk_sdram),
    .c2(vga_clk), .c3(vga_clk_dac), .locked(pll_sdram_locked)
);

pll_125 pll_125_inst (
    .inclk0(CLOCK_50), .c0(clk_125), .c1(clk_125_90), .locked(pll_125_locked)
);
`else
    wire clk_sdram, vga_clk_dac, pll_sdram_locked, pll_125_locked;
    wire vga_clk; // Thêm khai báo này
    // clk và clk_125 đã là port đầu vào
    assign pll_sdram_locked = 1'b1;
    assign pll_125_locked   = 1'b1;
    assign clk_sdram        = clk;
    assign vga_clk          = VGA_CLK; // Thêm dòng này
    assign vga_clk_dac      = vga_clk;
`endif

`ifndef SIMULATION
assign DRAM_CLK = clk_sdram; // SDRAM clock từ sdram_pll, cùng PLL với VGA
assign VGA_CLK  = vga_clk_dac;
`endif
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
`ifdef SIMULATION
    wire mac_rst = rst; // Bỏ qua phy_ready trong mô phỏng
`else
    wire mac_rst = rst | !phy_ready | !pll_125_locked;
`endif

// ==========================================================================
// 3. MAC CORE
// ==========================================================================
wire [7:0] rx_axis_tdata;
wire rx_axis_tvalid, rx_axis_tlast;
wire [1:0] mac_speed;

`ifndef SIMULATION
eth_mac_1g_rgmii_fifo #(
    .TARGET("ALTERA"),
    .RX_FIFO_DEPTH(4096),
    .RX_FRAME_FIFO(1),
    .RX_DROP_BAD_FRAME(0)
) mac_inst (
    .gtx_clk(clk_125), .gtx_clk90(clk_125_90), .gtx_rst(mac_rst), 
    .logic_clk(clk_125), .logic_rst(mac_rst),
    .rx_axis_tdata(rx_axis_tdata), .rx_axis_tvalid(rx_axis_tvalid), .rx_axis_tready(1'b1), .rx_axis_tlast(rx_axis_tlast),
    .rgmii_rx_clk(ENET_RX_CLK),
    .rgmii_rxd(ENET_RX_DATA), .rgmii_rx_ctl(ENET_RX_DV),
    .rgmii_tx_clk(ENET_GTX_CLK), .rgmii_txd(ENET_TX_DATA), .rgmii_tx_ctl(ENET_TX_EN),
    .cfg_rx_enable(1'b1), .cfg_tx_enable(1'b1), // BAT BUOC PHAI BAT ENABLE DE MAC HOAT DONG
    .speed(mac_speed)
);
`else
    assign mac_speed = 2'b10;
`endif

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
wire fifo_full;

always @(posedge clk_125) begin
    if (mac_rst) begin
        dbg_fsm <= 0; byte_cnt <= 0; word_addr <= 0; byte_idx <= 0; 
        word_valid <= 0; frame_start_pulse <= 0; debug_pkt_cnt <= 0;
    end else begin
        word_valid <= 0; frame_start_pulse <= 0;
        
        // RESET địa chỉ khi bắt đầu khung hình mới
        if (frame_start_pulse) begin
            word_addr <= 0;
        end else if (word_valid) begin
            word_addr <= word_addr + 1;
        end
        
        // RESET FSM khi kết thúc gói tin để chống lệch byte
        if (rx_axis_tlast) begin
            dbg_fsm <= 0; 
            debug_pkt_cnt <= debug_pkt_cnt + 1;
            byte_idx <= 0;
        end else if (rx_axis_tvalid) begin
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
                        
                        // Ghép trực tiếp byte đang nhận (rx_axis_tdata) với byte đã chốt (row_idx[15:8])
                        if ({row_idx[15:8], rx_axis_tdata} < 16'd480) begin
                            // CHẾ ĐỘ MONO8: 640 pixel ngang, mỗi pixel 1 byte -> 160 words (32-bit)
                            // y * 160 = y * 128 + y * 32
                            word_addr <= ({3'd0, row_idx[15:8], rx_axis_tdata} << 7)
                                       + ({5'd0, row_idx[15:8], rx_axis_tdata} << 5); 
                        end else begin
                            word_addr <= 18'h3FFFF;
                        end
                        
                        byte_idx <= 0;
                        byte_cnt <= byte_cnt + 1;
                        if ({row_idx[15:8], rx_axis_tdata} == 16'd0) begin
                            frame_start_pulse <= 1;
                            frame_id <= frame_id + 1;
                        end
                    end else if (byte_cnt < 642) begin // Nhận 640 byte (640 pixel Mono8)
                        if (byte_idx == 3) begin
                            word_data <= {word_data[23:0], rx_axis_tdata};
                            word_valid <= 1;
                            byte_idx <= 0;
                        end else begin
                            word_data <= {word_data[23:0], rx_axis_tdata};
                            byte_idx <= byte_idx + 1;
                        end
                        byte_cnt <= byte_cnt + 1;
                    end
                end
            endcase
        end
    end
    
    // KHÔNG LOG Ở ĐÂY ĐỂ TRÁNH SPAM
    // Các sự kiện quan trọng sẽ được log ở khối Diagnostics cuối file
end

// ==========================================================================
// 4b. TEST PATTERN GENERATOR (SW[17] = ON -> gradient, OFF -> Ethernet)
// ==========================================================================
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg sw17_s1 = 0, sw17_s2 = 0;
always @(posedge clk_125) begin sw17_s1 <= SW[17]; sw17_s2 <= sw17_s1; end
wire test_mode = sw17_s2;

reg [1:0]  pg_state = 0;
reg [17:0] pg_addr = 0;
reg [9:0]  pg_row = 0;
reg [7:0]  pg_col = 0;      // 0-159 words per row
reg        pg_valid = 0;
reg        pg_frame_start = 0;
reg [20:0] pg_wait = 0;

localparam PG_IDLE = 0, PG_FSTART = 1, PG_WRITE = 2, PG_WAIT = 3;

always @(posedge clk_125) begin
    if (mac_rst || !test_mode) begin
        pg_state <= PG_IDLE; pg_valid <= 0; pg_frame_start <= 0;
    end else begin
        pg_valid <= 0; pg_frame_start <= 0;
        case (pg_state)
            PG_IDLE: begin
                pg_row <= 0; pg_col <= 0; pg_addr <= 18'h3FFFF; // Tràn về 0 khi +1 lần đầu
                pg_state <= PG_FSTART;
            end
            PG_FSTART: begin
                pg_frame_start <= 1;
                pg_state <= PG_WRITE;
            end
            PG_WRITE: begin
                if (!fifo_full) begin
                    pg_valid <= 1;
                    // pg_addr giữ nguyên cho FIFO capture, tăng cho lần sau
                    if (pg_col == 159) begin
                        pg_col <= 0;
                        if (pg_row == 479) begin
                            pg_wait <= 0; pg_state <= PG_WAIT;
                        end else
                            pg_row <= pg_row + 1;
                    end else
                        pg_col <= pg_col + 1;
                    pg_addr <= pg_addr + 1;
                end
            end
            PG_WAIT: begin
                // Chờ ~16ms (2M cycles @125MHz) cho VGA quét xong 1 frame
                if (pg_wait >= 21'd2000000) pg_state <= PG_IDLE;
                else pg_wait <= pg_wait + 1;
            end
        endcase
    end
end

// Pattern: Gradient dọc (pixel = y[7:0]), 4 pixel/word
wire [31:0] pg_word_data = {pg_row[7:0], pg_row[7:0], pg_row[7:0], pg_row[7:0]};

// === MUX: Test Pattern vs Ethernet ===
wire        mux_valid       = test_mode ? pg_valid          : word_valid;
wire [17:0] mux_addr        = test_mode ? pg_addr           : word_addr;
wire [31:0] mux_data        = test_mode ? pg_word_data      : word_data;
wire        mux_frame_start = test_mode ? pg_frame_start    : frame_start_pulse;

// ==========================================================================
// 5. TRIPLE BUFFER MANAGEMENT
// ==========================================================================
reg [1:0] wr_frame = 0, ready_frame_eth = 0;
reg [1:0] rd_frame = 0;

wire fifo_wr = mux_valid & !fifo_full & (mux_addr < 76800);
wire [51:0] fifo_din  = {wr_frame, mux_addr, mux_data};

(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [1:0] rd_frame_eth_s1 = 0, rd_frame_eth_s2 = 0;
always @(posedge clk_125) begin
    rd_frame_eth_s1 <= rd_frame;
    rd_frame_eth_s2 <= rd_frame_eth_s1;
end
wire [1:0] rd_frame_sync = rd_frame_eth_s2;

reg frame_ready = 0; // Flag: đã có ít nhất 1 frame hoàn chỉnh trong SDRAM

always @(posedge clk_125) begin
    if (mux_frame_start) begin
        ready_frame_eth <= wr_frame;
        frame_ready     <= 1'b1; // Kể từ đây VGA mới được phép fetch
        // Thuật toán Triple Buffer: Chọn buffer không phải là đang đọc và không phải là vừa ghi xong
        if      (wr_frame != 2'd0 && rd_frame_sync != 2'd0) wr_frame <= 2'd0;
        else if (wr_frame != 2'd1 && rd_frame_sync != 2'd1) wr_frame <= 2'd1;
        else                                                 wr_frame <= 2'd2;
    end
end

// Synchronizer cho frame_ready: clk_125 -> clk (SDRAM domain)
reg frame_ready_s1 = 0, frame_ready_s = 0;
always @(posedge clk) begin
    frame_ready_s1 <= frame_ready;
    frame_ready_s  <= frame_ready_s1;
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

// Đồng bộ ready_frame_eth (125MHz) sang vga_clk (25MHz)
reg [1:0] ready_frame_vga_s1 = 0, ready_frame_vga_s2 = 0;
always @(posedge vga_clk) begin
    ready_frame_vga_s1 <= ready_frame_eth;
    ready_frame_vga_s2 <= ready_frame_vga_s1;
end

// VGA side: rd_frame được cập nhật trong clk domain (line 316) — KHÔNG drive ở đây
// Chỉ log khi VGA frame mới bắt đầu
always @(posedge vga_clk) begin
    if (v_cnt == 0 && h_cnt == 0)
        $display("[VGA] New Frame. rd_frame=%d, ready=%d", rd_frame, ready_frame_vga_s2);
end
assign VGA_HS = ~((h_cnt>=H_VISIBLE+H_FRONT) && (h_cnt<H_VISIBLE+H_FRONT+H_SYNC_W));
assign VGA_VS = ~((v_cnt>=V_VISIBLE+V_FRONT) && (v_cnt<V_VISIBLE+V_FRONT+V_SYNC_W));

// --- SỬA LỖI PREFETCH: Kích hoạt fetch trước khi dòng mới bắt đầu ---
// H_TOTAL = 800. Khi h_cnt = 700 (đang ở Front Porch / Sync), ra lệnh fetch dòng tiếp theo!
reg prefetch_vga; always @(posedge vga_clk) prefetch_vga <= (h_cnt == 700);
wire [10:0] next_v_cnt = (v_cnt == V_TOTAL - 1) ? 0 : v_cnt + 1;
reg [10:0] fetch_line_vga; always @(posedge vga_clk) if (h_cnt == 699) fetch_line_vga <= next_v_cnt;

(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg prefetch_s1=0, prefetch_s2=0, prefetch_s3=0;
always @(posedge clk) begin prefetch_s1<=prefetch_vga; prefetch_s2<=prefetch_s1; prefetch_s3<=prefetch_s2; end
wire start_fetch = (prefetch_s3==0 && prefetch_s2==1);

(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [10:0] fetch_line_s1=0, fetch_line=0;
always @(posedge clk) begin fetch_line_s1<=fetch_line_vga; fetch_line<=fetch_line_s1; end

reg [10:0] v_cnt_latched; always @(posedge vga_clk) if (h_cnt==1) v_cnt_latched<=v_cnt;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [10:0] v_cnt_s1=0,v_cnt_s2=0;
always @(posedge clk) begin v_cnt_s1<=v_cnt_latched; v_cnt_s2<=v_cnt_s1; end

(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [1:0] ready_s1 = 0, ready_s2 = 0;
always @(posedge clk) begin ready_s1<=ready_frame_eth; ready_s2<=ready_s1; end
reg [1:0] rd_frame_prev = 0;
always @(posedge clk) begin
    if (v_cnt_s2 >= V_VISIBLE) rd_frame <= ready_s2;
    rd_frame_prev <= rd_frame;
    if (rd_frame != rd_frame_prev)
        $display("[BUFFER] SDRAM Switch: rd_frame=%d (was %d)", rd_frame, rd_frame_prev);
end

wire write_to_buf_B  = fetch_line[0];
wire read_from_buf_B = v_cnt[0];

// ==========================================================================
// 8. DOUBLE LINE BUFFER (VGA MONO8 640x480)
// ==========================================================================
(* ramstyle="M9K" *) reg [31:0] line_buf_A [0:511];
(* ramstyle="M9K" *) reg [31:0] line_buf_B [0:511];
integer i;
initial begin
    for(i=0; i<512; i=i+1) begin
        line_buf_A[i] = 32'd0;
        line_buf_B[i] = 32'd0;
    end
end
reg [8:0] buf_wr_ptr; reg buf_wr_en; reg [31:0] buf_wr_data;
always @(posedge clk) if (buf_wr_en)
    if (write_to_buf_B) line_buf_B[buf_wr_ptr] <= buf_wr_data;
    else                line_buf_A[buf_wr_ptr] <= buf_wr_data;

// SỬA LỖI PIPELINE LATENCY: Pre-fetch rd_idx trước 2 chu kỳ clock
// h_cnt hiện tại sẽ load data cho h_cnt + 2
wire [9:0] target_x = (h_cnt + 1 >= H_TOTAL) ? (h_cnt + 1 - H_TOTAL) : (h_cnt + 1);
wire [10:0] target_y = (h_cnt + 1 >= H_TOTAL) ? ((v_cnt == V_TOTAL-1) ? 0 : v_cnt + 1) : v_cnt;

wire [9:0] fetch_x = (target_x + 1 >= H_TOTAL) ? (target_x + 1 - H_TOTAL) : (target_x + 1);
wire [8:0] rd_idx = (fetch_x < 640) ? fetch_x[9:2] : 9'd0;

reg [31:0] rd_data_A, rd_data_B;
always @(posedge vga_clk) begin rd_data_A<=line_buf_A[rd_idx]; rd_data_B<=line_buf_B[rd_idx]; end
wire [31:0] pixel_word = read_from_buf_B ? rd_data_B : rd_data_A;

// Tách byte tùy theo vị trí target_x
wire [7:0] mono_pixel = (target_x[1:0] == 2'b00) ? pixel_word[31:24] :
                        (target_x[1:0] == 2'b01) ? pixel_word[23:16] :
                        (target_x[1:0] == 2'b10) ? pixel_word[15:8]  : pixel_word[7:0];

wire target_valid = (target_x < 640 && target_y < V_VISIBLE);

reg [7:0] vr,vg,vb; reg vblank;
always @(posedge vga_clk) begin
    vr <= target_valid ? mono_pixel : 8'd0; 
    vg <= target_valid ? mono_pixel : 8'd0; 
    vb <= target_valid ? mono_pixel : 8'd0; 
    vblank <= target_valid;
end
assign VGA_R=vr; assign VGA_G=vg; assign VGA_B=vb; assign VGA_BLANK_N=vblank;

// ==========================================================================
// 9. SDRAM FSM (Mượn logic từ bản Test chạy đẹp v4_test)
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

`ifdef SIMULATION
localparam INIT_WAIT=100;
`else
localparam INIT_WAIT=20000;
`endif
localparam tRP=2,tRFC=7,tMRD=2,tRCD=2,CAS_LAT=2;
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
reg [8:0]  disp_col;
reg [1:0] burst_bank; reg [8:0] burst_row; reg [6:0] burst_count;
localparam BURST_THRESHOLD=8, BURST_MAX=64;

reg fetch_req=0;
always @(posedge clk or negedge pll_sdram_locked) begin
    if (!pll_sdram_locked) fetch_req<=0;
    else begin
        if (start_fetch && fetch_line<480 && frame_ready_s) fetch_req<=1'b1;
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
        ST_RESET:      begin DRAM_CKE_r<=1; DRAM_DQM_r<=0; wait_cnt<=0; state<=ST_INIT_WAIT; $display("SDRAM: State RESET -> INIT_WAIT"); end
        ST_INIT_WAIT:  if(wait_cnt==INIT_WAIT) begin wait_cnt<=0; state<=ST_INIT_PRE; $display("SDRAM: State INIT_WAIT -> PRE"); end else wait_cnt<=wait_cnt+1;
        ST_INIT_PRE:   begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_INIT_PRE_W; $display("SDRAM: State PRECHARGE"); end
        ST_INIT_PRE_W: if(wait_cnt==tRP) begin wait_cnt<=0; state<=ST_INIT_REF; $display("SDRAM: State PRE_W -> REF"); end else wait_cnt<=wait_cnt+1;
        ST_INIT_REF:   begin send_cmd(CMD_REF); wait_cnt<=0; state<=ST_INIT_REF_W; $display("SDRAM: State REFRESH"); end
        ST_INIT_REF_W: if(wait_cnt==tRFC) begin wait_cnt<=0; if(!init_ref_done) begin init_ref_done<=1; state<=ST_INIT_REF; end else state<=ST_INIT_LM; end else wait_cnt<=wait_cnt+1;
        ST_INIT_LM:    begin send_cmd(CMD_LMR); DRAM_BA_r<=0; DRAM_ADDR_r<=MODE_REG; wait_cnt<=0; state<=ST_INIT_LM_W; $display("SDRAM: State LOAD MODE"); end
        ST_INIT_LM_W:  if(wait_cnt==tMRD) begin state<=ST_IDLE; $display("SDRAM: State LOAD_W -> IDLE (READY!)"); end else wait_cnt<=wait_cnt+1;
        
        ST_IDLE: begin
            if (refresh_cnt>=REFRESH_IV) begin refresh_cnt<=0; state<=ST_REFRESH; end
            // ƯU TIÊN SỐ 1: VGA FETCH (Line Buffer)
            else if (fetch_req) begin 
                // fetch_line * 160 = fetch_line * 128 + fetch_line * 32
                disp_addr <= ({7'd0, fetch_line} << 7) + ({9'd0, fetch_line} << 5); 
                disp_words_read<=0; buf_wr_ptr<=0; state<=ST_DISP_ACT; 
            end
            // ƯU TIÊN SỐ 2: ETHERNET WRITE (Chỉ khi VGA đã xong dòng)
            else if (!fifo_empty && fifo_rdusedw>=BURST_THRESHOLD) begin 
                burst_bank<=fifo_dout[51:50]; burst_row<=fifo_dout[49:41]; state<=ST_ETH_BURST_ACT; 
            end
        end

        ST_REFRESH:        begin send_cmd(CMD_REF); wait_cnt<=0; state<=ST_REFRESH_W; end
        ST_REFRESH_W:      if(wait_cnt==tRFC) begin wait_cnt<=0; state<=ST_IDLE; end else wait_cnt<=wait_cnt+1;

        // --- FETCH DỮ LIỆU VGA ---
        ST_DISP_ACT:       begin 
            $display("SDRAM: [RD] Frame:%d Row:%d Bank:%d", rd_frame, fetch_line, rd_frame); 
            send_cmd(CMD_ACT); 
            DRAM_BA_r <= rd_frame; // SỬA LỖI: Dùng rd_frame trực tiếp làm bank (0,1,2) thay vì skip bank 0
            DRAM_ADDR_r <= {4'd0,disp_addr[17:9]}; 
            disp_col <= disp_addr[8:0]; 
            wait_cnt <= 0; 
            state <= ST_DISP_ACT_W; 
        end
        ST_DISP_ACT_W:     if(wait_cnt==tRCD-1) begin wait_cnt<=0; state<=ST_DISP_RD; end else wait_cnt<=wait_cnt+1;
        ST_DISP_RD:        begin send_cmd(CMD_RD); DRAM_ADDR_r<={4'd0,disp_col}; DRAM_ADDR_r[10]<=0; disp_col<=disp_col+1; disp_addr<=disp_addr+1; disp_words_read<=disp_words_read+1; wait_cnt<=0; state<=ST_DISP_CAS_W; end
        // SỬA LỖI TIMING: Lệnh READ mất 1 chu kỳ tới chân pin, SDRAM mất 3 chu kỳ (CAS=3), data mất 1 chu kỳ về pin FPGA
        // Tổng delay = 5 chu kỳ. FSM cần đợi CAS_LAT + 1 (vì bản thân trạng thái ST_DISP_RD là 1 chu kỳ rồi).
        ST_DISP_CAS_W:     if(wait_cnt==CAS_LAT+1) state<=ST_DISP_CAP; else wait_cnt<=wait_cnt+1;
        // Kết thúc burst khi đủ 160 word/dòng (tương đương 640 byte Mono8)
        ST_DISP_CAP:       begin buf_wr_data<=dq_in; buf_wr_en<=1; buf_wr_ptr<=buf_wr_ptr+1; if(disp_words_read==10'd160||(disp_words_read!=0&&disp_col==9'd0)) state<=ST_DISP_PRE; else state<=ST_DISP_RD; end
        ST_DISP_PRE:       begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_DISP_PRE_W; end
        ST_DISP_PRE_W:     if(wait_cnt==tRP) begin if(disp_words_read>=160) state<=ST_IDLE; else state<=ST_DISP_ACT; end else wait_cnt<=wait_cnt+1;

        // --- GHI DỮ LIỆU ETHERNET ---
        ST_ETH_BURST_ACT:  begin $display("SDRAM: [WR] Bank:%d Row:%d", burst_bank, burst_row); send_cmd(CMD_ACT); DRAM_BA_r<=burst_bank; DRAM_ADDR_r<={4'd0,burst_row}; wait_cnt<=0; burst_count<=0; state<=ST_ETH_BURST_ACT_W; end
        ST_ETH_BURST_ACT_W:if(wait_cnt==tRCD) state<=ST_ETH_BURST_WR; else wait_cnt<=wait_cnt+1;
        ST_ETH_BURST_WR:   begin send_cmd(CMD_WR); DRAM_BA_r<=burst_bank; DRAM_ADDR_r<={4'd0,fifo_dout[40:32]}; DRAM_ADDR_r[10]<=0; DRAM_DQM_r<=0; dq_out<=fifo_dout[31:0]; dq_oe<=1; burst_count<=burst_count+1; fifo_rd<=1; state<=ST_ETH_BURST_WAIT; end
        ST_ETH_BURST_WAIT: begin dq_oe<=0; fifo_rd<=0; state<=ST_ETH_BURST_CHECK; end
        ST_ETH_BURST_CHECK:if(fifo_empty||burst_count>=BURST_MAX||fifo_dout[51:50]!=burst_bank||fifo_dout[49:41]!=burst_row) begin wait_cnt<=0; state<=ST_ETH_BURST_WR_W; end else state<=ST_ETH_BURST_WR;
        ST_ETH_BURST_WR_W: begin dq_oe<=0; fifo_rd<=0; if(wait_cnt>=2) state<=ST_ETH_BURST_PRE; else wait_cnt<=wait_cnt+1; end
        ST_ETH_BURST_PRE:  begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_ETH_BURST_PRE_W; end
        ST_ETH_BURST_PRE_W:if(wait_cnt==tRP) state<=ST_IDLE; else wait_cnt<=wait_cnt+1;
        default: state<=ST_IDLE;
        endcase
    end
end

// ==========================================================================
// 10. PROFESSIONAL DIAGNOSTICS & ASSERTIONS
// ==========================================================================
`ifdef SIMULATION
    // 10a. ASSERTIONS (Bắt lỗi ngay lập tức)
    always @(posedge clk) begin
        if (frame_ready_s && (wr_frame == rd_frame)) begin
            $display("!!! ASSERTION FAILED: Buffer Collision! WR=%d, RD=%d at time %t", wr_frame, rd_frame, $time);
            $stop; // Dừng sim để debug ngay
        end
        if (fifo_full && rx_axis_tvalid) begin
            $display("!!! ASSERTION FAILED: FIFO Overflow! Data lost at time %t", $time);
        end
    end

    // 10b. VALID TRANSACTION LOGGING (Chỉ log khi có data thực)
    always @(posedge clk_125) begin
        if (frame_start_pulse) 
            $display("[ETH] New Frame detected. Writing to Bank %d", wr_frame);
        if (rx_axis_tlast)
            $display("[ETH] Packet received. Row %d complete.", row_idx);
    end

    always @(posedge clk) begin
        if (state == ST_ETH_BURST_ACT)
            $display("[SDRAM-WR] Burst Start: Bank %d, Row %d", burst_bank, burst_row);
        if (state == ST_DISP_ACT)
            $display("[SDRAM-RD] Fetch Start: Bank %d, Line %d", rd_frame, fetch_line);
    end
`endif

assign LEDG[0] = pll_125_locked;
assign LEDG[1] = pll_sdram_locked;
assign LEDG[2] = test_mode;         // Sáng = đang ở chế độ Test Pattern
assign LEDG[3] = frame_ready;       // Sáng = đã có frame trong SDRAM
assign LEDG[8] = test_mode;         // LED xanh lớn nhất = Test Mode indicator

endmodule
