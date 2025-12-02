import SwiftUI

struct ResetPasswordConfirmView: View {
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var bannerCenter: BannerCenter
    let repo: AuthRepositoryProtocol
    @State private var token: String = ""
    @State private var newPassword: String = ""
    @State private var isLoading: Bool = false
    @State private var message: String?
    @State private var error: String?
    @State private var showErrorBanner: Bool = false
    @State private var showPassword: Bool = false
    private let isTokenPrefilled: Bool
    private let prefillEmail: String?

    init(repo: AuthRepositoryProtocol, prefillToken: String? = nil, prefillEmail: String? = nil) {
        self.repo = repo
        _token = State(initialValue: prefillToken ?? "")
        // 仅当令牌非空时视为已预填，避免空令牌导致输入框被错误禁用
        self.isTokenPrefilled = (prefillToken?.isEmpty == false)
        self.prefillEmail = prefillEmail
    }

    var body: some View {
        List {
            Section {
                Text(loc("请输入邮件中的重置令牌以及新的密码"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Section {
                TextField(loc("重置令牌"), text: $token)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.asciiCapable)
                    .autocapitalization(.none)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .disabled(isTokenPrefilled)
                HStack {
                    if showPassword {
                        TextField(loc("新密码"), text: $newPassword)
                            .textContentType(.newPassword)
                    } else {
                        SecureField(loc("新密码"), text: $newPassword)
                            .textContentType(.newPassword)
                    }
                    Button(action: { showPassword.toggle() }) {
                        Image(systemName: showPassword ? "eye" : "eye.slash")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                if !newPassword.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Image(systemName: newPassword.count >= 8 ? "checkmark.circle" : "xmark.circle").foregroundColor(newPassword.count >= 8 ? .green : .red); Text(loc("最少 8 个字符")) }
                        HStack { Image(systemName: passwordHasUppercase ? "checkmark.circle" : "xmark.circle").foregroundColor(passwordHasUppercase ? .green : .red); Text(loc("大写")) }
                        HStack { Image(systemName: passwordHasLowercase ? "checkmark.circle" : "xmark.circle").foregroundColor(passwordHasLowercase ? .green : .red); Text(loc("小写")) }
                        HStack { Image(systemName: passwordHasDigit ? "checkmark.circle" : "xmark.circle").foregroundColor(passwordHasDigit ? .green : .red); Text(loc("数字 1234567890")) }
                        HStack { Image(systemName: passwordHasSymbol ? "checkmark.circle" : "xmark.circle").foregroundColor(passwordHasSymbol ? .green : .red); Text(loc("一个符号 +-*/?:=!%$#")) }
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("— " + loc("最少 8 个字符"))
                        Text("— " + loc("大写"))
                        Text("— " + loc("小写"))
                        Text("— " + loc("数字 1234567890"))
                        Text("— " + loc("一个符号 +-*/?:=!%$#"))
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }
            }
            Section {
                LoadingButton(
                    title: loc("重置密码"),
                    isLoading: isLoading,
                    disabled: token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !resetPasswordMeetsAllRules || isLoading,
                    fullWidth: true
                ) {
                    submit()
                }
            }

            if let msg = message {
                Section { Text(msg).foregroundColor(.green) }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            Telemetry.shared.logEvent("reset_confirm_open", parameters: [
                "prefill_email": prefillEmail ?? ""
            ])
        }
        
        .onChange(of: error) { _, newValue in
            if let msg = newValue, !msg.isEmpty {
                bannerCenter.enqueue(message: msg, style: .error, source: "reset_password_confirm", onClose: { withAnimation(.easeInOut(duration: 0.25)) { error = nil } })
            }
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(loc("取消")) { navBridge.dismiss() } } }
        // 成功后通过重置路径返回到登录根页（不保留返回栈）
    }

    private func submit() {
        error = nil
        message = nil
        isLoading = true
        Task {
            do {
                let ok = try await repo.confirmPasswordReset(token: token, newPassword: newPassword)
                isLoading = false
                if ok {
                    message = loc("密码已重置，请使用新密码登录")
                    Telemetry.shared.logEvent("password_reset_confirm_success", parameters: [
                        "prefill_email": prefillEmail ?? "",
                        "token_prefilled": isTokenPrefilled
                    ])
                    // 将邮箱写入上次登录缓存，便于登录页预填
                    if let email = prefillEmail, !email.isEmpty {
                        UserDefaults.standard.set(email, forKey: "simigo.lastLoginEmail")
                    }
                    DispatchQueue.main.async { navBridge.dismiss() }
                } else {
                    error = loc("重置失败，请检查令牌与密码")
                    Telemetry.shared.logEvent("password_reset_confirm_failure", parameters: [
                        "prefill_email": prefillEmail ?? "",
                        "reason": "validation_failed"
                    ])
                }
            } catch {
                isLoading = false
                self.error = error.localizedDescription
                Telemetry.shared.logEvent("password_reset_confirm_failure", parameters: [
                    "prefill_email": prefillEmail ?? "",
                    "error": error.localizedDescription
                ])
                Telemetry.shared.record(error: error)
            }
        }
    }

    // 与注册一致的密码规则
    private var passwordHasUppercase: Bool { newPassword.rangeOfCharacter(from: .uppercaseLetters) != nil }
    private var passwordHasLowercase: Bool { newPassword.rangeOfCharacter(from: .lowercaseLetters) != nil }
    private var passwordHasDigit: Bool { newPassword.rangeOfCharacter(from: .decimalDigits) != nil }
    private var symbolSet: CharacterSet { CharacterSet(charactersIn: "+-*/?:=!%$#") }
    private var passwordHasSymbol: Bool { newPassword.rangeOfCharacter(from: symbolSet) != nil }
    private var resetPasswordMeetsAllRules: Bool {
        newPassword.count >= 8 && passwordHasUppercase && passwordHasLowercase && passwordHasDigit && passwordHasSymbol
    }
}

#Preview("确认重置") {
    NavigationStack { ResetPasswordConfirmView(repo: MockAuthRepository(), prefillToken: "demo-dev-token") }
        .environmentObject(AuthManager())
}
