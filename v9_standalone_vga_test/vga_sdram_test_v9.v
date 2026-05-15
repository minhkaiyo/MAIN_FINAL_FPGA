module vga_sdram_test_v9 (
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
    output wire        VGA_CLK,
    output wire        VGA_HS, VGA_SYNC_N, VGA_VS
);

// ==========================================================================
// 1. PLLs (Chỉ dùng sdram_pll cho 100MHz và 25MHz)
// ==========================================================================
wire clk, clk_sdram, vga_clk, vga_clk_dac, pll_sdram_locked;
wire clk_125 = clk; // Giả lập clk_125 bằng clk hệ thống để tối giản

sdram_pll pll_sdram_inst (
    .inclk0(CLOCK_50), .c0(clk), .c1(clk_sdram),
    .c2(vga_clk), .c3(vga_clk_dac), .locked(pll_sdram_locked)
);

assign DRAM_CLK = clk_sdram;
assign VGA_CLK  = vga_clk_dac;
assign VGA_SYNC_N = 1'b0;

wire rst = ~KEY[0];

// ==========================================================================
// 2. STANDALONE TEST PATTERN GENERATOR (Always ON)
// ==========================================================================
reg [1:0]  pg_state = 0;
reg [17:0] pg_addr = 0;
reg [9:0]  pg_row = 0;
reg [7:0]  pg_col = 0;
reg        pg_valid = 0;
reg        pg_frame_start = 0;
reg [20:0] pg_wait = 0;

localparam PG_IDLE = 0, PG_FSTART = 1, PG_WRITE = 2, PG_WAIT = 3;

