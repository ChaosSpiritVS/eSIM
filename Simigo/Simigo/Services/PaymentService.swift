import Foundation
import UIKit

func selectedCurrency(fallback: String) -> String {
    let selected = (UserDefaults.standard.string(forKey: "simigo.currencyCode") ?? "").uppercased()
    let allowed = (UserDefaults.standard.array(forKey: "simigo.allowedCurrencies") as? [String])?.map { $0.uppercased() } ?? [
        "USD","EUR","GBP","CHF","CNY","HKD","JPY","SGD",
        "KRW","THB","IDR","MYR","VND","BRL","MXN","TWD",
        "AED","SAR","AUD","CAD"
    ]
    return Set(allowed).contains(selected) ? selected : fallback
}

protocol PaymentProcessorProtocol {
    func startPayment(for order: Order) async throws -> OrderStatus
}

/// 准备支付所需的后端数据（如支付宝 orderString）
actor PaymentPreparationService {
    private let network = NetworkService()

    struct AlipayCreateBody: Encodable { let orderId: String }
    struct AlipayCreateDTO: Decodable { let orderString: String }
    struct GsalaryCreateBody: Encodable {
        let orderId: String
        let method: String
        let amount: Double
        let currency: String
    }
    struct GsalaryConsultBody: Encodable {
        let amount: Double
        let currency: String
        let settlementCurrency: String?
        let allowedPaymentMethodRegions: [String]?
        let allowedPaymentMethods: [String]?
        let userRegion: String?
        let envTerminalType: String?
        let envOsType: String?
        let envClientIp: String?
    }
    struct GsalaryConsultCardBrandDTO: Decodable {
        let card_brand: String?
        let brand_logo_name: String?
        let brand_logo_url: String?
    }
    struct GsalaryConsultOptionDTO: Decodable {
        let payment_method_type: String?
        let payment_method_logo_name: String?
        let payment_method_logo_url: String?
        let payment_method_category: String?
        let payment_method_region: [String]?
        let support_card_brands: [GsalaryConsultCardBrandDTO]?
        let card_funding: [String]?
    }
    struct GsalaryConsultDTO: Decodable { let payment_options: [GsalaryConsultOptionDTO] }
    struct GsalaryCreateDTO: Decodable {
        let checkoutUrl: String
        let paymentId: String
        let paymentMethodId: String?
        let paymentRequestId: String?
    }
    struct GsalaryPayBody: Encodable {
        let orderId: String
        let method: String
        let payment_method_id: String?
        let amount: Double
        let currency: String
    }
    struct GsalaryPayDTO: Decodable {
        let checkoutUrl: String?
        let paymentId: String
        let schemeUrl: String?
        let applinkUrl: String?
        let appIdentifier: String?
    }
    struct GsalaryCancelBody: Encodable { let payment_request_id: String }
    struct GsalaryCancelDTO: Decodable { let paymentId: String; let paymentRequestId: String; let cancelTime: String }
    
    struct GsalaryRefundBody: Encodable {
        let refund_request_id: String
        let payment_request_id: String
        let refund_currency: String
        let refund_amount: Double
        let refund_reason: String?
    }
    struct GsalaryRefundDTO: Decodable {
        let refund_request_id: String
        let refund_id: String
        let payment_id: String?
        let payment_request_id: String?
        let refund_status: String?
        let refund_currency: String?
        let refund_amount: Double?
        let refund_create_time: String?
    }
    struct GsalaryQueryPayBody: Encodable {
        let payment_request_id: String?
        let payment_id: String?
    }
    struct SimpleAmountDTO: Decodable {
        let currency: String?
        let amount: Double?
    }
    struct SettlementQuoteDTO: Decodable {
        let guaranteed: Bool?
        let quote_currency_pair: String?
        let quote_expiry_time: String?
        let quote_id: String?
        let quote_price: Double?
        let quote_start_time: String?
    }
    struct ThreeDSResultDTO: Decodable {
        let three_ds_version: String?
        let eci: String?
        let cavv: String?
        let ds_transaction_id: String?
        let xid: String?
    }
    struct PaymentResultInfoDTO: Decodable {
        let funding: String?
        let credit_pay_plan: CreditPayPlanDTO?
        let card_no: String?
        let card_brand: String?
        let card_token: String?
        let issuing_country: String?
        let payment_method_region: String?
        let three_ds_result: ThreeDSResultDTO?
        let avs_result_raw: String?
        let cvv_result_raw: String?
        let network_transaction_id: String?
        let cardholder_name: String?
        let card_bin: String?
        let last_four: String?
        let expiry_month: String?
        let expiry_year: String?
        struct CreditPayPlanDTO: Decodable {
            let installment_num: Int?
            let interval: String?
        }
    }
    struct TransactionDTO: Decodable {
        let transaction_id: String?
        let transaction_type: String?
        let transaction_amount: Double?
        let transaction_currency: String?
        let transaction_request_id: String?
        let transaction_time: String?
    }
    struct GsalaryQueryPayDTO: Decodable {
        let payment_method_type: String?
        let payment_status: String?
        let payment_result_message: String?
        let payment_request_id: String?
        let payment_id: String?
        let payment_amount: SimpleAmountDTO?
        let surcharge: SimpleAmountDTO?
        let gross_settlement_amount: SimpleAmountDTO?
        let customs_declaration_amount: SimpleAmountDTO?
        let payment_create_time: String?
        let payment_time: String?
        let captured: Bool?
        let capture_time: String?
        let settlement_quote: SettlementQuoteDTO?
        let payment_result_info: PaymentResultInfoDTO?
        let transactions: [TransactionDTO]?
    }
    struct GsalaryRefundQueryBody: Encodable {
        let refund_request_id: String?
        let refund_id: String?
        let payment_request_id: String?
    }
    struct GsalaryRefundQueryDTO: Decodable {
        let refund_id: String?
        let refund_request_id: String?
        let payment_id: String?
        let payment_request_id: String?
        let refund_currency: String?
        let refund_amount: Double?
        let refund_status: String?
        let refund_time: String?
        let refund_create_time: String?
        let refund_result_message: String?
    }

    func createAlipayOrderString(orderId: String) async throws -> String {
        if AppConfig.isMock {
            return "MOCK_ALIPAY_ORDER_STRING"
        } else {
            let dto: AlipayCreateDTO = try await network.post("/payments/alipay/create", body: AlipayCreateBody(orderId: orderId))
            return dto.orderString
        }
    }

    func createGsalaryPayment(orderId: String, method: PaymentMethod, amount: Decimal, currency: String) async throws -> GsalaryCreateDTO {
        if AppConfig.isMock {
            return GsalaryCreateDTO(
                checkoutUrl: "https://example.com/checkout?mock=1",
                paymentId: "MOCK-PAY-\(orderId)",
                paymentMethodId: nil,
                paymentRequestId: "PAY_\(orderId)"
            )
        } else {
            let body = GsalaryCreateBody(orderId: orderId, method: method.rawValue, amount: NSDecimalNumber(decimal: amount).doubleValue, currency: currency)
            let dto: GsalaryCreateDTO = try await network.post("/payments/gsalary/create", body: body)
            return dto
        }
    }

    func consultPaymentOptions(amount: Decimal, currency: String, userRegion: String?) async throws -> GsalaryConsultDTO {
        let body = GsalaryConsultBody(
            amount: NSDecimalNumber(decimal: amount).doubleValue,
            currency: currency,
            settlementCurrency: currency,
            allowedPaymentMethodRegions: nil,
            allowedPaymentMethods: nil,
            userRegion: userRegion,
            envTerminalType: "APP",
            envOsType: "IOS",
            envClientIp: nil
        )
        let dto: GsalaryConsultDTO = try await network.post("/payments/gsalary/consult", body: body)
        return dto
    }

    

    func payGsalary(orderId: String, method: PaymentMethod, paymentMethodId: String?, amount: Decimal, currency: String) async throws -> GsalaryPayDTO {
        let body = GsalaryPayBody(orderId: orderId, method: method.rawValue, payment_method_id: paymentMethodId, amount: NSDecimalNumber(decimal: amount).doubleValue, currency: currency)
        let dto: GsalaryPayDTO = try await network.post("/payments/gsalary/pay", body: body)
        return dto
    }

    func cancelGsalary(paymentRequestId: String) async throws -> GsalaryCancelDTO {
        let dto: GsalaryCancelDTO = try await network.post("/payments/gsalary/cancel", body: GsalaryCancelBody(payment_request_id: paymentRequestId))
        return dto
    }

    func refundGsalary(refundRequestId: String, paymentRequestId: String, currency: String, amount: Decimal, reason: String?) async throws -> GsalaryRefundDTO {
        let body = GsalaryRefundBody(refund_request_id: refundRequestId, payment_request_id: paymentRequestId, refund_currency: currency, refund_amount: NSDecimalNumber(decimal: amount).doubleValue, refund_reason: reason)
        let dto: GsalaryRefundDTO = try await network.post("/payments/gsalary/refund", body: body)
        return dto
    }
    func queryGsalaryPayment(paymentRequestId: String?, paymentId: String?) async throws -> GsalaryQueryPayDTO {
        let body = GsalaryQueryPayBody(payment_request_id: paymentRequestId, payment_id: paymentId)
        let dto: GsalaryQueryPayDTO = try await network.post("/payments/gsalary/query", body: body)
        return dto
    }
    func queryGsalaryRefund(refundRequestId: String?, refundId: String?, paymentRequestId: String?) async throws -> GsalaryRefundQueryDTO {
        let body = GsalaryRefundQueryBody(refund_request_id: refundRequestId, refund_id: refundId, payment_request_id: paymentRequestId)
        let dto: GsalaryRefundQueryDTO = try await network.post("/payments/gsalary/refund/query", body: body)
        return dto
    }
}

