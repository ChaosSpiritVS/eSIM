import Foundation

@MainActor
final class OrdersListViewModel: ObservableObject {
    @Published var orders: [Order] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var info: String?
    @Published var usageByOrderId: [String: OrderUsage] = [:]
    @Published var loadingUsageIds: Set<String> = []
    @Published var bundleById: [String: ESIMBundle] = [:]
    @Published var loadingBundleIds: Set<String> = []
    @Published var failedOrderId: String?
    @Published var pageSize: Int = 25
    @Published var hasMore: Bool = false
    @Published var isLoadingMore: Bool = false

    private let repository: OrderRepositoryProtocol
    private let usageRepository: OrderUsageRepositoryProtocol
    private let catalogRepository: CatalogRepositoryProtocol
    private let upstreamRepository: UpstreamOrderRepositoryProtocol?
    private let upstreamCatalogRepository: UpstreamCatalogRepositoryProtocol?
    private let cacheStore = CatalogCacheStore.shared
    private var installationObserver: NSObjectProtocol?
    private var paymentObserver: NSObjectProtocol?
    private var paymentFailedObserver: NSObjectProtocol?
    private var lastErrorAt: Date?
    private var currentOrdersNetworkKey: String?
    private var auth: AuthManager?
    private var hasInitializedMappings = false
    private var currentPage: Int = 1
    private var lastFetchedCount: Int = 0

    init(repository: OrderRepositoryProtocol? = nil, catalogRepository: CatalogRepositoryProtocol? = nil) {
        self.repository = repository ?? (AppConfig.isMock ? MockOrderRepository() : HTTPOrderRepository())
        self.usageRepository = AppConfig.isMock ? MockOrderUsageRepository() : HTTPOrderUsageRepository()
        self.catalogRepository = catalogRepository ?? (AppConfig.isMock ? MockCatalogRepository() : HTTPCatalogRepository())
        self.upstreamRepository = AppConfig.useAliasAPI ? HTTPUpstreamOrderRepository() : nil
        self.upstreamCatalogRepository = AppConfig.useAliasAPI ? HTTPUpstreamCatalogRepository() : nil

        // 监听 eSIM 安装成功事件：显式失效用量缓存并强制刷新
        installationObserver = NotificationCenter.default.addObserver(
            forName: .esimInstallationSucceeded,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            guard let orderId = note.userInfo?["orderId"] as? String else { return }
            self.cacheStore.invalidateOrderUsage(orderId: orderId)
            self.loadUsage(for: orderId, force: true)
            self.load(preservePagination: true)
        }

        // 监听支付成功事件：刷新列表并强制刷新对应订单用量
        paymentObserver = NotificationCenter.default.addObserver(
            forName: .paymentSucceeded,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            let newId = note.userInfo?["orderId"] as? String
            let oldId = note.userInfo?["oldOrderId"] as? String
            if let old = oldId { self.cacheStore.invalidateOrderUsage(orderId: old) }
            if let nid = newId { self.cacheStore.invalidateOrderUsage(orderId: nid) }
            // 重载列表以反映订单状态/ID 变化（特别是别名模式）
            self.load(preservePagination: true)
            // 目标订单用量强制刷新，避免命中短 TTL 缓存
            if let nid = newId { self.loadUsage(for: nid, force: true) }
            self.info = loc("支付成功，已刷新订单与用量")
        }

        // 监听支付失败事件：提示失败原因并刷新列表以反映状态
        paymentFailedObserver = NotificationCenter.default.addObserver(
            forName: .paymentFailed,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            let failedId = note.userInfo?["orderId"] as? String
            self.failedOrderId = failedId
            let reason = note.userInfo?["reason"] as? String
            let message = (reason?.isEmpty == false) ? String(format: loc("支付失败：%@"), reason!) : loc("支付失败")
            // 简单节流：2秒内重复错误不再次提示
            if self.error == message, let last = self.lastErrorAt, Date().timeIntervalSince(last) < 2 {
                return
            }
            self.error = message
            self.lastErrorAt = Date()
            // 列表重载以尽快反映状态变化（如从 created->failed）
            self.load(preservePagination: true)
        }
    }

