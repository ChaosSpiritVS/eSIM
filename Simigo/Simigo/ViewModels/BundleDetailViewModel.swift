import Foundation

@MainActor
final class BundleDetailViewModel: ObservableObject {
    @Published var bundle: ESIMBundle
    @Published var networks: [String] = []
    @Published var isLoadingNetworks: Bool = false
    @Published var error: String?

    private let upstreamRepository: UpstreamCatalogRepositoryProtocol?
    private let cacheStore = CatalogCacheStore.shared
    private var currentNetworksKey: String?

    init(bundle: ESIMBundle) {
        self.bundle = bundle
        self.upstreamRepository = AppConfig.useAliasAPI ? HTTPUpstreamCatalogRepository() : nil
    }

    func loadNetworks() {
        guard !isLoadingNetworks else { return }
        guard upstreamRepository != nil else { return }
        var shouldFetch = true
        if let cached = cacheStore.loadBundleNetworks(bundleCode: bundle.id, ttl: AppConfig.bundleNetworksCacheTTL) {
            networks = cached.list
            isLoadingNetworks = false
            shouldFetch = cached.isExpired && NetworkMonitor.shared.isOnline
        } else {
            isLoadingNetworks = true
            shouldFetch = NetworkMonitor.shared.isOnline
        }
        error = nil
        // 主动取消在途单飞（套餐网络列表）
        let newKey = ["bundle:networks", bundle.id, "-"] .joined(separator: "|")
        if let oldKey = currentNetworksKey, oldKey != newKey {
            Task { await RequestCenter.shared.cancel(key: oldKey) }
        }
        currentNetworksKey = newKey
        let expectedKey = newKey
        if !shouldFetch { return }
        Task {
            do {
                // 统一使用聚合后的网络列表，提升可读性
                let rid = UUID().uuidString
                let list = try await upstreamRepository!.getBundleNetworks(bundleCode: bundle.id, countryCode: nil, requestId: rid)
                if self.currentNetworksKey == expectedKey {
                    self.networks = list
                    cacheStore.saveBundleNetworks(list, bundleCode: bundle.id)
                }
            } catch {
                if self.currentNetworksKey == expectedKey { self.error = error.localizedDescription }
            }
            if self.currentNetworksKey == expectedKey { isLoadingNetworks = false }
        }
    }
}
