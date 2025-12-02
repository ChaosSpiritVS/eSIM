import Foundation

// MARK: - 上游（alias 风格）订单仓库
protocol UpstreamOrderRepositoryProtocol {
    func listOrders(
        pageNumber: Int,
        pageSize: Int,
        bundleCode: String?,
        orderId: String?,
        orderReference: String?,
        startDate: String?,
        endDate: String?,
        iccid: String?,
        requestId: String?
    ) async throws -> (orders: [HTTPUpstreamOrderRepository.OrderListItemDTO], total: Int)

    func getOrderDetail(orderReference: String, requestId: String?) async throws -> HTTPUpstreamOrderRepository.OrderDetailDTO

    func getConsumption(orderReference: String, requestId: String?) async throws -> HTTPUpstreamOrderRepository.OrderConsumptionDTO

    func initMappingsForCurrentUser(requestId: String?) async throws -> (checked: Int, updated: Int)

    func listOrdersWithUsage(
        pageNumber: Int,
        pageSize: Int,
        bundleCode: String?,
        orderId: String?,
        orderReference: String?,
        startDate: String?,
        endDate: String?,
        iccid: String?,
        requestId: String?
    ) async throws -> (items: [HTTPUpstreamOrderRepository.OrderWithUsageItemDTO], total: Int)

    func getOrderDetailById(orderId: String, requestId: String?) async throws -> HTTPUpstreamOrderRepository.OrderDetailDTO

    func getOrderDetailNormalized(orderId: String?, orderReference: String?, requestId: String?) async throws -> HTTPOrderRepository.OrderDTO

    func getConsumptionByOrderId(orderId: String, requestId: String?) async throws -> HTTPUpstreamOrderRepository.OrderConsumptionDTO

    func refundOrderById(orderId: String, reason: String, requestId: String?) async throws -> RefundResult
}

struct HTTPUpstreamOrderRepository: UpstreamOrderRepositoryProtocol {
    private let service = NetworkService()

    // MARK: - 数据传输对象（DTO）
    struct OrdersListBody: Encodable {
        let pageNumber: Int
        let pageSize: Int
        let bundleCode: String?
        let orderId: String?
        let orderReference: String?
        let startDate: String?
        let endDate: String?
        let iccid: String?
    }

    struct OrdersListWithUsageBody: Encodable {
        let pageNumber: Int
        let pageSize: Int
        let bundleCode: String?
        let orderId: String?
        let orderReference: String?
        let startDate: String?
        let endDate: String?
        let iccid: String?
    }

    struct OrderListItemDTO: Decodable {
        let orderId: String
        let orderReference: String
        let previousOrderReference: String?
        let clientName: String?
        let clientEmail: String?
        let bundleCode: String?
        let bundleName: String?
        let bundleMarketingName: String?
        let countryCode: [String]?
        let countryName: [String]?
        let bundleSalePrice: String?
        let agentSalePrice: String?
        let resellerRetailPrice: String?
        let currencyCode: String?
        let createdAt: String?
        let orderStatus: String?
        let status: Int?

        struct K: CodingKey {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
            init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            func decodeString(_ keys: [String]) -> String? {
                for k in keys {
                    if let v = try? c.decode(String.self, forKey: K(stringValue: k)!) { return v }
                    if let i = try? c.decode(Int.self, forKey: K(stringValue: k)!) {
                        if i > 1_000_000_000_000 { return String(i / 1000) }
                        return String(i)
                    }
                    if let d = try? c.decode(Double.self, forKey: K(stringValue: k)!) {
                        if d > 1_000_000_000_000 { return String(Int(d / 1000)) }
                        if d.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(d)) }
                        return String(d)
                    }
                }
                return nil
            }
            func decodeStringArray(_ keys: [String]) -> [String]? {
                for k in keys {
                    if let arr = try? c.decode([String].self, forKey: K(stringValue: k)!) { return arr }
                    if let one = try? c.decode(String.self, forKey: K(stringValue: k)!) { return [one] }
                }
                return nil
            }

