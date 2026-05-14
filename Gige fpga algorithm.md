# Thuật toán hoàn chỉnh: GigE Vision Receiver trên FPGA
```
Camera : Allied Vision Mako G-040 (728x544, Mono8, toi da 286fps)
Board  : Terasic DE2i-150 — Altera Cyclone IV GX EP4CGX150
PHY    : Marvell 88E1111 (RGMII interface)
Memory : SDRAM 256MB (frame buffer)
Output : VGA 800x600 (anh 728x544 o giua, vien den)
Tool   : Quartus II, ngon ngu Verilog
```

---

## TONG QUAN LUONG HE THONG

```
POWER ON / RESET
     |
     v
[M0] PHY INIT & LINK UP          <- Marvell 88E1111, RGMII
     |
     v
[M1] ARP ANNOUNCE                <- Bao IP cua FPGA len mang
     |
     v
[M2] GVCP DISCOVERY              <- Tim camera Mako G-040
     |  nhan ACK, luu IP+MAC camera
     v
[M3] GVCP FORCEIP                <- Gan IP co dinh cho camera
     |  ACK ok
     v
[M4] GVCP CCP — TAKE CONTROL     <- Gianh quyen dieu khien (BAT BUOC)
     |  ACK status = 0x0000
     v
[M5] GVCP CONFIGURE STREAM       <- Set IP+Port dich GVSP ve FPGA
     |  ACK ok
     v
[M6] GVCP CONFIGURE CAMERA       <- Set pixel format, width, height
     |  ACK ok
     v
[M7] HEARTBEAT LOOP              <- Giu ket noi (song song voi M8)
     |
     v
[M8] GVCP ACQUISITION START      <- Camera bat dau stream
     |
     +--------------------------------------------+
     v                                            v
[M9] GVSP RECEIVER               [M10] VGA CONTROLLER
     |  reassemble frame                |  doc frame buffer
     |  ghi vao SDRAM                    |  xuat ra VGA
     +---- frame_ready ---------------->|
     +---- swap double buffer ----------+
```

---

## MODULE 0: PHY INIT & ETHERNET LINK

```
Chip PHY : Marvell 88E1111
Interface: RGMII (4-bit data, 125MHz DDR)
IP core  : eth_mac_1g_rgmii (alexforencich/verilog-ethernet)
```

### Cau hinh PHY qua MDIO

```
MDIO_WRITE(PHY_ADDR=0x01, REG=0x00, DATA=0x9140)
  // Reg 0x00 = Control Register
  // 0x9140  = Software Reset + Gigabit + Auto-Negotiation Enable

MDIO_READ(PHY_ADDR=0x01, REG=0x01)
  // Reg 0x01 = Status Register
  // Bit 2 = Link Status
  // Cho den khi bit 2 = 1 (link up)
  // Timeout sau 3 giay -> reset lai tu dau

MDIO_READ(PHY_ADDR=0x01, REG=0x0A)
  // Xac nhan dang chay Gigabit
```

### State machine PHY INIT

```
STATE: PHY_RESET
  mdio_write(reg=0x00, data=0x9140)
  wait 100ms
  -> PHY_WAIT_LINK

STATE: PHY_WAIT_LINK
  mdio_read(reg=0x01)
  if bit[2] == 1 -> PHY_LINK_UP
  if timeout 3s  -> PHY_RESET (retry)

STATE: PHY_LINK_UP
  led_link = ON
  -> ARP_ANNOUNCE
```

### Cau hinh IP tinh cua FPGA

```
FPGA_MAC  = 48'hAA_BB_CC_DD_EE_FF   // MAC tu dat (locally administered)
FPGA_IP   = 32'hC0A8_0164            // 192.168.1.100
FPGA_PORT = 16'd5005                 // Port FPGA lang nghe GVSP

CAM_IP_STATIC = 32'hC0A8_0165       // 192.168.1.101 (IP muon gan cho cam)
SUBNET_MASK   = 32'hFFFF_FF00       // 255.255.255.0
```

---

## MODULE 1: ARP — ADDRESS RESOLUTION PROTOCOL

### ARP Request (FPGA hoi camera MAC)

