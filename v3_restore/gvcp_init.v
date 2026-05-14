// gvcp_init.v
// Tu dong cau hinh Camera Mako G-040C qua GVCP (UDP port 3956)
// Gui chuoi WriteReg: set IP, Port, Resolution, Format, Start Acquisition
// Date: 2025-05-09

module gvcp_init (
    input           clk_25,
    input           rst_n,
    input           link_up,        // Bat dau khi co link
    input           arp_done,       // Bat dau sau khi ARP xong
    input           trigger,        // Gạt SW[0] để bắt đầu gửi lệnh

    output reg      done,           // 1 = da gui xong AcquisitionStart
    output [2:0]    gvcp_state_out, // Debug state
    output [3:0]    gvcp_cmd_idx,   // Debug cmd_idx (4-bit vi co 9 lenh)

    // --- Interface voi eth_tx_mii ---
    output reg       tx_start,
    output reg [10:0] tx_len,
    input            tx_busy,
    input  [10:0]   buf_addr,
    output reg [7:0] buf_data
);

// --- Network Parameters ---
localparam [47:0] MY_MAC     = 48'h001122334455;
localparam [31:0] MY_IP      = 32'hC0A80164; // 192.168.1.100
localparam [31:0] CAM_IP     = 32'hC0A801A4; // 192.168.1.164 (Khop voi anh Vimba)
localparam [47:0] CAM_MAC    = 48'h00_0F_31_5C_E5_1C; // MAC thuc te cua Mako
localparam [15:0] GVCP_PORT  = 16'd3956;
localparam [15:0] MY_PORT    = 16'd3957;
localparam [15:0] STREAM_PORT= 16'd1234;

// GVCP WriteReg command = [Magic 0x4200] [Flags 0x01] [Command 0x0082] [Length 8] [ReqID] [Addr] [Data]
// Total UDP payload = 16 bytes

// --- Danh sach lenh WriteReg ---
// Format: {addr[31:0], data[31:0]}
localparam CMD_COUNT = 10;
reg [63:0] cmds [0:9];
initial begin
    // 0: Control Channel Privilege (CCP) = Exclusive Access
    cmds[0] = {32'h00000A00, 32'h00000002};
    // 1: Heartbeat Disable
    cmds[1] = {32'h00000938, 32'h00000000};
    // 2: Stream Destination IP (GevSCDA) = MY_IP
    cmds[2] = {32'h00000D18, MY_IP};
    // 3: Stream Destination Port (GevSCPHostPort) = 1234
    cmds[3] = {32'h00000D1C, {16'd0, STREAM_PORT}};
    // 4: Packet Size (GevSCPSPacketSize) = 1400 (Tranh loi MTU 1500)
    cmds[4] = {32'h00000D00, 32'd1400};
    // 5: Width = 320 (Mako G-040C offset)
    cmds[5] = {32'h0001000C, 32'd320};
    // 6: Height = 240 (Mako G-040C offset)
    cmds[6] = {32'h00010010, 32'd240};
    // 7: PixelFormat = Mono8 (Mako G-040C offset)
    cmds[7] = {32'h00010048, 32'h01080001};
    // 8: AcquisitionStart (Mako G-040C offset)
    cmds[8] = {32'h000100B4, 32'h00000001};
    // 9: AcquisitionStop (Mako G-040C offset)
    cmds[9] = {32'h000100B4, 32'h00000000};
end

// --- TX Buffer: [Eth 14] + [IP 20] + [UDP 8] + [GVCP 16+2] = 60 byte ---
reg [7:0] pkt_buf [0:59];

reg [3:0]  cmd_idx = 0; // FIX LOI: 3-bit khong the dem den 8 (CMD_COUNT-1)!
reg [15:0] req_id  = 1;
reg [15:0] ip_checksum;

