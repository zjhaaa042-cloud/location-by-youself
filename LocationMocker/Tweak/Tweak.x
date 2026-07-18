// Tweak.x — LocationMocker 越狱插件
// 挂钩 CoreLocation 框架，向所有 App 注入模拟定位数据
//
// 支持的 jailbreak: Dopamine (rootless), palera1n (rootful/rootless)
// 最低 iOS 版本: 14.0
// 构建: make package THEOS_PACKAGE_SCHEME=rootless

#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "SharedConfig.h"

#pragma mark - 配置

// 注入目标: 所有进程 (通过 plist filter: CoreLocation)
// 如果只想注入特定 App，修改 plist 中的 BundleIdentifier 过滤

// 定时器 tick 间隔 (秒)
static const NSTimeInterval kTickInterval = 1.0;

// 全局状态
static BOOL _isMocking = NO;
static NSTimer *_mockTimer = nil;
static NSDictionary *_cachedConfig = nil;
static NSArray *_cachedRoutePoints = nil;
static NSInteger _cachedRouteIndex = 0;

#pragma mark - 辅助函数

/// 获取 CLLocationManager 的 delegate (私有 ivar)
static id GetLocationManagerDelegate(id manager) {
    return object_getIvar(manager, class_getInstanceVariable([manager class], "_delegate"));
}

/// 获取 delegate 的弱引用包装
static id GetWeakDelegateWrapper(id manager) {
    return object_getIvar(manager, class_getInstanceVariable([manager class], "_delegate"));
}

