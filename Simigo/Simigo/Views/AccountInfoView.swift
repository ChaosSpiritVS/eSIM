import SwiftUI

struct AccountInfoView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var bannerCenter: BannerCenter
    private var repo: UserRepositoryProtocol { AppConfig.isMock ? MockUserRepository(auth: auth) : HTTPUserRepository() }

    @State private var name: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""

    @State private var isEditingEmail = false
    @State private var emailPassword = ""
    @State private var newEmail = ""
    @State private var showEmailPassword = false
    // Apple 登录初始无密码：需先创建密码后才允许编辑邮箱/密码
    @State private var hasPassword = false
    @State private var showCreatePasswordSheet = false
    @State private var showEditEmailSheet = false
    @State private var createPw1: String = ""
    @State private var createPw2: String = ""

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var showCurrentPassword = false
    @State private var showNewPassword = false
    @State private var deletePassword = ""
    @State private var showDeletePassword = false

    @State private var showDeleteSheet = false
    @State private var deleteReason: String = ""
    @State private var deleteDetails: String = ""

    @State private var error: String?
    @State private var showErrorBanner = false
    @State private var isLoading = false
    private let lastEmailKey = "simigo.lastLoginEmail"
    // 编辑邮箱弹窗内的导航路径（用于跳转到验证码页）
    @State private var showVerifyEmailSheet = false
    @State private var pendingNewEmail: String = ""
    @State private var pendingEmailPassword: String = ""
    // 焦点与触碰状态，用于“失焦后再提示错误”
    private enum Field { case name, lastName, newPassword, newEmail, emailPassword }
    @FocusState private var focusedField: Field?
    @State private var nameTouched = false
    @State private var newEmailTouched = false
    @State private var newPasswordTouched = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: hasPassword && (auth.currentUser?.email != nil) ? "envelope" : "applelogo")
                        .foregroundColor(.secondary)
                    Text(hasPassword && (auth.currentUser?.email != nil) ? loc("登录方式：邮箱登录") : (hasPassword ? loc("登录方式：Apple 登录（已设置密码）") : loc("登录方式：Apple 登录（未设置密码）")))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            Section(loc("账户信息")) {
                LabeledContent {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(loc("请输入名称"), text: $name)
                            .focused($focusedField, equals: .name)
                        if nameTouched, let err = nameError { Text(err).font(.footnote).foregroundColor(.red) }
                    }
                } label: {
                    Text(loc("名称")).foregroundColor(.secondary)
                }
                LabeledContent {
                    TextField(loc("可选"), text: $lastName)
                        .focused($focusedField, equals: .lastName)
                } label: {
                    Text(loc("姓氏")).foregroundColor(.secondary)
                }
                LabeledContent {
                    HStack {
                        TextField("", text: $email)
                            .disabled(true)
                        if hasPassword {
                            Button(loc("编辑邮箱")) { showEditEmailSheet = true }
                        } else {
                            Text(loc("编辑邮箱")).foregroundColor(.secondary)
                        }
                    }
                } label: {
                    Text(loc("电子邮件")).foregroundColor(.secondary)
                }
                LoadingButton(title: loc("保存资料"), isLoading: isLoading, disabled: isProfileSaveDisabled, fullWidth: false) {
                    Task { await saveProfile() }
                }
            }
            Section(loc("密码")) {
                if !hasPassword {
                    Text(loc("您当前尚未设置密码。点击下方按钮创建密码，以便后续更改邮箱与密码。"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Button(loc("创建密码")) { showCreatePasswordSheet = true }
                } else {
                    HStack {
                        if showCurrentPassword {
                            TextField(loc("当前密码"), text: $currentPassword).textContentType(.password)
                        } else {
                            SecureField(loc("当前密码"), text: $currentPassword).textContentType(.password)
                        }
                        Button(action: { showCurrentPassword.toggle() }) {
                            Image(systemName: showCurrentPassword ? "eye" : "eye.slash").foregroundColor(.secondary)
                                .accessibilityLabel(Text(showCurrentPassword ? loc("隐藏密码") : loc("显示密码")))
                        }
                    }
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if showNewPassword {
                                TextField(loc("新密码"), text: $newPassword).textContentType(.newPassword).focused($focusedField, equals: .newPassword)
                            } else {
                                SecureField(loc("新密码"), text: $newPassword).textContentType(.newPassword).focused($focusedField, equals: .newPassword)
                            }
                            Button(action: { showNewPassword.toggle() }) {
                                Image(systemName: showNewPassword ? "eye" : "eye.slash").foregroundColor(.secondary)
                                    .accessibilityLabel(Text(showNewPassword ? loc("隐藏密码") : loc("显示密码")))
                            }
                        }
                        .padding(10)
                        .background(Color(UIColor.secondarySystemBackground))
                        if newPasswordTouched && !newPasswordMeetsAllRules && focusedField != .newPassword && !newPassword.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Image(systemName: newPassword.count >= 8 ? "checkmark.circle" : "xmark.circle").foregroundColor(newPassword.count >= 8 ? .green : .red); Text(loc("最少 8 个字符")) }
                                HStack { Image(systemName: newPasswordHasUppercase ? "checkmark.circle" : "xmark.circle").foregroundColor(newPasswordHasUppercase ? .green : .red); Text(loc("大写")) }
                                HStack { Image(systemName: newPasswordHasLowercase ? "checkmark.circle" : "xmark.circle").foregroundColor(newPasswordHasLowercase ? .green : .red); Text(loc("小写")) }
                                HStack { Image(systemName: newPasswordHasDigit ? "checkmark.circle" : "xmark.circle").foregroundColor(newPasswordHasDigit ? .green : .red); Text(loc("数字 1234567890")) }
                                HStack { Image(systemName: newPasswordHasSymbol ? "checkmark.circle" : "xmark.circle").foregroundColor(newPasswordHasSymbol ? .green : .red); Text(loc("一个符号 +-*/?:=!%$#")) }
                            }
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        }
                    }
                    LoadingButton(title: loc("更新密码"), isLoading: isLoading, disabled: isLoading || !newPasswordMeetsAllRules || (hasPassword && currentPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), fullWidth: false) {
                        Task { await updatePassword() }
                    }
                }
            }
            Section(loc("删除您的账户")) {
                Text(loc("您可以永久删除您的账户，完成后无法撤销。")).font(.footnote).foregroundColor(.secondary)
                Button(loc("删除账户"), role: .destructive) {
                    Telemetry.shared.logEventDeferred("account_delete_sheet_open", parameters: nil)
                    showDeleteSheet = true
                }
            }
        }
        .listStyle(.insetGrouped)
        
        .task { await loadInitial() }
        .onAppear { Telemetry.shared.logEvent("account_info_open", parameters: nil) }
        
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .name { nameTouched = true }
            if oldValue == .newEmail { newEmailTouched = true }
            if oldValue == .newPassword { newPasswordTouched = true }
        }
        .onChange(of: error) { _, newValue in
            if let msg = newValue, !msg.isEmpty {
                bannerCenter.enqueue(message: msg, style: .error, source: "account_info", onClose: { withAnimation(.easeInOut(duration: 0.25)) { error = nil } })
            }
        }
        .onChange(of: networkMonitor.backendOnline) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.25)) { showErrorBanner = false; error = nil }
                Task {
                    do {
                        let me = try await repo.getMe()
                        auth.currentUser = me
                        name = me.name
                        lastName = me.lastName ?? ""
                        email = me.email ?? ""
                        newEmail = email
                    } catch {
                    }
                }
            }
        }
        .sheet(isPresented: $showCreatePasswordSheet) {
            UIKitNavHost(root: Form {
                Section {
                    SecureField(loc("新密码（至少 8 位，含大小写/数字/符号）"), text: $createPw1)
                    SecureField(loc("确认新密码"), text: $createPw2)
                    if !createPw1.isEmpty && !createPasswordMeetsAllRules {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Image(systemName: createPw1.count >= 8 ? "checkmark.circle" : "xmark.circle").foregroundColor(createPw1.count >= 8 ? .green : .red); Text(loc("最少 8 个字符")) }
                            HStack { Image(systemName: createPasswordHasUppercase ? "checkmark.circle" : "xmark.circle").foregroundColor(createPasswordHasUppercase ? .green : .red); Text(loc("大写")) }
                            HStack { Image(systemName: createPasswordHasLowercase ? "checkmark.circle" : "xmark.circle").foregroundColor(createPasswordHasLowercase ? .green : .red); Text(loc("小写")) }
                            HStack { Image(systemName: createPasswordHasDigit ? "checkmark.circle" : "xmark.circle").foregroundColor(createPasswordHasDigit ? .green : .red); Text(loc("数字 1234567890")) }
                            HStack { Image(systemName: createPasswordHasSymbol ? "checkmark.circle" : "xmark.circle").foregroundColor(createPasswordHasSymbol ? .green : .red); Text(loc("一个符号 +-*/?:=!%$#")) }
                        }
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    }
                }
                Section {
                    LoadingButton(title: loc("保存密码"), isLoading: isLoading, disabled: isLoading || !createPasswordMeetsAllRules || createPw1 != createPw2, fullWidth: true) {
                        Task { await createPassword() }
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(loc("取消")) { showCreatePasswordSheet = false } } }
            
            )
        }
        .sheet(isPresented: $showEditEmailSheet) {
            UIKitNavHost(root: Form {
                Section(loc("当前邮箱")) { Text(email).foregroundColor(.secondary) }
                Section(loc("验证与新邮箱")) {
                    HStack {
                        if showEmailPassword {
                            TextField(loc("当前密码"), text: $emailPassword).textContentType(.password)
                        } else {
                            SecureField(loc("当前密码"), text: $emailPassword).textContentType(.password)
                        }
                        Button(action: { showEmailPassword.toggle() }) {
                            Image(systemName: showEmailPassword ? "eye" : "eye.slash").foregroundColor(.secondary)
                                .accessibilityLabel(Text(showEmailPassword ? loc("隐藏密码") : loc("显示密码")))
                        }
                    }
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(loc("新的电子邮件地址"), text: $newEmail)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .padding(10)
                            .background(Color(UIColor.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke((focusedField == .newEmail) ? Color.accentColor : (((newEmailTouched || (!newEmail.isEmpty && focusedField != .newEmail)) && newEmailError != nil) ? Color.red : Color.secondary.opacity(0.3)), lineWidth: 1)
                            )
                            .focused($focusedField, equals: .newEmail)
                        if (newEmailTouched || (!newEmail.isEmpty && focusedField != .newEmail)), let err = newEmailError { Text(err).font(.footnote).foregroundColor(.red) }
                    }
                }
                Section {
                    LoadingButton(title: loc("保存邮箱"), isLoading: isLoading, disabled: isEmailSaveDisabled, fullWidth: true) {
                        let trimmed = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard isValidEmail(trimmed), !emailPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = loc("请输入有效的新邮箱与当前密码"); return }
                        pendingNewEmail = trimmed
                        pendingEmailPassword = emailPassword
                        showVerifyEmailSheet = true
                    }
                }
            }
            .onAppear { emailPassword = "" }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(loc("取消")) { showEditEmailSheet = false } } }
            )
        }
        .sheet(isPresented: $showVerifyEmailSheet) {
            UIKitNavHost(root: ChangeEmailCodeView(
                authRepo: AppConfig.isMock ? MockAuthRepository() : HTTPAuthRepository(),
                userRepo: AppConfig.isMock ? MockUserRepository(auth: auth) : HTTPUserRepository(),
                newEmail: pendingNewEmail,
                currentPassword: pendingEmailPassword,
                onSuccess: { updated in
                    self.email = updated.email ?? ""
                    self.newEmail = self.email
                    UserDefaults.standard.set(self.email, forKey: lastEmailKey)
                    self.showEditEmailSheet = false
                    self.emailPassword = ""
                    self.showVerifyEmailSheet = false
                }
            ))
        }
        .sheet(isPresented: $showDeleteSheet) {
            UIKitNavHost(root: Form {
                Section(loc("原因")) {
                    Picker(loc("选择原因"), selection: $deleteReason) {
                        Text(loc("不兼容的设备")).tag("device")
                        Text(loc("数字安全")).tag("security")
                        Text(loc("不再需要")).tag("not_needed")
                        Text(loc("糟糕的客户服务")).tag("service")
                        Text(loc("不佳的用户体验")).tag("ux")
                        Text(loc("其他")).tag("other")
                    }
                }
                Section(loc("补充说明")) { TextField(loc("请输入..."), text: $deleteDetails, axis: .vertical).lineLimit(3...6) }
                Section {
                    if hasPassword {
                        HStack {
                            if showDeletePassword {
                                TextField(loc("当前密码"), text: $deletePassword).textContentType(.password)
                            } else {
                                SecureField(loc("当前密码"), text: $deletePassword).textContentType(.password)
                            }
                            Button(action: { showDeletePassword.toggle() }) {
                                Image(systemName: showDeletePassword ? "eye" : "eye.slash").foregroundColor(.secondary)
                                    .accessibilityLabel(Text(showDeletePassword ? loc("隐藏密码") : loc("显示密码")))
                            }
                        }
                        .padding(10)
                        .background(Color(UIColor.secondarySystemBackground))
                    }
                    LoadingButton(title: loc("确认删除"), isLoading: isLoading, disabled: isLoading || (hasPassword && deletePassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), fullWidth: false, tint: .red) {
                        Telemetry.shared.logEvent("account_delete_submit", parameters: [
                            "has_password": hasPassword,
                            "reason": deleteReason.isEmpty ? "" : deleteReason,
                            "details_len": deleteDetails.trimmingCharacters(in: .whitespacesAndNewlines).count
                        ])
                        Task { await deleteAccount() }
                    }
                }
            }
            .onAppear { deletePassword = "" }
            .onAppear { Telemetry.shared.logEvent("account_delete_sheet_opened", parameters: nil) }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(loc("取消")) { showDeleteSheet = false } } }
            
            )
        }
    }

    // MARK: - 账户信息校验（与注册一致）
    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", pattern)
        return predicate.evaluate(with: trimmed)
    }

    private var nameError: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count >= 2 ? nil : loc("请填写至少 2 个字符的名字。")
    }

    private var newEmailError: String? {
        let trimmed = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return isValidEmail(trimmed) ? nil : loc("请输入有效的电子邮件地址。")
    }

    private var newPasswordError: String? {
        guard !newPassword.isEmpty else { return nil }
        return newPasswordMeetsAllRules ? nil : loc("至少 8 位且包含大小写字母、数字与符号。")
    }

    private var newPasswordMeetsAllRules: Bool {
        let uc = newPassword.rangeOfCharacter(from: .uppercaseLetters) != nil
        let lc = newPassword.rangeOfCharacter(from: .lowercaseLetters) != nil
        let dg = newPassword.rangeOfCharacter(from: .decimalDigits) != nil
        let symbolSet = CharacterSet(charactersIn: "+-*/?:=!%$#")
        let sm = newPassword.rangeOfCharacter(from: symbolSet) != nil
        return newPassword.count >= 8 && uc && lc && dg && sm
    }

    private var newPasswordHasUppercase: Bool {
        newPassword.rangeOfCharacter(from: .uppercaseLetters) != nil
    }
    private var newPasswordHasLowercase: Bool {
        newPassword.rangeOfCharacter(from: .lowercaseLetters) != nil
    }
    private var newPasswordHasDigit: Bool {
        newPassword.rangeOfCharacter(from: .decimalDigits) != nil
    }
    private var newPasswordHasSymbol: Bool {
        let symbolSet = CharacterSet(charactersIn: "+-*/?:=!%$#")
        return newPassword.rangeOfCharacter(from: symbolSet) != nil
    }

    private func loadInitial() async {
        guard let u = auth.currentUser else { return }
        name = u.name
        lastName = u.lastName ?? ""
        email = u.email ?? ""
        newEmail = email
        // 直接使用服务器返回的 hasPassword 字段，而非通过邮箱推断
        hasPassword = u.hasPassword
    }

    private var isProfileSaveDisabled: Bool {
        guard let u = auth.currentUser else { return true }
        let nameValid = name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
        let origName = u.name
        let origLast = u.lastName ?? ""
        let ln = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = (name != origName) || (ln != origLast)
        return isLoading || !nameValid || !changed
    }

    private var isEmailSaveDisabled: Bool {
        guard let u = auth.currentUser else { return true }
        let origEmail = (u.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNewEmail = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return isLoading || !hasPassword || emailPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isValidEmail(trimmedNewEmail) || trimmedNewEmail == origEmail
    }

    private func saveProfile() async {
        do {
            isLoading = true
            let ln = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            let updated = try await repo.updateProfile(name: name, lastName: ln.isEmpty ? nil : ln)
            auth.currentUser = updated
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // 原 saveEmail 由验证码视图接管，保留空实现以兼容可能的调用
    private func saveEmail() async {}

    private func updatePassword() async {
        if hasPassword && currentPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = loc("请输入当前密码")
            return
        }
        guard newPasswordMeetsAllRules else { error = loc("至少 8 位且包含大小写字母、数字与符号。"); return }
        do {
            isLoading = true
            let ok = try await repo.updatePassword(current: currentPassword.isEmpty ? nil : currentPassword, new: newPassword)
            if ok {
                currentPassword = ""; newPassword = ""; hasPassword = true
                // 更新密码成功：先返回到个人资料页，再退出并弹出登录
                navBridge.dismiss()
                auth.restoreHint = loc("密码已更新，请重新登录")
                await Task.yield()
                auth.logout()
                Telemetry.shared.logEvent("account_password_update_success", parameters: nil)
            }
        } catch {
            if let ne = error as? NetworkError {
                switch ne {
                case .server(_, let msg):
                    self.error = msg
                default:
                    self.error = ne.localizedDescription
                }
            } else {
                self.error = error.localizedDescription
            }
            Telemetry.shared.logEvent("account_password_update_failure", parameters: [
                "error": (self.error ?? "")
            ])
            Telemetry.shared.record(error: error)
        }
        isLoading = false
    }

    private func deleteAccount() async {
        if hasPassword && deletePassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = loc("请输入当前密码")
            return
        }
        do {
            isLoading = true
            let ok = try await repo.deleteAccount(reason: deleteReason.isEmpty ? nil : deleteReason, details: deleteDetails.isEmpty ? nil : deleteDetails, currentPassword: deletePassword.isEmpty ? nil : deletePassword)
            if ok {
                // 删除账户不是“退出登录”：清除登录邮箱预填缓存，并弹出登录页
                UserDefaults.standard.removeObject(forKey: lastEmailKey)
                auth.logout()
                showDeleteSheet = false
                // 返回个人资料页
                navBridge.dismiss()
                // 触发登录弹窗
                auth.promptLoginAfterAccountDeletion = true
                Telemetry.shared.logEvent("account_delete_success", parameters: [
                    "has_password": hasPassword,
                    "reason": deleteReason.isEmpty ? "" : deleteReason,
                    "details_len": deleteDetails.trimmingCharacters(in: .whitespacesAndNewlines).count
                ])
            }
        } catch {
            if let ne = error as? NetworkError {
                switch ne {
                case .server(_, let msg):
                    self.error = msg
                default:
                    self.error = ne.localizedDescription
                }
            } else {
                self.error = error.localizedDescription
            }
            Telemetry.shared.logEvent("account_delete_failure", parameters: [
                "error": self.error ?? ""
            ])
            Telemetry.shared.record(error: error)
        }
        isLoading = false
    }

    private func createPassword() async {
        let p1 = createPw1.trimmingCharacters(in: .whitespacesAndNewlines)
        let p2 = createPw2.trimmingCharacters(in: .whitespacesAndNewlines)
        guard createPasswordMeetsAllRules else { error = loc("至少 8 位且包含大小写字母、数字与符号。"); return }
        guard p1 == p2 else { error = loc("两次输入的密码不一致"); return }
        do {
            isLoading = true
            let ok = try await repo.updatePassword(current: nil, new: p1)
            if ok {
                hasPassword = true
                createPw1 = ""
                createPw2 = ""
                // 创建密码成功后关闭弹窗
                showCreatePasswordSheet = false
                Telemetry.shared.logEvent("account_password_create_success", parameters: nil)
            }
        } catch {
            self.error = error.localizedDescription
            Telemetry.shared.logEvent("account_password_create_failure", parameters: [
                "error": error.localizedDescription
            ])
            Telemetry.shared.record(error: error)
        }
        isLoading = false
    }
}

// MARK: - 创建密码的合规项（与注册页一致）
extension AccountInfoView {
    private var createPasswordHasUppercase: Bool { createPw1.rangeOfCharacter(from: .uppercaseLetters) != nil }
    private var createPasswordHasLowercase: Bool { createPw1.rangeOfCharacter(from: .lowercaseLetters) != nil }
    private var createPasswordHasDigit: Bool { createPw1.rangeOfCharacter(from: .decimalDigits) != nil }
    private var createPasswordHasSymbol: Bool {
        let symbolSet = CharacterSet(charactersIn: "+-*/?:=!%$#")
        return createPw1.rangeOfCharacter(from: symbolSet) != nil
    }
    private var createPasswordMeetsAllRules: Bool {
        createPw1.count >= 8 && createPasswordHasUppercase && createPasswordHasLowercase && createPasswordHasDigit && createPasswordHasSymbol
    }
}

// 已统一改为横幅提示，移除 item 弹窗适配

#Preview("账户信息") { AccountInfoView().environmentObject(AuthManager()) }
