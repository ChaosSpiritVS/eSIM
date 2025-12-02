import Foundation

struct OrderInstallationInfo: Codable, Hashable {
    let qrCodeURL: String?
    let activationCode: String?
    let instructions: [String]
    let profileURL: String?
    let smdpAddress: String?
}