/// 向 delegate 发送 didUpdateToLocation 回调
/// iOS 14+ 使用 locationManager:didUpdateLocations:
static void SendMockLocationToDelegate(id manager, CLLocation *location) {
    id delegate = GetLocationManagerDelegate(manager);

    // iOS 6+: locationManager:didUpdateLocations:
    if ([delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        NSArray *locations = @[location];
        // 使用 objc_msgSend 避免 ARC 问题
        SEL sel = @selector(locationManager:didUpdateLocations:);
        NSMethodSignature *sig = [delegate methodSignatureForSelector:sel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:delegate];
        [inv setSelector:sel];
        [inv setArgument:&manager atIndex:2];
        [inv setArgument:&locations atIndex:3];
        [inv invoke];
    }
    // 兼容旧版: locationManager:didUpdateToLocation:fromLocation:
    else if ([delegate respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) {
        SEL sel = @selector(locationManager:didUpdateToLocation:fromLocation:);
        CLLocation *old = location; // 使用同一个位置作为 old
        NSMethodSignature *sig = [delegate methodSignatureForSelector:sel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:delegate];
        [inv setSelector:sel];
        [inv setArgument:&manager atIndex:2];
        [inv setArgument:&location atIndex:3];
        [inv setArgument:&old atIndex:4];
        [inv invoke];
    }
}

/// 读取配置并返回是否启用
static BOOL ReloadConfig(void) {
    _cachedConfig = LoadMockConfig();
    if (!_cachedConfig) return NO;

    BOOL enabled = [_cachedConfig[@"enabled"] boolValue];
    if (!enabled) return NO;

    // 缓存路线数据
    _cachedRoutePoints = _cachedConfig[@"routePoints"];
    _cachedRouteIndex = [_cachedConfig[@"routeIndex"] integerValue];

    return YES;
}

/// 获取当前应发送的位置
static CLLocation *GetCurrentMockLocation(void) {
    NSString *mode = _cachedConfig[@"mode"] ?: @"fixed";

    if ([mode isEqualToString:@"route"] || [mode isEqualToString:@"track"]) {
        if (_cachedRoutePoints && _cachedRoutePoints.count > 0) {
            // 从路线点构造 CLLocation
            NSInteger idx = _cachedRouteIndex;
            if (idx < 0 || idx >= (NSInteger)_cachedRoutePoints.count) {
                idx = 0;
            }
            NSDictionary *pt = _cachedRoutePoints[idx];

            CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(
                [pt[@"lat"] doubleValue],
                [pt[@"lon"] doubleValue]
            );
            CLLocationDistance alt = [pt[@"alt"] doubleValue];

            return [[CLLocation alloc] initWithCoordinate:coord
                                                 altitude:alt
                                       horizontalAccuracy:5.0
                                         verticalAccuracy:10.0
                                                   course:[_cachedConfig[@"course"] doubleValue]
                                                    speed:[_cachedConfig[@"speed"] doubleValue]
                                                timestamp:[NSDate date]];
        }
    }

    // 固定点模式
    return CLLocationFromConfig(_cachedConfig);
}

/// 更新路线索引 (由定时器调用)
static void AdvanceRouteIndex(void) {
    if (!_cachedRoutePoints || _cachedRoutePoints.count == 0) return;

    NSString *mode = _cachedConfig[@"mode"] ?: @"fixed";
    NSInteger count = (NSInteger)_cachedRoutePoints.count;
    NSInteger index = _cachedRouteIndex;
    NSString *playbackMode = _cachedConfig[@"playbackMode"] ?: @"once";

    if ([playbackMode isEqualToString:@"loop"]) {
        index = (index + 1) % count;
    } else if ([playbackMode isEqualToString:@"pingPong"]) {
        // pingpong 方向由外部管理，这里简化为循环
        index = (index + 1) % count;
    } else {
        // once: 到达末尾后停用
        if (index + 1 >= count) {
            _isMocking = NO;
            [_mockTimer invalidate];
            _mockTimer = nil;
            return;
        }
        index = index + 1;
    }

    _cachedRouteIndex = index;

    // 写回 plist 以同步进度
    NSMutableDictionary *mutable = [_cachedConfig mutableCopy];
    mutable[@"routeIndex"] = @(index);
    [mutable writeToFile:GetMockConfigPath() atomically:YES];
    _cachedConfig = mutable;
}

/// 定时器回调
static void MockTimerTick(NSTimer *timer) {
    if (!_isMocking) {
        [timer invalidate];
        _mockTimer = nil;
        return;
    }

    // 重新加载配置 (允许热更新)
    if (!ReloadConfig()) {
        _isMocking = NO;
        [timer invalidate];
        _mockTimer = nil;
        return;
    }

    AdvanceRouteIndex();
}

#pragma mark - CLLocationManager Hook

%hook CLLocationManager

// Hook: 启动定位更新
- (void)startUpdatingLocation {
    // 检查是否启用了模拟
    if (ReloadConfig()) {
        _isMocking = YES;

        // 仍然调用原始方法 (保持系统状态一致)
        %orig;

        // 启动定时器向 delegate 发送模拟位置
        if (!_mockTimer) {
            dispatch_async(dispatch_get_main_queue(), ^{
                _mockTimer = [NSTimer scheduledTimerWithTimeInterval:kTickInterval
                                                              target:[NSBlockOperation blockOperationWithBlock:^{
                    @autoreleasepool {
                        if (!_isMocking) return;
                        CLLocation *mock = GetCurrentMockLocation();
                        if (mock) {
                            @try {
                                SendMockLocationToDelegate(self, mock);
                            } @catch (NSException *e) {
                                NSLog(@"[LocationMocker] 发送模拟位置异常: %@", e);
                            }
                        }
                    }
                }]
                                                            selector:@selector(main)
                                                            userInfo:nil
                                                             repeats:YES];
                // 立即发送第一个位置
                CLLocation *firstMock = GetCurrentMockLocation();
                if (firstMock) {
                    SendMockLocationToDelegate(self, firstMock);
                }
            });
        }
    } else {
        %orig;
    }
}

// Hook: 停止定位更新
- (void)stopUpdatingLocation {
    %orig;
    if (_isMocking) {
        [_mockTimer invalidate];
        _mockTimer = nil;
        _isMocking = NO;
    }
}

// Hook: location 属性 getter — 返回模拟位置
- (CLLocation *)location {
    if (_isMocking) {
        CLLocation *mock = GetCurrentMockLocation();
        if (mock) return mock;
    }
    return %orig;
}

%end

#pragma mark - 构造函数

%ctor {
    NSLog(@"[LocationMocker] Tweak 已加载 — 全局位置模拟已就绪");
    // 延迟初始化，等待系统完全启动
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSLog(@"[LocationMocker] 初始化完成，等待模拟指令...");
    });

    // 监听 App 写入配置的通知
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center, NULL,
        (CFNotificationCallback)ConfigChangedCallback,
        CFSTR("com.example.locationmocker.configChanged"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
}

/// App 更新配置后的回调
static void ConfigChangedCallback(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    NSLog(@"[LocationMocker] 配置已更新，重新加载...");
    ReloadConfig();
}
