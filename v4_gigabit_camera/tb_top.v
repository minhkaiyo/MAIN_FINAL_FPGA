// tb_top.v
// Professional Verification Testbench
// Multi-log files, Mismatch checking, and VGA sampling.

`timescale 1ns / 1ps

module tb_top();

    // ==========================================================================
    // 1. SIGNALS & CLOCKS
    // ==========================================================================
    reg CLOCK_50 = 0;
    reg [3:0] KEY = 4'hF;
    wire [17:0] LEDR; wire [8:0] LEDG;
    wire [12:0] DRAM_ADDR; wire [1:0] DRAM_BA;
    wire DRAM_CAS_N, DRAM_CKE, DRAM_CLK, DRAM_CS_N, DRAM_RAS_N, DRAM_WE_N;
    wire [31:0] DRAM_DQ; wire [3:0] DRAM_DQM;
    wire [7:0] VGA_B, VGA_G, VGA_R;
    wire VGA_BLANK_N, VGA_CLK, VGA_HS, VGA_SYNC_N, VGA_VS;

    always #10 CLOCK_50 = ~CLOCK_50;
    reg clk_gen_vga = 0, clk_gen_100 = 0, clk_gen_125 = 0;
    always #20 clk_gen_vga = ~clk_gen_vga;
    always #5  clk_gen_100 = ~clk_gen_100;
    always #4  clk_gen_125 = ~clk_gen_125;

    // ==========================================================================
    // 2. FILE LOGGING (Professional Strategy)
    // ==========================================================================
    integer fd_eth, fd_vga, fd_err;
    initial begin
        fd_eth = $fopen("output_log/eth_transactions.log", "w");
        fd_vga = $fopen("output_log/vga_samples.log", "w");
        fd_err = $fopen("output_log/mismatches.log", "w");
    end

    // ==========================================================================
    // 3. DUT & SDRAM MODEL
    // ==========================================================================
    sdram_ethernet_stream_v4 dut (
        .CLOCK_50(CLOCK_50), .KEY(KEY), .SW(18'h0),
        .LEDR(LEDR), .LEDG(LEDG),
        .DRAM_ADDR(DRAM_ADDR), .DRAM_BA(DRAM_BA), .DRAM_CAS_N(DRAM_CAS_N),
        .DRAM_CKE(DRAM_CKE), .DRAM_CLK(DRAM_CLK), .DRAM_CS_N(DRAM_CS_N),
        .DRAM_DQ(DRAM_DQ), .DRAM_DQM(DRAM_DQM), .DRAM_RAS_N(DRAM_RAS_N), .DRAM_WE_N(DRAM_WE_N),
        .VGA_B(VGA_B), .VGA_G(VGA_G), .VGA_R(VGA_R),
        .VGA_BLANK_N(VGA_BLANK_N), .VGA_CLK(clk_gen_vga), .VGA_HS(VGA_HS), .VGA_SYNC_N(VGA_SYNC_N), .VGA_VS(VGA_VS),
        .ENET_RX_CLK(1'b0), .ENET_RX_DATA(4'd0), .ENET_RX_DV(1'b0),
        .clk(clk_gen_100), .clk_125(clk_gen_125)
    );

    sdram_model mem_inst (
        .clk(clk_gen_100), .cke(DRAM_CKE), .cs_n(DRAM_CS_N),
        .ras_n(DRAM_RAS_N), .cas_n(DRAM_CAS_N), .we_n(DRAM_WE_N),
        .ba(DRAM_BA), .addr(DRAM_ADDR), .dqm(DRAM_DQM), .dq(DRAM_DQ)
    );

    // ==========================================================================
    // 4. TEST PROCEDURE
    // ==========================================================================
    integer x, y, f;
    initial begin
        $display("Starting Professional Simulation...");
        KEY[0] = 0; #200; KEY[0] = 1; #2000;

        for (f = 0; f < 2; f = f + 1) begin
            $display("--- Frame %0d Transmission Start ---", f);
            for (y = 0; y < 480; y = y + 1) begin
                send_udp_packet(y, f[7:0]);
                wait (dut.fifo_rdusedw < 4096);
                #100;
            end
        end
        
        #20000000;
        $fclose(fd_eth); $fclose(fd_vga); $fclose(fd_err);
        $display("Simulation Finished. Check mismatches.log for errors.");
        $finish;
    end

    // ==========================================================================
    // 5. SMART LOGGING & ASSERTIONS
    // ==========================================================================
    
    // ETH LOGGING (Chỉ log word hợp lệ)
    always @(posedge dut.clk_125) begin
        if (dut.word_valid) begin
            $fdisplay(fd_eth, "[ETH_WR] Addr:%d Data:%h at %t", dut.word_addr, dut.word_data, $time);
        end
    end

    // VGA LOGGING & SELF-CHECKING
    reg [7:0] expected_r, expected_g, expected_b;
    always @(posedge clk_gen_vga) begin
        if (dut.vblank && dut.frame_ready) begin
            // 5a. Mismatch Checking (Logic vàng của dân chuyên)
            // CHỈ check khi rd_frame != 0 (tức là đã load được frame hợp lệ đầu tiên)
            if (dut.rd_frame != 0) begin
                // Chuẩn Mono8: Giá trị pixel chính là số thứ tự cột (h_cnt)
                expected_r = dut.h_cnt[7:0];

                if (VGA_R != expected_r) begin
                    $fdisplay(fd_err, "[MISMATCH] X=%d Y=%d | EXP: %h | ACT: R=%h G=%h B=%h", 
                              dut.h_cnt, dut.v_cnt, expected_r, VGA_R, VGA_G, VGA_B);
                end
            end

            // 5b. Sampling (Chỉ log mỗi 32 pixel để giảm size log)
            if (dut.h_cnt % 32 == 0 && dut.v_cnt % 32 == 0) begin
                $fdisplay(fd_vga, "[VGA_SAMPLE] X=%d Y=%d RGB=%h%h%h", 
                          dut.h_cnt, dut.v_cnt, VGA_R, VGA_G, VGA_B);
            end
        end
    end

    // ==========================================================================
    // 6. HELPER TASKS
    // ==========================================================================
    task send_udp_packet;
        input [15:0] row;
        input [7:0]  frame_num;
        integer i;
        begin
            @(posedge dut.clk_125);
            for (i = 0; i < 14; i = i + 1) drive_byte(8'hAA);
            for (i = 0; i < 20; i = i + 1) drive_byte(8'hBB);
            for (i = 0; i < 8; i = i + 1)  drive_byte(8'hCC);
            drive_byte(row[15:8]);
            drive_byte(row[7:0]);
            // Gửi 640 byte (Mỗi pixel 1 byte Mono8)
            for (i = 0; i < 640; i = i + 1) begin
                drive_byte(i[7:0]); // Pixel Value = Cột hiện tại
            end
            force dut.rx_axis_tdata = 8'h00; force dut.rx_axis_tvalid = 1; force dut.rx_axis_tlast = 1;
            @(posedge dut.clk_125);
            force dut.rx_axis_tvalid = 0; force dut.rx_axis_tlast = 0;
            @(posedge dut.clk_125);
        end
    endtask

    task drive_byte;
        input [7:0] b;
        begin
            force dut.rx_axis_tdata = b;
            force dut.rx_axis_tvalid = 1;
            force dut.rx_axis_tlast = 0;
            @(posedge dut.clk_125);
        end
    endtask

endmodule