```
Ethernet Header:
  dst_mac   = FF:FF:FF:FF:FF:FF   // Broadcast
  src_mac   = FPGA_MAC
  ethertype = 0x0806              // ARP

ARP Payload:
  htype = 0x0001    // Ethernet
  ptype = 0x0800    // IPv4
  hlen  = 0x06
  plen  = 0x04
  oper  = 0x0001    // Request
  sha   = FPGA_MAC
  spa   = FPGA_IP
  tha   = 00:00:00:00:00:00
  tpa   = CAM_IP_STATIC
```

### ARP Reply handler

```
Khi nhan ARP packet:
  if oper == 0x0002:             // Reply
    if spa == CAM_IP_STATIC:
      arp_table[CAM_IP_STATIC] = sha   // Luu MAC camera
      cam_mac_valid = 1
```

### ARP state machine

```
STATE: ARP_ANNOUNCE
  gui ARP request den CAM_IP_STATIC
  retry_count = 0
  -> ARP_WAIT

STATE: ARP_WAIT
  Cho ARP Reply, timeout = 1s
  if cam_mac_valid   -> GVCP_DISCOVERY
  if timeout:
    retry_count++
    if retry_count < 5 -> ARP_ANNOUNCE
    else               -> ERROR
```

---

## MODULE 2: GVCP — GIGABIT VISION CONTROL PROTOCOL

```
Cong GVCP : UDP port 3956 (camera lang nghe)
Format    : Request tu FPGA -> Acknowledge tu camera
Timeout   : 500ms moi command, retry 3 lan
```

### Cau truc GVCP packet chung

```
Byte 0   : 0x42                // Magic key
Byte 1   : 0x01                // Version = 1
Byte 2-3 : command_id          // Loai lenh
Byte 4-5 : payload_length      // Do dai phan payload (bytes)
Byte 6-7 : req_id              // Request ID (tang dan 1->65535)
Byte 8+  : payload             // Noi dung tuy command
```

### Bang command_id

```
0x0002  DISCOVERY_CMD   -> 0x0003  DISCOVERY_ACK
0x0004  FORCEIP_CMD     -> 0x0005  FORCEIP_ACK
0x0080  READREG_CMD     -> 0x0081  READREG_ACK
0x0082  WRITEREG_CMD    -> 0x0083  WRITEREG_ACK
```

### Bang Register dia chi GigE Vision Bootstrap

```
0x00000A00  ControlChannelPrivilege  // CCP — quyen dieu khien
0x00000D00  StreamChannelPort        // Port GVSP destination
0x00000D04  Width
0x00000D08  Height
0x00000D10  PixelFormat
0x00000D14  AcquisitionStart
0x00000D18  StreamChannelDestIP      // IP destination GVSP
0x00000D1C  OffsetX
0x00000D1E  AcquisitionMode
0x00000938  HeartbeatTimeout
```

---

### M2: GVCP DISCOVERY

```
// Dung Unicast Discovery (da biet IP camera)

TX Packet:
  dst_ip   = CAM_IP_STATIC      // Unicast, khong broadcast
  dst_port = 3956
  src_port = 3956
  payload:
    [0x42, 0x01]                // magic, version
    [0x00, 0x02]                // DISCOVERY_CMD
    [0x00, 0x00]                // length = 0
    [req_id >> 8, req_id & 0xFF]

Khi nhan DISCOVERY_ACK:
  bytes[2:3] = 0x00, 0x03      // DISCOVERY_ACK
  bytes[8:13] = cam_mac        // MAC camera (6 bytes)
  -> Luu cam_mac, xac nhan camera online
```

---

### M3: GVCP FORCEIP

```
TX Packet:
  dst_ip   = 255.255.255.255   // Broadcast (dung MAC-based)
  dst_port = 3956
  payload:
    [0x42, 0x01, 0x00, 0x04]  // FORCEIP_CMD
    [0x00, 0x1C]              // length = 28
    [req_id_hi, req_id_lo]
    [0x00, 0x00]              // reserved 2 bytes
    [cam_mac[5:0]]            // MAC camera 6 bytes
    [0x00, 0x00]              // padding 2 bytes
    [CAM_IP bytes 3..0]       // IP muon gan (big-endian)
    [SUBNET_MASK bytes 3..0]
    [GATEWAY bytes 3..0]      // co the la 0.0.0.0

Cho FORCEIP_ACK: status = 0x0000
Sau FORCEIP: doi 500ms de camera reinit IP stack
```