always @(posedge clk) begin // Chạy trên clk (100MHz) thay vì clk_125
    if (rst || !pll_sdram_locked) begin
        pg_state <= PG_IDLE; pg_valid <= 0; pg_frame_start <= 0;
    end else begin
        pg_valid <= 0; pg_frame_start <= 0;
        case (pg_state)
            PG_IDLE: begin
                pg_row <= 0; pg_col <= 0; pg_addr <= 18'h3FFFF; 
                pg_state <= PG_FSTART;
            end
            PG_FSTART: begin
                pg_frame_start <= 1;
                pg_state <= PG_WRITE;
            end
            PG_WRITE: begin
                if (!fifo_full) begin
                    pg_valid <= 1;
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
                // Chờ ~16ms (@100MHz -> 1.6M cycles)
                if (pg_wait >= 21'd1600000) pg_state <= PG_IDLE;
                else pg_wait <= pg_wait + 1;
            end
        endcase
    end
end

// Pattern: Gradient dọc (có thể đổi sang ngang để test sọc dọc/ngang)
wire [31:0] pg_word_data = {pg_row[7:0], pg_row[7:0], pg_row[7:0], pg_row[7:0]};

// ==========================================================================
// 3. PING-PONG BUFFER MANAGEMENT
// ==========================================================================
reg [1:0] wr_frame = 0, ready_frame_eth = 0;
reg [1:0] rd_frame = 0;
wire fifo_full;

wire fifo_wr = pg_valid & !fifo_full;
wire [51:0] fifo_din  = {wr_frame, pg_addr, pg_word_data};

reg [1:0] rd_frame_s1 = 0, rd_frame_s2 = 0;
always @(posedge clk) begin
    rd_frame_s1 <= rd_frame;
    rd_frame_s2 <= rd_frame_s1;
end

reg frame_ready = 0;
always @(posedge clk) begin
    if (pg_frame_start) begin
        ready_frame_eth <= wr_frame;
        frame_ready     <= 1'b1;
        wr_frame <= (rd_frame_s2 == 2'd0) ? 2'd1 : 2'd0;
    end
end

// ==========================================================================
// 4. DCFIFO (Giữ lại để giữ nguyên flow data của v8)
// ==========================================================================
wire        fifo_empty;
wire [51:0] fifo_dout;
wire [12:0] fifo_rdusedw;
reg         fifo_rd = 0;

dcfifo #(
    .intended_device_family("Cyclone IV GX"),
    .lpm_numwords(8192), .lpm_showahead("ON"),
    .lpm_type("dcfifo"), .lpm_width(52), .lpm_widthu(13),
    .overflow_checking("ON"), .underflow_checking("ON"), .use_eab("ON")
) test_fifo_inst (
    .wrclk(clk), .rdclk(clk), 
    .wrreq(fifo_wr), .rdreq(fifo_rd),
    .data(fifo_din), .q(fifo_dout),
    .wrfull(fifo_full), .rdempty(fifo_empty),
    .rdusedw(fifo_rdusedw), .aclr(~pll_sdram_locked)
);

// ==========================================================================
// 5. VGA TIMING
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

reg prefetch_vga; always @(posedge vga_clk) prefetch_vga <= (h_cnt == 700);
wire [10:0] next_v_cnt = (v_cnt == V_TOTAL - 1) ? 0 : v_cnt + 1;
reg [10:0] fetch_line_vga; always @(posedge vga_clk) if (h_cnt == 699) fetch_line_vga <= next_v_cnt;

reg prefetch_s1=0, prefetch_s2=0, prefetch_s3=0;
always @(posedge clk) begin prefetch_s1<=prefetch_vga; prefetch_s2<=prefetch_s1; prefetch_s3<=prefetch_s2; end
wire start_fetch = (prefetch_s3==0 && prefetch_s2==1);

reg [10:0] fetch_line_s1=0, fetch_line=0;
always @(posedge clk) begin fetch_line_s1<=fetch_line_vga; fetch_line<=fetch_line_s1; end

reg [10:0] v_cnt_latched; always @(posedge vga_clk) if (h_cnt==1) v_cnt_latched<=v_cnt;
reg [10:0] v_cnt_s1=0,v_cnt_s2=0;
always @(posedge clk) begin v_cnt_s1<=v_cnt_latched; v_cnt_s2<=v_cnt_s1; end

reg [1:0] ready_s1 = 0, ready_s2 = 0;
always @(posedge clk) begin ready_s1<=ready_frame_eth; ready_s2<=ready_s1; end
always @(posedge clk) if (v_cnt_s2 >= V_VISIBLE) rd_frame <= ready_s2;

wire write_to_buf_B  = fetch_line[0];
wire read_from_buf_B = v_cnt[0];

// ==========================================================================
// 6. DOUBLE LINE BUFFER
// ==========================================================================
(* ramstyle="M9K" *) reg [31:0] line_buf_A [0:511];
(* ramstyle="M9K" *) reg [31:0] line_buf_B [0:511];
reg [8:0] buf_wr_ptr; reg buf_wr_en; reg [31:0] buf_wr_data;
always @(posedge clk) if (buf_wr_en)
    if (write_to_buf_B) line_buf_B[buf_wr_ptr] <= buf_wr_data;
    else                line_buf_A[buf_wr_ptr] <= buf_wr_data;

wire [9:0] fetch_x = ((h_cnt + 2 >= H_TOTAL) ? (h_cnt + 2 - H_TOTAL) : (h_cnt + 2));
wire [8:0] rd_idx = (fetch_x < 640) ? fetch_x[9:2] : 9'd0;

reg [31:0] rd_data_A, rd_data_B;
always @(posedge vga_clk) begin rd_data_A<=line_buf_A[rd_idx]; rd_data_B<=line_buf_B[rd_idx]; end
wire [31:0] pixel_word = read_from_buf_B ? rd_data_B : rd_data_A;
wire [7:0] mono_pixel = (h_cnt[1:0] == 2'b00) ? pixel_word[31:24] :
                        (h_cnt[1:0] == 2'b01) ? pixel_word[23:16] :
                        (h_cnt[1:0] == 2'b10) ? pixel_word[15:8]  : pixel_word[7:0];

wire display_valid = (h_cnt < 640 && v_cnt < V_VISIBLE);
assign VGA_R = display_valid ? mono_pixel : 8'd0;
assign VGA_G = display_valid ? mono_pixel : 8'd0;
assign VGA_B = display_valid ? mono_pixel : 8'd0;
assign VGA_BLANK_N = display_valid;

// ==========================================================================
// 7. SDRAM FSM
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

localparam INIT_WAIT=20000;
localparam tRP=2,tRFC=7,tMRD=2,tRCD=2,CAS_LAT=3;
localparam MODE_REG=13'b000_0_00_011_0_000; // Bit [6:4] = 011 -> CAS Latency 3
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
reg [17:0] disp_addr; reg [9:0] disp_words_read; reg [8:0] disp_col;
reg [1:0] burst_bank; reg [8:0] burst_row; reg [6:0] burst_count;
localparam BURST_THRESHOLD=8, BURST_MAX=64;

reg fetch_req=0;
always @(posedge clk or negedge pll_sdram_locked) begin
    if (!pll_sdram_locked) fetch_req<=0;
    else begin
        if (start_fetch && fetch_line<480 && frame_ready) fetch_req<=1'b1;
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
        ST_INIT_WAIT:  if(wait_cnt==INIT_WAIT) begin wait_cnt<=0; state<=ST_INIT_PRE; end else wait_cnt<=wait_cnt+1;
        ST_INIT_PRE:   begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_INIT_PRE_W; end
        ST_INIT_PRE_W: if(wait_cnt==tRP) begin wait_cnt<=0; state<=ST_INIT_REF; end else wait_cnt<=wait_cnt+1;
        ST_INIT_REF:   begin send_cmd(CMD_REF); wait_cnt<=0; state<=ST_INIT_REF_W; end
        ST_INIT_REF_W: if(wait_cnt==tRFC) begin wait_cnt<=0; if(!init_ref_done) begin init_ref_done<=1; state<=ST_INIT_REF; end else state<=ST_INIT_LM; end else wait_cnt<=wait_cnt+1;
        ST_INIT_LM:    begin send_cmd(CMD_LMR); DRAM_BA_r<=0; DRAM_ADDR_r<=MODE_REG; wait_cnt<=0; state<=ST_INIT_LM_W; end
        ST_INIT_LM_W:  if(wait_cnt==tMRD) state<=ST_IDLE; else wait_cnt<=wait_cnt+1;
        ST_IDLE: begin
            if (refresh_cnt>=REFRESH_IV) begin refresh_cnt<=0; state<=ST_REFRESH; end
            else if (fetch_req) begin 
                disp_addr <= ({7'd0, fetch_line} << 7) + ({9'd0, fetch_line} << 5); 
                disp_words_read<=0; buf_wr_ptr<=0; state<=ST_DISP_ACT; 
            end
            else if (!fifo_empty && fifo_rdusedw>=BURST_THRESHOLD) begin 
                burst_bank<=fifo_dout[51:50]; burst_row<=fifo_dout[49:41]; state<=ST_ETH_BURST_ACT; 
            end
        end
        ST_REFRESH:        begin send_cmd(CMD_REF); wait_cnt<=0; state<=ST_REFRESH_W; end
        ST_REFRESH_W:      if(wait_cnt==tRFC) begin wait_cnt<=0; state<=ST_IDLE; end else wait_cnt<=wait_cnt+1;
        ST_DISP_ACT:       begin send_cmd(CMD_ACT); DRAM_BA_r<=rd_frame; DRAM_ADDR_r<={4'd0,disp_addr[17:9]}; disp_col<=disp_addr[8:0]; wait_cnt<=0; state<=ST_DISP_ACT_W; end
        ST_DISP_ACT_W:     if(wait_cnt==tRCD-1) begin wait_cnt<=0; state<=ST_DISP_RD; end else wait_cnt<=wait_cnt+1;
        ST_DISP_RD:        begin send_cmd(CMD_RD); DRAM_ADDR_r<={4'd0,disp_col}; DRAM_ADDR_r[10]<=0; disp_col<=disp_col+1; disp_addr<=disp_addr+1; disp_words_read<=disp_words_read+1; wait_cnt<=0; state<=ST_DISP_CAS_W; end
        ST_DISP_CAS_W:     if(wait_cnt==CAS_LAT) state<=ST_DISP_CAP; else wait_cnt<=wait_cnt+1;
        ST_DISP_CAP:       begin buf_wr_data<=dq_in; buf_wr_en<=1; buf_wr_ptr<=buf_wr_ptr+1; if(disp_words_read==10'd160||(disp_words_read!=0&&disp_col==9'd0)) state<=ST_DISP_PRE; else state<=ST_DISP_RD; end
        ST_DISP_PRE:       begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_DISP_PRE_W; end
        ST_DISP_PRE_W:     if(wait_cnt==tRP) begin if(disp_words_read>=160) state<=ST_IDLE; else state<=ST_DISP_ACT; end else wait_cnt<=wait_cnt+1;
        ST_ETH_BURST_ACT:  begin send_cmd(CMD_ACT); DRAM_BA_r<=burst_bank; DRAM_ADDR_r<={4'd0,burst_row}; wait_cnt<=0; burst_count<=0; state<=ST_ETH_BURST_ACT_W; end
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

assign LEDG[0] = pll_sdram_locked;
assign LEDG[1] = pll_sdram_locked;
assign LEDG[2] = frame_ready;
assign LEDG[3] = frame_ready;

endmodule
