`timescale 1ns/1ps

// Self-checking testbench for cache_controller.
// Compile order: cache_pkg, main_memory, L1_cache, L2_cache, cache_controller, this file.
//
// Idea: the DUT is treated as a plain byte-addressable memory. Every write updates a
// reference model (associative array), every read is compared against it.
// Directed tests force each controller path, then a random test hammers a small set of
// conflicting addresses, then a final sweep re-reads everything that was ever touched.

module tb_cache_controller;
    import cache_pkg::*;

    // ------------------------------------------------------------
    // Settings
    localparam int CLK_PERIOD     = 10;
    localparam int TIMEOUT_CYCLES = 300;
    localparam int N_RANDOM       = 5000;
    // If main_memory is smaller than the full address space, lower this.
    localparam int MEM_ADDR_BITS  = ADDR_WIDTH;

    localparam logic [ADDR_WIDTH-1:0] ONE       = 1;
    localparam logic [ADDR_WIDTH-1:0] S1        = ONE << (ADDR_WIDTH - L1_TAG_WIDTH); // same L1 index, new L1 tag
    localparam logic [ADDR_WIDTH-1:0] S2        = ONE << (ADDR_WIDTH - L2_TAG_WIDTH); // same L2 set,  new L2 tag
    localparam logic [ADDR_WIDTH-1:0] ADDR_MASK = {ADDR_WIDTH{1'b1}} >> (ADDR_WIDTH - MEM_ADDR_BITS);

    // ------------------------------------------------------------
    // DUT
    logic                  Clk = 1'b0;
    logic                  reset;
    logic                  wren, en;
    logic [ADDR_WIDTH-1:0] address;
    logic [7:0]            write_data, read_data;
    logic                  done;

    cache_controller dut (
        .Clk       (Clk),
        .reset     (reset),
        .wren      (wren),
        .en        (en),
        .address   (address),
        .write_data(write_data),
        .read_data (read_data),
        .done      (done)
    );

    always #(CLK_PERIOD/2) Clk = ~Clk;

    // ------------------------------------------------------------
    // Scoreboard
    logic [7:0] model [bit [ADDR_WIDTH-1:0]];
    int  errors  = 0;
    int  checks  = 0;
    int  x_reads = 0;      // reads of never-written addresses that returned X
    bit  verbose = 1'b1;

    // Address builder: k1 steps the L1 tag, k2 steps the L2 tag,
    // set picks a different line index, off is the byte inside the line.
    function automatic logic [ADDR_WIDTH-1:0] mk(input int k1, input int k2,
                                                 input int set, input int off);
        logic [ADDR_WIDTH-1:0] a;
        a = k1*S1 + k2*S2 + set*LINE_SIZE + off;
        return a & ADDR_MASK;
    endfunction

    // One access: drive on negedge, sample on the negedge where done=1.
    // en is dropped in the done cycle, so the FSM does not restart.
    task automatic access(input bit is_write, input logic [ADDR_WIDTH-1:0] a, input logic [7:0] d);
        int cycles = 0;
        logic [7:0] got;

        @(negedge Clk);
        address    = a;
        wren       = is_write;
        write_data = d;
        en         = 1'b1;

        forever begin
            @(negedge Clk);
            cycles++;
            if (done) break;
            if (cycles > TIMEOUT_CYCLES)
                $fatal(1, "TIMEOUT: no done after %0d cycles (addr=%h, %s), state=%s",
                       TIMEOUT_CYCLES, a, is_write ? "WR" : "RD", dut.current_state.name());
        end

        got = read_data;
        en  = 1'b0;
        checks++;

        if (is_write) begin
            model[a] = d;
        end
        else if (model.exists(a)) begin
            if (got !== model[a]) begin
                errors++;
                $error("MISMATCH addr=%h expected=%h got=%h", a, model[a], got);
            end
        end
        else if ($isunknown(got)) begin
            x_reads++;                 // memory never initialised there; not checkable
        end
        else begin
            model[a] = got;            // first read: learn the value, check it later
        end

        if (verbose)
            $display("%8t  %s addr=%h data=%h  (%0d cycles)", $time,
                     is_write ? "WR" : "RD", a, is_write ? d : got, cycles);
    endtask

    task automatic wr(input logic [ADDR_WIDTH-1:0] a, input logic [7:0] d);
        access(1'b1, a, d);
    endtask

    task automatic rd(input logic [ADDR_WIDTH-1:0] a);
        access(1'b0, a, 8'h00);
    endtask

    // ------------------------------------------------------------
    // Monitors
    logic done_q;
    always @(posedge Clk) begin
        done_q <= done;
        if (reset && done && done_q) begin
            errors++;
            $error("done was high for more than one cycle");
        end
    end

    // Path coverage: how often each state was visited
    int state_cnt [string];
    int mm_flag_cnt = 0;      // MAIN_MEMORY_ACCESS entered with flag=1 (L1 victim not in L2)
    always @(posedge Clk) begin
        if (reset) begin
            state_cnt[dut.current_state.name()]++;
            if (dut.current_state.name() == "MAIN_MEMORY_ACCESS" && dut.flag)
                mm_flag_cnt++;
        end
    end

    // ------------------------------------------------------------
    // Directed tests
    task automatic directed();
        logic [ADDR_WIDTH-1:0] x, y, a0, a1, a2, a3;

        $display("\n--- T1: cold miss, L1 hit, write hit");
        x = mk(0,0,1,0);
        rd(x);               // L1 miss, L2 miss
        rd(x);               // L1 hit
        wr(x, 8'hA5);        // L1 write hit
        rd(x);

        $display("\n--- T2: L1 miss, L2 hit, L1 victim clean");
        x = mk(0,0,2,0);
        y = mk(1,0,2,0);    // same L1 index as x
        rd(x);
        rd(y);               // evicts clean x from L1, x stays in L2
        rd(x);               // L1 miss, L2 hit

        $display("\n--- T3: L1 miss, L2 hit, L1 victim dirty and present in L2");
        x = mk(0,0,3,0);
        y = mk(1,0,3,0);
        rd(x);
        rd(y);
        wr(y, 8'h5A);        // y dirty in L1
        rd(x);               // victim y written back to L2
        rd(y);               // must return 5A from L2

        $display("\n--- T4: same L2 set, dirty lines forced out to main memory");
        a0 = mk(0,0,4,0);
        a1 = mk(0,1,4,0);
        a2 = mk(0,2,4,0);
        a3 = mk(0,3,4,0);
        wr(a0, 8'h11);
        wr(a1, 8'h22);
        wr(a2, 8'h33);       // third line in a 2-way set: evicts one
        wr(a3, 8'h44);
        rd(a0); rd(a1); rd(a2); rd(a3);
        rd(a3); rd(a2); rd(a1); rd(a0);

        $display("\n--- T5: every byte of a line, then evict and read back");
        for (int i = 0; i < LINE_SIZE; i++)
            wr(mk(0,0,5,i), 8'(i + 1));
        rd(mk(0,1,5,0));
        rd(mk(0,2,5,0));
        for (int i = 0; i < LINE_SIZE; i++)
            rd(mk(0,0,5,i));
    endtask

    // ------------------------------------------------------------
    task automatic random_test();
        logic [ADDR_WIDTH-1:0] a;
        $display("\n--- Random test (%0d accesses)", N_RANDOM);
        verbose = 1'b0;
        for (int n = 0; n < N_RANDOM; n++) begin
            a = mk($urandom_range(0,2), $urandom_range(0,3),
                   $urandom_range(0,3), $urandom_range(0,LINE_SIZE-1));
            if ($urandom_range(0,1)) wr(a, 8'($urandom_range(0,255)));
            else                     rd(a);
        end
        verbose = 1'b1;
    endtask

    task automatic sweep();
        logic [ADDR_WIDTH-1:0] keys [$];
        $display("\n--- Final sweep over %0d touched addresses", model.num());
        verbose = 1'b0;
        foreach (model[k]) keys.push_back(k);
        foreach (keys[i])  rd(keys[i]);
        verbose = 1'b1;
    endtask

    // ------------------------------------------------------------
    initial begin
        reset      = 1'b0;
        en         = 1'b0;
        wren       = 1'b0;
        address    = '0;
        write_data = '0;

        repeat (4) @(posedge Clk);   // caches use a synchronous clear, so the clock must run
        @(negedge Clk);
        reset = 1'b1;
        repeat (2) @(negedge Clk);

        directed();
        random_test();
        sweep();

        $display("\n================ SUMMARY ================");
        $display("accesses checked : %0d", checks);
        $display("errors           : %0d", errors);
        $display("X reads skipped  : %0d", x_reads);
        $display("MAIN_MEMORY_ACCESS with flag=1 : %0d", mm_flag_cnt);
        foreach (state_cnt[s])
            $display("  %-22s %0d", s, state_cnt[s]);
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL");
        $finish;
    end

endmodule