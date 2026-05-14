// sdram_vga_noeth_test.v
// Test VGA + SDRAM
// KEY[0]: Reset hệ thống (Nhấn giữ để reset)
// SW[17]: ON = Vẽ trực tiếp Color Bar (Bypass SDRAM)
// SW[16]: ON = Ghi/Đọc Color Bar qua SDRAM

`timescale 1ns / 1ps

module sdram_vga_noeth_test (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [17:0] SW,
    output wire [8:0]  LEDG,

    // SDRAM
    output wire [12:0] DRAM_ADDR,
    output wire [1:0]  DRAM_BA,
    output wire        DRAM_CAS_N, DRAM_CKE, DRAM_CLK, DRAM_CS_N,
    inout  wire [31:0] DRAM_DQ,
    output wire [3:0]  DRAM_DQM,
    output wire        DRAM_RAS_N, DRAM_WE_N,

    // VGA
    output wire [7:0]  VGA_B, VGA_G, VGA_R,
    output wire        VGA_BLANK_N, VGA_CLK, VGA_HS, VGA_SYNC_N, VGA_VS
);

// 1. Clocking
wire clk, clk_sdram, vga_clk, vga_clk_dac, pll_locked;
sdram_pll pll_inst (
    .inclk0(CLOCK_50), 
    .c0(clk),           // 100MHz
    .c1(clk_sdram),     // 100MHz (-3ns)
    .c2(vga_clk),       // 25.175MHz
    .c3(vga_clk_dac),   // 25.175MHz (DAC)
    .locked(pll_locked)
);
assign DRAM_CLK   = clk_sdram;
assign VGA_CLK    = vga_clk_dac; 
assign VGA_SYNC_N = 1'b0;

// Reset kết hợp cả PLL Lock và Nút KEY[0]
wire sys_rst_n = KEY[0] & pll_locked;

wire dbg_direct_vga    = SW[17];
wire dbg_sdram_pattern = SW[16];

// 2. VGA TIMING
localparam H_VISIBLE=640, H_FRONT=16, H_SYNC_W=96, H_BACK=48, H_TOTAL=800;
localparam V_VISIBLE=480, V_FRONT=10, V_SYNC_W=2,  V_BACK=33, V_TOTAL=525;
reg [9:0] h_cnt=0; reg [10:0] v_cnt=0;
always @(posedge vga_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin h_cnt <= 0; v_cnt <= 0; end
    else begin
        if (h_cnt==H_TOTAL-1) begin h_cnt<=0; v_cnt<=(v_cnt==V_TOTAL-1)?0:v_cnt+1; end
        else h_cnt<=h_cnt+1;
    end
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

// Sync VGA -> Logic Clock
reg [2:0] h_sync_edge;
always @(posedge clk) h_sync_edge <= {h_sync_edge[1:0], (h_cnt == 1)};
wire start_fetch = (h_sync_edge[2:1] == 2'b01);

wire [10:0] fetch_line = (v_cnt == V_TOTAL - 1) ? 11'd0 : (v_cnt + 11'd1);
reg  [10:0] fetch_line_req, fetch_line_cur;
reg         fetch_req;
wire write_to_buf_B  = fetch_line_cur[0];
wire read_from_buf_B = v_cnt[0];

reg vs_d1, vs_d2;
always @(posedge clk) begin vs_d1 <= vga_vs_r; vs_d2 <= vs_d1; end
wire vs_falling_edge = vs_d2 & ~vs_d1;

// 3. Line Buffer
(* ramstyle = "M9K" *) reg [31:0] line_buf_A [0:159];
(* ramstyle = "M9K" *) reg [31:0] line_buf_B [0:159];
reg [7:0] buf_wr_ptr; reg buf_wr_en; reg [31:0] buf_wr_data;
always @(posedge clk) if (buf_wr_en) begin
    if (write_to_buf_B) line_buf_B[buf_wr_ptr] <= buf_wr_data;
    else                line_buf_A[buf_wr_ptr] <= buf_wr_data;
end

wire [7:0] rd_idx = (h_cnt < H_VISIBLE) ? h_cnt[9:2] : 8'd0;
reg [31:0] rd_data_A, rd_data_B;
always @(posedge vga_clk) begin
    rd_data_A <= line_buf_A[rd_idx];
    rd_data_B <= line_buf_B[rd_idx];
end
wire [31:0] pixel_word = read_from_buf_B ? rd_data_B : rd_data_A;
reg [1:0] h_cnt_d1; always @(posedge vga_clk) h_cnt_d1 <= h_cnt[1:0];

wire [7:0] pixel_byte = (h_cnt_d1 == 2'd0) ? pixel_word[7:0] : (h_cnt_d1 == 2'd1) ? pixel_word[15:8] : (h_cnt_d1 == 2'd2) ? pixel_word[23:16] : pixel_word[31:24];

function [7:0] dbg_bar_color;
    input [9:0] x;
    begin
        if      (x < 80)  dbg_bar_color = 8'hFF;
        else if (x < 160) dbg_bar_color = 8'hFC;
        else if (x < 240) dbg_bar_color = 8'h1F;
        else if (x < 320) dbg_bar_color = 8'h1C;
        else if (x < 400) dbg_bar_color = 8'hE3;
        else if (x < 480) dbg_bar_color = 8'hE0;
        else if (x < 560) dbg_bar_color = 8'h03;
        else              dbg_bar_color = 8'h00;
    end
endfunction

wire [7:0] r8 = {pixel_byte[7:5], pixel_byte[7:5], pixel_byte[7:6]};
wire [7:0] g8 = {pixel_byte[4:2], pixel_byte[4:2], pixel_byte[4:3]};
wire [7:0] b8 = {pixel_byte[1:0], pixel_byte[1:0], pixel_byte[1:0], pixel_byte[1:0]};

wire [7:0] direct_pixel = dbg_bar_color(h_cnt);
wire [7:0] dr8 = {direct_pixel[7:5], direct_pixel[7:5], direct_pixel[7:6]};
wire [7:0] dg8 = {direct_pixel[4:2], direct_pixel[4:2], direct_pixel[4:3]};
wire [7:0] db8 = {direct_pixel[1:0], direct_pixel[1:0], direct_pixel[1:0], direct_pixel[1:0]};

reg h_act_d1, v_act_d1;
always @(posedge vga_clk) begin h_act_d1 <= h_active; v_act_d1 <= v_active; end
wire disp_act = h_act_d1 && v_act_d1;

assign VGA_BLANK_N = disp_act;
assign VGA_R = disp_act ? (dbg_direct_vga ? dr8 : r8) : 8'd0;
assign VGA_G = disp_act ? (dbg_direct_vga ? dg8 : g8) : 8'd0;
assign VGA_B = disp_act ? (dbg_direct_vga ? db8 : b8) : 8'd0;

// 4. SDRAM FSM
reg [31:0] dq_out; reg dq_oe=0; assign DRAM_DQ=dq_oe?dq_out:32'bz;
wire [31:0] dq_in=DRAM_DQ;
localparam CMD_NOP=4'b0111,CMD_ACT=4'b0011,CMD_RD=4'b0101,CMD_WR=4'b0100,CMD_PRE=4'b0010,CMD_REF=4'b0001,CMD_LMR=4'b0000;
reg DRAM_CKE_r,DRAM_CS_N_r,DRAM_RAS_N_r,DRAM_CAS_N_r,DRAM_WE_N_r;
reg [12:0] DRAM_ADDR_r; reg [1:0] DRAM_BA_r;
assign {DRAM_CS_N_r,DRAM_RAS_N_r,DRAM_CAS_N_r,DRAM_WE_N_r} = DRAM_CMD_wire;
reg [3:0] DRAM_CMD_wire;
assign DRAM_CKE=DRAM_CKE_r; assign DRAM_CS_N=DRAM_CS_N_r; assign DRAM_RAS_N=DRAM_RAS_N_r; assign DRAM_CAS_N=DRAM_CAS_N_r; assign DRAM_WE_N=DRAM_WE_N_r;
assign DRAM_ADDR=DRAM_ADDR_r; assign DRAM_BA=DRAM_BA_r; assign DRAM_DQM=4'b0000;

localparam INIT_WAIT=20000,tRP=2,tRFC=7,tMRD=2,tRCD=2,CAS_LAT=2;
localparam [4:0] ST_RESET=0,ST_INIT_WAIT=1,ST_INIT_PRE=2,ST_INIT_REF=4,ST_INIT_LM=6,ST_IDLE=8,ST_REFRESH=9,ST_DISP_ACT=11,ST_DISP_RD=13,ST_DISP_CAP=15,ST_GEN_ACT=18,ST_GEN_WR=20;

reg [4:0] state; reg [15:0] wait_cnt; reg [9:0] refresh_cnt; reg init_ref_done;
reg [17:0] disp_addr; reg [8:0] disp_words_read; reg [17:0] gen_addr; reg [9:0] gen_x; reg gen_active;

always @(posedge clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state<=ST_RESET; DRAM_CKE_r<=0; DRAM_CMD_wire<=CMD_NOP; dq_oe<=0; buf_wr_en<=0; 
        init_ref_done<=0; gen_active<=0; gen_addr<=0; fetch_req<=0;
    end else begin
        DRAM_CMD_wire<=CMD_NOP; dq_oe<=0; buf_wr_en<=0;
        if (start_fetch && fetch_line < V_VISIBLE) begin fetch_req <= 1'b1; fetch_line_req <= fetch_line; end
        
        if (dbg_sdram_pattern && vs_falling_edge) begin gen_active <= 1'b1; gen_addr <= 0; gen_x <= 0; end
        if (refresh_cnt < 780) refresh_cnt <= refresh_cnt + 1;

        case (state)
            ST_RESET: begin DRAM_CKE_r<=1; wait_cnt<=0; state<=ST_INIT_WAIT; end
            ST_INIT_WAIT: if(wait_cnt==INIT_WAIT[15:0]) begin wait_cnt<=0; state<=ST_INIT_PRE; end else wait_cnt<=wait_cnt+1;
            ST_INIT_PRE: begin DRAM_CMD_wire<=CMD_PRE; DRAM_ADDR_r[10]<=1; state<=ST_IDLE; end // Gian luoc de test nhanh
            ST_IDLE: begin
                if (refresh_cnt >= 780) begin refresh_cnt <= 0; DRAM_CMD_wire <= CMD_REF; end
                else if (fetch_req) begin
                    disp_addr <= (fetch_line_req << 7) + (fetch_line_req << 5); fetch_line_cur <= fetch_line_req;
                    disp_words_read <= 0; buf_wr_ptr <= 0; state <= ST_DISP_ACT; fetch_req <= 0;
                end
                else if (gen_active) state <= ST_GEN_ACT;
            end
            ST_DISP_ACT: begin DRAM_CMD_wire<=CMD_ACT; DRAM_ADDR_r<={4'd0, disp_addr[17:9]}; state<=ST_DISP_RD; wait_cnt<=0; end
            ST_DISP_RD: begin DRAM_CMD_wire<=CMD_RD; DRAM_ADDR_r<={4'd0, disp_addr[8:0]}; state<=ST_DISP_CAP; wait_cnt<=0; end
            ST_DISP_CAP: begin 
                if (wait_cnt == 2) begin // CAS
                    buf_wr_data<=dq_in; buf_wr_en<=1; buf_wr_ptr<=buf_wr_ptr+1; disp_words_read<=disp_words_read+1; disp_addr<=disp_addr+1;
                    if (disp_words_read == 159) state <= ST_IDLE; else state <= ST_DISP_RD;
                end else wait_cnt <= wait_cnt + 1;
            end
            ST_GEN_ACT: begin DRAM_CMD_wire<=CMD_ACT; DRAM_ADDR_r<=gen_addr[17:9]; state<=ST_GEN_WR; end
            ST_GEN_WR: begin
                DRAM_CMD_wire<=CMD_WR; DRAM_ADDR_r<={4'd0, gen_addr[8:0]}; dq_out<={4{dbg_bar_color(gen_x)}}; dq_oe<=1;
                gen_addr<=gen_addr+1; gen_x<=gen_x+4; if (gen_addr==76799) gen_active<=0; state<=ST_IDLE;
            end
            default: state <= ST_IDLE;
        endcase
    end
end

assign LEDG[0] = pll_locked;
assign LEDG[1] = dbg_direct_vga;
assign LEDG[7] = (state == ST_IDLE);

endmodule