---

### M4: CCP — TAKE EXCLUSIVE CONTROL (BAT BUOC)

```
// Neu bo qua buoc nay -> moi WRITEREG sau se bi camera REJECTED

TX WriteReg:
  address = 0x00000A00
  value   = 0x00000002          // Exclusive Control

Payload:
  [0x42, 0x01, 0x00, 0x82]     // WRITEREG_CMD
  [0x00, 0x08]                 // length = 8
  [req_id_hi, req_id_lo]
  [0x00, 0x00, 0x0A, 0x00]     // address big-endian
  [0x00, 0x00, 0x00, 0x02]     // value

Nhan WRITEREG_ACK:
  bytes[8:9] = status
  if status == 0x0000 -> OK
  if status == 0x8005 -> camera dang bi control boi thiet bi khac -> ERROR
```

---

### M5: CAU HINH STREAM DESTINATION

```
// Noi camera biet gui GVSP stream ve dau

// 1. Set destination IP = FPGA IP
WriteReg(0x00000D18, 0xC0A80164)   // 192.168.1.100

// 2. Set destination port
WriteReg(0x00000D00, 0x0000138D)   // 5005

// 3. Set packet size (1500 bytes = MTU chuan, an toan qua router)
WriteReg(0x00000D04, 0x000005DC)   // 1500
// Neu dung truc tiep khong qua router: co the tang len 8228 (jumbo)

Moi WriteReg:
  Payload giong M4, chi thay address va value
  Phai cho ACK status = 0x0000 truoc khi gui cai tiep theo
```

---

### M6: CAU HINH CAMERA

```
// Set pixel format: Mono8
WriteReg(0x00000D10, 0x01080001)

// Set width = 728 (full resolution Mako G-040)
WriteReg(0x00000D04, 0x000002D8)

// Set height = 544
WriteReg(0x00000D08, 0x00000220)

// Set OffsetX = 0
WriteReg(0x00000D1C, 0x00000000)

// Set OffsetY = 0
WriteReg(0x00000D20, 0x00000000)

// Set AcquisitionMode = Continuous
WriteReg(0x00000D1E, 0x00000002)
```

---

### M7: HEARTBEAT — GIU KET NOI

```
// Mako G-040 mac dinh HeartbeatTimeout = 3000ms
// Neu khong co heartbeat trong 3000ms -> camera tu release control

// Cach 1: Disable heartbeat timeout (don gian nhat khi debug)
WriteReg(0x00000938, 0x00000000)

// Cach 2: Gui heartbeat dinh ky (production)
// Chay song song voi M8/M9/M10

HEARTBEAT_TIMER: moi 1000ms
  gui ReadReg(0x00000A00)    // Doc CCP = heartbeat nhe nhat
  if ACK ok -> reset timer
  if fail 3 lan lien tiep -> RECOVERY
```

---

### M8: ACQUISITION START

```
// Sau khi config xong, ra lenh stream

WriteReg(0x00000D14, 0x00000001)
  // AcquisitionStart command
  // value = 1 = execute

// Camera bat dau gui GVSP packets ve FPGA_IP:FPGA_PORT ngay lap tuc
```

---

### GVCP State Machine Tong quat (Verilog)

