import Foundation

@MainActor
final class AgentCenterViewModel: ObservableObject {
    @Published var account: HTTPUpstreamAgentRepository.AgentAccountDTO?
    @Published var bills: [HTTPUpstreamAgentRepository.AgentBillDTO] = []
    @Published var isLoading = false
    @Published var error: String?

    private let upstreamRepository: UpstreamAgentRepositoryProtocol?
    private let cacheStore = CatalogCacheStore.shared
    private var currentAccountNetworkKey: String?
    private var currentBillsNetworkKey: String?

    init(repository: UpstreamAgentRepositoryProtocol? = nil) {
        self.upstreamRepository = repository ?? (AppConfig.useAliasAPI ? HTTPUpstreamAgentRepository() : nil)
    }

    func load() {
        guard !isLoading else { return }
        // SWR：如果有缓存，先渲染账户与默认账单；否则展示骨架
        var shouldFetchAccount = true
        var shouldFetchBills = true
        if let cachedAcc = cacheStore.loadAgentAccount(ttl: AppConfig.agentAccountCacheTTL) {
            account = cachedAcc.item
            isLoading = false
            shouldFetchAccount = cachedAcc.isExpired
        }
        if let cachedBills = cacheStore.loadAgentBills(pageNumber: 1, pageSize: 20, reference: nil, startDate: nil, endDate: nil, ttl: AppConfig.agentBillsCacheTTL) {
            bills = cachedBills.list
            isLoading = false
            shouldFetchBills = cachedBills.isExpired
        }
        if account == nil && bills.isEmpty { isLoading = true }
        error = nil

        // 主动取消在途单飞（账户与默认账单）
        if let oldAccKey = currentAccountNetworkKey { Task { await RequestCenter.shared.cancel(key: oldAccKey) } }
        if let oldBillsKey = currentBillsNetworkKey { Task { await RequestCenter.shared.cancel(key: oldBillsKey) } }
        currentAccountNetworkKey = "agent:account"
        currentBillsNetworkKey = ["agent:bills", "1", String(safePageSize(20)), "-", "-", "-"].joined(separator: "|")
        let expectedAccKey = currentAccountNetworkKey
        let expectedBillsKey = currentBillsNetworkKey

        Task {
            do {
                guard let upstream = upstreamRepository else {
                    throw NSError(domain: "AgentCenter", code: -1, userInfo: [NSLocalizedDescriptionKey: loc("别名模式未开启或仓库不可用")])
                }
                let rid = UUID().uuidString
                if shouldFetchAccount {
                    let acc = try await upstream.getAccount(requestId: rid)
                    if self.currentAccountNetworkKey == expectedAccKey {
                        account = acc
                        cacheStore.saveAgentAccount(acc)
                    }
                }
                if shouldFetchBills {
                    let list = try await upstream.listBills(pageNumber: 1, pageSize: 20, reference: nil, startDate: nil, endDate: nil, requestId: rid)
                    if self.currentBillsNetworkKey == expectedBillsKey {
                        bills = list.bills
                        cacheStore.saveAgentBills(list.bills, pageNumber: 1, pageSize: 20, reference: nil, startDate: nil, endDate: nil)
                    }
                }
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    func searchBills(reference: String?, startDate: String?, endDate: String?) {
        guard !isLoading else { return }
        // SWR：基于筛选条件的账单缓存
        var shouldFetch = true
        if let cached = cacheStore.loadAgentBills(pageNumber: 1, pageSize: 50, reference: reference, startDate: startDate, endDate: endDate, ttl: AppConfig.agentBillsCacheTTL) {
            bills = cached.list
            isLoading = false
            shouldFetch = cached.isExpired
        } else {
            isLoading = true
            shouldFetch = true
        }
        error = nil

        // 主动取消在途单飞（账单搜索）
        if let oldBillsKey = currentBillsNetworkKey { Task { await RequestCenter.shared.cancel(key: oldBillsKey) } }
        currentBillsNetworkKey = [
            "agent:bills",
            "1",
            String(safePageSize(50)),
            reference ?? "-",
            startDate ?? "-",
            endDate ?? "-"
        ].joined(separator: "|")
        let expectedKey = currentBillsNetworkKey

        if !shouldFetch { return }
        Task {
            do {
                guard let upstream = upstreamRepository else { throw NSError(domain: "AgentCenter", code: -1, userInfo: [NSLocalizedDescriptionKey: loc("别名模式未开启或仓库不可用")]) }
                let rid = UUID().uuidString
                let list = try await upstream.listBills(pageNumber: 1, pageSize: 50, reference: reference, startDate: startDate, endDate: endDate, requestId: rid)
                if self.currentBillsNetworkKey == expectedKey {
                    bills = list.bills
                    cacheStore.saveAgentBills(list.bills, pageNumber: 1, pageSize: 50, reference: reference, startDate: startDate, endDate: endDate)
                }
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - 与仓库保持一致的页大小规则
    private func safePageSize(_ size: Int) -> Int {
        let allowed = [10, 25, 50, 100]
        return allowed.contains(size) ? size : 25
    }
}
