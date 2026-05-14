// mono8_to_rgb565.v
// Chuyen Mono8 (1 byte/pixel) -> RGB565 (2 byte/pixel)
// Va pack 2 pixel thanh 1 word 32-bit cho SDRAM
// Date: 2025-05-09
//
// Mono8 grayscale -> RGB565:
//   R[4:0] = mono[7:3]
//   G[5:0] = mono[7:2]
//   B[4:0] = mono[7:3]
//   => RGB565 = {mono[7:3], mono[7:2], mono[7:3]}

module mono8_to_rgb565 (
    input           clk,
    input           rst_n,

    // --- Input pixel stream (tu gvsp_rx, qua DCFIFO) ---
    input  [7:0]    pixel_in,   // Mono8
    input           pixel_valid,
    input           frame_start,

    // --- Output: 32-bit word (2 pixels packed) ---
    output reg [31:0] word_out,     // {pixel[n+1] RGB565, pixel[n] RGB565}
    output reg        word_valid,   // 1 = word_out hop le
    output reg [18:0] word_addr,    // Word address trong SDRAM frame
    output reg        frame_start_out // Propagate frame_start
);

// Chuyen doi 1 pixel Mono8 -> RGB565
function [15:0] mono_to_565;
    input [7:0] m;
    begin
        mono_to_565 = {m[7:3], m[7:2], m[7:3]};
    end
endfunction

reg [15:0] pixel_lo;        // Pixel chan (thu 1 trong cap)
reg        has_lo;          // Da co pixel lo
reg [18:0] pair_cnt;        // Dem cap pixel (= word index trong SDRAM)

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        word_valid <= 0; word_addr <= 0; has_lo <= 0;
        pair_cnt <= 0; frame_start_out <= 0; pixel_lo <= 0;
    end else begin
        word_valid <= 0;
        frame_start_out <= frame_start;

        if (frame_start) begin
            has_lo <= 0; pair_cnt <= 0; word_addr <= 0;
        end

        if (pixel_valid) begin
            if (!has_lo) begin
                // Luu pixel chan
                pixel_lo <= mono_to_565(pixel_in);
                has_lo <= 1;
            end else begin
                // Ghep voi pixel le -> xuat word 32-bit
                word_out   <= {mono_to_565(pixel_in), pixel_lo};
                word_addr  <= pair_cnt;
                word_valid <= 1;
                pair_cnt   <= pair_cnt + 1;
                has_lo     <= 0;
            end
        end
    end
end

endmodule
