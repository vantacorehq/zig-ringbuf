<p align="center">
  <img src="https://img.shields.io/badge/LANGUAGE-Zig-F7A41D?style=for-the-badge&logo=zig" alt="Language">
  <img src="https://img.shields.io/badge/DEPENDENCIES-ZERO-333333?style=for-the-badge" alt="Deps">
  <img src="https://img.shields.io/badge/STYLE-LOCK--FREE-FFFFFF?style=for-the-badge" alt="Style">
</p>

# zig-ringbuf

**Lock-free ring buffer + arena allocator in pure Zig.**  
No hidden costs. Full control. Comptime power.

## Why this is hardcore

- Explicit memory management — no GC, no hidden allocations.
- Lock-free SPSC ring buffer using atomics only.
- Custom arena allocator for ultra-fast bump allocation.
- Heavy use of `comptime` for zero-cost abstractions.

## Components

### 1. Lock-free Ring Buffer (SPSC)

```zig
var rb = RingBuffer(u64, 1024).init();
try rb.push(42);
const v = rb.pop(); // optional
```

- Single Producer / Single Consumer
- Wait-free on the fast path
- Power-of-two capacity for cheap masking

### 2. Arena Allocator

```zig
var arena = Arena.init(std.heap.page_allocator);
defer arena.deinit();
const ptr = try arena.allocator().alloc(u8, 128);
```

- Bump pointer, O(1) alloc
- Free-all in one shot
- Perfect for request / frame lifetimes

## Build & test

```bash
zig build test
zig build          # produces the example binary
```

## Guarantees

| Property              | Guarantee                                      |
|-----------------------|------------------------------------------------|
| Dependencies          | Zero (only std)                                |
| Thread-safety         | SPSC ring is lock-free                         |
| Allocation cost       | Arena: O(1) bump                               |
| Hidden allocations    | None                                           |
| Comptime              | Capacity & types resolved at compile time      |

## License

MIT
