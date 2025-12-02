import Foundation

struct Country: Identifiable, Hashable, Codable {
    var id: String { code }
    let code: String
    let name: String
}