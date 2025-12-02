import Foundation

// 仓库协议
protocol CatalogRepositoryProtocol {
    func fetchPopularBundles() async throws -> [ESIMBundle]
    func fetchBundle(id: String) async throws -> ESIMBundle
}

enum CatalogError: Error {
    case notFound
}

// Mock 仓库（默认用于MVP）
struct MockCatalogRepository: CatalogRepositoryProtocol {
    func fetchPopularBundles() async throws -> [ESIMBundle] {
        try await Task.sleep(nanoseconds: 300_000_000)
        return [
            ESIMBundle(
                id: "hk-1",
                name: "中国香港",
                countryCode: "HK",
                price: 3.50,
                currency: "GBP",
                dataAmount: "1GB",
                validityDays: 7,
                description: "支持即时激活，适合短途旅行与过境。",
                supportedNetworks: ["4G/LTE", "5G"],
                hotspotSupported: true,
                coverageNote: "覆盖中国香港主要运营商。",
                termsURL: "https://example.com/terms"
            ),
            ESIMBundle(
                id: "cn-1",
                name: "中国",
                countryCode: "CN",
                price: 3.00,
                currency: "GBP",
                dataAmount: "1GB",
                validityDays: 7,
                description: "入境后即可使用，激活方便。",
                supportedNetworks: ["4G/LTE"],
                hotspotSupported: false,
                coverageNote: "部分地区覆盖受运营商影响。",
                termsURL: "https://example.com/terms-cn"
            )
        ]
    }

    func fetchBundle(id: String) async throws -> ESIMBundle {
        let all = try await fetchPopularBundles()
        if let found = all.first(where: { $0.id == id }) { return found }
        throw CatalogError.notFound
    }
}

// HTTP 仓库（后端就绪后切换）
struct HTTPCatalogRepository: CatalogRepositoryProtocol {
    let service: NetworkService = NetworkService()

    struct BundleDTO: Decodable {
        let id: String
        let name: String
        let countryCode: String
        let price: Double
        let currency: String
        let dataAmount: String
        let validityDays: Int
        let description: String?
        let supportedNetworks: [String]?
        let hotspotSupported: Bool?
        let coverageNote: String?
        let termsUrl: String?
    }

    func fetchPopularBundles() async throws -> [ESIMBundle] {
        let key = "catalog:popular"
        let bundles: [ESIMBundle] = try await RequestCenter.shared.singleFlight(key: key) {
            let dtos: [BundleDTO] = try await service.get("/catalog/bundles", query: ["popular": "true"]) // 与后端约定
            return dtos.map { dto in
                ESIMBundle(
                    id: dto.id,
                    name: dto.name,
                    countryCode: RegionCodeConverter.toAlpha2(dto.countryCode),
                    price: Decimal(dto.price),
                    currency: dto.currency,
                    dataAmount: dto.dataAmount,
                    validityDays: dto.validityDays,
                    description: dto.description,
                    supportedNetworks: dto.supportedNetworks,
                    hotspotSupported: dto.hotspotSupported,
                    coverageNote: dto.coverageNote,
                    termsURL: dto.termsUrl
                )
            }
        }
        return bundles
    }

    func fetchBundle(id: String) async throws -> ESIMBundle {
        let key = ["catalog:bundle", id].joined(separator: "|")
        let bundle: ESIMBundle = try await RequestCenter.shared.singleFlight(key: key) {
            let dto: BundleDTO = try await service.get("/catalog/bundle/\(id)")
            return ESIMBundle(
                id: dto.id,
                name: dto.name,
                countryCode: RegionCodeConverter.toAlpha2(dto.countryCode),
                price: Decimal(dto.price),
                currency: dto.currency,
                dataAmount: dto.dataAmount,
                validityDays: dto.validityDays,
                description: dto.description,
                supportedNetworks: dto.supportedNetworks,
                hotspotSupported: dto.hotspotSupported,
                coverageNote: dto.coverageNote,
                termsURL: dto.termsUrl
            )
        }
        return bundle
    }
}