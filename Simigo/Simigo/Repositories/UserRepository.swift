import Foundation

protocol UserRepositoryProtocol {
    func getMe() async throws -> User
    func updateProfile(name: String?, lastName: String?) async throws -> User
    func changeEmail(email: String, password: String, verificationCode: String?) async throws -> User
    func updatePassword(current: String?, new: String) async throws -> Bool
    func deleteAccount(reason: String?, details: String?, currentPassword: String?) async throws -> Bool
}

struct HTTPUserRepository: UserRepositoryProtocol {
    let service = NetworkService()

    struct UserDTO: Decodable { let id: String; let name: String; let lastName: String?; let email: String?; let hasPassword: Bool }
    struct SuccessDTO: Decodable { let success: Bool? }

    func getMe() async throws -> User {
        let dto: UserDTO = try await service.get("/me")
        return User(id: dto.id, name: dto.name, lastName: dto.lastName, email: dto.email, hasPassword: dto.hasPassword)
    }

    struct UpdateProfileBody: Encodable { let name: String?; let lastName: String? }
    func updateProfile(name: String?, lastName: String?) async throws -> User {
        let dto: UserDTO = try await service.put("/me", body: UpdateProfileBody(name: name, lastName: lastName))
        return User(id: dto.id, name: dto.name, lastName: dto.lastName, email: dto.email, hasPassword: dto.hasPassword)
    }

    struct ChangeEmailBody: Encodable { let email: String; let password: String; let verificationCode: String? }
    func changeEmail(email: String, password: String, verificationCode: String?) async throws -> User {
        let dto: UserDTO = try await service.put("/me/email", body: ChangeEmailBody(email: email, password: password, verificationCode: verificationCode))
        return User(id: dto.id, name: dto.name, lastName: dto.lastName, email: dto.email, hasPassword: dto.hasPassword)
    }

    struct UpdatePasswordBody: Encodable { let currentPassword: String?; let newPassword: String }
    func updatePassword(current: String?, new: String) async throws -> Bool {
        let dto: SuccessDTO = try await service.put("/me/password", body: UpdatePasswordBody(currentPassword: current, newPassword: new))
        return dto.success ?? true
    }

    struct DeleteAccountBody: Encodable { let reason: String?; let details: String?; let currentPassword: String? }
    func deleteAccount(reason: String?, details: String?, currentPassword: String?) async throws -> Bool {
        let dto: SuccessDTO = try await service.delete("/me", body: DeleteAccountBody(reason: reason, details: details, currentPassword: currentPassword))
        return dto.success ?? true
    }
}

// 开发环境用 Mock 仓库：直接在内存中读取 AuthManager.currentUser，避免需要后端令牌
@MainActor
struct MockUserRepository: UserRepositoryProtocol {
    let auth: AuthManager

    func getMe() async throws -> User {
        try await Task.sleep(nanoseconds: 150_000_000)
        guard let u = auth.currentUser else {
            throw NetworkError.server(401, "未登录")
        }
        return u
    }

    func updateProfile(name: String?, lastName: String?) async throws -> User {
        try await Task.sleep(nanoseconds: 200_000_000)
        guard let u = auth.currentUser else {
            throw NetworkError.server(401, "未登录")
        }
        let updated = User(
            id: u.id,
            name: name ?? u.name,
            lastName: lastName ?? u.lastName,
            email: u.email,
            hasPassword: u.hasPassword
        )
        return updated
    }

    func changeEmail(email: String, password: String, verificationCode: String?) async throws -> User {
        try await Task.sleep(nanoseconds: 200_000_000)
        guard let u = auth.currentUser else {
            throw NetworkError.server(401, "未登录")
        }
        // 开发环境模拟：若已有密码则要求提供当前密码（由视图层先校验，这里仅提示）
        if u.hasPassword && password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NetworkError.server(400, "您必须提供当前密码才能更改电子邮件")
        }
        let updated = User(
            id: u.id,
            name: u.name,
            lastName: u.lastName,
            email: email,
            hasPassword: u.hasPassword
        )
        return updated
    }

    func updatePassword(current: String?, new: String) async throws -> Bool {
        try await Task.sleep(nanoseconds: 200_000_000)
        guard let u = auth.currentUser else {
            throw NetworkError.server(401, "未登录")
        }
        // 简化处理：总是成功，并将 hasPassword 置为 true
        _ = User(id: u.id, name: u.name, lastName: u.lastName, email: u.email, hasPassword: true)
        return true
    }

    func deleteAccount(reason: String?, details: String?, currentPassword: String?) async throws -> Bool {
        try await Task.sleep(nanoseconds: 200_000_000)
        return true
    }
}
