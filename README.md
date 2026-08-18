# 2-Level Cache Controller

A SystemVerilog RTL implementation of a two-level cache hierarchy with a write-back policy and LRU-based replacement.

## Overview

This project implements a two-level cache system consisting of:

- **L1 Cache:** Direct-mapped cache
- **L2 Cache:** 2-way set-associative cache
- **Main Memory:** Behavioral memory model
- **Cache Controller:** FSM-based controller coordinating data movement between L1, L2, and main memory

The cache hierarchy uses a **write-back policy** with dirty bits and supports cache-line transfers using a 128-bit data bus.

```text
              CPU
               │
               ▼
        ┌─────────────┐
        │ L1 Cache    │
        │ Direct Mapped│
        │   1 KB      │
        └──────┬──────┘
               │
               ▼
        ┌─────────────┐
        │ L2 Cache    │
        │ 2-Way Set   │
        │ Associative │
        │    8 KB     │
        └──────┬──────┘
               │
               ▼
        ┌─────────────┐
        │ Main Memory │
        │    64 KB    │
        └─────────────┘
