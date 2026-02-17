# Timeline Component Implementation Plan - IMPLEMENTED

## Context

Phases 1-4 (parser, collector, bridge) are complete. Phase 5 (timeline visualization) is now implemented. The app renders an SVG timeline with color-coded memory regions on a dark background.

## Files

| File | Action | Purpose |
|------|--------|---------|
| `src/types.ts` | Create | Shared Region/Snapshot interfaces (fix `timestamp` -> `timestamp_ms` mismatch) |
| `src/regionColors.ts` | Create | Map region type strings to categories and hex colors |
| `src/useCollector.ts` | Modify | Accumulate snapshots in state, accept pid/interval params, return `Snapshot[]` |
| `src/Timeline.tsx` | Create | SVG timeline: log-scale Y-axis, region bands color-coded by category |
| `src/App.tsx` | Modify | Replace NewAppScreen template with Timeline, wire up useCollector |

## Prerequisite - DONE

Installed `react-native-svg` (15.15.3) and ran `pod install`.

## Implementation Steps - ALL DONE

### 1. `types.ts` - DONE

Extracted `Region` and `Snapshot` interfaces. Fixed `timestamp` -> `timestamp_ms` mismatch.

### 2. `regionColors.ts` - DONE

Two-tier lookup (exact match -> prefix rules -> gray fallback). Also added `__DATA_DIRTY` and `__AUTH*` prefix.

### 3. `useCollector.ts` - DONE

Accepts `pid`/`intervalMs` params, accumulates snapshots in state, resets on param change, returns `Snapshot[]`.

### 4. `Timeline.tsx` - DONE

Region tracking via `Map<string, TrackedRegion>` keyed by `${start}-${end}-${type}`. Log-scale Y-axis with `Math.log2()`. Auto-scales from data. Each region rendered as `<Rect>` with opacity 0.7.

### 5. `App.tsx` - DONE

Stripped template. Hardcoded PID=25038, INTERVAL_MS=1000. Full-window SVG on `#1a1a2e` background.

## Verification

1. Build the Zig dylib: `cd collector && zig build -Doptimize=ReleaseFast`
2. Run the app: `cd frontend && yarn macos`
3. Start a long-running process (e.g. `sleep 999`) and note its PID
4. Update the hardcoded PID constant in App.tsx to match
5. Expect: colored horizontal bands appearing on dark background, one new column per second
6. After a few snapshots, the timeline should show persistent regions as wide bands and short-lived regions as narrow bands
