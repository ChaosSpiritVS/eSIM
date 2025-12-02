import Foundation

protocol SearchRepositoryProtocol {
    func search(q: String, include: [String]?, limit: Int) async throws -> [SearchResult]
    // 生成单飞 key，便于 ViewModel 进行精准取消
    func makeKey(q: String, include: [String]?, limit: Int) -> String
    func recent(limit: Int, sort: String) async throws -> [SearchResult]
    func logSelection(_ r: SearchResult) async throws -> Bool
}

struct HTTPSearchRepository: SearchRepositoryProtocol {
    private let service = NetworkService()

    private struct SearchResultDTO: Decodable {
        let kind: String
        let id: String
        let title: String
        let subtitle: String?
        let countryCode: String?
        let regionCode: String?
        let bundleCode: String?
    }

    private struct SuccessDTO: Decodable { let success: Bool? }

    func makeKey(q: String, include: [String]? = nil, limit: Int = 20) -> String {
        let inc = (include ?? ["country", "region", "bundle"]).joined(separator: ",")
        let lang = UserDefaults.standard.string(forKey: "simigo.languageCode") ?? Locale.preferredLanguages.first ?? "en"
        return "search|\(lang)|\(q.lowercased())|\(inc)|\(limit)"
    }

    func search(q: String, include: [String]? = nil, limit: Int = 20) async throws -> [SearchResult] {
        let inc = (include ?? ["country", "region", "bundle"]).joined(separator: ",")
        let key = makeKey(q: q, include: include, limit: limit)
        let results: [SearchResult] = try await RequestCenter.shared.singleFlight(key: key) {
            let dtos: [SearchResultDTO] = try await service.get("/search", query: [
                "q": q,
                "include": inc,
                "limit": String(limit),
                "dedupe": "true"
            ])
            return dtos.map { dto in
                SearchResult(
                    id: dto.id,
                    kind: SearchKind(rawValue: dto.kind) ?? .bundle,
                    title: dto.title,
                    subtitle: dto.subtitle,
                    countryCode: dto.countryCode.map { RegionCodeConverter.toAlpha2($0) },
                    regionCode: dto.regionCode,
                    bundleCode: dto.bundleCode
                )
            }
        }
        return results
    }

    func recent(limit: Int = 10, sort: String = "recent") async throws -> [SearchResult] {
        let dtos: [SearchResultDTO] = try await service.get("/search/recent", query: [
            "limit": String(limit),
            "sort": sort
        ])
        return dtos.map { dto in
            SearchResult(
                id: dto.id,
                kind: SearchKind(rawValue: dto.kind) ?? .bundle,
                title: dto.title,
                subtitle: dto.subtitle,
                countryCode: dto.countryCode.map { RegionCodeConverter.toAlpha2($0) },
                regionCode: dto.regionCode,
                bundleCode: dto.bundleCode
            )
        }
    }

    func logSelection(_ r: SearchResult) async throws -> Bool {
        struct Body: Encodable {
            let kind: String
            let id: String
            let countryCode: String?
            let regionCode: String?
            let bundleCode: String?
            let title: String?
            let subtitle: String?
        }
        let body = Body(
            kind: r.kind.rawValue,
            id: r.id,
            countryCode: r.countryCode,
            regionCode: r.regionCode,
            bundleCode: r.bundleCode,
            title: r.title,
            subtitle: r.subtitle
        )
        let dto: SuccessDTO = try await service.post("/search/log", body: body)
        return dto.success ?? true
    }
}
