import Foundation

enum NetworkError: Error {
    case invalidURL
    case badStatus(Int)
    case decoding(Error)
    case server(Int, String)
    case offline
}

// 为 UI 提供更友好的错误描述
extension NetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "请求地址无效"
        case .badStatus(let code):
            return "服务器返回错误（\(code)）"
        case .decoding(let err):
            return "数据解析失败：\(err.localizedDescription)"
        case .server(_, let message):
            return message
        case .offline:
            return "当前无网络连接"
        }
    }
}

/// 轻量网络服务（GET示例），后续可扩展POST/PUT与授权头
actor NetworkService {
    private let tokenStore = TokenStore.shared

    func get<T: Decodable>(_ path: String, query: [String: String]? = nil) async throws -> T {
        // 离线 fail-fast：直接返回可本地化的错误，避免不必要等待；同时触发一次轻量连通性探针以加速状态恢复
        if !NetworkMonitor.shared.isOnline {
            NetworkMonitor.shared.probeConnectivity()
            throw NetworkError.offline
        }

        var components = URLComponents(url: AppConfig.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if let query = query { components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components?.url else { throw NetworkError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 自动注入 Request-Id，便于后端与日志追踪
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "Request-Id")
        // 统一携带语言头（由服务端进行规范化与白名单约束）
        let lang = UserDefaults.standard.string(forKey: "simigo.languageCode") ?? Locale.preferredLanguages.first ?? "en"
        request.setValue(lang, forHTTPHeaderField: "X-Language")
        if let token = await tokenStore.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // GET：一次轻量自动重试（幂等且仅在网络在线时）
        var attempt = 0
        let perform: @Sendable () async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: request)
        }
        var (data, response): (Data, URLResponse)
        do {
            (data, response) = try await perform()
        } catch {
            // 若仍在线且为瞬时网络错误，最多重试一次
            if attempt == 0, NetworkMonitor.shared.isOnline, let urlErr = error as? URLError {
                let transientCodes: [URLError.Code] = [.networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed]
                if transientCodes.contains(urlErr.code) {
                    attempt = 1
                    try await Task.sleep(nanoseconds: 400_000_000)
                    (data, response) = try await perform()
                } else {
                    NetworkMonitor.shared.reportBackendReachable(false)
                    throw error
                }
            } else {
                // 离线或非瞬时错误直接抛出
                if !NetworkMonitor.shared.isOnline { throw NetworkError.offline }
                NetworkMonitor.shared.reportBackendReachable(false)
                throw error
            }
        }
        var status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, await attemptRefresh() {
            if let token = await tokenStore.getAccessToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            (data, response) = try await URLSession.shared.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        }
        if !(200..<300).contains(status) {
            if status >= 500 { NetworkMonitor.shared.reportBackendReachable(false) }
            if status == 401 { AuthEventBridge.sessionExpired(reason: NetworkService.extractServerMessage(from: data) ?? "401") }
            if let msg = NetworkService.extractServerMessage(from: data) {
                throw NetworkError.server(status, msg)
            }
            throw NetworkError.badStatus(status)
        }
        NetworkMonitor.shared.reportBackendReachable(true)
        do {
            let decoder = NetworkService.makeDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decoding(error)
        }
    }

    func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        // 离线 fail-fast：写操作或需要服务端参与的流程在离线时直接失败；触发轻量探针
        if !NetworkMonitor.shared.isOnline {
            NetworkMonitor.shared.probeConnectivity()
            throw NetworkError.offline
        }

        let url = AppConfig.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)
        // 自动注入 Request-Id，便于后端与日志追踪
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "Request-Id")
        // 统一携带语言头（由服务端进行规范化与白名单约束）
        let lang = UserDefaults.standard.string(forKey: "simigo.languageCode") ?? Locale.preferredLanguages.first ?? "en"
        request.setValue(lang, forHTTPHeaderField: "X-Language")
        if let token = await tokenStore.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var (data, response) = try await URLSession.shared.data(for: request)
        var status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, await attemptRefresh() {
            if let token = await tokenStore.getAccessToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            (data, response) = try await URLSession.shared.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        }
        if !(200..<300).contains(status) {
            if status >= 500 { NetworkMonitor.shared.reportBackendReachable(false) }
            if status == 401 { AuthEventBridge.sessionExpired(reason: NetworkService.extractServerMessage(from: data) ?? "401") }
            if let msg = NetworkService.extractServerMessage(from: data) {
                throw NetworkError.server(status, msg)
            }
            throw NetworkError.badStatus(status)
        }
        NetworkMonitor.shared.reportBackendReachable(true)
        let decoder = NetworkService.makeDecoder()
        return try decoder.decode(T.self, from: data)
    }

    func put<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        if !NetworkMonitor.shared.isOnline {
            NetworkMonitor.shared.probeConnectivity()
            throw NetworkError.offline
        }
        let url = AppConfig.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)
        // 自动注入 Request-Id，便于后端与日志追踪
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "Request-Id")
        // 统一携带语言头（由服务端进行规范化与白名单约束）
        let lang = UserDefaults.standard.string(forKey: "simigo.languageCode") ?? Locale.preferredLanguages.first ?? "en"
        request.setValue(lang, forHTTPHeaderField: "X-Language")
        if let token = await tokenStore.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var (data, response) = try await URLSession.shared.data(for: request)
        var status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, await attemptRefresh() {
            if let token = await tokenStore.getAccessToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            (data, response) = try await URLSession.shared.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        }
        if !(200..<300).contains(status) {
            if status >= 500 { NetworkMonitor.shared.reportBackendReachable(false) }
            if status == 401 { AuthEventBridge.sessionExpired(reason: NetworkService.extractServerMessage(from: data) ?? "401") }
            if let msg = NetworkService.extractServerMessage(from: data) {
                throw NetworkError.server(status, msg)
            }
            throw NetworkError.badStatus(status)
        }
        NetworkMonitor.shared.reportBackendReachable(true)
        let decoder = NetworkService.makeDecoder()
        return try decoder.decode(T.self, from: data)
    }

    func delete(_ path: String) async throws {
        if !NetworkMonitor.shared.isOnline {
            NetworkMonitor.shared.probeConnectivity()
            throw NetworkError.offline
        }
        let url = AppConfig.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "Request-Id")
        // 统一携带语言头（由服务端进行规范化与白名单约束）
        let lang = UserDefaults.standard.string(forKey: "simigo.languageCode") ?? Locale.preferredLanguages.first ?? "en"
        request.setValue(lang, forHTTPHeaderField: "X-Language")
        if let token = await tokenStore.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var (data, response) = try await URLSession.shared.data(for: request)
        var status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, await attemptRefresh() {
            if let token = await tokenStore.getAccessToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            (data, response) = try await URLSession.shared.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        }
        if !(200..<300).contains(status) {
            if status >= 500 { NetworkMonitor.shared.reportBackendReachable(false) }
            if status == 401 { AuthEventBridge.sessionExpired(reason: NetworkService.extractServerMessage(from: data) ?? "401") }
            if let msg = NetworkService.extractServerMessage(from: data) {
                throw NetworkError.server(status, msg)
            }
            throw NetworkError.badStatus(status)
        }
        NetworkMonitor.shared.reportBackendReachable(true)
    }

    func delete<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        if !NetworkMonitor.shared.isOnline {
            NetworkMonitor.shared.probeConnectivity()
            throw NetworkError.offline
        }
        let url = AppConfig.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)
        // 自动注入 Request-Id，便于后端与日志追踪
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "Request-Id")
        // 统一携带语言头（由服务端进行规范化与白名单约束）
        let lang = UserDefaults.standard.string(forKey: "simigo.languageCode") ?? Locale.preferredLanguages.first ?? "en"
        request.setValue(lang, forHTTPHeaderField: "X-Language")
        if let token = await tokenStore.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var (data, response) = try await URLSession.shared.data(for: request)
        var status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, await attemptRefresh() {
            if let token = await tokenStore.getAccessToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            (data, response) = try await URLSession.shared.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        }
        if !(200..<300).contains(status) {
            if status >= 500 { NetworkMonitor.shared.reportBackendReachable(false) }
            if status == 401 { AuthEventBridge.sessionExpired(reason: NetworkService.extractServerMessage(from: data) ?? "401") }
            if let msg = NetworkService.extractServerMessage(from: data) {
                throw NetworkError.server(status, msg)
            }
            throw NetworkError.badStatus(status)
        }
        NetworkMonitor.shared.reportBackendReachable(true)
        let decoder = NetworkService.makeDecoder()
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - 刷新令牌助手
    private func attemptRefresh() async -> Bool {
        guard let refresh = await tokenStore.getRefreshToken() else { return false }
        struct RefreshBody: Encodable { let refreshToken: String }
        struct AuthResponseDTO: Decodable { let user: UserDTO; let accessToken: String; let refreshToken: String }
        struct UserDTO: Decodable { let id: String; let name: String; let lastName: String?; let email: String? }
        do {
            let url = AppConfig.baseURL.appendingPathComponent("/auth/refresh")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let enc = JSONEncoder()
            enc.keyEncodingStrategy = .useDefaultKeys
            req.httpBody = try enc.encode(RefreshBody(refreshToken: refresh))
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { return false }
            let dec = JSONDecoder()
            dec.keyDecodingStrategy = .convertFromSnakeCase
            let dto = try dec.decode(AuthResponseDTO.self, from: data)
            await tokenStore.setTokens(access: dto.accessToken, refresh: dto.refreshToken)
            return true
        } catch {
            return false
        }
    }

    // MARK: - 错误信息提取
    private static func extractServerMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let s = obj["detail"] as? String { return s }
            if let s = obj["message"] as? String { return s }
            if let s = obj["error"] as? String { return s }
        }
        return nil
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            if let s = try? c.decode(String.self) {
                let isoFs = ISO8601DateFormatter()
                isoFs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d0 = isoFs.date(from: s) { return d0 }
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime]
                if let d1 = iso.date(from: s) { return d1 }
                // Naive ISO8601 without timezone
                let posix = Locale(identifier: "en_US_POSIX")
                let tzUTC = TimeZone(secondsFromGMT: 0)
                let tryFmt: (String) -> Date? = { df in
                    let fmt = DateFormatter()
                    fmt.locale = posix
                    fmt.timeZone = tzUTC
                    fmt.dateFormat = df
                    return fmt.date(from: s)
                }
                if let d2 = tryFmt("yyyy-MM-dd'T'HH:mm:ss.SSSSSS") { return d2 }
                if let d3 = tryFmt("yyyy-MM-dd'T'HH:mm:ss.SSS") { return d3 }
                if let d4 = tryFmt("yyyy-MM-dd'T'HH:mm:ss") { return d4 }
                if let d5 = tryFmt("yyyy-MM-dd HH:mm:ss") { return d5 }
                // Custom text format
                do {
                    let fmt = DateFormatter()
                    fmt.locale = posix
                    fmt.timeZone = tzUTC
                    fmt.dateFormat = "MMM dd, yyyy 'at' HH:mm:ss"
                    if let d6 = fmt.date(from: s) { return d6 }
                }
                if let ts = Double(s) {
                    return Date(timeIntervalSince1970: ts > 1_000_000_000_000 ? ts / 1000.0 : ts)
                }
            }
            if let i = try? c.decode(Double.self) {
                return Date(timeIntervalSince1970: i > 1_000_000_000_000 ? i / 1000.0 : i)
            }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date")
        }
        return d
    }
}

