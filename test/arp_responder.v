// arp_responder.v
// Tu dong tra loi ARP Request va gui Gratuitous ARP khi khoi dong.
// FPGA IP: 192.168.1.100 | MAC: 00:11:22:33:44:55
// Date: 2025-05-09

module arp_responder (
    input           clk_25,
    input           rst_n,
    input           link_up,    // 1 = Ethernet link da up

    // --- MII RX (nhan ARP Request) ---
    input  [3:0]    RX_DATA,
    input           RX_DV,

    // --- Interface voi eth_tx_mii ---
    output reg       tx_start,
    output reg [10:0] tx_len,
    input            tx_busy,

    // --- Buffer cho eth_tx_mii doc ---
    input  [10:0]   buf_addr,
    output reg [7:0] buf_data
);

// --- Dia chi cua FPGA ---
localparam [47:0] MY_MAC = 48'h001122334455;
localparam [31:0] MY_IP  = 32'hC0A80164; // 192.168.1.100

// --- Nho packet ARP Reply (42 byte) ---
reg [7:0] arp_buf [0:41];

// --- Xay dung ARP Reply vao arp_buf ---
// Goi arp_build khi can gui
task build_arp_reply;
    input [47:0] dst_mac;
    input [31:0] dst_ip;
    begin
        // Ethernet Header (14B)
        arp_buf[0]  <= dst_mac[47:40]; arp_buf[1]  <= dst_mac[39:32];
        arp_buf[2]  <= dst_mac[31:24]; arp_buf[3]  <= dst_mac[23:16];
        arp_buf[4]  <= dst_mac[15:8];  arp_buf[5]  <= dst_mac[7:0];
        arp_buf[6]  <= MY_MAC[47:40];  arp_buf[7]  <= MY_MAC[39:32];
        arp_buf[8]  <= MY_MAC[31:24];  arp_buf[9]  <= MY_MAC[23:16];
        arp_buf[10] <= MY_MAC[15:8];   arp_buf[11] <= MY_MAC[7:0];
        arp_buf[12] <= 8'h08; arp_buf[13] <= 8'h06; // EtherType ARP
        // ARP Payload (28B)
        arp_buf[14] <= 8'h00; arp_buf[15] <= 8'h01; // HW type Ethernet
        arp_buf[16] <= 8'h08; arp_buf[17] <= 8'h00; // Proto type IP
        arp_buf[18] <= 8'h06;                        // HW size
        arp_buf[19] <= 8'h04;                        // Proto size
        arp_buf[20] <= 8'h00; arp_buf[21] <= 8'h02; // Opcode=Reply
        // Sender (FPGA)
        arp_buf[22] <= MY_MAC[47:40]; arp_buf[23] <= MY_MAC[39:32];
        arp_buf[24] <= MY_MAC[31:24]; arp_buf[25] <= MY_MAC[23:16];
        arp_buf[26] <= MY_MAC[15:8];  arp_buf[27] <= MY_MAC[7:0];
        arp_buf[28] <= MY_IP[31:24];  arp_buf[29] <= MY_IP[23:16];
        arp_buf[30] <= MY_IP[15:8];   arp_buf[31] <= MY_IP[7:0];
        // Target (requester)
        arp_buf[32] <= dst_mac[47:40]; arp_buf[33] <= dst_mac[39:32];
        arp_buf[34] <= dst_mac[31:24]; arp_buf[35] <= dst_mac[23:16];
        arp_buf[36] <= dst_mac[15:8];  arp_buf[37] <= dst_mac[7:0];
        arp_buf[38] <= dst_ip[31:24];  arp_buf[39] <= dst_ip[23:16];
        arp_buf[40] <= dst_ip[15:8];   arp_buf[41] <= dst_ip[7:0];
    end
endtask

// buf_data: doc tu arp_buf cho eth_tx_mii
always @(*) buf_data = arp_buf[buf_addr[5:0]];

// --- RX Parser: nhan ARP Request ---
reg [7:0]  rx_byte_buf [0:41];
reg [5:0]  rx_byte_idx;
reg        rx_nib_hi;
reg [3:0]  rx_prev_nib;
reg        rx_arp_detected;
reg [47:0] req_mac;
reg [31:0] req_ip;

// Gratuitous ARP timer
reg [24:0] grat_timer;
reg        grat_req;

localparam S_IDLE    = 0,
           S_WAIT_TX = 1,
           S_SEND    = 2;
reg [1:0]  tx_state = S_IDLE;

always @(posedge clk_25 or negedge rst_n) begin
    if (!rst_n) begin
        tx_start <= 0; tx_len <= 0; grat_timer <= 0; grat_req <= 0;
        rx_arp_detected <= 0; rx_byte_idx <= 0; rx_nib_hi <= 0; tx_state <= S_IDLE;
    end else begin
        tx_start <= 0;
        grat_timer <= grat_timer + 1;
        if (grat_timer == 0) grat_req <= link_up; // Moi ~1.3 giay

        // RX nibble assembly
        if (RX_DV) begin
            if (!rx_nib_hi) begin
                rx_prev_nib <= RX_DATA;
                rx_nib_hi <= 1;
            end else begin
                rx_nib_hi <= 0;
                if (rx_byte_idx < 42) begin
                    rx_byte_buf[rx_byte_idx] <= {RX_DATA, rx_prev_nib};
                    rx_byte_idx <= rx_byte_idx + 1;
                end
            end
        end else begin
            // End of packet: check ARP Request
            if (rx_byte_idx >= 42) begin
                // EtherType=0x0806, ARP Opcode=0x0001
                if (rx_byte_buf[12]==8'h08 && rx_byte_buf[13]==8'h06 &&
                    rx_byte_buf[20]==8'h00 && rx_byte_buf[21]==8'h01 &&
                    rx_byte_buf[38]==MY_IP[31:24] && rx_byte_buf[39]==MY_IP[23:16] &&
                    rx_byte_buf[40]==MY_IP[15:8]  && rx_byte_buf[41]==MY_IP[7:0]) begin
                    req_mac <= {rx_byte_buf[22],rx_byte_buf[23],rx_byte_buf[24],
                                rx_byte_buf[25],rx_byte_buf[26],rx_byte_buf[27]};
                    req_ip  <= {rx_byte_buf[28],rx_byte_buf[29],rx_byte_buf[30],rx_byte_buf[31]};
                    rx_arp_detected <= 1;
                end
            end
            rx_byte_idx <= 0; rx_nib_hi <= 0;
        end

        // TX state machine
        case (tx_state)
        S_IDLE: begin
            if (rx_arp_detected) begin
                rx_arp_detected <= 0;
                build_arp_reply(req_mac, req_ip);
                tx_len <= 42; tx_state <= S_WAIT_TX;
            end else if (grat_req) begin
                grat_req <= 0;
                build_arp_reply(48'hFFFFFFFFFFFF, MY_IP); // Broadcast
                tx_len <= 42; tx_state <= S_WAIT_TX;
            end
        end
        S_WAIT_TX: if (!tx_busy) begin tx_start <= 1; tx_state <= S_SEND; end
        S_SEND:    begin tx_start <= 0; tx_state <= S_IDLE; end
        endcase
    end
end

endmodule
