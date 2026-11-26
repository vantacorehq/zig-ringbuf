const std = @import("std");
const Atomic = std.atomic.Value;
const Allocator = std.mem.Allocator;

/// Lock-free Single-Producer Single-Consumer ring buffer.
/// Capacity must be a power of two.
pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    comptime {
        if (!std.math.isPowerOfTwo(capacity)) {
            @compileError("RingBuffer capacity must be a power of two");
        }
    }

    return struct {
        const Self = @This();
        const mask: usize = capacity - 1;

        buffer: [capacity]T = undefined,
        head: Atomic(usize) = Atomic(usize).init(0), // write index
        tail: Atomic(usize) = Atomic(usize).init(0), // read index

        pub fn init() Self {
            return .{};
        }

        /// Returns false if the buffer is full.
        pub fn push(self: *Self, value: T) bool {
            const head = self.head.load(.unordered);
            const next = (head + 1) & mask;
            if (next == self.tail.load(.acquire)) {
                return false; // full
            }
            self.buffer[head] = value;
            self.head.store(next, .release);
            return true;
        }

        /// Returns null if the buffer is empty.
        pub fn pop(self: *Self) ?T {
            const tail = self.tail.load(.unordered);
            if (tail == self.head.load(.acquire)) {
                return null; // empty
            }
            const value = self.buffer[tail];
            self.tail.store((tail + 1) & mask, .release);
            return value;
        }

        pub fn len(self: *const Self) usize {
            const head = self.head.load(.unordered);
            const tail = self.tail.load(.unordered);
            return (head -% tail) & mask;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.len() == 0;
        }

        pub fn isFull(self: *const Self) bool {
            return self.len() == capacity - 1;
        }
    };
}

/// Simple bump-pointer arena allocator.
/// Extremely fast allocations; free everything at once with `reset` or `deinit`.
pub const Arena = struct {
    underlying: Allocator,
    buffer: []u8,
    offset: usize = 0,

    pub fn init(underlying: Allocator, size: usize) !Arena {
        const buffer = try underlying.alloc(u8, size);
        return .{ .underlying = underlying, .buffer = buffer };
    }

    pub fn deinit(self: *Arena) void {
        self.underlying.free(self.buffer);
        self.* = undefined;
    }

    pub fn reset(self: *Arena) void {
        self.offset = 0;
    }

    pub fn allocator(self: *Arena) Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .free = free } };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *Arena = @ptrCast(@alignCast(ctx));
        const align_mask = @as(usize, 1) << @intCast(ptr_align) - 1;
        const aligned = (self.offset + align_mask) & ~align_mask;
        if (aligned + len > self.buffer.len) return null;
        const ptr = self.buffer.ptr + aligned;
        self.offset = aligned + len;
        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false; // arenas do not support resize
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
        // no-op — free happens only on reset/deinit
    }
};

test "ring buffer basic" {
    var rb = RingBuffer(u32, 8).init();
    try std.testing.expect(rb.push(10));
    try std.testing.expect(rb.push(20));
    try std.testing.expectEqual(@as(?u32, 10), rb.pop());
    try std.testing.expectEqual(@as(?u32, 20), rb.pop());
    try std.testing.expect(rb.pop() == null);
}

test "ring buffer full" {
    var rb = RingBuffer(u8, 4).init();
    try std.testing.expect(rb.push(1));
    try std.testing.expect(rb.push(2));
    try std.testing.expect(rb.push(3));
    try std.testing.expect(!rb.push(4)); // full (capacity-1 usable)
}

test "arena" {
    var arena = try Arena.init(std.testing.allocator, 1024);
    defer arena.deinit();
    const a = arena.allocator();
    const slice = try a.alloc(u8, 100);
    @memset(slice, 0xAA);
    try std.testing.expect(slice[0] == 0xAA);
    arena.reset();
    const slice2 = try a.alloc(u8, 50);
    try std.testing.expect(@intFromPtr(slice2.ptr) == @intFromPtr(slice.ptr));
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("zig-ringbuf — lock-free ring + arena ready\n", .{});

    var rb = RingBuffer(u64, 16).init();
    _ = rb.push(42);
    _ = rb.push(7);
    try stdout.print("popped: {d}\n", .{rb.pop().?});
    try stdout.print("popped: {d}\n", .{rb.pop().?});
}