/// 支付宝支付处理器（Mock）
struct MockAlipayProcessor: PaymentProcessorProtocol {
    let prep = PaymentPreparationService()
    func startPayment(for order: Order) async throws -> OrderStatus {
        // 模拟：先向后端请求 orderString（或直接返回Mock值），随后“拉起”支付
        _ = try await prep.createAlipayOrderString(orderId: order.id)
        try await Task.sleep(nanoseconds: 600_000_000)
        return .paid
    }
}

/// PayPal支付处理器（Mock）
struct MockPayPalProcessor: PaymentProcessorProtocol {
    func startPayment(for order: Order) async throws -> OrderStatus {
        try await Task.sleep(nanoseconds: 600_000_000)
        return .paid
    }
}

/// 支付宝处理器（真实接入占位，SDK可用时启用）
struct AlipayProcessor: PaymentProcessorProtocol {
    let prep = PaymentPreparationService()
    func startPayment(for order: Order) async throws -> OrderStatus {
        #if canImport(AlipaySDK)
        let orderString = try await prep.createAlipayOrderString(orderId: order.id)
        // 这里应调用 AlipaySDK 的 payOrder 接口并在回调中解析结果
        // 为避免引入未安装的SDK导致编译错误，此处仅保留占位逻辑
        return .paid
        #else
        throw NSError(domain: "payment.alipay", code: -1, userInfo: [NSLocalizedDescriptionKey: "Alipay SDK 未集成"])
        #endif
    }
}

