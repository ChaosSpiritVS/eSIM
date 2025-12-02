import Foundation

/// 全局请求中心：提供单飞（single-flight）去重与取消能力。
/// - 适用于列表与详情等幂等读取请求；按 key 去重同一时间段内的重复调用。
/// - 与 Swift Concurrency 任务取消协作，避免快速切换下的旧结果覆盖。
actor RequestCenter {
    static let shared = RequestCenter()

    // 以字符串 key 管理在途任务；使用 Any 进行类型擦除以支持泛型返回。
    private var inflight: [String: Task<Any, Error>] = [:]
    private var logEnabled: Bool { AppConfig.requestCenterLogEnabled }

    /// 执行单飞：同一 key 下复用在途任务；否则启动新任务。
    func singleFlight<T>(key: String, work: @Sendable @escaping () async throws -> T) async throws -> T {
        if let existing = inflight[key] {
            if logEnabled { print("[RequestCenter] hit singleFlight key=\(key)") }
            let any = try await existing.value
            if let typed = any as? T { return typed }
            // 类型不匹配时丢弃旧任务结果，启动新任务
            inflight[key] = nil
        }
        // 离线场景快速失败，避免创建新在途任务
        if !NetworkMonitor.shared.isOnline {
            if logEnabled { print("[RequestCenter] offline fast-fail key=\(key)") }
            throw NetworkError.offline
        }
        if logEnabled { print("[RequestCenter] start singleFlight key=\(key)") }
        let task = Task<Any, Error> { try await work() }
        inflight[key] = task
        do {
            let any = try await task.value
            inflight[key] = nil
            if logEnabled { print("[RequestCenter] done singleFlight key=\(key)") }
            guard let typed = any as? T else {
                throw NSError(domain: "request.center", code: -1, userInfo: [NSLocalizedDescriptionKey: "RequestCenter 类型不匹配"])
            }
            return typed
        } catch {
            inflight[key] = nil
            if logEnabled { print("[RequestCenter] error singleFlight key=\(key) err=\(error)") }
            throw error
        }
    }

    /// 取消指定 key 的在途任务（若存在）。
    func cancel(key: String) {
        if let t = inflight[key] {
            if logEnabled { print("[RequestCenter] cancel key=\(key)") }
            t.cancel()
            inflight[key] = nil
        }
    }

    /// 取消所有在途任务。
    func cancelAll() {
        if logEnabled { print("[RequestCenter] cancelAll count=\(inflight.count)") }
        for (_, t) in inflight { t.cancel() }
        inflight.removeAll()
    }
}