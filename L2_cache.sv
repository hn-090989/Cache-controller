/* 2 way associative L2 cache 
 
 tag store:                                                                    data store:
	      
		          	way 1                                way2                 
			 ________________________   			  ________________________
	       |valid bit  | dirty bit |	           |valid bit  | dirty bit |  
	set 1  |				 | 			 |  	 set 1  |			  | 	   	  | 
	set 2  |           |           | 	 set 2  |           |           |
	                                            
*/

module L2_cache 
	import cache_pkg::*;
#(
	 parameter LINE_SIZE  = cache_pkg::LINE_SIZE,
    parameter CACHE_SIZE = cache_pkg::L2_CACHE_SIZE,
    parameter BUS_WIDTH  = cache_pkg::BUS_WIDTH,
	 parameter ADDR_WIDTH = cache_pkg::ADDR_WIDTH
)(
	input Clk,
	input logic [ADDR_WIDTH-1:0] address,
	
	// L1 <-> L2
	input logic L2_to_L1_en,
	input logic L1_to_L2_en,
	input logic [BUS_WIDTH-1:0] l1_to_l2_data,   // L1 drives, L2 reads
	output logic [BUS_WIDTH-1:0] l2_to_l1_data,   // L2 drives, L1 reads
	
	// L2 <-> main memory
	input logic main_to_L2_en,
	input logic L2_to_main_en,
	input  logic [BUS_WIDTH-1:0] main_to_l2_data,   
	output logic [BUS_WIDTH-1:0] l2_to_main_data,   
	
	input  [1:0] transfer_logic,
	input  logic transfer_complete,
	output logic hit,
	
	output l2_tag_entry eviction_tag,
	output [L2_INDEX_WIDTH] eviction_index,
	
	output full
	);
	
	// ------------------------------------------------------------
   // ADDRESS DECODING
   // ------------------------------------------------------------
	logic [L2_TAG_WIDTH-1:0] tag_bits;
	logic [L2_INDEX_WIDTH-1:0] index_bits;
	logic [L2_OFFSET_WIDTH-1:0] offset_bits;
	
	assign tag_bits = address[ADDR_WIDTH-1 -: L2_TAG_WIDTH];
	assign index_bits = address[ADDR_WIDTH-L2_TAG_WIDTH-1 -: L2_INDEX_WIDTH];
	assign offset_bits = address[ADDR_WIDTH-L2_TAG_WIDTH-L2_INDEX_WIDTH-1 -: L2_OFFSET_WIDTH];
	
	
	// ------------------------------------------------------------
   // CACHE ORGANIZATION
   // ------------------------------------------------------------
	localparam NUM_LINES = CACHE_SIZE/(LINE_SIZE*2);
	localparam LINE_BITS = LINE_SIZE*8;
	
	logic [LINE_BITS-1:0] data_store [NUM_LINES][2];       //data store
	l2_tag_entry tag_store[NUM_LINES][2];                  //tag store
	logic LRU[NUM_LINES];                                  //LRU 
	
	
	logic replacement_way, hit_way, selected_way, update_LRU;

   l2_tag_entry tag0;
   l2_tag_entry tag1;

   assign tag0 = tag_store[index_bits][0];
   assign tag1 = tag_store[index_bits][1];	
	 
	 
	//recieving from L1/main memory
	always_ff @(posedge Clk) begin
		//L2 miss - data transfer from main memory to L2 
		if (main_to_L2_en) 
		  data_store[index_bits][selected_way][transfer_counter*BUS_WIDTH +: BUS_WIDTH] <= main_to_l2_data;
		
		if (transfer_complete & main_to_L2_en) begin
			tag_store[index_bits][selected_way].tag <= tag_bits;
			tag_store[index_bits][selected_way].valid <= 1'b1;
			tag_store[index_bits][selected_way].dirty <= 1'b0;
		end
		
		//write back (L2 hit and need to transfer to an occupied L1) - from L1 to L2 when L1 
		if (L1_to_L2_en) begin
			data_store[index_bits][selected_way][transfer_counter*BUS_WIDTH +: BUS_WIDTH] <= l1_to_l2_data;
		end
		
		if(transfer_complete_L2 & L1_to_L2_en) begin
			tag_store[index_bits][selected_way].dirty <= 1'b1;
		end
		
		
		//LRU register
		LRU[index_bits] <= update_LRU;
	end

	always_comb begin 
		//determinig HIT/MISS
		hit_way = 1'b0;
		hit = 1'b0;
		update_LRU = 1'b0;
		full = 1'b0;
			
		// --------------------------------------------------------
		// HIT DETECTION
      // --------------------------------------------------------
		if (tag0.valid && tag0.tag == tag_bits) begin
			hit = 1'b1;
			hit_way = 1'b0; 
			update_LRU = 1'b1;
		end
			
		if (tag1.valid && tag1.tag == tag_bits) begin
			hit = 1'b1;
			hit_way = 1'b1;
			update_LRU = 1'b0;
		end
			
		//L2 driving data wires
		l2_to_l1_data = data_store[index_bits][selected_way][transfer_counter*BUS_WIDTH +: BUS_WIDTH];       //L2 hit
		l2_to_main_data = data_store[index_bits][selected_way][transfer_counter*BUS_WIDTH +: BUS_WIDTH];    //write back (main memory access after L2 miss and L2 needs to write back to memory)
		
		//determining replacement way
		if (!tag_store[index_bits][0].valid) begin 
			replacement_way = 1'b0;
			full = 1'b0;
		end
		else if (!tag_store[index_bits][1].valid) begin
			replacement_way = 1'b1;
			full = 1'b0;
		end
		else begin
			replacement_way = LRU[index_bits];
			full = 1'b1;
		end
			
		// selected victim tag
		if (replacement_way == 1'b0)
			eviction_tag = tag_store[index_bits][0];
		else
			eviction_tag = tag_store[index_bits][1];
		end
	
	
endmodule