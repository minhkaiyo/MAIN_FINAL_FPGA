// vga_sdram_test_fixed.v
// Fixed version — các lỗi nhiễu đã được sửa:
//   1. SDRAM write: burst toàn bộ row trước khi PRE, không nhảy về IDLE giữa chừng
//   2. gen_data pipeline: tính trước 1 cycle, đồng bộ với gen_addr write
//   3. disp_col: dùng đúng column offset trong row (addr[8:0])
//   4. Read pipeline: thêm 1 cycle capture delay cho dq_in ổn định
//   5. Pixel output: sửa h_cnt_d1 delay để alignment đúng
//   6. Line buffer: dùng ping-pong rõ ràng, tránh conflict vùng boundary

module vga_sdram_test (
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

    output wire [8:0]  LEDG
);

// ---------------------------------------------------------------------------
// Clocking
// ---------------------------------------------------------------------------
wire clk, clk_sdram, vga_clk, vga_clk_dac, locked;
sdram_pll pll_inst (
    .inclk0   (CLOCK_50),
    .c0       (clk),         // 100 MHz FSM
    .c1       (clk_sdram),   // 100 MHz -90 deg DRAM
    .c2       (vga_clk),     // 25 MHz pixel logic
    .c3       (vga_clk_dac), // 25 MHz -10 ns DAC
    .locked   (locked)
);

assign DRAM_CLK   = clk_sdram;
assign VGA_CLK    = vga_clk_dac;
assign VGA_SYNC_N = 1'b0;

// ---------------------------------------------------------------------------
// VGA Timing  640x480 @ 60 Hz
// ---------------------------------------------------------------------------
localparam H_VISIBLE = 640, H_FRONT = 16, H_SYNC_W = 96, H_BACK = 48, H_TOTAL = 800;
localparam V_VISIBLE = 480, V_FRONT = 10, V_SYNC_W = 2,  V_BACK  = 33, V_TOTAL = 525;

reg [9:0]  h_cnt = 0;
reg [10:0] v_cnt = 0;

always @(posedge vga_clk) begin
    if (h_cnt == H_TOTAL - 1) begin
        h_cnt <= 0;
        v_cnt <= (v_cnt == V_TOTAL - 1) ? 11'd0 : v_cnt + 1'b1;
    end else begin
        h_cnt <= h_cnt + 1'b1;
    end
end

// Sync pulses — registered for clean edges
reg vga_hs_r, vga_vs_r;
always @(posedge vga_clk) begin
    vga_hs_r <= ~((h_cnt >= H_VISIBLE + H_FRONT) && (h_cnt < H_VISIBLE + H_FRONT + H_SYNC_W));
    vga_vs_r <= ~((v_cnt >= V_VISIBLE + V_FRONT) && (v_cnt < V_VISIBLE + V_FRONT + V_SYNC_W));
end
assign VGA_HS = vga_hs_r;
assign VGA_VS = vga_vs_r;

// ---------------------------------------------------------------------------
// Line-start pulse (vga_clk → clk CDC via 3-FF edge detect)
// ---------------------------------------------------------------------------
// FIX: pulse exactly at h_cnt==1 (not 0) so the FSM sees it 1 cycle after
//      the counter wraps, giving stable fetch_line.
reg [2:0] h_sync_edge = 0;
wire      h_line_start_vga = (h_cnt == 1);
always @(posedge clk) h_sync_edge <= {h_sync_edge[1:0], h_line_start_vga};
wire start_fetch = (h_sync_edge[2:1] == 2'b01);

// Which SDRAM line to prefetch (next line, clamped)
wire [10:0] fetch_line     = (v_cnt == V_TOTAL - 1) ? 11'd0 : (v_cnt + 11'd1);
// Ping-pong buffer select: write into buffer whose index matches fetch_line LSB,
// read from buffer whose index matches the *current* display line LSB.
wire        write_to_buf_B = fetch_line[0];
wire        read_from_buf_B = v_cnt[0];

// ---------------------------------------------------------------------------
// Line Buffers  (160 × 32-bit = 640 pixels packed as RGB332)
// ---------------------------------------------------------------------------
(* ramstyle = "M9K" *) reg [31:0] line_buf_A [0:159];
(* ramstyle = "M9K" *) reg [31:0] line_buf_B [0:159];

