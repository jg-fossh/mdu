// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

/* Multiplication & Division Unit */
module mdu_top #(
  parameter integer P_DATA_MSB = 31
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
  reg                           is_mul_r;
  reg                           is_mulh_r;
  reg  [(2*(P_DATA_MSB+1))-1:0] rd;
  reg                           mul_done;
  // Multiplication Control Signals
  wire mul_en          = is_mul & i_mdu_valid;
  wire is_mul          = !i_mdu_op[2];
  wire unsign_mul      =  i_mdu_op[1]; 
  wire sign_unsign_mul =  i_mdu_op[0]; 
  wire is_mulh         = (|i_mdu_op) & is_mul;
  // Multiplication Data Muxes 
  wire [P_DATA_MSB+1:0] rdata_a = unsign_mul ? (
                                    sign_unsign_mul ? $unsigned(i_mdu_rs1) : $signed({i_mdu_rs1[P_DATA_MSB],i_mdu_rs1})) :
                                    $signed(i_mdu_rs1);
  wire [P_DATA_MSB+1:0] rdata_b = unsign_mul ? $unsigned(i_mdu_rs2) : $signed(i_mdu_rs2);
  wire [P_DATA_MSB:0]   mul_rd  = is_mulh ? rd[(2*(P_DATA_MSB+1))-1:P_DATA_MSB+1] : rd[P_DATA_MSB:0];

  // Division Process Signals
  reg                          outsign;
  reg [P_DATA_MSB:0]           dividend;
  reg [P_DATA_MSB:0]           quotient;  
  reg [P_DATA_MSB:0]           quotient_msk;
  reg [P_DATA_MSB:0]           div_rd;
  reg [(2*(P_DATA_MSB+1))-2:0] divisor;
  // Division Control Signals
  reg  div_ready;
  reg  running;
  wire is_div         = i_mdu_op[2] & (!i_mdu_op[1]);
  wire is_rem         = i_mdu_op[2] & i_mdu_op[1];
  wire unsign_div_rem = i_mdu_op[0];
  wire prep           = i_mdu_valid & (is_div | is_rem) & !running & !div_ready;	

  ///////////////////////////////////////////////////////////////////////////////
  //            ********      Architecture Declaration      ********           //
  ///////////////////////////////////////////////////////////////////////////////

  /////////////////////////////////////////////////////////////////////////////
  // Process     : Multiplication Process
  // Description : Generic code that modern synthesizers infer as DSP blocks.
  //  and generates an operation done strobe.
  /////////////////////////////////////////////////////////////////////////////
  always @(posedge i_clk) begin : multiplication_proc
    if (!i_rst & mul_en) begin
      rd <= rdata_a * rdata_b;
    end
  end // multiplication_proc
  
  /////////////////////////////////////////////////////////////////////////////
  // Process     : Multiplication Process
  // Description : Generic code that modern synthesizers infer as DSP blocks.
  //  and generates an operation done strobe.
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
  // Description : Taken from picorv32.
  /////////////////////////////////////////////////////////////////////////////
  always @(posedge i_clk) begin
    if (i_rst)  
      running <= 1'b0;
    else if (prep) begin
      dividend <= (!unsign_div_rem & i_mdu_rs1[31]) ? -i_mdu_rs1 : i_mdu_rs1;
      divisor  <= ((!unsign_div_rem & i_mdu_rs2[31]) ? -i_mdu_rs2 : i_mdu_rs2) << 31; 
      outsign  <= (!unsign_div_rem & is_div & (i_mdu_rs1[31] != i_mdu_rs2[31]) & (|i_mdu_rs2)) 
                   | (!unsign_div_rem & is_rem & i_mdu_rs1[31]);
      quotient <= 32'b0;
      quotient_msk <= 1 << 31;
      running <= 1'b1;
      div_ready <= 1'b0;
    end else if (!quotient_msk && running) begin
      running   <= 1'b0;
      div_ready <= 1'b1;
      if (is_div) begin
        div_rd <= outsign ? -quotient : quotient;
      end else begin
        div_rd <= outsign ? -dividend : dividend; 
      end
    end else begin
      div_ready <= 1'b0; 
      if (divisor <= dividend) begin
	      dividend <= dividend - divisor;
	      quotient <= quotient | quotient_msk;
      end
      divisor <= divisor >> 1;
      quotient_msk <= quotient_msk >> 1;
    end
  end

  assign o_mdu_ready = mul_done | div_ready;
  assign o_mdu_rd    = is_mul ? mul_rd : div_rd;

endmodule
`default_nettype wire
