const std = @import("std");
const types = @import("types.zig");
const Collector = @import("collector.zig").Collector;

var global_allocator: std.mem.Allocator = undefined;

/// Set global_allocator to c_allocator (malloc/free). Must be called once before
/// any other vmmap_* function. Uses callconv(.c) so the symbol is callable from
/// C / Objective-C / any C FFI — this is how the React Native bridge will call it.
export fn vmmap_allocator_init() callconv(.c) void {
    global_allocator = std.heap.c_allocator;
}

/// Heap-allocate a Collector targeting `pid`, polling every `interval_ms`.
/// Returns null on allocation failure. c_int/c_uint give stable C ABI types;
/// ?*Collector is an optional pointer — null at the C boundary means "failed".
export fn vmmap_collector_create(pid: c_int, interval_ms: c_uint) callconv(.c) ?*Collector {
    const collector = global_allocator.create(Collector) catch return null;
    collector.* = Collector.init(global_allocator, @intCast(pid), interval_ms);
    return collector;
}

/// Free a Collector and all its snapshots. Safe to call with null (no-op).
/// `if (collector) |c|` unwraps the optional — body only runs when non-null.
export fn vmmap_collector_destroy(collector: ?*Collector) callconv(.c) void {
    if (collector) |c| {
        c.deinit();
        global_allocator.destroy(c);
    }
}

/// Spawn the background collection thread. Returns -1 on failure (thread spawn
/// error or null collector). The thread loops: spawn vmmap, parse, append snapshot,
/// sleep interval_ms, repeat — until vmmap_collector_stop is called.
export fn vmmap_collector_start(collector: ?*Collector) callconv(.c) void {
    if (collector) |c| {
        c.start() catch return -1;
    }
    return -1;
}

/// Signal the collection thread to stop and join it. Blocks until the thread
/// finishes its current snapshot (if any). Safe to call with null.
export fn vmmap_collector_stop(collector: ?*Collector) callconv(.c) void {
    if (collector) |c| {
        c.stop();
    }
}

/// Return the number of snapshots collected so far. Returns 0 for null collector.
export fn vmmap_collector_snapshot_count(collector: ?*Collector) callconv(.c) c_uint {
    if (collector) |c| {
        return @intCast(c.snapshots.items.len);
    }
    return 0;
}

/// Serialize all snapshots to a JSON string: [{timestamp_ms, regions: [...]}, ...].
/// Returns a null-terminated heap string the caller must free with vmmap_free_string.
/// Returns null on serialization failure or null collector.
export fn vmmap_collector_get_snapshots_json(collector: ?*Collector) callconv(.c) ?[*:0]u8 {
    if (collector) |c| {
        var json: std.ArrayList(u8) = std.ArrayList(u8).init(global_allocator);
        var writer = json.writer();

        writer.writeAll("[") catch return null;

        for (c.snapshots.items, 0..) |snapshot, i| {
            if (i > 0) writer.writeAll(",") catch return null;
            writeSnapshotJson(writer, snapshot) catch return null;
        }

        writer.writeAll("]") catch return null;

        // Null-terminate for C
        json.append(0) catch return null;
        return @ptrCast(json.items.ptr);
    }

    return null;
}

/// Write a single snapshot as JSON: {timestamp_ms, regions: [{type, start, end, vsize, rsize}, ...]}.
/// `anytype` for writer lets this work with any std.io.Writer — here it's ArrayList(u8).writer().
fn writeSnapshotJson(writer: anytype, snapshot: types.Snapshot) !void {
    for (snapshot.regions, 0..) |region, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("{{\"type\":\"{s}\",\"start\":{d},\"end\":{d},\"vsize\":{d},\"rsize\":{d}}}", .{
            region.region_type,
            region.start_addr,
            region.end_addr,
            region.virtual_size,
            region.resident_size,
        });
    }
    try writer.writeAll("]}");
}

/// Free a null-terminated string returned by vmmap_collector_get_snapshots_json.
/// Walks to the sentinel to reconstruct the slice length, then frees.
/// Safe to call with null. Caller must not use the pointer after this.
export fn vmmap_free_string(ptr: ?[*:0]u8) callconv(.C) void {
    if (ptr) |p| {
        var len: usize = 0;
        while (p[len] != 0) : (len += 1) {}
        global_allocator.free(p[0 .. len + 1]);
    }
}
