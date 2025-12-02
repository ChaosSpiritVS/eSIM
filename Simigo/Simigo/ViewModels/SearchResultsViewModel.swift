import Foundation

@MainActor
final class SearchResultsViewModel: ObservableObject {
    // 输出状态
    @Published var isLoading: Bool = false
    @Published var countryHits: [Country] = []
    @Published var regionHits: [Region] = []
    @Published var bundles: [ESIMBundle] = []
    @Published var canLoadMore: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var error: String?

    // 输入与上下文
    private(set) var query: String = ""
    private(set) var countryScope: String?
    private(set) var regionScope: String?
    private(set) var bundleCategoryScope: String?

    // 依赖
    private let upstreamRepository: UpstreamCatalogRepositoryProtocol?
    private let cacheStore = CatalogCacheStore.shared

    // 分页与取消
    private var pageNumber: Int = 1
    private var pageSize: Int = 25
    private var currentCountriesKey: String?
    private var currentRegionsKey: String?
    private var currentBundlesKey: String?
    private var currentCacheKey: String?
    private var autoPrefetchRemaining: Int = 0

    init(initialQuery: String, countryCode: String? = nil, regionCode: String? = nil, bundleCategory: String? = nil) {
        self.query = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        self.countryScope = countryCode
        self.regionScope = regionCode
        self.bundleCategoryScope = bundleCategory
        self.upstreamRepository = AppConfig.useAliasAPI ? HTTPUpstreamCatalogRepository() : nil
    }

    var isEmpty: Bool { countryHits.isEmpty && regionHits.isEmpty && bundles.isEmpty }

    func clearResults() {
        countryHits = []
        regionHits = []
        bundles = []
        canLoadMore = false
        error = nil
    }

    func cancelAll() {
        if let k = currentCountriesKey { Task { await RequestCenter.shared.cancel(key: k) } }
        if let k = currentRegionsKey { Task { await RequestCenter.shared.cancel(key: k) } }
        if let k = currentBundlesKey { Task { await RequestCenter.shared.cancel(key: k) } }
        currentCountriesKey = nil
        currentRegionsKey = nil
        currentBundlesKey = nil
    }

    func applyScope(countryCode: String? = nil, regionCode: String? = nil) {
        self.countryScope = countryCode
        self.regionScope = regionCode
        self.bundleCategoryScope = nil
        // 切换范围后重新搜索（保留关键词）
        performSearch(query: query, commit: true)
    }

    func performSearch(query: String, commit: Bool) {
        // 防抖已在 View 中由 onChange 合理触发；此处直接执行
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.query = trimmed
        error = nil
        isLoading = true
        Telemetry.shared.logEvent("search_results_open", parameters: ["q": trimmed, "country": countryScope ?? "-", "region": regionScope ?? "-", "category": bundleCategoryScope ?? "-"])

        // 先取消在途请求，避免旧结果回写
        cancelAll()

        // 第一阶段：本地建议（国家/地区）通过上游列表+前缀过滤
        Task { [weak self] in
            guard let self else { return }
            do {
                if let upstream = upstreamRepository {
                    let ck = "bundle:countries"
                    currentCountriesKey = ck
                    if let cached = cacheStore.loadCountries(ttl: AppConfig.catalogCacheTTL) {
                        if currentCountriesKey == ck {
                            countryHits = filterCountrys(cached.list, by: trimmed)
                        }
                        if cached.isExpired {
                            let rid1 = UUID().uuidString
                            let countries = try await upstream.listCountries(requestId: rid1)
                            if currentCountriesKey == ck {
                                countryHits = filterCountrys(countries, by: trimmed)
                                cacheStore.saveCountries(countries)
                            }
                        }
                    } else {
                        let rid1 = UUID().uuidString
                        let countries = try await upstream.listCountries(requestId: rid1)
                        if currentCountriesKey == ck {
                            countryHits = filterCountrys(countries, by: trimmed)
                            cacheStore.saveCountries(countries)
                        }
                    }

                    let rk = "bundle:regions"
                    currentRegionsKey = rk
                    if let cachedR = cacheStore.loadRegions(ttl: AppConfig.catalogCacheTTL) {
                        if currentRegionsKey == rk {
                            regionHits = filterRegions(cachedR.list, by: trimmed)
                        }
                        if cachedR.isExpired {
                            let rid2 = UUID().uuidString
                            let regions = try await upstream.listRegions(requestId: rid2)
                            if currentRegionsKey == rk {
                                regionHits = filterRegions(regions, by: trimmed)
                                cacheStore.saveRegions(regions)
                            }
                        }
                    } else {
                        let rid2 = UUID().uuidString
                        let regions = try await upstream.listRegions(requestId: rid2)
                        if currentRegionsKey == rk {
                            regionHits = filterRegions(regions, by: trimmed)
                            cacheStore.saveRegions(regions)
                        }
                    }
                } else {
                    countryHits = []
                    regionHits = []
                }
            } catch {
                if error.localizedDescription.isEmpty == false { self.error = error.localizedDescription }
            }
        }

        // 第二阶段：套餐（范围优先）
        pageSize = 10
        pageNumber = 1
        bundles = []
        canLoadMore = false
        autoPrefetchRemaining = {
            let limited = NetworkMonitor.shared.isConstrained || NetworkMonitor.shared.isExpensive
            return limited ? 0 : 2
        }()
        let cat: String? = {
            if let c = bundleCategoryScope { return c }
            if countryScope != nil { return "country" }
            if regionScope != nil { return "region" }
            return nil
        }()
        let cacheKey = cacheStore.bundlesKey(
            pageNumber: 1,
            pageSize: pageSize,
            countryCode: countryScope,
            regionCode: regionScope,
            bundleCategory: cat,
            sortBy: "price_dsc"
        )
        currentCacheKey = cacheKey
        var shouldFetch = true
        if let cached = cacheStore.loadBundles(key: cacheKey, ttl: AppConfig.catalogCacheTTL) {
            bundles = cached.list
            canLoadMore = cached.list.count == pageSize
            isLoading = false
            pageNumber = canLoadMore ? 2 : 1
            shouldFetch = cached.isExpired
        } else {
            shouldFetch = true
        }
        if shouldFetch { loadBundlesPage(reset: true) }
    }

