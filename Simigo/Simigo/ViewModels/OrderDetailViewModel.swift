import Foundation

@MainActor
final class OrderDetailViewModel: ObservableObject {
    @Published var order: Order?
    @Published var isLoading = false
    @Published var error: String?
    @Published var info: String?
    @Published var isRequestingRefund = false
    @Published var refundSucceeded: Bool?
    @Published var refundState: RefundState?
    @Published var refundProgress: [RefundProgressStep] = []
    @Published var usage: OrderUsage?
    @Published var isLoadingUsage = false
    @Published var bundle: ESIMBundle?
    @Published var isLoadingBundle = false

    private let repository: OrderRepositoryProtocol
    private let usageRepository: OrderUsageRepositoryProtocol
    private let catalogRepository: CatalogRepositoryProtocol
    let orderId: String
    private let upstreamRepository: UpstreamOrderRepositoryProtocol?
    private let upstreamCatalogRepository: UpstreamCatalogRepositoryProtocol?
    private var currentOrderDetailKey: String?
    private var currentConsumptionKey: String?
    private let cacheStore = CatalogCacheStore.shared
    private var installationObserver: NSObjectProtocol?
    private var paymentObserver: NSObjectProtocol?
    private var paymentFailedObserver: NSObjectProtocol?
    private var lastErrorAt: Date?

    init(orderId: String, repository: OrderRepositoryProtocol? = nil) {
        self.orderId = orderId
        self.repository = repository ?? (AppConfig.isMock ? MockOrderRepository() : HTTPOrderRepository())
        self.usageRepository = AppConfig.isMock ? MockOrderUsageRepository() : HTTPOrderUsageRepository()
        self.catalogRepository = AppConfig.isMock ? MockCatalogRepository() : HTTPCatalogRepository()
        self.upstreamRepository = AppConfig.useAliasAPI ? HTTPUpstreamOrderRepository() : nil
        self.upstreamCatalogRepository = AppConfig.useAliasAPI ? HTTPUpstreamCatalogRepository() : nil
        // 监听 eSIM 安装成功事件：若匹配当前订单，失效用量缓存并强制刷新
        installationObserver = NotificationCenter.default.addObserver(
            forName: .esimInstallationSucceeded,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            guard let notifiedId = note.userInfo?["orderId"] as? String else { return }
            guard notifiedId == self.orderId else { return }
            // 失效用量缓存后，重拉订单详情与用量
            self.cacheStore.invalidateOrderUsage(orderId: self.orderId)
            self.load()
            self.info = loc("安装成功，已刷新详情与用量")
        }

        // 监听支付成功事件：若匹配当前订单，重拉详情与用量
        paymentObserver = NotificationCenter.default.addObserver(
            forName: .paymentSucceeded,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            // 对应新旧ID都做匹配
            let notifiedId = note.userInfo?["orderId"] as? String
            let oldId = note.userInfo?["oldOrderId"] as? String
            guard notifiedId == self.orderId || oldId == self.orderId else { return }
            self.cacheStore.invalidateOrderUsage(orderId: self.orderId)
            self.load()
            self.info = loc("支付成功，已刷新详情与用量")
        }

        // 监听支付失败事件：若匹配当前订单，提示失败并重拉详情
        paymentFailedObserver = NotificationCenter.default.addObserver(
            forName: .paymentFailed,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            let notifiedId = note.userInfo?["orderId"] as? String
            let oldId = note.userInfo?["oldOrderId"] as? String
            guard notifiedId == self.orderId || oldId == self.orderId else { return }
            let reason = note.userInfo?["reason"] as? String
            let message = (reason?.isEmpty == false) ? String(format: loc("支付失败：%@"), reason!) : loc("支付失败")
            // 简单节流：2秒内重复错误不再次提示
            if self.error == message, let last = self.lastErrorAt, Date().timeIntervalSince(last) < 2 { return }
            // 先刷新详情，再设置错误，避免在 load() 内部清空 error 导致横幅一闪而过
            self.load()
            self.error = message
            self.lastErrorAt = Date()
        }
    }

