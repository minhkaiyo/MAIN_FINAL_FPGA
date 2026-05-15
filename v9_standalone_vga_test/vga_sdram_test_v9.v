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
// 1. PLLs
// ==========================================================================
wire clk, clk_sdram, vga_clk, vga_clk_dac, pll_locked;
sdram_pll pll_inst (
    .inclk0(CLOCK_50), .c0(clk), .c1(clk_sdram),
    .c2(vga_clk), .c3(vga_clk_dac), .locked(pll_locked)
);
assign DRAM_CLK   = clk_sdram;
assign VGA_CLK    = vga_clk_dac;
assign VGA_SYNC_N = 1'b0;

wire rst = ~KEY[0];

// ==========================================================================
// 2. PATTERN GENERATOR (Dùng logic đơn giản để test)
// ==========================================================================
reg [17:0] pg_addr = 0;
reg [9:0]  pg_row = 0;
reg [7:0]  pg_col = 0;
reg        pg_valid = 0;
reg        pg_frame_start = 0;
reg [1:0]  pg_state = 0;
reg [20:0] pg_wait = 0;

always @(posedge clk) begin
    if (rst || !pll_locked) begin
        pg_state <= 0; pg_valid <= 0; pg_frame_start <= 0;
    end else begin
        pg_valid <= 0; pg_frame_start <= 0;
        case (pg_state)
            0: begin pg_row <= 0; pg_col <= 0; pg_addr <= 18'h3FFFF; pg_state <= 1; end
            1: begin pg_frame_start <= 1; pg_state <= 2; end
            2: begin
                if (!fifo_full) begin
                    pg_valid <= 1;
                    if (pg_col == 159) begin
                        pg_col <= 0;
                        if (pg_row == 479) pg_state <= 3;
                        else pg_row <= pg_row + 1;
                    end else pg_col <= pg_col + 1;
                    pg_addr <= pg_addr + 1;
                end
            end
            3: begin if (pg_wait >= 1600000) begin pg_wait <= 0; pg_state <= 0; end else pg_wait <= pg_wait + 1; end
        endcase
    end
end
wire [31:0] pg_data = {pg_row[7:0], pg_row[7:0], pg_row[7:0], pg_row[7:0]};

// ==========================================================================
// 3. FIFO & BUFFER (Domain Crossing)
// ==========================================================================
reg [1:0] wr_frame = 0, rd_frame_eth = 0;
wire fifo_full, fifo_empty;
wire [51:0] fifo_dout;
wire [12:0] fifo_rdusedw;
reg fifo_rd = 0;

always @(posedge clk) if (pg_frame_start) begin rd_frame_eth <= wr_frame; wr_frame <= ~wr_frame; end

dcfifo #(
    .lpm_numwords(8192), .lpm_showahead("ON"), .lpm_width(52), .lpm_widthu(13)
) test_fifo (
    .wrclk(clk), .rdclk(clk), .wrreq(pg_valid && !fifo_full), .rdreq(fifo_rd),
    .data({wr_frame, pg_addr, pg_data}), .q(fifo_dout),
    .wrfull(fifo_full), .rdempty(fifo_empty), .rdusedw(fifo_rdusedw), .aclr(rst)
);

// ==========================================================================
// 4. VGA TIMING (Copy sát bài mẫu)
// ==========================================================================
localparam H_VISIBLE=640, H_FRONT=16, H_SYNC_W=96, H_BACK=48, H_TOTAL=800;
localparam V_VISIBLE=480, V_FRONT=10, V_SYNC_W=2,  V_BACK=33, V_TOTAL=525;
reg [9:0] h_cnt=0; reg [10:0] v_cnt=0;
always @(posedge vga_clk) begin
    if (h_cnt == H_TOTAL-1) begin h_cnt <= 0; v_cnt <= (v_cnt == V_TOTAL-1) ? 0 : v_cnt + 1; end
    else h_cnt <= h_cnt + 1;
end
assign VGA_HS = ~((h_cnt >= H_VISIBLE+H_FRONT) && (h_cnt < H_VISIBLE+H_FRONT+H_SYNC_W));
assign VGA_VS = ~((v_cnt >= V_VISIBLE+V_FRONT) && (v_cnt < V_VISIBLE+V_FRONT+V_SYNC_W));

// Sync/Trigger fetch
reg h_start_vga; always @(posedge vga_clk) h_start_vga <= (h_cnt == 0);
reg h_s1, h_s2, h_s3; always @(posedge clk) begin h_s1 <= h_start_vga; h_s2 <= h_s1; h_s3 <= h_s2; end
wire start_fetch = (h_s3 == 0 && h_s2 == 1);

