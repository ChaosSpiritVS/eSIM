import Foundation

// 调用忘记密码请求的统一结果（包含 Debug 下的令牌）
struct PasswordResetResult {
    let success: Bool
    let devToken: String?
}

protocol AuthRepositoryProtocol {
    func login(email: String, password: String) async throws -> User
    func register(name: String, lastName: String?, email: String, password: String, marketingOptIn: Bool, verificationCode: String?) async throws -> User
    func loginApple(userId: String, identityToken: Data?) async throws -> User
    func requestPasswordReset(email: String) async throws -> PasswordResetResult
    func confirmPasswordReset(token: String, newPassword: String) async throws -> Bool
    func requestEmailCode(email: String, purpose: String) async throws -> String?
}

struct MockAuthRepository: AuthRepositoryProtocol {
    /// 生成一个与 Apple 私有邮箱风格相同的地址（仅用于开发/Mock）
    /// local-part 取 10 个字符，字母数字混合，域为 privaterelay.appleid.com
    private func makeRelayEmail(for userId: String) -> String {
        var local = userId.replacingOccurrences(of: "-", with: "").lowercased()
        if local.count < 10 {
            local += UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        local = String(local.prefix(10))
        return "\(local)@privaterelay.appleid.com"
    }

    func login(email: String, password: String) async throws -> User {
        try await Task.sleep(nanoseconds: 200_000_000)
        return User(id: UUID().uuidString, name: email.components(separatedBy: "@").first ?? "用户", lastName: nil, email: email, hasPassword: true, kycStatus: nil, kycProvider: nil, kycReference: nil, kycVerifiedAt: nil)
    }

    func register(name: String, lastName: String?, email: String, password: String, marketingOptIn: Bool, verificationCode: String?) async throws -> User {
        try await Task.sleep(nanoseconds: 250_000_000)
        return User(id: UUID().uuidString, name: name, lastName: lastName, email: email, hasPassword: true, kycStatus: nil, kycProvider: nil, kycReference: nil, kycVerifiedAt: nil)
    }

    func loginApple(userId: String, identityToken: Data?) async throws -> User {
        try await Task.sleep(nanoseconds: 200_000_000)
        // 在开发模式下模拟 Apple 私有邮箱地址，便于端到端测试
        let relayEmail = makeRelayEmail(for: userId)
        return User(id: userId, name: "Apple 用户", lastName: nil, email: relayEmail, hasPassword: false, kycStatus: nil, kycProvider: nil, kycReference: nil, kycVerifiedAt: nil)
    }

    func requestPasswordReset(email: String) async throws -> PasswordResetResult {
        try await Task.sleep(nanoseconds: 200_000_000)
        return PasswordResetResult(success: true, devToken: nil)
    }

    func confirmPasswordReset(token: String, newPassword: String) async throws -> Bool {
        try await Task.sleep(nanoseconds: 200_000_000)
        return newPassword.count >= 8
    }

    func requestEmailCode(email: String, purpose: String) async throws -> String? {
        try await Task.sleep(nanoseconds: 150_000_000)
        return nil
    }
}

struct HTTPAuthRepository: AuthRepositoryProtocol {
    let service = NetworkService()
    let tokenStore = TokenStore.shared

    struct LoginBody: Encodable { let email: String; let password: String }
    struct RegisterBody: Encodable { let name: String; let lastName: String?; let email: String; let password: String; let marketingOptIn: Bool; let verificationCode: String? }
    struct AppleBody: Encodable { let userId: String; let identityToken: String? }
    struct UserDTO: Decodable {
        let id: String
        let name: String
        let lastName: String?
        let email: String?
        let hasPassword: Bool
        let kycStatus: String?
        let kycProvider: String?
        let kycReference: String?
        let kycVerifiedAt: Date?
    }
    struct AuthResponseDTO: Decodable { let user: UserDTO; let accessToken: String; let refreshToken: String }
    struct ResetBody: Encodable { let email: String }
    struct ResetDTO: Codable { let success: Bool?; let devToken: String? }
    struct ConfirmResetBody: Encodable { let token: String; let newPassword: String }
    struct SuccessDTO: Decodable { let success: Bool? }
    struct EmailCodeRequestBody: Encodable { let email: String; let purpose: String }
    struct EmailCodeDTO: Decodable { let success: Bool?; let devCode: String? }

