// SharedConfig.h
// 位置模拟数据协议 — App 与 Tweak 之间的通信契约
//
// App 将模拟配置写入共享文件，Tweak 读取并注入系统定位服务
// 路径 (rootless jailbreak): /var/jb/var/mobile/Documents/location_mock_config.plist
// 路径 (rootful jailbreak):    /var/mobile/Documents/location_mock_config.plist

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

/// 共享 plist 文件名
static NSString * const kMockConfigFileName = @"location_mock_config.plist";

/// 模拟配置数据结构
/// plist 格式:
/// {
///   "enabled": <bool>,
///   "latitude": <double>,
///   "longitude": <double>,
///   "altitude": <double>,
///   "speed": <double>,        // m/s
///   "course": <double>,       // degrees
///   "horizontalAccuracy": <double>,
///   "verticalAccuracy": <double>,
///   "timestamp": <double>,    // Unix timestamp
///   "routePoints": [          // 路线点数组 (用于动态路线)
///     {"lat": <double>, "lon": <double>, "alt": <double>},
///     ...
///   ],
///   "routeIndex": <int>,
///   "updateInterval": <double>, // seconds
///   "mode": <string>           // "fixed" | "route" | "track"
/// }

/// 获取共享配置文件路径 (自动适配 rootless/rootful)
static NSString *GetMockConfigPath(void) {
    // rootless jailbreak 路径
    NSString *rootless = @"/var/jb/var/mobile/Documents";
    if ([[NSFileManager defaultManager] fileExistsAtPath:rootless]) {
        return [rootless stringByAppendingPathComponent:kMockConfigFileName];
    }
    // rootful jailbreak 路径 (兼容旧版)
    return [@"/var/mobile/Documents" stringByAppendingPathComponent:kMockConfigFileName];
}

/// 从 plist 读取模拟配置
static NSDictionary *LoadMockConfig(void) {
    return [NSDictionary dictionaryWithContentsOfFile:GetMockConfigPath()];
}

/// 从配置字典构造 CLLocation 对象
static CLLocation *CLLocationFromConfig(NSDictionary *config) {
    if (!config || ![config[@"enabled"] boolValue]) return nil;

    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(
        [config[@"latitude"] doubleValue],
        [config[@"longitude"] doubleValue]
    );
    CLLocationDistance alt = [config[@"altitude"] doubleValue];
    CLLocationAccuracy hAcc = [config[@"horizontalAccuracy"] doubleValue] ?: 5.0;
    CLLocationAccuracy vAcc = [config[@"verticalAccuracy"] doubleValue] ?: 10.0;
    CLLocationSpeed speed = [config[@"speed"] doubleValue];
    CLLocationDirection course = [config[@"course"] doubleValue];
    NSTimeInterval ts = [config[@"timestamp"] doubleValue] ?: [[NSDate date] timeIntervalSince1970];

    return [[CLLocation alloc] initWithCoordinate:coord
                                         altitude:alt
                               horizontalAccuracy:hAcc
                                 verticalAccuracy:vAcc
                                           course:course
                                            speed:speed
                                        timestamp:[NSDate dateWithTimeIntervalSince1970:ts]];
}
