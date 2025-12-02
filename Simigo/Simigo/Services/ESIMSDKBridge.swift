import Foundation

// MARK: - eSIM 安装事件通知名
extension Notification.Name {
    static let esimInstallationSucceeded = Notification.Name("esimInstallationSucceeded")
    static let esimInstallationFailed = Notification.Name("esimInstallationFailed")
}

// MARK: - SDK 回调桥
// 将第三方 eSIM SDK 的安装结果，统一透传为应用内通知。
// 集成 SDK 后，在其成功/失败回调中调用对应方法即可。
enum ESIMSDKBridge {
    /// 安装成功回调
    /// - Parameters:
    ///   - orderId: 业务订单 ID（用于定位并刷新用量）
    ///   - iccid: 可选，设备侧返回的 ICCID（如可用可带上）
    static func installationSucceeded(orderId: String, iccid: String? = nil) {
        var info: [AnyHashable: Any] = ["orderId": orderId]
        if let iccid = iccid { info["iccid"] = iccid }
        NotificationCenter.default.post(name: .esimInstallationSucceeded, object: nil, userInfo: info)
    }

    /// 安装失败回调
    /// - Parameters:
    ///   - orderId: 业务订单 ID
    ///   - reason: 可选，失败原因或错误码
    static func installationFailed(orderId: String, reason: String? = nil) {
        var info: [AnyHashable: Any] = ["orderId": orderId]
        if let reason = reason { info["reason"] = reason }
        NotificationCenter.default.post(name: .esimInstallationFailed, object: nil, userInfo: info)
    }
}