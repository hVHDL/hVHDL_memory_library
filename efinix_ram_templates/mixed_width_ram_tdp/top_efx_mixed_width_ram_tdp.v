////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2013-2018 Efinix Inc. All rights reserved.
//
// top_efx_mixed_width_ram_tdp.v
//
// Example on how to instantiate VHDL module. 
//
// *******************************
// Revisions:
// 0.0 Initial rev
// *******************************
/////////////////////////////////////////////////////////////////////////////

module top_efx_mixed_width_ram_tdp
  #( parameter OUTREG_A = 0,
               OUTREG_B = 0,
               WRITE_MODE_A = "READ_FIRST",
               WRITE_MODE_B = "READ_FIRST",
               DATA_WIDTH_A = 8,
               ADDRESS_WIDTH_A = 10,
               ADDRESS_WIDTH_B = 8
     )
  (
   //inputs
   input 	 clk,
   input         en,   
   input 	 we_a,
   input 	 we_b,
   input [9:0] 	 addr_a,
   input [7:0] 	 addr_b,
   input [7:0] 	 data_in_a,
   input [31:0]  data_in_b,

   //outputs
   output [7:0]  data_out_a,
   output [31:0] data_out_b
    );

  

   efx_mixed_width_ram_tdp
     #(.OUTREG_A(OUTREG_A),
       .OUTREG_B(OUTREG_B),
       .WRITE_MODE_A(WRITE_MODE_A),
       .WRITE_MODE_B(WRITE_MODE_B),
       .DATA_WIDTH_A(DATA_WIDTH_A),
       .ADDRESS_WIDTH_A(ADDRESS_WIDTH_A),
       .ADDRESS_WIDTH_B(ADDRESS_WIDTH_B)
       )
     u_efx_mixed_width_ram_tdp
       (
	//inputs
	.clk(clk),
	.en(en),
	.we_a(we_a),
	.we_b(we_b),
	.addr_a(addr_a),
	.addr_b(addr_b),
	.data_in_a(data_in_a),
	.data_in_b(data_in_b),
	//outputs
	.data_out_a(data_out_a),
	.data_out_b(data_out_b));

endmodule // top_efx_mixed_width_ram