```verilog
localparam IDLE       = 4'd0;
localparam ARP_SEND   = 4'd1;
localparam ARP_WAIT   = 4'd2;
localparam DISCOVERY  = 4'd3;
localparam FORCEIP    = 4'd4;
localparam TAKE_CTRL  = 4'd5;
localparam CFG_STREAM = 4'd6;
localparam CFG_CAM    = 4'd7;
localparam ACQ_START  = 4'd8;
localparam STREAMING  = 4'd9;
localparam RECOVERY   = 4'd10;
localparam ERROR      = 4'd11;

reg [3:0]  gvcp_state;
reg [15:0] req_id;
reg [2:0]  cfg_step;
reg [2:0]  retry;
reg [31:0] timeout_cnt;

always @(posedge clk or posedge rst) begin
  if (rst) begin
    gvcp_state <= IDLE;
    req_id     <= 16'd1;
    cfg_step   <= 0;
    retry      <= 0;
  end else begin
    case (gvcp_state)

      IDLE: begin
        if (phy_link_up) gvcp_state <= ARP_SEND;
      end

      ARP_SEND: begin
        arp_send_req <= 1'b1;       // kich hoat ARP module
        retry        <= 0;
        timeout_cnt  <= 0;
        gvcp_state   <= ARP_WAIT;
      end

      ARP_WAIT: begin
        timeout_cnt <= timeout_cnt + 1;
        if (cam_mac_valid) begin
          gvcp_state <= DISCOVERY;
        end else if (timeout_cnt >= TIMEOUT_1S) begin
          if (retry < 5) begin
            retry      <= retry + 1;
            gvcp_state <= ARP_SEND;
          end else begin
            gvcp_state <= ERROR;
          end
        end
      end

      DISCOVERY: begin
        if (send_done) begin
          if (ack_ok && ack_cmd == 16'h0003)
            gvcp_state <= FORCEIP;
          else if (timeout || ack_fail)
            gvcp_state <= DISCOVERY;  // retry
        end else begin
          send_gvcp_discovery();
          req_id <= req_id + 1;
        end
      end

      FORCEIP: begin
        if (send_done && ack_ok) begin
          // Doi 500ms
          if (delay_done) gvcp_state <= TAKE_CTRL;
        end else begin
          send_gvcp_forceip(cam_mac, CAM_IP_STATIC);
          req_id <= req_id + 1;
        end
      end

      TAKE_CTRL: begin
        if (send_done) begin
          if (ack_ok)   gvcp_state <= CFG_STREAM;
          else          gvcp_state <= ERROR;   // camera bi chiem
        end else begin
          send_writereg(32'h00000A00, 32'h00000002, req_id);
          req_id <= req_id + 1;
        end
      end

      CFG_STREAM: begin
        if (send_done && ack_ok) begin
          cfg_step <= cfg_step + 1;
          if (cfg_step == 2) begin
            cfg_step   <= 0;
            gvcp_state <= CFG_CAM;
          end
        end else if (!send_busy) begin
          case (cfg_step)
            0: send_writereg(32'h00000D18, FPGA_IP,         req_id);
            1: send_writereg(32'h00000D00, 32'd5005,        req_id);
            2: send_writereg(32'h00000D04, 32'd1500,        req_id);
          endcase
          req_id <= req_id + 1;
        end
      end

      CFG_CAM: begin
        if (send_done && ack_ok) begin
          cfg_step <= cfg_step + 1;
          if (cfg_step == 4) begin
            cfg_step   <= 0;
            gvcp_state <= ACQ_START;
          end
        end else if (!send_busy) begin
          case (cfg_step)
            0: send_writereg(32'h00000D10, 32'h01080001,   req_id); // Mono8
            1: send_writereg(32'h00000D04, 32'd728,        req_id); // width
            2: send_writereg(32'h00000D08, 32'd544,        req_id); // height
            3: send_writereg(32'h00000D1E, 32'h00000002,   req_id); // continuous
            4: send_writereg(32'h00000938, 32'h00000000,   req_id); // disable HB
          endcase
          req_id <= req_id + 1;
        end
      end

      ACQ_START: begin
        if (send_done && ack_ok)
          gvcp_state <= STREAMING;
        else if (!send_busy) begin
          send_writereg(32'h00000D14, 32'h00000001, req_id);
          req_id <= req_id + 1;
        end
      end

      STREAMING: begin
        // Giu trang thai, heartbeat chay song song
        if (heartbeat_fail) gvcp_state <= RECOVERY;
      end

      RECOVERY: begin
        // Release control truoc khi retry
        send_writereg(32'h00000A00, 32'h00000000, req_id);
        req_id     <= 16'd1;
        cfg_step   <= 0;
        if (delay_1s_done) gvcp_state <= ARP_SEND;
      end

      ERROR: begin
        led_error <= 1'b1;
        // Cho manual reset
      end

    endcase
  end
end
```

---

## MODULE 3: GVSP RECEIVER — NHAN VA REASSEMBLE FRAME

```
Cong lang nghe : UDP FPGA_PORT (5005)
Du lieu Mako   : 728x544 Mono8 = 395,776 bytes/frame
So packet/frame: ~271 packets (MTU 1500) hoac ~49 packets (Jumbo 8228)
```

