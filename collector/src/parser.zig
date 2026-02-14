const std = @import("std");
const types = @import("types.zig");

pub const ParseError = error{ InvalidLine, InvalidAddress, InvalidSize, InvalidPermissions, OutOfMemory };
const Sizes = struct { virtual: u64, resident: u64, dirty: u64, swap: u64 };
const PermPair = struct { current: types.Permissions, max: types.Permissions };

pub fn parse(allocator: std.mem.Allocator, output: []const u8) ![]types.Region {
    var regions: std.ArrayList(types.Region) = .{};
    errdefer regions.deinit(allocator);

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (isRegionLine(line)) {
            const region = parseRegionLine(allocator, line) catch continue;
            try regions.append(allocator, region);
        }
    }

    return regions.toOwnedSlice(allocator);
}

fn parseRegionLine(allocator: std.mem.Allocator, line: []const u8) !types.Region {
    // Find the address range first (anchor point)
    const addr_start = findAddressStart(line) orelse return error.InvalidLine;

    // Everything before the address is the region type
    const region_type_raw = std.mem.trim(u8, line[0..addr_start], " ");
    const region_type = try allocator.dupe(u8, region_type_raw);

    // Parse address range
    var rest = line[addr_start..];
    const dash_pos = std.mem.indexOf(u8, rest, "-") orelse return error.InvalidAddress;
    const start_addr = try std.fmt.parseInt(u64, rest[0..dash_pos], 16);

    rest = rest[dash_pos + 1 ..];
    const end_pos = std.mem.indexOfAny(u8, rest, " [") orelse return error.InvalidAddress;
    const end_addr = try std.fmt.parseInt(u64, rest[0..end_pos], 16);

    // Find the bracket section
    const bracket_start = std.mem.indexOf(u8, rest, "[") orelse return error.InvalidLine;
    const bracket_end = std.mem.indexOf(u8, rest, "]") orelse return error.InvalidLine;
    const sizes = try parseSizes(rest[bracket_start + 1 .. bracket_end]);

    // Parse permissions after ]
    rest = rest[bracket_end + 1 ..];
    const perms = try parsePermissions(rest);

    // Parse sharing mode (SM=XXX)
    const sharing_mode = parseSharingMode(rest);

    // Detail is everything after sharing mode (optional)
    const detail = parseDetail(allocator, rest);

    return types.Region{
        .region_type = region_type,
        .start_addr = start_addr,
        .end_addr = end_addr,
        .virtual_size = sizes.virtual,
        .resident_size = sizes.resident,
        .dirty_size = sizes.dirty,
        .swap_size = sizes.swap,
        .current_perm = perms.current,
        .max_perm = perms.max,
        .sharing_mode = sharing_mode,
        .detail = detail,
    };
}

fn parsePermissions(rest: []const u8) !PermPair {
    // Look for pattern like "r-x/rwx" or "rw-/rwx"
    const trimmed = std.mem.trim(u8, rest, " ");

    var i: usize = 0;
    while (i + 6 < trimmed.len) : (i += 1) {
        if (trimmed[i + 3] == '/') {
            const current = parsePerm(trimmed[i..][0..3]);
            const max = parsePerm(trimmed[i + 4 ..][0..3]);
            return .{ .current = current, .max = max };
        }
    }

    return .{
        .current = .{
            .read = false,
            .write = false,
            .execute = false,
        },
        .max = .{
            .read = false,
            .write = false,
            .execute = false,
        },
    };
}

fn parsePerm(s: []const u8) types.Permissions {
    return .{
        .read = s[0] == 'r',
        .write = s[1] == 'w',
        .execute = s[2] == 'x',
    };
}

fn parseSharingMode(rest: []const u8) types.SharingMode {
    if (std.mem.indexOf(u8, rest, "SM=COW")) |_| return .COW;
    if (std.mem.indexOf(u8, rest, "SM=PRV")) |_| return .PRV;
    if (std.mem.indexOf(u8, rest, "SM=SHM")) |_| return .SHM;
    if (std.mem.indexOf(u8, rest, "SM=NUL")) |_| return .NUL;
    if (std.mem.indexOf(u8, rest, "SM=ALI")) |_| return .ALI;
    if (std.mem.indexOf(u8, rest, "SM=S/A")) |_| return .S_A;
    return .PRV;
}

