/* 2 way associative L2 cache 
 
 tag store:                                                                    
	      
		          	way 1                                way2                 
			 ________________________   			   ________________________
	       |valid bit  | dirty bit |	           |valid bit  | dirty bit |  
	set 1  |				 | 			 |  	 set 1  |			  | 	   	  | 
	set 2  |           |           | 	 set 2  |           |           |
	

 data store:
	                                            
*/

module L2_cache
    import cache_pkg::*;
#(
    parameter int LINE_SIZE      = cache_pkg::LINE_SIZE,
    parameter int CACHE_SIZE     = cache_pkg::L2_CACHE_SIZE,
    parameter int BUS_WIDTH      = cache_pkg::BUS_WIDTH,
    parameter int ADDR_WIDTH     = cache_pkg::ADDR_WIDTH,
    parameter int L2_TAG_WIDTH   = cache_pkg::L2_TAG_WIDTH,
    parameter int L2_INDEX_WIDTH = cache_pkg::L2_INDEX_WIDTH
)(
    input  logic                  Clk,
    input  logic                  reset,            // active low, synchronous clear
    input  logic [ADDR_WIDTH-1:0] address,

    // L1 <-> L2
    input  logic                  L1_to_L2_en,
    input  logic [BUS_WIDTH-1:0]  l1_to_l2_data,    // L1 drives, L2 reads
    output logic [BUS_WIDTH-1:0]  l2_to_l1_data,    // L2 drives, L1 reads

    // L2 <-> main memory
    input  logic                  main_to_L2_en,
    input  logic [BUS_WIDTH-1:0]  main_to_l2_data,
    output logic [BUS_WIDTH-1:0]  l2_to_main_data,

    input  logic [2:0]            transfer_counter,
    input  logic                  transfer_complete,
    input  logic                  use_hit_way,
    input  logic                  touch,            // mark the hit line most recently used
    output logic                  hit,

    output l2_tag_entry                   eviction_tag,
    output logic [L2_INDEX_WIDTH-1:0]     eviction_index
);

    // ------------------------------------------------------------
    // ADDRESS DECODING
    logic [L2_TAG_WIDTH-1:0]   tag_bits;
    logic [L2_INDEX_WIDTH-1:0] index_bits;

    assign tag_bits   = address[ADDR_WIDTH-1 -: L2_TAG_WIDTH];
    assign index_bits = address[ADDR_WIDTH-L2_TAG_WIDTH-1 -: L2_INDEX_WIDTH];

    // ------------------------------------------------------------
    // CACHE ORGANIZATION
    localparam int NUM_LINES = CACHE_SIZE/(LINE_SIZE*2);
    localparam int LINE_BITS = LINE_SIZE*8;

    logic [LINE_BITS-1:0] data_store [NUM_LINES][2];
    l2_tag_entry tag_store  [NUM_LINES][2];
    logic LRU [NUM_LINES];

    logic replacement_way, hit_way, selected_way;

    l2_tag_entry tag0, tag1;

    assign tag0 = tag_store[index_bits][0];
    assign tag1 = tag_store[index_bits][1];
    assign eviction_index = index_bits;

    // ------------------------------------------------------------
    // WRITES, TAG UPDATES, LRU
    always_ff @(posedge Clk) begin
        if (!reset) begin
            for (int i = 0; i < NUM_LINES; i++) begin
                tag_store[i][0].valid <= 1'b0;
                tag_store[i][0].dirty <= 1'b0;
                tag_store[i][1].valid <= 1'b0;
                tag_store[i][1].dirty <= 1'b0;
                LRU[i]                <= 1'b0;
            end
        end
        else begin
            // main memory -> L2 (refill, uses replacement way)
            if (main_to_L2_en)
                data_store[index_bits][selected_way][transfer_counter*BUS_WIDTH +: BUS_WIDTH] <= main_to_l2_data;

            // L1 -> L2 (writeback)
            if (L1_to_L2_en)
                data_store[index_bits][selected_way][transfer_counter*BUS_WIDTH +: BUS_WIDTH] <= l1_to_l2_data;

            // Refill finished: line is valid and clean
            if (transfer_complete && main_to_L2_en) begin
                tag_store[index_bits][selected_way].tag   <= tag_bits;
                tag_store[index_bits][selected_way].valid <= 1'b1;
                tag_store[index_bits][selected_way].dirty <= 1'b0;
            end

            // L1 writeback finished: line is valid and dirty.
            // The tag is written too, so a victim that was NOT in L2
            // gets a proper tag when it is installed in the replacement way.
            if (transfer_complete && L1_to_L2_en) begin
                tag_store[index_bits][selected_way].tag   <= tag_bits;
                tag_store[index_bits][selected_way].valid <= 1'b1;
                tag_store[index_bits][selected_way].dirty <= 1'b1;
            end

            // The way that was just hit becomes most recently used
            if (touch && hit)
                LRU[index_bits] <= ~hit_way;
        end
    end

    // ------------------------------------------------------------
    // HIT, REPLACEMENT, READ DATA
    always_comb begin
        hit     = 1'b0;
        hit_way = 1'b0;
		  selected_way = '0; 

        if (tag0.valid && tag0.tag == tag_bits) begin
            hit     = 1'b1;
            hit_way = 1'b0;
        end
        if (tag1.valid && tag1.tag == tag_bits) begin
            hit     = 1'b1;
            hit_way = 1'b1;
        end

			// Replacement: first invalid way, otherwise LRU (the way L2 will overwrite when space is needed for a new line) 
        // the destination of REFILL_L2 (main to L2), and the source of WRITEBACK_L2 (L2 to main).
		  if (!tag0.valid)
            replacement_way = 1'b0;
        else if (!tag1.valid)
            replacement_way = 1'b1;
        else
            replacement_way = LRU[index_bits];  

        eviction_tag = replacement_way ? tag1 : tag0;    // tag entry of the replacement way

        selected_way = use_hit_way ? hit_way : replacement_way;

        l2_to_l1_data   = data_store[index_bits][selected_way][transfer_counter*BUS_WIDTH +: BUS_WIDTH];
        l2_to_main_data = data_store[index_bits][selected_way][transfer_counter*BUS_WIDTH +: BUS_WIDTH];
    end

endmodule
