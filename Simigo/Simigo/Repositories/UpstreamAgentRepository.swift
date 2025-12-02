import Foundation

// MARK: - 上游（alias 风格）代理仓库
protocol UpstreamAgentRepositoryProtocol {
    func getAccount(requestId: String?) async throws -> HTTPUpstreamAgentRepository.AgentAccountDTO
    func listBills(
        pageNumber: Int,
        pageSize: Int,
        reference: String?,
        startDate: String?,
        endDate: String?,
        requestId: String?
    ) async throws -> HTTPUpstreamAgentRepository.AgentBillsDTO
}

struct HTTPUpstreamAgentRepository: UpstreamAgentRepositoryProtocol {
    private let service = NetworkService()
    // 将分页大小限制为上游允许的取值，避免触发 1003 错误
    func safePageSize(_ size: Int) -> Int {
        let allowed = [10, 25, 50, 100]
        return allowed.contains(size) ? size : 25
    }

    struct AgentAccountDTO: Codable {
        let agentId: String
        let username: String
        let name: String
        let balance: Double
        let revenueRate: Int
        let status: Int
        let createdAt: Int
    }

    struct AgentBillDTO: Codable {
        let billId: String
        let trade: Int
        let amount: Double
        let reference: String
        let description: String
        let createdAt: Int
    }

    struct AgentBillsDTO: Decodable {
        let bills: [AgentBillDTO]
        let billsCount: Int
    }

    struct BillsBody: Encodable {
        let pageNumber: Int
        let pageSize: Int
        let reference: String?
        let startDate: String?
        let endDate: String?
    }

    func getAccount(requestId: String? = nil) async throws -> AgentAccountDTO {
        let key = "agent:account"
        let dto: AgentAccountDTO = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<AgentAccountDTO> = try await service.postEnvelope("/agent/account", body: EmptyBody(), requestId: requestId)
            return env.data
        }
        return dto
    }

    func listBills(
        pageNumber: Int,
        pageSize: Int,
        reference: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        requestId: String? = nil
    ) async throws -> AgentBillsDTO {
        let body = BillsBody(pageNumber: pageNumber, pageSize: safePageSize(pageSize), reference: reference, startDate: startDate, endDate: endDate)
        let key = [
            "agent:bills",
            String(pageNumber),
            String(safePageSize(pageSize)),
            reference ?? "-",
            startDate ?? "-",
            endDate ?? "-"
        ].joined(separator: "|")

        let dto: AgentBillsDTO = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<AgentBillsDTO> = try await service.postEnvelope("/agent/bills", body: body, requestId: requestId)
            return env.data
        }
        return dto
    }

    private struct EmptyBody: Encodable {}
}