// MARK: - 别名风格 Envelope 支持
/// 别名风格响应包裹类型：
/// - `code`：业务状态码（非 HTTP 状态码）
/// - `data`：实际业务数据
/// - `msg`：文本提示或错误信息
public struct Envelope<T: Decodable>: Decodable {
    public let code: Int
    public let data: T
    public let msg: String
}

// 仅解析头部（code/msg），用于在错误场景先读 meta 再决定是否解 data
struct EnvelopeMeta: Decodable {
    let code: Int
    let msg: String
}

extension NetworkService {
    /// 别名风格 Envelope 的 POST 辅助方法：若未显式传入 `Request-Id`，则自动生成并注入该请求头。
    func postEnvelope<T: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        requestId: String? = nil
    ) async throws -> Envelope<T> {
        // 别名接口同样在离线时快速失败
        if !NetworkMonitor.shared.isOnline { throw NetworkError.offline }

        let url = AppConfig.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)

        let rid = requestId ?? UUID().uuidString.lowercased()
        request.setValue(rid, forHTTPHeaderField: "Request-Id")
        // 统一携带语言头（由服务端进行规范化与白名单约束）
        let lang = UserDefaults.standard.string(forKey: "simigo.languageCode") ?? Locale.preferredLanguages.first ?? "en"
        request.setValue(lang, forHTTPHeaderField: "X-Language")

        if let token = await tokenStore.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        #if DEBUG
        if let hb = request.httpBody, let hbStr = String(data: hb, encoding: .utf8) {
            print("[HTTP-REQ] method=POST path=\(path) body=\(hbStr)")
        } else {
            print("[HTTP-REQ] method=POST path=\(path) body=<empty>")
        }
        #endif

        var (data, response) = try await URLSession.shared.data(for: request)
        var status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, await attemptRefresh() {
            if let token = await tokenStore.getAccessToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            (data, response) = try await URLSession.shared.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        }
        if !(200..<300).contains(status) {
            if status >= 500 { NetworkMonitor.shared.reportBackendReachable(false) }
            if status == 401 { AuthEventBridge.sessionExpired(reason: NetworkService.extractServerMessage(from: data) ?? "401") }
            if let msg = NetworkService.extractServerMessage(from: data) {
                throw NetworkError.server(status, msg)
            }
            throw NetworkError.badStatus(status)
        }
        NetworkMonitor.shared.reportBackendReachable(true)

        #if DEBUG
        if let respStr = String(data: data, encoding: .utf8) {
            print("[HTTP-RESP] method=POST path=\(path) body=\(respStr)")
        } else {
            print("[HTTP-RESP] method=POST path=\(path) body=<non-utf8 \(data.count) bytes>")
        }
        #endif

        let decoder = NetworkService.makeDecoder()
        let meta = try decoder.decode(EnvelopeMeta.self, from: data)
        if meta.code != 200 {
            NetworkMonitor.shared.reportBackendReachable(meta.code < 500)
            throw NetworkError.server(meta.code, meta.msg)
        }
        // Detect embedded alias errors inside `data` (e.g., {"err_code":1003,"err_msg":"..."})
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let d = obj["data"] as? [String: Any] {
            if let ecode = d["err_code"] as? Int, ecode != 0 {
                let msg = (d["err_msg"] as? String) ?? meta.msg
                throw NetworkError.server(ecode, msg)
            }
            if let ecodeStr = d["err_code"] as? String, let ecodeInt = Int(ecodeStr), ecodeInt != 0 {
                let msg = (d["err_msg"] as? String) ?? meta.msg
                throw NetworkError.server(ecodeInt, msg)
            }
        }
        do {
            let env = try decoder.decode(Envelope<T>.self, from: data)
            return env
        } catch {
            throw NetworkError.decoding(error)
        }
    }
}
