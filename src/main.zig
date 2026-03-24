const builtin = @import("builtin");
const std = @import("std");
const Io = std.Io;

const _09_03_alignment = @import("_09_03_alignment");
const config = @import("config");

pub const CACHE_LINE_SIZE_OVERRIDE: ?usize =
    if (@hasDecl(config, "cache_line"))
        config.cache_line
    else
        null;

pub const CACHE_LINE_SIZE: usize = CACHE_LINE_SIZE_OVERRIDE orelse switch (builtin.cpu.arch) {
    .aarch64 => 128,
    else => 64,
};

// Validate
comptime {
    if (CACHE_LINE_SIZE != 64 and CACHE_LINE_SIZE != 128) {
        @compileError("CACHE_LINE_SIZE must be 64 or 128 bytes.");
    }
}

pub fn main(init: std.process.Init) !void {
    // Prints to stderr, unbuffered, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);
    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }

    // In order to do I/O operations need an `Io` instance.
    const io = init.io;

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try _09_03_alignment.printAnotherMessage(stdout_writer);

    try stdout_writer.flush(); // Don't forget to flush!

    // Gets the cache_line from config
    try stdout_writer.print("\nCache Line Override: {?}\n", .{CACHE_LINE_SIZE_OVERRIDE});
    try stdout_writer.print("Cache Line: {}\n\n", .{CACHE_LINE_SIZE});
    try stdout_writer.flush();

    // Each entry occupies exactly one 64-byte cache line.
    // Writes by different CPU cores do not cause false sharing.
    const PerCoreCounter = extern struct {
        value: u64,
        //_pad: [56]u8, // explicit padding to reach Full Cache Line Size
        _pad: [CACHE_LINE_SIZE - @sizeOf(u64)]u8,
    };

    comptime {
        std.debug.assert(@sizeOf(PerCoreCounter) == CACHE_LINE_SIZE);
    }

    const counters: [128]PerCoreCounter align(CACHE_LINE_SIZE) = undefined;
    _ = counters;

    // Delegating the creation to a function
    const AnyCoreCounter = CacheAlignedWithPadding(u32);

    comptime {
        std.debug.assert(@sizeOf(AnyCoreCounter) == CACHE_LINE_SIZE);
    }

    const any_counters: [128]AnyCoreCounter align(CACHE_LINE_SIZE) = undefined;
    _ = any_counters;

    // Another delegation
    const MyCoreCounter = CacheAligned(u64);

    comptime {
        std.debug.assert(@sizeOf(MyCoreCounter) == CACHE_LINE_SIZE);
    }

    const my_counters: [128]MyCoreCounter align(CACHE_LINE_SIZE) = undefined;
    _ = my_counters;
}

pub fn CacheAlignedWithPadding(comptime T: type) type {
    return extern struct {
        value: T,
        _pad: [CACHE_LINE_SIZE - @sizeOf(T)]u8,
    };
}

pub fn CacheAligned(comptime T: type) type {
    return extern struct {
        value: T align(CACHE_LINE_SIZE),
    };
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    try std.testing.fuzz({}, testOne, .{});
}

fn testOne(context: void, smith: *std.testing.Smith) !void {
    _ = context;
    // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!

    const gpa = std.testing.allocator;
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(gpa);
    while (!smith.eos()) switch (smith.value(enum { add_data, dup_data })) {
        .add_data => {
            const slice = try list.addManyAsSlice(gpa, smith.value(u4));
            smith.bytes(slice);
        },
        .dup_data => {
            if (list.items.len == 0) continue;
            if (list.items.len > std.math.maxInt(u32)) return error.SkipZigTest;
            const len = smith.valueRangeAtMost(u32, 1, @min(32, list.items.len));
            const off = smith.valueRangeAtMost(u32, 0, @intCast(list.items.len - len));
            try list.appendSlice(gpa, list.items[off..][0..len]);
            try std.testing.expectEqualSlices(
                u8,
                list.items[off..][0..len],
                list.items[list.items.len - len ..],
            );
        },
    };
}
