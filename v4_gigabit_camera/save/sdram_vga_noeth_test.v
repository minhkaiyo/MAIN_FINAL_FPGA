// sdram_vga_noeth_test.v
// Test VGA + SDRAM – boc tach nguyen xi tu sdram_ethernet_stream_v4.v
// Chi bo phan Ethernet (pll_125, phy_init, MAC, DCFIFO, UDP parser, Triple buffer)
// Thay vao do: Pattern generator (co san trong top) duoc kich hoat ngay khi SDRAM init xong.
// 2 SW de debug giong top:
//   SW[17] = dbg_direct_vga  : bypass SDRAM, ve color bar thang len VGA
//   SW[16] = dbg_sdram_pattern: dung generator ghi color bar vao SDRAM (mac dinh nen bat)
// Date: 2026-05-12
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

// ==========================================================================
// 1. PLL (chi dung sdram_pll – giong top)
// ==========================================================================
wire clk, clk_sdram, vga_clk, vga_clk_dac, pll_sdram_locked;
sdram_pll pll_sdram_inst (
    .inclk0(CLOCK_50), .c0(clk), .c1(clk_sdram),
    .c2(vga_clk), .c3(vga_clk_dac), .locked(pll_sdram_locked)
);

assign DRAM_CLK   = clk_sdram;
assign VGA_CLK    = vga_clk_dac;  // Phase-shifted cho DAC (giong top)
assign VGA_SYNC_N = 1'b0;

wire dbg_direct_vga    = SW[17];
wire dbg_sdram_pattern = SW[16];

// ==========================================================================
// 2. VGA TIMING – nguyen xi tu top (section 7)
// ==========================================================================
localparam H_VISIBLE=640, H_FRONT=16, H_SYNC_W=96, H_BACK=48, H_TOTAL=800;
localparam V_VISIBLE=480, V_FRONT=10, V_SYNC_W=2,  V_BACK=33, V_TOTAL=525;
reg [9:0] h_cnt=0; reg [10:0] v_cnt=0;
always @(posedge vga_clk) begin
    if (h_cnt==H_TOTAL-1) begin h_cnt<=0; v_cnt<=(v_cnt==V_TOTAL-1)?0:v_cnt+1; end
    else h_cnt<=h_cnt+1;
end

wire h_active = (h_cnt < H_VISIBLE);
wire v_active = (v_cnt < V_VISIBLE);

// CHUAN BAI 3: Pipeline VGA sync 1 bac
reg vga_hs_r, vga_vs_r;
always @(posedge vga_clk) begin
    vga_hs_r <= ~((h_cnt >= H_VISIBLE+H_FRONT) && (h_cnt < H_VISIBLE+H_FRONT+H_SYNC_W));
    vga_vs_r <= ~((v_cnt >= V_VISIBLE+V_FRONT) && (v_cnt < V_VISIBLE+V_FRONT+V_SYNC_W));
end
assign VGA_HS = vga_hs_r;
assign VGA_VS = vga_vs_r;

// FIX: Dung h_cnt==1 (giong test module muot) de v_cnt on dinh truoc khi fetch
reg [2:0] h_sync_edge = 0;
always @(posedge clk) h_sync_edge <= {h_sync_edge[1:0], (h_cnt == 1)};
wire start_fetch = (h_sync_edge[2:1] == 2'b01);

wire [10:0] fetch_line = (v_cnt == V_TOTAL - 1) ? 11'd0 : (v_cnt + 11'd1);
reg  [10:0] fetch_line_req = 0;
reg  [10:0] fetch_line_cur = 0;
reg         fetch_req = 0;
wire write_to_buf_B  = fetch_line_cur[0];
wire read_from_buf_B = v_cnt[0];

// VSync edge detect de cap nhat rd_frame (giong top – section 7)
reg vs_d1, vs_d2;
always @(posedge clk) begin vs_d1 <= vga_vs_r; vs_d2 <= vs_d1; end
wire vs_falling_edge = vs_d2 & ~vs_d1;

// rd_frame luon = 0 vi khong co triple buffer (chi 1 vung nho)
// Khai bao de SDRAM FSM tuong thich voi cau truc cua top
reg [1:0] rd_frame = 0;
always @(posedge clk) if (vs_falling_edge) rd_frame <= 2'd0; // Fix frame 0

