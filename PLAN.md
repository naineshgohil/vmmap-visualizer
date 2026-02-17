# vmmap Visualizer - Implementation Plan

## Overview

Native macOS desktop application for visualizing process virtual memory over time. React Native GUI with Zig core.

## Tech Stack

- **Core**: Zig (parser, collector) compiled as dynamic library with C ABI
- **GUI**: React Native for macOS
- **Visualization**: react-native-svg
- **Data collection**: Zig module spawns `vmmap` via `std.process.Child`
- **Bridge**: Objective-C `RCTEventEmitter` loading Zig dylib via `dlopen`

### Future
- Native AppKit via Zig ObjC interop (for learning/performance)

## Project Structure

```
vmmap-visualizer/
  # React Native app
  frontend/
    src/
      App.tsx             # Root component (dark background + Timeline)
      useCollector.ts     # Bridge to native module, accumulates Snapshot[]
      types.ts            # Region/Snapshot TypeScript interfaces
      regionColors.ts     # Region type -> category -> hex color mapping
      Timeline.tsx        # SVG timeline visualization (log-scale Y-axis)
      components/
        Controls.tsx      # PID input, start/stop (not yet implemented)
        RegionTooltip.tsx # Hover details (not yet implemented)
    macos/
      VmmapVisualizer-macOS/
        VmmapCollectorModule.m  # ObjC bridge (RCTEventEmitter + dlopen)
        AppDelegate.mm          # React Native macOS entry point
    package.json
    metro.config.js

  # Zig native module
  collector/
    build.zig             # Builds libvmmap_collector.dylib
    src/
      main.zig            # C ABI exports + CResult/CRegion/CSnapshot structs
      collector.zig       # Background thread, spawns vmmap, push via callback
      parser.zig          # vmmap output parser (full format support)
      types.zig           # Region, Snapshot, Permissions, SharingMode
```

## Implementation Status

### v1 (Core)

1. **Project setup** - DONE
2. **Parser** - DONE
3. **Collector** - DONE
4. **Bridge** - DONE
5. **Timeline View** - DONE
6. **Controls** - Not started

---

## Phase 1: Project Setup - DONE

### React Native macOS

Initialized with `react-native-macos-init`. Running on React 19.1.0, react-native 0.81.2, react-native-macos 0.81.0.

Dependencies: `react-native-safe-area-context`, `react-native-svg`.

### Zig Native Module

Compiles as a dynamic library (`libvmmap_collector.dylib`) with C ABI exports. Built with `zig build -Doptimize=ReleaseFast`. Links libc, uses dynamic linkage.

The dylib is copied into the macOS app bundle via an Xcode build phase so the ObjC bridge can load it at runtime.

## Phase 2: Parser (Zig) - DONE

**File**: `collector/src/parser.zig`

Parses vmmap output line-by-line, extracting:

| Field             | Example                           |
| ----------------- | --------------------------------- |
| Region type       | `MALLOC_SMALL`, `__TEXT`, `Stack` |
| Start/End address | `100484000-100f3c000` (hex)       |
| Virtual size      | `10.7M`                           |
| Resident size     | `7904K`                           |
| Dirty size        | `512K`                            |
| Swap size         | `0K`                              |
| Permissions       | `r-x/rwx`                         |
| Sharing mode      | `COW`, `PRV`, `SHM`, `NUL`, `ALI`, `S/A` |
| Detail            | `/path/to/binary`                 |

Handles multi-word region types, variable whitespace, bracketed size fields with K/M/G multipliers and float support. Invalid lines are skipped gracefully.

**Data structures** (`collector/src/types.zig`):

```zig
const Region = struct {
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

const Snapshot = struct {
    timestamp_ms: i64,
    regions: []Region,
    allocator: std.mem.Allocator,
};
```

## Phase 3: Collector (Zig) - DONE

**File**: `collector/src/collector.zig`

Background thread spawns `vmmap <pid>` at a configurable interval, reads stdout (up to 10MB), parses with the parser, appends the snapshot to an ArrayList, and invokes an `on_snapshot` callback.

- `start()` spawns a background thread with atomic guard against double-start
- `stop()` sets atomic bool to false, joins the thread (blocks until current capture finishes)
- `deinit()` stops collection and frees all snapshot data
- Errors from individual captures are logged but don't kill the loop

## Phase 4: Bridge (Zig C ABI + ObjC) - DONE

### Zig C ABI (`collector/src/main.zig`)

Exported functions:

```
vmmap_collector_create(pid, interval_ms, callback) -> CResult
vmmap_collector_start(collector) -> CResult
vmmap_collector_stop(collector)
vmmap_collector_destroy(collector)
vmmap_collector_snapshot_count(collector) -> count
vmmap_collector_push_snapshot(snapshot) -> CSnapshotResult
vmmap_free_string(ptr)
```

C-compatible structs (`CResult`, `CRegion`, `CSnapshot`) flatten Zig types for the ABI boundary. `push_snapshot` converts a Zig Snapshot to a heap-allocated CSnapshot with null-terminated string copies.

### ObjC Bridge (`frontend/macos/.../VmmapCollectorModule.m`)

- Extends `RCTEventEmitter` for push-based events to JS
- Loads `libvmmap_collector.dylib` at init via `dlopen`/`dlsym`
- Resolves function pointers: create, destroy, start, stop, count, freeString
- `onSnapshotCallback` (C function) converts `CSnapshot*` to `NSDictionary` and emits `onSnapshot` event via the shared `RCTEventEmitter` instance
- Exported methods: `create(pid, interval, promise)`, `start(promise)`, `stop()`, `getSnapshots(promise)` (legacy, kept for compatibility)

