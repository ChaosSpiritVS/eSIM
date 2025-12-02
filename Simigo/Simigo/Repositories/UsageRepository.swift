import Foundation

protocol OrderUsageRepositoryProtocol {
    func fetchUsage(orderId: String) async throws -> OrderUsage
}

struct MockOrderUsageRepository: OrderUsageRepositoryProtocol {
    func fetchUsage(orderId: String) async throws -> OrderUsage {
        try await Task.sleep(nanoseconds: 200_000_000)
        return OrderUsage(
            remainingMB: 512,
            expiresAt: Date().addingTimeInterval(9 * 24 * 3600),
            lastUpdated: Date()
        )
    }
}

struct HTTPOrderUsageRepository: OrderUsageRepositoryProtocol {
    let service = NetworkService()

    struct UsageDTO: Decodable {
        let remainingMb: Double
        let expiresAt: Date?
        let lastUpdated: Date?
    }

    func fetchUsage(orderId: String) async throws -> OrderUsage {
        let key = ["usage:order", orderId].joined(separator: "|")
        let usage: OrderUsage = try await RequestCenter.shared.singleFlight(key: key) {
            let dto: UsageDTO = try await service.get("/orders/\(orderId)/usage")
            return OrderUsage(
                remainingMB: dto.remainingMb,
                expiresAt: dto.expiresAt,
                lastUpdated: dto.lastUpdated ?? Date()
            )
        }
        return usage
    }
}