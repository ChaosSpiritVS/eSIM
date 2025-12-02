import Foundation

struct OrderUsage: Codable, Hashable {
    let remainingMB: Double
    let expiresAt: Date?
    let lastUpdated: Date
    var allocatedMB: Double? = nil
    var usedMB: Double? = nil
    var dataUnitRaw: String? = nil
    var minutesAllocated: Double? = nil
    var minutesRemaining: Double? = nil
    var minutesUsed: Double? = nil
    var smsAllocated: Double? = nil
    var smsRemaining: Double? = nil
    var smsUsed: Double? = nil
    var supportsCallsSms: Bool? = nil
    var unlimited: Bool? = nil
    var iccid: String? = nil
    var planStatusText: String? = nil
    var policyStatusText: String? = nil
    var profileStatusText: String? = nil
}