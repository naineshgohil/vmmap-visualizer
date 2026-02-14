//
//  VmmapCollectorModule.m
//  VmmapVisualizer-macOS
//
//  Created by Naineshkumar  Gohil on 2026-02-14.
//

#import <React/RCTBridgeModule.h>
#import <dlfcn.h>

// Function pointers to Zig dylib
typedef void* (*CreateFn)(int, unsigned int);
typedef void (*DestroyFn)(void*);
typedef int (*StartFn)(int*);
typedef void (*StopFn)(void*);
typedef unsigned int (*CountFn)(void*);
typedef char* (*GetJsonFn)(void*);
typedef void (*FreeStringFn)(char*);

@interface VmmapCollectorModule : NSObject <RCTBridgeModule>
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

RCT_EXPORT_MODULE();

- (instancetype)init {
  self = [super init];
  if (self) {
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

RCT_EXPORT_METHOD(create:(int)pid interval:(int)intervalMs) {
  if (_collector) {
    _destroyFn(_collector);
  }
  
  _collector = _createFn(pid, (unsigned int) intervalMs);
}

RCT_EXPORT_METHOD(start) {
  if (_collector && _startFn) {
    _startFn(_collector);
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