reg [7:0]  buf_wr_ptr;
reg        buf_wr_en;
reg [31:0] buf_wr_data;

always @(posedge clk) begin
    if (buf_wr_en) begin
        if (write_to_buf_B) line_buf_B[buf_wr_ptr] <= buf_wr_data;
        else                line_buf_A[buf_wr_ptr] <= buf_wr_data;
    end
end

// Read side — use h_cnt >> 2 as word index.
// rd_idx is combinational from h_cnt so the register gets the *next* word
// one pixel clock early — that aligns with the 1-cycle register latency.
wire [7:0] rd_idx = h_cnt[9:2];
reg [31:0] rd_data_A, rd_data_B;
always @(posedge vga_clk) begin
    rd_data_A <= line_buf_A[rd_idx];
    rd_data_B <= line_buf_B[rd_idx];
end
wire [31:0] pixel_word = read_from_buf_B ? rd_data_B : rd_data_A;

// FIX: delay h_cnt[1:0] by 1 cycle to match the 1-cycle RAM read latency.
// Without this the byte-select mux is 1 pixel ahead of the actual data.
reg [1:0] h_cnt_d1;
always @(posedge vga_clk) h_cnt_d1 <= h_cnt[1:0];

wire [7:0] pixel_byte =
    (h_cnt_d1 == 2'd0) ? pixel_word[ 7: 0] :
    (h_cnt_d1 == 2'd1) ? pixel_word[15: 8] :
    (h_cnt_d1 == 2'd2) ? pixel_word[23:16] :
                         pixel_word[31:24] ;

// RGB332 → RGB888 expansion
wire [7:0] r8 = {pixel_byte[7:5], pixel_byte[7:5], pixel_byte[7:6]};
wire [7:0] g8 = {pixel_byte[4:2], pixel_byte[4:2], pixel_byte[4:3]};
wire [7:0] b8 = {pixel_byte[1:0], pixel_byte[1:0], pixel_byte[1:0], pixel_byte[1:0]};

// FIX: delay active flags 1 cycle to align with RAM read latency
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

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Color-bar pattern generator (Dynamic Motion)
// ---------------------------------------------------------------------------
reg  [17:0] gen_addr   = 0;
reg  [9:0]  gen_x      = 0;
reg         gen_active = 0;
reg  [7:0]  move_offset = 0;

function [7:0] bar_color;
    input [9:0] x;
    begin
        if      (x < 80)  bar_color = 8'hFF; // White
        else if (x < 160) bar_color = 8'hFC; // Yellow
        else if (x < 240) bar_color = 8'h1F; // Cyan
        else if (x < 320) bar_color = 8'h1C; // Green
        else if (x < 400) bar_color = 8'hE3; // Magenta
        else if (x < 480) bar_color = 8'hE0; // Red
        else if (x < 560) bar_color = 8'h03; // Blue
        else              bar_color = 8'h00; // Black
    end
endfunction

// Pack 4 pixels with move_offset
wire [31:0] gen_data_comb = {
    bar_color(gen_x + move_offset + 10'd3),
    bar_color(gen_x + move_offset + 10'd2),
    bar_color(gen_x + move_offset + 10'd1),
    bar_color(gen_x + move_offset + 10'd0)
};

// ---------------------------------------------------------------------------
// SDRAM interface registers & FSM State
// ---------------------------------------------------------------------------
reg [31:0] dq_out;
reg        dq_oe = 0;
assign DRAM_DQ = dq_oe ? dq_out : 32'bz;
wire [31:0] dq_in = DRAM_DQ;

localparam CMD_NOP = 4'b0111, CMD_ACT = 4'b0011, CMD_RD = 4'b0101, 
           CMD_WR  = 4'b0100, CMD_PRE = 4'b0010, CMD_REF = 4'b0001, CMD_LMR = 4'b0000;

reg [3:0]  dram_cmd;
reg [12:0] dram_addr_r;
reg [1:0]  dram_ba_r;
assign {DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N} = dram_cmd;
assign DRAM_ADDR = dram_addr_r;
assign DRAM_BA   = dram_ba_r;
assign DRAM_CKE  = 1'b1;
assign DRAM_DQM  = 4'b0000;

localparam INIT_WAIT = 20000; 
localparam tRP = 2, tRFC = 7, tMRD = 2, tRCD = 2, CAS_LAT = 2;
localparam MODE_REG = 13'b000_0_00_010_0_000; 

localparam [4:0]
    ST_RESET       = 0,  ST_INIT_WAIT   = 1,  ST_INIT_PRE    = 2,  ST_INIT_PRE_W  = 3,
    ST_INIT_REF    = 4,  ST_INIT_REF_W  = 5,  ST_INIT_LM     = 6,  ST_INIT_LM_W   = 7,
    ST_IDLE        = 8,  ST_REFRESH     = 9,  ST_REFRESH_W   = 10,
    ST_DISP_ACT    = 11, ST_DISP_ACT_W  = 12, ST_DISP_RD     = 13, ST_DISP_CAS_W  = 14,
    ST_DISP_CAP    = 15, ST_DISP_PRE    = 16, ST_DISP_PRE_W  = 17,
    ST_GEN_ACT     = 18, ST_GEN_ACT_W   = 19, ST_GEN_WR      = 20, ST_GEN_WR_W    = 21,
    ST_GEN_PRE     = 22, ST_GEN_PRE_W   = 23;

reg [4:0]  state = ST_RESET;
reg [15:0] wait_cnt = 0;
reg [9:0]  refresh_cnt = 0;
reg [17:0] disp_addr;
reg [8:0]  disp_words_read;
reg [8:0]  disp_col;
reg        init_ref_done = 0;
reg        vsync_d1;

always @(posedge clk or negedge locked) begin
    if (!locked) begin
        state <= ST_RESET; dram_cmd <= CMD_NOP; dq_oe <= 0; buf_wr_en <= 0; refresh_cnt <= 0;
        gen_addr <= 0; gen_x <= 0; move_offset <= 0; gen_active <= 0;
        init_ref_done <= 0; vsync_d1 <= 0;
    end else begin
        dram_cmd <= CMD_NOP; dq_oe <= 0; buf_wr_en <= 0;
        vsync_d1 <= VGA_VS;
        
        // Motion Trigger: Bat dau ghi frame moi khi VSYNC canh len
        if (vsync_d1 == 1'b0 && VGA_VS == 1'b1) begin
            gen_active <= 1;
            gen_addr <= 0;
            gen_x <= 0;
            move_offset <= move_offset + 1'b1;
        end

        if (refresh_cnt < 780) refresh_cnt <= refresh_cnt + 1'b1;

        case (state)
            ST_RESET:      begin wait_cnt <= 0; state <= ST_INIT_WAIT; end
            ST_INIT_WAIT:  if (wait_cnt == INIT_WAIT) begin wait_cnt <= 0; state <= ST_INIT_PRE; end else wait_cnt <= wait_cnt + 1'b1;
            ST_INIT_PRE:   begin dram_cmd <= CMD_PRE; dram_addr_r[10] <= 1; wait_cnt <= 0; state <= ST_INIT_PRE_W; end
            ST_INIT_PRE_W: if (wait_cnt == tRP) begin wait_cnt <= 0; state <= ST_INIT_REF; end else wait_cnt <= wait_cnt + 1'b1;
            ST_INIT_REF:   begin dram_cmd <= CMD_REF; wait_cnt <= 0; state <= ST_INIT_REF_W; end
            ST_INIT_REF_W: if (wait_cnt == tRFC) begin wait_cnt <= 0; if (!init_ref_done) begin init_ref_done <= 1; state <= ST_INIT_REF; end else state <= ST_INIT_LM; end else wait_cnt <= wait_cnt + 1'b1;
            ST_INIT_LM:    begin dram_cmd <= CMD_LMR; dram_ba_r <= 0; dram_addr_r <= MODE_REG; wait_cnt <= 0; state <= ST_INIT_LM_W; end
            ST_INIT_LM_W:  if (wait_cnt == tMRD) state <= ST_IDLE; else wait_cnt <= wait_cnt + 1'b1;

            ST_IDLE: begin
                if (refresh_cnt >= 780) begin
                    refresh_cnt <= 0;
                    state <= ST_REFRESH;
                end
                else if (start_fetch && (fetch_line < V_VISIBLE)) begin
                    disp_addr <= fetch_line * 18'd160;
                    disp_words_read <= 0;
                    buf_wr_ptr <= 0;
                    state <= ST_DISP_ACT;
                end 
                else if (gen_active) begin
                    state <= ST_GEN_ACT;
                end
            end

            ST_REFRESH:   begin dram_cmd <= CMD_REF; wait_cnt <= 0; state <= ST_REFRESH_W; end
            ST_REFRESH_W: if (wait_cnt == tRFC) begin wait_cnt <= 0; state <= ST_IDLE; end else wait_cnt <= wait_cnt + 1'b1;

            ST_DISP_ACT: begin
                dram_cmd <= CMD_ACT; dram_ba_r <= 0; dram_addr_r <= disp_addr[17:9];
                disp_col <= disp_addr[8:0]; wait_cnt <= 0; state <= ST_DISP_ACT_W;
            end
            ST_DISP_ACT_W: if (wait_cnt == tRCD) begin wait_cnt <= 0; state <= ST_DISP_RD; end else wait_cnt <= wait_cnt + 1'b1;
            ST_DISP_RD: begin
                dram_cmd <= CMD_RD; dram_addr_r <= {4'd0, disp_col}; dram_addr_r[10] <= 0;
                disp_col <= disp_col + 1'b1; disp_addr <= disp_addr + 1'b1;
                disp_words_read <= disp_words_read + 1'b1; wait_cnt <= 0; state <= ST_DISP_CAS_W;
            end
            ST_DISP_CAS_W: begin
                if (wait_cnt == CAS_LAT) begin
                    wait_cnt <= 0;
                    state <= ST_DISP_CAP;
                end else wait_cnt <= wait_cnt + 1'b1;
            end
            ST_DISP_CAP: begin
                buf_wr_data <= dq_in; buf_wr_en <= 1'b1; buf_wr_ptr <= buf_wr_ptr + 1'b1;
                if (disp_words_read >= 9'd160 || disp_col == 9'd0) state <= ST_DISP_PRE;
                else state <= ST_DISP_RD;
            end
            ST_DISP_PRE:   begin dram_cmd <= CMD_PRE; dram_addr_r[10] <= 1; wait_cnt <= 0; state <= ST_DISP_PRE_W; end
            ST_DISP_PRE_W: if (wait_cnt == tRP) begin
                if (disp_words_read < 9'd160) state <= ST_DISP_ACT;
                else state <= ST_IDLE;
            end else wait_cnt <= wait_cnt + 1'b1;

            ST_GEN_ACT:   begin dram_cmd <= CMD_ACT; dram_ba_r <= 0; dram_addr_r <= gen_addr[17:9]; wait_cnt <= 0; state <= ST_GEN_ACT_W; end
            ST_GEN_ACT_W: if (wait_cnt == tRCD) begin wait_cnt <= 0; state <= ST_GEN_WR; end else wait_cnt <= wait_cnt + 1'b1;
            ST_GEN_WR: begin
                dram_cmd <= CMD_WR; dram_addr_r <= {4'd0, gen_addr[8:0]}; dram_addr_r[10] <= 0;
                dq_out <= gen_data_comb; dq_oe <= 1'b1;
                gen_addr <= gen_addr + 1'b1;
                if (gen_x >= 10'd636) gen_x <= 0;
                else                  gen_x <= gen_x + 10'd4;
                state <= ST_GEN_WR_W;
            end
            ST_GEN_WR_W: begin
                if (gen_addr == 18'd76800) begin
                    gen_active <= 0; // Xong frame
                    state <= ST_GEN_PRE;
                end else if (gen_addr[8:0] == 9'd0) begin
                    state <= ST_GEN_PRE;
                end else begin
                    state <= ST_GEN_WR;
                end
            end
            ST_GEN_PRE:   begin dram_cmd <= CMD_PRE; dram_addr_r[10] <= 1; wait_cnt <= 0; state <= ST_GEN_PRE_W; end
            ST_GEN_PRE_W: if (wait_cnt == tRP) state <= ST_IDLE; else wait_cnt <= wait_cnt + 1'b1;

            default: state <= ST_RESET;
        endcase
    end
end
endmodule