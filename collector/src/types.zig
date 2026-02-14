const std = @import("std");

/// How a memory region is shared between processes.
pub const SharingMode = enum {
    COW, // Copy-on-write: shared until modified, then gets a private copy
    PRV, // Private: belongs to this process only
    SHM, // Shared memory: writable by multiple processes
    NUL, // No sharing info (typically reserved/unused regions)
    ALI, // Aliased: multiple virtual addresses map to the same physical page
    S_A, // Shared aliased: shared + aliased
};

/// The rwx protection bits on a memory region.
pub const Permissions = struct { read: bool, write: bool, execute: bool };

/// A single contiguous virtual memory region from one vmmap snapshot.
/// Captures type (e.g. MALLOC_TINY, __TEXT), address range, sizes,
/// permissions, sharing mode, and an optional detail string (e.g. dylib path).
pub const Region = struct {
    region_type: []const u8,
    start_addr: u64,
    end_addr: u64,
    virtual_size: u64,
    resident_size: u64,
    dirty_size: u64,
    swap_size: u64,
    current_perm: Permissions,
    max_perm: Permissions,
    sharing_mode: SharingMode,
    detail: ?[]const u8,
};

/// All regions captured from a single vmmap invocation at a point in time.
/// One frame in the timeline.
pub const Snapshot = struct {
    timestamp_ms: i64,
    regions: []Region,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Snapshot) void {
        self.allocator.free(self.regions);
    }
};