// ==========================================================================
// 3. DOUBLE LINE BUFFER – nguyen xi tu top (section 8)
// ==========================================================================
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

wire [7:0] rd_idx = (h_cnt < H_VISIBLE) ? h_cnt[9:2] : 8'd0;
reg [31:0] rd_data_A, rd_data_B;
always @(posedge vga_clk) begin
    rd_data_A <= line_buf_A[rd_idx];
    rd_data_B <= line_buf_B[rd_idx];
end
wire [31:0] pixel_word = read_from_buf_B ? rd_data_B : rd_data_A;

// Byte select: dung h_cnt_d1 de bu delay 1 cycle (do registered read)
reg [1:0] h_cnt_d1;
always @(posedge vga_clk) h_cnt_d1 <= h_cnt[1:0];

wire [7:0] pixel_byte = (h_cnt_d1 == 2'd0) ? pixel_word[7:0]   :
                        (h_cnt_d1 == 2'd1) ? pixel_word[15:8]  :
                        (h_cnt_d1 == 2'd2) ? pixel_word[23:16] :
                                             pixel_word[31:24] ;

// Color bar function – nguyen xi tu top
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

// RGB expand – nguyen xi tu top
wire [2:0] r3 = pixel_byte[7:5];
wire [2:0] g3 = pixel_byte[4:2];
wire [1:0] b2 = pixel_byte[1:0];

wire [7:0] r8 = {r3, r3, r3[2:1]};
wire [7:0] g8 = {g3, g3, g3[2:1]};
wire [7:0] b8 = {b2, b2, b2, b2};

wire [7:0] direct_pixel_byte = dbg_bar_color(h_cnt);
wire [7:0] direct_r8 = {direct_pixel_byte[7:5], direct_pixel_byte[7:5], direct_pixel_byte[7:6]};
wire [7:0] direct_g8 = {direct_pixel_byte[4:2], direct_pixel_byte[4:2], direct_pixel_byte[4:3]};
wire [7:0] direct_b8 = {direct_pixel_byte[1:0], direct_pixel_byte[1:0], direct_pixel_byte[1:0], direct_pixel_byte[1:0]};

// Display active pipeline - delay 1 cycle khop voi registered pixel
reg h_act_d1, v_act_d1;
always @(posedge vga_clk) begin
    h_act_d1 <= h_active;
    v_act_d1 <= v_active;
end
wire disp_act = h_act_d1 && v_act_d1;

assign VGA_BLANK_N = disp_act;
assign VGA_R = disp_act ? (dbg_direct_vga ? direct_r8 : r8) : 8'd0;
assign VGA_G = disp_act ? (dbg_direct_vga ? direct_g8 : g8) : 8'd0;
assign VGA_B = disp_act ? (dbg_direct_vga ? direct_b8 : b8) : 8'd0;

// ==========================================================================
// 4. SDRAM FSM – nguyen xi tu top (section 9), bo het ETH burst states
// Chi giu: Init, Refresh, Display Read, Gen Write
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
    ST_DISP_PRE_W=17,
    ST_GEN_ACT=18,ST_GEN_ACT_W=19,ST_GEN_WR=20,ST_GEN_WR_W=21,
    ST_GEN_PRE=22,ST_GEN_PRE_W=23;

reg [4:0] state=ST_RESET; reg [15:0] wait_cnt=0; reg [9:0] refresh_cnt=0;
reg init_ref_done = 0;
localparam REFRESH_IV=780;
reg [17:0] disp_addr; reg [8:0] disp_words_read;
reg [17:0] gen_addr = 0;
reg [9:0]  gen_x = 0;
reg        gen_active = 0;
reg [7:0]  move_offset = 0;
reg        vsync_d1 = 0;

wire [31:0] gen_data_comb = {
    dbg_bar_color(gen_x + move_offset + 10'd3),
    dbg_bar_color(gen_x + move_offset + 10'd2),
    dbg_bar_color(gen_x + move_offset + 10'd1),
    dbg_bar_color(gen_x + move_offset + 10'd0)
};

// fetch_req logic – nguyen xi tu top
always @(posedge clk or negedge pll_sdram_locked) begin
    if (!pll_sdram_locked) begin
        fetch_req <= 1'b0;
        fetch_line_req <= 0;
    end else begin
        if (start_fetch && fetch_line < V_VISIBLE) begin
            fetch_req <= 1'b1;
            fetch_line_req <= fetch_line;
        end
        if (state == ST_DISP_ACT && disp_words_read == 0) begin
            fetch_req <= 1'b0;
        end
    end
end

// SDRAM FSM chinh
always @(posedge clk or negedge pll_sdram_locked) begin
    if (!pll_sdram_locked) begin
        state<=ST_RESET; DRAM_CKE_r<=0; send_cmd(CMD_NOP);
        DRAM_BA_r<=0; DRAM_ADDR_r<=0; DRAM_DQM_r<=4'b1111;
        dq_oe<=0; buf_wr_en<=0; refresh_cnt<=0; init_ref_done<=0;
        gen_addr<=0; gen_x<=0; gen_active<=0; move_offset<=0; vsync_d1<=0;
    end else begin
        send_cmd(CMD_NOP); dq_oe<=0; buf_wr_en<=0;
        vsync_d1 <= VGA_VS;
        // Kick pattern generator moi VSync (giong top)
        if (dbg_sdram_pattern && vsync_d1 == 1'b0 && VGA_VS == 1'b1) begin
            gen_active  <= 1'b1;
            gen_addr    <= 0;
            gen_x       <= 0;
            move_offset <= move_offset + 1'b1;
        end
        if (refresh_cnt<REFRESH_IV) refresh_cnt<=refresh_cnt+1;
        case (state)
        ST_RESET:      begin DRAM_CKE_r<=1; DRAM_DQM_r<=0; wait_cnt<=0; state<=ST_INIT_WAIT; end
        ST_INIT_WAIT:  begin if(wait_cnt==INIT_WAIT[15:0]) begin wait_cnt<=0; state<=ST_INIT_PRE; end else wait_cnt<=wait_cnt+1; end
        ST_INIT_PRE:   begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1; wait_cnt<=0; state<=ST_INIT_PRE_W; end
        ST_INIT_PRE_W: begin if(wait_cnt==tRP) begin wait_cnt<=0; state<=ST_INIT_REF; end else wait_cnt<=wait_cnt+1; end
        ST_INIT_REF:   begin send_cmd(CMD_REF); wait_cnt<=0; state<=ST_INIT_REF_W; end
        ST_INIT_REF_W: begin if(wait_cnt==tRFC) begin wait_cnt<=0; if(!init_ref_done) begin init_ref_done<=1; state<=ST_INIT_REF; end else state<=ST_INIT_LM; end else wait_cnt<=wait_cnt+1; end
        ST_INIT_LM:    begin send_cmd(CMD_LMR); DRAM_BA_r<=0; DRAM_ADDR_r<=MODE_REG; wait_cnt<=0; state<=ST_INIT_LM_W; end
        ST_INIT_LM_W:  begin if(wait_cnt==tMRD) state<=ST_IDLE; else wait_cnt<=wait_cnt+1; end

        // === IDLE: Refresh > VGA Read > Gen Write – giong top ===
        ST_IDLE: begin
            if (refresh_cnt >= REFRESH_IV) begin
                refresh_cnt <= 0;
                state <= ST_REFRESH;
            end
            else if (fetch_req) begin
                disp_addr       <= (fetch_line_req << 7) + (fetch_line_req << 5);
                fetch_line_cur  <= fetch_line_req;
                disp_words_read <= 0;
                buf_wr_ptr      <= 0;
                state           <= ST_DISP_ACT;
            end
            else if (dbg_sdram_pattern && gen_active) begin
                state <= ST_GEN_ACT;
            end
        end

        ST_REFRESH:    begin send_cmd(CMD_REF); wait_cnt<=0; state<=ST_REFRESH_W; end
        ST_REFRESH_W:  begin if(wait_cnt==tRFC) begin wait_cnt<=0; state<=ST_IDLE; end else wait_cnt<=wait_cnt+1; end

        // === Display read – nguyen xi tu top ===
        ST_DISP_ACT: begin
            send_cmd(CMD_ACT); DRAM_BA_r<=rd_frame; DRAM_ADDR_r<={4'd0, disp_addr[17:9]}; wait_cnt<=0; state<=ST_DISP_ACT_W;
        end
        ST_DISP_ACT_W: begin if(wait_cnt==tRCD) begin wait_cnt<=0; state<=ST_DISP_RD; end else wait_cnt<=wait_cnt+1; end
        ST_DISP_RD: begin
            send_cmd(CMD_RD); DRAM_ADDR_r<={4'd0, disp_addr[8:0]}; DRAM_ADDR_r[10]<=1'b0;
            disp_addr<=disp_addr+1'b1; disp_words_read<=disp_words_read+1'b1; wait_cnt<=0; state<=ST_DISP_CAS_W;
        end
        ST_DISP_CAS_W: begin if(wait_cnt==CAS_LAT) begin wait_cnt<=0; state<=ST_DISP_CAP; end else wait_cnt<=wait_cnt+1; end
        ST_DISP_CAP: begin
            buf_wr_data<=dq_in; buf_wr_en<=1'b1; buf_wr_ptr<=buf_wr_ptr+8'd1;
            if (disp_words_read==9'd160 || disp_addr[8:0]==9'd0) state<=ST_DISP_PRE;
            else state<=ST_DISP_RD;
        end
        ST_DISP_PRE:   begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1'b1; wait_cnt<=0; state<=ST_DISP_PRE_W; end
        ST_DISP_PRE_W: begin if(wait_cnt==tRP) begin wait_cnt<=0; if(disp_words_read>=9'd160) state<=ST_IDLE; else state<=ST_DISP_ACT; end else wait_cnt<=wait_cnt+1; end

        // === Pattern generator write – nguyen xi tu top ===
        ST_GEN_ACT: begin
            send_cmd(CMD_ACT); DRAM_BA_r<=rd_frame; DRAM_ADDR_r<=gen_addr[17:9]; wait_cnt<=0; state<=ST_GEN_ACT_W;
        end
        ST_GEN_ACT_W: begin if(wait_cnt==tRCD) begin wait_cnt<=0; state<=ST_GEN_WR; end else wait_cnt<=wait_cnt+1; end
        ST_GEN_WR: begin
            send_cmd(CMD_WR); DRAM_ADDR_r<={4'd0, gen_addr[8:0]}; DRAM_ADDR_r[10]<=1'b0;
            DRAM_DQM_r<=0; dq_out<=gen_data_comb; dq_oe<=1'b1;
            gen_addr<=gen_addr+1'b1;
            if (gen_x >= 10'd636) gen_x<=0; else gen_x<=gen_x+10'd4;
            state<=ST_GEN_WR_W;
        end
        ST_GEN_WR_W: begin
            if (gen_addr==18'd76800) begin gen_active<=1'b0; state<=ST_GEN_PRE; end
            else if (gen_addr[8:0]==9'd0) state<=ST_GEN_PRE;
            else state<=ST_GEN_WR;
        end
        ST_GEN_PRE:   begin send_cmd(CMD_PRE); DRAM_ADDR_r[10]<=1'b1; wait_cnt<=0; state<=ST_GEN_PRE_W; end
        ST_GEN_PRE_W: begin if(wait_cnt==tRP) state<=ST_IDLE; else wait_cnt<=wait_cnt+1; end
        default: state<=ST_IDLE;
        endcase
    end
end

// ==========================================================================
// 5. DIAGNOSTICS
// ==========================================================================
assign LEDG[0] = pll_sdram_locked;
assign LEDG[1] = dbg_direct_vga;
assign LEDG[2] = dbg_sdram_pattern;
assign LEDG[3] = gen_active;
assign LEDG[4] = fetch_req;
assign LEDG[5] = (state == ST_DISP_RD) || (state == ST_DISP_CAP);
assign LEDG[6] = (state == ST_GEN_WR);
assign LEDG[7] = (state == ST_IDLE);
assign LEDG[8] = init_ref_done;

endmodule