fn parseDetail(allocator: std.mem.Allocator, rest: []const u8) ?[]const u8 {
    // Detail comes after sharing mode, typically a path or zone name
    const sm_markers = [_][]const u8{
        "SM=COW",
        "SM=PRV",
        "SM=SHM",
        "SM=NUL",
        "SM=ALI",
        "SM=S/A",
    };

    for (sm_markers) |marker| {
        if (std.mem.indexOf(u8, rest, marker)) |pos| {
            const after = rest[pos + marker.len ..];
            const trimmed = std.mem.trim(u8, after, " \t");
            if (trimmed.len > 0) {
                return allocator.dupe(u8, trimmed) catch null;
            }
        }
    }
    return null;
}

fn parseSizes(bracket_content: []const u8) !Sizes {
    var parts = std.mem.tokenizeScalar(u8, bracket_content, ' ');

    const vsize = parts.next() orelse return error.InvalidSize;
    const rsize = parts.next() orelse return error.InvalidSize;
    const dirty = parts.next() orelse return error.InvalidSize;
    const swap = parts.next() orelse return error.InvalidSize;

    return Sizes{
        .virtual = try parseSize(vsize),
        .resident = try parseSize(rsize),
        .dirty = try parseSize(dirty),
        .swap = try parseSize(swap),
    };
}

fn parseSize(size: []const u8) !u64 {
    if (size.len == 0) return 0;

    var multiplier: u64 = 1;
    var end = size.len;

    if (size[size.len - 1] == 'K') {
        multiplier = 1024;
        end -= 1;
    } else if (size[size.len - 1] == 'M') {
        multiplier = 1024 * 1024;
        end -= 1;
    } else if (size[size.len - 1] == 'G') {
        multiplier = 1024 * 1024 * 1024;
        end -= 1;
    }

    // Handle decimal values like "10.7M"
    const num_str = size[0..end];

    if (std.mem.indexOf(u8, num_str, ".")) |_| {
        const whole = std.fmt.parseFloat(f64, num_str) catch return error.InvalidSize;
        return @intFromFloat(whole * @as(f64, @floatFromInt(multiplier)));
    }

    const value = std.fmt.parseInt(u64, num_str, 10) catch return error.InvalidSize;
    return value * multiplier;
}

fn findAddressStart(line: []const u8) ?usize {
    // Find first hex digit sequence that's followed by a dash and more hex
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (isHexDigit(line[i])) {
            var j = i;
            while (j < line.len and isHexDigit(line[j])) : (j += 1) {}
            if (j < line.len and line[j] == '-' and j + 1 < line.len and isHexDigit(line[j + 1])) {
                return i;
            }
        }
    }
    return null;
}

fn isRegionLine(line: []const u8) bool {
    const trimmed = std.mem.trim(u8, line, " ");
    if (trimmed.len == 0) return false;
    if (std.mem.startsWith(u8, trimmed, "==")) return false;
    if (std.mem.startsWith(u8, trimmed, "REGION TYPE")) return false;
    if (std.mem.startsWith(u8, trimmed, "---")) return false;

    // Must contain address range pattern: hex-hex
    return std.mem.indexOf(u8, line, "-") != null and containsHexRange(line);
}

fn containsHexRange(line: []const u8) bool {
    // Look for pattern like "100444000-1002f3c000"
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (isHexDigit(line[i])) {
            var j = i;
            while (j < line.len and isHexDigit(line[j])) : (j += 1) {}
            if (j < line.len and line[j] == '-') {
                j += 1;
                if (j < line.len and isHexDigit(line[j])) {
                    return true;
                }
            }
        }
    }
    return false;
}

fn isHexDigit(c: u8) bool {
    return (c >= '0' and c <= '9') or
        (c >= 'a' and c <= 'f') or
        (c >= 'A' and c <= 'F');
}
