import SwiftUI

struct RegisterEmailCodeView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var bannerCenter: BannerCenter
    let repo: AuthRepositoryProtocol

    let name: String
    let lastName: String?
    let email: String
    let password: String
    let marketingOptIn: Bool

    @State private var code: String = ""
    @State private var isLoading: Bool = false
    @State private var error: String?
    @State private var showErrorBanner: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                Text(String(format: loc("您的验证码已发送至 %@ — 请输入 4 位验证码完成验证。"), email))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Section {
                TextField(loc("验证码"), text: $code)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .onChange(of: code) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered.count > 4 {
                            code = String(filtered.prefix(4))
                        } else {
                            code = filtered
                        }
                    }
            }
            Section {
                LoadingButton(title: loc("重新发送验证码"), isLoading: isLoading, disabled: isLoading, fullWidth: true) {
                    resend()
                }
                LoadingButton(title: loc("输入代码"), isLoading: isLoading, disabled: code.count != 4 || isLoading, fullWidth: true) {
                    submit()
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear { resend(); focused = true }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(loc("取消")) { navBridge.dismiss() } } }
        
        .onChange(of: error) { _, newValue in
            if let msg = newValue, !msg.isEmpty {
                bannerCenter.enqueue(message: msg, style: .error, source: "email_code_register", onClose: { withAnimation(.easeInOut(duration: 0.25)) { error = nil } })
            }
        }
    }

    private func resend() {
        Task {
            isLoading = true
            do {
                _ = try await repo.requestEmailCode(email: email, purpose: "register")
                Telemetry.shared.logEvent("register_verification_resend", parameters: [
                    "email": email
                ])
            } catch {
                self.error = error.localizedDescription
                showErrorBanner = true
                Telemetry.shared.logEvent("register_verification_resend_failure", parameters: [
                    "email": email,
                    "error": error.localizedDescription
                ])
                Telemetry.shared.record(error: error)
            }
            isLoading = false
        }
    }

    private func submit() {
        Task {
            isLoading = true
            do {
                let user = try await repo.register(name: name, lastName: lastName, email: email, password: password, marketingOptIn: marketingOptIn, verificationCode: code)
                auth.currentUser = user
                navBridge.dismiss()
                Telemetry.shared.logEvent("register_verification_success", parameters: [
                    "email": email
                ])
            } catch {
                self.error = error.localizedDescription
                showErrorBanner = true
                Telemetry.shared.logEvent("register_verification_failure", parameters: [
                    "email": email,
                    "error": error.localizedDescription
                ])
                Telemetry.shared.record(error: error)
            }
            isLoading = false
        }
    }
}

struct ChangeEmailCodeView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var bannerCenter: BannerCenter

    let authRepo: AuthRepositoryProtocol
    let userRepo: UserRepositoryProtocol
    let newEmail: String
    let currentPassword: String
    let onSuccess: ((User) -> Void)?

    @State private var code: String = ""
    @State private var isLoading: Bool = false
    @State private var error: String?
    @State private var showErrorBanner: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                Text(String(format: loc("您的验证码已发送至 %@ — 请输入 4 位验证码完成验证。"), newEmail))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Section {
                TextField(loc("验证码"), text: $code)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .onChange(of: code) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered.count > 4 {
                            code = String(filtered.prefix(4))
                        } else {
                            code = filtered
                        }
                    }
            }
            Section {
                LoadingButton(title: loc("重新发送验证码"), isLoading: isLoading, disabled: isLoading, fullWidth: true) {
                    resend()
                }
                LoadingButton(title: loc("输入代码"), isLoading: isLoading, disabled: code.count != 4 || isLoading, fullWidth: true) {
                    submit()
                }
            }
        }
        .listStyle(.insetGrouped)
        
        .onAppear { resend(); focused = true }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(loc("取消")) { navBridge.dismiss() } } }
        
        .onChange(of: error) { _, newValue in
            if let msg = newValue, !msg.isEmpty {
                bannerCenter.enqueue(message: msg, style: .error, source: "email_code_change", onClose: { withAnimation(.easeInOut(duration: 0.25)) { error = nil } })
            }
        }
    }

    private func resend() {
        Task {
            isLoading = true
            do {
                _ = try await authRepo.requestEmailCode(email: newEmail, purpose: "change_email")
                Telemetry.shared.logEvent("change_email_verification_resend", parameters: [
                    "email": newEmail
                ])
            } catch {
                self.error = error.localizedDescription
                showErrorBanner = true
                Telemetry.shared.logEvent("change_email_verification_resend_failure", parameters: [
                    "email": newEmail,
                    "error": error.localizedDescription
                ])
                Telemetry.shared.record(error: error)
            }
            isLoading = false
        }
    }

    private func submit() {
        Task {
            isLoading = true
            do {
                let updated = try await userRepo.changeEmail(email: newEmail, password: currentPassword, verificationCode: code)
                auth.currentUser = updated
                onSuccess?(updated)
                navBridge.dismiss()
                Telemetry.shared.logEvent("change_email_verification_success", parameters: [
                    "email": newEmail
                ])
            } catch {
                self.error = error.localizedDescription
                showErrorBanner = true
                Telemetry.shared.logEvent("change_email_verification_failure", parameters: [
                    "email": newEmail,
                    "error": error.localizedDescription
                ])
                Telemetry.shared.record(error: error)
            }
            isLoading = false
        }
    }
}

#Preview("注册验证码") {
    NavigationStack {
        RegisterEmailCodeView(
            repo: MockAuthRepository(),
            name: "测试",
            lastName: nil,
            email: "demo@example.com",
            password: "Password1+",
            marketingOptIn: false
        )
        .environmentObject(AuthManager())
    }
}

#Preview("改邮箱验证码") {
    NavigationStack {
        ChangeEmailCodeView(
            authRepo: MockAuthRepository(),
            userRepo: HTTPUserRepository(),
            newEmail: "demo@example.com",
            currentPassword: "Password1+",
            onSuccess: { _ in }
        )
        .environmentObject(AuthManager())
    }
}
