import Foundation
import Network
import Combine

final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "NetworkMonitor.queue")

    @Published private(set) var isOnline: Bool = true
    @Published private(set) var isExpensive: Bool = false
    @Published private(set) var isConstrained: Bool = false
    @Published private(set) var interfaceType: String = "unknown"
    @Published private(set) var backendOnline: Bool = true

    private var isStarted = false
    private var lastProbeAt: Date = .distantPast
    private var lastBackendProbeAt: Date = .distantPast

    private init() {
        monitor = NWPathMonitor()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            let iface: String = {
                if path.usesInterfaceType(.wifi) { return "wifi" }
                if path.usesInterfaceType(.cellular) { return "cellular" }
                if path.usesInterfaceType(.wiredEthernet) { return "ethernet" }
                if path.usesInterfaceType(.loopback) { return "loopback" }
                if path.usesInterfaceType(.other) { return "other" }
                return "unknown"
            }()

            DispatchQueue.main.async {
                self.isOnline = online
                self.isExpensive = expensive
                self.isConstrained = constrained
                self.interfaceType = iface
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        monitor.cancel()
    }

    // 连接性探针：用于在模拟器或某些网络场景下，解决 NWPathMonitor 不能及时感知“重新连上网络”的问题。
    // 通过访问轻量 204 页面来确认外网可达，并在主线程更新 isOnline。
    // 为避免频繁请求，这里加入 1 秒节流。
    func probeConnectivity(url: URL = URL(string: "https://www.gstatic.com/generate_204")!, timeout: TimeInterval = 3) {
        let now = Date()
        guard now.timeIntervalSince(lastProbeAt) > 1 else { return }
        lastProbeAt = now
        Task {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let reachable = status == 204 || (200..<400).contains(status)
                await MainActor.run { self.isOnline = reachable }
            } catch {
                await MainActor.run { self.isOnline = false }
            }
        }
    }

    func reportBackendReachable(_ reachable: Bool) {
        DispatchQueue.main.async { self.backendOnline = reachable }
    }

    func probeBackend(timeout: TimeInterval = 3) {
        let now = Date()
        guard now.timeIntervalSince(lastBackendProbeAt) > 1 else { return }
        lastBackendProbeAt = now
        Task {
            let url = AppConfig.baseURL.appendingPathComponent("health")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            do {
                let (_, _) = try await URLSession.shared.data(for: request)
                await MainActor.run { self.backendOnline = true }
            } catch {
                await MainActor.run { self.backendOnline = false }
            }
        }
    }
}