struct GsalaryAlipayProcessor: PaymentProcessorProtocol {
    let prep = PaymentPreparationService()
    func startPayment(for order: Order) async throws -> OrderStatus {
        let session = try await prep.createGsalaryPayment(orderId: order.id, method: .alipay, amount: order.amount, currency: selectedCurrency(fallback: order.currency))
        await PaymentLauncher.open(urlString: session.checkoutUrl)
        return try await PaymentPoller.waitUntilPaid(prep: prep, paymentId: session.paymentId, paymentRequestId: session.paymentRequestId, timeoutSeconds: AppConfig.paymentPollTimeoutSeconds)
    }
}

struct GsalaryPayPalProcessor: PaymentProcessorProtocol {
    let prep = PaymentPreparationService()
    func startPayment(for order: Order) async throws -> OrderStatus {
        let session = try await prep.createGsalaryPayment(orderId: order.id, method: .paypal, amount: order.amount, currency: selectedCurrency(fallback: order.currency))
        await PaymentLauncher.open(urlString: session.checkoutUrl)
        return try await PaymentPoller.waitUntilPaid(prep: prep, paymentId: session.paymentId, paymentRequestId: session.paymentRequestId, timeoutSeconds: AppConfig.paymentPollTimeoutSeconds)
    }
}

