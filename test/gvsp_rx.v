// gvsp_rx.v
// Parse goi tin GVSP tu Camera Mako qua MII 100Mbps
// Protocol: [Eth 14B][IP 20B][UDP 8B][GVSP Hdr 8B][Pixel Data...]
// Output: pixel data (Mono8) + write enable + frame sync
// Date: 2025-05-09

module gvsp_rx (
    input           clk_eth,    // ENET_RX_CLK 25MHz
    input           rst_n,

    // --- MII RX ---
    input  [3:0]    RX_DATA,
    input           RX_DV,

    // --- Output pixel stream ---
    output reg       frame_start,   // Pulse: bat dau frame moi
    output reg       frame_done,    // Pulse: ket thuc frame
    output reg [7:0] pixel_data,    // Mono8 pixel
    output reg       pixel_valid,   // 1 = pixel_data hop le
    output reg [18:0] pixel_addr,   // Vi tri pixel trong frame (0..320*240-1)

    // --- Debug ---
    output reg [7:0] pkt_count      // So packet da nhan
);

// --- Tat ca header byte duoc ghi vao shift buffer ---
reg [7:0]  hdr_buf [0:49];  // Du chua het [Eth+IP+UDP+GVSP] = 14+20+8+8 = 50B
reg [5:0]  hdr_idx;
reg        rx_nib_hi;
reg [3:0]  rx_prev_nib;
reg [7:0]  cur_byte;

// --- GVSP packet format byte 42-49 ---
// byte 42-43: Status (2B)
// byte 44-45: BlockID (Frame ID)
// byte 46: Packet Format
//   0x01 = Leader (bat dau frame)
//   0x02 = Trailer (ket thuc frame)
//   0x03 = Payload (du lieu)
// byte 47-49: PacketID (thu tu goi trong frame)

localparam PKT_LEADER  = 8'h01;
localparam PKT_TRAILER = 8'h02;
localparam PKT_PAYLOAD = 8'h03;

// --- Chieu rong/cao frame ---
localparam FRAME_W = 320;
localparam FRAME_H = 240;

// --- Trang thai parse ---
reg        in_payload;   // Dang trong vung payload
reg [18:0] pkt_pixel_offset; // Pixel offset tinh theo PacketID
reg [18:0] pixel_cnt_frame;  // Pixel da viet trong frame
reg [15:0] prev_block_id;

// UDP packet nhan duoc co ung dung ca IP (192.168.1.100, port 1234) khong
localparam [31:0] MY_IP   = 32'hC0A80164; // 192.168.1.100
localparam [15:0] MY_PORT = 16'd1234;

// --- RX nibble assembly ---
always @(posedge clk_eth or negedge rst_n) begin
    if (!rst_n) begin
        hdr_idx <= 0; rx_nib_hi <= 0; in_payload <= 0;
        frame_start <= 0; frame_done <= 0; pixel_valid <= 0;
        pixel_addr <= 0; pixel_cnt_frame <= 0; pkt_count <= 0;
    end else begin
        frame_start  <= 0; frame_done  <= 0; pixel_valid <= 0;

        if (RX_DV) begin
            if (!rx_nib_hi) begin
                rx_prev_nib <= RX_DATA; rx_nib_hi <= 1;
            end else begin
                cur_byte <= {RX_DATA, rx_prev_nib};
                rx_nib_hi <= 0;

                // Ghi vao header buffer
                if (hdr_idx < 50) begin
                    hdr_buf[hdr_idx] <= {RX_DATA, rx_prev_nib};
                    hdr_idx <= hdr_idx + 1;
                end

                // Khi da doc du 50 byte header -> check va xu ly
                if (hdr_idx == 49) begin
                    // Kiem tra: EtherType=IP, Proto=UDP, Dst IP=MY_IP, Dst Port=MY_PORT
                    if (hdr_buf[12]==8'h08 && hdr_buf[13]==8'h00 && // IP
                        hdr_buf[23]==8'h11 &&                        // UDP
                        hdr_buf[30]==MY_IP[31:24] && hdr_buf[31]==MY_IP[23:16] &&
                        hdr_buf[32]==MY_IP[15:8]  && hdr_buf[33]==MY_IP[7:0]  &&
                        hdr_buf[36]==MY_PORT[15:8] && hdr_buf[37]==MY_PORT[7:0]) begin

                        // GVSP header o byte 42-49
                        case (hdr_buf[46]) // Packet Format
                        PKT_LEADER: begin
                            // Frame moi bat dau
                            if (hdr_buf[44] != prev_block_id[15:8] ||
                                hdr_buf[45] != prev_block_id[7:0]) begin
                                frame_start <= 1;
                                pixel_cnt_frame <= 0;
                                pixel_addr <= 0;
                                prev_block_id <= {hdr_buf[44], hdr_buf[45]};
                            end
                            in_payload <= 0;
                        end
                        PKT_PAYLOAD: begin
                            // Pixel offset = PacketID * pixels_per_packet
                            // PacketID = hdr_buf[47:49] (3 byte)
                            // Offset = PacketID * (MTU - 50) = PacketID * 1430 (approx)
                            // Don gian: dung pixel_cnt_frame de dem lien tiep
                            pkt_pixel_offset <= {hdr_buf[47], hdr_buf[48], hdr_buf[49]};
                            in_payload <= 1;
                            pkt_count <= pkt_count + 1;
                        end
                        PKT_TRAILER: begin
                            in_payload <= 0; frame_done <= 1;
                        end
                        endcase
                    end
                end

                // Neu dang trong payload -> xuat pixel
                if (in_payload && hdr_idx >= 50) begin
                    pixel_data  <= {RX_DATA, rx_prev_nib};
                    pixel_valid <= 1;
                    pixel_addr  <= pixel_cnt_frame;
                    if (pixel_cnt_frame < FRAME_W * FRAME_H - 1)
                        pixel_cnt_frame <= pixel_cnt_frame + 1;
                end
            end
        end else begin
            // Het packet
            hdr_idx   <= 0; rx_nib_hi <= 0;
            in_payload <= 0;
        end
    end
end

endmodule
