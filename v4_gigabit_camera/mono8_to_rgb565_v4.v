// mono8_to_rgb565_v4.v
// Mono8 pixel → pair of RGB565 words (2 pixels per 32-bit word for SDRAM efficiency)
// Identical algorithm to V3 but interface adapted for AXI-style handshaking
// Date: 2026-05-09

module mono8_to_rgb565_v4 (
    input  wire        clk,
    input  wire        rst,

    // Input: Mono8 pixels from GVSP parser
    input  wire [7:0]  pixel_in,
    input  wire        pixel_valid,
    input  wire [18:0] pixel_addr,
    input  wire        frame_start,

    // Output: pairs of RGB565 pixels packed into 32-bit words
    // Writes to SDRAM via FIFO
    output reg  [31:0] word_out,
    output reg         word_valid,
    output reg  [18:0] word_addr,
    output reg         frame_start_out
);

// Mono8 → RGB565: replicate grey value into R(5) G(6) B(5)
// R = grey[7:3], G = grey[7:2], B = grey[7:3]
function [15:0] m8_to_565;
    input [7:0] m;
    begin
        m8_to_565 = {m[7:3], m[7:2], m[7:3]};
    end
endfunction

reg [15:0] prev_pixel = 0;
reg        has_prev   = 0;
reg [18:0] prev_addr  = 0;

always @(posedge clk) begin
    if (rst) begin
        has_prev        <= 0;
        word_valid      <= 0;
        frame_start_out <= 0;
    end else begin
        word_valid      <= 0;
        frame_start_out <= 0;

        if (frame_start) begin
            has_prev        <= 0;
            frame_start_out <= 1;
        end

        if (pixel_valid) begin
            if (!has_prev) begin
                // Buffer first pixel
                prev_pixel <= m8_to_565(pixel_in);
                prev_addr  <= pixel_addr >> 1; // word address
                has_prev   <= 1;
            end else begin
                // Emit pair: [pixel_n+1 Hi | pixel_n Lo]
                word_out   <= {m8_to_565(pixel_in), prev_pixel};
                word_addr  <= prev_addr;
                word_valid <= 1;
                has_prev   <= 0;
            end
        end
    end
end

endmodule
