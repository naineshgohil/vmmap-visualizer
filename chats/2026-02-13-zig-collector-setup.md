# Zig Collector Setup - Concepts Learned

**Date**: 2026-02-13

---

## 1. C Calling Convention (`callconv(.c)`)

`callconv(.c)` forces a function to use the C calling convention - the rules for how arguments are passed in registers/stack, return values, and which registers are caller vs callee saved. This makes the function callable from C, Objective-C, or any language with a C FFI.

The `export` keyword already implies C calling convention, so `callconv(.c)` on an `export fn` is redundant but can be kept for explicitness.

In Zig 0.15, the enum casing changed from `.C` to `.c`.

---

## 2. No Multi-line Comments in Zig

Zig only has single-line comments (`//`) and doc comments (`///`). This is a deliberate design choice to keep the grammar simple and avoid nesting issues that `/* */` style comments have. For multi-line doc comments, repeat `///` on each line.

---

## 3. Atomic Bool and Data Races

### Why `std.atomic.Value(bool)` instead of plain `bool`

A plain `bool` accessed from two threads is a data race. Two problems:

1. **Cache staleness**: CPU cores have their own caches. A write on one core isn't immediately visible to another. Thread 1 could keep reading stale `true` after thread 2 wrote `false`.

2. **Compiler optimization**: The compiler assumes no other thread modifies the value and can hoist reads out of loops:
   ```zig
   // Compiler might optimize to:
   const cached = self.running;
   while (cached) { ... }  // infinite loop
   ```

`std.atomic.Value(bool)` uses atomic CPU instructions that force memory visibility and prevent the compiler from optimizing away reads.

---

## 4. Atomic Memory Ordering (`.acquire` / `.release`)

`.release` and `.acquire` work as a pair to create a happens-before relationship between threads.

**`.release` on store**: Every memory write done before this store is guaranteed to be visible to any thread that reads this value with `.acquire`. It "releases" all prior work to other threads.

**`.acquire` on load**: Once this value is read, all writes the storing thread did before its `.release` store are guaranteed to be visible. It "acquires" the other thread's prior work.

**In the collector**: `start()` sets up `pid`, `interval_ms`, etc., then stores `running = true` with `.release`. When the collection thread loads `running` with `.acquire` and sees `true`, it's guaranteed to also see those field values - not stale/uninitialized memory.

Without ordering, the CPU could reorder the store of `running = true` to happen before the field writes are visible.

---

## 5. Tuple to Slice Coercion

```zig
const argv: []const []const u8 = &.{ "vmmap", pid_str };
```

The coercion chain:
```
.{ "vmmap", pid_str }    ->  [2][]const u8          (inferred array)
&(array)                  ->  *const [2][]const u8   (pointer to array)
: []const []const u8      ->  []const []const u8     (pointer-to-array coerces to slice)
```

The explicit type annotation drives the coercion. Without it, Zig stops at pointer-to-array and doesn't coerce further. Inside struct literals (`.{ .argv = &.{...} }`), Zig doesn't propagate the expected field type back through `&`, so you need to pull it out with a type annotation.

---

## 6. Zig 0.15 API Changes

| Old (0.14) | New (0.15) |
|---|---|
| `addLibrary(.{ .root_source_file = ..., .target = ..., .optimize = ... })` | `addLibrary(.{ .linkage = .static, .root_module = b.createModule(.{ .root_source_file = ..., .target = ..., .optimize = ... }) })` |
| `callconv(.C)` | `callconv(.c)` |
| `ArrayList.init(allocator)` | `.{}` (pass allocator per-operation) |
| `list.deinit()` | `list.deinit(allocator)` |
| `list.append(item)` | `list.append(allocator, item)` |
| `Child.init(.{ .argv = ..., .stdout_behaviour = .pipe }, allocator)` | `Child.init(argv, allocator)` then `child.stdout_behavior = .Pipe` |
| `std.time.sleep(ns)` | `std.Thread.sleep(ns)` |
| `file.reader().readAllAlloc(allocator, max)` | `file.readToEndAlloc(allocator, max)` |

The theme: Zig 0.15 moved away from storing allocators inside data structures. You pass the allocator explicitly at each call site for clearer ownership.