struct GsalaryCardProcessor: PaymentProcessorProtocol {
    let prep = PaymentPreparationService()
    func startPayment(for order: Order) async throws -> OrderStatus {
        // 第一次支付：创建会话用于卡授权，用户输入卡信息并完成授权
        let session = try await prep.createGsalaryPayment(orderId: order.id, method: .card, amount: order.amount, currency: selectedCurrency(fallback: order.currency))
        await PaymentLauncher.open(urlString: session.checkoutUrl)
        // 轮询获取 card_token（payment_result_info.card_token）
        let token = try await PaymentPoller.waitForCardToken(prep: prep, paymentId: session.paymentId, paymentRequestId: session.paymentRequestId, timeoutSeconds: AppConfig.paymentPollTimeoutSeconds)
        
        // 第二次支付：使用 card token 作为 payment_method_id 进行扣款
        let pay = try await prep.payGsalary(orderId: order.id, method: .card, paymentMethodId: token, amount: order.amount, currency: selectedCurrency(fallback: order.currency))
        if let app = pay.applinkUrl, !app.isEmpty { await PaymentLauncher.open(urlString: app) }
        else if let scheme = pay.schemeUrl, !scheme.isEmpty { await PaymentLauncher.open(urlString: scheme) }
        else if let web = pay.checkoutUrl, !web.isEmpty { await PaymentLauncher.open(urlString: web) }
        return try await PaymentPoller.waitUntilPaid(prep: prep, paymentId: pay.paymentId, paymentRequestId: session.paymentRequestId, timeoutSeconds: AppConfig.paymentPollTimeoutSeconds)
    }
}

struct GsalaryApplePayProcessor: PaymentProcessorProtocol {
    let prep = PaymentPreparationService()
    func startPayment(for order: Order) async throws -> OrderStatus {
        let session = try await prep.createGsalaryPayment(orderId: order.id, method: .applepay, amount: order.amount, currency: selectedCurrency(fallback: order.currency))
        let pay = try await prep.payGsalary(orderId: order.id, method: .applepay, paymentMethodId: nil, amount: order.amount, currency: selectedCurrency(fallback: order.currency))
        if let app = pay.applinkUrl, !app.isEmpty { await PaymentLauncher.open(urlString: app) }
        else if let scheme = pay.schemeUrl, !scheme.isEmpty { await PaymentLauncher.open(urlString: scheme) }
        else if let web = pay.checkoutUrl, !web.isEmpty { await PaymentLauncher.open(urlString: web) }
        return try await PaymentPoller.waitUntilPaid(prep: prep, paymentId: pay.paymentId, paymentRequestId: session.paymentRequestId, timeoutSeconds: AppConfig.paymentPollTimeoutSeconds)
    }
}

