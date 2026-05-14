// gvsp_rx.v
// Nhan du lieu GVSP tu Camera Mako qua MII 100Mbps
// Boc tach header, xuat pixel stream Mono8
// Date: 2025-05-09

module gvsp_rx (
    input            clk_eth,       // ENET_RX_CLK (25MHz)
    input            rst_n,

    // MII RX Interface
    input  [3:0]     RX_DATA,
    input            RX_DV,

    // Pixel Stream Output
    output reg [7:0] pixel_data,
    output reg       pixel_valid,
    output reg [18:0] pixel_addr,
    output reg       frame_start,
    output reg       frame_done,
    output reg [7:0] pkt_count      // Debug: so packet payload nhan duoc
);

// === Cau hinh co dinh (hardcode) ===
localparam [31:0] MY_IP   = 32'hC0A80164; // 192.168.1.100
localparam [15:0] MY_PORT = 16'd1234;

// === GVSP Packet type ===
localparam PKT_LEADER  = 8'h01;
localparam PKT_TRAILER = 8'h02;
localparam PKT_PAYLOAD = 8'h03;

// === Frame size ===
localparam FRAME_W = 320;
localparam FRAME_H = 240;

// === RX state ===
reg [7:0]  hdr_buf [0:63];   // Luu 64 byte dau cua frame Ethernet (sau SFD)
reg [10:0] rx_byte_idx;       // Dem byte (sau SFD)
reg        rx_nib_hi;         // Toggle nibble: 0=low, 1=high
reg [3:0]  rx_prev_nib;       // Luu low nibble
reg        rx_sfd_found;      // Da phat hien SFD (0xD5)
reg        in_payload;        // Dang trong vung pixel payload
reg [18:0] pixel_cnt_frame;   // Dem pixel trong frame
reg [15:0] prev_block_id;     // Frame ID truoc (de phat hien frame moi)
reg        hdr_matched;       // Header da match (IP/UDP/GVSP)

// === Ethernet Frame Layout (sau SFD, byte 0 = Dst MAC[0]) ===
// Byte  0- 5: Dst MAC (6B)
// Byte  6-11: Src MAC (6B)
// Byte 12-13: EtherType (0x0800 = IP)
// Byte 14-33: IP Header (20B) — Byte 23 = Protocol (0x11=UDP), Byte 30-33 = Dst IP
// Byte 34-41: UDP Header (8B) — Byte 36-37 = Dst Port
// Byte 42-49: GVSP Header (8B)
//   42-43: Status
//   44-45: Block ID (Frame ID)
//   46:    Packet Format (01=Leader, 02=Trailer, 03=Payload)
//   47-49: Packet ID
// Byte 50+:  GVSP Payload (pixel data)

always @(posedge clk_eth or negedge rst_n) begin
    if (!rst_n) begin
        rx_byte_idx <= 0; rx_nib_hi <= 0; rx_sfd_found <= 0;
        in_payload <= 0; hdr_matched <= 0;
        frame_start <= 0; frame_done <= 0; pixel_valid <= 0;
        pixel_addr <= 0; pixel_cnt_frame <= 0; pkt_count <= 0;
        prev_block_id <= 16'hFFFF;
    end else begin
        // Clear one-shot pulses
        frame_start <= 0;
        frame_done <= 0;
        pixel_valid <= 0;

        if (RX_DV) begin
            if (!rx_nib_hi) begin
                // === Nhan low nibble ===
                rx_prev_nib <= RX_DATA;
                rx_nib_hi <= 1;
            end else begin
                // === Nhan high nibble -> ghep thanh byte ===
                rx_nib_hi <= 0;

                if (!rx_sfd_found) begin
                    // Tim SFD = 0xD5
                    // MII truyen low nibble truoc: 0101 (0x5) roi 1101 (0xD)
                    // Byte = {high_nibble, low_nibble} = {RX_DATA, rx_prev_nib}
                    if ({RX_DATA, rx_prev_nib} == 8'hD5) begin
                        rx_sfd_found <= 1;
                        rx_byte_idx <= 0;
                        hdr_matched <= 0;
                    end
                end else begin
                    // === Đã qua SFD, đếm byte frame thực ===
                    
                    // Lưu header vào buffer (tối đa 64 byte)
                    if (rx_byte_idx < 64)
                        hdr_buf[rx_byte_idx] <= {RX_DATA, rx_prev_nib};

                    // === Kiểm tra header khi đủ 50 byte ===
                    // Dùng rx_byte_idx == 49 vì hdr_buf[49] vừa được ghi ở CÙNG cycle
                    // nhưng giá trị trong hdr_buf[0..48] đã ổn định từ các cycle trước
                    if (rx_byte_idx == 49) begin
                        // Check: EtherType=IP, Protocol=UDP, Dst IP=MY_IP, Dst Port=MY_PORT
                        if (hdr_buf[12] == 8'h08 && hdr_buf[13] == 8'h00 &&  // IPv4
                            hdr_buf[23] == 8'h11 &&                            // UDP
                            hdr_buf[30] == MY_IP[31:24] && hdr_buf[31] == MY_IP[23:16] &&
                            hdr_buf[32] == MY_IP[15:8]  && hdr_buf[33] == MY_IP[7:0]  &&
                            hdr_buf[36] == MY_PORT[15:8] && hdr_buf[37] == MY_PORT[7:0]) begin

                            hdr_matched <= 1;

                            // Decode GVSP packet type
                            case (hdr_buf[46])
                            PKT_LEADER: begin
                                // Frame mới nếu Block ID khác
                                if ({hdr_buf[44], hdr_buf[45]} != prev_block_id) begin
                                    frame_start <= 1;
                                    pixel_cnt_frame <= 0;
                                    prev_block_id <= {hdr_buf[44], hdr_buf[45]};
                                end
                                in_payload <= 0;
                            end
                            PKT_PAYLOAD: begin
                                in_payload <= 1;
                                pkt_count <= pkt_count + 1;
                            end
                            PKT_TRAILER: begin
                                in_payload <= 0;
                                frame_done <= 1;
                            end
                            default: begin
                                in_payload <= 0;
                            end
                            endcase
                        end else begin
                            hdr_matched <= 0;  // Không khớp → bỏ qua packet
                        end
                    end

                    // === Xuat pixel data (byte 50 tro di) ===
                    if (in_payload && rx_byte_idx >= 50) begin
                        pixel_data  <= {RX_DATA, rx_prev_nib};
                        pixel_valid <= 1;
                        pixel_addr  <= pixel_cnt_frame;
                        if (pixel_cnt_frame < FRAME_W * FRAME_H - 1)
                            pixel_cnt_frame <= pixel_cnt_frame + 1;
                    end

                    rx_byte_idx <= rx_byte_idx + 1;
                end // rx_sfd_found
            end // rx_nib_hi
        end else begin
            // === Packet kết thúc (RX_DV xuống thấp) ===
            rx_byte_idx <= 0;
            rx_nib_hi <= 0;
            rx_sfd_found <= 0;
            in_payload <= 0;
            hdr_matched <= 0;
        end
    end
end

endmodule
