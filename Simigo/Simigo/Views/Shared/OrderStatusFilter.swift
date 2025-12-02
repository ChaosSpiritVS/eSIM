import Foundation

enum OrderStatusFilter: Hashable {
    case all
    case created
    case paid
    case failed
}