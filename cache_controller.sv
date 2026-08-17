typedef enum logic [3:0] {
    IDLE,
    SEARCH_L1,
    L1_HIT,
    SEARCH_L2,
    L2_HIT,
    CHECK_L2_VICTIM,
    MAIN_MEMORY_ACCESS,
    WRITEBACK_L1,
    REFILL_L1,
    WRITEBACK_L2,
    REFILL_L2
} controller_states;


module cache_controller(
    input  logic Clk,
    input  logic reset,
    input  logic wren,
    input  logic en,

    input logic [ADDR_WIDTH-1:0] address,
    input logic [7:0] write_data,
    output logic [7:0] read_data
);

    controller_states current_state, next_state;

    logic [7:0] controller_to_l1_data;
    logic [7:0] l1_to_controller_data;

    logic [BUS_WIDTH-1:0] l2_to_l1_data;
    logic [BUS_WIDTH-1:0] l1_to_l2_data;

    logic [BUS_WIDTH-1:0] main_to_l2_data;
    logic [BUS_WIDTH-1:0] l2_to_main_data;

    logic [1:0] transfer_counter;
    logic [1:0] next_transfer_counter;

    tag_entry current_l1_tag_entry;

    logic l1_hit, l2_hit;
    logic transfer_complete_l1, transfer_complete_l2;
    logic l2_full;
    logic flag, next_flag;

    logic main_to_L2_en;
    logic L2_to_main_en;
    logic L2_to_L1_en;
    logic L1_to_controller_en;
    logic controller_to_L1_en;
    logic L1_to_L2_en;

    logic [ADDR_WIDTH-1:0] l2_address;
    logic [ADDR_WIDTH-1:0] main_address;

    logic [L1_TAG_WIDTH-1:0] l1_eviction_tag;
    logic [L1_INDEX_WIDTH-1:0] l1_eviction_index;

    logic [L2_TAG_WIDTH-1:0] l2_eviction_tag;
    logic [L2_INDEX_WIDTH-1:0] l2_eviction_index;

    tag_entry l2_hit_tag, current_l1_tag_entry;

	 // ------------------------------------------------------------
    // L1 CACHE
    // ------------------------------------------------------------
    L1_cache L1(
        .Clk(Clk),

        .address(address),

        .L2_to_L1_en(L2_to_L1_en),
        .L1_to_L2_en(L1_to_L2_en),
        .l2_to_l1_data(l2_to_l1_data),
        .l1_to_l2_data(l1_to_l2_data),

        .L1_to_controller_en(L1_to_controller_en),
        .controller_to_L1_en(controller_to_L1_en),
        .controller_to_l1_data(controller_to_l1_data),
        .l1_to_controller_data(l1_to_controller_data),

        .transfer_counter(transfer_counter),
        .transfer_complete(transfer_complete_l1),

        .hit(l1_hit),

        .tag0(current_l1_tag_entry),
        .l1_index_bits(index_bits)
    );
	 
	 // ------------------------------------------------------------
    // L2 CACHE
	 // ------------------------------------------------------------
    L2_cache L2(
        .Clk(Clk),

        .address(l2_address),

        .main_to_L2_en(main_to_L2_en),
        .L2_to_main_en(L2_to_main_en),
        .main_to_l2_data(main_to_l2_data),
        .l2_to_main_data(l2_to_main_data),

        .L2_to_L1_en(L2_to_L1_en),
        .L1_to_L2_en(L1_to_L2_en),
        .l2_to_l1_data(l2_to_l1_data),
        .l1_to_l2_data(l1_to_l2_data),

        .transfer_counter(transfer_counter),
        .transfer_complete(transfer_complete_l2),

        .hit(l2_hit),

        .eviction_tag(l2_eviction_tag),
        .eviction_index(l2_eviction_index),

        .full(l2_full)
    );


    // ------------------------------------------------------------
    // MAIN MEMORY
    // ------------------------------------------------------------
    main_memory RAM(
        .Clk(Clk),

        .address(main_address),

        .main_to_L2_en(main_to_L2_en),
        .L2_to_main_en(L2_to_main_en),

        .main_to_l2_data(main_to_l2_data),
        .l2_to_main_data(l2_to_main_data),

        .transfer_counter(transfer_counter)
    );

    // ------------------------------------------------------------
    // STATE REGISTERS
    // ------------------------------------------------------------

    always_ff @(posedge Clk or negedge reset) begin
        if (!reset) begin
            current_state <= IDLE;
            transfer_counter <= 2'd0;
            flag <= 1'b0;
        end
        else begin
            current_state <= next_state;
            transfer_counter <= next_transfer_counter;
            flag <= next_flag;
        end
    end


    // ------------------------------------------------------------
    // NEXT STATE LOGIC
    // ------------------------------------------------------------

    always_comb begin

        // Default values
        next_state = current_state;
        next_transfer_counter = transfer_counter;
        next_flag = 1'b0;

        main_to_L2_en = 1'b0;
        L2_to_main_en = 1'b0;
        L2_to_L1_en = 1'b0;

        L1_to_controller_en = 1'b0;
        controller_to_L1_en = 1'b0;

        L1_to_L2_en = 1'b0;

        transfer_complete_l1 = 1'b0;
        transfer_complete_l2 = 1'b0;


        case (current_state)

            // ----------------------------------------------------
            // IDLE
            // ----------------------------------------------------
            IDLE: begin
                if (en)
                    next_state = SEARCH_L1;
                else
                    next_state = IDLE;
            end

            // ----------------------------------------------------
            // SEARCH L1
            // ----------------------------------------------------
            SEARCH_L1: begin
                if (l1_hit)
                    next_state = L1_HIT;
                else
                    next_state = SEARCH_L2;
            end
				
            // ----------------------------------------------------
            // L1 HIT
            // ----------------------------------------------------
            L1_HIT: begin
                if (wren) begin
                    // Transfer 1 byte of requested data
                    controller_to_L1_en = 1'b1;

                    next_state = IDLE;
                end
                else begin
                    L1_to_controller_en = 1'b1;
                    next_state = IDLE;
                end
            end
				
            // ----------------------------------------------------
            // SEARCH L2
            // ----------------------------------------------------
            SEARCH_L2: begin
                if (l2_hit)
                    next_state = L2_HIT;
                else
                    next_state = MAIN_MEMORY_ACCESS;
            end

            // ----------------------------------------------------
            // L2 HIT
            // ----------------------------------------------------
            L2_HIT: begin
                if (!current_l1_tag_entry.valid) begin
                    next_state = REFILL_L1;
                end
                else if (current_l1_tag_entry.dirty) begin
                    next_state = WRITEBACK_L1;
                end
                else begin
                    next_state = REFILL_L1;
                end
            end


            // ----------------------------------------------------
            // CHECK L2 VICTIM
            // ----------------------------------------------------
            CHECK_L2_VICTIM: begin
                if (l2_full) begin
                    next_state = WRITEBACK_L2;
                    next_flag = 1'b1;
                end
                else begin
                    next_state = WRITEBACK_L1;
                end
            end

            // ----------------------------------------------------
            // MAIN MEMORY ACCESS
            // ----------------------------------------------------
            MAIN_MEMORY_ACCESS: begin
                if (!l2_hit_tag.valid) begin
                    next_state = REFILL_L2;
                end
                else if (l2_hit_tag.dirty) begin
                    next_state = WRITEBACK_L2;
                end
                else begin
                    next_state = REFILL_L2;
                end
            end

            // ----------------------------------------------------
            // REFILL L1
            // ----------------------------------------------------
            REFILL_L1: begin
                L2_to_L1_en = 1'b1;

                if (transfer_counter < 2'd3) begin
                    next_transfer_counter = transfer_counter + 1'b1;
                    next_state = REFILL_L1;
                end
                else begin
                    transfer_complete_l1 = 1'b1;
                    next_transfer_counter = 2'd0;
                    next_state = L1_HIT;
                end
            end

            // ----------------------------------------------------
            // WRITEBACK L1
            // ----------------------------------------------------
            WRITEBACK_L1: begin
                L1_to_L2_en = 1'b1;
					 
                if (transfer_counter < 2'd3) begin
                    next_transfer_counter = transfer_counter + 1'b1;
                    next_state = WRITEBACK_L1;
                end
                else begin
                    next_transfer_counter = 2'd0;
                    next_state = REFILL_L1;
                end
            end

            // ----------------------------------------------------
            // REFILL L2
            // ----------------------------------------------------
            REFILL_L2: begin
                main_to_L2_en = 1'b1;

                if (transfer_counter < 2'd3) begin
                    next_transfer_counter = transfer_counter + 1'b1;
                    next_state = REFILL_L2;
                end
                else begin
                    transfer_complete_l2 = 1'b1;
                    next_transfer_counter = 2'd0;
                    next_state = L2_HIT;
                end
            end

            // ----------------------------------------------------
            // WRITEBACK L2
            // ----------------------------------------------------
            WRITEBACK_L2: begin
                L2_to_main_en = 1'b1;

                if (transfer_counter < 2'd3) begin
                    next_transfer_counter = transfer_counter + 1'b1;
                    next_state = WRITEBACK_L2;
                end

                else begin
                    next_transfer_counter = 2'd0;

                    if (flag)
                        next_state = WRITEBACK_L1;
                    else
                        next_state = REFILL_L2;
                end
            end


            // ----------------------------------------------------
            // DEFAULT
            // ----------------------------------------------------
            default: begin
                next_state = IDLE;
                next_transfer_counter = 2'd0;
                next_flag = 1'b0;
            end
        endcase
    end


    // ------------------------------------------------------------
    // ADDRESS GENERATION
    // ------------------------------------------------------------
    always_comb begin

        if (current_state == WRITEBACK_L1) begin
            l2_address = { current_l1_tag_entry.tag, l1_index_bits, {L2_OFFSET_WIDTH{1'b0}}};
        end
        else begin
            l2_address = address;
        end

        if (current_state == WRITEBACK_L2) begin
            main_address =
                {l2_eviction_tag, l2_eviction_index, {L2_OFFSET_WIDTH{1'b0}}};
        end
        else begin
            main_address = address;
        end
    end

endmodule

	 