// Tinh IP Checksum (1's complement)
function [15:0] ip_chk;
    input [31:0] src_ip, dst_ip;
    reg [31:0] s;
    begin
        // Version+IHL=0x4500, Total=44, ID=0, Flags=0, TTL=64, Proto=17(UDP)
        s = 16'h4500 + 16'd44 + 16'h0000 + 16'h0000 + 16'h4011
          + src_ip[31:16] + src_ip[15:0]
          + dst_ip[31:16] + dst_ip[15:0];
        // Synthesis-friendly (Max 2 lan cong carry)
        s = (s & 32'h0000FFFF) + (s >> 16);
        s = (s & 32'h0000FFFF) + (s >> 16);
        ip_chk = ~s[15:0];
    end
endfunction

task build_gvcp_pkt;
    input [31:0] reg_addr;
    input [31:0] reg_data;
    input [15:0] id;
    reg [15:0] udp_len;
    reg [15:0] ip_chksum;
    begin
        udp_len   = 16'd24; // UDP hdr(8) + GVCP(16)
        ip_chksum = ip_chk(MY_IP, CAM_IP);
        // Ethernet
        pkt_buf[0]=CAM_MAC[47:40]; pkt_buf[1]=CAM_MAC[39:32];
        pkt_buf[2]=CAM_MAC[31:24]; pkt_buf[3]=CAM_MAC[23:16];
        pkt_buf[4]=CAM_MAC[15:8];  pkt_buf[5]=CAM_MAC[7:0];
        pkt_buf[6]=MY_MAC[47:40]; pkt_buf[7]=MY_MAC[39:32];
        pkt_buf[8]=MY_MAC[31:24]; pkt_buf[9]=MY_MAC[23:16];
        pkt_buf[10]=MY_MAC[15:8]; pkt_buf[11]=MY_MAC[7:0];
        pkt_buf[12]=8'h08; pkt_buf[13]=8'h00; // EtherType IP
        // IP Header
        pkt_buf[14]=8'h45; pkt_buf[15]=8'h00;
        pkt_buf[16]=8'h00; pkt_buf[17]=8'd44; // Total length
        pkt_buf[18]=8'h00; pkt_buf[19]=id[15:8]; // ID = req_id hi
        pkt_buf[20]=8'h00; pkt_buf[21]=8'h00; // Flags+FragOffset
        pkt_buf[22]=8'h40; pkt_buf[23]=8'h11; // TTL=64, Proto=UDP
        pkt_buf[24]=ip_chksum[15:8]; pkt_buf[25]=ip_chksum[7:0];
        pkt_buf[26]=MY_IP[31:24]; pkt_buf[27]=MY_IP[23:16];
        pkt_buf[28]=MY_IP[15:8];  pkt_buf[29]=MY_IP[7:0];
        pkt_buf[30]=CAM_IP[31:24];pkt_buf[31]=CAM_IP[23:16];
        pkt_buf[32]=CAM_IP[15:8]; pkt_buf[33]=CAM_IP[7:0];
        // UDP Header
        pkt_buf[34]=MY_PORT[15:8]; pkt_buf[35]=MY_PORT[7:0];
        pkt_buf[36]=GVCP_PORT[15:8]; pkt_buf[37]=GVCP_PORT[7:0];
        pkt_buf[38]=udp_len[15:8]; pkt_buf[39]=udp_len[7:0];
        pkt_buf[40]=8'h00; pkt_buf[41]=8'h00; // Checksum = 0 (optional)
        // GVCP WriteReg Command (16 bytes)
        pkt_buf[42]=8'h42; pkt_buf[43]=8'h01; // Magic=0x42, Flag=0x01 (Ack Req)
        pkt_buf[44]=8'h00; pkt_buf[45]=8'h82; // Command = WriteReg (0x0082)
        pkt_buf[46]=8'h00; pkt_buf[47]=8'h08; // Length = 8 bytes
        pkt_buf[48]=id[15:8]; pkt_buf[49]=id[7:0]; // Request ID
        
        // Data Payload (8 bytes)
        pkt_buf[50]=reg_addr[31:24]; pkt_buf[51]=reg_addr[23:16];
        pkt_buf[52]=reg_addr[15:8];  pkt_buf[53]=reg_addr[7:0];
        pkt_buf[54]=reg_data[31:24]; pkt_buf[55]=reg_data[23:16];
        pkt_buf[56]=reg_data[15:8];  pkt_buf[57]=reg_data[7:0];
    end
endtask

// Combo read buf_data tu pkt_buf (58 byte)
always @(*) buf_data = pkt_buf[(buf_addr < 58) ? buf_addr[5:0] : 6'd0];

localparam S_IDLE   = 0,
           S_WAIT   = 1,
           S_BUILD  = 2,
           S_SEND   = 3,
           S_GAP    = 4,
           S_DONE   = 5;
reg [2:0] state = S_IDLE;
reg [19:0] delay_cnt;

assign gvcp_state_out = state;
assign gvcp_cmd_idx = cmd_idx;

reg trigger_prev = 0;

always @(posedge clk_25 or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE; cmd_idx <= 0; req_id <= 1;
        tx_start <= 0; tx_len <= 0; done <= 0; delay_cnt <= 0;
        trigger_prev <= 0;
    end else begin
        tx_start <= 0;
        trigger_prev <= trigger;

        case (state)
        S_IDLE: begin
            if (link_up && arp_done) begin
                if (trigger && !trigger_prev) begin // SW0 BẬT -> Gửi từ lệnh 0 đến 8
                    cmd_idx <= 0; state <= S_WAIT; delay_cnt <= 0; done <= 0;
                end else if (!trigger && trigger_prev) begin // SW0 TẮT -> Chỉ gửi lệnh 9 (Stop)
                    cmd_idx <= 9; state <= S_WAIT; delay_cnt <= 0; done <= 0;
                end
            end
        end

        S_WAIT: begin // Doi 10ms giua cac lenh (250k cycles @ 25MHz)
            if (delay_cnt == 20'd250_000) begin
                delay_cnt <= 0; state <= S_BUILD;
            end else delay_cnt <= delay_cnt + 1;
        end

        S_BUILD: begin
            build_gvcp_pkt(cmds[cmd_idx][63:32], cmds[cmd_idx][31:0], req_id);
            tx_len <= 11'd58; // 58 byte packet
            state <= S_SEND;
        end

        S_SEND: begin
            if (!tx_busy) begin
                tx_start <= 1;
                req_id <= req_id + 1;
                
                if (cmd_idx == 8) begin // Đã gửi xong Start
                    state <= S_DONE;
                end else if (cmd_idx == 9) begin // Đã gửi xong Stop
                    state <= S_DONE;
                end else begin // Đang trong quá trình cài đặt (0 -> 7)
                    cmd_idx <= cmd_idx + 1; state <= S_WAIT;
                end
            end
        end

        S_DONE: begin 
            done <= 1; 
            if (trigger != trigger_prev) state <= S_IDLE; // Cho phép đổi trạng thái
        end
        endcase
    end
end

endmodule
