import Foundation

enum PaymentMethod: String, Codable, CaseIterable, Identifiable {
    case paypal
    case card
    case alipay
    case applepay
    case googlepay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paypal: return "PayPal"
        case .card: return "银行卡"
        case .alipay: return "支付宝"
        case .applepay: return "Apple Pay"
        case .googlepay: return "Google Pay"
        }
    }

    var systemImage: String {
        switch self {
        case .paypal: return "p.circle" // 占位图标
        case .card: return "creditcard"
        case .alipay: return "a.circle" // 占位图标
        case .applepay: return "applelogo"
        case .googlepay: return "g.circle"
        }
    }
}