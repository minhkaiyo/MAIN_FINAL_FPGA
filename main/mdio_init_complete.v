// mdio_init.v
// Module cấu hình MDIO: Tắt quảng bá Gigabit (1000Mbps) để ép Laptop nhận 100Mbps (MII)
// Tránh lỗi Laptop báo Unplugged do thiếu xung GTX_CLK 125MHz.

module mdio_init (
    input  wire clk,         // Khuyên dùng 50MHz
    input  wire rst_n,       // Khởi động khi rst_n = 1
    
    output reg  mdc,         // Xung nhịp cho MDIO (~1MHz)
    output reg  mdio_out,    // Dữ liệu truyền ra
    output reg  mdio_en,     // 1: Xuất dữ liệu, 0: Thả nổi (Z)
    output reg  done         // 1: Đã cấu hình xong
);

    // Mảng dữ liệu MDIO (Opcode Write = 01, PHY_ADDR = 10000, REG, TA = 10, DATA)
    // Lệnh 1: Ghi vào Reg 9 (01001) giá trị 0x0000 để TẮT Gigabit Advertisement
    wire [31:0] cmd1 = {2'b01, 2'b01, 5'b10000, 5'b01001, 2'b10, 16'h0000};
    
    // Lệnh 2: Ghi vào Reg 0 (00000) giá trị 0x1200 để kích hoạt lại Auto-Negotiation
    wire [31:0] cmd2 = {2'b01, 2'b01, 5'b10000, 5'b00000, 2'b10, 16'h1200};

    reg [5:0] step = 0;       // Máy trạng thái chính
    reg [5:0] bit_cnt = 0;    // Đếm bit (0->31)
    reg [4:0] div_cnt = 0;    // Chia tần số
    reg mdc_tick = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            div_cnt <= 0;
            mdc_tick <= 0;
            mdc <= 0;
        end else begin
            div_cnt <= div_cnt + 1'b1;
            mdc_tick <= (div_cnt == 5'd24); // Tạo xung sau ~25 chu kỳ 50MHz
            if (div_cnt == 5'd24) div_cnt <= 0;
            if (mdc_tick) mdc <= ~mdc;      // MDC clock ~ 1MHz
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            step <= 0;
            bit_cnt <= 0;
            mdio_out <= 1;
            mdio_en <= 0;
            done <= 0;
        end else if (mdc_tick && !mdc) begin // Thay đổi dữ liệu ở sườn XUỐNG của MDC
            case (step)
                0: begin // Đợi 1 chút
                    mdio_en <= 0;
                    if (bit_cnt < 32) bit_cnt <= bit_cnt + 1'b1;
                    else begin bit_cnt <= 0; step <= 1; end
                end
                
                1: begin // Truyền Preamble (32 bits '1')
                    mdio_en <= 1;
                    mdio_out <= 1'b1;
                    if (bit_cnt < 31) bit_cnt <= bit_cnt + 1'b1;
                    else begin bit_cnt <= 0; step <= 2; end
                end
                
                2: begin // Truyền Command 1 (Reg 9)
                    mdio_out <= cmd1[31 - bit_cnt];
                    if (bit_cnt < 31) bit_cnt <= bit_cnt + 1'b1;
                    else begin bit_cnt <= 0; step <= 3; end
                end
                
                3: begin // Trễ giữa 2 lệnh
                    mdio_en <= 0; // Nghỉ
                    if (bit_cnt < 31) bit_cnt <= bit_cnt + 1'b1;
                    else begin bit_cnt <= 0; step <= 4; end
                end

                4: begin // Truyền Preamble cho Command 2
                    mdio_en <= 1;
                    mdio_out <= 1'b1;
                    if (bit_cnt < 31) bit_cnt <= bit_cnt + 1'b1;
                    else begin bit_cnt <= 0; step <= 5; end
                end

                5: begin // Truyền Command 2 (Reg 0)
                    mdio_out <= cmd2[31 - bit_cnt];
                    if (bit_cnt < 31) bit_cnt <= bit_cnt + 1'b1;
                    else begin bit_cnt <= 0; step <= 6; end
                end

                6: begin // Xong
                    mdio_en <= 0;
                    done <= 1;
                end
            endcase
        end
    end

endmodule
