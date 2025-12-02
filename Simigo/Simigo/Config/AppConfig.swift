import Foundation

/// 全局配置（后续可切换到不同环境）
struct AppConfig {
    /// 后端基础地址（请替换为你的后端）
    static let baseURL: URL = {
        if let s = ProcessInfo.processInfo.environment["SIMIGO_BASE_URL"], let u = URL(string: s) {
            return u
        }
        return URL(string: "http://127.0.0.1:3001")!
    }()
    /// 是否使用Mock仓库（后端就绪后改为false）
    static let isMock = false
    /// 是否启用别名（Upstream）API 模式（启用后请确保 baseURL 指向别名服务端，例如 http://127.0.0.1:8000）
    static let useAliasAPI = true
    private static var ttlOverrides: [String: TimeInterval] = [:]
    private static func ttl(_ key: String, _ def: TimeInterval) -> TimeInterval { ttlOverrides[key] ?? def }
    static var catalogCacheTTL: TimeInterval { ttl("catalogCacheTTL", 3600) }
    static var ordersCacheTTL: TimeInterval { ttl("ordersCacheTTL", 900) }
    static var orderDetailCacheTTL: TimeInterval { ttl("orderDetailCacheTTL", 900) }
    static var agentAccountCacheTTL: TimeInterval { ttl("agentAccountCacheTTL", 600) }
    static var agentBillsCacheTTL: TimeInterval { ttl("agentBillsCacheTTL", 600) }
    static var bundleNetworksCacheTTL: TimeInterval { ttl("bundleNetworksCacheTTL", 86400) }
    static var settingsCacheTTL: TimeInterval { ttl("settingsCacheTTL", 86400) }
    static var searchSuggestionsCacheTTL: TimeInterval { ttl("searchSuggestionsCacheTTL", 300) }
    static var orderUsageCacheTTL: TimeInterval { ttlOverrides["orderUsageCacheTTL"] ?? (isMock ? 15 : 60) }
    /// 是否开启 RequestCenter 的轻量日志（singleFlight 命中/取消）
    static let requestCenterLogEnabled: Bool = false
    static let enableTelemetry: Bool = true
    static let enableAnalytics: Bool = true
    static let enableCrashlytics: Bool = true
    static let paymentPollIntervalSeconds: Int = 2
    static let paymentPollTimeoutSeconds: Int = 180

    private struct RemoteConfigDTO: Decodable {
        let catalogCacheTTL: Double?
        let ordersCacheTTL: Double?
        let orderDetailCacheTTL: Double?
        let agentAccountCacheTTL: Double?
        let agentBillsCacheTTL: Double?
        let bundleNetworksCacheTTL: Double?
        let settingsCacheTTL: Double?
        let searchSuggestionsCacheTTL: Double?
        let orderUsageCacheTTL: Double?
        let bannerEnabled: Bool?
        let bannerErrorDismiss: Double?
        let bannerSuccessDismiss: Double?
        let bannerWarningDismiss: Double?
        let bannerInfoDismiss: Double?
    }

    private static var bannerEnabledCache: Bool = true
    private static var bannerDismissOverrides: [String: TimeInterval] = [:]
    static var bannersEnabled: Bool { bannerEnabledCache }
    static func bannerDefaultDismiss(for style: BannerStyle) -> TimeInterval? {
        switch style {
        case .error: return bannerDismissOverrides["bannerErrorDismiss"] ?? 5
        case .success: return bannerDismissOverrides["bannerSuccessDismiss"] ?? 3
        case .warning: return bannerDismissOverrides["bannerWarningDismiss"] ?? 4
        case .info: return bannerDismissOverrides["bannerInfoDismiss"] ?? 4
        }
    }

    static func loadRemoteConfig() async {
        let service = NetworkService()
        do {
            let dto: RemoteConfigDTO = try await service.get("/config")
            var map: [String: TimeInterval] = [:]
            if let v = dto.catalogCacheTTL { map["catalogCacheTTL"] = v }
            if let v = dto.ordersCacheTTL { map["ordersCacheTTL"] = v }
            if let v = dto.orderDetailCacheTTL { map["orderDetailCacheTTL"] = v }
            if let v = dto.agentAccountCacheTTL { map["agentAccountCacheTTL"] = v }
            if let v = dto.agentBillsCacheTTL { map["agentBillsCacheTTL"] = v }
            if let v = dto.bundleNetworksCacheTTL { map["bundleNetworksCacheTTL"] = v }
            if let v = dto.settingsCacheTTL { map["settingsCacheTTL"] = v }
            if let v = dto.searchSuggestionsCacheTTL { map["searchSuggestionsCacheTTL"] = v }
            if let v = dto.orderUsageCacheTTL { map["orderUsageCacheTTL"] = v }
            ttlOverrides = map

            if let enabled = dto.bannerEnabled { bannerEnabledCache = enabled }
            var bmap: [String: TimeInterval] = [:]
            if let v = dto.bannerErrorDismiss { bmap["bannerErrorDismiss"] = v }
            if let v = dto.bannerSuccessDismiss { bmap["bannerSuccessDismiss"] = v }
            if let v = dto.bannerWarningDismiss { bmap["bannerWarningDismiss"] = v }
            if let v = dto.bannerInfoDismiss { bmap["bannerInfoDismiss"] = v }
            bannerDismissOverrides = bmap
        } catch {
        }
    }
}
