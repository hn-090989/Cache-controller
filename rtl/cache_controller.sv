typedef enum logic [4:0] {
    IDLE,
    SEARCH_L1,
    L1_HIT,
    SEARCH_L2,
    L2_HIT,
    SEARCH_L2_L1_VICTIM,
    MAIN_MEMORY_ACCESS,
    WRITEBACK_L1,
    REFILL_L1,
    WRITEBACK_L2,
    REFILL_L2
} controller_states;


module cache_controller
    import cache_pkg::*;
#(
    parameter int ADDR_WIDTH      = cache_pkg::ADDR_WIDTH,
    parameter int BUS_WIDTH       = cache_pkg::BUS_WIDTH,
    parameter int L1_TAG_WIDTH    = cache_pkg::L1_TAG_WIDTH,
    parameter int L1_INDEX_WIDTH  = cache_pkg::L1_INDEX_WIDTH,
    parameter int L2_TAG_WIDTH    = cache_pkg::L2_TAG_WIDTH,
    parameter int L2_INDEX_WIDTH  = cache_pkg::L2_INDEX_WIDTH,
    parameter int L2_OFFSET_WIDTH = cache_pkg::L2_OFFSET_WIDTH
)
(
    input  logic                  Clk,
    input  logic                  reset,      // active low
    input  logic                  wren,
    input  logic                  en,         // hold high until done
    input  logic [ADDR_WIDTH-1:0] address,
    input  logic [7:0]            write_data,
    output logic [7:0]            read_data,
    output logic                  done
);

    localparam logic [2:0] LAST_BEAT = 3'd3; 

    controller_states current_state, next_state;

    // ------------------------------------------------------------
    // Latched request
    logic [ADDR_WIDTH-1:0] address_q;
    logic                  wren_q;
    logic [7:0]            write_data_q;

    // ------------------------------------------------------------
    // Datapath signals
    logic [7:0]           controller_to_l1_data;
    logic [7:0]           l1_to_controller_data;
    logic [BUS_WIDTH-1:0] l2_to_l1_data;
    logic [BUS_WIDTH-1:0] l1_to_l2_data;
    logic [BUS_WIDTH-1:0] main_to_l2_data;
    logic [BUS_WIDTH-1:0] l2_to_main_data;

    logic [2:0] transfer_counter;
    logic [2:0] next_transfer_counter;

    l1_tag_entry current_l1_tag_entry;

    logic l1_hit, l2_hit;
    logic transfer_complete_l1, transfer_complete_l2;
    logic flag, next_flag;       // flag = 1 while making room in L2 for the L1 victim

    logic l2_use_hit_way;        // 1: L2 uses the way that hit, 0: L2 uses its replacement way
    logic L2_touch;              // mark the L2 hit line most recently used

    logic main_to_L2_en;
    logic L2_to_main_en;
    logic L2_to_L1_en;
    logic L1_to_controller_en;
    logic controller_to_L1_en;
    logic L1_to_L2_en;

    logic [ADDR_WIDTH-1:0]     l2_address;
    logic [ADDR_WIDTH-1:0]     main_address;
    logic [L1_INDEX_WIDTH-1:0] l1_index_bits;
    l2_tag_entry               l2_eviction_tag;
    logic [L2_INDEX_WIDTH-1:0] l2_eviction_index;

    assign controller_to_l1_data = write_data_q;

    // ------------------------------------------------------------
    // L1 CACHE
    L1_cache L1(
        .Clk                  (Clk),
        .reset                (reset),
        .address              (address_q),
        .L2_to_L1_en          (L2_to_L1_en),
        .l2_to_l1_data        (l2_to_l1_data),
        .l1_to_l2_data        (l1_to_l2_data),
        .controller_to_L1_en  (controller_to_L1_en),
        .controller_to_l1_data(controller_to_l1_data),
        .l1_to_controller_data(l1_to_controller_data),
        .transfer_counter     (transfer_counter),
        .transfer_complete    (transfer_complete_l1),
        .hit                  (l1_hit),
        .tag0                 (current_l1_tag_entry),
        .l1_index_bits        (l1_index_bits)
    );

    // ------------------------------------------------------------
    // L2 CACHE
    L2_cache L2(
        .Clk              (Clk),
        .reset            (reset),
        .address          (l2_address),
        .main_to_L2_en    (main_to_L2_en),
        .main_to_l2_data  (main_to_l2_data),
        .l2_to_main_data  (l2_to_main_data),
        .L1_to_L2_en      (L1_to_L2_en),
        .l2_to_l1_data    (l2_to_l1_data),
        .l1_to_l2_data    (l1_to_l2_data),
        .transfer_counter (transfer_counter),
        .transfer_complete(transfer_complete_l2),
        .use_hit_way      (l2_use_hit_way),
        .touch            (L2_touch),
        .hit              (l2_hit),
        .eviction_tag     (l2_eviction_tag),
        .eviction_index   (l2_eviction_index)
    );

    // ------------------------------------------------------------
    // MAIN MEMORY
    main_memory RAM(
        .Clk             (Clk),
        .address         (main_address),
        .L2_to_main_en   (L2_to_main_en),
        .main_to_l2_data (main_to_l2_data),
        .l2_to_main_data (l2_to_main_data),
        .transfer_counter(transfer_counter)
    );

    // ------------------------------------------------------------
    // STATE / REGISTERS
    always_ff @(posedge Clk or negedge reset) begin
        if (!reset) begin
            current_state    <= IDLE;
            transfer_counter <= 3'd0;
            flag             <= 1'b0;
            address_q        <= '0;
            wren_q           <= 1'b0;
            write_data_q     <= 8'd0;
        end
        else begin
            current_state    <= next_state;
            transfer_counter <= next_transfer_counter;
            flag             <= next_flag;

            // Latch the request when it is accepted
            if (current_state == IDLE && en) begin
                address_q    <= address;
                wren_q       <= wren;
                write_data_q <= write_data;
            end
        end
    end

    // ------------------------------------------------------------
    // NEXT STATE + OUTPUT LOGIC
    always_comb begin
        next_state            = current_state;
        next_transfer_counter = transfer_counter;
        next_flag             = flag;

        done                  = 1'b0;
        read_data             = 8'd0;
        main_to_L2_en         = 1'b0;
        L2_to_main_en         = 1'b0;
        L2_to_L1_en           = 1'b0;
        L1_to_controller_en   = 1'b0;
        controller_to_L1_en   = 1'b0;
        L1_to_L2_en           = 1'b0;
        transfer_complete_l1  = 1'b0;
        transfer_complete_l2  = 1'b0;
        L2_touch              = 1'b0;

        case (current_state)
            IDLE: begin
                next_flag = 1'b0;
                if (en)
                    next_state = SEARCH_L1;
            end

            SEARCH_L1: begin
                if (l1_hit)
                    next_state = L1_HIT;
                else
                    next_state = SEARCH_L2;
            end

            L1_HIT: begin
                done = 1'b1;
                if (wren_q) begin
                    controller_to_L1_en = 1'b1;     // write 1 byte, L1 sets dirty
                end
                else begin
                    L1_to_controller_en = 1'b1;
                    read_data           = l1_to_controller_data;
                end
                next_state = IDLE;
            end

            SEARCH_L2: begin
                if (l2_hit)
                    next_state = L2_HIT;
                else
                    next_state = MAIN_MEMORY_ACCESS;   // with flag 0
            end

            // Requested line is in L2. Mark it most recently used so the
            // victim handling can never evict it.
            L2_HIT: begin
                L2_touch = 1'b1;
                if (current_l1_tag_entry.valid && current_l1_tag_entry.dirty)   //cache block stored in L1 must evicted + writeback has to be carried out
                    next_state = SEARCH_L2_L1_VICTIM;
                else
                    next_state = REFILL_L1;
            end

            // l2_address = victim address here
				// L2 is inclusive of L1, so a dirty L1 victim is always present in L2 and this
				// search should always hit. (Inclusion holds because L1's index bits are a subset
				// of L2's and L2_HIT touches the requested line, so L2 never evicts a line L1 holds.)
				// The miss branch below is only a precaution in case inclusion is ever broken.
            SEARCH_L2_L1_VICTIM: begin
                if (l2_hit) begin
                    next_state = WRITEBACK_L1;
                end
                else begin
                    next_flag  = 1'b1;
                    next_state = MAIN_MEMORY_ACCESS;
                end
            end

            // L2 replacement slot is visible on l2_eviction_tag
            MAIN_MEMORY_ACCESS: begin
                if (l2_eviction_tag.dirty)
                    next_state = WRITEBACK_L2;
                else if (flag)
                    next_state = WRITEBACK_L1;
                else
                    next_state = REFILL_L2;
            end

            WRITEBACK_L2: begin
                L2_to_main_en = 1'b1;
                if (transfer_counter < LAST_BEAT) begin
                    next_transfer_counter = transfer_counter + 3'd1;
                end
                else begin
                    next_transfer_counter = 3'd0;
                    if (flag)
                        next_state = WRITEBACK_L1;
                    else
                        next_state = REFILL_L2;
                end
            end

            REFILL_L2: begin
                main_to_L2_en = 1'b1;
                if (transfer_counter < LAST_BEAT) begin
                    next_transfer_counter = transfer_counter + 3'd1;
                end
                else begin
                    transfer_complete_l2  = 1'b1;      // L2: tag, valid=1, dirty=0
                    next_transfer_counter = 3'd0;
                    next_state            = L2_HIT;
                end
            end

            WRITEBACK_L1: begin
                L1_to_L2_en = 1'b1;
                if (transfer_counter < LAST_BEAT) begin
                    next_transfer_counter = transfer_counter + 3'd1;
                end
                else begin
                    transfer_complete_l2  = 1'b1;      // L2: tag, valid=1, dirty=1
                    next_transfer_counter = 3'd0;
                    next_flag             = 1'b0;
                    next_state            = REFILL_L1;
                end
            end

            REFILL_L1: begin
                L2_to_L1_en = 1'b1;
                if (transfer_counter < LAST_BEAT) begin
                    next_transfer_counter = transfer_counter + 3'd1;
                end
                else begin
                    transfer_complete_l1  = 1'b1;      // L1: tag, valid=1, dirty=0
                    next_transfer_counter = 3'd0;
                    next_state            = L1_HIT;
                end
            end

            default: begin
                next_state            = IDLE;
                next_transfer_counter = 3'd0;
                next_flag             = 1'b0;
            end
        endcase
    end
    // ------------------------------------------------------------
    // ADDRESS / WAY SELECTION
    // While flag=1 (victim handling) L2 keeps looking at the victim's
    // address through MAIN_MEMORY_ACCESS and WRITEBACK_L2 as well.
    logic victim_phase;
    assign victim_phase = (current_state == SEARCH_L2_L1_VICTIM) || (current_state == WRITEBACK_L1) || (flag && (current_state == MAIN_MEMORY_ACCESS ||
                                    current_state == WRITEBACK_L2));

    always_comb begin
        if (victim_phase)
            l2_address = {current_l1_tag_entry.tag, l1_index_bits, {L1_OFFSET_WIDTH{1'b0}}};
        else
            l2_address = address_q;

        if (current_state == WRITEBACK_L2)
            main_address = {l2_eviction_tag.tag, l2_eviction_index, {L2_OFFSET_WIDTH{1'b0}}};
        else
            main_address = address_q;

        // Which L2 way is used:
        //   REFILL_L1               -> the way holding the requested line (hit way)
        //   WRITEBACK_L1,(flag=0) -> the way holding the victim (hit way)
        //   WRITEBACK_L1,(flag=1) -> L2's replacement way (victim is not in L2)
        //   REFILL_L2 / WRITEBACK_L2  -> L2's replacement way
        l2_use_hit_way = (current_state == REFILL_L1) || (current_state == WRITEBACK_L1 && !flag);
    end

endmodule