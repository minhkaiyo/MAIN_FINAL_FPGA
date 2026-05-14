// eth_basic_link.v
// Module Verilog thuần để đánh thức PHY Marvell 88E1111 và thiết lập Link với Laptop
// Không cần Nios II, không cần MDIO phức tạp, chỉ cần Reset đúng chuẩn Terasic!

module eth_basic_link (
    input  wire        CLOCK_50,     // Xung hệ thống 50MHz
    input  wire [3:0]  KEY,          // Nút nhấn (KEY[0] dùng làm System Reset)
    
    // --- Giao tiếp với Marvell 88E1111 PHY ---
    output wire        ENET_GTX_CLK, // Clock cho Gigabit (Set 0 để chạy 10/100 MII)
    output wire        ENET_RST_N,   // Tín hiệu Reset cực kỳ quan trọng cho PHY
    output wire        ENET_MDC,     // Xung nhịp cho bộ quản lý (MDIO) - không xài
    inout  wire        ENET_MDIO,    // Dữ liệu quản lý - thả nổi vì không cấu hình mềm
    output wire [3:0]  ENET_TX_DATA, // Dữ liệu truyền - để mức 0 khi Idle
    output wire        ENET_TX_EN,   // Cho phép truyền - 0
    output wire        ENET_TX_ER,   // Lỗi truyền - 0
    
    // --- Tín hiệu vào từ PHY ---
    input  wire        ENET_LINK100, // Đèn báo Link 100Mbps
    input  wire        ENET_RX_CLK,  // Clock nhận từ PHY
    input  wire        ENET_TX_CLK,  // Clock truyền từ PHY
    
    // --- Hiển thị lên Board (Feedback) ---
    output wire [8:0]  LEDG,
    output wire [17:0] LEDR
);

    // =========================================================
    // 1. TẠO XUNG RESET ĐÚNG CHUẨN (Cực sạch, kéo dài ~20ms)
    // =========================================================
    // Con Marvell 88E1111 cần giữ Reset LOW một lúc sau khi có điện,
    // và bắt đầu chốt cấu hình phần cứng ngay tại sườn CẠNH LÊN của Reset.
    reg [20:0] rst_cnt = 0;
    reg        phy_rst_n = 0;
    
    always @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0]) begin
            rst_cnt <= 0;
            phy_rst_n <= 1'b0;
        end else begin
            if (rst_cnt == 21'h1FFFFF) begin // Đếm khoảng 2 triệu chu kỳ (40ms)
                phy_rst_n <= 1'b1;           // Đủ thời gian, nhả Reset lên 1!
            end else begin
                rst_cnt <= rst_cnt + 1'b1;
                phy_rst_n <= 1'b0;
            end
        end
    end
    
    // Gán tín hiệu ra chân ngoại vi
    assign ENET_RST_N = phy_rst_n;

    // =========================================================
    // 2. KHÓA CÁC CHÂN TÍN HIỆU ĐỂ PHY VÀO IDLE MII MODE
    // =========================================================
    // Chân quan trọng nhất: GTX_CLK phải bằng 0 để PHY không hiểu nhầm là chạy RGMII/GMII
    assign ENET_GTX_CLK = 1'b0; 
    
    // Trạng thái nhàn rỗi (IDLE) của MAC, không truyền gì cả
    assign ENET_TX_DATA = 4'd0;
    assign ENET_TX_EN   = 1'b0;
    assign ENET_TX_ER   = 1'b0;
    
    // MDIO thả nổi hoặc tắt đi vì dùng Hardware Strapping là đủ
    assign ENET_MDC     = 1'b0;
    assign ENET_MDIO    = 1'bz;

    // =========================================================
    // 3. HIỂN THỊ KẾT QUẢ ĐỂ BẠN THẤY
    // =========================================================
    // Đèn Xanh 0: Báo hiệu FPGA đã bung Reset cho PHY thành công
    assign LEDG[0] = phy_rst_n;
    
    // Đèn Xanh 1: Sáng rực rỡ nếu Link 100Mbps với Laptop được thiết lập!
    assign LEDG[1] = ENET_LINK100;
    
    // Đèn Xanh 2 & 3: Nhấp nháy chứng tỏ PHY đã cấp Clock ổn định cho FPGA
    reg [23:0] rx_clk_div_cnt = 0;
    reg [23:0] tx_clk_div_cnt = 0;
    
    always @(posedge ENET_RX_CLK) rx_clk_div_cnt <= rx_clk_div_cnt + 1'b1;
    always @(posedge ENET_TX_CLK) tx_clk_div_cnt <= tx_clk_div_cnt + 1'b1;
    
    assign LEDG[2] = rx_clk_div_cnt[23]; // Theo dõi Clock nhận
    assign LEDG[3] = tx_clk_div_cnt[23]; // Theo dõi Clock truyền
    
    assign LEDG[8:4] = 5'd0;
    assign LEDR = 18'd0;

endmodule
