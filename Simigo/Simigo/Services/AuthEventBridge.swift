import Foundation

extension Notification.Name {
    static let sessionExpired = Notification.Name("sessionExpired")
}

enum AuthEventBridge {
    static func sessionExpired(reason: String? = nil) {
        var info: [AnyHashable: Any] = [:]
        if let r = reason { info["reason"] = r }
        Telemetry.shared.logEvent("session_expired", parameters: [
            "reason": reason ?? "-"
        ])
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .sessionExpired, object: nil, userInfo: info)
        }
    }
}
