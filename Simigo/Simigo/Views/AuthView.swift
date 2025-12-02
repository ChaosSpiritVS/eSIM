import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @StateObject private var viewModel: AuthViewModel
    private let initialMode: AuthViewModel.Mode
    @State private var showLoginPassword: Bool = false
    @State private var showRegisterPassword: Bool = false
    @State private var showForgotSheet: Bool = false
    @State private var showVerifyRegisterSheet: Bool = false
    @State private var pendingVerifyName: String = ""
    @State private var pendingVerifyLastName: String = ""
    @State private var pendingVerifyEmail: String = ""
    @State private var pendingVerifyPassword: String = ""
    @State private var pendingVerifyMarketingOptIn: Bool = false
    @State private var showTermsSheet: Bool = false
    @State private var showPrivacySheet: Bool = false
    @FocusState private var focusedField: Field?
    @State private var showErrorBanner: Bool = false
    @State private var hasAppliedInitialMode = false
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var bannerCenter: BannerCenter

    // 在模拟器或使用 Mock 仓库时，显示开发用 Apple 登录入口
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private enum Field {
        case loginEmail, loginPassword
        case registerName, registerLastName, registerEmail, registerPassword
    }

    // 仅在结束编辑后提示错误
    @State private var loginEmailTouched = false
    @State private var loginPasswordTouched = false
    @State private var registerNameTouched = false
    @State private var registerEmailTouched = false
    @State private var registerPasswordTouched = false

    init(auth: AuthManager, initialMode: AuthViewModel.Mode = .login) {
        _viewModel = StateObject(wrappedValue: AuthViewModel(auth: auth))
        self.initialMode = initialMode
    }

    var body: some View {
        List {
            Section {
                Picker(loc("模式"), selection: $viewModel.mode) {
                    Text(loc("登录")).tag(AuthViewModel.Mode.login)
                    Text(loc("注册")).tag(AuthViewModel.Mode.register)
                }
                .pickerStyle(.segmented)
            }

            Section {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    switch result {
                    case .success(let authResult):
                        if let credential = authResult.credential as? ASAuthorizationAppleIDCredential {
                            viewModel.loginWithApple(credential)
                        }
                    case .failure(let error):
                        viewModel.error = error.localizedDescription
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                

                // 开发流程：在模拟器或 Mock 环境下提供模拟 Apple 登录
                if isSimulator || AppConfig.isMock {
                    Button {
                        Telemetry.shared.logEvent("auth_apple_dev_click", parameters: nil)
                        viewModel.loginWithAppleDev()
                    } label: {
                        Text(loc("使用模拟 Apple 登录（开发）"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }

            if viewModel.mode == .login {
                Section {
                    // 邮箱
                    TextField(loc("电子邮件"), text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .padding(10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke((focusedField == .loginEmail) ? Color.accentColor : ((loginEmailTouched && viewModel.loginEmailError != nil) ? Color.red : Color.secondary.opacity(0.3)), lineWidth: 1)
                        )
                        .focused($focusedField, equals: .loginEmail)
                    if loginEmailTouched, focusedField != .loginEmail, let err = viewModel.loginEmailError {
                        Text(err).font(.footnote).foregroundColor(.red)
                    }

                    // 密码
                    HStack {
                        if showLoginPassword {
                            TextField(loc("密码"), text: $viewModel.password)
                                .textContentType(.password)
                                .focused($focusedField, equals: .loginPassword)
                        } else {
                            SecureField(loc("密码"), text: $viewModel.password)
                                .textContentType(.password)
                                .focused($focusedField, equals: .loginPassword)
                        }
                        Button(action: { showLoginPassword.toggle() }) {
                            Image(systemName: showLoginPassword ? "eye" : "eye.slash")
                                .foregroundColor(.secondary)
                                .accessibilityLabel(Text(loc(showLoginPassword ? "隐藏密码" : "显示密码")))
                        }
                    }
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke((focusedField == .loginPassword) ? Color.accentColor : ((loginPasswordTouched && viewModel.loginPasswordError != nil) ? Color.red : Color.secondary.opacity(0.3)), lineWidth: 1)
                    )
                    if loginPasswordTouched, focusedField != .loginPassword, let err = viewModel.loginPasswordError {
                        Text(err).font(.footnote).foregroundColor(.red)
                    }
                } footer: {
                    Button {
                        showForgotSheet = true
                    } label: {
                        Text(loc("忘记密码"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Section {
                    LoadingButton(title: loc("登录"), isLoading: viewModel.isLoading, disabled: !viewModel.isLoginFormValid, fullWidth: true) {
                        loginEmailTouched = true
                        loginPasswordTouched = true
                        Telemetry.shared.logEvent("auth_login_click", parameters: [
                            "is_valid": viewModel.isLoginFormValid,
                            "email": viewModel.email
                        ])
                        viewModel.loginWithEmail()
                    }
                }
            } else {
                Section {
                    TextField(loc("名字"), text: $viewModel.name)
                        .textContentType(.givenName)
                        .padding(10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke((focusedField == .registerName) ? Color.accentColor : ((registerNameTouched && viewModel.registerNameError != nil) ? Color.red : Color.secondary.opacity(0.3)), lineWidth: 1)
                        )
                        .focused($focusedField, equals: .registerName)
                    if registerNameTouched, focusedField != .registerName, let err = viewModel.registerNameError { Text(err).font(.footnote).foregroundColor(.red) }
                    TextField(loc("姓氏（可选）"), text: $viewModel.lastName)
                        .textContentType(.familyName)
                        .padding(10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(focusedField == .registerLastName ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .focused($focusedField, equals: .registerLastName)
                    TextField(loc("电子邮件"), text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .padding(10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke((focusedField == .registerEmail) ? Color.accentColor : ((registerEmailTouched && viewModel.registerEmailError != nil) ? Color.red : Color.secondary.opacity(0.3)), lineWidth: 1)
                        )
                        .focused($focusedField, equals: .registerEmail)
                    if registerEmailTouched, focusedField != .registerEmail, let err = viewModel.registerEmailError { Text(err).font(.footnote).foregroundColor(.red) }
                    HStack {
                        if showRegisterPassword {
                            TextField(loc("密码"), text: $viewModel.password)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .registerPassword)
                        } else {
                            SecureField(loc("密码"), text: $viewModel.password)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .registerPassword)
                        }
                        Button(action: { showRegisterPassword.toggle() }) {
                            Image(systemName: showRegisterPassword ? "eye" : "eye.slash")
                                .foregroundColor(.secondary)
                                .accessibilityLabel(Text(loc(showRegisterPassword ? "隐藏密码" : "显示密码")))
                        }
                    }
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke((focusedField == .registerPassword) ? Color.accentColor : ((registerPasswordTouched && viewModel.registerPasswordError != nil) ? Color.red : Color.secondary.opacity(0.3)), lineWidth: 1)
                    )
                } footer: {
                    if !viewModel.password.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Image(systemName: viewModel.password.count >= 8 ? "checkmark.circle" : "xmark.circle").foregroundColor(viewModel.password.count >= 8 ? .green : .red); Text(loc("最少 8 个字符")) }
                            HStack { Image(systemName: viewModel.passwordHasUppercase ? "checkmark.circle" : "xmark.circle").foregroundColor(viewModel.passwordHasUppercase ? .green : .red); Text(loc("大写")) }
                            HStack { Image(systemName: viewModel.passwordHasLowercase ? "checkmark.circle" : "xmark.circle").foregroundColor(viewModel.passwordHasLowercase ? .green : .red); Text(loc("小写")) }
                            HStack { Image(systemName: viewModel.passwordHasDigit ? "checkmark.circle" : "xmark.circle").foregroundColor(viewModel.passwordHasDigit ? .green : .red); Text(loc("数字 1234567890")) }
                            HStack { Image(systemName: viewModel.passwordHasSymbol ? "checkmark.circle" : "xmark.circle").foregroundColor(viewModel.passwordHasSymbol ? .green : .red); Text(loc("一个符号 +-*/?:=!%$#")) }
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
                    LoadingButton(title: loc("注册"), isLoading: viewModel.isLoading, disabled: !viewModel.isRegisterFormValid, fullWidth: true) {
                        registerNameTouched = true
                        registerEmailTouched = true
                        registerPasswordTouched = true
                        Telemetry.shared.logEvent("auth_register_click", parameters: [
                            "is_valid": viewModel.isRegisterFormValid,
                            "email": viewModel.email
                        ])
                        // 进入验证码验证页
                        Telemetry.shared.logEvent("auth_register_start", parameters: [
                            "email": viewModel.email,
                            "has_last_name": !(viewModel.lastName.isEmpty),
                            "marketing_opt_in": viewModel.marketingOptIn
                        ])
                        pendingVerifyName = viewModel.name
                        pendingVerifyLastName = viewModel.lastName
                        pendingVerifyEmail = viewModel.email
                        pendingVerifyPassword = viewModel.password
                        pendingVerifyMarketingOptIn = viewModel.marketingOptIn
                        showVerifyRegisterSheet = true
                    }
                } footer: {
                    HStack(spacing: 4) {
                        Text(loc("注册账户即表示我同意"))
                            .foregroundColor(.secondary)
                        Button { showTermsSheet = true } label: { Text(loc("条款与条件")).underline() }
                        .buttonStyle(.plain)
                        Text(loc("与"))
                            .foregroundColor(.secondary)
                        Button { showPrivacySheet = true } label: { Text(loc("隐私政策")).underline() }
                        .buttonStyle(.plain)
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .listStyle(.insetGrouped)
        
        .onAppear {
            // 仅在首次出现时应用初始模式，返回子页面后不重置用户选择
            if !hasAppliedInitialMode {
                viewModel.mode = initialMode
                hasAppliedInitialMode = true
            }
            Telemetry.shared.logEvent("auth_open", parameters: [
                "mode": (viewModel.mode == .login ? "login" : "register")
            ])
        }
        .onChange(of: viewModel.mode) { _, newMode in
            Telemetry.shared.logEvent("auth_mode_change", parameters: [
                "mode": (newMode == .login ? "login" : "register")
            ])
        }
        
        
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(loc("取消")) { navBridge.dismiss() } } }
        // 焦点变化时，标记“已结束编辑”用于触发错误提示
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .loginEmail { loginEmailTouched = true }
            if oldValue == .loginPassword { loginPasswordTouched = true }
            if oldValue == .registerName { registerNameTouched = true }
            if oldValue == .registerEmail { registerEmailTouched = true }
            if oldValue == .registerPassword { registerPasswordTouched = true }
        }
        .onChange(of: viewModel.error) { _, newValue in
            if let msg = newValue, !msg.isEmpty {
                bannerCenter.enqueue(message: msg, style: .error, source: "auth", onClose: { withAnimation(.easeInOut(duration: 0.25)) { viewModel.error = nil } })
            }
        }
        .sheet(isPresented: $showForgotSheet) {
            UIKitNavHost(root: ForgotPasswordView(
                repo: AppConfig.isMock ? MockAuthRepository() : HTTPAuthRepository(),
                prefillEmail: viewModel.email
            ))
        }
        .sheet(isPresented: $showVerifyRegisterSheet) {
            UIKitNavHost(root: RegisterEmailCodeView(
                repo: AppConfig.isMock ? MockAuthRepository() : HTTPAuthRepository(),
                name: pendingVerifyName,
                lastName: pendingVerifyLastName.isEmpty ? nil : pendingVerifyLastName,
                email: pendingVerifyEmail,
                password: pendingVerifyPassword,
                marketingOptIn: pendingVerifyMarketingOptIn
            ))
        }
        .sheet(isPresented: $showTermsSheet) { UIKitNavHost(root: TermsOfServiceView(showCancel: true)) }
        .sheet(isPresented: $showPrivacySheet) { UIKitNavHost(root: PrivacyPolicyView(showCancel: true)) }
    }
}

#Preview("登录/注册") {
    NavigationStack { AuthView(auth: AuthManager(), initialMode: .login) }
}
