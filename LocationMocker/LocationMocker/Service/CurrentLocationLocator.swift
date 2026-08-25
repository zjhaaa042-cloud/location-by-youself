import CoreLocation

/// 一次性获取当前系统定位（供「定位到当前位置」按钮使用）。
///
/// 与 LocationVerifier 的长期校验不同，这里只做单次 requestLocation。
/// 注意：系统注入激活期间读到的是模拟后的坐标——这正是期望行为
/// （「当前位置」= 系统认为你在哪里）。
final class CurrentLocationLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((CLLocationCoordinate2D?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// 请求一次当前位置；未授权时先发起授权，被拒绝/失败时回调 nil
    func request(completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        self.completion = completion
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            finish(nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        let callback = completion
        completion = nil
        callback?(coordinate)
    }
}
