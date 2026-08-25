import UIKit

/// LocalDevVPN 安装检测与跳转。
///
/// 免费 Personal Team 无法签名 Network Extension，系统注入依赖 LocalDevVPN
/// 提供回环隧道。LocalDevVPN 注册了 `localdevvpn://` URL Scheme，
/// 可用 `canOpenURL` 判断是否已安装（需在 Info.plist 声明
/// `LSApplicationQueriesSchemes`）。
enum LocalDevVPNGuide {
    private static let appScheme = URL(string: "localdevvpn://")!
    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044")!

    static var isInstalled: Bool {
        UIApplication.shared.canOpenURL(appScheme)
    }

    static func openApp() {
        UIApplication.shared.open(appScheme)
    }

    static func openAppStore() {
        UIApplication.shared.open(appStoreURL)
    }
}