    deinit {
        if let obs = installationObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = paymentObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = paymentFailedObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func setAuth(_ auth: AuthManager) {
        self.auth = auth
    }

    func load(forceUsageForPaid: Bool = false, preservePagination: Bool = false) {
        guard !isLoading else { return }
        var shouldFetch = true
        if !preservePagination {
            currentPage = 1
            hasMore = false
            lastFetchedCount = 0
            if let cached = cacheStore.loadOrders(ttl: AppConfig.ordersCacheTTL) {
                orders = cached.list
                let total = cached.list.count
                let remainder = total % pageSize
                lastFetchedCount = remainder == 0 ? (total > 0 ? pageSize : 0) : remainder
                currentPage = max(1, Int(ceil(Double(total) / Double(pageSize))))
                hasMore = total > 0 && remainder == 0
                isLoading = false
                shouldFetch = cached.isExpired
            } else {
                isLoading = true
                shouldFetch = true
            }
        } else {
            if let cached = cacheStore.loadOrders(ttl: AppConfig.ordersCacheTTL), !cached.isExpired {
                let total = cached.list.count
                let remainder = total % pageSize
                lastFetchedCount = remainder == 0 ? (total > 0 ? pageSize : 0) : remainder
                currentPage = max(1, Int(ceil(Double(total) / Double(pageSize))))
                hasMore = total > 0 && remainder == 0
                shouldFetch = false
            } else {
                shouldFetch = true
            }
        }
        error = nil
        // 在发起新请求前主动取消在途列表请求，避免旧结果覆盖
        if let oldKey = currentOrdersNetworkKey {
            Task { await RequestCenter.shared.cancel(key: oldKey) }
        }
        if upstreamRepository != nil {
            let requestPage = preservePagination ? 1 : currentPage
            currentOrdersNetworkKey = [
                "order:list",
                String(requestPage),
                String(pageSize),
                "-",
                "-",
                "-",
                "-",
                "-",
                "-"
            ].joined(separator: "|")
        } else {
            currentOrdersNetworkKey = nil
        }
        let expectedKey = currentOrdersNetworkKey
        if !shouldFetch { return }
        Task {
            do {
                if let upstream = upstreamRepository {
                    Telemetry.shared.logEvent("orders_load", parameters: ["page": preservePagination ? 1 : currentPage, "size": pageSize, "preserve": preservePagination])
                    let rid = UUID().uuidString
                    if !hasInitializedMappings {
                        _ = try? await upstream.initMappingsForCurrentUser(requestId: rid)
                        hasInitializedMappings = true
                    }
                    let requestPage = preservePagination ? 1 : currentPage
                    let result = try await upstream.listOrders(
                        pageNumber: requestPage,
                        pageSize: pageSize,
                        bundleCode: nil,
                        orderId: nil,
                        orderReference: nil,
                        startDate: nil,
                        endDate: nil,
                        iccid: nil,
                        requestId: rid
                    )
                    if self.currentOrdersNetworkKey != expectedKey { return }
                    let upstreamItems = result.orders
                    let mapped = upstreamItems.map { dto in
                        let oid = dto.orderId
                        let bundleId = dto.bundleCode ?? ""
                        let amount = Decimal(string: dto.agentSalePrice ?? "0") ?? 0
                        let currency = dto.currencyCode ?? "USD"
                        let createdAt: Date = {
                            let s = dto.createdAt ?? ""
                            // 数字时间戳（秒/毫秒）
                            if let ts = Double(s) {
                                let v = ts > 1_000_000_000_000 ? ts / 1000 : ts
                                return Date(timeIntervalSince1970: v)
                            }
                            // ISO 8601
                            let iso = ISO8601DateFormatter()
                            if let dt = iso.date(from: s) { return dt }
                            // 常规格式：yyyy-MM-dd HH:mm:ss
                            do {
                                let fmt1 = DateFormatter()
                                fmt1.locale = Locale(identifier: "en_US_POSIX")
                                fmt1.timeZone = TimeZone(secondsFromGMT: 0)
                                fmt1.dateFormat = "yyyy-MM-dd HH:mm:ss"
                                if let dt1 = fmt1.date(from: s) { return dt1 }
                            }
                            // 上游常见格式：Oct 29, 2025 at 06:26:49
                            do {
                                let fmt2 = DateFormatter()
                                fmt2.locale = Locale(identifier: "en_US_POSIX")
                                fmt2.timeZone = TimeZone(secondsFromGMT: 0)
                                fmt2.dateFormat = "MMM dd, yyyy 'at' HH:mm:ss"
                                if let dt2 = fmt2.date(from: s) { return dt2 }
                            }
                            return Date()
                        }()
                        let status: OrderStatus = {
                            let raw = (dto.orderStatus ?? "").lowercased()
                            if raw.contains("paid") { return .paid }
                            if raw.contains("fail") { return .failed }
                            return .created
                        }()
                        return Order(
                            id: oid,
                            bundleId: bundleId,
                            amount: amount,
                            currency: currency,
                            createdAt: createdAt,
                            status: status,
                            paymentMethod: .paypal,
                            installation: nil,
                            orderStatusText: dto.orderStatus,
                            orderReference: dto.orderReference,
                            bundleCategory: nil,
                            bundleMarketingName: dto.bundleMarketingName,
                            bundleName: dto.bundleName,
                            countryCode: (dto.countryCode ?? []).first,
                            countryName: (dto.countryName ?? []).first,
                            iccid: nil,
                            bundleExpiryDate: nil,
                            expiryDate: nil,
                            planStarted: nil,
                            planStatusText: nil
                        )
                    }
                    if preservePagination {
                        var newOrders = self.orders
                        var indexById: [String: Int] = [:]
                        for (idx, o) in newOrders.enumerated() { indexById[o.id] = idx }
                        for (i, item) in mapped.enumerated() {
                            if let idx = indexById[item.id] {
                                newOrders[idx] = item
                            } else {
                                if i <= newOrders.count {
                                    newOrders.insert(item, at: i)
                                } else {
                                    newOrders.append(item)
                                }
                            }
                        }
                        var seen = Set<String>()
                        var unique: [Order] = []
                        for o in newOrders {
                            if seen.insert(o.id).inserted { unique.append(o) }
                        }
                        self.orders = unique
                        self.cacheStore.saveOrders(self.orders)
                        Telemetry.shared.logEvent("orders_load_done", parameters: ["count": unique.count, "preserve": true])
                    } else {
                        orders = mapped
                        lastFetchedCount = upstreamItems.count
                        hasMore = upstreamItems.count == pageSize
                        cacheStore.saveOrders(orders)
                        Telemetry.shared.logEvent("orders_load_done", parameters: ["count": mapped.count, "preserve": false])
                    }
                } else {
                    orders = try await repository.fetchOrders()
                    hasMore = false
                    cacheStore.saveOrders(orders)
                    Telemetry.shared.logEvent("orders_load_done", parameters: ["count": orders.count, "preserve": false])
                }

                // 手动刷新场景：对已支付订单强制刷新用量
                if forceUsageForPaid {
                    for o in orders where o.status == .paid {
                        self.loadUsage(for: o.id, force: true)
                    }
                }
            } catch {
                self.error = error.localizedDescription
                Telemetry.shared.record(error: error)
            }
            if self.currentOrdersNetworkKey == expectedKey { isLoading = false }
        }
    }

    func loadMore(forceUsageForPaid: Bool = false) {
        guard !isLoading && !isLoadingMore && hasMore else { return }
        guard upstreamRepository != nil else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        Telemetry.shared.logEvent("orders_load_more_call", parameters: ["next_page": nextPage, "size": pageSize])
        Task {
            defer { self.isLoadingMore = false }
            do {
                let rid = UUID().uuidString
                let result = try await upstreamRepository!.listOrders(
                    pageNumber: nextPage,
                    pageSize: pageSize,
                    bundleCode: nil,
                    orderId: nil,
                    orderReference: nil,
                    startDate: nil,
                    endDate: nil,
                    iccid: nil,
                    requestId: rid
                )
                let upstreamItems = result.orders
                let mapped = upstreamItems.map { dto in
                    let oid = dto.orderId
                    let bundleId = dto.bundleCode ?? ""
                    let amount = Decimal(string: dto.agentSalePrice ?? "0") ?? 0
                    let currency = dto.currencyCode ?? "USD"
                    let createdAt: Date = {
                        let s = dto.createdAt ?? ""
                        if let ts = Double(s) {
                            let v = ts > 1_000_000_000_000 ? ts / 1000 : ts
                            return Date(timeIntervalSince1970: v)
                        }
                        let iso = ISO8601DateFormatter()
                        if let dt = iso.date(from: s) { return dt }
                        do {
                            let fmt1 = DateFormatter()
                            fmt1.locale = Locale(identifier: "en_US_POSIX")
                            fmt1.timeZone = TimeZone(secondsFromGMT: 0)
                            fmt1.dateFormat = "yyyy-MM-dd HH:mm:ss"
                            if let dt1 = fmt1.date(from: s) { return dt1 }
                        }
                        do {
                            let fmt2 = DateFormatter()
                            fmt2.locale = Locale(identifier: "en_US_POSIX")
                            fmt2.timeZone = TimeZone(secondsFromGMT: 0)
                            fmt2.dateFormat = "MMM dd, yyyy 'at' HH:mm:ss"
                            if let dt2 = fmt2.date(from: s) { return dt2 }
                        }
                        return Date()
                    }()
                    let status: OrderStatus = {
                        let raw = (dto.orderStatus ?? "").lowercased()
                        if raw.contains("paid") { return .paid }
                        if raw.contains("fail") { return .failed }
                        return .created
                    }()
                    return Order(
                        id: oid,
                        bundleId: bundleId,
                        amount: amount,
                        currency: currency,
                        createdAt: createdAt,
                        status: status,
                        paymentMethod: .paypal,
                        installation: nil,
                        orderStatusText: dto.orderStatus,
                        orderReference: dto.orderReference,
                        bundleCategory: nil,
                        bundleMarketingName: dto.bundleMarketingName,
                        bundleName: dto.bundleName,
                        countryCode: (dto.countryCode ?? []).first,
                        countryName: (dto.countryName ?? []).first,
                        iccid: nil,
                        bundleExpiryDate: nil,
                        expiryDate: nil,
                        planStarted: nil,
                        planStatusText: nil
                    )
                }
                var existingIds = Set(self.orders.map { $0.id })
                for item in mapped where !existingIds.contains(item.id) {
                    self.orders.append(item)
                    existingIds.insert(item.id)
                    if forceUsageForPaid && item.status == .paid { self.loadUsage(for: item.id, force: true) }
                }
                self.currentPage = nextPage
                self.lastFetchedCount = upstreamItems.count
                self.hasMore = upstreamItems.count == pageSize
                self.cacheStore.saveOrders(self.orders)
                Telemetry.shared.logEvent("orders_load_more_done", parameters: ["page": nextPage, "count": mapped.count, "has_more": self.hasMore])
            } catch {
                self.error = error.localizedDescription
                Telemetry.shared.record(error: error)
            }
        }
    }

    func setPageSize(_ size: Int) {
        let allowed = [10, 25, 50, 100]
        let s = allowed.contains(size) ? size : 25
        pageSize = s
    }

    func loadUsage(for orderId: String, force: Bool = false) {
        guard !loadingUsageIds.contains(orderId) else { return }
        loadingUsageIds.insert(orderId)
        // SWR：先读短 TTL 缓存；未过期则直接返回，过期则后台刷新
        if let cached = cacheStore.loadOrderUsage(orderId: orderId, ttl: AppConfig.orderUsageCacheTTL) {
            usageByOrderId[orderId] = cached.item
            if !cached.isExpired && !force {
                loadingUsageIds.remove(orderId)
                return
            }
        }
        // 主动取消在途单飞（订单用量）
        let usageKey = ["usage:order", orderId].joined(separator: "|")
        Task { await RequestCenter.shared.cancel(key: usageKey) }
        Task {
            defer { self.loadingUsageIds.remove(orderId) }
            do {
                let usage = try await usageRepository.fetchUsage(orderId: orderId)
                usageByOrderId[orderId] = usage
                cacheStore.saveOrderUsage(usage, orderId: orderId)
            } catch {
                // 静默失败，不影响订单列表展示
            }
        }
    }

    func loadBundle(id bundleId: String) {
        guard !loadingBundleIds.contains(bundleId) else { return }
        loadingBundleIds.insert(bundleId)
        // 主动取消在途单飞（套餐详情）
        let bundleKey = ["catalog:bundle", bundleId].joined(separator: "|")
        Task { await RequestCenter.shared.cancel(key: bundleKey) }
        Task {
            defer { self.loadingBundleIds.remove(bundleId) }
            do {
                if let upstream = upstreamCatalogRepository {
                    let rid = UUID().uuidString
                    let bundle = try await upstream.getBundleByCode(bundleCode: bundleId, requestId: rid)
                    self.bundleById[bundleId] = bundle
                } else {
                    let bundle = try await catalogRepository.fetchBundle(id: bundleId)
                    self.bundleById[bundleId] = bundle
                }
            } catch {
                // 静默失败，不影响交互
            }
        }
    }
}
