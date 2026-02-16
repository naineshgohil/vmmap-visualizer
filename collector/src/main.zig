const std = @import("std");
const types = @import("types.zig");
const Collector = @import("collector.zig").Collector;

var global_allocator: std.mem.Allocator = undefined;
var on_push: *const fn (*const CSnapshot) callconv(.c) void = undefined;

const CResult = extern struct {
    ok: bool,
    error_msg: ?[*:0]const u8 = null,
    ref: ?*anyopaque = null,
};

/// Heap-allocate a Collector targeting `pid`, polling every `interval_ms`.
/// Stores the callback for pushing CSnapshots to the ObjC bridge.
/// Returns CResult with ref pointing to the Collector on success.
export fn vmmap_collector_create(
    pid: c_int,
    interval_ms: c_uint,
    callback: *const fn (*const CSnapshot) callconv(.c) void,
) callconv(.c) CResult {
    std.debug.print("[vmmap] create: pid={d} interval={d}ms\n", .{ pid, interval_ms });
    global_allocator = std.heap.c_allocator;
    on_push = callback;
    const collector = global_allocator.create(Collector) catch return .{
        .ok = false,
        .error_msg = "Collector not initialized",
    };
    collector.* = Collector.init(
        global_allocator,
        @intCast(pid),
        interval_ms,
        &onSnapshot,
    );
    return .{ .ok = true, .ref = collector };
}

fn onSnapshot(snapshot: *const types.Snapshot) void {
    std.debug.print("[vmmap] onSnapshot: converting {d} regions\n", .{snapshot.regions.len});
    const result = vmmap_collector_push_snapshot(snapshot);
    if (result.ok) {
        if (result.snapshot) |s| {
            std.debug.print("[vmmap] onSnapshot: pushing to ObjC bridge\n", .{});
            on_push(s);
        }
    } else {
        std.debug.print("[vmmap] onSnapshot: conversion failed: {s}\n", .{result.error_msg orelse "unknown"});
    }
}

/// Free a Collector and all its snapshots. Safe to call with null (no-op).
/// `if (collector) |c|` unwraps the optional — body only runs when non-null.
export fn vmmap_collector_destroy(collector: ?*Collector) callconv(.c) void {
    std.debug.print("[vmmap] destroy\n", .{});
    if (collector) |c| {
        c.deinit();
        global_allocator.destroy(c);
    }
}

/// Spawn the background collection thread. Returns a CResult struct: ok=true on
/// success, ok=false with error_msg on failure (null collector or thread spawn error).
/// The thread loops: spawn vmmap, parse, append snapshot, sleep interval_ms, repeat
/// — until vmmap_collector_stop is called.
export fn vmmap_collector_start(collector: ?*Collector) callconv(.c) CResult {
    std.debug.print("[vmmap] start\n", .{});
    const c = collector orelse return .{
        .ok = false,
        .error_msg = "Collector not initialized",
    };
    c.start() catch return .{
        .ok = false,
        .error_msg = "Failed to spawn collection thread",
    };
    return .{ .ok = true };
}

/// Signal the collection thread to stop and join it. Blocks until the thread
/// finishes its current snapshot (if any). Safe to call with null.
export fn vmmap_collector_stop(collector: ?*Collector) callconv(.c) void {
    std.debug.print("[vmmap] stop\n", .{});
    if (collector) |c| {
        c.stop();
    }
}

/// Return the number of snapshots collected so far. Returns 0 for null collector.
/// Note: with push-based delivery, this is mainly useful for debugging.
export fn vmmap_collector_snapshot_count(collector: ?*Collector) callconv(.c) c_uint {
    if (collector) |c| {
        return @intCast(c.snapshots.items.len);
    }
    return 0;
}

const CRegion = extern struct {
    region_type: [*:0]const u8,
    start_addr: u64,
    end_addr: u64,
    virtual_size: u64,
    resident_size: u64,
};

const CSnapshot = extern struct {
    timestamp_ms: i64,
    regions: [*]CRegion,
    region_count: c_uint,
};

const CSnapshotResult = extern struct {
    ok: bool,
    error_msg: ?[*:0]const u8 = null,
    snapshot: ?*CSnapshot = null,
};

/// Convert an internal Zig Snapshot to a C-ABI CSnapshot. Allocates CRegion array
/// and null-terminated copies of region_type strings. Called from the collection
/// thread via onSnapshot callback. Caller receives ownership of the CSnapshot.
export fn vmmap_collector_push_snapshot(snapshot: *const types.Snapshot) callconv(.c) CSnapshotResult {
    std.debug.print("[vmmap] push_snapshot: {d} regions, ts={d}\n", .{ snapshot.regions.len, snapshot.timestamp_ms });
    const regions: []CRegion = global_allocator.alloc(CRegion, snapshot.regions.len) catch return .{
        .ok = false,
        .error_msg = "Regions allocation failed",
    };

    for (snapshot.regions, 0..) |r, i| {
        regions[i] = CRegion{
            .region_type = toCString(r.region_type) orelse return .{
                .ok = false,
                .error_msg = "String allocation failed",
            },
            .start_addr = r.start_addr,
            .end_addr = r.end_addr,
            .resident_size = r.resident_size,
            .virtual_size = r.virtual_size,
        };
    }

    const c_snapshot = global_allocator.create(CSnapshot) catch return .{
        .ok = false,
        .error_msg = "Snapshot allocation failed",
    };

    c_snapshot.* = .{
        .timestamp_ms = snapshot.timestamp_ms,
        .regions = regions.ptr,
        .region_count = @intCast(regions.len),
    };

    return .{ .ok = true, .snapshot = c_snapshot };
}

fn toCString(slice: []const u8) ?[*:0]const u8 {
    const buf = global_allocator.allocSentinel(u8, slice.len, 0) catch return null;
    @memcpy(buf, slice);
    return buf;
}

/// Free a null-terminated heap string. Walks to the sentinel to reconstruct
/// the slice length, then frees. Safe to call with null.
export fn vmmap_free_string(ptr: ?[*:0]u8) callconv(.c) void {
    if (ptr) |p| {
        var len: usize = 0;
        while (p[len] != 0) : (len += 1) {}
        global_allocator.free(p[0 .. len + 1]);
    }
}