reg [10:0] v_cnt_s1, v_cnt_s2; always @(posedge clk) begin v_cnt_s1 <= v_cnt; v_cnt_s2 <= v_cnt_s1; end
reg rd_frame = 0; always @(posedge clk) if (v_cnt_s2 >= V_VISIBLE) rd_frame <= rd_frame_eth;

wire [10:0] fetch_line = (v_cnt_s2 == V_TOTAL-1) ? 0 : v_cnt_s2 + 1;
reg fetch_req = 0;
always @(posedge clk) begin
    if (start_fetch && fetch_line < 480) fetch_req <= 1;
    if (state == 11 && disp_words_read == 0) fetch_req <= 0;
end

// ==========================================================================
// 5. LINE BUFFER & PIXEL SELECT (Fixed Alignment)
// ==========================================================================
(* ramstyle="M9K" *) reg [31:0] line_buf_A [0:511], line_buf_B [0:511];
reg buf_wr_en; reg [8:0] buf_wr_ptr; reg [31:0] buf_wr_data;
always @(posedge clk) if (buf_wr_en) begin
    if (fetch_line[0]) line_buf_B[buf_wr_ptr] <= buf_wr_data;
    else               line_buf_A[buf_wr_ptr] <= buf_wr_data;
end

// Read Port
wire [8:0] rd_idx = h_cnt[9:2];
reg [31:0] rd_data_A, rd_data_B;
always @(posedge vga_clk) begin rd_data_A <= line_buf_A[rd_idx]; rd_data_B <= line_buf_B[rd_idx]; end

// FIX: Delay bộ chọn pixel 2 nhịp để khớp BRAM Latency
reg [1:0] h_cnt_d1, h_cnt_d2;
always @(posedge vga_clk) begin h_cnt_d1 <= h_cnt[1:0]; h_cnt_d2 <= h_cnt_d1; end

