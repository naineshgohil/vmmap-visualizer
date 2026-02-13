# vmmap Output Format

Reference documentation for parsing `vmmap` output on macOS.

## Command

```bash
vmmap <pid>
vmmap -w <pid>        # Wide output (full paths)
vmmap -resident <pid> # Include resident memory details
```

## Output Structure

```
[Header]
[Non-writable regions]
[Writable regions]
[Summary by region type]
[MALLOC ZONE table]
```

## Header Section

```
Process:         Finder [677]
Path:            /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder
Load Address:    0x100484000
Identifier:      com.apple.finder
Version:         26.2 (1828.2.3)
Code Type:       ARM64E
Platform:        macOS
Parent Process:  launchd [1]

Date/Time:       2026-02-11 09:22:08.866 -0500
Launch Time:     2026-02-11 04:00:29.952 -0500
OS Version:      macOS 26.2 (25C56)

Physical footprint:         177.0M
Physical footprint (peak):  243.6M

Virtual Memory Map of process 677 (Finder)
Output report format:  2.4  -- 64-bit process
VM page size:  16384 bytes
```

## Region Line Format

```
REGION TYPE                    START - END         [ VSIZE  RSDNT  DIRTY   SWAP] PRT/MAX SHRMOD PURGE    REGION DETAIL
```

### Example Lines

```
__TEXT                      100484000-100f3c000    [ 10.7M  7904K     0K     0K] r-x/r-x SM=COW          /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder
MALLOC_SMALL                102000000-103000000    [ 16.0M  2048K  2048K     0K] rw-/rwx SM=PRV          DefaultMallocZone_0x101a14000
Stack                       16f800000-170000000    [ 8192K   128K   128K     0K] rw-/rwx SM=PRV          thread 0
mapped file                 1060f8000-106868000    [ 7616K   976K     0K     0K] r--/rw- SM=COW          /System/Library/CoreServices/SystemAppearance.bundle/Contents/Resources/DarkAqua.car
shared memory               101190000-101198000    [   32K    32K    32K     0K] r--/r-- SM=SHM
VM_ALLOCATE                 101104000-101108000    [   16K     0K     0K     0K] ---/rwx SM=NUL
```

## Fields

| Field | Position | Description |
|-------|----------|-------------|
| Region Type | Column 1 | Category of memory region |
| Start Address | After type | Hex address (no 0x prefix) |
| End Address | After `-` | Hex address (no 0x prefix) |
| Virtual Size | Bracket [1] | Total virtual size |
| Resident Size | Bracket [2] | Physical memory used |
| Dirty Size | Bracket [3] | Modified pages |
| Swap Size | Bracket [4] | Swapped to disk |
| Permissions | After `]` | Current/Max (r/w/x or -) |
| Sharing Mode | After `SM=` | COW, PRV, SHM, NUL, ALI, S/A |
| Purge | After `PURGE=` | Y or N (optional) |
| Region Detail | End of line | Path, zone name, thread, or empty |

## Region Types

### Code Segments
| Type | Description |
|------|-------------|
| `__TEXT` | Executable code |
| `__LINKEDIT` | Linker metadata |
| `__OBJC_RO` | Objective-C read-only data |
| `__AUTH` | Authenticated pointers (ARM64E) |
| `__AUTH_CONST` | Authenticated constants |

### Data Segments
| Type | Description |
|------|-------------|
| `__DATA` | Initialized read-write data |
| `__DATA_CONST` | Read-only after initialization |
| `__DATA_DIRTY` | Frequently modified data |
| `__OBJC_RW` | Objective-C read-write data |

### Heap (malloc zones)
| Type | Description |
|------|-------------|
| `MALLOC_TINY` | Small allocations (< 1KB) |
| `MALLOC_SMALL` | Medium allocations |
| `MALLOC_LARGE` | Large allocations |
| `MALLOC metadata` | Zone bookkeeping |
| `MALLOC guard page` | Protection pages |
| `MALLOC_NANO metadata` | Nano zone metadata |

### Stack
| Type | Description |
|------|-------------|
| `Stack` | Thread stack |
| `STACK GUARD` | Guard pages between stacks |
| `Stack Guard` | Per-thread guard page |
| `Stack (reserved)` | Reserved but not committed |

### Mapped Files
| Type | Description |
|------|-------------|
| `mapped file` | Memory-mapped file |
| `dyld private memory` | Dynamic linker internal |

### Shared Memory
| Type | Description |
|------|-------------|
| `shared memory` | POSIX shared memory |
| `IOKit` | IOKit shared regions |
| `IOAccelerator` | GPU-related shared memory |
| `IOSurface` | GPU surfaces |

### System
| Type | Description |
|------|-------------|
| `VM_ALLOCATE` | vm_allocate() regions |
| `Kernel Alloc Once` | Lazy kernel allocations |
| `CoreAnimation` | CA layer backing stores |
| `CoreGraphics` | CG rendering buffers |
| `ColorSync` | Color management data |
| `Activity Tracing` | os_log buffers |

## Sharing Modes

| Mode | Description |
|------|-------------|
| `COW` | Copy-on-write (shared until modified) |
| `PRV` | Private (not shared) |
| `SHM` | Explicitly shared memory |
| `NUL` | No physical pages (reserved only) |
| `ALI` | Aliased (multiple mappings) |
| `S/A` | Shared/aliased |

## Permissions

Format: `current/max`

| Char | Meaning |
|------|---------|
| `r` | Readable |
| `w` | Writable |
| `x` | Executable |
| `-` | Denied |

Examples:
- `r-x/r-x` - Read+execute only (code)
- `rw-/rwx` - Read+write, could become executable
- `r--/rw-` - Read-only, could become writable
- `---/rwx` - No access currently (guard page)

## Size Suffixes

| Suffix | Multiplier |
|--------|------------|
| (none) | Bytes |
| `K` | 1,024 |
| `M` | 1,048,576 |
| `G` | 1,073,741,824 |

Note: Raw byte values appear without suffix (e.g., `824` means 824 bytes).

## Summary Section

After all regions, vmmap outputs aggregated stats:

```
REGION TYPE                          VIRTUAL   RESIDENT    DIRTY     SWAP    ...
===========                          =======   ========    =====    =====
MALLOC_SMALL                          124.0M      20.0M    20.0M    53.7M    ...
Stack                                  11.2M       112K     112K     256K    ...
__TEXT                                  1.2G     325.1M       0K       0K    ...
...
===========                          =======   ========    =====    =====
TOTAL                                   2.8G     514.8M    23.1M   153.9M    ...
```

## Parsing Notes

1. **Section markers**: Look for `==== Non-writable` and `==== Writable` to identify region sections
2. **Multi-word types**: Some types have spaces, e.g., `MALLOC guard page`, `shared memory`, `mapped file`
3. **Parenthetical suffixes**: Some types have qualifiers, e.g., `MALLOC_SMALL (empty)`, `Stack (reserved)`
4. **Address format**: Always hex without `0x` prefix, uppercase A-F
5. **Variable whitespace**: Columns are space-aligned, not tab-separated
6. **Optional fields**: PURGE and REGION DETAIL may be absent