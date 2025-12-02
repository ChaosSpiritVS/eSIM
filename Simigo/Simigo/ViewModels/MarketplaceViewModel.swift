import Foundation

@MainActor
final class MarketplaceViewModel: ObservableObject {
    @Published var bundles: [ESIMBundle] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var currentBundleCategory: String?
    @Published var currentCountryCode: String?
    @Published var currentRegionCode: String?
    @Published var currentSortBy: String?

    private let repository: CatalogRepositoryProtocol
    private let upstreamRepository: UpstreamCatalogRepositoryProtocol?
    private let cacheStore = CatalogCacheStore.shared
    private var loadTask: Task<Void, Never>?
    private var currentRequestKey: String?
    private var currentNetworkKey: String?

    init(repository: CatalogRepositoryProtocol? = nil,
         countryCode: String? = nil,
         regionCode: String? = nil,
         bundleCategory: String? = nil,
         sortBy: String? = nil) {
        if let repository { self.repository = repository }
        else { self.repository = AppConfig.isMock ? MockCatalogRepository() : HTTPCatalogRepository() }
        self.upstreamRepository = AppConfig.useAliasAPI ? HTTPUpstreamCatalogRepository() : nil
        self.currentCountryCode = countryCode
        self.currentRegionCode = regionCode
        self.currentBundleCategory = bundleCategory
        self.currentSortBy = sortBy
    }

    func load() {
        // 取消上一请求，避免快速切换导致旧结果覆盖新筛选
        loadTask?.cancel()
        // 主动取消在途单飞任务（若切换了筛选参数或模式）
        let newNetworkKey: String = {
            if upstreamRepository != nil {
                return upstreamBundlesKey(
                    pageNumber: 1,
                    pageSize: 10,
                    countryCode: currentCountryCode,
                    regionCode: currentRegionCode,
                    bundleCategory: currentBundleCategory,
                    sortBy: currentSortBy
                )
            } else {
                return "catalog:popular"
            }
        }()
        if let oldKey = currentNetworkKey, oldKey != newNetworkKey {
            Task { await RequestCenter.shared.cancel(key: oldKey) }
        }
        currentNetworkKey = newNetworkKey
        let expectedNetworkKey = newNetworkKey
        // SWR：如果有缓存先渲染，无缓存再展示骨架
        let key = cacheStore.bundlesKey(
            pageNumber: 1,
            pageSize: 10,
            countryCode: currentCountryCode,
            regionCode: currentRegionCode,
            bundleCategory: currentBundleCategory,
            sortBy: currentSortBy
        )
        currentRequestKey = key
        var shouldFetch = true
        if let cached = cacheStore.loadBundles(key: key, ttl: AppConfig.catalogCacheTTL) {
            // 有缓存：先渲染缓存内容，避免骨架；未过期则跳过网络请求
            bundles = cached.list
            isLoading = false
            shouldFetch = cached.isExpired
        } else {
            isLoading = true
            shouldFetch = true
        }
        guard shouldFetch else { return }
        loadTask = Task {
            do {
                if let upstream = upstreamRepository {
                    let rid = UUID().uuidString
                    let result = try await upstream.listBundles(
                        pageNumber: 1,
                        pageSize: 10,
                        countryCode: currentCountryCode,
                        regionCode: currentRegionCode,
                        bundleCategory: currentBundleCategory,
                        sortBy: currentSortBy,
                        requestId: rid
                    )
                    if Task.isCancelled { return }
                    if self.currentRequestKey == key && self.currentNetworkKey == expectedNetworkKey {
                        bundles = result
                        cacheStore.saveBundles(result, key: key)
                    }
                } else {
                    // 非 alias 模式维持现有逻辑：热门套餐
                    let result = try await repository.fetchPopularBundles()
                    if Task.isCancelled { return }
                    if self.currentRequestKey == key && self.currentNetworkKey == expectedNetworkKey {
                        bundles = result
                        cacheStore.saveBundles(result, key: key)
                    }
                }
            } catch {
                self.error = error.localizedDescription
            }
            if self.currentRequestKey == key && self.currentNetworkKey == expectedNetworkKey { isLoading = false }
        }
    }

