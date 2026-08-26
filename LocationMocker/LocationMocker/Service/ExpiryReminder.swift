import UserNotifications

/// 签名到期本地提醒。
///
/// 免费 Personal Team 没有 APNs 权限，做不了远程推送；好在这个场景
/// 到期时间写在本地描述文件里，本地通知完全够用，不需要服务器。
enum ExpiryReminder {
    private static let notificationID = "signature-expiry-reminder"

    /// 每次启动调用：按描述文件到期日重新排程（到期前 1 天提醒）
    static func schedule() {
        guard let expiry = SignatureExpiry.expirationDate else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.removePendingNotificationRequests(withIdentifiers: [notificationID])
            let fireDate = expiry.addingTimeInterval(-24 * 3600)
            guard fireDate > Date() else { return }
            let content = UNMutableNotificationContent()
            content.title = "LocationMocker 签名即将到期"
            content.body = "免费开发者签名 7 天有效，到期后 App 将无法打开。请连接电脑重新安装一次（配对与收藏数据不受影响）。"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: fireDate.timeIntervalSinceNow,
                repeats: false
            )
            center.add(UNNotificationRequest(
                identifier: notificationID, content: content, trigger: trigger
            ))
        }
    }
}
