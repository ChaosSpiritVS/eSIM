import Foundation

// MARK: - 支付事件通知名
extension Notification.Name {
    static let paymentSucceeded = Notification.Name("paymentSucceeded")
    static let paymentFailed = Notification.Name("paymentFailed")
}

// MARK: - 支付事件桥
// 在支付 SDK 或支付流程回调中调用以下方法，将事件透传到应用内。
enum PaymentEventBridge {
    /// 支付成功事件
    /// - Parameters:
    ///   - orderId: 当前订单 ID（可能是上游订单ID）
    ///   - oldOrderId: 可选，支付前的本地订单ID（在别名模式下可能被替换）
    ///   - method: 可选，支付方式标识
    static func paymentSucceeded(orderId: String, oldOrderId: String? = nil, method: String? = nil) {
        var info: [AnyHashable: Any] = ["orderId": orderId]
        if let old = oldOrderId { info["oldOrderId"] = old }
        if let m = method { info["method"] = m }
        Telemetry.shared.logEvent("payment_success", parameters: ["order_id": orderId, "old_order_id": oldOrderId ?? "-", "method": method ?? "-"])
        Telemetry.shared.log("payment_success_\(orderId)")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .paymentSucceeded, object: nil, userInfo: info)
        }
    }

    /// 支付失败事件
    static func paymentFailed(orderId: String, reason: String? = nil, method: String? = nil, error: Error? = nil) {
        var info: [AnyHashable: Any] = ["orderId": orderId]
        if let r = reason { info["reason"] = r }
        if let m = method { info["method"] = m }
        let category = reasonCategory(reason: reason, error: error)
        info["reasonCategory"] = category.category
        if let code = category.code { info["reasonCode"] = code }
        Telemetry.shared.logEvent("payment_failed", parameters: [
            "order_id": orderId,
            "reason": reason ?? "-",
            "method": method ?? "-",
            "reason_category": category.category,
            "reason_code": category.code ?? "-"
        ])
        if let e = error { Telemetry.shared.record(error: e) }
        else {
            let err = NSError(domain: "Payment", code: -1, userInfo: [NSLocalizedDescriptionKey: reason ?? "unknown"])
            Telemetry.shared.record(error: err)
        }
        Telemetry.shared.log("payment_failed_\(orderId)")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .paymentFailed, object: nil, userInfo: info)
        }
    }

    static func reasonCategory(reason: String?, error: Error?) -> (category: String, code: String?) {
        if let e = error as? NetworkError {
            switch e {
            case .offline:
                return ("network", "offline")
            case .badStatus(let s):
                return ("network", "http_\(s)")
            case .server(let code, _):
                return ("server", "srv_\(code)")
            case .decoding:
                return ("client", "decoding")
            case .invalidURL:
                return ("client", "invalid_url")
            }
        }
        if let ue = error as? URLError {
            switch ue.code {
            case .timedOut: return ("network", "timeout")
            case .notConnectedToInternet: return ("network", "offline")
            case .networkConnectionLost: return ("network", "conn_lost")
            case .cannotConnectToHost: return ("network", "cannot_connect")
            case .dnsLookupFailed: return ("network", "dns")
            default: return ("network", String(describing: ue.code))
            }
        }
        if let ns = error as NSError?, ns.domain.hasPrefix("payment.") {
            return ("sdk", ns.domain)
        }
        let r = (reason ?? "").lowercased()
        if r.contains("余额") || r.contains("insufficient") || r.contains("balance") {
            return ("balance", nil)
        }
        if r.contains("sdk") || r.contains("未集成") || r.contains("alipay sdk") {
            return ("sdk", nil)
        }
        if r.contains("服务器") || r.contains("上游") || r.contains("server") {
            return ("server", nil)
        }
        if r.contains("网络") || r.contains("offline") || r.contains("timeout") || r.contains("connect") {
            return ("network", nil)
        }
        return ("unknown", nil)
    }
}
