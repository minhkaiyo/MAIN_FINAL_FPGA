// gvsp_parser_axi.v
module gvsp_parser_axi (
    input  wire clk,
    input  wire rst,
    
    // RX AXIS Input
    input  wire [7:0] rx_axis_tdata,
    input  wire rx_axis_tvalid,
    input  wire rx_axis_tlast,
    
    // Pixel Output
    output reg [7:0] pixel_data,
    output reg pixel_valid,
    output reg pixel_frame_end,
    output reg [15:0] frame_id
);

localparam ST_IDLE = 0, ST_HDR = 1, ST_PAYLOAD = 2;
reg [1:0] state = ST_IDLE;
reg [15:0] byte_cnt = 0;

always @(posedge clk) begin
    if (rst) begin
        state <= ST_IDLE;
        pixel_valid <= 0;
        pixel_frame_end <= 0;
    end else begin
        pixel_valid <= 0;
        pixel_frame_end <= 0;
        
        if (rx_axis_tvalid) begin
            case (state)
                ST_IDLE: begin
                    byte_cnt <= 0;
                    state <= ST_HDR;
                end
                ST_HDR: begin
                    // GVSP Header logic (Simplified for verification)
                    if (byte_cnt == 2) frame_id[15:8] <= rx_axis_tdata;
                    if (byte_cnt == 3) frame_id[7:0]  <= rx_axis_tdata;
                    
                    if (byte_cnt == 7) state <= ST_PAYLOAD;
                    else byte_cnt <= byte_cnt + 1;
                end
                ST_PAYLOAD: begin
                    pixel_data <= rx_axis_tdata;
                    pixel_valid <= 1;
                    if (rx_axis_tlast) begin
                        state <= ST_IDLE;
                        pixel_frame_end <= 1;
                    end
                end
            endcase
        end
    end
end
endmodule
