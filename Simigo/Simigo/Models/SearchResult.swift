import Foundation

enum SearchKind: String, Codable, Hashable {
    case country
    case region
    case bundle
}

struct SearchResult: Identifiable, Hashable, Codable {
    let id: String
    let kind: SearchKind
    let title: String
    let subtitle: String?
    let countryCode: String?
    let regionCode: String?
    let bundleCode: String?
}