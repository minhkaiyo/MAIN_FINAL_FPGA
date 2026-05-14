// uart_rx.v
// Bộ thu tín hiệu nối tiếp chuẩn RS-232
// Author: Antigravity AI
// Module này chịu trách nhiệm nhận từng bit rời rạc từ PC qua UART_RXD và ghép thành byte 8-bit.

module uart_rx #(
    parameter CLK_FREQ = 50_000_000, // Tần số clock mặc định (50MHz)
    parameter BAUD_RATE = 115200     // Tốc độ truyền baud
) (
    input  wire       clk,     // Xung nhịp hệ thống
    input  wire       rst_n,   // Reset tích cực mức thấp
    input  wire       rx,      // Chân nhận vật lý
    output reg  [7:0] data,    // Dữ liệu 1 byte (8-bit) xuất ra
    output reg        valid    // Xung kích 1 clock báo hiệu vừa nhận xong 1 byte
);

    // Tính toán số chu kỳ clock cho mỗi bit
    localparam CLOCKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    
    // Khai báo tập trạng thái cho Máy trạng thái (FSM)
    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;
    
    reg [1:0]  state_reg = IDLE;
    reg [15:0] clk_cnt = 0;      // Đếm clock để tạo thời gian
    reg [2:0]  bit_cnt = 0;      // Đếm đã nhận được bao nhiêu bit (0-7)
    reg [7:0]  rx_data = 0;      // Thanh ghi dịch chứa tạm
    
    // -----------------------------------------------------------
    // DOUBLE SYNCHRONIZER: Chống nhiễu Metastability
    // -----------------------------------------------------------
    // Tín hiệu UART_RX từ chân pin nối ngoài mội trường rất nhiều nhiễu.
    // Đưa 2 lần qua Flip-Flop để đồng bộ hóa với Clock của FPGA.
    reg rx_sync1, rx_sync2;
    always @(posedge clk) begin
        rx_sync1 <= rx;
        rx_sync2 <= rx_sync1;
    end
    
    // -----------------------------------------------------------
    // MAIN UART RX FSM
    // -----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= IDLE;
            clk_cnt   <= 0;
            bit_cnt   <= 0;
            rx_data   <= 0;
            data      <= 0;
            valid     <= 0;
        end else begin
            valid <= 1'b0; // Default: clear cờ valid ngay sau 1 nhịp clock
            
            case (state_reg)
                // 1. Trạng thái nghỉ - Khung đường truyền lôn ở mức 1 (HIGH)
                IDLE: begin
                    clk_cnt <= 0;
                    bit_cnt <= 0;
                    // Bất ngờ tụt xuống 0 -> Phát hiện Cạnh xuống của START BIT
                    if (rx_sync2 == 1'b0) begin 
                        state_reg <= START;
                    end
                end
                
                // 2. Kiểm tra Start Bit
                START: begin
                    // Đợi đến GIỮA chu kỳ của Start Bit
                    if (clk_cnt == (CLOCKS_PER_BIT/2) - 1) begin
                        if (rx_sync2 == 1'b0) begin // Vẫn là 0? Chắc chắn ko phải nhiễu!
                            clk_cnt <= 0;
                            state_reg <= DATA;
                        end else begin
                            state_reg <= IDLE;      // Nhiễu chập mạch, quay lại
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                
                // 3. Đọc 8 bits dữ liệu liên tiếp (LSB First)
                DATA: begin
                    // Chờ trọn vẹn 1 chu kỳ bit (Sample tại chính giữa mỗi bit)
                    if (clk_cnt == CLOCKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        rx_data[bit_cnt] <= rx_sync2; // Lấy mẫu bỏ vào túi
                        if (bit_cnt == 3'd7) begin    // Lấy đủ 8 bits (0->7)
                            state_reg <= STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                
                // 4. Lấy Stop Bit
                STOP: begin
                    if (clk_cnt == CLOCKS_PER_BIT - 1) begin
                        data <= rx_data;    // Chốt dữ liệu ra Output
                        valid <= 1'b1;      // Đánh cờ báo hiệu cho module hệ thống biết
                        state_reg <= IDLE;  // Trở về hóng byte tiếp theo
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
            endcase
        end
    end
endmodule
