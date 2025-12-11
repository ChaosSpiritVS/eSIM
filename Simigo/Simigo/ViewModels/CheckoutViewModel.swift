import Foundation
import UIKit

@MainActor
final class CheckoutViewModel: ObservableObject {
    @Published var isPlacingOrder = false
    @Published var error: String?
    @Published var order: Order?
    @Published var selectedPaymentMethod: PaymentMethod?
    
    @Published var availableMethods: Set<PaymentMethod> = []

    let bundle: ESIMBundle?
    let existingOrder: Order?
    private let repository: OrderRepositoryProtocol
    private let processorFactory = PaymentProcessorFactory()
    private let cacheStore = CatalogCacheStore.shared
    private let upstreamCatalogRepository: UpstreamCatalogRepositoryProtocol?
    // 轻量分配结果匹配：仅当当前引用一致时回写新订单ID或错误
    private var currentAssignRef: String?
    private let auth: AuthManager

    init(bundle: ESIMBundle, auth: AuthManager, repository: OrderRepositoryProtocol? = nil) {
        self.bundle = bundle
        self.existingOrder = nil
        self.repository = repository ?? (AppConfig.isMock ? MockOrderRepository() : HTTPOrderRepository())
        self.upstreamCatalogRepository = AppConfig.useAliasAPI ? HTTPUpstreamCatalogRepository() : nil
        self.auth = auth
    }

    init(order: Order, bundle: ESIMBundle? = nil, auth: AuthManager, repository: OrderRepositoryProtocol? = nil) {
        self.existingOrder = order
        self.bundle = bundle
        self.repository = repository ?? (AppConfig.isMock ? MockOrderRepository() : HTTPOrderRepository())
        self.order = order
        let raw = (bundle?.countryCode) ?? (order.countryCode)
        let code2 = raw.map { RegionCodeConverter.toAlpha2($0) } ?? ""
        let allowAli = (code2 == "CN" || code2 == "HK")
        if order.paymentMethod == .googlepay || (order.paymentMethod == .alipay && !allowAli) {
            self.selectedPaymentMethod = .card
        } else {
            self.selectedPaymentMethod = order.paymentMethod
        }
        self.upstreamCatalogRepository = AppConfig.useAliasAPI ? HTTPUpstreamCatalogRepository() : nil
        self.auth = auth
    }

    init(auth: AuthManager, repository: OrderRepositoryProtocol? = nil) {
        self.bundle = nil
        self.existingOrder = nil
        self.repository = repository ?? (AppConfig.isMock ? MockOrderRepository() : HTTPOrderRepository())
        self.upstreamCatalogRepository = AppConfig.useAliasAPI ? HTTPUpstreamCatalogRepository() : nil
        self.auth = auth
    }

