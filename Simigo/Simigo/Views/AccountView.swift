import SwiftUI

private enum AccountDestination: Hashable {
    case orders
    case support
    case auth
    case more
    case privacy
    case terms
    case about
}

struct AccountView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var bannerCenter: BannerCenter
    @State private var showSupport = false
    @State private var showAuthSheet = false
    @State private var showRestoreBanner = false
    @State private var showAppleContinue = false
    @State private var isInitializingMappings = false
    @State private var showInitBanner = false
    @State private var initMessage = ""
    @State private var lastInitSuccess = true
    @State private var shareText = loc("我正在使用 Simigo eSIM 应用，快来试试吧！")
    private let appStoreURL = URL(string: "https://apps.apple.com/app/id000000")!
    private let websiteURL = URL(string: "https://example.com")!
    @State private var showLogoutConfirm = false
    
    var body: some View {
        List {
                // 启动时：恢复会话占位，避免闪烁未登录文案
                if auth.isRestoring {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(loc("正在恢复会话…"))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                // 顶部：未登录显示 登录/注册 两个按钮
                if !auth.isLoggedIn && !auth.isRestoring {
                    Section {
                        Button {
                            Telemetry.shared.logEvent("account_auth_sheet_open", parameters: nil)
                            showAuthSheet = true
                        } label: {
                            Text(loc("登录 / 注册"))
                        }
                    }
                }

                // 登录后：个人信息卡片（账号信息、订单）
                if auth.isLoggedIn && !auth.isRestoring {
                    Section {
                        Button {
                            navBridge.push(AccountInfoView(), auth: auth, settings: settings, network: networkMonitor, title: loc("账号信息"))
                        } label: {
                            Label(loc("账号信息"), systemImage: "person.crop.circle")
                        }
                        Button {
                            navBridge.push(OrdersListView(), auth: auth, settings: settings, network: networkMonitor, title: loc("订单"))
                        } label: {
                            Label(loc("订单"), systemImage: "doc.text")
                        }
                        
                        Button {
                            guard networkMonitor.isOnline, !isInitializingMappings else { return }
                            isInitializingMappings = true
                            Telemetry.shared.logEvent("account_init_mappings_click", parameters: nil)
                            Task {
                            let repo = HTTPUpstreamOrderRepository()
                            let rid = UUID().uuidString
                            do {
                                let res = try await repo.initMappingsForCurrentUser(requestId: rid)
                                initMessage = String(format: loc("订单归属修复完成：已检查 %d，修复 %d"), res.checked, res.updated)
                                lastInitSuccess = true
                                Telemetry.shared.logEvent("account_init_mappings_done", parameters: ["checked": res.checked, "updated": res.updated])
                                withAnimation(.easeInOut(duration: 0.25)) { showInitBanner = true }
                            } catch {
                                initMessage = String(format: loc("订单归属修复失败：%@"), error.localizedDescription)
                                lastInitSuccess = false
                                Telemetry.shared.record(error: error)
                                withAnimation(.easeInOut(duration: 0.25)) { showInitBanner = true }
                            }
                            isInitializingMappings = false
                        }
                        
                    } label: {
                        Label(loc("修复订单归属"), systemImage: "hammer")
                        }
                        .disabled(!networkMonitor.isOnline || isInitializingMappings)
                    }
                }

                // 语言/货币设置卡片（两种状态都展示）
                Section {
                    Button {
                        navBridge.push(LanguageSettingsView(), auth: auth, settings: settings, network: networkMonitor, title: loc("语言"))
                    } label: {
                        Text(String(format: loc("语言：%@"), settings.languageDisplayName))
                    }

                    Button {
                        navBridge.push(CurrencySettingsView(), auth: auth, settings: settings, network: networkMonitor, title: loc("货币"))
                    } label: {
                        Text(String(format: loc("货币：%@"), settings.currencyDisplayName))
                    }

                    Toggle(loc("允许匿名使用统计"), isOn: $settings.analyticsOptIn)
                    Toggle(loc("允许诊断与崩溃日志"), isOn: $settings.crashOptIn)

                    Button {
                        navBridge.push(MoreInfoView(), auth: auth, settings: settings, network: networkMonitor, title: loc("更多信息"))
                    } label: {
                        Text(loc("更多信息"))
                    }
                }

                // 分享卡片
                Section {
                    ShareLink(item: shareText) { HStack { Text(loc("与朋友分享")); Spacer(); Image(systemName: "arrow.up.right") } }
                        .simultaneousGesture(TapGesture().onEnded {
                            Telemetry.shared.logEventDeferred("account_share_click", parameters: [
                                "text_len": shareText.count
                            ])
                        })
                    Link(destination: appStoreURL) { Text(loc("为应用评分")) }
                        .simultaneousGesture(TapGesture().onEnded {
                            Telemetry.shared.logEventDeferred("account_rate_open", parameters: [
                                "url": appStoreURL.absoluteString
                            ])
                        })
                }

                // 更多信息已移动到设置分区下的单个入口

                // 退出放在列表底部
                if auth.isLoggedIn && !auth.isRestoring {
                    Section {
                        Button(loc("退出")) { Telemetry.shared.logEvent("auth_logout_click", parameters: nil); showLogoutConfirm = true }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .tint(.red)
                    }
                }

                
            }
            
            .listStyle(.insetGrouped)
            
            // 悬浮客服按钮（右下角）
            .overlay(alignment: .bottomTrailing) {
                Button {
                    Telemetry.shared.logEvent("support_open_from_account_button", parameters: nil)
                    showSupport = true
                } label: {
                    ZStack {
                        Circle().fill(Color.accentColor).frame(width: 56, height: 56)
                        Image(systemName: "message")
                            .foregroundColor(.white)
                    }
                }
                .accessibilityIdentifier("support.fab")
                .padding(16)
            }
            .sheet(isPresented: $showSupport) { UIKitNavHost(root: SupportView()) }
            .sheet(isPresented: $showAuthSheet) { UIKitNavHost(root: AuthView(auth: auth)) }
            .alert(loc("确认退出登录？"), isPresented: $showLogoutConfirm) {
                Button(loc("取消"), role: .cancel) {}
                Button(loc("退出"), role: .destructive) { auth.logout() }
            }
            
            .sheet(isPresented: $showAppleContinue) { UIKitNavHost(root: AppleContinueView()) }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    Telemetry.shared.logEvent("app_tab_change", parameters: ["tab": "account"]) 
                }
            }
            .onChange(of: auth.currentUser) { _, newValue in
                // 登录成功：关闭登录弹窗（弹窗的打开由应用根层统一处理）
                if let u = newValue {
                    showAuthSheet = false
                    // 仅在 Apple 登录（通常无密码）且资料不完整时，弹出 Apple 继续页
                    let isAppleLogin = (u.hasPassword == false)
                    let incompleteProfile = u.name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || u.lastName == nil
                    if isAppleLogin && incompleteProfile { showAppleContinue = true }
                    if networkMonitor.isOnline && !isInitializingMappings {
                        isInitializingMappings = true
                        Task {
                            let repo = HTTPUpstreamOrderRepository()
                            let rid = UUID().uuidString
                            do {
                                let res = try await repo.initMappingsForCurrentUser(requestId: rid)
                                initMessage = String(format: loc("订单归属修复完成：已检查 %d，修复 %d"), res.checked, res.updated)
                                lastInitSuccess = true
                                withAnimation(.easeInOut(duration: 0.25)) { showInitBanner = true }
                            } catch {
                                initMessage = String(format: loc("订单归属修复失败：%@"), error.localizedDescription)
                                lastInitSuccess = false
                                withAnimation(.easeInOut(duration: 0.25)) { showInitBanner = true }
                            }
                            isInitializingMappings = false
                        }
                    }
                }
            }
            .onChange(of: auth.restoreHint) { _, newValue in
                if showRestoreBanner, let hint = newValue, !hint.isEmpty, !auth.isRestoring, !auth.isLoggedIn {
                    bannerCenter.enqueue(message: hint, style: .error, source: "account_view", onClose: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showRestoreBanner = false
                            auth.restoreHint = nil
                        }
                    })
                }
            }
            .onChange(of: showInitBanner) { _, newValue in
                if newValue, !initMessage.isEmpty {
                    bannerCenter.enqueue(message: initMessage, style: (lastInitSuccess ? .success : .error), source: "account_view", onClose: {
                        withAnimation(.easeInOut(duration: 0.25)) { showInitBanner = false }
                    })
                }
            }
            // 删除账号后：自动弹出登录/注册弹窗
            .onChange(of: auth.promptLoginAfterAccountDeletion) { _, newValue in
                if newValue {
                    showAuthSheet = true
                    // 重置触发标记，避免重复弹出
                    auth.promptLoginAfterAccountDeletion = false
                }
            }
            // 提示变化时：显示横幅并在5秒后自动消失（若期间文案未变化）
            .onChange(of: auth.restoreHint) { _, newValue in
                if let msg = newValue, !msg.isEmpty {
                    withAnimation(.easeInOut(duration: 0.25)) { showRestoreBanner = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if showRestoreBanner && auth.restoreHint == msg {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showRestoreBanner = false
                                auth.restoreHint = nil
                            }
                        }
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) { showRestoreBanner = false }
                }
            }
            .onChange(of: auth.promptLoginAfterAccountDeletion) { _, newValue in
                if newValue {
                    Telemetry.shared.logEvent("auth_prompt_login_after_account_deletion", parameters: nil)
                }
            }
            .onChange(of: settings.analyticsOptIn) { _, newValue in
                Telemetry.shared.logEvent("settings_analytics_optin_change", parameters: [
                    "enabled": newValue
                ])
            }
            .onChange(of: settings.crashOptIn) { _, newValue in
                Telemetry.shared.logEvent("settings_crash_optin_change", parameters: [
                    "enabled": newValue
                ])
            }
        }
    }


#Preview("个人资料") {
    AccountView()
        .environmentObject(AuthManager())
        .environmentObject(SettingsManager())
        .environmentObject(NetworkMonitor.shared)
}
