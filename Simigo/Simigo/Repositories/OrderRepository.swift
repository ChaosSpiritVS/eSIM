import Foundation

protocol OrderRepositoryProtocol {
    func createOrder(bundle: ESIMBundle, paymentMethod: PaymentMethod) async throws -> Order
    func fetchOrders() async throws -> [Order]
    func fetchOrder(id: String) async throws -> Order
    func refundOrder(id: String, reason: String) async throws -> RefundResult
}

struct MockOrderRepository: OrderRepositoryProtocol {
    func createOrder(bundle: ESIMBundle, paymentMethod: PaymentMethod) async throws -> Order {
        try await Task.sleep(nanoseconds: 400_000_000)
        return Order(
            id: UUID().uuidString,
            bundleId: bundle.id,
            amount: bundle.price,
            currency: bundle.currency,
            createdAt: Date(),
            status: .created,
            paymentMethod: paymentMethod,
            installation: nil
        )
    }

    func fetchOrders() async throws -> [Order] {
        try await Task.sleep(nanoseconds: 200_000_000)
        return [
            Order(id: UUID().uuidString, bundleId: "hk-1", amount: 3.50, currency: "GBP", createdAt: Date().addingTimeInterval(-3600), status: .paid, paymentMethod: .paypal, installation: nil),
            Order(id: UUID().uuidString, bundleId: "cn-1", amount: 3.00, currency: "GBP", createdAt: Date().addingTimeInterval(-7200), status: .created, paymentMethod: .alipay, installation: nil)
        ]
    }

    func fetchOrder(id: String) async throws -> Order {
        try await Task.sleep(nanoseconds: 150_000_000)
        return Order(
            id: id,
            bundleId: "hk-1",
            amount: 3.50,
            currency: "GBP",
            createdAt: Date().addingTimeInterval(-3600),
            status: .paid,
            paymentMethod: .alipay,
            installation: OrderInstallationInfo(
                qrCodeURL: "https://example.com/qr/demo.png",
                activationCode: "ABCDEF-123456",
                instructions: [
                    "在设置中选择“移动网络”→“添加 eSIM”。",
                    "扫描二维码或输入激活码。",
                    "确认并启用数据网络。"
                ],
                profileURL: "https://example.com/esim-profile.mobileconfig",
                smdpAddress: "smdp.example.com"
            )
        )
    }

    func refundOrder(id: String, reason: String) async throws -> RefundResult {
        try await Task.sleep(nanoseconds: 200_000_000)
        return RefundResult(accepted: true, state: .requested, progress: [
            RefundProgressStep(state: .requested, updatedAt: Date(), note: reason)
        ])
    }
}

struct HTTPOrderRepository: OrderRepositoryProtocol {
    let service = NetworkService()

    struct CreateOrderBody: Encodable {
        let bundleId: String
        let paymentMethod: String
    }

    struct OrderDTO: Decodable {
        let id: String
        let bundleId: String
        let amount: Double
        let currency: String
        let createdAt: Date
        let status: String
        let paymentMethod: String
        let installation: InstallationDTO?

        struct InstallationDTO: Decodable {
            let qrCodeUrl: String?
            let activationCode: String?
            let instructions: [String]?
            let profileUrl: String?
            let smdp: String?
        }
    }

    func createOrder(bundle: ESIMBundle, paymentMethod: PaymentMethod) async throws -> Order {
        let dto: OrderDTO = try await service.post("/orders", body: CreateOrderBody(bundleId: bundle.id, paymentMethod: paymentMethod.rawValue))
        return Order(
            id: dto.id,
            bundleId: dto.bundleId,
            amount: Decimal(dto.amount),
            currency: dto.currency,
            createdAt: dto.createdAt,
            status: OrderStatus(rawValue: dto.status) ?? .created,
            paymentMethod: PaymentMethod(rawValue: dto.paymentMethod) ?? paymentMethod,
            installation: dto.installation.map { ins in
                OrderInstallationInfo(
                    qrCodeURL: ins.qrCodeUrl,
                    activationCode: ins.activationCode,
                    instructions: ins.instructions ?? [],
                    profileURL: ins.profileUrl,
                    smdpAddress: ins.smdp
                )
            }
        )
    }

    func fetchOrders() async throws -> [Order] {
        let dtos: [OrderDTO] = try await service.get("/orders")
        return dtos.map { dto in
            Order(
                id: dto.id,
                bundleId: dto.bundleId,
                amount: Decimal(dto.amount),
                currency: dto.currency,
                createdAt: dto.createdAt,
                status: OrderStatus(rawValue: dto.status) ?? .created,
                paymentMethod: PaymentMethod(rawValue: dto.paymentMethod) ?? .paypal,
                installation: dto.installation.map { ins in
                    OrderInstallationInfo(
                        qrCodeURL: ins.qrCodeUrl,
                        activationCode: ins.activationCode,
                        instructions: ins.instructions ?? [],
                        profileURL: ins.profileUrl,
                        smdpAddress: ins.smdp
                    )
                }
            )
        }
    }

    func fetchOrder(id: String) async throws -> Order {
        let dto: OrderDTO = try await service.get("/orders/\(id)")
        return Order(
            id: dto.id,
            bundleId: dto.bundleId,
            amount: Decimal(dto.amount),
            currency: dto.currency,
            createdAt: dto.createdAt,
            status: OrderStatus(rawValue: dto.status) ?? .created,
            paymentMethod: PaymentMethod(rawValue: dto.paymentMethod) ?? .paypal,
            installation: dto.installation.map { ins in
                OrderInstallationInfo(
                    qrCodeURL: ins.qrCodeUrl,
                    activationCode: ins.activationCode,
                    instructions: ins.instructions ?? [],
                    profileURL: ins.profileUrl,
                    smdpAddress: ins.smdp
                )
            }
        )
    }

    func refundOrder(id: String, reason: String) async throws -> RefundResult {
        struct RefundBody: Encodable { let reason: String }
        struct RefundStepDTO: Decodable { let state: String; let updatedAt: Date; let note: String? }
        struct RefundDTO: Decodable { let accepted: Bool; let state: String?; let steps: [RefundStepDTO]? }
        let dto: RefundDTO = try await service.post("/orders/\(id)/refund", body: RefundBody(reason: reason))
        let mappedState: RefundState? = dto.state.flatMap { RefundState(rawValue: $0) }
        let mappedSteps: [RefundProgressStep]? = dto.steps?.compactMap { step in
            guard let st = RefundState(rawValue: step.state) else { return nil }
            return RefundProgressStep(state: st, updatedAt: step.updatedAt, note: step.note)
        }
        return RefundResult(accepted: dto.accepted, state: mappedState, progress: mappedSteps)
    }
}