    func loadMoreBundles() { loadBundlesPage(reset: false) }

    private func loadBundlesPage(reset: Bool) {
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let upstream = upstreamRepository else {
                    isLoading = false
                    return
                }
                if reset { isLoadingMore = false } else { isLoadingMore = true }
                Telemetry.shared.logEvent("search_results_load_page", parameters: ["page": pageNumber, "size": pageSize, "reset": reset])

                let effectiveCategory: String? = {
                    if let cat = bundleCategoryScope { return cat }
                    if countryScope != nil { return "country" }
                    if regionScope != nil { return "region" }
                    return nil
                }()

                let key = [
                    "bundle:list",
                    String(pageNumber),
                    String(pageSize),
                    countryScope ?? "-",
                    regionScope ?? "-",
                    effectiveCategory ?? "-",
                    "price_dsc" // 默认排序：价格从高到低（与上游文档一致）
                ].joined(separator: "|")
                currentBundlesKey = key
                let rid = UUID().uuidString
                var list = try await upstream.listBundles(
                    pageNumber: pageNumber,
                    pageSize: pageSize,
                    countryCode: countryScope,
                    regionCode: regionScope,
                    bundleCategory: effectiveCategory,
                    sortBy: "price_dsc",
                    requestId: rid
                )
                // 轻量本地过滤（名称/描述包含关键词）
                // 当存在国家或地区范围时，优先按范围展示，不再因关键词剔除结果
                let hasScope = (countryScope != nil) || (regionScope != nil)
                if !hasScope && !query.isEmpty {
                    list = list.filter { b in
                        b.name.localizedCaseInsensitiveContains(query) || (b.description?.localizedCaseInsensitiveContains(query) ?? false)
                    }
                }
                if currentBundlesKey == key {
                    if reset {
                        bundles = list
                    } else {
                        bundles.append(contentsOf: list)
                        // 去重：按 id 去重，避免跨页重复
                        var seen = Set<String>()
                        bundles = bundles.filter { seen.insert($0.id).inserted }
                    }
                    // 简单分页启发：返回数量 == pageSize 则可能还有更多
                    canLoadMore = list.count == pageSize
                    pageNumber += 1
                    Telemetry.shared.logEvent("search_results_load_done", parameters: ["page": pageNumber - 1, "count": list.count, "can_more": canLoadMore])
                    let cacheKey = cacheStore.bundlesKey(
                        pageNumber: pageNumber - 1,
                        pageSize: pageSize,
                        countryCode: countryScope,
                        regionCode: regionScope,
                        bundleCategory: effectiveCategory,
                        sortBy: "price_dsc"
                    )
                    cacheStore.saveBundles(list, key: cacheKey)
                }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
                Telemetry.shared.record(error: error)
            }
            isLoading = false
            isLoadingMore = false

