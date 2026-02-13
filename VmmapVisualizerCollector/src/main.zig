const std = @import("std");
const types = @import("types.zig");

const Collector = struct {
    pid: std.posix.pid_t,
    interval_ms: u32,
    snapshots: std.ArrayList(types.Snapshot),
    running: std.atomic.Value(bool),
    allocator: std.mem.Allocator,
};

var global_allocator: std.mem.Allocator = undefined;

/// Initialize the global allocator used by all collector operations.
/// Exported with callconv(.c) so this function uses the C calling convention
/// (how arguments are passed in registers/stack, return values, caller vs callee
/// saved registers).
/// This makes the function callable from C, Objective-C, or any
/// language with a C FFI — which is how React Native's native module bridge will
/// invoke it.
export fn allocator_init() callconv(.c) void {
    global_allocator = std.heap.c_allocator;
}

/// Heap-allocate a new Collector for the given process. Returns null on
/// allocation failure. Uses c_int/c_uint so the C ABI has stable, portable
/// integer types. The ?*Collector return is an optional pointer — null at the
/// C boundary, avoiding the need for a separate error code.
export fn collector_create(pid: c_int, interval_ms: c_uint) callconv(.c) ?*Collector {
    const collector = global_allocator.create(Collector) catch return null;
    collector.* = .{
        .pid = @intCast(pid),
        .interval_ms = interval_ms,
        .snapshots = .{},
        .running = std.atomic.Value(bool).init(false),
        .allocator = global_allocator,
    };
    return collector;
}

/// Free a Collector and its snapshot list. Accepts an optional pointer so
/// callers can safely pass null (e.g. if collector_create failed). The
/// `if (collector) |c|` unwraps the optional — only runs the body when non-null.
export fn collector_destroy(collector: ?*Collector) callconv(.c) void {
    if (collector) |c| {
        c.snapshots.deinit(global_allocator);
        global_allocator.destroy(c);
    }
}

/// Signal the collector to begin capturing snapshots. Sets the atomic `running`
/// flag to true with .release ordering — guarantees all prior writes (e.g. pid,
/// interval_ms) are visible to the collection thread before it sees running=true.
export fn collector_start(collector: ?*Collector) callconv(.c) void {
    if (collector) |c| {
        c.running.store(true, .release);
        // TODO: spawn collection thread
    }
}

/// Signal the collection thread to stop. The thread checks `running` each
/// iteration and will exit its loop once it loads false.
export fn collector_stop(collector: ?*Collector) callconv(.c) void {
    if (collector) |c| {
        c.running.store(false, .release);
    }
}

/// Return how many snapshots have been collected so far. Returns 0 for a null
/// collector. Uses c_uint so the return type is a fixed-width C unsigned int.
export fn collector_snapshot_count(collector: ?*Collector) callconv(.c) c_uint {
    if (collector) |c| {
        return @intCast(c.snapshots.items.len);
    }

    return 0;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: vmmap_collector <pid>\n", .{});
        return;
    }

    const pid = std.fmt.parseInt(std.posix.pid_t, args[1], 10) catch {
        std.debug.print("Invalid PID: {s}\n", .{args[1]});
        return;
    };

    const collector_mod = @import("collector.zig");
    var collector = collector_mod.Collector.init(allocator, pid, 1000);
    defer collector.deinit();

    try collector.start();

    std.Thread.sleep(3 * std.time.ns_per_s);

    collector.stop();

    std.debug.print("Collected {d} snapshots\n", .{collector.snapshots.items.len});
}
