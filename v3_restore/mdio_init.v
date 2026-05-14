// mdio_init.v - Hard Force 100M
// Ép chip PHY Marvell về 100Mbps bằng mọi giá

module mdio_init (
    input  wire clk,     // 50MHz
    input  wire rst_n,   // Active-low reset
    output reg  mdc,
    output reg  mdio_out,
    output reg  mdio_en,
    output reg  done
);

    reg [5:0] state = 0;
    reg [7:0] clk_divider = 0;
    reg [63:0] shift_reg;
    reg [6:0] bit_cnt;
    reg [23:0] wait_cnt;

    // Command sequence: 
    // 1. Force PHY 0, Reg 0 -> 0xA100 (100M, Full, Reset)
    // 2. Force PHY 1, Reg 0 -> 0xA100 (100M, Full, Reset)
    wire [63:0] cmd0 = {32'hFFFFFFFF, 2'b01, 2'b01, 5'd0, 5'd0, 2'b10, 16'hA100};
    wire [63:0] cmd1 = {32'hFFFFFFFF, 2'b01, 2'b01, 5'd1, 5'd0, 2'b10, 16'hA100};

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= 0; mdc <= 0; mdio_out <= 1; mdio_en <= 0; done <= 0;
            clk_divider <= 0; wait_cnt <= 0;
        end else begin
            case (state)
                0: begin // Khởi động
                    if (wait_cnt < 24'd5_000_000) wait_cnt <= wait_cnt + 1;
                    else begin state <= 1; shift_reg <= cmd0; bit_cnt <= 0; end
                end
                1, 3: begin // Gửi 64 bit (Preamble + Cmd)
                    if (clk_divider < 8'd50) clk_divider <= clk_divider + 1;
                    else begin
                        clk_divider <= 0;
                        mdc <= ~mdc;
                        if (mdc) begin // Falling edge: Change data
                            mdio_out <= shift_reg[63];
                            shift_reg <= {shift_reg[62:0], 1'b1};
                            mdio_en <= 1'b1;
                            if (bit_cnt == 63) begin
                                state <= state + 1;
                                wait_cnt <= 0;
                            end else bit_cnt <= bit_cnt + 1;
                        end
                    end
                end
                2: begin // Đợi giữa 2 lệnh
                    mdio_en <= 0;
                    if (wait_cnt < 24'd1_000_000) wait_cnt <= wait_cnt + 1;
                    else begin state <= 3; shift_reg <= cmd1; bit_cnt <= 0; end
                end
                4: begin // Xong
                    done <= 1;
                    mdio_en <= 0;
                end
            endcase
        end
    end
endmodule
