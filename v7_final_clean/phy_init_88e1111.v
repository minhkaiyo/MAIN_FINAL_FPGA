// phy_init_88e1111.v
module phy_init_88e1111 #(
    parameter CLK_MHZ = 50,
    parameter CLK_DIV = 100
)(
    input  wire clk, input wire rst_n,
    output reg  phy_rst_n, output reg mdc, inout wire mdio,
    output reg  configured,
    output wire [3:0] debug_fsm,
    output wire [4:0] debug_addr
);
    reg [4:0] phy_addr = 0; 
    reg [15:0] mio_in_data;
    reg mdio_oe=0, mdio_out=1;
    assign mdio = mdio_oe ? mdio_out : 1'bz;
    wire mdio_in = mdio;

    reg [15:0] div_cnt=0;
    reg mdc_rise=0;
    always @(posedge clk) begin
        if(div_cnt==CLK_DIV/2-1) begin div_cnt<=0; mdc<=~mdc; mdc_rise<=~mdc; end
        else div_cnt<=div_cnt+1;
    end

    reg [5:0] mio_cnt=0;
    reg [13:0] mio_hdr;
    reg [1:0] mio_st=0;
    localparam MIO_IDLE=0, MIO_FRAME=1, MIO_TA=2, MIO_DATA=3;

    localparam F_HWRST=0, F_HWWAIT=1, F_SCAN=2, F_SCAN_W=3, F_RD20=4, F_RD20W=5, F_WR20=6, F_WR20W=7, F_WR0=8, F_WR0W=9, F_DONE=10;
    reg [3:0] fsm=0;
    reg [24:0] timer=0;
    reg [4:0] mio_reg;
    reg mio_is_wr;
    reg [15:0] mio_wr_data;
    reg mio_start=0;

    assign debug_fsm = fsm;
    assign debug_addr = phy_addr;
    wire mio_done = (mio_st==MIO_IDLE && mio_cnt==0 && !mio_start);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            fsm<=F_HWRST; configured<=0; phy_addr<=0;
            mio_st<=MIO_IDLE; mio_cnt<=0; mio_start<=0; mdio_oe<=0;
        end else begin
            if(mio_start) begin
                mio_hdr <= mio_is_wr ? {2'b01,2'b01,phy_addr,mio_reg} : {2'b01,2'b10,phy_addr,mio_reg};
                mio_cnt <= 13; mio_st <= MIO_FRAME; mio_start <= 0; mdio_oe <= 1;
            end else case(mio_st)
                MIO_FRAME: if(mdc_rise) begin
                    mdio_out<=mio_hdr[13]; mio_hdr<={mio_hdr[12:0],1'b0};
                    if(mio_cnt==0) begin mio_cnt<=1; mio_st<=MIO_TA; end else mio_cnt<=mio_cnt-1;
                end
                MIO_TA: if(mdc_rise) begin
                    if(mio_is_wr) mdio_out<=1; else mdio_oe<=0;
                    if(mio_cnt==0) begin mio_cnt<=15; mio_st<=MIO_DATA; end else mio_cnt<=mio_cnt-1;
                end
                MIO_DATA: if(mdc_rise) begin
                    if(mio_is_wr) begin mdio_out<=mio_wr_data[15]; mio_wr_data<={mio_wr_data[14:0],1'b0}; end
                    else mio_in_data<={mio_in_data[14:0], mdio_in};
                    if(mio_cnt==0) begin mio_st<=MIO_IDLE; mdio_oe<=0; end else mio_cnt<=mio_cnt-1;
                end
            endcase

            case(fsm)
                F_HWRST: begin phy_rst_n<=0; timer<=CLK_MHZ*20000; fsm<=F_HWWAIT; end
                F_HWWAIT: if(timer==0) begin phy_rst_n<=1; timer<=CLK_MHZ*10000; fsm<=F_SCAN; end else timer<=timer-1;
                F_SCAN: if(mio_done) begin mio_reg<=2; mio_is_wr<=0; mio_start<=1; fsm<=F_SCAN_W; end
                F_SCAN_W: if(mio_done) begin
                    if(mio_in_data != 16'hFFFF && mio_in_data != 16'h0000) fsm<=F_RD20;
                    else if(phy_addr == 31) begin phy_addr<=0; timer<=CLK_MHZ*1000; fsm<=F_SCAN; end
                    else begin phy_addr<=phy_addr+1; fsm<=F_SCAN; end
                end
                F_RD20: if(mio_done) begin mio_reg<=20; mio_is_wr<=0; mio_start<=1; fsm<=F_RD20W; end
                F_RD20W: if(mio_done) begin mio_wr_data <= mio_in_data | 16'h0082; fsm<=F_WR20; end
                F_WR20: if(mio_done) begin mio_reg<=20; mio_is_wr<=1; mio_start<=1; fsm<=F_WR20W; end
                F_WR20W: if(mio_done) fsm<=F_WR0;
                F_WR0: if(mio_done) begin mio_reg<=0; mio_is_wr<=1; mio_wr_data<=16'h9140; mio_start<=1; fsm<=F_WR0W; end
                F_WR0W: if(mio_done) begin configured<=1; fsm<=F_DONE; end
                F_DONE: configured<=1;
            endcase
        end
    end
endmodule
