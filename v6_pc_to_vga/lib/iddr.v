// iddr.v - Custom DDR Sampling for RGMII Timing Skew Compensation
`timescale 1ns / 1ps

module iddr #
(
    parameter TARGET = "ALTERA",
    parameter IODDR_STYLE = "IODDR2",
    parameter WIDTH = 1
)
(
    input  wire             clk,
    input  wire [WIDTH-1:0] d,
    output wire [WIDTH-1:0] q1,
    output wire [WIDTH-1:0] q2
);

// Dùng Flip-flop thuần để chủ động kiểm soát cạnh lấy mẫu
reg [WIDTH-1:0] d_reg_1 = {WIDTH{1'b0}};
reg [WIDTH-1:0] d_reg_2 = {WIDTH{1'b0}};
reg [WIDTH-1:0] q_reg_1 = {WIDTH{1'b0}};
reg [WIDTH-1:0] q_reg_2 = {WIDTH{1'b0}};

// Lấy mẫu cạnh LÊN
always @(posedge clk) begin
    d_reg_1 <= d;
end

// Lấy mẫu cạnh XUỐNG
always @(negedge clk) begin
    d_reg_2 <= d;
end

// Đồng bộ hóa về cùng một miền thời gian (cạnh LÊN)
always @(posedge clk) begin
    // TRICK: Đảo chéo q_reg_1 và q_reg_2 để khắc phục lỗi lệch pha
    // q1 là Rising Edge, q2 là Falling Edge
    q_reg_1 <= d_reg_1; 
    q_reg_2 <= d_reg_2; 
end

// Nếu dữ liệu bị đảo Nibble, ta có thể đảo trực tiếp ở đây
assign q1 = q_reg_1;
assign q2 = q_reg_2;

endmodule
