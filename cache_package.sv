package cache_pkg;
    parameter int ADDR_WIDTH  = 30;
    parameter int BUS_WIDTH   = 128;
    parameter int LINE_SIZE   = 64;

    parameter int L1_CACHE_SIZE = 4*1024;
    parameter int L2_CACHE_SIZE = 512*1024;

    parameter int L1_OFFSET_WIDTH = $clog2(LINE_SIZE);
    parameter int L1_INDEX_WIDTH  = $clog2(L1_CACHE_SIZE/LINE_SIZE);
    parameter int L1_TAG_WIDTH    = ADDR_WIDTH - L1_INDEX_WIDTH - L1_OFFSET_WIDTH;

    parameter int L2_OFFSET_WIDTH = $clog2(LINE_SIZE);
    parameter int L2_INDEX_WIDTH  = $clog2(L2_CACHE_SIZE/(LINE_SIZE*2));
    parameter int L2_TAG_WIDTH    = ADDR_WIDTH - L2_INDEX_WIDTH - L2_OFFSET_WIDTH;

    typedef struct packed {
        logic valid;
        logic dirty;
        logic [L1_TAG_WIDTH-1:0] tag;
    } l1_tag_entry;

    typedef struct packed {
        logic valid;
        logic dirty;
        logic [L2_TAG_WIDTH-1:0] tag;
    } l2_tag_entry;
endpackage