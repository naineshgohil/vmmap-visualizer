# vmmap Visualizer - Implementation Plan

## Overview

Native macOS desktop application for visualizing process virtual memory over time. React Native GUI with Zig core.

## Tech Stack

- **Core**: Zig (parser, collector) compiled as native module
- **GUI**: React Native for macOS
- **Visualization**: react-native-svg or react-native-skia
- **Data collection**: Zig module spawns `vmmap` via `std.process.Child`

### Future
- Native AppKit via Zig ObjC interop (for learning/performance)

## Project Structure

```
vmmap-visualizer/
  # React Native app
  App.tsx             # Root component
  src/
    screens/
      Home.tsx        # Main screen with timeline
    components/
      Timeline.tsx    # Timeline visualization (SVG)
      Controls.tsx    # PID input, start/stop
      RegionTooltip.tsx
    hooks/
      useCollector.ts # Bridge to native module
    types/
      index.ts        # TypeScript types

  # Zig native module
  native/
    build.zig
    src/
      main.zig        # C ABI exports for React Native
      collector.zig   # Spawns vmmap, collects snapshots
      parser.zig      # vmmap output parser
      types.zig       # Data structures

  # React Native config
  package.json
  metro.config.js
  macos/              # React Native macOS target
```

## Phase 1: Project Setup

### React Native macOS

```bash
npx react-native init VmmapVisualizer
cd VmmapVisualizer
npx react-native-macos-init
```

Dependencies:
- `react-native-svg` - For timeline rendering
- Custom native module for Zig integration

### Zig Native Module

Compile Zig as a dynamic library with C ABI exports:

```zig
// native/src/main.zig
export fn collector_start(pid: c_int, interval_ms: c_uint) callconv(.C) *Collector { ... }
export fn collector_stop(collector: *Collector) callconv(.C) void { ... }
export fn collector_get_snapshots(collector: *Collector) callconv(.C) [*]Snapshot { ... }
```

Build as `.dylib`:
```bash
zig build -Doptimize=ReleaseFast
# Outputs: zig-out/lib/libvmmap_collector.dylib
```

Bridge to React Native via a native module wrapper in Objective-C/Swift.

## Phase 2: Data Collector (Zig)

**File**: `src/collector.zig`

Spawns `vmmap` as a child process and captures output:

```zig
const Collector = struct {
    pid: std.posix.pid_t,
    interval_ms: u32,
    snapshots: std.ArrayList(Snapshot),
    running: std.atomic.Value(bool),

    pub fn start(self: *Collector) !void {
        while (self.running.load(.acquire)) {
            const snapshot = try self.captureSnapshot();
            try self.snapshots.append(snapshot);
            std.time.sleep(self.interval_ms * std.time.ns_per_ms);
        }
    }

    fn captureSnapshot(self: *Collector) !Snapshot {
        var child = std.process.Child.init(.{
            .argv = &.{ "vmmap", self.pid_str },
        });
        // ... capture stdout, parse, return Snapshot
    }
};
```

Features:
- Run in background thread while UI remains responsive
- Configurable interval (default 1s)
- Stop/start controls from UI
- Live updates to timeline as snapshots arrive

## Phase 3: Parser (Zig)

Parse vmmap output to extract per-region data:

| Field             | Example                           |
| ----------------- | --------------------------------- |
| Region type       | `MALLOC_SMALL`, `__TEXT`, `Stack` |
| Start/End address | `100484000-100f3c000` (hex)       |
| Virtual size      | `10.7M`                           |
| Resident size     | `7904K`                           |
| Permissions       | `r-x/r-x`                         |
| Sharing mode      | `COW`, `PRV`, `SHM`               |
| Detail            | `/path/to/binary`                 |

**Data structures**:
```zig
const Region = struct {
    region_type: []const u8,
    start_addr: u64,
    end_addr: u64,
    virtual_size: u64,
    resident_size: u64,
    permissions: Permissions,
    sharing_mode: SharingMode,
    detail: ?[]const u8,
};

const Snapshot = struct {
    timestamp: f64,
    regions: []Region,
};
```

