import Foundation

struct User: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let lastName: String?
    let email: String?
    let hasPassword: Bool
    let kycStatus: String?
    let kycProvider: String?
    let kycReference: String?
    let kycVerifiedAt: Date?
}
