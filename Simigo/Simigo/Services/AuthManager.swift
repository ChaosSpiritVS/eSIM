import Foundation

@MainActor
final class AuthManager: ObservableObject {
    @Published var currentUser: User? {
        didSet {
            if let id = currentUser?.id {
                UserDefaults.standard.set(id, forKey: "simigo.currentUserId")
                UserDefaults.standard.set(false, forKey: "simigo.useStaleCache")
                UserDefaults.standard.removeObject(forKey: "simigo.staleUserId")
            } else {
                UserDefaults.standard.removeObject(forKey: "simigo.currentUserId")
            }
        }
    }
    @Published var isRestoring: Bool = false
    @Published var restoreHint: String?
    // 删除账户后提示登录（用于弹出登录/注册弹窗）
    @Published var promptLoginAfterAccountDeletion: Bool = false

    var isLoggedIn: Bool { currentUser != nil }

    func logout() {
        let uid = currentUser?.id
        CatalogCacheStore.shared.clearAllForCurrentUser()
        currentUser = nil
        restoreHint = nil
        Task {
            await HTTPAuthRepository().logout()
            Telemetry.shared.logEvent("auth_logout", parameters: [
                "user_id": uid ?? ""
            ])
            UserDefaults.standard.set(false, forKey: "simigo.useStaleCache")
            UserDefaults.standard.removeObject(forKey: "simigo.staleUserId")
        }
    }

    /// 在应用启动时尝试从已保存的令牌恢复会话
    func restoreSession() async {
        isRestoring = true
        restoreHint = nil
        Telemetry.shared.logEvent("auth_restore_start", parameters: nil)
        let token = await TokenStore.shared.getAccessToken()
        guard token != nil else { isRestoring = false; Telemetry.shared.logEvent("auth_restore_skip", parameters: ["has_token": false]); return }
        let service = NetworkService()
        struct MeDTO: Decodable { let id: String; let name: String; let lastName: String?; let email: String?; let hasPassword: Bool }
        do {
            let me: MeDTO = try await service.get("/me")
            currentUser = User(id: me.id, name: me.name, lastName: me.lastName, email: me.email, hasPassword: me.hasPassword)
            restoreHint = nil
            Telemetry.shared.logEvent("auth_restore_success", parameters: [
                "user_id": me.id
            ])
        } catch {
            if let last = UserDefaults.standard.string(forKey: "simigo.currentUserId") {
                UserDefaults.standard.set(last, forKey: "simigo.staleUserId")
                UserDefaults.standard.set(true, forKey: "simigo.useStaleCache")
            }
            await TokenStore.shared.clear()
            currentUser = nil
            restoreHint = "登录会话已过期，请重新登录"
            Telemetry.shared.logEvent("auth_restore_failure", parameters: [
                "error": error.localizedDescription
            ])
            Telemetry.shared.record(error: error)
        }
        isRestoring = false
    }

    func handleSessionExpired(reason: String?) {
        if let last = UserDefaults.standard.string(forKey: "simigo.currentUserId") {
            UserDefaults.standard.set(last, forKey: "simigo.staleUserId")
            UserDefaults.standard.set(true, forKey: "simigo.useStaleCache")
        }
        currentUser = nil
        restoreHint = "登录会话已过期，请重新登录"
        Task { await TokenStore.shared.clear() }
        Telemetry.shared.logEvent("auth_session_expired", parameters: [
            "reason": reason ?? "-"
        ])
    }
}
