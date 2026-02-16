const std = @import("std");
const types = @import("types.zig");
const parser = @import("parser.zig");

/// Manages periodic vmmap snapshot collection for a target process.
/// Runs a background thread that spawns `vmmap <pid>` at a fixed interval,
/// parses the output, appends Snapshots to an ArrayList, and pushes each
/// new snapshot to the caller via on_snapshot callback.
pub const Collector = struct {
    pid: std.posix.pid_t,
    interval_ms: u32,
    snapshots: std.ArrayList(types.Snapshot),
    running: std.atomic.Value(bool),
    allocator: std.mem.Allocator,
    thread: ?std.Thread,
    on_snapshot: ?*const fn (*const types.Snapshot) void,

    /// Construct a Collector on the stack. No heap allocation or threads yet —
    /// just stores config, initializes the snapshot list, and registers the
    /// on_snapshot callback. Call start() to begin collecting.
    pub fn init(
        allocator: std.mem.Allocator,
        pid: std.posix.pid_t,
        interval_ms: u32,
        on_snapshot: ?*const fn (*const types.Snapshot) void,
    ) Collector {
        return .{
            .pid = pid,
            .interval_ms = interval_ms,
            .snapshots = .{},
            .running = std.atomic.Value(bool).init(false),
            .allocator = allocator,
            .thread = null,
            .on_snapshot = on_snapshot,
        };
    }

    /// Stop collection if running, free every snapshot's region data, then free
    /// the snapshot list itself. Mirrors init() — caller must call deinit() when
    /// done to avoid leaking memory.
    pub fn deinit(self: *Collector) void {
        self.stop();
        for (self.snapshots.items) |*snapshots| {
            snapshots.deinit();
        }
        self.snapshots.deinit(self.allocator);
    }

    /// Begin collecting snapshots on a background thread. The .acquire load
    /// checks if already running to prevent spawning duplicate threads. Sets
    /// running=true with .release so the new thread sees all prior field writes
    /// before entering collectionLoop.
    pub fn start(self: *Collector) !void {
        if (self.running.load(.acquire)) return;
        std.debug.print("[vmmap] start: spawning collection thread for pid {d}\n", .{self.pid});
        self.running.store(true, .release);
        self.thread = try std.Thread.spawn(.{}, collectionLoop, .{self});
    }

    /// Signal the collection thread to stop and wait for it to finish. Sets
    /// running=false so collectionLoop exits, then calls join() which blocks
    /// until the thread actually terminates. This ensures no snapshot is
    /// mid-capture when we return — safe to call deinit() after this.
    pub fn stop(self: *Collector) void {
        if (!self.running.load(.acquire)) return;
        std.debug.print("[vmmap] stop: signaling collection thread\n", .{});
        self.running.store(false, .release);

        if (self.thread) |t| {
            t.join();
            self.thread = null;
            std.debug.print("[vmmap] stop: collection thread joined\n", .{});
        }
    }

    /// Background thread entry point. Loops until running is set to false:
    /// capture a snapshot, sleep for interval_ms, repeat. Errors from individual
    /// captures are logged but don't kill the loop — collection continues on the
    /// next tick.
    fn collectionLoop(self: *Collector) void {
        while (self.running.load(.acquire)) {
            std.debug.print("[vmmap] capturing snapshot for pid {d}...\n", .{self.pid});
            self.captureSnapshot() catch |err| {
                std.debug.print("Snapshot failed: {}\n", .{err});
            };
            std.Thread.sleep(self.interval_ms * std.time.ns_per_ms);
        }
        std.debug.print("[vmmap] collection loop exited\n", .{});
    }

    /// Spawn `vmmap <pid>` as a child process, read its stdout (up to 10MB),
    /// append a timestamped Snapshot, and invoke on_snapshot callback if set.
    /// The pid is formatted into a stack buffer (no heap alloc needed for a
    /// small int-to-string conversion). stdout is read fully before wait() to
    /// avoid deadlock — if vmmap fills the pipe buffer and blocks on write,
    /// wait() would never return.
    fn captureSnapshot(self: *Collector) !void {
        std.debug.print("[vmmap] captureSnapshot: spawning vmmap for pid {d}\n", .{self.pid});
        var pid_buf: [16]u8 = undefined;
        const pid_str = std.fmt.bufPrint(&pid_buf, "{d}", .{self.pid}) catch unreachable;

        const argv: []const []const u8 = &.{ "vmmap", pid_str };
        var child = std.process.Child.init(argv, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        try child.spawn();

        const stdout = child.stdout orelse return error.NoStdout;
        const output = try stdout.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(output);

        const result = try child.wait();
        if (result.Exited != 0) return error.VmmapFailed;

        const timestamp = std.time.milliTimestamp();

        const regions = try parser.parse(self.allocator, output);
        std.debug.print("[vmmap] snapshot: {d} regions, {d} bytes output\n", .{ regions.len, output.len });

        const snapshot = types.Snapshot{
            .timestamp_ms = timestamp,
            .regions = regions,
            .allocator = self.allocator,
        };

        try self.snapshots.append(self.allocator, snapshot);
        std.debug.print("[vmmap] captureSnapshot: appended, total={d}\n", .{self.snapshots.items.len});

        if (self.on_snapshot) |cb| {
            std.debug.print("[vmmap] captureSnapshot: invoking on_snapshot callback\n", .{});
            cb(&snapshot);
        }
    }
};