**Region tracking**:
- Key regions by `start_addr + end_addr + type`
- Track first seen, last seen, size changes across snapshots

## Phase 4: Timeline View (React Native)

### Component: Timeline.tsx

Using `react-native-svg` for rendering:

```tsx
import Svg, { Rect, G } from 'react-native-svg';

function Timeline({ snapshots, width, height }) {
  const yScale = d3.scaleLog()
    .domain([minAddr, maxAddr])
    .range([height, 0]);

  return (
    <Svg width={width} height={height}>
      {regions.map(region => (
        <Rect
          key={region.id}
          x={xScale(region.firstSeen)}
          y={yScale(region.endAddr)}
          width={xScale(region.lastSeen) - xScale(region.firstSeen)}
          height={yScale(region.startAddr) - yScale(region.endAddr)}
          fill={categoryColor(region.type)}
        />
      ))}
    </Svg>
  );
}
```

### Layout

- **X-axis**: Time (snapshot index)
- **Y-axis**: Address space (log scale)
- **Regions**: Horizontal bands spanning their lifetime

### Color coding by category

| Category | Region Types                                  | Color              |
| -------- | --------------------------------------------- | ------------------ |
| Code     | `__TEXT`, `__LINKEDIT`                        | `#3b82f6` (Blue)   |
| Data     | `__DATA`, `__DATA_CONST`, `__OBJC_*`          | `#22c55e` (Green)  |
| Heap     | `MALLOC_*`                                    | `#f97316` (Orange) |
| Stack    | `Stack`, `STACK GUARD`                        | `#ef4444` (Red)    |
| Mapped   | `mapped file`                                 | `#a855f7` (Purple) |
| Shared   | `shared memory`                               | `#06b6d4` (Cyan)   |
| System   | `IOKit`, `CoreAnimation`, `Kernel Alloc Once` | `#6b7280` (Gray)   |

## Phase 5: Interactivity

- **Touch/click handling**: `onPress` on SVG elements
- **Tooltips**: Custom `RegionTooltip` component positioned near selection
- **Filters**: Toggle buttons for region categories (Pressable components)
- **Gestures**: Pinch to zoom, pan with react-native-gesture-handler

## Implementation Order

### v1 (Core)

1. **Project setup** - React Native macOS + Zig native module scaffold
2. **Parser** - vmmap output parsing in Zig
3. **Collector** - Spawn vmmap, capture snapshots in background thread
4. **Bridge** - Objective-C wrapper exposing Zig to React Native
5. **Timeline View** - react-native-svg rendering
6. **Controls** - PID input, start/stop collection

### v2 (Polish)

- Hover tooltips
- Filter toggles
- Zoom/pan
- Playback scrubber
- Export to PNG

## Build

```bash
# Build Zig native module
cd native && zig build -Doptimize=ReleaseFast

# Install React Native dependencies
yarn install

# Run macOS app
yarn macos
```

## References

- [React Native macOS](https://microsoft.github.io/react-native-windows/docs/rnm-getting-started)
- [react-native-svg](https://github.com/software-mansion/react-native-svg)
- [Zig Build System](https://ziglang.org/learn/build-system/)
- [Creating Native Modules](https://reactnative.dev/docs/native-modules-ios)

## Challenges

1. **Zig to React Native bridge** - Need Objective-C wrapper to expose Zig functions as native module
2. **Log scale rendering** - Address space spans ~48 bits; need careful scaling for visualization
3. **Performance** - Many regions (1000+) may need virtualization or canvas fallback
4. **Real-time updates** - Switch from pull-based polling (`getSnapshots`) to push-based events (`RCTEventEmitter`). Collection thread serializes each snapshot to JSON immediately after capture, then signals the ObjC module which emits an `onSnapshot` event to JS. This eliminates polling, sends one snapshot per event instead of the full history, and avoids the data race since serialization happens on the collection thread before any concurrent access.
5. **Snapshot list data race** - Resolved by the push model above: the snapshot is serialized on the collection thread immediately after capture, so the ObjC bridge queue never reads the ArrayList concurrently. If pull-based access is still needed (e.g. replaying history), protect `snapshots` with a mutex.