    deinit {
        if let obs = installationObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = paymentObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = paymentFailedObserver { NotificationCenter.default.removeObserver(obs) }
    }

    func load() {
        guard !isLoading else { return }
        Telemetry.shared.logEvent("order_detail_open", parameters: ["order_id": orderId])
        // SWR：如有订单详情缓存先渲染，避免骨架
        if let cached = cacheStore.loadOrder(id: orderId, ttl: AppConfig.orderDetailCacheTTL) {
            order = cached.item
            isLoading = false
        } else {
            isLoading = true
        }
        error = nil
        Task {
            // 记录期望键以用于结果匹配与 isLoading 关闭（需在 do-catch 外部声明，便于 catch 与后续访问）
            var expectedListKey: String? = nil
            var expectedDetailKey: String? = nil
            do {

                if let upstream = upstreamRepository {
                    let rid = UUID().uuidString
                    expectedDetailKey = ["order:detail:id", orderId].joined(separator: "|")
                    if let prev = currentOrderDetailKey, prev != expectedDetailKey { await RequestCenter.shared.cancel(key: prev) }
                    currentOrderDetailKey = expectedDetailKey

                    let dto = try await upstream.getOrderDetailById(orderId: orderId, requestId: rid)

                    guard self.currentOrderDetailKey == expectedDetailKey else { return }

                    let prev = self.order
                    let createdAt: Date = {
                        let s = dto.dateCreated ?? ""
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
                        return prev?.createdAt ?? Date()
                    }()
                    let status: OrderStatus = {
                        let raw = (dto.orderStatus ?? "").lowercased()
                        if raw.contains("paid") || raw.contains("success") || raw.contains("active") { return .paid }
                        if raw.contains("fail") { return .failed }
                        return .created
                    }()
                    let bundleExp: Date? = Self.parseDate(dto.bundleExpiryDate)
                    let profileExp: Date? = Self.parseDate(dto.expiryDate)
                    let amtCur: (Decimal, String) = {
                        if let p = prev, p.amount > 0 { return (p.amount, p.currency) }
                        if let cached = cacheStore.loadOrders(ttl: AppConfig.ordersCacheTTL)?.list.first(where: { $0.id == dto.orderId }) {
                            return (cached.amount, cached.currency)
                        }
                        return (0, "USD")
                    }()
                    let mapped = Order(
                        id: dto.orderId,
                        bundleId: dto.bundleCode ?? "",
                        amount: amtCur.0,
                        currency: amtCur.1,
                        createdAt: createdAt,
                        status: status,
                        paymentMethod: prev?.paymentMethod ?? .paypal,
                        installation: OrderInstallationInfo(
                            qrCodeURL: nil,
                            activationCode: dto.activationCode,
                            instructions: [],
                            profileURL: nil,
                            smdpAddress: dto.smdpAddress
                        ),
                        orderStatusText: dto.orderStatus,
                        orderReference: dto.orderReference,
                        bundleCategory: dto.bundleCategory,
                        bundleMarketingName: dto.bundleMarketingName,
                        bundleName: dto.bundleName,
                        countryCode: (dto.countryCode ?? []).first,
                        countryName: (dto.countryName ?? []).first,
                        iccid: dto.iccid,
                        bundleExpiryDate: bundleExp,
                        expiryDate: profileExp,
                        planStarted: dto.planStarted,
                        planStatusText: dto.planStatus
                    )
                    order = mapped
                    cacheStore.saveOrder(mapped, id: orderId)
                    await loadUsage(force: order?.status == .paid)
                    await loadBundleIfNeeded()

                    let stillValid = (expectedDetailKey != nil) && (self.currentOrderDetailKey == expectedDetailKey)
                    if !stillValid { return }
                } else {
                    let fetched = try await repository.fetchOrder(id: orderId)
                    order = fetched
                    cacheStore.saveOrder(fetched, id: orderId)
                    await loadUsage(force: order?.status == .paid)
                    await loadBundleIfNeeded()
                }
            } catch {
                // 若为上游路径，仅在键仍匹配时设置错误；非上游路径始终设置错误
                let shouldSetError: Bool = {
                    if upstreamRepository == nil { return true }
                    let detailOk = (expectedDetailKey == nil) || (self.currentOrderDetailKey == expectedDetailKey)
                    return detailOk
                }()
                if shouldSetError { self.error = error.localizedDescription }
                Telemetry.shared.record(error: error)
            }
            if upstreamRepository == nil {
                isLoading = false
            } else {
                let stillValid = (expectedDetailKey != nil) && (currentOrderDetailKey == expectedDetailKey)
                if stillValid { isLoading = false }
            }
        }
    }

