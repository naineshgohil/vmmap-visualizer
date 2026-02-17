# Concepts Learned - vmmap Visualizer

## React Native Bridge

### RCT_EXPORT_METHOD

The macro does two things at compile time:
1. Generates a hidden `+__rct_export__<name>` class method that returns metadata (selector string)
2. Defines the actual instance method

At app startup, `RCTBridge` uses the ObjC runtime to enumerate all `+__rct_export__*` methods on classes conforming to `<RCTBridgeModule>`, calls each to get selector strings, and builds a JS-to-ObjC dispatch table.

`RCT_EXPORT_MODULE()` is required alongside it -- implements `+moduleName` so the bridge discovers the class.

### ObjC Method Syntax

The repeated identifier in `count:(int)count` serves two roles:
- First `count:` is the **selector label** (part of the method name, visible to callers)
- Second `count` is the **parameter name** (used inside the method body)

They don't have to match: `count:(int)n` is valid. Same concept Swift inherited.

### Promise Pattern

When the last two parameters are `RCTPromiseResolveBlock` and `RCTPromiseRejectBlock`, React Native automatically makes the JS method return a `Promise`. JS never sees those parameters.

`reject` takes three arguments: `(NSString *code, NSString *message, NSError *underlyingError)`.

### RCTEventEmitter (Push Model)

Extend `RCTEventEmitter` instead of `NSObject` to push events from native to JS without JS polling. Requires:
- `#import <React/RCTEventEmitter.h>`
- Override `-(NSArray<NSString *> *)supportedEvents`
- Call `[self sendEventWithName:@"eventName" body:dict]`

JS listens with `NativeEventEmitter`:
```ts
const emitter = new NativeEventEmitter(NativeModule);
const sub = emitter.addListener('eventName', handler);
```

### NSDictionary vs JSON

React Native's bridge automatically converts `NSDictionary -> {}` and `NSArray -> []` to JS objects. Building NSDictionary in ObjC and passing it through the bridge avoids the double cost of JSON serialization (Zig) + JSON.parse (JS).

### console.log to Xcode

`console.log` in React Native is bridged to `NSLog`, which writes to stderr. Xcode's console captures stderr, which is why JS logs appear there alongside `std.debug.print` output from Zig (also writes to stderr).

## Zig C ABI

### extern struct

Required for C-compatible memory layout. Every field must be a C-compatible type (`u64`, `c_int`, `bool`, `[*]T`, `[*:0]const u8`, etc.). Internal Zig types like `[]const u8` (slice), `?[]const u8` (optional slice), `std.mem.Allocator` are not C-compatible.

Keep two sets of types: internal Zig types for the parser/collector, and `extern struct` types for the C boundary. Convert at the boundary.

### Default Field Values

`extern struct` fields can have defaults:
```zig
const Result = extern struct {
    ok: bool,
    error_msg: ?[*:0]const u8 = null,
    ref: ?*anyopaque = null,
};
// Allows: return .{ .ok = true };
```

### Return Type Conventions

| Pattern | Return Type | Meaning |
|---------|-------------|---------|
| Pointer result | `?*T` | null = failed, non-null = success |
| Status code | `c_int` | 0 = success, negative = error |
| Rich error | `extern struct { ok, error_msg }` | Structured result with message |
| Cleanup | `void` | Accept null gracefully (no-op) |

Returning a Result struct with `error_msg` keeps error knowledge in Zig where failures actually happen, instead of mapping integer codes in ObjC.

### Slice to C String

Zig `[]const u8` is not null-terminated. C needs `[*:0]const u8`. Must copy:
```zig
fn toCString(slice: []const u8) ?[*:0]const u8 {
    const buf = allocator.allocSentinel(u8, slice.len, 0) catch return null;
    @memcpy(buf, slice);
    return buf;
}
```

### Optional Unwrapping

- `.?` -- force unwrap: `result.snapshot.?` (crashes if null)
- `if (opt) |val|` -- safe unwrap with capture
- Cannot combine two conditions with a single capture: `if (a and b) |val|` is invalid
- Chain instead: `if (a) { if (b) |val| { ... } }`

### Function Pointer Callbacks

Pass C-compatible function pointers across the ABI boundary for push-based communication:
```zig
// Zig stores the callback
var on_push: *const fn (*const CSnapshot) callconv(.c) void = undefined;

// ObjC passes it during create
typedef void (*SnapshotCallback)(const CSnapshot *);
typedef Result (*CreateFn)(int, unsigned int, SnapshotCallback);
```

Internal Zig code uses a wrapper to avoid leaking `callconv(.c)` into non-ABI code:
```zig
fn onSnapshot(snapshot: *const types.Snapshot) void {
    // convert and call on_push
}
```

## macOS Threading

### Everything is a pthread

The kernel provides one primitive: Mach threads, wrapped as pthreads. Every threading API -- `std.Thread.spawn`, `NSThread`, `dispatch_async`, `std::thread` -- calls `pthread_create` underneath.

### Three Threads in This App

1. **Main thread** -- runs the AppKit run loop (event dispatch). Blocking it freezes the app.
2. **JS thread** -- React Native spawns a dedicated pthread for the JS engine. All JS code runs here.
3. **Collection thread** -- spawned by `std.Thread.spawn` via `pthread_create`. Runs the vmmap capture loop.

### GCD (Grand Central Dispatch)

React Native gives each native module a GCD serial queue. `RCT_EXPORT_METHOD` calls run on a thread from GCD's pool, not the main thread. Serial means methods on one module never overlap.

### Thread Communication

- **Atomic bool** (`std.atomic.Value(bool)`) -- for signaling (start/stop). Not sufficient for protecting data structures.
- **Shared memory** -- threads read/write the same `ArrayList`. `ArrayList` is not thread-safe; concurrent read + write is a data race.
- **Callback** -- collection thread pushes data to ObjC via function pointer. Avoids concurrent access to the ArrayList.

### Viewing Threads

Activity Monitor shows processes, not threads. Use:
```bash
ps -M <pid>       # shows each thread as a row
top -pid <pid>    # shows thread count
```

## Architecture: Pull vs Push

### Pull (old)
JS polls with `getSnapshots()` on an interval. Zig serializes ALL snapshots to JSON every call. Data race: ObjC reads ArrayList while Zig thread writes to it.

### Push (new)
Collection thread captures snapshot, converts to CSnapshot via callback, ObjC builds NSDictionary, emits event to JS. One snapshot per event. No polling, no full-history serialization, no concurrent ArrayList access.

## Dynamic Library Loading

Zig compiles to `libvmmap_collector.dylib`. At runtime, no Zig compiler/runtime is needed -- it's plain machine code. ObjC loads it with:
```objc
dlopen(path, RTLD_NOW);     // load dylib
dlsym(handle, "fn_name");   // get function pointer
dlclose(handle);             // unload
```

The dylib is bundled inside `VmmapVisualizer.app/Contents/Resources/` by an Xcode build phase.