### JS Hook (`frontend/src/useCollector.ts`)

- Creates collector with hardcoded PID and 1000ms interval (test mode)
- Listens for `onSnapshot` events via `NativeEventEmitter`
- Logs snapshots to console
- Cleanup: stops collector on unmount

### Data Flow

```
Zig collection thread
  vmmap <pid> -> parse -> Snapshot struct
  -> on_snapshot callback
    -> main.zig converts to CSnapshot
      -> ObjC onSnapshotCallback()
        -> NSDictionary { timestamp_ms, regions[] }
          -> sendEventWithName:@"onSnapshot"
            -> NativeEventEmitter in JS
              -> useCollector listener
```

Key design: serialization happens on the collection thread before crossing to ObjC, avoiding concurrent access to the Zig ArrayList.

## Phase 5: Timeline View - DONE

### Types (`frontend/src/types.ts`)

Extracted `Region` and `Snapshot` interfaces from useCollector. Fixed field name mismatch: bridge sends `timestamp_ms`, previous interface had `timestamp`.

### Color Classification (`frontend/src/regionColors.ts`)

Two-tier lookup for mapping region type strings to hex colors:
1. Exact match map for known types (`__TEXT`, `Stack`, `mapped file`, etc.)
2. Prefix rules for families (`MALLOC*` -> heap, `__OBJC*` -> data, `__AUTH*` -> data)
3. Fallback: system (gray)

| Category | Region Types                                  | Color              |
| -------- | --------------------------------------------- | ------------------ |
| Code     | `__TEXT`, `__LINKEDIT`                        | `#3b82f6` (Blue)   |
| Data     | `__DATA`, `__DATA_CONST`, `__DATA_DIRTY`, `__OBJC_*`, `__AUTH*` | `#22c55e` (Green)  |
| Heap     | `MALLOC_*`                                    | `#f97316` (Orange) |
| Stack    | `Stack`, `STACK GUARD`                        | `#ef4444` (Red)    |
| Mapped   | `mapped file`                                 | `#a855f7` (Purple) |
| Shared   | `shared memory`                               | `#06b6d4` (Cyan)   |
| System   | Everything else                               | `#6b7280` (Gray)   |

### useCollector Hook (`frontend/src/useCollector.ts`)

- Accepts `pid: number` and `intervalMs: number` parameters (replaces hardcoded values)
- Accumulates snapshots in `useState<Snapshot[]>` via `setSnapshots(prev => [...prev, snapshot])`
- Resets snapshots to `[]` when pid or intervalMs changes
- Returns `Snapshot[]` array

### Timeline Component (`frontend/src/Timeline.tsx`)

SVG visualization using `react-native-svg`:

- **Region tracking**: `Map<string, TrackedRegion>` keyed by `${start}-${end}-${type}`. Each entry tracks `firstSeen`/`lastSeen` snapshot index. Memoized with `useMemo`.
- **Log-scale Y-axis**: `Math.log2(address)` mapped to pixel position. Auto-scales from data (scans min/max log2 addresses across all tracked regions).
- **SVG rendering**: Each tracked region becomes a `<Rect>` with x/width from snapshot indices, y/height from log-scale address mapping, fill from `colorForType()`, opacity 0.7.
- **Empty state**: Returns null when no snapshots (dark background shows through).

### App Component (`frontend/src/App.tsx`)

- Removed NewAppScreen template, StatusBar, useColorScheme, SafeAreaProvider, AppContent
- Calls `useCollector(PID, INTERVAL_MS)` with hardcoded constants (PID=25038, interval=1000ms)
- Uses `useWindowDimensions()` for full-window SVG viewport
- Dark background (`#1a1a2e`) so region colors pop

## Phase 6: Controls - NOT STARTED

- PID input field
- Start/stop button
- Interval configuration
- Replace hardcoded PID in useCollector with user input

## Phase 7: Interactivity - NOT STARTED

- Touch/click handling on SVG elements
- Tooltips: custom `RegionTooltip` component positioned near selection
- Filters: toggle buttons for region categories
- Gestures: pinch to zoom, pan with react-native-gesture-handler

### v2 (Polish)

- Hover tooltips
- Filter toggles
- Zoom/pan
- Playback scrubber
- Export to PNG

## Build

```bash
# Build Zig native module
cd collector && zig build -Doptimize=ReleaseFast

# Install React Native dependencies
cd frontend && yarn install

# Run macOS app
cd frontend && yarn macos
```

## References

- [React Native macOS](https://microsoft.github.io/react-native-windows/docs/rnm-getting-started)
- [react-native-svg](https://github.com/software-mansion/react-native-svg)
- [Zig Build System](https://ziglang.org/learn/build-system/)
- [Creating Native Modules](https://reactnative.dev/docs/native-modules-ios)

## Challenges

1. **Zig to React Native bridge** - RESOLVED. ObjC `RCTEventEmitter` loads Zig dylib via `dlopen`. C function pointer callback bridges from Zig thread to ObjC event emitter.
2. **Log scale rendering** - RESOLVED. `Math.log2(address)` with auto-scaling from min/max across all tracked regions. Typical span is ~15 log2 units (bits 32-47).
3. **Performance** - Many regions (1000+) may need virtualization or canvas fallback.
4. **Real-time updates** - RESOLVED. Push-based delivery via `on_snapshot` callback. Collection thread serializes each snapshot to a CSnapshot immediately after capture, then invokes the ObjC callback which emits an `onSnapshot` event to JS. One snapshot per event, no polling, no full-history serialization.
5. **Snapshot list data race** - RESOLVED. Serialization happens on the collection thread before any cross-thread access. The ObjC bridge queue never reads the ArrayList directly.
