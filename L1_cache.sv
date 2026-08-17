/*Directly mapped L1 cache (1 way associative)
 Contains seperate tag and data stores
 
 tag store:                                 data store:
	      		    	way 1
			 ________________________
	       |valid bit  | dirty bit |	  
	set 1  |				 | 			 |  
	set 2  |           |           | 
	
*/

module L1_cache 
	import cache_pkg::*;
#(
	 parameter LINE_SIZE  = cache_pkg::LINE_SIZE,
    parameter CACHE_SIZE = cache_pkg::L1_CACHE_SIZE,
    parameter BUS_WIDTH  = cache_pkg::BUS_WIDTH
)(
	input logic Clk,
	input logic [L1_INDEX_WIDTH-1:0] address,
	
	// L1 <-> L2
	input logic L2_to_L1_en,
	input logic L1_to_L2_en,
	input  logic [BUS_WIDTH-1:0] l2_to_l1_data,   // L2 drives, L1 reads
	output logic [BUS_WIDTH-1:0] l1_to_l2_data,   // L1 drives, L2 reads
	
	// L1 <-> controller
	input logic L1_to_controller_en,
	input logic controller_to_L1_en,
	input  logic [7:0] controller_to_l1_data,   // controller drives, L1 reads
	output logic [7:0] l1_to_controller_data,   // L1 drives, controller reads
	
	input  [1:0] transfer_counter,
	input  logic transfer_complete,
	output logic hit,
	output tag_entry tag0
	);
	
	// ------------------------------------------------------------
   // ADDRESS DECODING
   // ------------------------------------------------------------
	logic [L1_TAG_WIDTH-1:0] tag_bits;
	logic [L1_INDEX_WIDTH-1:0] index_bits;
	logic [L1_OFFSET_WIDTH-1:0] offset_bits;
	
	assign tag_bits = address[ADDR_WIDTH-1 -: L1_TAG_WIDTH];
	assign index_bits = address[ADDR_WIDTH-L1_TAG_WIDTH-1 -: L1_INDEX_WIDTH];
	assign offset_bits = address[ADDR_WIDTH-L1_TAG_WIDTH-L1_INDEX_WIDTH-1 -: L1_OFFSET_WIDTH];
	
	// ------------------------------------------------------------
   // CACHE ORGANIZATION
   // ------------------------------------------------------------
	localparam NUM_LINES = CACHE_SIZE/LINE_SIZE;
	localparam LINE_BITS = LINE_SIZE*8;

	logic [LINE_BITS-1:0] data_store [NUM_LINES];               //data store
	l1_tag_entry tag_store[NUM_LINES];                          //tag store
	
	assign tag0 = tag_store[index_bits];
	
	// ------------------------------------------------------------
   // L2 / CONTROLLER -> L1
   // ------------------------------------------------------------
	always_ff @(posedge Clk) begin
		if (L2_to_L1_en) 
		  data_store[index_bits][transfer_counter*BUS_WIDTH +: BUS_WIDTH] <= l2_to_l1_data;
		
		if (transfer_complete) begin
			tag_store[index_bits].tag <= tag_bits;
			tag_store[index_bits].valid <= 1'b1;
			tag_store[index_bits].dirty <= 1'b0;
		end
		
		if (controller_to_L1_en) begin
			data_store[index_bits][offset_bits*8 +: 8] <= controller_to_l1_data;
			tag_store[index_bits].dirty <= 1'b1;
		end
	end
	
	
	always_comb begin 
		//HIT/MISS logic
		hit = 1'b0;
			
		if (tag0.valid && tag0.tag == tag_bits)
			hit = 1'b1;	
			
		//L1 -> controller
		l1_to_controller_data = data_store[index_bits][offset_bits*8 +: 8];
		
		//L1 -> L2
		l1_to_l2_data = data_store[index_bits][transfer_counter*BUS_WIDTH +: BUS_WIDTH];
	end
	
endmodule