            orderId = decodeString(["orderId", "order_id"]) ?? ""
            orderReference = decodeString(["orderReference", "order_reference"]) ?? ""
            previousOrderReference = decodeString(["previousOrderReference", "previous_order_reference"])
            clientName = decodeString(["clientName", "client_name"])
            clientEmail = decodeString(["clientEmail", "client_email"])
            bundleCode = decodeString(["bundleCode", "bundle_code"])
            bundleName = decodeString(["bundleName", "bundle_name"])
            bundleMarketingName = decodeString(["bundleMarketingName", "bundle_marketing_name"])
            countryCode = decodeStringArray(["countryCode", "country_code"])
            countryName = decodeStringArray(["countryName", "country_name"])
            bundleSalePrice = decodeString(["bundleSalePrice", "bundle_sale_price"])
            agentSalePrice = decodeString(["agentSalePrice", "agent_sale_price"])
            resellerRetailPrice = decodeString(["resellerRetailPrice", "reseller_retail_price"])
            currencyCode = decodeString(["currencyCode", "currency_code"])
            createdAt = decodeString(["createdAt", "created_at", "dateCreated", "date_created"])
            orderStatus = decodeString(["orderStatus", "order_status"])
            if let v = try? c.decode(Int.self, forKey: K(stringValue: "status")!) {
                status = v
            } else if let s = try? c.decode(String.self, forKey: K(stringValue: "status")!), let v = Int(s) {
                status = v
            } else {
                status = nil
            }
        }
    }

    struct OrdersListDataDTO: Decodable {
        let orders: [OrderListItemDTO]
        let ordersCount: Int
    }

    struct OrderWithUsageItemDTO: Decodable {
        let order: HTTPOrderRepository.OrderDTO
        let usage: OrderConsumptionDTO?
    }

    struct OrdersListWithUsageDataDTO: Decodable {
        let items: [OrderWithUsageItemDTO]
        let ordersCount: Int
    }

    struct OrderDetailDTO: Decodable {
        let orderId: String
        let orderReference: String?
        let iccid: String?
        let bundleCategory: String?
        let bundleCode: String?
        let bundleMarketingName: String?
        let bundleName: String?
        let countryCode: [String]?
        let countryName: [String]?
        let activationCode: String?
        let smdpAddress: String?
        let matchingId: String?
        let bundleExpiryDate: String?
        let expiryDate: String?
        let planStarted: Bool?
        let planStatus: String?
        let orderStatus: String?
        let dateCreated: String?

        enum CodingKeys: String, CodingKey {
            case orderId
            case orderReference
            case iccid
            case bundleCategory
            case bundleCode
            case bundleMarketingName
            case bundleName
            case countryCode
            case countryName
            case activationCode
            case smdpAddress
            case matchingId
            case bundleExpiryDate
            case expiryDate
            case planStarted
            case planStatus
            case orderStatus
            case dateCreated
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let s = try? c.decode(String.self, forKey: .orderId) {
                orderId = s
            } else if let i = try? c.decode(Int.self, forKey: .orderId) {
                orderId = String(i)
            } else if let d = try? c.decode(Double.self, forKey: .orderId) {
                orderId = String(Int(d))
            } else {
                orderId = ""
            }
            orderReference = try? c.decode(String.self, forKey: .orderReference)
            iccid = try? c.decode(String.self, forKey: .iccid)
            bundleCategory = try? c.decode(String.self, forKey: .bundleCategory)
            bundleCode = try? c.decode(String.self, forKey: .bundleCode)
            bundleMarketingName = try? c.decode(String.self, forKey: .bundleMarketingName)
            bundleName = try? c.decode(String.self, forKey: .bundleName)
            countryCode = try? c.decode([String].self, forKey: .countryCode)
            countryName = try? c.decode([String].self, forKey: .countryName)
            activationCode = try? c.decode(String.self, forKey: .activationCode)
            smdpAddress = try? c.decode(String.self, forKey: .smdpAddress)
            matchingId = try? c.decode(String.self, forKey: .matchingId)
            if let s = try? c.decode(String.self, forKey: .bundleExpiryDate) {
                bundleExpiryDate = s
            } else if let i = try? c.decode(Int.self, forKey: .bundleExpiryDate) {
                bundleExpiryDate = String(i)
            } else if let d = try? c.decode(Double.self, forKey: .bundleExpiryDate) {
                bundleExpiryDate = String(d)
            } else {
                bundleExpiryDate = nil
            }
            if let s = try? c.decode(String.self, forKey: .expiryDate) {
                expiryDate = s
            } else if let i = try? c.decode(Int.self, forKey: .expiryDate) {
                expiryDate = String(i)
            } else if let d = try? c.decode(Double.self, forKey: .expiryDate) {
                expiryDate = String(d)
            } else {
                expiryDate = nil
            }
            planStarted = try? c.decode(Bool.self, forKey: .planStarted)
            planStatus = try? c.decode(String.self, forKey: .planStatus)
            orderStatus = try? c.decode(String.self, forKey: .orderStatus)
            if let s = try? c.decode(String.self, forKey: .dateCreated) {
                dateCreated = s
            } else if let i = try? c.decode(Int.self, forKey: .dateCreated) {
                dateCreated = String(i)
            } else if let d = try? c.decode(Double.self, forKey: .dateCreated) {
                let v = d
                if v > 1_000_000_000_000 { dateCreated = String(Int(v / 1000)) } else { dateCreated = String(Int(v)) }
            } else {
                dateCreated = nil
            }
        }
    }

    struct OrderConsumptionDTO: Decodable {
        let bundleExpiryDate: String?
        let dataAllocated: Double?
        let dataRemaining: Double?
        let dataUnit: String?
        let dataUsed: Double?
        let iccid: String?
        let minutesAllocated: Double?
        let minutesRemaining: Double?
        let minutesUsed: Double?
        let planStatus: String?
        let policyStatus: String?
        let profileStatus: String?
        let smsAllocated: Double?
        let smsRemaining: Double?
        let smsUsed: Double?
        let supportsCallsSms: Bool?
        let unlimited: Bool?
        let profileExpiryDate: String?
    }

    struct ConsumptionDataDTO: Decodable { let order: OrderConsumptionDTO }

    struct OrdersDetailByIdBody: Encodable { let orderId: String }
    struct OrdersDetailNormalizedBody: Encodable { let orderId: String?; let orderReference: String? }
    struct OrdersConsumptionByIdBody: Encodable { let orderId: String }

    struct RefundByIdBody: Encodable { let orderId: String; let reason: String }
    struct RefundStepDTO: Decodable { let state: String; let updatedAt: String; let note: String? }
    struct RefundDataDTO: Decodable { let accepted: Bool; let state: String?; let steps: [RefundStepDTO]? }

    // MARK: - 接口方法
    func listOrders(
        pageNumber: Int,
        pageSize: Int,
        bundleCode: String? = nil,
        orderId: String? = nil,
        orderReference: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        iccid: String? = nil,
        requestId: String? = nil
    ) async throws -> (orders: [OrderListItemDTO], total: Int) {
        let body = OrdersListBody(
            pageNumber: pageNumber,
            pageSize: pageSize,
            bundleCode: bundleCode,
            orderId: orderId,
            orderReference: orderReference,
            startDate: startDate,
            endDate: endDate,
            iccid: iccid
        )
        // 单飞 key：同一筛选参数下复用在途请求，避免重复拉取
        let keyComponents: [String] = [
            "order:list",
            String(pageNumber),
            String(pageSize),
            bundleCode ?? "-",
            orderId ?? "-",
            orderReference ?? "-",
            startDate ?? "-",
            endDate ?? "-",
            iccid ?? "-"
        ]
        let key = keyComponents.joined(separator: "|")

        // 降低类型推断复杂度：让单飞闭包返回 DTO，再在外部构造结果元组
        let data: OrdersListDataDTO = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<OrdersListDataDTO> = try await service.postEnvelope("/orders/list", body: body, requestId: requestId)
            return env.data
        }
        return (orders: data.orders, total: data.ordersCount)
    }

    func listOrdersWithUsage(
        pageNumber: Int,
        pageSize: Int,
        bundleCode: String? = nil,
        orderId: String? = nil,
        orderReference: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        iccid: String? = nil,
        requestId: String? = nil
    ) async throws -> (items: [OrderWithUsageItemDTO], total: Int) {
        let body = OrdersListWithUsageBody(
            pageNumber: pageNumber,
            pageSize: pageSize,
            bundleCode: bundleCode,
            orderId: orderId,
            orderReference: orderReference,
            startDate: startDate,
            endDate: endDate,
            iccid: iccid
        )
        let keyComponents: [String] = [
            "order:list:usage",
            String(pageNumber),
            String(pageSize),
            bundleCode ?? "-",
            orderId ?? "-",
            orderReference ?? "-",
            startDate ?? "-",
            endDate ?? "-",
            iccid ?? "-"
        ]
        let key = keyComponents.joined(separator: "|")
        let data: OrdersListWithUsageDataDTO = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<OrdersListWithUsageDataDTO> = try await service.postEnvelope("/orders/list-with-usage", body: body, requestId: requestId)
            return env.data
        }
        return (items: data.items, total: data.ordersCount)
    }

    func getOrderDetail(orderReference: String, requestId: String? = nil) async throws -> OrderDetailDTO {
        struct DetailBody: Encodable { let orderReference: String }
        let key = ["order:detail", orderReference].joined(separator: "|")
        let dto: OrderDetailDTO = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<OrderDetailDTO> = try await service.postEnvelope("/orders/detail", body: DetailBody(orderReference: orderReference), requestId: requestId)
            return env.data
        }
        return dto
    }

    func getConsumption(orderReference: String, requestId: String? = nil) async throws -> OrderConsumptionDTO {
        struct ConsumptionBody: Encodable { let orderReference: String }
        let key = ["order:consumption", orderReference].joined(separator: "|")
        let dto: OrderConsumptionDTO = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<ConsumptionDataDTO> = try await service.postEnvelope("/orders/consumption", body: ConsumptionBody(orderReference: orderReference), requestId: requestId)
            return env.data.order
        }
        return dto
    }

    func getOrderDetailById(orderId: String, requestId: String? = nil) async throws -> OrderDetailDTO {
        let key = ["order:detail:id", orderId].joined(separator: "|")
        let dto: OrderDetailDTO = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<OrderDetailDTO> = try await service.postEnvelope("/orders/detail-by-id", body: OrdersDetailByIdBody(orderId: orderId), requestId: requestId)
            return env.data
        }
        return dto
    }

    func getOrderDetailNormalized(orderId: String?, orderReference: String?, requestId: String? = nil) async throws -> HTTPOrderRepository.OrderDTO {
        let key = ["order:detail:normalized", orderId ?? "-", orderReference ?? "-"].joined(separator: "|")
        let dto: HTTPOrderRepository.OrderDTO = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<HTTPOrderRepository.OrderDTO> = try await service.postEnvelope("/orders/detail-normalized", body: OrdersDetailNormalizedBody(orderId: orderId, orderReference: orderReference), requestId: requestId)
            return env.data
        }
        return dto
    }

    func getConsumptionByOrderId(orderId: String, requestId: String? = nil) async throws -> OrderConsumptionDTO {
        let key = ["order:consumption:id", orderId].joined(separator: "|")
        let dto: OrderConsumptionDTO = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<ConsumptionDataDTO> = try await service.postEnvelope("/orders/consumption-by-id", body: OrdersConsumptionByIdBody(orderId: orderId), requestId: requestId)
            return env.data.order
        }
        return dto
    }

    func initMappingsForCurrentUser(requestId: String? = nil) async throws -> (checked: Int, updated: Int) {
        struct InitResultDTO: Decodable { let checked: Int; let updated: Int }
        let key = ["order:mappings:init"].joined(separator: "|")
        let dto: InitResultDTO = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<InitResultDTO> = try await service.postEnvelope("/orders/mappings/init", body: [String: String](), requestId: requestId)
            return env.data
        }
        return (checked: dto.checked, updated: dto.updated)
    }
    func refundOrderById(orderId: String, reason: String, requestId: String? = nil) async throws -> RefundResult {
        let key = ["order:refund:id", orderId].joined(separator: "|")
        let data: RefundDataDTO = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<RefundDataDTO> = try await service.postEnvelope("/orders/refund-by-id", body: RefundByIdBody(orderId: orderId, reason: reason), requestId: requestId)
            return env.data
        }
        let mappedState: RefundState? = data.state.flatMap { RefundState(rawValue: $0) }
        let mappedSteps: [RefundProgressStep]? = data.steps?.compactMap { s in
            guard let st = RefundState(rawValue: s.state) else { return nil }
            let dt: Date = {
                if let ts = Double(s.updatedAt) { return Date(timeIntervalSince1970: ts) }
                let iso = ISO8601DateFormatter(); if let d = iso.date(from: s.updatedAt) { return d }
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f.date(from: s.updatedAt) ?? Date()
            }()
            return RefundProgressStep(state: st, updatedAt: dt, note: s.note)
        }
        return RefundResult(accepted: data.accepted, state: mappedState, progress: mappedSteps)
    }
}