### Cau truc GVSP Packet Header

```
Byte 0-1 : status        (0x0000 = OK)
Byte 2-3 : block_id      (frame number, tang dan)
Byte 4   : packet_format
             0x01 = LEADER   (dau frame)
             0x02 = TRAILER  (cuoi frame)
             0x03 = PAYLOAD  (du lieu anh)
Byte 5-7 : packet_id     (thu tu packet trong frame, bat dau tu 0)
Byte 8+  : payload data
```

### Cau truc LEADER packet (packet_format = 0x01)

```
Byte 8-9  : payload_type  (0x0001 = uncompressed image)
Byte 10-17: timestamp (8 bytes)
Byte 18-21: pixel_format  (0x01080001 = Mono8)
Byte 22-25: size_x        (width = 728)
Byte 26-29: size_y        (height = 544)
Byte 30-33: offset_x
Byte 34-37: offset_y
```

### Thuat toan Reassemble Frame (Verilog)

```verilog
// Parameters
parameter BUF_A_BASE = 32'h0000_0000;
parameter BUF_B_BASE = 32'h0010_0000;  // 1MB offset
parameter IMG_SIZE   = 32'd395776;     // 728 x 544

// Registers
reg [15:0] current_block_id;
reg [23:0] expected_packet_id;
reg        frame_receiving;
reg [31:0] write_addr;
reg        buf_write_sel;             // 0=ghi A doc B, 1=ghi B doc A

always @(posedge clk or posedge rst) begin
  if (rst) begin
    frame_receiving    <= 0;
    buf_write_sel      <= 0;
    expected_packet_id <= 0;
    write_addr         <= BUF_A_BASE;
  end else if (udp_rx_valid && udp_rx_dst_port == FPGA_PORT) begin

    case (gvsp_packet_format)   // byte [4] cua GVSP header

      8'h01: begin  // LEADER
        current_block_id   <= gvsp_block_id;
        expected_packet_id <= 24'd1;
        write_addr         <= buf_write_sel ? BUF_B_BASE : BUF_A_BASE;
        frame_receiving    <= 1'b1;
        drop_flag          <= 1'b0;
      end

      8'h03: begin  // PAYLOAD
        if (frame_receiving
            && !drop_flag
            && gvsp_block_id == current_block_id) begin

          if (gvsp_packet_id == expected_packet_id) begin
            // Ghi payload vao SDRAM
            sdram_wr_addr  <= write_addr;
            sdram_wr_data  <= gvsp_payload;
            sdram_wr_len   <= gvsp_payload_len;
            sdram_wr_en    <= 1'b1;
            write_addr         <= write_addr + gvsp_payload_len;
            expected_packet_id <= expected_packet_id + 1;
          end else if (gvsp_packet_id > expected_packet_id) begin
            // Mat packet -> bo frame nay
            drop_flag       <= 1'b1;
            frame_receiving <= 1'b0;
            drop_count      <= drop_count + 1;
          end
          // packet_id < expected -> duplicate, bo qua
        end
      end

      8'h02: begin  // TRAILER
        if (frame_receiving
            && !drop_flag
            && gvsp_block_id == current_block_id) begin
          frame_receiving <= 1'b0;
          frame_ready     <= 1'b1;         // bao VGA controller
          buf_write_sel   <= ~buf_write_sel; // swap buffer
        end else begin
          frame_receiving <= 1'b0;
        end
      end

    endcase
  end else begin
    sdram_wr_en  <= 1'b0;
    frame_ready <= 1'b0;
  end
end
```

---

## MODULE 4: DOUBLE FRAME BUFFER TRONG SDRAM

```
SDRAM layout (DE2i-150 co 256MB SDRAM):
  [0x0000_0000 -> 0x0006_09FF]  Buffer A  (395,776 bytes = 728x544 Mono8)
  [0x0010_0000 -> 0x0016_09FF]  Buffer B  (offset 1MB cho alignment dep)

Co che swap:
  buf_write_sel = 0  -> GVSP ghi vao A, VGA doc tu B
  buf_write_sel = 1  -> GVSP ghi vao B, VGA doc tu A

  Khi nhan TRAILER va frame hop le:
    buf_write_sel <= ~buf_write_sel;

  VGA doc tu:
    vga_read_base = buf_write_sel ? BUF_A_BASE : BUF_B_BASE

Khong can mutex vi:
  - VGA doc tuan tu tu dau -> cuoi, khong bao gio doc lai
  - GVSP ghi vao buffer khac hoan toan
  - Chi swap sau TRAILER (frame HOAN CHINH)
```

