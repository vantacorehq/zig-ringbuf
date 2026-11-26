const std = @import("std");
const Atomic = std.atomic.Value;
const Allocator = std.mem.Allocator;

pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    if (comptime !std.math.isPowerOfTwo(capacity)) {
        @compileError("capacity must be a power of two");
    }
    return struct {
        const Self = @This();
        const mask: usize = capacity - 1;

        buffer: [capacity]T = undefined,
        head: Atomic(usize) = Atomic(usize).init(0),
        tail: Atomic(usize) = Atomic(usize).init(0),

        pub fn init() Self {
            return .{};
        }

        pub fn push(self: *Self, value: T) bool {
            const head = self.head.load(.unordered);
            const next = (head + 1) & mask;
            if (next == self.tail.load(.acquire)) return false;
            self.buffer[head] = value;
            self.head.store(next, .release);
            return true;
        }

        pub fn pop(self: *Self) ?T {
            const tail = self.tail.load(.unordered);
            if (tail == self.head.load(.acquire)) return null;
            const value = self.buffer[tail];
            self.tail.store((tail + 1) & mask, .release);
            return value;
        }

        pub fn len(self: *const Self) usize {
            const h = self.head.load(.unordered);
            const t = self.tail.load(.unordered);
            return (h -% t) & mask;
        }
    };
}

pub const Arena = struct {
    underlying: Allocator,
    buffer: []u8,
    offset: usize = 0,

    pub fn init(u: Allocator, size: usize) !Arena {
        return .{ .underlying = u, .buffer = try u.alloc(u8, size) };
    }

    pub fn deinit(self: *Arena) void {
        self.underlying.free(self.buffer);
        self.* = undefined;
    }

    pub fn reset(self: *Arena) void {
        self.offset = 0;
    }

    pub fn allocator(self: *Arena) Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .free = free, .remap = remap } };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
        const self: *Arena = @ptrCast(@alignCast(ctx));
        const align_amt = alignment.toByteUnits();
        const aligned = std.mem.alignForward(usize, self.offset, align_amt);
        if (aligned + len > self.buffer.len) return null;
        const ptr = self.buffer.ptr + aligned;
        self.offset = aligned + len;
        return ptr;
    }

    fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        return false;
    }

    fn free(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize) void {}

    fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
        return null;
    }
};

test "ring basic" {
    var rb = RingBuffer(u32, 8).init();
    try std.testing.expect(rb.push(10));
    try std.testing.expect(rb.push(20));
    try std.testing.expectEqual(@as(?u32, 10), rb.pop());
    try std.testing.expectEqual(@as(?u32, 20), rb.pop());
    try std.testing.expect(rb.pop() == null);
}

test "arena" {
    var arena = try Arena.init(std.testing.allocator, 1024);
    defer arena.deinit();
    const a = arena.allocator();
    const s = try a.alloc(u8, 64);
    @memset(s, 0xAA);
    try std.testing.expect(s[0] == 0xAA);
    arena.reset();
}

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    try out.print("zig-ringbuf ready\n", .{});
    var rb = RingBuffer(u64, 16).init();
    _ = rb.push(42);
    try out.print("popped: {d}\n", .{rb.pop().?});
}
