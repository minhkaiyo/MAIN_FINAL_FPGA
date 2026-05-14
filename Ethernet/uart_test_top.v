// uart_test_top.v
// Module Top Level dùng để Validate (Kiểm tra) module uart_rx trên board DE2i-150.
// Bạn gõ chữ từ màn hình máy tính -> nó sẽ truyền xuống dây RS-232 vào cổng COM -> Board thu lại -> Hiện mã HEX lên bóng đèn.

module uart_test_top (
    input  wire        CLOCK_50, // Xung 50MHz hệ thống
    input  wire [3:0]  KEY,      // KEY[0] cấu hình làm nút bấm Bắt đầu/Reset
    input  wire        UART_RXD, // Chân tiếp nhận cáp COM RS-232
    
    // Đổ kết quả ra ngoại vi
    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1
);

    wire rst_n = KEY[0];
    
    wire [7:0] rx_data;
    wire       rx_valid;
    
    // Gọi Module Bộ thu UART (Phase 1) - Tốc độ chuẩn 115200bps
    uart_rx #(
        .CLK_FREQ(50_000_000),
        .BAUD_RATE(115200)
    ) uart_inst (
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .rx(UART_RXD),
        .data(rx_data),
        .valid(rx_valid)
    );
    
    // ----------------------------------------------------
    // Feedback 1: Đèn Xanh chớp tắt nhạy tín hiệu (Event Ping)
    // ----------------------------------------------------
    reg [23:0] ledg_cnt = 0;
    reg [7:0]  latest_data = 0;
    
    always @(posedge CLOCK_50) begin
        if (!rst_n) begin
            latest_data <= 0;
            ledg_cnt <= 0;
        end else if (rx_valid) begin
            latest_data <= rx_data;        // Khóa chặt Data để ngắm
            ledg_cnt <= 24'd5_000_000;     // Hẹn giờ sáng LEDG trong ~0.1 Giây (100ms)
        end else if (ledg_cnt > 0) begin
            ledg_cnt <= ledg_cnt - 1'b1;   // Cạn thời gian thì tắt đèn Xanh
        end
    end
    
    assign LEDR[7:0] = latest_data;        // Nhìn số thập phân dưới định dạng Nhị Phân 8 bóng đỏ
    assign LEDR[17:8] = 10'd0;             // Tắt bóng dư
    assign LEDG[0]   = (ledg_cnt > 0);     // Bóng Flash Xanh nhấp nháy
    assign LEDG[8:1] = 8'd0;               // Tắt bóng dư
    
    // ----------------------------------------------------
    // Feedback 2: Đưa số liệu giải mã lên Màn Hình LED 7 thanh
    // ----------------------------------------------------
    function [6:0] seg7;
        input [3:0] hex;
        case (hex)
            4'h0: seg7 = 7'b1000000;
            4'h1: seg7 = 7'b1111001;
            4'h2: seg7 = 7'b0100100;
            4'h3: seg7 = 7'b0110000;
            4'h4: seg7 = 7'b0011001;
            4'h5: seg7 = 7'b0010010;
            4'h6: seg7 = 7'b0000010;
            4'h7: seg7 = 7'b1111000;
            4'h8: seg7 = 7'b0000000;
            4'h9: seg7 = 7'b0010000;
            4'hA: seg7 = 7'b0001000;
            4'hB: seg7 = 7'b0000011;
            4'hC: seg7 = 7'b1000110;
            4'hD: seg7 = 7'b0100001;
            4'hE: seg7 = 7'b0000110;
            4'hF: seg7 = 7'b0001110;
            default: seg7 = 7'b1111111;
        endcase
    endfunction
    
    // In LSB (Tách 4 bit dưới) vào HEX0
    assign HEX0 = seg7(latest_data[3:0]);
    // In MSB (Tách 4 bit trên) vào HEX1
    assign HEX1 = seg7(latest_data[7:4]);
    
endmodule