---

## MODULE 5: VGA CONTROLLER

```
Resolution nguon : 728x544 (Mako G-040 full res)
VGA output       : 800x600 @ 60Hz (anh 728x544 o giua, vien den)
Pixel clock      : 40MHz (dung PLL tu 50MHz onboard)
```

### VGA Timing 800x600 @ 60Hz

```
Horizontal (pixels):
  Active = 800  |  FP = 40  |  Sync = 128  |  BP = 88  |  Total = 1056

Vertical (lines):
  Active = 600  |  FP = 1   |  Sync = 4    |  BP = 23  |  Total = 628

HSync: active LOW
VSync: active HIGH
```

### VGA Controller Verilog

```verilog
module vga_controller #(
  parameter H_ACTIVE = 800,
  parameter H_FP     = 40,
  parameter H_SYNC   = 128,
  parameter H_BP     = 88,
  parameter H_TOTAL  = 1056,
  parameter V_ACTIVE = 600,
  parameter V_FP     = 1,
  parameter V_SYNC   = 4,
  parameter V_BP     = 23,
  parameter V_TOTAL  = 628,
  parameter IMG_W    = 728,
  parameter IMG_H    = 544,
  parameter H_OFFSET = 36,   // (800-728)/2
  parameter V_OFFSET = 28,   // (600-544)/2
  parameter BUF_A    = 32'h0000_0000,
  parameter BUF_B    = 32'h0010_0000
)(
  input        clk_40mhz,
  input        rst,
  input        buf_write_sel,

  // SDRAM read
  output reg [31:0] rd_addr,
  output reg        rd_en,
  input      [7:0]  rd_data,
  input             rd_valid,

  // VGA signals
  output reg        vga_hs,
  output reg        vga_vs,
  output reg        vga_blank_n,
  output            vga_sync_n,
  output            vga_clk,
  output     [7:0]  vga_r,
  output     [7:0]  vga_g,
  output     [7:0]  vga_b
);

  reg [10:0] h_cnt;
  reg [9:0]  v_cnt;

  assign vga_clk   = clk_40mhz;
  assign vga_sync_n = 1'b0;

  // H counter
  always @(posedge clk_40mhz or posedge rst) begin
    if (rst) h_cnt <= 0;
    else if (h_cnt == H_TOTAL-1) h_cnt <= 0;
    else h_cnt <= h_cnt + 1;
  end

  // V counter
  always @(posedge clk_40mhz or posedge rst) begin
    if (rst) v_cnt <= 0;
    else if (h_cnt == H_TOTAL-1) begin
      if (v_cnt == V_TOTAL-1) v_cnt <= 0;
      else v_cnt <= v_cnt + 1;
    end
  end

  // Sync signals
  always @(posedge clk_40mhz) begin
    vga_hs      <= ~((h_cnt >= H_ACTIVE+H_FP) &&
                     (h_cnt <  H_ACTIVE+H_FP+H_SYNC));
    vga_vs      <=  ((v_cnt >= V_ACTIVE+V_FP) &&
                     (v_cnt <  V_ACTIVE+V_FP+V_SYNC));
    vga_blank_n <= (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);
  end

  // Vung hien thi anh (728x544 o giua 800x600)
  wire in_img_h = (h_cnt >= H_OFFSET) && (h_cnt < H_OFFSET + IMG_W);
  wire in_img_v = (v_cnt >= V_OFFSET) && (v_cnt < V_OFFSET + IMG_H);
  wire in_img   = in_img_h && in_img_v && vga_blank_n;

  // Base address cua buffer can doc
  wire [31:0] rd_base = buf_write_sel ? BUF_A : BUF_B;

  // Generate SDRAM read address
  always @(posedge clk_40mhz) begin
    if (in_img) begin
      rd_addr <= rd_base +
                 (v_cnt - V_OFFSET[9:0]) * IMG_W +
                 (h_cnt - H_OFFSET[10:0]);
      rd_en   <= 1'b1;
    end else begin
      rd_en   <= 1'b0;
    end
  end

  // Output: Mono8 -> RGB (3 kenh bang nhau = grayscale)
  assign vga_r = (in_img && rd_valid) ? rd_data : 8'h00;
  assign vga_g = (in_img && rd_valid) ? rd_data : 8'h00;
  assign vga_b = (in_img && rd_valid) ? rd_data : 8'h00;

endmodule
```

