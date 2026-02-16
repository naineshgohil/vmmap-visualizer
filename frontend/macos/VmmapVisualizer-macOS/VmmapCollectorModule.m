//
//  VmmapCollectorModule.m
//  VmmapVisualizer-macOS
//
//  Created by Naineshkumar  Gohil on 2026-02-14.
//

#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <dlfcn.h>

typedef struct {
  bool ok;
  const char *error_msg;
  void* ref;
} Result;

typedef struct {
     const char *region_type;
     uint64_t start_addr;
     uint64_t end_addr;
     uint64_t virtual_size;
     uint64_t resident_size;
 } CRegion;

 typedef struct {
     int64_t timestamp_ms;
     CRegion *regions;
     unsigned int region_count;
 } CSnapshot;

// Function pointers to Zig dylib
typedef Result (*CreateFn)(int, unsigned int, void (*)(const CSnapshot *));
typedef void (*DestroyFn)(void*);
typedef Result (*StartFn)(void*);
typedef void (*StopFn)(void*);
typedef unsigned int (*CountFn)(void*);
typedef char* (*GetJsonFn)(void*);
typedef void (*FreeStringFn)(char*);

@interface VmmapCollectorModule : RCTEventEmitter <RCTBridgeModule>
@property (nonatomic) void* collector;
@property (nonatomic) void* libHandle;
@property (nonatomic) CreateFn createFn;
@property (nonatomic) DestroyFn destroyFn;
@property (nonatomic) StartFn startFn;
@property (nonatomic) StopFn stopFn;
@property (nonatomic) CountFn countFn;
@property (nonatomic) GetJsonFn getJsonFn;
@property (nonatomic) FreeStringFn freeStringFn;
@end

@implementation VmmapCollectorModule

RCT_EXPORT_MODULE()

static VmmapCollectorModule *_sharedInstance = nil;

void onSnapshotCallback(const CSnapshot *snapshot) {
  NSMutableArray *regions = [NSMutableArray arrayWithCapacity:snapshot->region_count];
  
  for (unsigned int i = 0; i < snapshot->region_count; i++) {
    CRegion r = snapshot->regions[i];
    [regions addObject:@{
      @"type": [NSString stringWithUTF8String:r.region_type],
      @"start": @(r.start_addr),
      @"end": @(r.end_addr),
      @"vsize": @(r.virtual_size),
      @"rsize": @(r.resident_size),
    }];
  }
  
  NSDictionary *dict = @{
    @"timestamp_ms": @(snapshot->timestamp_ms),
    @"regions": regions,
  };
  
  [_sharedInstance sendEventWithName:@"onSnapshot" body:dict];
}


- (instancetype)init {
  self = [super init];
  if (self) {
    _sharedInstance = self;
    
    NSString *libPath = [[NSBundle mainBundle] pathForResource:@"libvmmap_collector" ofType:@"dylib"];
    _libHandle = dlopen([libPath UTF8String], RTLD_NOW);
    
    if (_libHandle) {
      _createFn = dlsym(_libHandle, "vmmap_collector_create");
      _destroyFn = dlsym(_libHandle, "vmmap_collector_destroy");
      _startFn = dlsym(_libHandle, "vmmap_collector_start");
      _stopFn = dlsym(_libHandle, "vmmap_collector_stop");
      _countFn = dlsym(_libHandle, "vmmap_collector_snapshot_count");
      _getJsonFn = dlsym(_libHandle, "vmmap_collector_get_snapshots_json");
      _freeStringFn = dlsym(_libHandle, "vmmap_free_string");
    }
  }
  
  return self;
}

-(NSArray<NSString *> *)supportedEvents {
  return @[@"onSnapshot"];
}

RCT_EXPORT_METHOD(create:(int)pid interval:(int)intervalMs resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  if (_collector) {
    _destroyFn(_collector);
  }
  
  Result r = _createFn(pid, (unsigned int) intervalMs, &onSnapshotCallback);
  
  if (r.ok) {
    _collector = r.ref;
    resolve(@"");
  } else {
    reject(@"CREATE_FAILED", [NSString stringWithUTF8String:r.error_msg], nil);
  }
}

RCT_EXPORT_METHOD(start:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  if (_collector && _startFn) {
    Result r = _startFn(_collector);
    
    if (r.ok) {
      resolve(@"");
    } else {
      reject(@"START_FAILED", [NSString stringWithUTF8String:r.error_msg], nil);
    }
  }
}

RCT_EXPORT_METHOD(stop) {
  if (_collector && _stopFn) {
    _stopFn(_collector);
  }
}

RCT_EXPORT_METHOD(getSnapshots:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  if (_collector && _getJsonFn) {
    char* json = _getJsonFn(_collector);
    
    if (json) {
      NSString *result = [NSString stringWithUTF8String:json];
      _freeStringFn(json);
      resolve(result);
    } else {
      resolve(@"[]");
    }
  } else {
    resolve(@"[]");
  }
}

- (void)dealloc {
  if (_collector && _destroyFn) {
    _destroyFn(_collector);
  }
  
  if (_libHandle) {
    dlclose(_libHandle);
  }
}

@end
