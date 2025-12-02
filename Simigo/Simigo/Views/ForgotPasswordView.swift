import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var bannerCenter: BannerCenter
    @State private var showConfirmSheet: Bool = false
    let repo: AuthRepositoryProtocol
    @State private var email: String = ""
    @State private var isLoading: Bool = false
    @State private var message: String?
    @State private var error: String?
    @State private var showErrorBanner: Bool = false
    // Debug 下自动跳转到确认页所需的状态
    @State private var devToken: String?
    @State private var hasNavigatedToConfirm: Bool = false

    init(repo: AuthRepositoryProtocol, prefillEmail: String? = nil) {
        self.repo = repo
        // 从登录页传入的邮箱进行预填，避免重复输入
        _email = State(initialValue: prefillEmail ?? "")
    }

    var body: some View {
        List {
            Section {
                Text(loc("请输入注册邮箱以接收重置链接"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Section {
                TextField(loc("电子邮件"), text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
            }
            Section {
                LoadingButton(title: loc("发送重置邮件"), isLoading: isLoading, disabled: email.trimmingCharacters(in: .whitespaces).isEmpty || isLoading, fullWidth: true) {
                    submit()
                }
            }

            // 使用值导航的入口：我已有重置令牌

            Section {
                Button {
                    showConfirmSheet = true
                } label: {
                    Text(loc("我已有重置令牌，去设置新密码"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let msg = message {
                Section { Text(msg).foregroundColor(.green) }
            }
        }
        .listStyle(.insetGrouped)
        
        .onAppear {
            Telemetry.shared.logEvent("reset_request_open", parameters: [
                "prefill_email": email
            ])
        }
        
        .onChange(of: error) { _, newValue in
            if let msg = newValue, !msg.isEmpty {
                bannerCenter.enqueue(message: msg, style: .error, source: "forgot_password", onClose: { withAnimation(.easeInOut(duration: 0.25)) { error = nil } })
            }
        }
        // 监听 devToken 变化：令牌到达后通过路径值导航进入确认页
        .onChange(of: devToken) { t in
            if !hasNavigatedToConfirm, let t, !t.isEmpty {
                DispatchQueue.main.async {
                    showConfirmSheet = true
                    hasNavigatedToConfirm = true
                }
                Telemetry.shared.logEvent("reset_confirm_open", parameters: [
                    "from_link": false,
                    "prefill_email": email
                ])
            }
        }
        .sheet(isPresented: $showConfirmSheet) {
            UIKitNavHost(root: ResetPasswordConfirmView(
                repo: AppConfig.isMock ? MockAuthRepository() : HTTPAuthRepository(),
                prefillToken: devToken,
                prefillEmail: email
            ))
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(loc("取消")) { navBridge.dismiss() } } }
    }

    private func submit() {
        error = nil
        message = nil
        isLoading = true
        Task {
            do {
                let result = try await repo.requestPasswordReset(email: email)
                isLoading = false
                if result.success {
                    message = loc("重置邮件已发送，请检查你的邮箱")
                    Telemetry.shared.logEvent("password_reset_request_success", parameters: [
                        "email": email,
                        "has_dev_token": (result.devToken != nil)
                    ])
                    // 无论 Debug 或 Release，若返回了 devToken，则进行预填并自动跳转
                    if let token = result.devToken, !token.isEmpty {
                        devToken = token
                        // 导航由 .onChange(of: devToken) 统一触发
                    }
                } else {
                    error = loc("发送失败，请稍后重试")
                    Telemetry.shared.logEvent("password_reset_request_failure", parameters: [
                        "email": email,
                        "reason": "unsuccessful_response"
                    ])
                }
            } catch {
                isLoading = false
                self.error = error.localizedDescription
                Telemetry.shared.logEvent("password_reset_request_failure", parameters: [
                    "email": email,
                    "error": error.localizedDescription
                ])
                Telemetry.shared.record(error: error)
            }
        }
    }
}

#Preview("忘记密码") {
    NavigationStack { ForgotPasswordView(repo: MockAuthRepository(), prefillEmail: "demo@example.com") }
}