---

## TOP LEVEL — KET NOI CAC MODULE

```verilog
module top (
  input        CLOCK_50,
  input        RESET_N,

  // Ethernet PHY Marvell 88E1111
  output       ENET0_MDC,
  inout        ENET0_MDIO,
  output       ENET0_RESET_N,
  input        ENET0_RX_CLK,
  input  [3:0] ENET0_RX_DATA,
  input        ENET0_RX_DV,
  output       ENET0_GTX_CLK,
  output [3:0] ENET0_TX_DATA,
  output       ENET0_TX_EN,

  // VGA (24-bit DAC tren DE2i-150)
  output        VGA_CLK,
  output        VGA_HS,
  output        VGA_VS,
  output        VGA_BLANK_N,
  output        VGA_SYNC_N,
  output [7:0]  VGA_R,
  output [7:0]  VGA_G,
  output [7:0]  VGA_B,

  // SDRAM (giao tiep voi Altera SDRAM IP)
  // ... (khai bao theo SDRAM IP core cua Quartus)

  // Status
  output [7:0]  LEDR
);

  // PLL: 50MHz -> 125MHz (ETH), 40MHz (VGA), 200MHz (SDRAM ref)
  wire clk_125, clk_40, clk_200, pll_locked;
  pll_main pll_inst (
    .inclk0 (CLOCK_50),
    .c0     (clk_125),
    .c1     (clk_40),
    .c2     (clk_200),
    .locked (pll_locked)
  );

  wire rst = ~RESET_N | ~pll_locked;

  // Internal signals
  wire        phy_link_up;
  wire        cam_mac_valid;
  wire        frame_ready;
  wire        buf_write_sel;
  wire        heartbeat_fail;
  wire        error_flag;

  // UDP TX/RX bus
  wire [7:0]  udp_rx_data;
  wire        udp_rx_valid;
  wire [15:0] udp_rx_dst_port;
  wire [31:0] udp_rx_src_ip;
  wire [47:0] udp_rx_src_mac;

  // SDRAM arbiter
  wire [31:0] sdram_wr_addr, sdram_rd_addr;
  wire [7:0]  sdram_wr_data, sdram_rd_data;
  wire        sdram_wr_en,   sdram_rd_en, sdram_rd_valid;

  // --- Instances ---

  phy_mdio_ctrl u_phy_ctrl (
    .clk         (CLOCK_50),
    .rst         (rst),
    .mdc         (ENET0_MDC),
    .mdio        (ENET0_MDIO),
    .phy_reset_n (ENET0_RESET_N),
    .link_up     (phy_link_up)
  );

  // ETH MAC + UDP/IP stack (alexforencich/verilog-ethernet)
  eth_mac_1g_rgmii_fifo u_mac ( ... );
  udp_complete u_udp_stack ( ... );

  gvcp_controller u_gvcp (
    .clk           (clk_125),
    .rst           (rst),
    .phy_link_up   (phy_link_up),
    .udp_tx_*      (...),
    .udp_rx_*      (...),
    .cam_ip        (32'hC0A80165),
    .fpga_ip       (32'hC0A80164),
    .fpga_gvsp_port(16'd5005),
    .heartbeat_fail(heartbeat_fail),
    .error_flag    (error_flag)
  );

  gvsp_receiver u_gvsp (
    .clk            (clk_125),
    .rst            (rst),
    .udp_rx_data    (udp_rx_data),
    .udp_rx_valid   (udp_rx_valid),
    .udp_rx_dst_port(udp_rx_dst_port),
    .sdram_wr_addr   (sdram_wr_addr),
    .sdram_wr_data   (sdram_wr_data),
    .sdram_wr_en     (sdram_wr_en),
    .frame_ready    (frame_ready),
    .buf_write_sel  (buf_write_sel)
  );

  // SDRAM arbiter: uu tien GVSP ghi > VGA doc
  sdram_arbiter u_arb (
    .wr_addr  (sdram_wr_addr),
    .wr_data  (sdram_wr_data),
    .wr_en    (sdram_wr_en),
    .rd_addr  (sdram_rd_addr),
    .rd_en    (sdram_rd_en),
    .rd_data  (sdram_rd_data),
    .rd_valid (sdram_rd_valid)
    // ... connect to SDRAM IP core
  );

  vga_controller u_vga (
    .clk_40mhz    (clk_40),
    .rst          (rst),
    .buf_write_sel(buf_write_sel),
    .rd_addr      (sdram_rd_addr),
    .rd_en        (sdram_rd_en),
    .rd_data      (sdram_rd_data),
    .rd_valid     (sdram_rd_valid),
    .vga_hs       (VGA_HS),
    .vga_vs       (VGA_VS),
    .vga_blank_n  (VGA_BLANK_N),
    .vga_sync_n   (VGA_SYNC_N),
    .vga_clk      (VGA_CLK),
    .vga_r        (VGA_R),
    .vga_g        (VGA_G),
    .vga_b        (VGA_B)
  );

  // Status LED
  assign LEDR[0] = phy_link_up;
  assign LEDR[1] = cam_mac_valid;
  assign LEDR[2] = frame_ready;
  assign LEDR[3] = buf_write_sel;
  assign LEDR[7] = error_flag;

endmodule
```

