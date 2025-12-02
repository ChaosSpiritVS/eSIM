import Foundation

enum OrderStatus: String, Codable {
    case created
    case paid
    case failed
}

enum RefundState: String, Codable {
    case requested
    case reviewing
    case completed
    case rejected
}

struct RefundProgressStep: Codable, Hashable {
    let state: RefundState
    let updatedAt: Date
    let note: String?
}

struct RefundResult: Codable {
    let accepted: Bool
    let state: RefundState?
    let progress: [RefundProgressStep]?
}

struct Order: Identifiable, Codable, Hashable {
    let id: String
    let bundleId: String
    let amount: Decimal
    let currency: String
    let createdAt: Date
    let status: OrderStatus
    let paymentMethod: PaymentMethod
    let installation: OrderInstallationInfo?
    var orderStatusText: String? = nil
    var orderReference: String? = nil
    var bundleCategory: String? = nil
    var bundleMarketingName: String? = nil
    var bundleName: String? = nil
    var countryCode: String? = nil
    var countryName: String? = nil
    var iccid: String? = nil
    var bundleExpiryDate: Date? = nil
    var expiryDate: Date? = nil
    var planStarted: Bool? = nil
    var planStatusText: String? = nil
}