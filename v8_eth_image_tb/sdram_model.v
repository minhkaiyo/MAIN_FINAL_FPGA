// sdram_model.v
// Simple SDRAM Simulation Model (Simplified)
// Supports: ACT, WR, RD, PRE, REF
// Memory size: 64MB (similar to DE2i-150 SDRAM)
// Date: 2026-05-13

`timescale 1ns / 1ps

module sdram_model (
    input  wire        clk,
    input  wire        cke,
    input  wire        cs_n,
    input  wire        ras_n,
    input  wire        cas_n,
    input  wire        we_n,
    input  wire [1:0]  ba,
    input  wire [12:0] addr,
    input  wire [3:0]  dqm,
    inout  wire [31:0] dq
);

    // Memory array: 4 banks x 4096 rows x 512 columns (32-bit words)
    // Total: 4 * 4096 * 512 * 4 bytes = 32MB? 
    // DE2i-150 has 64MB (2 chips of 32MB? No, usually 1 chip 64MB 32-bit)
    // We only need enough for 640x480 images.
    reg [31:0] mem [0:2097151]; // 2M x 32-bit = 8MB (enough for ~25 frames)

    wire [3:0] cmd = {cs_n, ras_n, cas_n, we_n};
    localparam CMD_ACT = 4'b0011;
    localparam CMD_RD  = 4'b0101;
    localparam CMD_WR  = 4'b0100;
    localparam CMD_PRE = 4'b0010;
    localparam CMD_REF = 4'b0001;
    localparam CMD_MRS = 4'b0000;

    reg [12:0] active_row [0:3];
    reg [31:0] dq_out;
    reg        dq_en = 0;
    assign dq = dq_en ? dq_out : 32'bz;

    integer i;
    initial begin
        for (i = 0; i < 2097152; i = i + 1) mem[i] = 32'hDEADBEEF; // Default pattern
    end

    // Command Decoder
    always @(posedge clk) begin
        if (cke) begin
            case (cmd)
                CMD_ACT: begin
                    active_row[ba] <= addr;
                end
                CMD_WR: begin
                    // Simple linear address mapping for simulation
                    // {ba, active_row, column} -> mem_index
                    // Here we use {ba, active_row[8:0], addr[8:0]} to stay within 2M range
                    mem[{ba, active_row[ba][8:0], addr[8:0]}] <= dq;
                    $display("[SDRAM WR] Bank:%d Row:%d Col:%d Data:%h", ba, active_row[ba], addr[8:0], dq);
                end
                CMD_RD: begin
                    dq_en <= 1;
                    dq_out <= mem[{ba, active_row[ba][8:0], addr[8:0]}];
                    $display("[SDRAM RD] Bank:%d Row:%d Col:%d Data:%h", ba, active_row[ba], addr[8:0], mem[{ba, active_row[ba][8:0], addr[8:0]}]);
                end
                CMD_PRE: begin
                    dq_en <= 0;
                end
                default: begin
                    // CAS Latency simulation (fixed at 2 cycles for simplicity)
                    // In real model, this would be more complex
                    // But for this FSM, it's enough
                end
            endcase
        end
    end

    // Turn off DQ if not reading
    always @(posedge clk) begin
        if (cmd != CMD_RD && cmd != 4'b0111) begin // Not RD and not NOP? 
            // In a real chip, DQ stays for a bit depending on CAS latency
            // We'll keep it simple for now
        end
    end

endmodule