    func loadUsage(force: Bool = false) async {
        guard !isLoadingUsage else { return }
        isLoadingUsage = true
        // SWR：先读短 TTL 用量缓存；未过期直接渲染并返回
        if let cached = cacheStore.loadOrderUsage(orderId: orderId, ttl: AppConfig.orderUsageCacheTTL) {
            usage = cached.item
            if !cached.isExpired && !force {
                isLoadingUsage = false
                Telemetry.shared.logEvent("order_usage_cache", parameters: ["order_id": orderId])
                return
            }
        }
        // 记录期望键以用于结果匹配与 isLoadingUsage 关闭
        var expectedKey: String? = nil
        do {
            if let upstream = upstreamRepository {
                let rid = UUID().uuidString
                expectedKey = ["order:consumption:id", orderId].joined(separator: "|")
                if let prev = currentConsumptionKey, prev != expectedKey { await RequestCenter.shared.cancel(key: prev) }
                currentConsumptionKey = expectedKey

                let dto = try await upstream.getConsumptionByOrderId(orderId: orderId, requestId: rid)

                guard self.currentConsumptionKey == expectedKey else { return }

                let unit = (dto.dataUnit ?? "MB").uppercased()
                let allocatedMB: Double? = {
                    guard let num = dto.dataAllocated else { return nil }
                    switch unit {
                    case "GB": return num * 1024
                    case "MB": return num
                    case "KB": return num / 1024
                    default: return num
                    }
                }()
                let usedMB: Double? = {
                    guard let num = dto.dataUsed else { return nil }
                    switch unit {
                    case "GB": return num * 1024
                    case "MB": return num
                    case "KB": return num / 1024
                    default: return num
                    }
                }()
                let remainingMB: Double = {
                    if let num = dto.dataRemaining {
                        switch unit {
                        case "GB": return num * 1024
                        case "MB": return num
                        case "KB": return num / 1024
                        default: return num
                        }
                    }
                    if let a = allocatedMB, let u = usedMB, a >= u { return a - u }
                    return 0
                }()
                let expiresAt: Date? = {
                    let primary = dto.bundleExpiryDate ?? dto.profileExpiryDate
                    if let s = primary {
                        if let ts = Double(s) { return Date(timeIntervalSince1970: ts) }
                        let iso = ISO8601DateFormatter()
                        if let dt = iso.date(from: s) { return dt }
                        let fmt = DateFormatter()
                        fmt.locale = Locale(identifier: "en_US_POSIX")
                        fmt.dateFormat = "MMM dd, yyyy 'at' HH:mm:ss"
                        if let dt2 = fmt.date(from: s) { return dt2 }
                    }
                    return nil
                }()
                var newUsage = OrderUsage(
                    remainingMB: remainingMB,
                    expiresAt: expiresAt,
                    lastUpdated: Date()
                )
                newUsage.allocatedMB = allocatedMB
                newUsage.usedMB = usedMB
                newUsage.dataUnitRaw = dto.dataUnit
                newUsage.minutesAllocated = dto.minutesAllocated
                newUsage.minutesRemaining = dto.minutesRemaining
                newUsage.minutesUsed = dto.minutesUsed
                newUsage.smsAllocated = dto.smsAllocated
                newUsage.smsRemaining = dto.smsRemaining
                newUsage.smsUsed = dto.smsUsed
                newUsage.supportsCallsSms = dto.supportsCallsSms
                newUsage.unlimited = dto.unlimited
                newUsage.iccid = dto.iccid
                newUsage.planStatusText = dto.planStatus
                newUsage.policyStatusText = dto.policyStatus
                newUsage.profileStatusText = dto.profileStatus
                usage = newUsage
                cacheStore.saveOrderUsage(newUsage, orderId: orderId)
                Telemetry.shared.logEvent("order_usage_fetched", parameters: ["order_id": orderId])
            } else {
                let data = try await usageRepository.fetchUsage(orderId: orderId)
                usage = data
                cacheStore.saveOrderUsage(data, orderId: orderId)
                Telemetry.shared.logEvent("order_usage_fetched", parameters: ["order_id": orderId])
            }
        } catch {
            // 不覆盖主错误；仅在UI中不显示用量
            Telemetry.shared.record(error: error)
        }
        // 仅在键仍匹配时关闭用量加载状态（非上游路径直接关闭）
        if upstreamRepository == nil {
            isLoadingUsage = false
        } else if (expectedKey != nil) && (currentConsumptionKey == expectedKey) {
            isLoadingUsage = false
        }
    }

