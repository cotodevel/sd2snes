`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    06:32:24 02/24/2018 
// Design Name: 
// Module Name:    gsu 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module gsu(
  input         RST,
  input         CLK,

  input [23:0] SAVERAM_MASK,
  input [23:0] ROM_MASK,

  // MMIO interface
  input         ENABLE,
  input         SNES_RD_start,
  input         SNES_WR_start,
  input         SNES_WR_end,
  input  [23:0] SNES_ADDR,
  input  [7:0]  DATA_IN,
  output        DATA_ENABLE,
  output [7:0]  DATA_OUT,
  
  // RAM interface
  input         ROM_BUS_RDY,
  output        ROM_BUS_RRQ,
  output        ROM_BUS_WRQ,
  output        ROM_BUS_WORD,
  output [23:0] ROM_BUS_ADDR,
  input  [15:0] ROM_BUS_RDDATA,
  output [15:0] ROM_BUS_WRDATA,
  
  // ACTIVE interface
  output        ACTIVE,
  
  // State debug read interface
  input  [9:0]  PGM_ADDR, // [9:0]
  output [7:0]  PGM_DATA, // [7:0]

  // config interface
  input [7:0] reg_group_in,
  input [7:0] reg_index_in,
  input [7:0] reg_value_in,
  input [7:0] reg_invmask_in,
  input       reg_we_in,
  input [7:0] reg_read_in,
  output[7:0] config_data_out,
  // config interface

  output DBG
);

// temporaries
integer i;
wire pipeline_advance;
wire op_complete;

//-------------------------------------------------------------------
// INPUTS
//-------------------------------------------------------------------
reg [7:0]  data_in_r;
reg [23:0] addr_in_r;
reg        enable_r;
reg [9:0]  pgm_addr_r;

always @(posedge CLK) begin
  data_in_r  <= DATA_IN;
  addr_in_r  <= SNES_ADDR;
  enable_r   <= ENABLE;
  pgm_addr_r <= PGM_ADDR;
end

//-------------------------------------------------------------------
// PARAMETERS
//-------------------------------------------------------------------
parameter NUM_GPR = 16;

parameter
  R0    = 8'h00,
  R1    = 8'h01,
  R2    = 8'h02,
  R3    = 8'h03,
  R4    = 8'h04,
  R5    = 8'h05,
  R6    = 8'h06,
  R7    = 8'h07,
  R8    = 8'h08,
  R9    = 8'h09,
  R10   = 8'h0A,
  R11   = 8'h0B,
  R12   = 8'h0C,
  R13   = 8'h0D,
  R14   = 8'h0E,
  R15   = 8'h0F
  ;

parameter
  ADDR_R0    = 8'h00,
  ADDR_R1    = 8'h02,
  ADDR_R2    = 8'h04,
  ADDR_R3    = 8'h06,
  ADDR_R4    = 8'h08,
  ADDR_R5    = 8'h0A,
  ADDR_R6    = 8'h0C,
  ADDR_R7    = 8'h0E,
  ADDR_R8    = 8'h10,
  ADDR_R9    = 8'h12,
  ADDR_R10   = 8'h14,
  ADDR_R11   = 8'h16,
  ADDR_R12   = 8'h18,
  ADDR_R13   = 8'h1A,
  ADDR_R14   = 8'h1C,
  ADDR_R15   = 8'h1E,
  ADDR_GPRL  = 8'b000x_xxx0,
  ADDR_GPRH  = 8'b000x_xxx1,
  
  ADDR_SFR   = 8'h30,
  ADDR_BRAMR = 8'h33,
  ADDR_PBR   = 8'h34,
  ADDR_ROMBR = 8'h36,
  ADDR_CFGR  = 8'h37,
  ADDR_SCBR  = 8'h38,
  ADDR_CLSR  = 8'h39,
  ADDR_SCMR  = 8'h3A,
  ADDR_VCR   = 8'h3B,
  ADDR_RAMBR = 8'h3C,
  ADDR_CBR   = 8'h3E,
  
  ADDR_CACHE_BASE = 10'h100
  ;

// instructions
parameter
  OP_STOP          = 8'h00,
  OP_NOP           = 8'h01,
  OP_CACHE         = 8'h02,
  
  // bra (no reset state)
  OP_BRA           = 8'h05,
  OP_BGE           = 8'h06,
  OP_BLT           = 8'h07,
  OP_BNE           = 8'h08,
  OP_BEQ           = 8'h09,
  OP_BPL           = 8'h0A,
  OP_BMI           = 8'h0B,
  OP_BCC           = 8'h0C,
  OP_BCS           = 8'h0D,
  OP_BVC           = 8'h0E,
  OP_BVS           = 8'h0F,
  // jmps/loops
  //OP_LINK_JMP_LJMP = 8'h9x, // conflict with lots
  OP_LOOP          = 8'h3C,
  
  // prefix (also see branch) no reset state
  OP_ALT1          = 8'h3D,
  OP_ALT2          = 8'h3E,
  OP_ALT3          = 8'h3F,
  OP_TO            = 8'h1x,
  OP_WITH          = 8'h2x,
  OP_FROM          = 8'hBx,
  
  // MOV
  // MOVE/MOVES use WITH/TO and WITH/FROM
  OP_IBT           = 8'hAx,
  OP_IWT           = 8'hFx,
  // load from ROM
  OP_GETB          = 8'hEF,
  // load from RAM
  OP_LD            = 8'h4x, // 4C, 4D, 4E, 4F conflict
  OP_ST            = 8'h3x, // 3C, 3D, 3E, 3F conflict
  OP_SBK           = 8'h90,
  OP_GETC_RAMB_ROMB= 8'hDF,
  
  // BITMAP
  OP_CMODE_COLOR   = 8'h4E,
  OP_PLOT_RPIX     = 8'h4C,
  
  // ALU
  OP_ADD           = 8'h5x,
  OP_SUB           = 8'h6x,
  //OP_AND_BIC       = 8'h7x, // 70 conflict
  //OP_OR_XOR        = 8'hCx, // C0 conflict
  OP_NOT           = 8'h4F,
  
  // ROTATE/SHIFT/INC/DEC
  OP_LSR           = 8'h03,
  OP_ASR_DIV2      = 8'h96,
  OP_ROL           = 8'h04,
  OP_ROR           = 8'h97,
  OP_INC           = 8'hDx,
  OP_DEC           = 8'hEx,
  
  // BYTE
  OP_SWAP          = 8'h4D,
  OP_SEX           = 8'h95,
  OP_LOB           = 8'h9E,
  OP_HIB           = 8'hC0,
  OP_MERGE         = 8'h70,
  
  // MULTIPLY
  OP_FMULT_LMULT   = 8'h9F,
  OP_MULT_UMULT    = 8'h8x
  
  ;

//-------------------------------------------------------------------
// CONFIG
//-------------------------------------------------------------------

parameter CONFIG_REGISTERS = 2;
reg [7:0] config_r[CONFIG_REGISTERS-1:0]; initial for (i = 0; i < CONFIG_REGISTERS; i = i + 1) config_r[i] = 8'h00;

always @(posedge CLK) begin
  if (RST) begin
    for (i = 0; i < CONFIG_REGISTERS; i = i + 1) config_r[i] <= 8'h00;
  end
  else if (reg_we_in && (reg_group_in == 8'h03)) begin
    if (reg_index_in < CONFIG_REGISTERS) config_r[reg_index_in] <= (config_r[reg_index_in] & reg_invmask_in) | (reg_value_in & ~reg_invmask_in);
  end
end

assign config_data_out = config_r[reg_read_in];

wire       CONFIG_STEP_ENABLED = config_r[0][0] | 1'b1; // FIXME: temporary enable
wire [7:0] CONFIG_STEP_COUNT   = config_r[1];

//-------------------------------------------------------------------
// FLOPS
//-------------------------------------------------------------------
reg cache_rom_rd_r; initial cache_rom_rd_r = 0;
reg gsu_rom_rd_r; initial gsu_rom_rd_r = 0;
reg gsu_ram_rd_r; initial gsu_ram_rd_r = 0;
reg gsu_ram_wr_r; initial gsu_ram_wr_r = 0;

reg cache_rom_word_r;
reg gsu_rom_word_r;
reg gsu_ram_word_r;

reg [23:0] cache_rom_addr_r;
reg [23:0] data_rom_addr_r;
reg [15:0] gsu_ram_data_r;

reg [31:0] gsu_cycle_cnt_r; initial gsu_cycle_cnt_r = 0;

reg [1:0]  gsu_cycle_r; initial gsu_cycle_r = 0;
reg        gsu_clock_en;

// step counter for pipelines
reg [7:0] stepcnt_r; initial stepcnt_r = 0;
reg       step_r; initial step_r = 0;

always @(posedge CLK) begin
  if (RST) begin
    gsu_cycle_r <= 0;
    gsu_clock_en <= 0;
  end
  else begin
    gsu_cycle_r  <= gsu_cycle_r + 1;
    gsu_clock_en <= (gsu_cycle_r == 2'b10);
  end
end

// Assert clock enable every 4 FPGA clocks.  Delays are calculated in
// terms of GSU clocks so this is used to align transitions and
// operate counters.

always @(posedge CLK) begin
  if (RST) begin
    gsu_cycle_cnt_r <= 0;
  end
  else if (gsu_clock_en & step_r) begin
    gsu_cycle_cnt_r <= gsu_cycle_cnt_r + 1;
  end
end

//-------------------------------------------------------------------
// STATE
//-------------------------------------------------------------------
reg [15:0] REG_r   [15:0];

// Special Registers
reg [15:0] SFR_r;   // 3030-3031
reg [7:0]  BRAMR_r; // 3033
reg [7:0]  PBR_r;   // 3034
reg [7:0]  ROMBR_r; // 3036
reg [7:0]  CFGR_r;  // 3037
reg [7:0]  SCBR_r;  // 3038
reg [7:0]  CLSR_r;  // 3039
reg [7:0]  SCMR_r;  // 303A
reg [7:0]  VCR_r;   // 303B
reg [7:0]  RAMBR_r; // 303C
reg [15:0] CBR_r;   // 303E
// unmapped
reg [7:0]  COLR_r;
reg [7:0]  POR_r;
reg [7:0]  SREG_r;
reg [7:0]  DREG_r;
reg [7:0]  ROMRDBUF_r;
reg [15:0] RAMWRBUF_r; // FIXME: this should be 8b
reg [15:0] RAMADDR_r;

// Important breakouts
assign SFR_Z    = SFR_r[1];
assign SFR_CY   = SFR_r[2];
assign SFR_S    = SFR_r[3];
assign SFR_OV   = SFR_r[4];
assign SFR_GO   = SFR_r[5];
assign SFR_RR   = SFR_r[6];
assign SFR_ALT1 = SFR_r[8];
assign SFR_ALT2 = SFR_r[9];
assign SFR_IL   = SFR_r[10];
assign SFR_IH   = SFR_r[11];
assign SFR_B    = SFR_r[12];
assign SFR_IRQ  = SFR_r[15];

assign BRAMR_EN = BRAMR_r[0];

assign CFGR_MS0 = CFGR_r[5];
assign CFGR_IRQ = CFGR_r[7];

assign CLSR_CLS = CLSR_r[0];

wire [1:0] SCMR_MD; assign SCMR_MD = SCMR_r[1:0];
wire [1:0] SCMR_HT; assign SCMR_HT = {SCMR_r[5],SCMR_r[2]};
assign SCMR_RAN = SCMR_r[3];
assign SCMR_RON = SCMR_r[4];

assign POR_TRS  = POR_r[0];
assign POR_DTH  = POR_r[1];
assign POR_HN   = POR_r[2];
assign POR_FHN  = POR_r[3];
assign POR_OBJ  = POR_r[4];

//-------------------------------------------------------------------
// PIPELINE IO
//-------------------------------------------------------------------
// Fetch -> Execute
// The fetch pipe and execution pipe are synchronized via the opbuf.
// Fetch operates one byte ahead of execution.
reg [7:0]  i2e_op_r[1:0]; initial for (i = 0; i < 2; i = i + 1) i2e_op_r[i] = OP_NOP;
reg        i2e_ptr_r; initial i2e_ptr_r = 0;

// Execute -> RegisterFile
reg        e2r_val_r;
reg [3:0]  e2r_destnum_r;
reg [15:0] e2r_data_r;
reg [15:0] e2r_r15_r;
reg [15:0] e2r_r4_r;
reg [1:0]  e2r_mask_r;
reg        e2r_loop_r;
reg        e2r_ljmp_r;
reg [15:0] e2r_pbr_r;
reg        e2r_wpor_r;
reg [7:0]  e2r_por_r;
reg        e2r_wcolr_r;
reg [7:0]  e2r_colr_r;
// non dest registers to update
reg [1:0]  e2r_alt_r;
reg        e2r_z_r;
reg        e2r_cy_r;
reg        e2r_s_r;
reg        e2r_ov_r;
reg        e2r_b_r;
reg        e2r_g_r;
reg        e2r_irq_r;
reg [3:0]  e2r_sreg_r;
reg [3:0]  e2r_dreg_r;

// Fetch -> Common
reg        i2c_waitcnt_val_r; initial i2c_waitcnt_val_r = 0;
reg [3:0]  i2c_waitcnt_r;

// Execute -> Common
reg        e2c_waitcnt_val_r; initial e2c_waitcnt_val_r = 0;
reg [3:0]  e2c_waitcnt_r;

reg waitcnt_zero_r;

//-------------------------------------------------------------------
// FIXME: Pixel Buffer
//-------------------------------------------------------------------

//-------------------------------------------------------------------
// Cache
//-------------------------------------------------------------------
// GSU/SNES interface
reg        cache_mmio_wren_r; initial cache_mmio_wren_r = 0;
reg  [7:0] cache_mmio_wrdata_r;
reg  [8:0] cache_mmio_addr_r;

reg        cache_gsu_wren_r; initial cache_gsu_wren_r = 0;
reg  [7:0] cache_gsu_wrdata_r;
reg  [8:0] cache_gsu_addr_r;

wire       cache_wren;
wire [8:0] cache_addr;
wire [7:0] cache_wrdata;
wire [7:0] cache_rddata;
// 
wire       debug_cache_wren;
wire [8:0] debug_cache_addr;
wire [7:0] debug_cache_wrdata;
wire [7:0] debug_cache_rddata;

assign cache_wren   = SFR_GO ? cache_gsu_wren_r   : cache_mmio_wren_r;
assign cache_addr   = SFR_GO ? cache_gsu_addr_r   : cache_mmio_addr_r;
assign cache_wrdata = SFR_GO ? cache_gsu_wrdata_r : cache_mmio_wrdata_r;

assign debug_cache_wren = 0;
assign debug_cache_addr = {~pgm_addr_r[8],pgm_addr_r[7:0]};

// valid bits
reg [31:0] cache_val_r; initial cache_val_r = 0;

gsu_cache cache (
  .clka(CLK), // input clka
  .wea(cache_wren), // input [0 : 0] wea
  .addra(cache_addr), // input [8 : 0] addra
  .dina(cache_wrdata), // input [7 : 0] dina
  .douta(cache_rddata), // output [7 : 0] douta
  
  .clkb(CLK), // input clkb
  .web(debug_cache_wren), // input [0 : 0] web
  .addrb(debug_cache_addr), // input [8 : 0] addrb
  .dinb(debug_cache_wrdata), // input [7 : 0] dinb
  .doutb(debug_cache_rddata) // output [7 : 0] doutb
);

//-------------------------------------------------------------------
// REGISTER/MMIO ACCESS
//-------------------------------------------------------------------
// This handles all state read and write.  The main execution pipeline
// feeds intermediate results back here.
reg        data_enable_r;
reg [7:0]  data_out_r;
reg [7:0]  data_flop_r;

reg        snes_write_r;

always @(posedge CLK) begin
  if (RST) begin
    //for (i = 0; i < NUM_GPR; i = i + 1) begin
    //  REG_r[i] <= 0;
    //end
    
    SFR_r   <= 0;
    BRAMR_r <= 0;
    PBR_r   <= 0;
    //ROMBR_r <= 0;
    CFGR_r  <= 0;
    SCBR_r  <= 0;
    CLSR_r  <= 0;
    SCMR_r  <= 0;
    VCR_r   <= 4;
    //RAMBR_r <= 0;
    
    COLR_r  <= 0;
    POR_r   <= 0;
    SREG_r  <= 0;
    DREG_r  <= 0;
    
    //ROMRDBUF_r <= 0;
    //RAMWRBUF_r <= 0;
    //RAMADDR_r  <= 0;
    
    data_enable_r <= 0;
    data_flop_r <= 0;
    snes_write_r <= 0;
    
    cache_mmio_wren_r <= 0;
  end
  else begin
    // True data enable.  This assumes we need unmapped read addresses to be openbus.
    // Register Read
    if (enable_r) begin
      if (SNES_RD_start) begin
        if (~|addr_in_r[9:8]) begin
          casex (addr_in_r[7:0])
            ADDR_GPRL : begin data_out_r <= REG_r[addr_in_r[4:1]][7:0];  if (~SFR_GO) data_enable_r <= 1; end
            ADDR_GPRH : begin data_out_r <= REG_r[addr_in_r[4:1]][15:8]; if (~SFR_GO) data_enable_r <= 1; end
          
            ADDR_SFR  : begin data_out_r <= SFR_r[7:0];  data_enable_r <= 1; end
            ADDR_SFR+1: begin data_out_r <= SFR_r[15:8]; data_enable_r <= 1; end
            ADDR_PBR  : begin data_out_r <= PBR_r;       if (~SFR_GO) data_enable_r <= 1; end
            ADDR_ROMBR: begin data_out_r <= ROMBR_r;     if (~SFR_GO) data_enable_r <= 1; end
            ADDR_VCR  : begin data_out_r <= VCR_r;       data_enable_r <= 1; end
            ADDR_RAMBR: begin data_out_r <= RAMBR_r;     if (~SFR_GO) data_enable_r <= 1; end
            ADDR_CBR+0: begin data_out_r <= CBR_r[7:0];  if (~SFR_GO) data_enable_r <= 1; end
            ADDR_CBR+1: begin data_out_r <= CBR_r[15:8]; if (~SFR_GO) data_enable_r <= 1; end
          endcase
        end
        else begin
          data_enable_r <= 1;
          cache_mmio_addr_r <= {~addr_in_r[8],addr_in_r[7:0]};
        end
      end
      else if (cache_mmio_wren_r) begin
        data_out_r <= cache_rddata;
        cache_mmio_wren_r <= 0;
      end
    end
    else begin
      data_enable_r <= 0;
    end
  
    // Register Write
    snes_write_r <= SNES_WR_end && enable_r && ({addr_in_r[9:1],1'b0} == ADDR_SFR || addr_in_r[9:0] == ADDR_SCMR || !SFR_GO);
  
    // TODO: figure out how to deal with conflicts between SFX and SNES.
    // handle GSU register writes
    if (pipeline_advance | snes_write_r) begin
      // handle GPR
      if (e2r_val_r) begin
        case (e2r_destnum_r)
          R0 : begin if (~e2r_mask_r[1]) REG_r[R0 ][15:8] <= e2r_data_r[15:8]; if (~e2r_mask_r[0]) REG_r[R0 ][7:0] <= e2r_data_r[7:0]; if (SFR_GO) REG_r[R15] <= REG_r[R15] + 1; end
          R1 : begin if (~e2r_mask_r[1]) REG_r[R1 ][15:8] <= e2r_data_r[15:8]; if (~e2r_mask_r[0]) REG_r[R1 ][7:0] <= e2r_data_r[7:0]; if (SFR_GO) REG_r[R15] <= REG_r[R15] + 1; end
          R2 : begin if (~e2r_mask_r[1]) REG_r[R2 ][15:8] <= e2r_data_r[15:8]; if (~e2r_mask_r[0]) REG_r[R2 ][7:0] <= e2r_data_r[7:0]; if (SFR_GO) REG_r[R15] <= REG_r[R15] + 1; end
          R3 : begin if (~e2r_mask_r[1]) REG_r[R3 ][15:8] <= e2r_data_r[15:8]; if (~e2r_mask_r[0]) REG_r[R3 ][7:0] <= e2r_data_r[7:0]; if (SFR_GO) REG_r[R15] <= REG_r[R15] + 1; end
          R4 : begin if (~e2r_mask_r[1]) REG_r[R4 ][15:8] <= e2r_data_r[15:8]; if (~e2r_mask_r[0]) REG_r[R4 ][7:0] <= e2r_data_r[7:0]; if (SFR_GO) REG_r[R15] <= REG_r[R15] + 1; end
          R5 : begin if (~e2r_mask_r[1]) REG_r[R5 ][15:8] <= e2r_data_r[15:8]; if (~e2r_mask_r[0]) REG_r[R5 ][7:0] <= e2r_data_r[7:0]; if (SFR_GO) REG_r[R15] <= REG_r[R15] + 1; end
          R6 : begin if (~e2r_mask_r[1]) REG_r[R6 ][15:8] <= e2r_data_r[15:8]; if (~e2r_mask_r[0]) REG_r[R6 ][7:0] <= e2r_data_r[7:0]; if (SFR_GO) REG_r[R15] <= REG_r[R15] + 1; end
          R7 : begin if (~e2r_mask_r[1]) REG_r[R7 ][15:8] <= e2r_data_r[15:8]; if (~e2r_mask_r[0]) REG_r[R7 ][7:0] <= e2r_data_r[7:0]; if (SFR_GO) REG_r[R15] <= REG_r[R15] + 1; end
          R8 : begin if (~e2r_mask_r[1]) REG_r[R8 ][15:8] <= e2r_data_r[15:8]; if (~e2r_mask_r[0]) REG_r[R8 ][7:0] <= e2r_data_r[7:0]; if (SFR_GO) REG_r[R15] <= REG_r[R15] + 1; end
          R9 : begin if (~e2r_mask_r[1]) REG_r[R9 ][15:8] <= e2r_data_r[15:8]; if (~e2r_mask_r[0]) REG_r[R9 ][7:0] <= e2r_data_r[7:0]; if (SFR_GO) REG_r[R15] <= REG_r[R15] + 1; end
          R10: begin if (~e2r_mask_r[1]) REG_r[R10][15:8] <= e2r_data_r[15:8]; if (~e2r_mask_r[0]) REG_r[R10][7:0] <= e2r_data_r[7:0]; if (SFR_GO) REG_r[R15] <= REG_r[R15] + 1; end
          R11: begin if (~e2r_mask_r[1]) REG_r[R11][15:8] <= e2r_data_r[15:8]; if (~e2r_mask_r[0]) REG_r[R11][7:0] <= e2r_data_r[7:0]; if (SFR_GO) REG_r[R15] <= REG_r[R15] + 1; end
          R12: begin if (~e2r_mask_r[1]) REG_r[R12][15:8] <= e2r_data_r[15:8]; if (~e2r_mask_r[0]) REG_r[R12][7:0] <= e2r_data_r[7:0]; if (SFR_GO) REG_r[R15] <= e2r_loop_r ? REG_r[R13] : (REG_r[R15] + 1); end
          R13: begin if (~e2r_mask_r[1]) REG_r[R13][15:8] <= e2r_data_r[15:8]; if (~e2r_mask_r[0]) REG_r[R13][7:0] <= e2r_data_r[7:0]; if (SFR_GO) REG_r[R15] <= REG_r[R15] + 1; end
          R14: begin if (~e2r_mask_r[1]) REG_r[R14][15:8] <= e2r_data_r[15:8]; if (~e2r_mask_r[0]) REG_r[R14][7:0] <= e2r_data_r[7:0]; if (SFR_GO) REG_r[R15] <= REG_r[R15] + 1; end
          R15: REG_r[R15] <= e2r_r15_r;
        endcase
      end
      else if (SFR_GO) begin
        REG_r[R15] <= REG_r[R15] + 1;
      end
      
      // handle other
      if (snes_write_r) begin
        if (~|addr_in_r[9:8]) begin
          case (addr_in_r[7:0])
            //ADDR_GPRL : data_flop_r <= data_in_r;
            //ADDR_GPRH : begin REG_r[addr_in_r[4:1]] <= {data_in_r,data_flop_r}; if (addr_in_r[4:1] == R15) SFR_r[5] <= 1; end
            ADDR_R15+1: SFR_r[5] <= 1;
          
            ADDR_SFR  : SFR_r[6:1] <= data_in_r[6:1];
            ADDR_SFR+1: {SFR_r[15],SFR_r[12:8]} <= {data_in_r[7],data_in_r[4:0]};
            ADDR_BRAMR: BRAMR_r[0] <= data_in_r[0];
            ADDR_PBR  : PBR_r <= data_in_r;
            //ADDR_ROMBR: ROMBR_r <= data_in_r;
            ADDR_CFGR : {CFGR_r[7],CFGR_r[5]} <= {data_in_r[7],data_in_r[5]};
            ADDR_SCBR : SCBR_r <= data_in_r;
            ADDR_CLSR : CLSR_r[0] <= data_in_r[0];
            ADDR_SCMR : SCMR_r[5:0] <= data_in_r[5:0];
            //ADDR_VCR  : VCR_r <= data_in_r;
            //ADDR_RAMBR: RAMBR_r[0] <= data_in_r[0];
            //ADDR_CBR+0: CBR_r[7:4] <= data_in_r[7:4];
            //ADDR_CBR+1: CBR_r[15:8] <= data_in_r;
          endcase
        end
        else begin
          cache_mmio_wren_r <= 1;
          cache_mmio_wrdata_r <= data_in_r;
          cache_mmio_addr_r <= {~addr_in_r[8],addr_in_r[7:0]};
        end
      end
      else if (op_complete) begin
        // TODO: R, IL,IH, IRQ
        SFR_r[1]   <= e2r_z_r;
        SFR_r[2]   <= e2r_cy_r;
        SFR_r[3]   <= e2r_s_r;
        SFR_r[4]   <= e2r_ov_r;
        SFR_r[5]   <= e2r_g_r;
        SFR_r[9:8] <= e2r_alt_r;
        SFR_r[12]  <= e2r_b_r;
        SFR_r[15]  <= e2r_irq_r;
          
        SREG_r     <= e2r_sreg_r;
        DREG_r     <= e2r_dreg_r;
        if (e2r_ljmp_r) PBR_r <= e2r_pbr_r;
        if (e2r_wpor_r) POR_r <= e2r_por_r;
        if (e2r_wcolr_r) COLR_r <= e2r_colr_r;
      end
      
      if (snes_write_r) data_flop_r <= data_in_r;
    end
  end
end

//-------------------------------------------------------------------
// COMMON PIPELINE
//-------------------------------------------------------------------

reg [3:0] fetch_waitcnt_r;
reg [3:0] exe_waitcnt_r;

always @(posedge CLK) begin
  if (RST) begin
    fetch_waitcnt_r <= 0;
    exe_waitcnt_r <= 0;
    waitcnt_zero_r <= 0;
    
    stepcnt_r <= 0;
    step_r <= 0;
  end
  else begin
    // decrement delay counters
    if (i2c_waitcnt_val_r) fetch_waitcnt_r <= i2c_waitcnt_r;
    else if (gsu_clock_en & |fetch_waitcnt_r) fetch_waitcnt_r <= fetch_waitcnt_r - 1;

    if (e2c_waitcnt_val_r) exe_waitcnt_r <= e2c_waitcnt_r;
    else if (gsu_clock_en & |exe_waitcnt_r) exe_waitcnt_r <= exe_waitcnt_r - 1;
    
    step_r <= (~CONFIG_STEP_ENABLED | (stepcnt_r != CONFIG_STEP_COUNT));    
    if (pipeline_advance) stepcnt_r <= CONFIG_STEP_COUNT;
    waitcnt_zero_r <= ~|fetch_waitcnt_r & ~|exe_waitcnt_r;
  end
end

//-------------------------------------------------------------------
// MEMORY READ PIPELINE
//-------------------------------------------------------------------
parameter
  ST_FILL_IDLE      = 8'b00000001,
  ST_FILL_FETCH_RD  = 8'b00000010,
  ST_FILL_DATA_RD   = 8'b00000100,
  ST_FILL_DATA_WR   = 8'b00001000,
  ST_FILL_FETCH_END = 8'b00010000,
  ST_FILL_DATA_END  = 8'b00100000
  ;
reg [7:0] FILL_STATE; initial FILL_STATE = ST_FILL_IDLE;
reg rom_bus_rrq_r; initial rom_bus_rrq_r = 0;
reg rom_bus_wrq_r; initial rom_bus_wrq_r = 0;
reg [23:0] rom_bus_addr_r;
reg [15:0] rom_bus_data_r;
reg        rom_bus_word_r;
//reg [3:0] rom_waitcnt_r;

// The ROM/RAM should be dedicated to the GSU whenever it wants to do a fetch
always @(posedge CLK) begin
  if (RST) begin
    FILL_STATE <= ST_FILL_IDLE;
    
    gsu_rom_rd_r <= 0; // FIXME:
    //gsu_ram_wr_r <= 0; // FIXME:

    ROMRDBUF_r <= 0;
    RAMWRBUF_r <= 0;
    RAMADDR_r  <= 0;
  end
  else begin
    case (FILL_STATE)
      ST_FILL_IDLE: begin
        // TODO: determine if the cache can make demand fetches
        if (gsu_rom_rd_r & SCMR_RON) begin
          rom_bus_rrq_r <= 1;
          rom_bus_addr_r <= 0; // TODO: get correct cache address for demand fetch
          FILL_STATE <= ST_FILL_DATA_RD;
        end
        else if (gsu_ram_rd_r & SCMR_RAN) begin
          rom_bus_rrq_r <= 1;
          rom_bus_word_r <= gsu_ram_word_r;
          rom_bus_addr_r <= data_rom_addr_r; // TODO: get correct cache address for demand fetch
          RAMADDR_r <= data_rom_addr_r[15:0];
          FILL_STATE <= ST_FILL_DATA_RD;
        end
        else if (gsu_ram_wr_r & SCMR_RAN) begin
          rom_bus_wrq_r <= 1;
          rom_bus_word_r <= gsu_ram_word_r;
          rom_bus_addr_r <= data_rom_addr_r; // TODO: get correct cache address for demand fetch
          RAMADDR_r <= data_rom_addr_r[15:0];
          //rom_bus_data_r <= gsu_ram_data_r; // TODO: data to write
          RAMWRBUF_r <= gsu_ram_data_r;
          FILL_STATE <= ST_FILL_DATA_WR;
        end
        else if (cache_rom_rd_r & SCMR_RON) begin
          rom_bus_rrq_r <= 1;
          rom_bus_addr_r <= cache_rom_addr_r;
          rom_bus_word_r <= cache_rom_word_r;
          FILL_STATE <= ST_FILL_FETCH_RD;
        end
      end
      ST_FILL_FETCH_RD,
      ST_FILL_DATA_RD,
      ST_FILL_DATA_WR: begin
        rom_bus_rrq_r <= 0;
        rom_bus_wrq_r <= 0;
        
        if (~(rom_bus_rrq_r | rom_bus_wrq_r) & ROM_BUS_RDY) begin
          rom_bus_data_r <= ROM_BUS_RDDATA;
          FILL_STATE <= (|(FILL_STATE & ST_FILL_FETCH_RD)) ? ST_FILL_FETCH_END : ST_FILL_DATA_END;
        end
      end
      ST_FILL_FETCH_END,
      ST_FILL_DATA_END: begin
        FILL_STATE <= ST_FILL_IDLE;
      end
    endcase
  end
end

assign ROM_BUS_RRQ = rom_bus_rrq_r;
assign ROM_BUS_WRQ = rom_bus_wrq_r;
assign ROM_BUS_WORD = rom_bus_word_r;
assign ROM_BUS_ADDR = rom_bus_addr_r;
assign ROM_BUS_WRDATA = RAMWRBUF_r;

//-------------------------------------------------------------------
// FETCH PIPELINE
//-------------------------------------------------------------------
// The frontend of the pipeline starts with the fetch operation which
// is pipelined relative to execute and operates a clock ahead.

// The cache holds instructions to execute and is accesible by the GSU
// using a PC of 0-$1FF.  It is true dual port to support debug reads
// and writes.

// The fetch pipeline is composed primarily of the cache lookup state machine
// which can access the cache once per GSU clock.  It synchronizes with the
// 4x FPGA clock and the execution pipeline.  It does this 
// - Cache hit
// - ROM fill (into cache if offset)
parameter
  ST_FETCH_IDLE   = 8'b00000001,
  ST_FETCH_LOOKUP = 8'b00000010,
  ST_FETCH_HIT    = 8'b00000100,
  ST_FETCH_FILL   = 8'b00001000,
  ST_FETCH_WAIT   = 8'b00010000
  ;
reg [7:0] FETCH_STATE; initial FETCH_STATE = ST_FETCH_IDLE;

// Fetch operations
// - Check if cache hit (use valid bits) or !cache address
// - if miss or no allocate then load miss pipeline
// - read data out of cache or from fill
// - wait for cycles to expire and edge

reg [7:0] fetch_data_r;

// Need to check if we are within 512B of the address
wire[15:0] cache_offset = REG_r[R15][15:0] - CBR_r;
wire       cache_hit = (~|cache_offset[15:9] & cache_val_r[cache_offset[12:4]]);

assign     i2c_setcnt = cache_hit & |(FETCH_STATE & ST_FETCH_LOOKUP);

always @(posedge CLK) begin
  if (RST) begin
    FETCH_STATE <= ST_FETCH_IDLE;

    i2e_op_r[0] <= OP_NOP;
    i2e_ptr_r <= 0;
    
    i2c_waitcnt_val_r <= 0;
    cache_rom_rd_r <= 0;
  end
  else begin
    case (FETCH_STATE)
      ST_FETCH_IDLE: begin
        // align to GSU clock
        if (SFR_GO & gsu_clock_en) begin
          FETCH_STATE <= ST_FETCH_LOOKUP;
        end
      end
      ST_FETCH_LOOKUP: begin
        // check if cache hit
        if (cache_hit) begin
          i2c_waitcnt_val_r <= 1;
          i2c_waitcnt_r <= 0;
          cache_gsu_addr_r <= REG_r[R15][8:0];
          FETCH_STATE <= ST_FETCH_HIT;
        end
        else begin
          // TODO: fill address
          i2c_waitcnt_val_r <= 1;
          i2c_waitcnt_r <= 4; // TODO: account for slow clock.
          
          cache_rom_rd_r <= 1;
          cache_rom_word_r <= 1;

          cache_rom_addr_r <= (PBR_r < 8'h60) ? ((PBR_r[6] ? {PBR_r,REG_r[R15]} : {PBR_r[4:0],REG_r[R15][14:0]}) & ROM_MASK)
                                              : 24'hE00000 + ({PBR_r[4:0],REG_r[R15]} & SAVERAM_MASK);
          
          FETCH_STATE <= ST_FETCH_FILL;
        end
      end
      ST_FETCH_HIT: begin
        i2c_waitcnt_val_r <= 0;
        fetch_data_r <= cache_rddata;
        FETCH_STATE <= ST_FETCH_WAIT;
      end
      ST_FETCH_FILL: begin
        // TODO: get correct data from ROM
        i2c_waitcnt_val_r <= 0;
        
        if (|(FILL_STATE & ST_FILL_FETCH_END)) begin
          cache_rom_rd_r <= 0;
          fetch_data_r <= rom_bus_data_r;
          FETCH_STATE <= ST_FETCH_WAIT;
        end
      end
      ST_FETCH_WAIT: begin
        if (pipeline_advance) begin
          // TODO: fetch address increment
          i2e_op_r[~i2e_ptr_r] <= fetch_data_r;
          i2e_ptr_r <= ~i2e_ptr_r;

          if (SFR_GO) FETCH_STATE <= ST_FETCH_LOOKUP;
          else        FETCH_STATE <= ST_FETCH_IDLE;
        end
      end
    endcase
  end
end

//-------------------------------------------------------------------
// EXECUTION PIPELINE
//-------------------------------------------------------------------
parameter
  ST_EXE_IDLE        = 8'b00000001,
  
  ST_EXE_DECODE      = 8'b00000010,
  ST_EXE_REGREAD     = 8'b00000100,
  ST_EXE_EXECUTE     = 8'b00001000,
  ST_EXE_MEMORY      = 8'b00010000,
  ST_EXE_MEMORY_WAIT = 8'b00100000,
  ST_EXE_WAIT        = 8'b01000000
  ;
reg [7:0]  EXE_STATE; initial EXE_STATE = ST_EXE_IDLE;

reg        exe_branch_r;

reg [7:0]  exe_opcode_r;
reg [15:0] exe_operand_r;
reg [1:0]  exe_opsize_r;
reg [15:0] exe_src_r;
reg [15:0] exe_dst_r;
reg [15:0] exe_srcn_r;
reg        exe_alt1_r;
reg        exe_alt2_r;
reg        exe_cy_r;
reg [15:0] exe_mult_srca_r;
reg [15:0] exe_mult_srcb_r;
reg        exe_mult_r;

reg [15:0] exe_n;
reg [15:0] exe_result;
reg        exe_carry;

wire [31:0] exe_fmult_out;
wire [15:0] exe_mult_out;
wire [15:0] exe_umult_out;

reg [7:0]  exe_byte_r;

always @(posedge CLK) begin
  if (RST) begin
    EXE_STATE <= ST_EXE_IDLE;
    
    e2r_alt_r  <= 0;
    e2r_sreg_r <= 0;
    e2r_dreg_r <= 0;
    e2r_z_r    <= 0;
    e2r_cy_r   <= 0;
    e2r_s_r    <= 0;
    e2r_ov_r   <= 0;
    e2r_b_r    <= 0;
    e2r_g_r    <= 0;
    e2r_irq_r  <= 0;

    e2r_val_r <= 0;
    e2r_mask_r <= 0;
    e2r_loop_r <= 0;
    e2r_ljmp_r <= 0;
    e2r_wpor_r <= 0;
    e2r_wcolr_r <= 0;
    
    exe_opcode_r <= OP_NOP;
    exe_byte_r <= 0;
    exe_opsize_r <= 0;
    exe_operand_r <= 0;
    
    data_rom_addr_r <= 0;

    e2c_waitcnt_val_r <= 0;
    gsu_ram_rd_r <= 0;
    gsu_ram_wr_r <= 0;
  end
  else begin
    case (EXE_STATE)
      ST_EXE_IDLE: begin
        // align to GSU clock.  Sinks up with fetch.
        if (SFR_GO & gsu_clock_en) begin
          EXE_STATE <= ST_EXE_DECODE;
        end
        
        // handle snes writes
        e2r_val_r  <= SNES_WR_end & enable_r & addr_in_r[0] & ~|addr_in_r[9:5];
        e2r_data_r <= {data_in_r,data_flop_r};
        e2r_r15_r  <= {data_in_r,data_flop_r};
        e2r_mask_r <= 0;
        e2r_destnum_r <= addr_in_r[4:1];
      end
      ST_EXE_DECODE: begin
        if (~|exe_opsize_r) begin
        
          // calculate operands
          casex (exe_opcode_r)
            OP_BRA,
            OP_BGE,
            OP_BLT,
            OP_BNE,
            OP_BEQ,
            OP_BPL,
            OP_BMI,
            OP_BCC,
            OP_BCS,
            OP_BVC,
            OP_BVS : exe_opsize_r <= 2;
           
            OP_IBT : exe_opsize_r <= 2;
            OP_IWT : exe_opsize_r <= 3;
            default: exe_opsize_r <= 1;
          endcase

          // handle prefixes
          casex (exe_opcode_r)
            OP_BRA           : exe_branch_r <= 1;
            OP_BGE           : exe_branch_r <= ( SFR_S == SFR_OV);
            OP_BLT           : exe_branch_r <= ( SFR_S != SFR_OV);
            OP_BNE           : exe_branch_r <= (~SFR_Z);   
            OP_BEQ           : exe_branch_r <= ( SFR_Z);
            OP_BPL           : exe_branch_r <= (~SFR_S);
            OP_BMI           : exe_branch_r <= ( SFR_S);
            OP_BCC           : exe_branch_r <= (~SFR_CY);
            OP_BCS           : exe_branch_r <= ( SFR_CY);
            OP_BVC           : exe_branch_r <= (~SFR_OV);
            OP_BVS           : exe_branch_r <= ( SFR_OV);
            
            OP_ALT1          : begin e2r_alt_r <= 1; e2r_b_r <= 0; end
            OP_ALT2          : begin e2r_alt_r <= 2; e2r_b_r <= 0; end
            OP_ALT3          : begin e2r_alt_r <= 3; e2r_b_r <= 0; end
            OP_TO            : if (~SFR_B) e2r_dreg_r <= exe_opcode_r[3:0];
            OP_WITH          : begin e2r_sreg_r <= exe_opcode_r[3:0]; e2r_dreg_r <= exe_opcode_r[3:0]; e2r_b_r <= 1; end
            OP_FROM          : if (~SFR_B) e2r_sreg_r <= exe_opcode_r[3:0];
            
            default          : begin e2r_alt_r <= 0; e2r_sreg_r <= 0; e2r_dreg_r <= 0; e2r_b_r <= SFR_B; end
          endcase
        end
        else begin
          exe_operand_r <= {exe_operand_r[7:0],exe_byte_r};
        end
        
        // get previous values for defaults
        e2r_z_r    <= SFR_Z;
        e2r_cy_r   <= SFR_CY;
        e2r_s_r    <= SFR_S;
        e2r_ov_r   <= SFR_OV;
        //e2r_b_r    <= SFR_B;
        e2r_g_r    <= SFR_GO;
        e2r_irq_r  <= SFR_IRQ;
        
        // get default destination
        e2r_destnum_r <= DREG_r;
        
        exe_alt1_r <= SFR_ALT1;
        exe_alt2_r <= SFR_ALT2;
        exe_cy_r   <= SFR_CY;
        // get register sources
        exe_src_r <= REG_r[SREG_r];
        //exe_dst_r <= REG_r[DREG_r];
        exe_srcn_r <= REG_r[exe_opcode_r[3:0]];
        
        EXE_STATE <= ST_EXE_EXECUTE;
      end
      ST_EXE_EXECUTE: begin
        if (op_complete) begin
          if (exe_branch_r) begin
            // calculate branch target
            e2r_val_r <= 1;
            e2r_destnum_r <= R15;
            e2r_r15_r <= REG_r[R15] + {{8{exe_operand_r[7]}},exe_operand_r[7:0]};
            
            exe_branch_r <= 0;
          end
          else begin
            casex (exe_opcode_r)
              OP_STOP           : begin
                // TODO: deal with interrupts and other stuff here
                e2r_g_r <= 0;
                e2r_irq_r <= 1;
              end
              //OP_NOP            : begin end
              OP_CACHE          : begin
                if (REG_r[R15][15:4] != CBR_r[15:4]) begin
                  CBR_r[15:4] <= REG_r[R15][15:4];
                  cache_val_r <= 0;
                end
              end

              OP_TO             : begin
                if (SFR_B) begin
                  e2r_val_r  <= 1;
                  e2r_destnum_r <= exe_opcode_r[3:0]; // uses N as destination
                  e2r_data_r <= exe_src_r;                  
                end
              end
              OP_WITH           : begin end
              OP_FROM           : begin
                if (SFR_B) begin
                  exe_result = exe_srcn_r; // uses N as source
                
                  e2r_val_r  <= 1;
                  e2r_data_r <= exe_result;

                  e2r_z_r    <= ~|exe_result;
                  e2r_ov_r   <= exe_result[7];
                  e2r_s_r    <= exe_result[15];
                end
              end
              
              OP_LOOP           : begin
                exe_result = REG_r[R12] - 1;
                
                e2r_val_r  <= 1;
                e2r_destnum_r <= R12;
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_s_r    <= exe_result[15];
                
                e2r_loop_r <= 1;                
              end

              OP_CMODE_COLOR    : begin
                if (exe_alt1_r) begin
                  e2r_wpor_r <= 1;
                  e2r_por_r  <= {3'h0,exe_src_r[4:0]};
                end
                else begin
                  e2r_wcolr_r <= 1;
                  e2r_colr_r  <= POR_HN ? {COLR_r[7:4],exe_src_r[7:4]} : POR_FHN ? {COLR_r[7:4],exe_src_r[3:0]} : exe_src_r[7:0];
                end
              end
              OP_PLOT_RPIX      : begin end

              // ALU
              OP_ADD           : begin 
                exe_n      = exe_alt2_r ? {12'h000, exe_opcode_r[3:0]} : exe_srcn_r;
                {exe_carry,exe_result} = exe_src_r + exe_n + (exe_alt1_r & exe_cy_r);
                
                e2r_val_r <= 1;
                // e2r_destnum_r <= DREG_r; // standard dest
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_ov_r   <= (exe_src_r[15] ^ exe_result[15]) & (exe_n[15] ^ exe_result[15]);
                e2r_s_r    <= exe_result[15];
                e2r_cy_r   <= exe_carry;
              end
              OP_SUB           : begin
                exe_n      = (~exe_alt1_r & exe_alt2_r) ? {12'h000, exe_opcode_r[3:0]} : exe_srcn_r;
                {exe_carry,exe_result} = exe_src_r - exe_n - (exe_alt1_r & ~exe_alt2_r & ~exe_cy_r);
                
                // CMP doesn't output the result
                e2r_val_r <= ~(exe_alt1_r & exe_alt2_r);
                // e2r_destnum_r <= DREG_r; // standard dest
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_ov_r   <= (exe_src_r[15] ^ exe_result[15]) & (exe_src_r[15] ^ exe_n[15]);
                e2r_s_r    <= exe_result[15];
                e2r_cy_r   <= ~exe_carry;
              end
              //OP_AND_BIC       : begin
              8'h71, 8'h72, 8'h73, 8'h74, 8'h75, 8'h76, 8'h77, 8'h78, 8'h79, 8'h7A, 8'h7B, 8'h7C, 8'h7D, 8'h7E, 8'h7F : begin 
                exe_n      = exe_alt2_r ? {12'h000, exe_opcode_r[3:0]} : exe_srcn_r;
                exe_result = exe_src_r & exe_n;
                
                e2r_val_r  <= 1;
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_s_r    <= exe_result[15];
              end
              //OP_OR_XOR        : begin
              8'hC1, 8'hC2, 8'hC3, 8'hC4, 8'hC5, 8'hC6, 8'hC7, 8'hC8, 8'hC9, 8'hCA, 8'hCB, 8'hCC, 8'hCD, 8'hCE, 8'hCF : begin 
                exe_n      = exe_alt2_r ? {12'h000, exe_opcode_r[3:0]} : exe_srcn_r;
                exe_result = exe_alt1_r ? exe_src_r ^ exe_n : exe_src_r | exe_n;
                
                e2r_val_r  <= 1;
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_s_r    <= exe_result[15];                
              end
              OP_NOT           : begin
                exe_result = ~exe_src_r;
                
                e2r_val_r  <= 1;
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_s_r    <= exe_result[15];
              end
              
              // ROTATE/SHIFT/INC/DEC
              OP_LSR           : begin
                exe_result = {1'b0,exe_src_r[15:1]};
                
                e2r_val_r  <= 1;
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_s_r    <= exe_result[15];
                e2r_cy_r   <= exe_src_r[0];
              end
              OP_ASR_DIV2      : begin
                exe_result = {exe_src_r[15],exe_src_r[15:1]};
                
                e2r_val_r  <= 1;
                e2r_data_r <= (exe_alt1_r & (&exe_src_r))? 0 : exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_s_r    <= exe_result[15];
                e2r_cy_r   <= exe_result[0]; // unique to look at result for ASR/DIV2
              end
              OP_ROL           : begin
                exe_result = {exe_src_r[14:0],exe_cy_r};
                
                e2r_val_r  <= 1;
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_s_r    <= exe_result[15];
                e2r_cy_r   <= exe_src_r[15];
              end
              OP_ROR           : begin
                exe_result = {exe_cy_r,exe_src_r[15:1]};
                
                e2r_val_r  <= 1;
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_s_r    <= exe_result[15];
                e2r_cy_r   <= exe_src_r[0];
              end
              
              // BYTE
              OP_SWAP          : begin
                exe_result = {exe_src_r[7:0],exe_src_r[15:8]};
                
                e2r_val_r  <= 1;
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_s_r    <= exe_result[15];
              end
              OP_SEX           : begin
                exe_result = {{8{exe_src_r[7]}},exe_src_r[7:0]};
                
                e2r_val_r  <= 1;
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_s_r    <= exe_result[15];
              end
              OP_LOB           : begin
                exe_result = {8'h00,exe_src_r[7:0]};
                
                e2r_val_r  <= 1;
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_s_r    <= exe_result[7];
              end
              OP_HIB           : begin
                exe_result = {8'h00,exe_src_r[15:8]};
                
                e2r_val_r  <= 1;
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_s_r    <= exe_result[7];
              end
              OP_MERGE         : begin
                exe_result = {REG_r[R7][15:8],REG_r[R8][15:8]};
                
                e2r_val_r  <= 1;
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= exe_result & 16'hF0F0;
                e2r_ov_r   <= exe_result & 16'hC0C0;
                e2r_s_r    <= exe_result & 16'h8080;
                e2r_cy_r   <= exe_result & 16'hE0E0;
              end
              
              // MULTIPLY
              OP_FMULT_LMULT   : begin
                exe_mult_r      <= 1;
                exe_mult_srca_r <= exe_src_r;
                exe_mult_srcb_r <= REG_r[R6];
              end
              OP_MULT_UMULT    : begin
                exe_mult_r      <= 1;
                exe_mult_srca_r <= exe_src_r;
                exe_mult_srcb_r <= exe_alt2_r ? {12'h000, exe_opcode_r[3:0]} : exe_srcn_r;
              end
              
              OP_GETC_RAMB_ROMB: begin
                if      (exe_alt1_r & exe_alt2_r)   ROMBR_r    <= exe_src_r;
                else if (exe_alt2_r)                RAMBR_r[0] <= exe_src_r[0];
              end
              //OP_INC           : begin
              8'hD0, 8'hD1, 8'hD2, 8'hD3, 8'hD4, 8'hD5, 8'hD6, 8'hD7, 8'hD8, 8'hD9, 8'hDA, 8'hDB, 8'hDC, 8'hDD, 8'hDE: begin
                exe_result = exe_srcn_r + 1;
                
                e2r_val_r  <= 1;
                e2r_destnum_r <= exe_opcode_r[3:0]; // uses N as destination                  
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_s_r    <= exe_result[15];
              end
              //OP_DEC           : begin
              8'hE0, 8'hE1, 8'hE2, 8'hE3, 8'hE4, 8'hE5, 8'hE6, 8'hE7, 8'hE8, 8'hE9, 8'hEA, 8'hEB, 8'hEC, 8'hED, 8'hEE: begin
                exe_result = exe_srcn_r - 1;
                
                e2r_val_r  <= 1;
                e2r_destnum_r <= exe_opcode_r[3:0]; // uses N as destination
                e2r_data_r <= exe_result;
                
                e2r_z_r    <= ~|exe_result;
                e2r_s_r    <= exe_result[15];
              end
              
            endcase
          end
        end

        EXE_STATE <= ST_EXE_MEMORY;
      end
      ST_EXE_MEMORY: begin
        if (op_complete) begin
          casex (exe_opcode_r)
            OP_GETC_RAMB_ROMB: begin
              if (~exe_alt1_r & ~exe_alt2_r) begin
                //e2r_val_r    <= 1;
                e2r_wcolr_r <= 1;

                e2c_waitcnt_val_r <= 1;
                // TODO: add 16b cache latencies
                e2c_waitcnt_r <= 6-1; // TODO: account for slow clock.

                // TODO: decide if we need separate state machines for this
                gsu_ram_rd_r <= 1;
                gsu_ram_word_r <= 1; // load for cache

                data_rom_addr_r <= ((ROMBR_r[6] ? {ROMBR_r,REG_r[R14]} : {ROMBR_r[4:0],REG_r[R14][14:0]}) & ROM_MASK);

                EXE_STATE <= ST_EXE_MEMORY_WAIT;
              end
              else EXE_STATE <= ST_EXE_WAIT;
            end
            OP_FMULT_LMULT   : begin
              e2r_val_r      <= 1;
              
              e2r_data_r     <= exe_fmult_out[31:16];
              e2r_r4_r       <= exe_fmult_out[15:0];
              
              e2r_z_r        <= ~|exe_fmult_out[31:16];
              e2r_s_r        <= exe_fmult_out[31];
              e2r_cy_r       <= exe_fmult_out[15];
              
              e2c_waitcnt_val_r <= 1;
              e2c_waitcnt_r     <= 8-1; // TODO: account for slow clock and multiplier.
              // TODO: figure out how to write to R4.  Have plenty of cycles to do it.
              
              EXE_STATE <= ST_EXE_WAIT;
            end
            OP_MULT_UMULT    : begin
              exe_result = exe_alt1_r ? exe_umult_out : exe_mult_out;
            
              e2r_val_r      <= 1;
              
              e2r_data_r     <= exe_result;
              
              e2r_z_r        <= ~|exe_result;
              e2r_s_r        <= exe_result[15];
              
              e2c_waitcnt_val_r <= 1;
              e2c_waitcnt_r     <= 2-1; // TODO: account for slow clock and multiplier.
              
              EXE_STATE <= ST_EXE_WAIT;
            end
          
            OP_IBT           : begin
              if (exe_alt1_r) begin
                // LMS Rn, (2*imm8)
                //exe_memory = 1;
                e2r_val_r    <= 1;
                e2r_destnum_r   <= exe_opcode_r[3:0];
                 
                e2c_waitcnt_val_r <= 1;
                e2c_waitcnt_r <= 7-1; // TODO: account for slow clock.
          
                gsu_ram_rd_r <= 1;
                gsu_ram_word_r <= 1;

                data_rom_addr_r <= {4'hE,3'h0,RAMBR_r[0],7'h00,exe_operand_r[7:0],1'b0};
                EXE_STATE <= ST_EXE_MEMORY_WAIT;
              end
              else if (exe_alt2_r) begin
                // SMS (2*imm8), Rn                
                e2c_waitcnt_val_r <= 1;
                e2c_waitcnt_r <= 7-1; // TODO: account for slow clock.
          
                // TODO: this really does a byte at a time.
                // TODO: do we need to handle misaligned data in a special way?
                gsu_ram_wr_r <= 1;
                gsu_ram_word_r <= 1;
                gsu_ram_data_r <= exe_srcn_r;

                data_rom_addr_r <= {4'hE,3'h0,RAMBR_r[0],7'h00,exe_operand_r[7:0],1'b0};
                EXE_STATE <= ST_EXE_MEMORY_WAIT;
              end
              else begin
                e2r_val_r    <= 1;
                e2r_destnum_r   <= exe_opcode_r[3:0];
                e2r_data_r   <= {{8{exe_operand_r[7]}},exe_operand_r[7:0]};
                EXE_STATE <= ST_EXE_WAIT;
              end
            end
            OP_IWT           : begin
              if (exe_alt1_r) begin
                // LM Rn, (imm)
                e2r_val_r    <= 1;
                e2r_destnum_r   <= exe_opcode_r[3:0];

                e2c_waitcnt_val_r <= 1;
                e2c_waitcnt_r <= 7-1; // TODO: account for slow clock.
          
                gsu_ram_rd_r <= 1;
                gsu_ram_word_r <= 1;

                data_rom_addr_r <= {4'hE,3'h0,RAMBR_r[0],exe_operand_r};
                EXE_STATE <= ST_EXE_MEMORY_WAIT;
              end
              else if (exe_alt2_r) begin
                // SM (imm), Rn
                e2c_waitcnt_val_r <= 1;
                e2c_waitcnt_r <= 7-1; // TODO: account for slow clock.
          
                // TODO: this really does a byte at a time.
                // TODO: do we need to handle misaligned data in a special way?
                gsu_ram_wr_r <= 1;
                gsu_ram_word_r <= 1;
                gsu_ram_data_r <= exe_srcn_r;

                data_rom_addr_r <= {4'hE,3'h0,RAMBR_r[0],exe_operand_r};
                EXE_STATE <= ST_EXE_MEMORY_WAIT;
              end
              else begin
                e2r_val_r    <= 1;
                e2r_destnum_r   <= exe_opcode_r[3:0];
                e2r_data_r   <= exe_operand_r;
                EXE_STATE <= ST_EXE_WAIT;
              end
            end
            OP_GETB          : begin
              e2r_val_r    <= 1;

              e2c_waitcnt_val_r <= 1;
              // TODO: add 16b cache latencies
              e2c_waitcnt_r <= 6-1; // TODO: account for slow clock.

              // TODO: decide if we need separate state machines for this
              gsu_ram_rd_r <= 1;
              gsu_ram_word_r <= 1; // load for cache

              data_rom_addr_r <= ((ROMBR_r[6] ? {ROMBR_r,REG_r[R14]} : {ROMBR_r[4:0],REG_r[R14][14:0]}) & ROM_MASK);

              EXE_STATE <= ST_EXE_MEMORY_WAIT;
              //EXE_STATE <= ST_EXE_WAIT;
            end
            OP_SBK           : begin
              e2c_waitcnt_val_r <= 1;
              e2c_waitcnt_r <= 7-1; // TODO: account for slow clock.
          
              // TODO: this really does a byte at a time.
              // TODO: do we need to handle misaligned data in a special way?
              gsu_ram_wr_r <= 1;
              gsu_ram_word_r <= 1;
              gsu_ram_data_r <= exe_src_r;

              data_rom_addr_r <= {8'hE0,RAMADDR_r};
              EXE_STATE <= ST_EXE_MEMORY_WAIT;
            end
            //OP_LD            : begin
            8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47, 8'h48, 8'h49, 8'h4A, 8'h4B: begin
              e2r_val_r    <= 1;
                 
              e2c_waitcnt_val_r <= 1;
              e2c_waitcnt_r <= exe_alt1_r ? 4-1 : 6-1; // TODO: account for slow clock.

              gsu_ram_rd_r <= 1;
              gsu_ram_word_r <= ~exe_alt1_r;

              data_rom_addr_r <= {4'hE,3'h0,RAMBR_r[0],exe_srcn_r};

              EXE_STATE <= ST_EXE_MEMORY_WAIT;
              //EXE_STATE <= ST_EXE_WAIT;
            end
            //OP_ST            : begin
            8'h30, 8'h31, 8'h32, 8'h33, 8'h34, 8'h35, 8'h36, 8'h37, 8'h38, 8'h39, 8'h3A, 8'h3B: begin
              e2c_waitcnt_val_r <= 1;
              e2c_waitcnt_r <= exe_alt1_r ? 4-1 : 6-1; // TODO: account for slow clock.

              gsu_ram_wr_r <= 1;
              gsu_ram_word_r <= ~exe_alt1_r;
              gsu_ram_data_r <= exe_src_r;

              data_rom_addr_r <= {4'hE,3'h0,RAMBR_r[0],exe_srcn_r};

              EXE_STATE <= ST_EXE_MEMORY_WAIT;
              //EXE_STATE <= ST_EXE_WAIT;
            end
            // LINK
            8'h91, 8'h92, 8'h93, 8'h94: begin
              exe_result = REG_r[R15] + exe_opcode_r[3:0];
                
              e2r_val_r  <= 1;
              e2r_destnum_r <= R11;
              e2r_data_r <= exe_result;
              
              EXE_STATE <= ST_EXE_WAIT;
            end
            // JMP/LJMP
            8'h98, 8'h99, 8'h9A, 8'h9B, 8'h9C, 8'h9D: begin
              e2r_val_r <= 1;
              e2r_destnum_r <= R15;

              if (exe_alt1_r) begin
                // LJMP
                e2r_r15_r   <= exe_src_r;
                e2r_ljmp_r  <= 1; // write PBR with srcn
                e2r_pbr_r   <= exe_srcn_r;
                CBR_r[15:4] <= exe_src_r[15:4];
                cache_val_r <= 0;
              end
              else begin
                // JMP
                e2r_r15_r   <= exe_srcn_r;
              end
            end
            default: EXE_STATE <= ST_EXE_WAIT;
          endcase
        end
        else EXE_STATE <= ST_EXE_WAIT;
      end
      ST_EXE_MEMORY_WAIT: begin
        e2c_waitcnt_val_r <= 0;
        
        if (|(FILL_STATE & ST_FILL_DATA_END)) begin
          gsu_ram_rd_r <= 0;
          gsu_ram_wr_r <= 0;
          // byte loads do zero extension
          if (exe_opcode_r == OP_GETB) begin
            e2r_data_r <= (exe_alt1_r & exe_alt2_r) ? {{8{rom_bus_data_r[7]}},rom_bus_data_r[7:0]} : exe_alt2_r ? {8'h00,rom_bus_data_r[7:0]} : exe_alt1_r ? {rom_bus_data_r[7:0],8'h00} : {8'h00,rom_bus_data_r[7:0]};
            e2r_mask_r <= {(~exe_alt1_r & exe_alt2_r),(exe_alt1_r & ~exe_alt2_r)};
          end
          else if (exe_opcode_r == OP_GETC_RAMB_ROMB) begin
            if (~exe_alt1_r & ~exe_alt2_r) begin
              e2r_colr_r  <= POR_HN ? {COLR_r[7:4],rom_bus_data_r[7:4]} : POR_FHN ? {COLR_r[7:4],rom_bus_data_r[3:0]} : rom_bus_data_r[7:0];
            end
          end
          else begin
            e2r_data_r <= {(gsu_ram_word_r ? rom_bus_data_r[15:8] : 8'h00),rom_bus_data_r[7:0]};
          end
            
          EXE_STATE <= ST_EXE_WAIT;
        end
      end
      ST_EXE_WAIT: begin
        if (pipeline_advance) begin
          if (|exe_opsize_r) exe_opsize_r <= exe_opsize_r - 1;
        
          if (SFR_GO) EXE_STATE <= ST_EXE_DECODE;
          else        EXE_STATE <= ST_EXE_IDLE;
                    
          if (op_complete) begin
            // get next instruction byte
            exe_opcode_r <= fetch_data_r;//i2e_op_r[~i2e_ptr_r];
            exe_operand_r <= 0;

            e2r_val_r  <= 0;
            e2r_mask_r <= 0;
            e2r_loop_r <= 0;
            e2r_ljmp_r <= 0;
            exe_mult_r <= 0;
            e2r_wpor_r <= 0;
            e2r_wcolr_r <= 0;
          end
          
          exe_byte_r <= fetch_data_r;
        end
      end
      
    endcase
  end
end

//assign pipeline_advance = gsu_clock_en & ~|fetch_waitcnt_r & ~|exe_waitcnt_r & |(EXE_STATE & ST_EXE_WAIT) & |(FETCH_STATE & ST_FETCH_WAIT) & (~CONFIG_STEP_ENABLED | (stepcnt_r != CONFIG_STEP_COUNT));
//assign pipeline_advance = gsu_clock_en & waitcnt_zero_r & |(EXE_STATE & ST_EXE_WAIT) & |(FETCH_STATE & ST_FETCH_WAIT) & (~CONFIG_STEP_ENABLED | (stepcnt_r != CONFIG_STEP_COUNT));
assign pipeline_advance = gsu_clock_en & waitcnt_zero_r & |(EXE_STATE & ST_EXE_WAIT) & |(FETCH_STATE & ST_FETCH_WAIT) & step_r;
assign op_complete = exe_opsize_r == 1;

// Multipliers
gsu_fmult gsu_fmult(
  .clk(CLK),
  .a(exe_mult_srca_r[15:0]),
  .b(exe_mult_srcb_r[15:0]),
  .p(exe_fmult_out)
);

gsu_mult gsu_mult(
  .clk(CLK),
  .a(exe_mult_srca_r[7:0]),
  .b(exe_mult_srcb_r[7:0]),
  .p(exe_mult_out)
);

gsu_umult gsu_umult(
  .clk(CLK),
  .a(exe_mult_srca_r[7:0]),
  .b(exe_mult_srcb_r[7:0]),
  .p(exe_umult_out)
);

//-------------------------------------------------------------------
// DEBUG OUTPUT
//-------------------------------------------------------------------
reg [7:0]  pgmdata_out; //initial pgmdata_out_r = 0;
//reg [15:0] debug_reg_r;
//
//always @(CLK) begin
//  debug_reg_r <= REG_r[PGM_ADDR[4:1]];
//end

// TODO: also map other non-visible state
//always @(REG_r[0], REG_r[1], REG_r[2], REG_r[3], REG_r[4], REG_r[5], REG_r[6], REG_r[7],
//         REG_r[8], REG_r[9], REG_r[10], REG_r[11], REG_r[12], REG_r[13], REG_r[14], REG_r[15],
//         SFR_r, BRAMR_r, PBR_r, ROMBR_r, CFGR_r, SCBR_r, CLSR_r, SCMR_r, VCR_r, RAMBR_r, CBR_r, RAMADDR_r,
//         config_r[0], config_r[1],
//         FETCH_STATE, EXE_STATE, FILL_STATE,
//         i2e_op_r[0], i2e_op_r[1],
//         debug_cache_rddata
//        ) begin
always @(posedge CLK) begin
  casex (pgm_addr_r)
    {2'h0,ADDR_GPRL } : pgmdata_out <= REG_r[pgm_addr_r[4:1]][7:0];
    {2'h0,ADDR_GPRH } : pgmdata_out <= REG_r[pgm_addr_r[4:1]][15:8];          
    //{2'h0,ADDR_GPRL } : pgmdata_out = debug_reg_r[7:0];
    //{2'h0,ADDR_GPRH } : pgmdata_out = debug_reg_r[15:8];          
    {2'h0,ADDR_SFR  } : pgmdata_out <= SFR_r[7:0];
    {2'h0,ADDR_SFR+1} : pgmdata_out <= SFR_r[15:8];
    {2'h0,ADDR_BRAMR} : pgmdata_out <= BRAMR_r;
    {2'h0,ADDR_PBR  } : pgmdata_out <= PBR_r;
    {2'h0,ADDR_ROMBR} : pgmdata_out <= ROMBR_r;
    {2'h0,ADDR_CFGR } : pgmdata_out <= CFGR_r;
    {2'h0,ADDR_SCBR } : pgmdata_out <= SCBR_r;
    {2'h0,ADDR_CLSR } : pgmdata_out <= CLSR_r;
    {2'h0,ADDR_SCMR } : pgmdata_out <= SCMR_r;
    {2'h0,ADDR_VCR  } : pgmdata_out <= VCR_r;
    {2'h0,ADDR_RAMBR} : pgmdata_out <= RAMBR_r;
    {2'h0,ADDR_CBR+0} : pgmdata_out <= CBR_r[7:0];
    {2'h0,ADDR_CBR+1} : pgmdata_out <= CBR_r[15:8];
    10'h40            : pgmdata_out <= COLR_r;
    10'h41            : pgmdata_out <= POR_r;
    10'h42            : pgmdata_out <= SREG_r;
    10'h43            : pgmdata_out <= DREG_r;
    10'h44            : pgmdata_out <= ROMRDBUF_r;
    10'h45            : pgmdata_out <= RAMWRBUF_r;
    10'h46            : pgmdata_out <= RAMADDR_r[7:0];
    10'h47            : pgmdata_out <= RAMADDR_r[15:8];

    // TODO: add more internal temps @ $80
    10'h80            : pgmdata_out <= SFR_Z;
    10'h81            : pgmdata_out <= SFR_CY;
    10'h82            : pgmdata_out <= SFR_S;
    10'h83            : pgmdata_out <= SFR_OV;
    10'h84            : pgmdata_out <= SFR_GO;
    10'h85            : pgmdata_out <= SFR_RR;
    10'h86            : pgmdata_out <= SFR_ALT1;
    10'h87            : pgmdata_out <= SFR_ALT2;
    10'h88            : pgmdata_out <= SFR_IL;
    10'h89            : pgmdata_out <= SFR_IH;
    10'h8A            : pgmdata_out <= SFR_B;
    10'h8B            : pgmdata_out <= SCMR_MD;
    10'h8C            : pgmdata_out <= SCMR_HT;
    10'h8D            : pgmdata_out <= SCMR_RAN;
    10'h8E            : pgmdata_out <= SCMR_RON;
    
    10'h1xx,
    10'h2xx           : pgmdata_out <= debug_cache_rddata;
    
    // fetch state
    10'h300           : pgmdata_out <= FETCH_STATE;
    10'h301           : pgmdata_out <= fetch_waitcnt_r;
    // exe state
    10'h320           : pgmdata_out <= EXE_STATE;
    10'h321           : pgmdata_out <= exe_waitcnt_r;
    10'h322           : pgmdata_out <= exe_opcode_r;
    10'h323           : pgmdata_out <= exe_operand_r[7:0];
    10'h324           : pgmdata_out <= exe_operand_r[15:8];
    10'h325           : pgmdata_out <= exe_opsize_r;
    10'h326           : pgmdata_out <= e2r_destnum_r;

    10'h330           : pgmdata_out <= exe_src_r[7:0];
    10'h331           : pgmdata_out <= exe_src_r[15:8];
    10'h332           : pgmdata_out <= exe_srcn_r[7:0];
    10'h333           : pgmdata_out <= exe_srcn_r[15:8];
    10'h334           : pgmdata_out <= e2r_data_r[7:0];
    10'h335           : pgmdata_out <= e2r_data_r[15:8];

    // cache state
    //10'h340
    // fill state
    10'h360           : pgmdata_out <= ROM_BUS_RDY;
    10'h368           : pgmdata_out <= cache_rom_rd_r;
    10'h370           : pgmdata_out <= gsu_ram_rd_r;
    10'h371           : pgmdata_out <= data_rom_addr_r[7:0];
    10'h372           : pgmdata_out <= data_rom_addr_r[15:8];
    10'h373           : pgmdata_out <= data_rom_addr_r[23:16];
    10'h374           : pgmdata_out <= gsu_ram_data_r[7:0];
    10'h375           : pgmdata_out <= gsu_ram_data_r[15:8];
    10'h376           : pgmdata_out <= rom_bus_data_r[7:0];
    10'h377           : pgmdata_out <= rom_bus_data_r[15:8];
    // interface state
    10'h380           : pgmdata_out <= i2e_op_r[0];
    10'h381           : pgmdata_out <= i2e_op_r[1];
    // config state
    10'h3A0           : pgmdata_out <= config_r[0];
    10'h3A1           : pgmdata_out <= config_r[1];

    10'h3C0           : pgmdata_out <= FILL_STATE;
    
    // misc
    10'h3E0           : pgmdata_out <= gsu_cycle_cnt_r[31:24];
    10'h3E1           : pgmdata_out <= gsu_cycle_cnt_r[23:16];
    10'h3E2           : pgmdata_out <= gsu_cycle_cnt_r[15: 8];
    10'h3E3           : pgmdata_out <= gsu_cycle_cnt_r[ 7: 0];
    10'h3E4           : pgmdata_out <= snes_write_r;
    10'h3E5           : pgmdata_out <= pipeline_advance;
    
    default           : pgmdata_out <= 8'hFF;
  endcase
end

//-------------------------------------------------------------------
// MISC OUTPUTS
//-------------------------------------------------------------------
assign DBG = 0;
assign DATA_ENABLE = data_enable_r;
assign DATA_OUT = data_out_r;

assign PGM_DATA = pgmdata_out;

assign ACTIVE = ~|(FILL_STATE & ST_FILL_IDLE);

endmodule