    func login(email: String, password: String) async throws -> User {
        if AppConfig.isMock { return try await MockAuthRepository().login(email: email, password: password) }
        let dto: AuthResponseDTO = try await service.post("/auth/login", body: LoginBody(email: email, password: password))
        await tokenStore.setTokens(access: dto.accessToken, refresh: dto.refreshToken)
        return User(id: dto.user.id, name: dto.user.name, lastName: dto.user.lastName, email: dto.user.email, hasPassword: dto.user.hasPassword, kycStatus: dto.user.kycStatus, kycProvider: dto.user.kycProvider, kycReference: dto.user.kycReference, kycVerifiedAt: dto.user.kycVerifiedAt)
    }

    func register(name: String, lastName: String?, email: String, password: String, marketingOptIn: Bool, verificationCode: String?) async throws -> User {
        if AppConfig.isMock { return try await MockAuthRepository().register(name: name, lastName: lastName, email: email, password: password, marketingOptIn: marketingOptIn, verificationCode: verificationCode) }
        let dto: AuthResponseDTO = try await service.post("/auth/register", body: RegisterBody(name: name, lastName: lastName, email: email, password: password, marketingOptIn: marketingOptIn, verificationCode: verificationCode))
        await tokenStore.setTokens(access: dto.accessToken, refresh: dto.refreshToken)
        return User(id: dto.user.id, name: dto.user.name, lastName: dto.user.lastName, email: dto.user.email, hasPassword: dto.user.hasPassword, kycStatus: dto.user.kycStatus, kycProvider: dto.user.kycProvider, kycReference: dto.user.kycReference, kycVerifiedAt: dto.user.kycVerifiedAt)
    }

    func loginApple(userId: String, identityToken: Data?) async throws -> User {
        if AppConfig.isMock { return try await MockAuthRepository().loginApple(userId: userId, identityToken: identityToken) }
        let tokenString = identityToken.flatMap { String(data: $0, encoding: .utf8) }
        let dto: AuthResponseDTO = try await service.post("/auth/apple", body: AppleBody(userId: userId, identityToken: tokenString))
        await tokenStore.setTokens(access: dto.accessToken, refresh: dto.refreshToken)
        return User(id: dto.user.id, name: dto.user.name, lastName: dto.user.lastName, email: dto.user.email, hasPassword: dto.user.hasPassword, kycStatus: dto.user.kycStatus, kycProvider: dto.user.kycProvider, kycReference: dto.user.kycReference, kycVerifiedAt: dto.user.kycVerifiedAt)
    }

    func requestPasswordReset(email: String) async throws -> PasswordResetResult {
        if AppConfig.isMock { return try await MockAuthRepository().requestPasswordReset(email: email) }
        HTTPLogger.logRequest(method: "POST", path: "/auth/password-reset", body: ResetBody(email: email))
        let dto: ResetDTO = try await service.post("/auth/password-reset", body: ResetBody(email: email))
        HTTPLogger.logResponse(method: "POST", path: "/auth/password-reset", response: dto)
        return PasswordResetResult(success: dto.success ?? true, devToken: dto.devToken)
    }

    func confirmPasswordReset(token: String, newPassword: String) async throws -> Bool {
        if AppConfig.isMock { return try await MockAuthRepository().confirmPasswordReset(token: token, newPassword: newPassword) }
        let dto: SuccessDTO = try await service.post("/auth/password-reset/confirm", body: ConfirmResetBody(token: token, newPassword: newPassword))
        return dto.success ?? true
    }

    func requestEmailCode(email: String, purpose: String) async throws -> String? {
        if AppConfig.isMock { return try await MockAuthRepository().requestEmailCode(email: email, purpose: purpose) }
        HTTPLogger.logRequest(method: "POST", path: "/auth/email-code", body: EmailCodeRequestBody(email: email, purpose: purpose))
        let dto: EmailCodeDTO = try await service.post("/auth/email-code", body: EmailCodeRequestBody(email: email, purpose: purpose))
        HTTPLogger.logResponse(method: "POST", path: "/auth/email-code", response: dto)
        return dto.devCode
    }

    func logout() async {
        if let refresh = await tokenStore.getRefreshToken() {
            struct LogoutBody: Encodable { let refreshToken: String }
            let _: EmptyResponse? = try? await service.post("/auth/logout", body: LogoutBody(refreshToken: refresh))
        }
        await tokenStore.clear()
    }

    private struct EmptyResponse: Decodable {}
}