    func placeOrder() {
        guard !isPlacingOrder else { return }
        isPlacingOrder = true
        error = nil
        Task {
            do {
                if (auth.currentUser?.kycStatus?.lowercased() ?? "") != "verified" {
                    struct KycStartDTO: Decodable { let provider: String?; let sessionUrl: String? }
                    struct Empty: Encodable {}
                    let service = NetworkService()
                    do {
                        let dto: KycStartDTO = try await service.post("/kyc/start", body: Empty())
                        if let u = dto.sessionUrl, let url = URL(string: u) { _ = await UIApplication.shared.open(url) }
                        // 轮询 /me，等待验证完成（最长 30 秒）
                        let repo = HTTPUserRepository()
                        let deadline = Date().addingTimeInterval(30)
                        while Date() < deadline {
                            try await Task.sleep(nanoseconds: 2_000_000_000)
                            do {
                                let me = try await repo.getMe()
                                self.auth.currentUser = me
                                if (me.kycStatus?.lowercased() ?? "") == "verified" { break }
                            } catch {
                                // ignore transient failures
                            }
                        }
                        if (self.auth.currentUser?.kycStatus?.lowercased() ?? "") != "verified" {
                            self.error = loc("需要完成身份验证")
                            isPlacingOrder = false
                            return
                        }
                    } catch {
                        self.error = error.localizedDescription
                        isPlacingOrder = false
                        return
                    }
                }
                await ensureSupportedSelection()
                if let existing = existingOrder {
                    var current = existing
                    if let method = selectedPaymentMethod, let processor = processorFactory.processor(for: method) {
                        let status: OrderStatus
                        do {
                            status = try await processor.startPayment(for: current)
                        } catch {
                            // 捕获支付流程异常并透传失败原因
                            PaymentEventBridge.paymentFailed(
                                orderId: current.id,
                                reason: error.localizedDescription,
                                method: String(describing: method),
                                error: error
                            )
                            throw error
                        }
                        current = Order(
                            id: current.id,
                            bundleId: current.bundleId,
                            amount: current.amount,
                            currency: current.currency,
                            createdAt: current.createdAt,
                            status: status,
                            paymentMethod: method,
                            installation: current.installation
                        )
                        // 充值/支付成功后失效订单用量缓存，确保下次拉取到最新用量
                        if status == .paid {
                            cacheStore.invalidateOrderUsage(orderId: current.id)

                            // 记录原始订单ID，便于事件内同时透传新旧ID
                            let originalId = current.id

                            // 别名模式：支付成功后进行上游分配，切换为上游订单ID
                            if let upstream = upstreamCatalogRepository {
                                let rid = UUID().uuidString
                                var ref = current.id.replacingOccurrences(of: "-", with: "")
                                if ref.count > 30 { ref = String(ref.prefix(30)) }
                                self.currentAssignRef = ref
                                do {
                                    let result = try await upstream.assignBundle(
                                        bundleCode: current.bundleId,
                                        orderReference: ref,
                                        name: auth.currentUser?.name,
                                        email: auth.currentUser?.email,
                                        requestId: rid
                                    )
                                    if self.currentAssignRef == ref {
                                        let oldId = current.id
                                        let newId = result.orderId
                                        // 切换为上游订单ID，便于详情页按上游ID查询 orderReference 与用量
                                        current = Order(
                                            id: newId,
                                            bundleId: current.bundleId,
                                            amount: current.amount,
                                            currency: current.currency,
                                            createdAt: current.createdAt,
                                            status: current.status,
                                            paymentMethod: current.paymentMethod,
                                            installation: current.installation
                                        )
                                        // 失效新旧ID的用量缓存，避免显示旧数据
                                        cacheStore.invalidateOrderUsage(orderId: oldId)
                                        cacheStore.invalidateOrderUsage(orderId: newId)
                                        // 如后续需要，可在此处透传 iccid（result.iccid）到模型或日志
                                    }
                                } catch {
                                    if self.currentAssignRef == ref {
                                        if let ne = error as? NetworkError {
                                            switch ne {
                                            case .server(let code, let message):
                                                if code == 1081 { self.error = loc("上游分配失败：交易编号重复，请更换并重试") }
                                                else if code == 1070 { self.error = loc("上游分配失败：套餐不存在或不可用") }
                                                else { self.error = String(format: loc("上游分配失败：%@"), message) }
                                            default:
                                                self.error = String(format: loc("上游分配失败：%@"), error.localizedDescription)
                                            }
                                        } else {
                                            self.error = String(format: loc("上游分配失败：%@"), error.localizedDescription)
                                        }
                                    }
                                }
                                if self.currentAssignRef == ref { self.currentAssignRef = nil }
                            }

                            // 支付成功事件派发（包含可能的旧ID），供详情页监听后重拉
                            PaymentEventBridge.paymentSucceeded(
                                orderId: current.id,
                                oldOrderId: originalId,
                                method: String(describing: method)
                            )
                        } else if status == .failed {
                            // 支付失败事件派发，供列表/详情显示错误提示并刷新
                            PaymentEventBridge.paymentFailed(
                                orderId: current.id,
                                reason: nil,
                                method: String(describing: method)
                            )
                        }
                    }
                    self.order = current
                } else {
                    guard let bundle = bundle else { throw NSError(domain: "checkout", code: -1, userInfo: [NSLocalizedDescriptionKey: loc("缺少套餐信息")]) }
                    guard let method = selectedPaymentMethod else { throw NSError(domain: "checkout", code: -2, userInfo: [NSLocalizedDescriptionKey: loc("请选择付款方式")]) }
                    var created: Order
                    do {
                        created = try await repository.createOrder(bundle: bundle, paymentMethod: method)
                    } catch {
                        if let ne = error as? NetworkError {
                            switch ne {
                            case .server(let code, _):
                                if code == 403 {
                                    struct KycStartDTO: Decodable { let provider: String?; let sessionUrl: String? }
                                    struct Empty: Encodable {}
                                    let service = NetworkService()
                                    do {
                                        let dto: KycStartDTO = try await service.post("/kyc/start", body: Empty())
                                        if let u = dto.sessionUrl, let url = URL(string: u) { _ = await UIApplication.shared.open(url) }
                                        self.error = loc("需要完成身份验证")
                                    } catch {
                                        self.error = error.localizedDescription
                                    }
                                    isPlacingOrder = false
                                    return
                                }
                            default:
                                break
                            }
                        }
                        throw error
                    }
                    if let processor = processorFactory.processor(for: method) {
                        let status: OrderStatus
                        do {
                            status = try await processor.startPayment(for: created)
                        } catch {
                            // 捕获支付流程异常并透传失败原因
                            PaymentEventBridge.paymentFailed(
                                orderId: created.id,
                                reason: error.localizedDescription,
                                method: String(describing: method),
                                error: error
                            )
                            throw error
                        }
                        created = Order(
                            id: created.id,
                            bundleId: created.bundleId,
                            amount: created.amount,
                            currency: created.currency,
                            createdAt: created.createdAt,
                            status: status,
                            paymentMethod: created.paymentMethod,
                            installation: created.installation
                        )
                        // 新订单支付成功后同样失效用量缓存（如为充值型订单）
                        if status == .paid {
                            cacheStore.invalidateOrderUsage(orderId: created.id)

                            let originalId = created.id

                            // 别名模式：支付成功后进行上游分配，切换为上游订单ID
                            if let upstream = upstreamCatalogRepository {
                                let rid = UUID().uuidString
                                var ref = created.id.replacingOccurrences(of: "-", with: "")
                                if ref.count > 30 { ref = String(ref.prefix(30)) }
                                self.currentAssignRef = ref
                                do {
                                    let result = try await upstream.assignBundle(
                                        bundleCode: created.bundleId,
                                        orderReference: ref,
                                        name: auth.currentUser?.name,
                                        email: auth.currentUser?.email,
                                        requestId: rid
                                    )
                                    if self.currentAssignRef == ref {
                                        let oldId = created.id
                                        let newId = result.orderId
                                        created = Order(
                                            id: newId,
                                            bundleId: created.bundleId,
                                            amount: created.amount,
                                            currency: created.currency,
                                            createdAt: created.createdAt,
                                            status: created.status,
                                            paymentMethod: created.paymentMethod,
                                            installation: created.installation
                                        )
                                        cacheStore.invalidateOrderUsage(orderId: oldId)
                                        cacheStore.invalidateOrderUsage(orderId: newId)
                                    }
                                } catch {
                                    if self.currentAssignRef == ref {
                                        if let ne = error as? NetworkError {
                                            switch ne {
                                            case .server(let code, let message):
                                                if code == 1081 { self.error = loc("上游分配失败：交易编号重复，请更换并重试") }
                                                else if code == 1070 { self.error = loc("上游分配失败：套餐不存在或不可用") }
                                                else { self.error = String(format: loc("上游分配失败：%@"), message) }
                                            default:
                                                self.error = String(format: loc("上游分配失败：%@"), error.localizedDescription)
                                            }
                                        } else {
                                            self.error = String(format: loc("上游分配失败：%@"), error.localizedDescription)
                                        }
                                    }
                                }
                                if self.currentAssignRef == ref { self.currentAssignRef = nil }
                            }

                            PaymentEventBridge.paymentSucceeded(
                                orderId: created.id,
                                oldOrderId: originalId,
                                method: String(describing: method)
                            )
                        } else if status == .failed {
                            // 支付失败事件派发，供列表/详情显示错误提示并刷新
                            PaymentEventBridge.paymentFailed(
                                orderId: created.id,
                                reason: nil,
                                method: String(describing: method)
                            )
                        }
                    }
                    self.order = created
                }
            } catch {
                self.error = error.localizedDescription
            }
            isPlacingOrder = false
        }
    }

