// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

/* Multiplication & Division Unit */
module mdu_top #(
  parameter integer WIDTH      = 32,
  parameter integer P_DATA_MSB = WIDTH-1
)(
  input                 i_clk,  
  input                 i_rst,
  input  [P_DATA_MSB:0] i_mdu_rs1,
  input  [P_DATA_MSB:0] i_mdu_rs2,
  input  [2:0]          i_mdu_op,
  input                 i_mdu_valid,
  output                o_mdu_ready,
  output [P_DATA_MSB:0] o_mdu_rd
);

  ///////////////////////////////////////////////////////////////////////////////
  // Internal Signals Declarations
  ///////////////////////////////////////////////////////////////////////////////
  // Multiplication Process Signals
  reg                    is_mul_r;
  reg                    is_mulh_r;
  reg  [(2*(WIDTH))-1:0] rd;
  reg                    mul_done;
  // Multiplication Control Signals
  wire mul_en          = is_mul & i_mdu_valid;
  wire is_mul          = !i_mdu_op[2];
  wire unsign_mul      =  i_mdu_op[1]; 
  wire sign_unsign_mul =  i_mdu_op[0]; 
  wire is_mulh         = (|i_mdu_op) & is_mul;
  // Multiplication Inputs Data Muxes 
  wire [WIDTH:0] rdata_a = unsign_mul ? (
                             sign_unsign_mul ? $unsigned(i_mdu_rs1) : 
                                               $signed({i_mdu_rs1[P_DATA_MSB],i_mdu_rs1})
                             ) : 
                             $signed(i_mdu_rs1);
  wire [WIDTH:0] rdata_b = unsign_mul ? $unsigned(i_mdu_rs2) : $signed(i_mdu_rs2);
  // Resulting Product
  wire [P_DATA_MSB:0] mul_rd  = is_mulh ? rd[(2*(WIDTH))-1:WIDTH] : rd[P_DATA_MSB:0];

  // Division Process Signals
  reg [P_DATA_MSB:0]    divisor;
  reg [2*WIDTH:0]       dividend;
  reg                   outsign;
  reg [P_DATA_MSB:0]    div_rd;
  reg                   div_ready;
  reg [$clog2(WIDTH):0] cntr;
  reg div_start;
  // Division Control Signals
  wire is_div         = i_mdu_op[2] & (!i_mdu_op[1]);
  wire is_rem         = i_mdu_op[2] & i_mdu_op[1];
  wire unsign_div_rem = i_mdu_op[0];
  wire cntr_zero      = ~|cntr;
  wire prep           = i_mdu_valid & (is_div | is_rem) & !div_ready & !div_start;	

  wire [P_DATA_MSB:0] quotient       = dividend[P_DATA_MSB:0];
  wire [WIDTH:0]      upper_dividend = dividend[2*WIDTH:WIDTH];
  wire [P_DATA_MSB:0] remainder      = upper_dividend >> 1;
  
  wire [WIDTH:0] sub_result     = upper_dividend - divisor;
  wire           sub_result_neg = sub_result[WIDTH];
  

  ///////////////////////////////////////////////////////////////////////////////
  //            ********      Architecture Declaration      ********           //
  ///////////////////////////////////////////////////////////////////////////////

  /////////////////////////////////////////////////////////////////////////////
  // Process     : Multiplication Process
  // Description : Generic code that modern synthesizers infer as DSP blocks.
  //               and generates an operation done strobe.
  /////////////////////////////////////////////////////////////////////////////
  always @(posedge i_clk) begin : multiplication_proc
    if (!i_rst & mul_en) begin
      rd <= $signed(rdata_a) * $signed(rdata_b);
    end
  end // multiplication_proc

  /////////////////////////////////////////////////////////////////////////////
  // Process     : Multiplication Handshake Process
  // Description : Keeps the handshake signals align with the multilication
  //               data, keeps the pipeline in-sync.
  /////////////////////////////////////////////////////////////////////////////
  always @(posedge i_clk) begin : multiplication_hndshk_proc
    if (i_rst) begin
      is_mul_r  <= 1'b0;
      is_mulh_r <= 1'b0;
      mul_done  <= 1'b0;
    end
    else begin
      is_mul_r  <= is_mul;
      is_mulh_r <= is_mulh;
      mul_done  <= mul_en;
    end
  end // multiplication_hndshk_proc

  /////////////////////////////////////////////////////////////////////////////
  // Process     : Division Process
  // Description : Inspired by Altera's old cook book.
  /////////////////////////////////////////////////////////////////////////////
  always @(posedge i_clk) begin
    if (i_rst) begin
      dividend  <= 0;
      divisor   <= 0;
      outsign   <= 1'b0;
      cntr      <= WIDTH;
      div_ready <= 1'b0;
      div_start <= 1'b0;
    end
    else if (prep) begin

      dividend  <= {{WIDTH{1'b0}},(!unsign_div_rem & i_mdu_rs1[31] ? -i_mdu_rs1 : i_mdu_rs1),1'b0};
      divisor   <= (!unsign_div_rem & i_mdu_rs2[31]) ? -i_mdu_rs2 : i_mdu_rs2; 
      outsign   <= (!unsign_div_rem & is_div & (i_mdu_rs1[31] ^ i_mdu_rs2[31]) & (|i_mdu_rs2)) |
                   (!unsign_div_rem & is_rem & i_mdu_rs1[31]);
      cntr      <= WIDTH;
      div_ready <= 1'b0;
      div_start <= 1'b1;
    end 
    else if (cntr_zero) begin
      div_ready <= 1'b1;
      div_start <= 1'b0;
      cntr      <= WIDTH;
      if (is_div) begin
        div_rd <= outsign ? -quotient : quotient;
      end 
      else begin
        div_rd <= outsign ? -remainder : remainder; 
      end
    end 
    else begin
      div_ready <= 1'b0;
			cntr      <= cntr - 1;
			dividend  <= sub_result_neg ? {dividend[WIDTH+P_DATA_MSB:0],1'b0} :
					                          {sub_result[P_DATA_MSB:0],quotient,1'b1};
    end
  end

  //
  assign o_mdu_ready = mul_done | div_ready;
  assign o_mdu_rd    = is_mul ? mul_rd : div_rd;

endmodule
`default_nettype wire