struct GsalaryGooglePayProcessor: PaymentProcessorProtocol {
    let prep = PaymentPreparationService()
    func startPayment(for order: Order) async throws -> OrderStatus {
        _ = try await prep.createGsalaryPayment(orderId: order.id, method: .googlepay, amount: order.amount, currency: selectedCurrency(fallback: order.currency))
        let _ = try await prep.payGsalary(orderId: order.id, method: .googlepay, paymentMethodId: nil, amount: order.amount, currency: selectedCurrency(fallback: order.currency))
        return .paid
    }
}

struct MockCardProcessor: PaymentProcessorProtocol {
    let prep = PaymentPreparationService()
    func startPayment(for order: Order) async throws -> OrderStatus {
        let session = try await prep.createGsalaryPayment(orderId: order.id, method: .card, amount: order.amount, currency: selectedCurrency(fallback: order.currency))
        await PaymentLauncher.open(urlString: session.checkoutUrl)
        return .paid
    }
}

struct MockApplePayProcessor: PaymentProcessorProtocol {
    func startPayment(for order: Order) async throws -> OrderStatus {
        return .paid
    }
}

struct MockGooglePayProcessor: PaymentProcessorProtocol {
    func startPayment(for order: Order) async throws -> OrderStatus {
        return .paid
    }
}

@MainActor
enum PaymentLauncher {
    static func open(urlString: String?) async {
        guard let s = urlString, let url = URL(string: s) else { return }
        await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:]) { _ in cont.resume() }
            }
        }
    }
}

enum PaymentPoller {
    static func waitUntilPaid(prep: PaymentPreparationService, paymentId: String?, paymentRequestId: String?, timeoutSeconds: Int) async throws -> OrderStatus {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(AppConfig.paymentPollIntervalSeconds) * 1_000_000_000)
            let q = try await prep.queryGsalaryPayment(paymentRequestId: paymentRequestId, paymentId: paymentId)
            let status = (q.payment_status ?? "").uppercased()
            if ["SUCCESS", "PAID"].contains(status) { return .paid }
            if ["FAILED", "CANCELLED", "VOID"].contains((q.payment_status ?? "").uppercased()) { return .failed }
        }
        throw NSError(domain: "payment.poll", code: -1, userInfo: [NSLocalizedDescriptionKey: "支付结果未确认，请稍后在订单详情中查看"])
    }
    static func waitForCardToken(prep: PaymentPreparationService, paymentId: String?, paymentRequestId: String?, timeoutSeconds: Int) async throws -> String {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(AppConfig.paymentPollIntervalSeconds) * 1_000_000_000)
            let q = try await prep.queryGsalaryPayment(paymentRequestId: paymentRequestId, paymentId: paymentId)
            if let t = q.payment_result_info?.card_token, !(t.isEmpty) { return t }
            // 部分渠道会在授权成功后返回 SUCCESS，此时若无 token 继续等待
            if ["FAILED", "CANCELLED", "VOID"].contains((q.payment_status ?? "").uppercased()) {
                throw NSError(domain: "payment.poll", code: -2, userInfo: [NSLocalizedDescriptionKey: "卡授权失败，请重试或更换卡片"])
            }
        }
        throw NSError(domain: "payment.poll", code: -3, userInfo: [NSLocalizedDescriptionKey: "未获取到卡 token，请在订单详情中稍后重试"])
    }
}

    

/// 支付处理器工厂：根据支付方式与配置选择具体实现
struct PaymentProcessorFactory {
    func processor(for method: PaymentMethod) -> PaymentProcessorProtocol? {
        switch method {
        case .alipay:
            return AppConfig.isMock ? MockAlipayProcessor() : GsalaryAlipayProcessor()
        case .paypal:
            return AppConfig.isMock ? MockPayPalProcessor() : GsalaryPayPalProcessor()
        case .card:
            return AppConfig.isMock ? MockCardProcessor() : GsalaryCardProcessor()
        case .applepay:
            return AppConfig.isMock ? MockApplePayProcessor() : GsalaryApplePayProcessor()
        case .googlepay:
            return nil
        }
    }
}