    func loadConsult() async {
        let prep = PaymentPreparationService()
        let amount = order?.amount ?? bundle?.price ?? 0
        let selected = (UserDefaults.standard.string(forKey: "simigo.currencyCode") ?? "").uppercased()
        let allowed: Set<String> = ["USD","CHF","CNY","EUR","GBP","HKD","JPY","SGD"]
        let currency = allowed.contains(selected) ? selected : (order?.currency ?? bundle?.currency ?? "USD")
        let regionCode = (bundle?.countryCode) ?? (order?.countryCode)
        let code2 = regionCode.map { RegionCodeConverter.toAlpha2($0) }
        do {
            let dto = try await prep.consultPaymentOptions(amount: amount, currency: currency, userRegion: code2)
            var set: Set<PaymentMethod> = []
            for opt in dto.payment_options {
                let t = (opt.payment_method_type ?? "").uppercased()
                if t.contains("ALIPAY") { set.insert(.alipay) }
                else if t.contains("PAYPAL") { set.insert(.paypal) }
                else if t.contains("APPLEPAY") { set.insert(.applepay) }
                else if t.contains("CARD") { set.insert(.card) }
            }
            self.availableMethods = set
            if let sel = selectedPaymentMethod, !set.contains(sel) {
                self.selectedPaymentMethod = set.contains(.applepay) ? .applepay : (set.contains(.paypal) ? .paypal : (set.contains(.card) ? .card : set.first))
            } else if selectedPaymentMethod == nil {
                self.selectedPaymentMethod = set.contains(.applepay) ? .applepay : (set.contains(.paypal) ? .paypal : (set.contains(.card) ? .card : set.first))
            }
        } catch {
        }
    }

