import Foundation
import AuthenticationServices

@MainActor
final class AuthViewModel: ObservableObject {
    enum Mode { case login, register }

    @Published var mode: Mode = .login
    @Published var isLoading = false
    @Published var error: String?

    // 登录表单
    @Published var email: String = ""
    @Published var password: String = ""

    // 注册表单
    @Published var name: String = ""
    @Published var lastName: String = ""
    @Published var marketingOptIn: Bool = false

    private let repository: AuthRepositoryProtocol
    private let auth: AuthManager
    private let lastEmailKey = "simigo.lastLoginEmail"

    init(auth: AuthManager, repository: AuthRepositoryProtocol? = nil) {
        self.auth = auth
        self.repository = repository ?? (AppConfig.isMock ? MockAuthRepository() : HTTPAuthRepository())
        // 预填上次登录邮箱，减少重复输入
        if let cached = UserDefaults.standard.string(forKey: lastEmailKey) {
            self.email = cached
        }
    }

    // MARK: - 表单校验（登录/注册通用）
    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", pattern)
        return predicate.evaluate(with: trimmed)
    }

    var loginEmailError: String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return isValidEmail(trimmed) ? nil : loc("请输入有效的电子邮件地址。")
    }

    var loginPasswordError: String? {
        guard !password.isEmpty else { return nil }
        return password.count >= 8 ? nil : loc("请输入至少包含 8 个字符的密码。")
    }

    var registerNameError: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count >= 2 ? nil : loc("请填写至少 2 个字符的名字。")
    }

    var registerEmailError: String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return isValidEmail(trimmed) ? nil : loc("请输入有效的电子邮件地址。")
    }

    var registerPasswordError: String? {
        guard !password.isEmpty else { return nil }
        return password.count >= 8 ? nil : loc("请输入至少包含 8 个字符的密码。")
    }

    var isLoginFormValid: Bool {
        isValidEmail(email) && password.count >= 8
    }

    var isRegisterFormValid: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        isValidEmail(email) && registerPasswordMeetsAllRules
    }

    // MARK: - 注册密码规则
    var passwordHasUppercase: Bool { password.rangeOfCharacter(from: .uppercaseLetters) != nil }
    var passwordHasLowercase: Bool { password.rangeOfCharacter(from: .lowercaseLetters) != nil }
    var passwordHasDigit: Bool { password.rangeOfCharacter(from: .decimalDigits) != nil }
    private var symbolSet: CharacterSet { CharacterSet(charactersIn: "+-*/?:=!%$#") }
    var passwordHasSymbol: Bool { password.rangeOfCharacter(from: symbolSet) != nil }
    var registerPasswordMeetsAllRules: Bool {
        password.count >= 8 && passwordHasUppercase && passwordHasLowercase && passwordHasDigit && passwordHasSymbol
    }

    func loginWithEmail() {
        guard !email.isEmpty, !password.isEmpty else { error = loc("请输入电子邮件与密码"); return }
        isLoading = true
        error = nil
        Task { [email, password] in
            do {
                let user = try await repository.login(email: email, password: password)
                auth.currentUser = user
                UserDefaults.standard.set(email, forKey: lastEmailKey)
                Telemetry.shared.logEvent("auth_login_success", parameters: [
                    "method": "email",
                    "email": email
                ])
            } catch {
                self.error = error.localizedDescription
                Telemetry.shared.logEvent("auth_login_failure", parameters: [
                    "method": "email",
                    "email": email,
                    "error": error.localizedDescription
                ])
                Telemetry.shared.record(error: error)
            }
            isLoading = false
        }
    }

    func registerWithEmail() {
        guard !name.isEmpty, !email.isEmpty, !password.isEmpty else { error = loc("请填写必填项"); return }
        isLoading = true
        error = nil
        let last = lastName.isEmpty ? nil : lastName
        Task { [name, last, email, password, marketingOptIn] in
            do {
                let user = try await repository.register(name: name, lastName: last, email: email, password: password, marketingOptIn: marketingOptIn, verificationCode: nil)
                auth.currentUser = user
                UserDefaults.standard.set(email, forKey: lastEmailKey)
                Telemetry.shared.logEvent("auth_register_success", parameters: [
                    "method": "email",
                    "email": email
                ])
            } catch {
                self.error = error.localizedDescription
                Telemetry.shared.logEvent("auth_register_failure", parameters: [
                    "method": "email",
                    "email": email,
                    "error": error.localizedDescription
                ])
                Telemetry.shared.record(error: error)
            }
            isLoading = false
        }
    }

    func loginWithApple(_ credential: ASAuthorizationAppleIDCredential) {
        isLoading = true
        error = nil
        Task {
            do {
                let user = try await repository.loginApple(userId: credential.user, identityToken: credential.identityToken)
                auth.currentUser = user
                Telemetry.shared.logEvent("auth_login_success", parameters: [
                    "method": "apple"
                ])
            } catch {
                self.error = error.localizedDescription
                Telemetry.shared.logEvent("auth_login_failure", parameters: [
                    "method": "apple",
                    "error": error.localizedDescription
                ])
                Telemetry.shared.record(error: error)
            }
            isLoading = false
        }
    }

    /// 开发流程模拟：在模拟器或后端未配置 Apple Sign In 时使用
    func loginWithAppleDev() {
        isLoading = true
        error = nil
        Task {
            do {
                let user = try await repository.loginApple(userId: "dev-" + UUID().uuidString, identityToken: nil)
                auth.currentUser = user
                Telemetry.shared.logEvent("auth_login_success", parameters: [
                    "method": "apple_dev"
                ])
            } catch {
                self.error = error.localizedDescription
                Telemetry.shared.logEvent("auth_login_failure", parameters: [
                    "method": "apple_dev",
                    "error": error.localizedDescription
                ])
                Telemetry.shared.record(error: error)
            }
            isLoading = false
        }
    }
}
