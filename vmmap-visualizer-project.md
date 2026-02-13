# vmmap Visualizer

A native macOS tool for understanding how memory allocations change over time. Watch a process's virtual address space evolve — see heap regions grow, stack frames push and pop, libraries load, and memory get freed — all visualized as a timeline.

## Why

**The goal is to build intuition for how programs use memory.**

Reading about virtual memory in OSTEP or CS:APP is one thing. Watching it happen in real time is another. This tool answers questions like:

- How does malloc actually allocate memory? (Watch MALLOC_TINY/SMALL/LARGE regions appear)
- What happens to the heap when I create objects? (See it grow)
- How much memory does loading a dylib cost? (See __TEXT/__DATA regions appear)
- Is my program leaking memory? (Watch regions accumulate without being freed)
- How does the stack grow during recursion? (See Stack regions expand)

macOS has no GUI for this. Instruments' VM Tracker frequently fails to attach, and `vmmap` dumps a wall of text. This tool turns that wall of text into an interactive timeline.

## How It Works

### Data Collection

The app spawns `vmmap <pid>` at a configurable interval (e.g., every 500ms-1s) in a background thread. Snapshots are collected in memory and the timeline updates live as new data arrives. No manual file management required.

### Parser

Each snapshot is parsed to extract per-region data:

- **Region type** — MALLOC_TINY, MALLOC_SMALL, MALLOC_LARGE, Stack, __TEXT, __DATA, __LINKEDIT, mapped file, etc.
- **Address range** — start and end virtual addresses
- **Size** — virtual size (and resident size if `--resident` flag was used)
- **Permissions** — r/w/x (current and max)
- **Sharing mode** — PRV, COW, NUL, ALI, SHM
- **Associated library** — dylib or binary name, if applicable

Regions are tracked across snapshots by matching on address range + type, allowing the visualizer to identify when regions appear, disappear, grow, or shrink.

### Visualization

#### 1. Timeline View (Primary)

X-axis is time, Y-axis is address space. Each memory region is a horizontal band spanning its lifetime. Color-coded by region type. Gaps and overlaps in the address space are visible. This is the core view — it shows the process "breathing" over time.

#### 2. Playback / Scrubber

A vertical address-space map (single snapshot) with a time scrubber. Hit play or drag to animate through the process's life frame by frame. Each frame shows the full address space at that moment, with regions drawn as blocks proportional to size (log scale to handle the vast range between tiny stack frames and large malloc regions).

#### 3. Aggregate Area Chart

Stacked area chart showing total memory by region type over time. Quick way to see trends — heap growing, libraries being loaded, stack expanding during recursion, etc.

### Interactivity

- **Hover** any region at any point in time for details (address range, size, permissions, library)
- **Filter** by region type (toggle heap, stack, text, data, etc.)
- **Filter** by permission (show only writable, only executable, etc.)
- **Search** by address to locate a specific region
- **Highlight** new/removed regions between adjacent frames
- **Click** a region to pin its detail panel

## Tech

- **GUI**: React Native for macOS
- **Core**: Zig (parser + collector) compiled as native module
- **Visualization**: react-native-svg for the timeline

Zig handles the performance-critical parts (spawning vmmap, parsing output, tracking regions across snapshots). React Native provides the UI.

## Stretch Goals

- **Diff mode** — Compare two snapshots side-by-side, highlighting what changed. Useful with `vmmap -d` which already takes two snapshots internally.
- **Live mode** — Instead of loading pre-collected snapshots, run the collector in the background and stream data to the browser via a local WebSocket server, rendering in real time.
- **Annotation** — Mark points in time ("started loading data", "triggered GC", "opened file") to correlate memory changes with application events.
- **Export** — Save the visualization as a static SVG or PNG for inclusion in notes or reports.

## Usage

```bash
# 1. Start your program
./myprogram &

# 2. Launch the visualizer
open VmmapVisualizer.app

# 3. Enter the PID and click Start
#    The timeline updates live as snapshots are collected
```
