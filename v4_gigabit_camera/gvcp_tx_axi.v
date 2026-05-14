// gvcp_tx_axi.v
// GigE Vision Control Protocol (GVCP) Transmitter over AXI-Stream UDP interface
// Sends WriteReg commands to Mako G-040C camera via udp_complete stack
// SW[0] rising edge = Start (send all config + AcquisitionStart)
// SW[0] falling edge = Stop (send AcquisitionStop)
// Date: 2026-05-09

module gvcp_tx_axi #(
    parameter [31:0] MY_IP    = {8'd192, 8'd168, 8'd1, 8'd111},
    parameter [31:0] CAM_IP   = {8'd192, 8'd168, 8'd1, 8'd164},
    parameter [15:0] MY_PORT  = 16'd3957,
    parameter [15:0] GVCP_PORT= 16'd3956,
    parameter [15:0] STREAM_PORT = 16'd1234
) (
    input  wire        clk,          // 125MHz system clock (from eth MAC domain)
    input  wire        rst,          // active-high reset

    input  wire        trigger,      // SW[0]

    // UDP TX AXI-Stream interface (to udp_complete)
    output reg         udp_hdr_valid,
    input  wire        udp_hdr_ready,
    output wire [31:0] udp_dest_ip,
    output wire [15:0] udp_src_port,
    output wire [15:0] udp_dest_port,
    output wire [15:0] udp_length,
    output wire [15:0] udp_checksum,
    output wire [5:0]  udp_ip_dscp,
    output wire [1:0]  udp_ip_ecn,
    output wire [7:0]  udp_ip_ttl,
    output wire [31:0] udp_src_ip,

    output reg  [7:0]  udp_payload_tdata,
    output reg         udp_payload_tvalid,
    input  wire        udp_payload_tready,
    output reg         udp_payload_tlast,
    output wire        udp_payload_tuser,

    // Status
    output reg  [3:0]  cmd_idx_dbg,
    output reg  [2:0]  state_dbg,
    output reg         done
);

// Fixed UDP fields
assign udp_dest_ip   = CAM_IP;
assign udp_src_port  = MY_PORT;
assign udp_dest_port = GVCP_PORT;
assign udp_length    = 16'd24;  // 8 UDP header + 16 GVCP payload
assign udp_checksum  = 16'd0;
assign udp_ip_dscp   = 6'd0;
assign udp_ip_ecn    = 2'd0;
assign udp_ip_ttl    = 8'd64;
assign udp_src_ip    = MY_IP;
assign udp_payload_tuser = 0;

// ============================================================
// Command list: {addr[31:0], data[31:0]}
// ============================================================
localparam CMD_COUNT = 10;
reg [63:0] cmds [0:CMD_COUNT-1];
initial begin
    // 0: CCP = Exclusive Access
    cmds[0] = {32'h0000_0A00, 32'h0000_0002};
    // 1: Heartbeat = Disable
    cmds[1] = {32'h0000_0938, 32'h0000_0000};
    // 2: GevSCDA = Stream destination IP (FPGA IP)
    cmds[2] = {32'h0000_0D18, MY_IP};
    // 3: GevSCPHostPort = 1234
    cmds[3] = {32'h0000_0D1C, {16'd0, STREAM_PORT}};
    // 4: GevSCPSPacketSize = 1400
    cmds[4] = {32'h0000_0D00, 32'd1400};
    // 5: Width = 320
    cmds[5] = {32'h0001_000C, 32'd320};
    // 6: Height = 240
    cmds[6] = {32'h0001_0010, 32'd240};
    // 7: PixelFormat = Mono8
    cmds[7] = {32'h0001_0048, 32'h0108_0001};
    // 8: AcquisitionStart
    cmds[8] = {32'h0001_00B4, 32'h0000_0001};
    // 9: AcquisitionStop
    cmds[9] = {32'h0001_00B4, 32'h0000_0000};
end

// ============================================================
// State machine
// ============================================================
localparam S_IDLE    = 3'd0;
localparam S_HEADER  = 3'd1;   // Assert udp_hdr_valid
localparam S_PAYLOAD = 3'd2;   // Send 16 bytes GVCP payload
localparam S_GAP     = 3'd3;   // Inter-command gap
localparam S_DONE    = 3'd4;

reg [2:0]  state = S_IDLE;
reg [3:0]  cmd_idx = 0;
reg [15:0] req_id  = 1;
reg [3:0]  byte_cnt = 0;
reg [23:0] gap_cnt = 0;

// Trigger edge detection
reg trig_prev = 0;
wire trig_rise = trigger && !trig_prev;
wire trig_fall = !trigger && trig_prev;

// Current command fields (latched at S_HEADER start)
reg [31:0] cur_addr, cur_data;
reg [15:0] cur_reqid;

