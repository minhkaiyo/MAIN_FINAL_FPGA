// mdio_init.v
// Bỏ qua ép xung PHY (Bypass MDIO) vì Router đã tự động cấp 100Mbps.
// Việc cố ép xung qua MDIO có thể gây xung đột với Router (Link Flapping).

module mdio_init (
    input  wire clk,     // 50MHz
    input  wire rst_n,   // Active-low reset
    output reg  mdc,
    output reg  mdio_out,
    output reg  mdio_en,
    output reg  done
);

    reg [19:0] delay_cnt = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            mdc <= 0;
            mdio_out <= 1;
            mdio_en <= 0;
            done <= 0;
            delay_cnt <= 0;
        end else begin
            // Chỉ đợi 10ms (500,000 xung clk) để đảm bảo PHY khởi động xong
            if (delay_cnt < 20'd500_000) begin
                delay_cnt <= delay_cnt + 1;
            end else begin
                done <= 1'b1; // Báo xong để State Machine chạy tiếp
            end
        end
    end

endmodule
