//
//  SimigoApp.swift
//  Simigo
//
//  Created by 李杰 on 2025/10/31.
//

import SwiftUI

@main
struct SimigoApp: App {
    @StateObject private var auth = AuthManager()
    @StateObject private var settings = SettingsManager()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var globalShowAuthSheet = false
    @State private var offlineBannerDismissed = false
    @State private var serviceBannerDismissed = false
    @StateObject private var navBridge = NavigationBridge()
    @StateObject private var bannerCenter = BannerCenter()
    private enum MainTab: Hashable { case market, myEsim, account }
    @State private var selectedTab: MainTab = .market
    @Environment(\.scenePhase) private var scenePhase
    // 防止因环境变化（如 locale）导致 .task 重复执行
    @State private var didRestoreSession = false
    @State private var didLoadSettings = false
    @State private var didLoadRemoteConfig = false
    @State private var didStartNetwork = false
    init() {
        // 在应用初始化阶段提前启动网络监控，确保状态变化能及时感知
        NetworkMonitor.shared.start()
        Telemetry.shared.setup()
        URLCache.shared.memoryCapacity = 64 * 1024 * 1024
        URLCache.shared.diskCapacity = 256 * 1024 * 1024
    }
    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                UIKitTabRootView()
            }
            .bannerCenterTopOverlay(center: bannerCenter)
            .environmentObject(auth)
            .environmentObject(settings)
            .environmentObject(networkMonitor)
            .environmentObject(navBridge)
            .environmentObject(bannerCenter)
            .environment(\.locale, settings.locale)
            .task { if !didRestoreSession { didRestoreSession = true; await auth.restoreSession() } }
            .task { if !didLoadSettings { didLoadSettings = true; await settings.loadSettings() } }
            .task { if !didLoadRemoteConfig { didLoadRemoteConfig = true; await AppConfig.loadRemoteConfig() } }
            .task {
                if !didStartNetwork {
                    didStartNetwork = true
                    networkMonitor.start()
                    networkMonitor.probeConnectivity()
                    networkMonitor.probeBackend()
                }
            }
            // 轻量预热：在线且缓存过期时预拉国家/地区列表到本地缓存，提升首次打开体验
            .task {
                guard NetworkMonitor.shared.isOnline else { return }
                let ttl = AppConfig.catalogCacheTTL
                let service = NetworkService()
                if let cached = CatalogCacheStore.shared.loadCountries(ttl: ttl) {
                    if cached.isExpired {
                        if let list: [Country] = try? await service.get("/catalog/countries") {
                            CatalogCacheStore.shared.saveCountries(list.map { Country(code: RegionCodeConverter.toAlpha2($0.code), name: $0.name) })
                        }
                    }
                } else {
                    if let list: [Country] = try? await service.get("/catalog/countries") {
                        CatalogCacheStore.shared.saveCountries(list.map { Country(code: RegionCodeConverter.toAlpha2($0.code), name: $0.name) })
                    }
                }
                if let cachedR = CatalogCacheStore.shared.loadRegions(ttl: ttl) {
                    if cachedR.isExpired {
                        if let list: [Region] = try? await service.get("/catalog/regions") {
                            CatalogCacheStore.shared.saveRegions(list.map { Region(code: $0.code.lowercased(), name: $0.name) })
                        }
                    }
                } else {
                    if let list: [Region] = try? await service.get("/catalog/regions") {
                        CatalogCacheStore.shared.saveRegions(list.map { Region(code: $0.code.lowercased(), name: $0.name) })
                    }
                }
            }
            .onChange(of: auth.currentUser) { _ in
                Task { await settings.syncProfileMergeWithServer() }
                Telemetry.shared.identify(auth.currentUser?.id)
            }
            // 全局监听：从已登录变为未登录时自动弹出登录弹窗
            .onChange(of: auth.currentUser) { oldValue, newValue in
                if oldValue != nil, newValue == nil, !auth.isRestoring {
                    globalShowAuthSheet = true
                }
            }
            // 全局监听：登录成功时自动关闭登录弹窗
            .onChange(of: auth.currentUser) { oldValue, newValue in
                if oldValue == nil, newValue != nil {
                    globalShowAuthSheet = false
                }
            }
            .onChange(of: networkMonitor.isOnline) { _, newValue in
                if !newValue && !offlineBannerDismissed {
                    bannerCenter.enqueue(
                        message: loc("当前处于离线状态，请检查网络连接"),
                        style: .warning,
                        source: "global",
                        priority: .high,
                        actionTitle: loc("重试"),
                        onAction: { offlineBannerDismissed = false; networkMonitor.probeConnectivity() },
                        onClose: { offlineBannerDismissed = true }
                    )
                }
                if newValue {
                    withAnimation(.easeInOut(duration: 0.25)) { offlineBannerDismissed = false }
                    bannerCenter.clear(source: "global")
                }
            }
            .onChange(of: networkMonitor.backendOnline) { _, newValue in
                if !newValue && !serviceBannerDismissed {
                    bannerCenter.enqueue(
                        message: loc("服务暂时不可用，请稍后重试"),
                        style: .error,
                        source: "global",
                        priority: .high,
                        actionTitle: loc("刷新"),
                        onAction: { serviceBannerDismissed = false; networkMonitor.probeBackend() },
                        onClose: { serviceBannerDismissed = true }
                    )
                }
                if newValue {
                    withAnimation(.easeInOut(duration: 0.25)) { serviceBannerDismissed = false }
                    bannerCenter.clear(source: "global")
                    Task { await AppConfig.loadRemoteConfig() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sessionExpired).receive(on: RunLoop.main)) { note in
                let reason = note.userInfo?["reason"] as? String
                auth.handleSessionExpired(reason: reason)
                navBridge.popToRoot()
                globalShowAuthSheet = true
            }
            // 回到前台时主动探测一次连通性，缓解模拟器/门户网络导致的 NWPathMonitor 恢复延迟
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    networkMonitor.probeConnectivity()
                    networkMonitor.probeBackend()
                }
            }
            .sheet(isPresented: $globalShowAuthSheet) {
                UIKitNavHost(root: AuthView(auth: auth))
                    .environmentObject(auth)
                    .environmentObject(settings)
                    .environmentObject(networkMonitor)
                    .environmentObject(bannerCenter)
                    
            }
            .onOpenURL { url in
                PaymentCallbackHandler.handle(url: url)
            }
            .onAppear {
                Telemetry.shared.setUserProperty(settings.languageCode, name: "app_language")
                Telemetry.shared.setUserProperty(settings.currencyCode, name: "currency")
            }
            .onChange(of: settings.languageCode) { _, newValue in
                Telemetry.shared.setUserProperty(newValue, name: "app_language")
            }
            .onChange(of: settings.currencyCode) { _, newValue in
                Telemetry.shared.setUserProperty(newValue, name: "currency")
            }
        }
    }

    private func tabCode(for tab: MainTab) -> String {
        switch tab {
        case .market: return "market"
        case .myEsim: return "my_esim"
        case .account: return "account"
        }
    }
}