// GVCP payload byte mux: 16 bytes total
// [0]  Magic  0x42
// [1]  Flags  0x01  (ack requested)
// [2]  Cmd Hi 0x00
// [3]  Cmd Lo 0x82  (WriteReg)
// [4]  Len Hi 0x00
// [5]  Len Lo 0x08
// [6]  ReqID Hi
// [7]  ReqID Lo
// [8..11] Address (Big-Endian)
// [12..15] Data (Big-Endian)
function [7:0] gvcp_byte;
    input [3:0] idx;
    input [31:0] addr, data;
    input [15:0] rid;
    case (idx)
        4'd0:  gvcp_byte = 8'h42;
        4'd1:  gvcp_byte = 8'h01;
        4'd2:  gvcp_byte = 8'h00;
        4'd3:  gvcp_byte = 8'h82;
        4'd4:  gvcp_byte = 8'h00;
        4'd5:  gvcp_byte = 8'h08;
        4'd6:  gvcp_byte = rid[15:8];
        4'd7:  gvcp_byte = rid[7:0];
        4'd8:  gvcp_byte = addr[31:24];
        4'd9:  gvcp_byte = addr[23:16];
        4'd10: gvcp_byte = addr[15:8];
        4'd11: gvcp_byte = addr[7:0];
        4'd12: gvcp_byte = data[31:24];
        4'd13: gvcp_byte = data[23:16];
        4'd14: gvcp_byte = data[15:8];
        4'd15: gvcp_byte = data[7:0];
        default: gvcp_byte = 8'h00;
    endcase
endfunction

always @(posedge clk) begin
    if (rst) begin
        state           <= S_IDLE;
        cmd_idx         <= 0;
        req_id          <= 1;
        byte_cnt        <= 0;
        gap_cnt         <= 0;
        trig_prev       <= 0;
        done            <= 0;
        udp_hdr_valid   <= 0;
        udp_payload_tvalid <= 0;
        udp_payload_tlast  <= 0;
    end else begin
        trig_prev <= trigger;

        case (state)
        // -------------------------------------------------------
        S_IDLE: begin
            udp_hdr_valid        <= 0;
            udp_payload_tvalid   <= 0;
            if (trig_rise) begin
                // SW0 went high → send cmds 0..8 (setup + AcquisitionStart)
                cmd_idx <= 0;
                done    <= 0;
                state   <= S_HEADER;
            end else if (trig_fall && done) begin
                // SW0 went low → send cmd 9 (AcquisitionStop)
                cmd_idx <= 9;
                done    <= 0;
                state   <= S_HEADER;
            end
        end
        // -------------------------------------------------------
        S_HEADER: begin
            // Latch command and assert UDP header
            cur_addr      <= cmds[cmd_idx][63:32];
            cur_data      <= cmds[cmd_idx][31:0];
            cur_reqid     <= req_id;
            udp_hdr_valid <= 1;
            byte_cnt      <= 0;
            if (udp_hdr_valid && udp_hdr_ready) begin
                udp_hdr_valid <= 0;
                state         <= S_PAYLOAD;
                udp_payload_tvalid <= 1;
                udp_payload_tdata  <= gvcp_byte(0, cur_addr, cur_data, cur_reqid);
                udp_payload_tlast  <= 0;
            end
        end
        // -------------------------------------------------------
        S_PAYLOAD: begin
            if (udp_payload_tvalid && udp_payload_tready) begin
                if (byte_cnt == 4'd15) begin
                    // Packet done
                    udp_payload_tvalid <= 0;
                    udp_payload_tlast  <= 0;
                    req_id  <= req_id + 1;
                    gap_cnt <= 24'd250_000; // 2ms @ 125MHz
                    state   <= S_GAP;
                end else begin
                    byte_cnt <= byte_cnt + 1;
                    udp_payload_tdata <= gvcp_byte(byte_cnt + 1, cur_addr, cur_data, cur_reqid);
                    udp_payload_tlast <= ((byte_cnt + 1) == 4'd15);
                end
            end
        end
        // -------------------------------------------------------
        S_GAP: begin
            if (gap_cnt == 0) begin
                if (cmd_idx == 4'd8 || cmd_idx == 4'd9) begin
                    // Done
                    done  <= 1;
                    state <= S_DONE;
                end else begin
                    cmd_idx <= cmd_idx + 1;
                    state   <= S_HEADER;
                end
            end else gap_cnt <= gap_cnt - 1;
        end
        // -------------------------------------------------------
        S_DONE: begin
            done <= 1;
            // Allow re-trigger
            if (trig_fall || trig_rise) begin
                state <= S_IDLE;
                done  <= 0;
            end
        end
        endcase
    end
end

// Debug outputs
always @(posedge clk) begin
    cmd_idx_dbg <= cmd_idx;
    state_dbg   <= state;
end

endmodule
