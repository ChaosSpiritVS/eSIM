import Foundation

struct Region: Identifiable, Hashable, Codable {
    var id: String { code }
    let code: String
    let name: String
}