wire [31:0] pixel_word = v_cnt[0] ? rd_data_B : rd_data_A;
wire [7:0] mono_pixel = (h_cnt_d2 == 2'b00) ? pixel_word[31:24] :
                        (h_cnt_d2 == 2'b01) ? pixel_word[23:16] :
                        (h_cnt_d2 == 2'b10) ? pixel_word[15:8]  : pixel_word[7:0];

// Registered Output (Chống nhiễu)
reg [7:0] vr, vg, vb; reg vblank;
wire disp_act = (h_cnt < 640 && v_cnt < 480);
always @(posedge vga_clk) begin
    vr <= disp_act ? mono_pixel : 0;
    vg <= disp_act ? mono_pixel : 0;
    vb <= disp_act ? mono_pixel : 0;
    vblank <= disp_act;
end
assign VGA_R = vr; assign VGA_G = vg; assign VGA_B = vb; assign VGA_BLANK_N = vblank;

// ==========================================================================
// 6. SDRAM FSM (Copy sát bài mẫu + Write Recovery)
// ==========================================================================
reg [31:0] dq_out; reg dq_oe = 0; assign DRAM_DQ = dq_oe ? dq_out : 32'bz;
wire [31:0] dq_in = DRAM_DQ;
localparam CMD_NOP=4'b0111, CMD_ACT=4'b0011, CMD_RD=4'b0101, CMD_WR=4'b0100, CMD_PRE=4'b0010, CMD_REF=4'b0001, CMD_LMR=4'b0000;
reg DRAM_CKE_r, DRAM_CS_N_r, DRAM_RAS_N_r, DRAM_CAS_N_r, DRAM_WE_N_r;
reg [12:0] DRAM_ADDR_r; reg [1:0] DRAM_BA_r; reg [3:0] DRAM_DQM_r;
assign {DRAM_CKE, DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N} = {DRAM_CKE_r, DRAM_CS_N_r, DRAM_RAS_N_r, DRAM_CAS_N_r, DRAM_WE_N_r};
assign DRAM_ADDR = DRAM_ADDR_r; assign DRAM_BA = DRAM_BA_r; assign DRAM_DQM = DRAM_DQM_r;
task send_cmd; input [3:0] cmd; begin {DRAM_CS_N_r, DRAM_RAS_N_r, DRAM_CAS_N_r, DRAM_WE_N_r} <= cmd; end endtask

localparam tRP=3, tRFC=7, tMRD=2, tRCD=3, CAS_LAT=3;
reg [4:0] state = 0; reg [15:0] wait_cnt = 0; reg [9:0] refresh_cnt = 0;
reg [17:0] d_addr; reg [8:0] d_col, d_read;

always @(posedge clk) begin
    if (rst || !pll_locked) begin state <= 0; DRAM_CKE_r <= 0; DRAM_DQM_r <= 4'b1111; dq_oe <= 0; end
    else begin
        send_cmd(CMD_NOP); dq_oe <= 0; buf_wr_en <= 0; fifo_rd <= 0;
        if (refresh_cnt < 780) refresh_cnt <= refresh_cnt + 1;
        case (state)
            0: begin DRAM_CKE_r <= 1; DRAM_DQM_r <= 0; wait_cnt <= 0; state <= 1; end
            1: if (wait_cnt == 20000) begin wait_cnt <= 0; state <= 2; end else wait_cnt <= wait_cnt + 1;
            2: begin send_cmd(CMD_PRE); DRAM_ADDR_r[10] <= 1; wait_cnt <= 0; state <= 3; end
            3: if (wait_cnt == tRP) begin wait_cnt <= 0; state <= 4; end else wait_cnt <= wait_cnt + 1;
            4: begin send_cmd(CMD_REF); wait_cnt <= 0; state <= 5; end
            5: if (wait_cnt == tRFC) begin wait_cnt <= 0; state <= 6; end else wait_cnt <= wait_cnt + 1;
            6: begin send_cmd(CMD_LMR); DRAM_BA_r <= 0; DRAM_ADDR_r <= 13'b000_0_00_011_0_000; wait_cnt <= 0; state <= 7; end
            7: if (wait_cnt == tMRD) state <= 8; else wait_cnt <= wait_cnt + 1;
            
            8: begin
                if (refresh_cnt >= 780) begin refresh_cnt <= 0; state <= 9; end
                else if (fetch_req) begin d_addr <= fetch_line * 160; d_read <= 0; buf_wr_ptr <= 0; state <= 11; end
                else if (!fifo_empty && fifo_rdusedw >= 8) state <= 18;
            end
            9: begin send_cmd(CMD_REF); wait_cnt <= 0; state <= 10; end
            10: if (wait_cnt == tRFC) state <= 8; else wait_cnt <= wait_cnt + 1;
            
            11: begin send_cmd(CMD_ACT); DRAM_BA_r <= rd_frame; DRAM_ADDR_r <= {4'd0, d_addr[17:9]}; d_col <= d_addr[8:0]; wait_cnt <= 0; state <= 12; end
            12: if (wait_cnt == tRCD-1) state <= 13; else wait_cnt <= wait_cnt + 1;
            13: begin send_cmd(CMD_RD); DRAM_ADDR_r <= {4'd0, d_col}; d_col <= d_col + 1; d_addr <= d_addr + 1; d_read <= d_read + 1; wait_cnt <= 0; state <= 14; end
            14: if (wait_cnt == CAS_LAT) state <= 15; else wait_cnt <= wait_cnt + 1;
            15: begin buf_wr_data <= dq_in; buf_wr_en <= 1; buf_wr_ptr <= buf_wr_ptr + 1; if (d_read == 160 || d_col == 0) state <= 16; else state <= 13; end
            16: begin send_cmd(CMD_PRE); DRAM_ADDR_r[10] <= 1; wait_cnt <= 0; state <= 17; end
            17: if (wait_cnt == tRP) begin if (d_read >= 160) state <= 8; else state <= 11; end else wait_cnt <= wait_cnt + 1;
            
            18: begin send_cmd(CMD_ACT); DRAM_BA_r <= fifo_dout[51:50]; DRAM_ADDR_r <= {4'd0, fifo_dout[49:41]}; wait_cnt <= 0; state <= 19; end
            19: if (wait_cnt == tRCD-1) state <= 20; else wait_cnt <= wait_cnt + 1;
            20: begin send_cmd(CMD_WR); DRAM_ADDR_r <= {4'd0, fifo_dout[40:32]}; dq_out <= fifo_dout[31:0]; dq_oe <= 1; fifo_rd <= 1; wait_cnt <= 0; state <= 23; end
            23: begin dq_oe <= 1; if (wait_cnt >= 2) state <= 21; else wait_cnt <= wait_cnt + 1; end
            21: begin send_cmd(CMD_PRE); DRAM_ADDR_r[10] <= 1; wait_cnt <= 0; state <= 22; end
            22: if (wait_cnt == tRP) state <= 8; else wait_cnt <= wait_cnt + 1;
        endcase
    end
end

assign LEDG = {pll_locked, frame_ready, rd_frame, wr_frame, 5'b0};

endmodule
