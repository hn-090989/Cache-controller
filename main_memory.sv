module main_memory #(
	parameter int unsigned ADDR_WIDTH = 30,
	parameter int unsigned BUS_WIDTH = 128,
	parameter int unsigned LINE_SIZE = 64
)(
	input logic Clk,
	
	input logic address[ADDR_WIDTH-1:0],
	
	// L2 <-> main memory
	input logic main_to_L2_en,
	input logic L2_to_main_en,
	input logic [BUS_WIDTH-1:0] l2_to_main_data,
	output logic [BUS_WIDTH-1:0] main_to_l2_data,   
	
	input [1:0] logic trasfer_counter;
);

	localparam int NUM_LINES = (2**ADDR_WIDTH) / LINE_SIZE;
	logic [ADDR_WIDTH-1:0] line_address;

	logic [LINE_SIZE*8-1:0] mem [0:NUM_LINES-1];

	assign line_address = address >> $clog2(LINE_SIZE);
	
	always_ff @(posedge Clk) begin
		if(L2_to_main_en)
			mem[line_address][transfer_counter*BUS_WIDTH +: BUS_WIDTH] <= l2_to_main_data;
	end
	
	always_comb begin
		main_to_l2_data = mem[line_address][transfer_counter*BUS_WIDTH +: BUS_WIDTH];
	end

endmodule