    func ensureSupportedSelection() async {
        let prep = PaymentPreparationService()
        let amount = order?.amount ?? bundle?.price ?? 0
        let selected = (UserDefaults.standard.string(forKey: "simigo.currencyCode") ?? "").uppercased()
        let allowed: Set<String> = ["USD","CHF","CNY","EUR","GBP","HKD","JPY","SGD"]
        let currency = allowed.contains(selected) ? selected : (order?.currency ?? bundle?.currency ?? "USD")
        let regionCode = (bundle?.countryCode) ?? (order?.countryCode)
        let code2 = regionCode.map { RegionCodeConverter.toAlpha2($0) }
        do {
            let dto = try await prep.consultPaymentOptions(amount: amount, currency: currency, userRegion: code2)
            var set: Set<PaymentMethod> = []
            for opt in dto.payment_options {
                let t = (opt.payment_method_type ?? "").uppercased()
                if t.contains("ALIPAY") { set.insert(.alipay) }
                else if t.contains("PAYPAL") { set.insert(.paypal) }
                else if t.contains("APPLEPAY") { set.insert(.applepay) }
                else if t.contains("CARD") { set.insert(.card) }
            }
            availableMethods = set
            if let sel = selectedPaymentMethod, !set.contains(sel) {
                selectedPaymentMethod = set.contains(.applepay) ? .applepay : (set.contains(.paypal) ? .paypal : (set.contains(.card) ? .card : set.first))
                error = loc("当前付款方式不可用，已为您切换为可用方式")
            } else if selectedPaymentMethod == nil {
                selectedPaymentMethod = set.contains(.applepay) ? .applepay : (set.contains(.paypal) ? .paypal : (set.contains(.card) ? .card : set.first))
            }
        } catch {
            availableMethods = []
            let r = (bundle?.countryCode) ?? (order?.countryCode)
            let c2 = r.map { RegionCodeConverter.toAlpha2($0) } ?? ""
            if c2 == "CN" || c2 == "HK" {
                selectedPaymentMethod = .alipay
            } else {
                selectedPaymentMethod = .paypal
            }
        }
    }

    
}