---

## THU TU IMPLEMENT DE NGHI

```
Buoc 1: VGA hien thi test pattern
         -> Khong can camera, xac nhan VGA + SDRAM hoat dong dung

Buoc 2: ETH MAC + ARP
         -> Ping tu PC den FPGA IP (192.168.1.100)
         -> FPGA tra loi ping duoc = ETH stack ok

Buoc 3: UDP echo server
         -> Gui UDP packet den FPGA, FPGA gui lai
         -> Wireshark xac nhan FPGA nhan va gui dung

Buoc 4: GVCP controller
         -> Wireshark capture: loc "udp.port == 3956"
         -> So sanh packet FPGA gui voi packet Vimba gui
         -> Camera tra DISCOVERY_ACK = GVCP dung
         -> Dung den STREAMING state (chua can GVSP)

Buoc 5: GVSP receiver
         -> Wireshark loc "udp.port == 5005"
         -> Xac nhan FPGA nhan duoc GVSP packet
         -> Ghi vao SDRAM, doc lai kiem tra

Buoc 6: Ket hop VGA + GVSP
         -> Frame dau tien hien thi len man hinh
         -> Tinh chinh double buffer neu co hien tuong tearing
```

---

## LUU Y QUAN TRONG

```
1. DUNG WIRESHARK TRUOC KHI CODE
   Capture Vimba <-> Mako de biet chinh xac byte sequence
   Loc: udp.port == 3956 (GVCP) hoac udp.port == 5005 (GVSP)
   So sanh voi thuat toan tren, dieu chinh register address neu khac

2. REGISTER ADDRESS CO THE SACH HAN VIMBA VIEWER
   Vimba Viewer -> Feature Browser -> chuot phai -> "Copy Address"
   -> Lay dia chi chinh xac cua tung feature cho Mako G-040

3. CLOCK DOMAIN CROSSING
   ETH 125MHz <-> SDRAM <-> VGA 40MHz
   Dung async FIFO khi truyen signal qua domain khac nhau
   Dung gray code cho pointer cua async FIFO

4. SDRAM LATENCY
   SDRAM read co latency khong co dinh (~10-30 cycles)
   VGA can pixel dung gio, nen phai prefetch truoc it nhat 1 dong (728 pixels)
   Dung line buffer (BRAM 728 bytes) lam dem giua SDRAM va VGA output

5. JUMBO FRAME (tuy chon)
   Neu noi thang Camera -> FPGA (khong qua router):
   Tang packet size len 8228 bytes -> so packet/frame giam tu 271 xuong 49
   WriteReg(0x00000D04, 0x00002024)  // 8228 bytes
   -> On dinh hon, de reassemble hon
```