    func reload(pageNumber: Int = 1,
                pageSize: Int = 10,
                bundleCategory: String? = nil,
                countryCode: String? = nil,
                regionCode: String? = nil,
                sortBy: String? = nil) {
        // 取消上一请求，确保新筛选优先
        loadTask?.cancel()
        // 基于“旧”筛选的在途请求主动取消，避免旧结果覆盖
        let oldNetworkKey = currentNetworkKey
        // 更新当前筛选条件（仅当传入非 nil 时覆盖）
        if let bundleCategory { self.currentBundleCategory = bundleCategory }
        if let countryCode { self.currentCountryCode = countryCode }
        if let regionCode { self.currentRegionCode = regionCode }
        if let sortBy { self.currentSortBy = sortBy }

        // 计算新的网络单飞键，并取消旧键对应的在途任务（若不同）
        let newNetworkKey: String = {
            if upstreamRepository != nil {
                return upstreamBundlesKey(
                    pageNumber: pageNumber,
                    pageSize: pageSize,
                    countryCode: self.currentCountryCode,
                    regionCode: self.currentRegionCode,
                    bundleCategory: self.currentBundleCategory,
                    sortBy: self.currentSortBy
                )
            } else {
                return "catalog:popular"
            }
        }()
        if let oldKey = oldNetworkKey, oldKey != newNetworkKey {
            Task { await RequestCenter.shared.cancel(key: oldKey) }
        }
        currentNetworkKey = newNetworkKey
        let expectedNetworkKey = newNetworkKey

        // SWR：切换筛选后先尝试缓存命中
        let key = cacheStore.bundlesKey(
            pageNumber: pageNumber,
            pageSize: pageSize,
            countryCode: self.currentCountryCode,
            regionCode: self.currentRegionCode,
            bundleCategory: self.currentBundleCategory,
            sortBy: self.currentSortBy
        )
        currentRequestKey = key
        var shouldFetch = true
        if let cached = cacheStore.loadBundles(key: key, ttl: AppConfig.catalogCacheTTL) {
            bundles = cached.list
            isLoading = false
            shouldFetch = cached.isExpired && NetworkMonitor.shared.isOnline
        } else {
            isLoading = true
            shouldFetch = NetworkMonitor.shared.isOnline
        }
        guard shouldFetch else { return }
        loadTask = Task {
            defer { if self.currentRequestKey == key { isLoading = false } }
            do {
                if let upstream = upstreamRepository {
                    let rid = UUID().uuidString
                    let result = try await upstream.listBundles(
                        pageNumber: pageNumber,
                        pageSize: pageSize,
                        countryCode: currentCountryCode,
                        regionCode: currentRegionCode,
                        bundleCategory: currentBundleCategory,
                        sortBy: currentSortBy,
                        requestId: rid
                    )
                    if Task.isCancelled { return }
                    if self.currentRequestKey == key && self.currentNetworkKey == expectedNetworkKey {
                        bundles = result
                        cacheStore.saveBundles(result, key: key)
                    }
                } else {
                    // 非 alias 模式回退到本地“热门”逻辑（暂不支持服务端筛选/排序）。
                    let result = try await repository.fetchPopularBundles()
                    if Task.isCancelled { return }
                    if self.currentRequestKey == key && self.currentNetworkKey == expectedNetworkKey {
                        bundles = result
                        cacheStore.saveBundles(result, key: key)
                    }
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // 切换分类时需清空国家/地区筛选，避免“全部”仍沿用上一次过滤
    func switchCategoryAndReload(to bundleCategory: String?) {
        self.currentBundleCategory = bundleCategory
        self.currentCountryCode = nil
        self.currentRegionCode = nil
        reload(pageNumber: 1, pageSize: 10, bundleCategory: bundleCategory)
    }

    // MARK: - 单飞键构造（与仓库保持一致）
    private func safePageSize(_ size: Int) -> Int {
        let allowed = [10, 25, 50, 100]
        return allowed.contains(size) ? size : 25
    }

    private func upstreamBundlesKey(pageNumber: Int,
                                    pageSize: Int,
                                    countryCode: String?,
                                    regionCode: String?,
                                    bundleCategory: String?,
                                    sortBy: String?) -> String {
        let iso3 = countryCode.map { RegionCodeConverter.toAlpha3($0) }
        let lang = UserDefaults.standard.string(forKey: "simigo.languageCode") ?? Locale.preferredLanguages.first ?? "en"
        return "bundle:list|\(lang)|\(pageNumber)|\(safePageSize(pageSize))|\(iso3 ?? "-")|\(regionCode ?? "-")|\(bundleCategory ?? "-")|\(sortBy ?? "-")"
    }

    func revalidatePreservingShortList() {
        let key = cacheStore.bundlesKey(
            pageNumber: 1,
            pageSize: 10,
            countryCode: currentCountryCode,
            regionCode: currentRegionCode,
            bundleCategory: currentBundleCategory,
            sortBy: currentSortBy
        )
        if let cached = cacheStore.loadBundles(key: key, ttl: AppConfig.catalogCacheTTL), !cached.isExpired { return }
        Task { [weak self] in
            guard let self else { return }
            guard let upstream = upstreamRepository else { return }
            let rid = UUID().uuidString
            let result = try await upstream.listBundles(
                pageNumber: 1,
                pageSize: 10,
                countryCode: currentCountryCode,
                regionCode: currentRegionCode,
                bundleCategory: currentBundleCategory,
                sortBy: currentSortBy,
                requestId: rid
            )
            var merged = self.bundles
            var indexById: [String: Int] = [:]
            for (idx, b) in merged.enumerated() { indexById[b.id] = idx }
            for (i, item) in result.enumerated() {
                if let idx = indexById[item.id] { merged[idx] = item }
                else { if i <= merged.count { merged.insert(item, at: i) } else { merged.append(item) } }
            }
            var seen = Set<String>()
            let unique = merged.filter { seen.insert($0.id).inserted }
            self.bundles = unique
            self.cacheStore.saveBundles(result, key: key)
        }
    }
}