    func refreshUsage() {
        Telemetry.shared.logEvent("order_usage_refresh", parameters: ["order_id": orderId])
        Task { await loadUsage(force: true) }
    }

    func loadBundleIfNeeded() async {
        guard !isLoadingBundle else { return }
        isLoadingBundle = true
        do {
            if let code = order?.bundleId, !code.isEmpty {
                if let cached = cacheStore.loadBundleDetail(id: code, ttl: AppConfig.catalogCacheTTL), !cached.isExpired {
                    bundle = cached.item
                    isLoadingBundle = false
                    return
                }
                if let upstream = upstreamCatalogRepository {
                    let rid = UUID().uuidString
                    let b = try await upstream.getBundleByCode(bundleCode: code, requestId: rid)
                    bundle = b
                    cacheStore.saveBundleDetail(b, id: code)
                } else {
                    let b = try await catalogRepository.fetchBundle(id: code)
                    bundle = b
                    cacheStore.saveBundleDetail(b, id: code)
                }
            }
        } catch {
        }
        isLoadingBundle = false
    }

    func requestRefund(reason: String) {
        guard let id = order?.id else { return }
        isRequestingRefund = true
        refundSucceeded = nil
        refundState = nil
        refundProgress = []
        error = nil
        Task {
            do {
                if let upstream = upstreamRepository {
                    let rid = UUID().uuidString
                    let res = try await upstream.refundOrderById(orderId: id, reason: reason, requestId: rid)
                    refundSucceeded = res.accepted
                    refundState = res.state
                    refundProgress = res.progress ?? []
                } else {
                    let res = try await repository.refundOrder(id: id, reason: reason)
                    refundSucceeded = res.accepted
                    refundState = res.state
                    refundProgress = res.progress ?? []
                }
                if refundSucceeded == true {
                    cacheStore.invalidateOrderUsage(orderId: id)
                    usage = nil
                }
            } catch {
                self.error = error.localizedDescription
            }
            isRequestingRefund = false
        }
    }

    var isRefundAllowed: Bool {
        guard let o = order else { return false }
        if o.status != .paid { return false }
        if o.planStarted == true { return false }
        if let u = usage?.usedMB, u > 0 { return false }
        return true
    }

    // MARK: - Helpers
    private static func parseNumber(from text: String) -> Double? {
        // 提取数字和小数点
        let allowed = Set("0123456789.")
        let filtered = String(text.filter { allowed.contains($0) })
        return Double(filtered)
    }

    private static func parseDate(_ text: String?) -> Date? {
        guard let s = text, !s.isEmpty else { return nil }
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
        return nil
    }
}
