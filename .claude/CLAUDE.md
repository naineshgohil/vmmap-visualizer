# vmmap Visualizer - Project Context

## Important

- Never write to files or suggest writing to files unless explicitly asked
- Share code in chat for learning; user will copy when ready

## Why This App Exists

This app is built to develop intuition for how programs use memory.

Reading about virtual memory in OSTEP or CS:APP is one thing. Watching it happen in real time is another. This tool answers questions like:

- How does malloc actually allocate memory? (Watch MALLOC_TINY/SMALL/LARGE regions appear)
- What happens to the heap when I create objects? (See it grow)
- How much memory does loading a dylib cost? (See __TEXT/__DATA regions appear)
- Is my program leaking memory? (Watch regions accumulate without being freed)
- How does the stack grow during recursion? (See Stack regions expand)

macOS has no GUI for this. Instruments' VM Tracker frequently fails to attach, and `vmmap` dumps a wall of text. This tool turns that wall of text into an interactive timeline.

## Overview

Native macOS desktop application for visualizing process virtual memory over time. Watch a process's virtual address space evolve - see heap regions grow, stack frames push and pop, libraries load, and memory get freed - all visualized as a timeline.

**Core concept**: X-axis is time, Y-axis is address space. Each memory region is a horizontal band spanning its lifetime. Color-coded by region type.

## Tech Stack

- **Core**: Zig (parser, collector) compiled as native module with C ABI
- **GUI**: React Native for macOS
- **Visualization**: react-native-svg
- **Data collection**: Zig module spawns `vmmap` via `std.process.Child`

## Project Structure

```
vmmap-visualizer/
  # React Native app
  App.tsx                # Root component
  src/
    screens/
      Home.tsx           # Main screen with timeline
    components/
      Timeline.tsx       # Timeline visualization (SVG)
      Controls.tsx       # PID input, start/stop
      RegionTooltip.tsx  # Hover details
    hooks/
      useCollector.ts    # Bridge to native module
    types/
      index.ts           # TypeScript types

  # Zig native module
  native/
    build.zig
    src/
      main.zig           # C ABI exports for React Native
      collector.zig      # Spawns vmmap, collects snapshots
      parser.zig         # vmmap output parser
      types.zig          # Data structures

  # React Native config
  package.json
  metro.config.js
  macos/                 # React Native macOS target
```

## Implementation Phases

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

## Key Data Structures (Zig)

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

## Region Categories and Colors

| Category | Region Types                                  | Color              |
| -------- | --------------------------------------------- | ------------------ |
| Code     | `__TEXT`, `__LINKEDIT`                        | `#3b82f6` (Blue)   |
| Data     | `__DATA`, `__DATA_CONST`, `__OBJC_*`          | `#22c55e` (Green)  |
| Heap     | `MALLOC_*`                                    | `#f97316` (Orange) |
| Stack    | `Stack`, `STACK GUARD`                        | `#ef4444` (Red)    |
| Mapped   | `mapped file`                                 | `#a855f7` (Purple) |
| Shared   | `shared memory`                               | `#06b6d4` (Cyan)   |
| System   | `IOKit`, `CoreAnimation`, `Kernel Alloc Once` | `#6b7280` (Gray)   |

## vmmap Output Format

See [VMMAP_FORMAT.md](../VMMAP_FORMAT.md) for complete parsing reference.

Key parsing notes:
- Section markers: Look for `==== Non-writable` and `==== Writable`
- Multi-word types: `MALLOC guard page`, `shared memory`, `mapped file`
- Address format: Hex without `0x` prefix, uppercase A-F (e.g., `100484000-100f3c000`)
- Variable whitespace: Columns are space-aligned, not tab-separated

## Commands

```bash
# Build Zig native module
cd native && zig build -Doptimize=ReleaseFast

# Install React Native dependencies
yarn install

# Run macOS app
yarn macos
```

## Development Notes

- Region tracking: Key by `start_addr + end_addr + type` to track across snapshots
- Log scale for Y-axis: Address space spans ~48 bits, need careful scaling
- Performance: Many regions (1000+) may need virtualization
- Real-time updates: Bridge snapshot data from Zig thread to JS efficiently

## Key Files

| File                          | Purpose                        |
| ----------------------------- | ------------------------------ |
| `PLAN.md`                     | Full implementation plan       |
| `VMMAP_FORMAT.md`             | vmmap output parsing reference |
| `native/src/parser.zig`       | vmmap output parser            |
| `native/src/collector.zig`    | Snapshot collection            |
| `src/components/Timeline.tsx` | Main visualization             |

## Challenges to Address

1. **Zig to React Native bridge** - Need Objective-C wrapper to expose Zig functions as native module
2. **Log scale rendering** - Address space spans ~48 bits; need careful scaling
3. **Performance** - Many regions (1000+) may need virtualization or canvas fallback
4. **Real-time updates** - Bridging snapshot data from Zig thread to JS efficiently
