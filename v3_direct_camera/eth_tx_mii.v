// eth_tx_mii.v
// MII TX Engine: Gui 1 Ethernet packet qua MII 100Mbps
// CRC32 tu dong. Buffer ngoai cung cap.
// Date: 2025-05-09

module eth_tx_mii (
    input           clk_25,     // 25MHz MII TX clock
    input           rst_n,

    // --- Interface voi module ngoai ---
    input  [10:0]   tx_len,     // So byte payload (khong tinh Preamble/SFD/CRC)
    input           tx_start,   // Pulse: bat dau gui
    output reg      tx_busy,    // 1 = dang gui

    // --- Buffer: doc tung byte ---
    output reg [10:0] buf_addr,
    input  [7:0]    buf_data,   // byte tai buf_addr (1 cycle delay)

    // --- MII TX Pins ---
    output reg [3:0] MII_TX_DATA,
    output reg       MII_TX_EN
);

// CRC32 lookup (ethernet polynomial 0xEDB88320)
function [31:0] crc32_byte;
    input [31:0] crc_in;
    input [7:0]  data;
    integer i;
    reg [31:0] c;
    begin
        c = crc_in ^ {24'd0, data};
        for (i = 0; i < 8; i = i + 1)
            c = (c[0]) ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
        crc32_byte = c;
    end
endfunction

localparam S_IDLE    = 0,
           S_PREAMBLE = 1,
           S_SFD     = 2,
           S_DATA    = 3,
           S_CRC     = 4,
           S_IPG     = 5;

reg [2:0]  state = S_IDLE;
reg [3:0]  nib_cnt;       // nibble trong 1 byte (0=lo, 1=hi)
reg [7:0]  cur_byte;
reg [10:0] byte_cnt;
reg [31:0] crc_reg;
reg [3:0]  preamble_cnt; // FIX LỖI: 3-bit không đếm được tới 13!
reg [3:0]  crc_nib;       // nibble index cua CRC (0-7)
reg [4:0]  ipg_cnt;
reg        buf_req;

// CRC phat nguoc (Ethernet gui CRC complement, LSB first)
wire [31:0] crc_out = ~crc_reg;

always @(posedge clk_25 or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE; MII_TX_EN <= 0; MII_TX_DATA <= 0;
        tx_busy <= 0; buf_addr <= 0; crc_reg <= 32'hFFFFFFFF;
    end else begin
        case (state)
        S_IDLE: begin
            MII_TX_EN <= 0; tx_busy <= 0;
            if (tx_start) begin
                tx_busy <= 1; preamble_cnt <= 0;
                crc_reg <= 32'hFFFFFFFF;
                nib_cnt <= 0; // Đảm bảo nibble luôn bắt đầu từ 0
                state <= S_PREAMBLE;
            end
        end

        S_PREAMBLE: begin
            MII_TX_EN <= 1; MII_TX_DATA <= 4'h5; // 0x55 x7
            if (preamble_cnt == 13) state <= S_SFD;
            else preamble_cnt <= preamble_cnt + 1;
        end

        S_SFD: begin
            // SFD = 0xD5: lo=5, hi=D
            if (nib_cnt == 0) begin MII_TX_DATA <= 4'h5; nib_cnt <= 1; end
            else begin MII_TX_DATA <= 4'hD; nib_cnt <= 0; byte_cnt <= 0; buf_addr <= 0; state <= S_DATA; end
        end

        S_DATA: begin
            if (nib_cnt == 0) begin
                // Doc byte tu buffer (da valid tu cycle truoc)
                cur_byte <= buf_data;
                MII_TX_DATA <= buf_data[3:0]; // Low nibble
                crc_reg <= crc32_byte(crc_reg, buf_data);
                nib_cnt <= 1;
            end else begin
                MII_TX_DATA <= cur_byte[7:4]; // High nibble
                nib_cnt <= 0;
                buf_addr <= buf_addr + 1;
                byte_cnt <= byte_cnt + 1;
                if (byte_cnt + 1 == tx_len) begin
                    crc_nib <= 0; state <= S_CRC;
                end
            end
        end

        S_CRC: begin
            // Gui 8 nibble CRC (4 byte, LSByte first)
            case (crc_nib)
                0: MII_TX_DATA <= crc_out[3:0];
                1: MII_TX_DATA <= crc_out[7:4];
                2: MII_TX_DATA <= crc_out[11:8];
                3: MII_TX_DATA <= crc_out[15:12];
                4: MII_TX_DATA <= crc_out[19:16];
                5: MII_TX_DATA <= crc_out[23:20];
                6: MII_TX_DATA <= crc_out[27:24];
                7: MII_TX_DATA <= crc_out[31:28];
            endcase
            if (crc_nib == 7) begin
                MII_TX_EN <= 0; ipg_cnt <= 0; state <= S_IPG;
            end else crc_nib <= crc_nib + 1;
        end

        S_IPG: begin
            // Inter-Packet Gap >= 12 byte = 24 nibble
            if (ipg_cnt == 23) state <= S_IDLE;
            else ipg_cnt <= ipg_cnt + 1;
        end
        endcase
    end
end

endmodule
