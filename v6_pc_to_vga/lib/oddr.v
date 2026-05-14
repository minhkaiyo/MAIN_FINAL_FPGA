// oddr.v - Optimized for Altera Cyclone IV GX
`timescale 1ns / 1ps

module oddr #
(
    parameter TARGET = "ALTERA",
    parameter IODDR_STYLE = "IODDR2",
    parameter WIDTH = 1
)
(
    input  wire             clk,
    input  wire [WIDTH-1:0] d1,
    input  wire [WIDTH-1:0] d2,
    output wire [WIDTH-1:0] q
);

altddio_out #(
    .WIDTH(WIDTH),
    .POWER_UP_HIGH("OFF"),
    .INTENDED_DEVICE_FAMILY("Cyclone IV GX")
)
altddio_out_inst (
    .aset(1'b0), .datain_h(d1), .datain_l(d2), .outclocken(1'b1), .outclock(clk),
    .aclr(1'b0), .dataout(q)
);

endmodule
