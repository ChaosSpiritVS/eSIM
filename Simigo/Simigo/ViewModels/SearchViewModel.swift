import Foundation

private struct CountryDTO: Decodable { let code: String; let name: String }
private struct RegionDTO: Decodable { let code: String; let name: String }
private struct BundleNameDTO: Decodable { let id: String; let name: String }

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var suggestions: [SearchResult] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var history: [SearchResult] = []

    private let repo: SearchRepositoryProtocol
    private var debounceTask: Task<Void, Never>? = nil
    private var currentKey: String? = nil
    private static let historyKey = "market_search_history_v1"
    private static let historyMetaKey = "market_search_history_meta_v1" // { lastAt: Double, lang: String, userId: String }
    private var historyRefreshKey: String? = nil

    init(repo: SearchRepositoryProtocol = HTTPSearchRepository()) {
        self.repo = repo
        self.history = Self.loadHistory()
    }

    func debounceSearch(query: String, include: [String]? = nil, limit: Int = 20, delayMs: Int = 250) {
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self.isLoading = false
            self.suggestions = []
            self.error = nil
            return
        }

        isLoading = true
        error = nil

        // 构造新的单飞键并取消旧在途请求，避免旧结果回写
        let newKey = repo.makeKey(q: trimmed, include: include, limit: limit)
        if let old = currentKey, old != newKey {
            Task { await RequestCenter.shared.cancel(key: old) }
        }
        currentKey = newKey
        let expectedKey = newKey

        if let cached = CatalogCacheStore.shared.loadSearchSuggestions(q: trimmed, include: include, limit: limit, ttl: AppConfig.searchSuggestionsCacheTTL) {
            suggestions = cached.list
            isLoading = false
            if !cached.isExpired { return }
        }

        // 离线优先：若离线且已有缓存结果，则不发起网络请求
        if !NetworkMonitor.shared.isOnline {
            if let cached = CatalogCacheStore.shared.loadSearchSuggestions(q: trimmed, include: include, limit: limit, ttl: AppConfig.searchSuggestionsCacheTTL) {
                suggestions = cached.list
                isLoading = false
                return
            }
            isLoading = false
            error = NetworkError.offline.localizedDescription
            return
        }
        debounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                let results = try await repo.search(q: trimmed, include: include, limit: limit)
                if self.currentKey == expectedKey {
                    self.suggestions = results
                    self.isLoading = false
                    CatalogCacheStore.shared.saveSearchSuggestions(results, q: trimmed, include: include, limit: limit)
                    Telemetry.shared.logEvent("search_query", parameters: ["q": trimmed, "limit": limit])
                }
            } catch is CancellationError {
                // swallowed
            } catch {
                if self.currentKey == expectedKey {
                    self.isLoading = false
                    self.error = error.localizedDescription
                }
            }
        }
    }

    func cancel() {
        debounceTask?.cancel()
        debounceTask = nil
        if let key = currentKey {
            Task { await RequestCenter.shared.cancel(key: key) }
        }
        currentKey = nil
        isLoading = false
    }

    func recordSelection(_ result: SearchResult) {
        Task {
            let token = await TokenStore.shared.getAccessToken()
            if token != nil {
                do { _ = try await repo.logSelection(result) } catch { }
                await refreshHistoryIfPossible()
            } else {
                var new = history.filter { $0.id != result.id || $0.kind != result.kind }
                new.insert(result, at: 0)
                if new.count > 10 { new = Array(new.prefix(10)) }
                history = new
                Self.saveHistory(new)
            }
        }
    }

    func refreshHistoryIfPossible() async {
        let token = await TokenStore.shared.getAccessToken()
        if token != nil {
            do {
                let now = Date().timeIntervalSince1970
                let ttl = AppConfig.searchSuggestionsCacheTTL
                let meta = Self.loadHistoryMeta()
                let currentLang = SettingsManager.canonicalLanguage(UserDefaults.standard.string(forKey: "simigo.languageCode") ?? Locale.preferredLanguages.first ?? "en")
                let currentUserId = UserDefaults.standard.string(forKey: "simigo.currentUserId") ?? "-"
                let key = "\(currentLang)|\(currentUserId)"
                if historyRefreshKey == key { return }
                if !history.isEmpty,
                   let lastAtStr = meta["lastAt"], let lastAt = Double(lastAtStr),
                   let lastLang = meta["lang"],
                   let lastUser = meta["userId"],
                   (now - lastAt) < ttl,
                   lastLang == currentLang,
                   lastUser == currentUserId {
                    return
                }
                historyRefreshKey = key
                var list = try await repo.recent(limit: 10, sort: "recent")
                let makeKey: (SearchResult) -> String = { r in
                    switch r.kind {
                    case .country: return "country|\(r.countryCode ?? r.id)"
                    case .region: return "region|\(r.regionCode ?? r.id)"
                    case .bundle: return "bundle|\(r.bundleCode ?? r.id)"
                    }
                }
                var serverSet = Set(list.map(makeKey))
                let local = Self.loadHistory()
                let missing = local.filter { !serverSet.contains(makeKey($0)) }
                if !missing.isEmpty {
                    for r in missing { _ = try? await repo.logSelection(r) }
                    var merged = list
                    for r in missing {
                        let k = makeKey(r)
                        if !serverSet.contains(k) {
                            merged.insert(r, at: 0)
                            serverSet.insert(k)
                        }
                    }
                    list = merged
                }
                history = list
                Self.saveHistory(list)
                Self.saveHistoryMeta(["lastAt": now, "lang": currentLang, "userId": currentUserId])
                historyRefreshKey = nil
            } catch {
                history = Self.loadHistory()
                historyRefreshKey = nil
            }
        } else {
            var list = Self.loadHistory()
            if list.isEmpty { history = list; return }
            let now = Date().timeIntervalSince1970
            let ttl = AppConfig.searchSuggestionsCacheTTL
            let meta = Self.loadHistoryMeta()
            let currentLang = SettingsManager.canonicalLanguage(UserDefaults.standard.string(forKey: "simigo.languageCode") ?? Locale.preferredLanguages.first ?? "en")
            let key = "\(currentLang)|-"
            if historyRefreshKey == key { return }
            if let lastAtStr = meta["lastAt"], let lastAt = Double(lastAtStr), let lastLang = meta["lang"], (now - lastAt) < ttl, lastLang == currentLang {
                historyRefreshKey = nil
                history = list
                return
            }
            historyRefreshKey = key
            let service = NetworkService()
            var countryNames: [String: String] = [:]
            var regionNames: [String: String] = [:]
            if list.contains(where: { $0.kind == .country }) {
                if let cached = CatalogCacheStore.shared.loadCountries(ttl: AppConfig.catalogCacheTTL) {
                    for c in cached.list { countryNames[RegionCodeConverter.toAlpha2(c.code)] = c.name }
                    if cached.isExpired {
                        if let countries: [CountryDTO] = try? await service.get("/catalog/countries") {
                            for c in countries { countryNames[RegionCodeConverter.toAlpha2(c.code)] = c.name }
                            CatalogCacheStore.shared.saveCountries(countries.map { Country(code: RegionCodeConverter.toAlpha2($0.code), name: $0.name) })
                        }
                    }
                } else {
                    if let countries: [CountryDTO] = try? await service.get("/catalog/countries") {
                        for c in countries { countryNames[RegionCodeConverter.toAlpha2(c.code)] = c.name }
                        CatalogCacheStore.shared.saveCountries(countries.map { Country(code: RegionCodeConverter.toAlpha2($0.code), name: $0.name) })
                    }
                }
            }
            if list.contains(where: { $0.kind == .region }) {
                if let cachedR = CatalogCacheStore.shared.loadRegions(ttl: AppConfig.catalogCacheTTL) {
                    for r in cachedR.list { regionNames[r.code.lowercased()] = r.name }
                    if cachedR.isExpired {
                        if let regions: [RegionDTO] = try? await service.get("/catalog/regions") {
                            for r in regions { regionNames[r.code.lowercased()] = r.name }
                            CatalogCacheStore.shared.saveRegions(regions.map { Region(code: $0.code.lowercased(), name: $0.name) })
                        }
                    }
                } else {
                    if let regions: [RegionDTO] = try? await service.get("/catalog/regions") {
                        for r in regions { regionNames[r.code.lowercased()] = r.name }
                        CatalogCacheStore.shared.saveRegions(regions.map { Region(code: $0.code.lowercased(), name: $0.name) })
                    }
                }
            }
            var localized: [SearchResult] = []
            for r in list {
                switch r.kind {
                case .country:
                    let code = (r.countryCode ?? r.id)
                    let t = countryNames[code] ?? r.title
                    localized.append(SearchResult(id: r.id, kind: r.kind, title: t, subtitle: r.subtitle, countryCode: r.countryCode, regionCode: r.regionCode, bundleCode: r.bundleCode))
                case .region:
                    let code = (r.regionCode ?? r.id)
                    let t = regionNames[code.lowercased()] ?? r.title
                    localized.append(SearchResult(id: r.id, kind: r.kind, title: t, subtitle: r.subtitle, countryCode: r.countryCode, regionCode: r.regionCode, bundleCode: r.bundleCode))
                case .bundle:
                    var t = r.title
                    if let cached = CatalogCacheStore.shared.loadBundleName(bundleId: r.id, ttl: AppConfig.catalogCacheTTL) {
                        t = cached.name
                        if cached.isExpired && NetworkMonitor.shared.isOnline {
                            if let dto: BundleNameDTO = try? await service.get("/catalog/bundle/\(r.id)") {
                                t = dto.name
                                CatalogCacheStore.shared.saveBundleName(dto.name, bundleId: r.id)
                            }
                        }
                    } else if NetworkMonitor.shared.isOnline {
                        if let dto: BundleNameDTO = try? await service.get("/catalog/bundle/\(r.id)") {
                            t = dto.name
                            CatalogCacheStore.shared.saveBundleName(dto.name, bundleId: r.id)
                        }
                    }
                    localized.append(SearchResult(id: r.id, kind: r.kind, title: t, subtitle: r.subtitle, countryCode: r.countryCode, regionCode: r.regionCode, bundleCode: r.bundleCode))
                }
            }
            history = localized
            Self.saveHistory(localized)
            Self.saveHistoryMeta(["lastAt": now, "lang": currentLang, "userId": "-"])
            historyRefreshKey = nil
        }
    }

    private static func loadHistory() -> [SearchResult] {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return [] }
        return (try? JSONDecoder().decode([SearchResult].self, from: data)) ?? []
    }

    private static func saveHistory(_ list: [SearchResult]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private static func loadHistoryMeta() -> [String: String] {
        guard let raw = UserDefaults.standard.dictionary(forKey: historyMetaKey) else { return [:] }
        var out: [String: String] = [:]
        if let lastAt = raw["lastAt"] as? Double { out["lastAt"] = String(lastAt) }
        if let lang = raw["lang"] as? String { out["lang"] = lang }
        if let user = raw["userId"] as? String { out["userId"] = user }
        return out
    }

    private static func saveHistoryMeta(_ meta: [String: Any]) {
        UserDefaults.standard.set(meta, forKey: historyMetaKey)
    }
}
