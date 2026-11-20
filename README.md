# ⚡ Two-Level Cache Controller

A SystemVerilog cache controller for an L1 + L2 + main memory hierarchy, coordinated by a single FSM.

![SystemVerilog](https://img.shields.io/badge/HDL-SystemVerilog-blue)
![Levels](https://img.shields.io/badge/Cache%20Levels-L1%20%2B%20L2-green)
![Policy](https://img.shields.io/badge/Write%20Policy-Write--Back-orange)
![Replacement](https://img.shields.io/badge/L2%20Replacement-LRU-purple)

---

## Table of Contents

- [Highlights](#highlights)
- [Architecture](#architecture)
- [Program Flow](#program-flow)
- [FSM States](#fsm-states)
- [Parameters](#parameters)
- [Cache Organisation](#cache-organisation)
- [Repository Layout](#repository-layout)
- [Results](#results)


---

## Highlights

- **L1:** direct-mapped, with separate tag and data stores and combinational hit and read
- **L2:** 2-way set associative with LRU replacement
- **Inclusive hierarchy:** L2 is always filled before L1, so an L1 victim is always present in L2
- **Write-back:** data goes to the next level only when a dirty line is evicted
- **4-beat line transfers** over a 128-bit bus
- **Parameterized** address width, bus width, line size and cache sizes

---

## Architecture

<img width="851" height="490" alt="image" src="https://github.com/user-attachments/assets/276520a8-a162-45ac-a389-dd3101493aa7" />

Each link between modules has a data bus and an enable signal: `controller_to_L1_en/data`, `L1_to_controller_en/data`, `L1_to_L2_en/data`, `L2_to_L1_en/data`, `L2_to_main_en/data` and `main_to_L2_en/data`.

| Unit | Role |
|---|---|
| `cache_controller` | The FSM that handles every read and write |
| `L1_CACHE_MEMORY` | Tag store, data store, valid and dirty bits |
| `L2_CACHE_MEMORY` | Tag store, data store, valid, dirty and LRU state per set |
| `MAIN_MEMORY` | Backing store, accessed in 4-beat line transfers |

---

## Program Flow

<img width="637" height="892" alt="image" src="https://github.com/user-attachments/assets/91ff3394-f4ef-4b0c-aff1-cb2b91021c76" />

---

## FSM States

| State | What it does |
|---|---|
| `IDLE` | Waits for a new processor request |
| `SEARCH_L1` | Looks up the address in L1 |
| `L1_HIT` | Returns the L1 data to the processor |
| `SEARCH_L2` | Looks up the address in L2 after an L1 miss |
| `L2_HIT` | L2 hit, the block is promoted to L1 |
| `SEARCH_L2_L1_VICTIM` | Searches L2 for the L1 victim |
| `MAIN_MEMORY_ACCESS` | Fetches the line from main memory |
| `WRITEBACK_L1` | Writes a dirty L1 victim back to L2 |
| `WRITEBACK_L2` | Writes a dirty L2 victim back to main memory |
| `REFILL_L1` | Fills an L1 line |
| `REFILL_L2` | Fills an L2 line |

---

## Parameters

| Parameter | Value | Meaning |
|---|---|---|
| `ADDR_WIDTH` | 16 | Address width in bits |
| `BUS_WIDTH` | 128 | Data bus width in bits |
| `LINE_SIZE` | 64 | Cache line size in bytes |
| `L1_CACHE_SIZE` | 1 KB | L1 capacity |
| `L2_CACHE_SIZE` | 8 KB | L2 capacity |

One line = 4 beats x 128 bits = 512 bits = 64 bytes.

---

## Cache Organisation

Formulas:

- `index bits = log2(number of cache blocks / associativity)`
- `tag bits = address width - index bits - offset bits`

| | L1 | L2 |
|---|---|---|
| Size | 1024 bytes | 8192 bytes |
| Block size | 64 bytes | 64 bytes |
| No. of cache blocks | 16 (16 sets x 1 way) | 128 (64 sets x 2 ways) |
| Index bits | 4 | 6 |
| Offset bits | 6 | 6 |
| Tag bits | 6 | 4 |

### L1 Cache

**Tag store**

| Index | Valid | Dirty | Tag |
|:---:|:---:|:---:|:---:|
| 0 | 1 | 0 | `0x23` |
| ... | 1 | 1 | `0x1C` |
| 15 | | | |

**Data store**

| Index | Beat 0 | Beat 1 | Beat 2 | Beat 3 |
|:---:|:---:|:---:|:---:|:---:|
| 0 | d0 | d1 | d2 | d3 |
| ... | ... | ... | ... | ... |
| 15 | d0 | d1 | d2 | d3 |

### L2 Cache

**Tag store**

| Index | W0 Valid | W0 Dirty | W0 Tag | W1 Valid | W1 Dirty | W1 Tag | LRU |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 0 | 1 | 0 | `0x3` | 1 | 1 | `0xC` | 1 |
| 1 | 1 | 0 | `0x7` | ... | ... | ... | 0 |
| ... | ... | ... | ... | ... | ... | ... | ... |
| 127 | | | | | | | |

**Data store**

| Index | W0 b0 | W0 b1 | W0 b2 | W0 b3 | W1 b0 | W1 b1 | W1 b2 | W1 b3 |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 0 | | | | | | | | |
| ... | | | | | | | | |
| 127 | | | | | | | | |

---

## Repository Layout

```
.
├── rtl/                       # SystemVerilog source
├── Architecture + Notes/      # Testbenches
├── Simulation_Testbenches/    # Testbenches
├── Simulation_Waveforms/      # Detailed Simulation log and multiple simulation waveforms 
└── README.md
```

---

## Results

### Self-checking testbench summary

```
================ SUMMARY ================
accesses checked : 7708
errors           : 0
X reads skipped  : 0
MAIN_MEMORY_ACCESS with flag=1 : 0

  IDLE                   7711
  L1_HIT                 7707
  L2_HIT                 4710
  MAIN_MEMORY_ACCESS     2569
  REFILL_L1              18840
  REFILL_L2              10276
  SEARCH_L1              7708
  SEARCH_L2              4710
  SEARCH_L2_L1_VICTIM    2468
  WRITEBACK_L1           9872
  WRITEBACK_L2           6820

RESULT: PASS
```

| Metric | Value |
|---|---|
| Accesses checked | 7708 |
| Errors | 0 |
| X reads skipped | 0 |
| Result | PASS |

### Waveforms

<img width="1917" height="866" alt="waveform3 2" src="https://github.com/user-attachments/assets/e210bcd3-5b70-4cf0-a097-1373e52fafb2" />
<img width="1912" height="857" alt="waveform5 1" src="https://github.com/user-attachments/assets/4097c0e5-09e7-40b8-b922-b423e5300bb5" />

---

## Author

Hadia Naveed, National University of Sciences and Technology
