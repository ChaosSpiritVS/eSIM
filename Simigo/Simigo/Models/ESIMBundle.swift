import Foundation

struct ESIMBundle: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let countryCode: String
    let price: Decimal
    let currency: String
    let dataAmount: String
    let validityDays: Int
    let description: String?
    let supportedNetworks: [String]?
    let hotspotSupported: Bool?
    let coverageNote: String?
    let termsURL: String?
    let bundleTag: [String]?
    let isActive: Bool?
    let serviceType: String?
    let supportTopup: Bool?
    let unlimited: Bool?

    init(
        id: String,
        name: String,
        countryCode: String,
        price: Decimal,
        currency: String,
        dataAmount: String,
        validityDays: Int,
        description: String?,
        supportedNetworks: [String]?,
        hotspotSupported: Bool?,
        coverageNote: String?,
        termsURL: String?,
        bundleTag: [String]? = nil,
        isActive: Bool? = nil,
        serviceType: String? = nil,
        supportTopup: Bool? = nil,
        unlimited: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.countryCode = countryCode
        self.price = price
        self.currency = currency
        self.dataAmount = dataAmount
        self.validityDays = validityDays
        self.description = description
        self.supportedNetworks = supportedNetworks
        self.hotspotSupported = hotspotSupported
        self.coverageNote = coverageNote
        self.termsURL = termsURL
        self.bundleTag = bundleTag
        self.isActive = isActive
        self.serviceType = serviceType
        self.supportTopup = supportTopup
        self.unlimited = unlimited
    }
}
