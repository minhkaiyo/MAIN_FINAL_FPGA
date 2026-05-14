// gvsp_rx.v - MII Simple Version (Final Fix for Indexing)
module gvsp_rx (
    input  wire clk_eth,
    input  wire rst_n,
    input  wire [3:0] RX_DATA,
    input  wire RX_DV,
    output reg  [7:0] pixel_data,
    output reg  pixel_valid,
    output reg  [18:0] pixel_addr,
    output reg  frame_start,
    output reg  frame_done,
    output reg  [7:0] pkt_count
);

    reg [1:0] nibble_idx;
    reg [7:0] assembled_byte;
    reg [11:0] byte_cnt;
    reg [15:0] row_y;

    always @(posedge clk_eth) begin
        pixel_valid <= 0;
        frame_start <= 0;
        frame_done <= 0;

        if (!RX_DV) begin
            nibble_idx <= 0;
            byte_cnt <= 0;
        end else begin
            if (nibble_idx == 0) begin
                assembled_byte[3:0] <= RX_DATA;
                nibble_idx <= 1;
            end else begin
                // Tại đây, một Byte vừa được ghép xong (assembled_byte[3:0] là nibble thấp, RX_DATA là nibble cao)
                assembled_byte[7:4] <= RX_DATA;
                nibble_idx <= 0;
                
                // Index byte_cnt lúc này đại diện cho byte vừa nhận xong
                // Byte 42 (0-indexed) là byte đầu tiên của Payload (y_high)
                if (byte_cnt == 42) row_y[15:8] <= {RX_DATA, assembled_byte[3:0]};
                if (byte_cnt == 43) begin
                    row_y[7:0] <= {RX_DATA, assembled_byte[3:0]};
                    pixel_addr <= {row_y[8:0], 10'd0}; 
                end
                
                // Kích hoạt frame_start ngay khi nhận xong header của dòng y=0
                if (byte_cnt == 43 && row_y == 0) frame_start <= 1;
                
                // Dữ liệu pixel bắt đầu từ byte 44 đến 683 (tổng 640 byte)
                if (byte_cnt >= 44 && byte_cnt < 684) begin
                    pixel_data <= {RX_DATA, assembled_byte[3:0]};
                    pixel_valid <= 1;
                    pixel_addr <= pixel_addr + 1;
                end
                
                if (byte_cnt == 683) pkt_count <= pkt_count + 1;

                byte_cnt <= byte_cnt + 1;
            end
        end
    end
endmodule