            // 首包完成后，若可能还有更多，自动预取最多 2 页（后台进行）
            if reset && canLoadMore && autoPrefetchRemaining > 0 {
                autoPrefetchRemaining -= 1
                Telemetry.shared.logEvent("search_results_prefetch", parameters: ["remaining": autoPrefetchRemaining])
                loadBundlesPage(reset: false)
                if canLoadMore && autoPrefetchRemaining > 0 {
                    // 轻量延迟，错开请求，避免 UI 卡顿
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.autoPrefetchRemaining -= 1
                        Telemetry.shared.logEvent("search_results_prefetch", parameters: ["remaining": self.autoPrefetchRemaining])
                        self.loadBundlesPage(reset: false)
                    }
                }
            }
        }
    }

    func revalidatePreservingPagination() {
        Telemetry.shared.logEvent("search_results_revalidate", parameters: ["page_size": pageSize])
        let effectiveCategory: String? = {
            if let cat = bundleCategoryScope { return cat }
            if countryScope != nil { return "country" }
            if regionScope != nil { return "region" }
            return nil
        }()
        let cacheKey = cacheStore.bundlesKey(
            pageNumber: 1,
            pageSize: pageSize,
            countryCode: countryScope,
            regionCode: regionScope,
            bundleCategory: effectiveCategory,
            sortBy: "price_dsc"
        )
        if let cached = cacheStore.loadBundles(key: cacheKey, ttl: AppConfig.catalogCacheTTL), !cached.isExpired {
            return
        }
        Task { [weak self] in
            guard let self else { return }
            guard let upstream = upstreamRepository else { return }
            let key = [
                "bundle:list",
                "1",
                String(pageSize),
                countryScope ?? "-",
                regionScope ?? "-",
                effectiveCategory ?? "-",
                "price_dsc"
            ].joined(separator: "|")
            currentBundlesKey = key
            let rid = UUID().uuidString
            var list = try await upstream.listBundles(
                pageNumber: 1,
                pageSize: pageSize,
                countryCode: countryScope,
                regionCode: regionScope,
                bundleCategory: effectiveCategory,
                sortBy: "price_dsc",
                requestId: rid
            )
            let hasScope = (countryScope != nil) || (regionScope != nil)
            if !hasScope && !query.isEmpty {
                list = list.filter { b in
                    b.name.localizedCaseInsensitiveContains(query) || (b.description?.localizedCaseInsensitiveContains(query) ?? false)
                }
            }
            if currentBundlesKey == key {
                var newBundles = bundles
                var indexById: [String: Int] = [:]
                for (idx, b) in newBundles.enumerated() { indexById[b.id] = idx }
                for (i, item) in list.enumerated() {
                    if let idx = indexById[item.id] {
                        newBundles[idx] = item
                    } else {
                        if i <= newBundles.count { newBundles.insert(item, at: i) }
                        else { newBundles.append(item) }
                    }
                }
                var seen = Set<String>()
                bundles = newBundles.filter { seen.insert($0.id).inserted }
                cacheStore.saveBundles(list, key: cacheKey)
            }
        }
    }

    /// 滚动预取：当出现索引超过当前列表 70% 时尝试拉下一页
    func prefetchIfNeeded(currentIndex: Int) {
        let total = bundles.count
        let limited = NetworkMonitor.shared.isConstrained || NetworkMonitor.shared.isExpensive
        guard total > 0, canLoadMore, !isLoadingMore, !limited else { return }
        let threshold = Int(Double(total) * 0.7)
        if currentIndex >= threshold {
            Telemetry.shared.logEvent("search_results_prefetch_scroll", parameters: ["index": currentIndex, "total": total])
            loadBundlesPage(reset: false)
        }
    }

    private func adaptivePageSize() -> Int {
        let iface = NetworkMonitor.shared.interfaceType
        let limited = NetworkMonitor.shared.isConstrained || NetworkMonitor.shared.isExpensive
        if iface == "wifi" && !limited { return 100 }
        if limited { return 25 }
        if iface == "cellular" { return 50 }
        return 50
    }

    // MARK: - 本地过滤
    private func filterCountrys(_ list: [Country], by q: String) -> [Country] {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return Array(list.prefix(10)) }
        let hit = list.filter { $0.name.localizedCaseInsensitiveContains(t) || $0.code.localizedCaseInsensitiveContains(t) }
        return Array(hit.prefix(10))
    }

    private func filterRegions(_ list: [Region], by q: String) -> [Region] {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return Array(list.prefix(10)) }
        let hit = list.filter { $0.name.localizedCaseInsensitiveContains(t) || $0.code.localizedCaseInsensitiveContains(t) }
        return Array(hit.prefix(10))
    }
}
