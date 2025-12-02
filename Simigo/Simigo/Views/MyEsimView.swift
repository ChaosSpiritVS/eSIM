import SwiftUI

struct MyEsimView: View {
    @StateObject private var viewModel = OrdersListViewModel()
    @State private var showSupport = false
    @State private var showAuthSheet = false
    @State private var showErrorBanner = false
    
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var bannerCenter: BannerCenter

    private var displayedOrders: [Order] { viewModel.orders }

    var body: some View {
        List {
                Section(header: Text(loc("我的套餐"))) {
                    if !auth.isLoggedIn {
                        VStack(spacing: 12) {
                            Text(loc("未登录")).font(.headline)
                            Button(loc("登录 / 注册")) { showAuthSheet = true }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else if viewModel.isLoading {
                        ForEach(0..<6, id: \.self) { _ in OrderRowSkeleton() }
                    } else {
                        if displayedOrders.isEmpty {
                            Text(loc("暂无套餐")).foregroundColor(.secondary)
                        } else {
                            Text(String(format: loc("共 %d 个套餐"), displayedOrders.count))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        ForEach(displayedOrders) { order in
                            Button {
                                navBridge.push(EsimDetailView(orderId: order.id), auth: auth, settings: settings, network: networkMonitor, title: (order.bundleName ?? order.bundleMarketingName ?? loc("我的 eSIM")))
                            } label: {
                                HStack {
                                    Group {
                                        let code2 = RegionCodeConverter.toAlpha2(order.countryCode ?? "")
                                        if code2.isEmpty {
                                            Image(systemName: "globe").foregroundColor(.green).font(.largeTitle)
                                        } else {
                                            Text(countryFlag(code2)).font(.largeTitle)
                                        }
                                    }
                                    .frame(width: 44)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(order.bundleName ?? order.bundleMarketingName ?? loc("套餐")).font(.headline)
                                        Text(String(format: loc("创建日期：%@"), formatDate(order.createdAt)))
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(PriceFormatter.string(amount: order.amount, currencyCode: settings.currencyCode.uppercased()))
                                        .font(.headline)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if viewModel.hasMore {
                            HStack {
                                Spacer()
                                Button {
                                    Telemetry.shared.logEvent("my_esim_load_more_click", parameters: ["page_size": viewModel.pageSize])
                                    viewModel.loadMore()
                                } label: {
                                    Text(viewModel.isLoadingMore ? loc("加载中...") : loc("加载更多"))
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 8)
                                }
                                .background(Color(UIColor.systemGray5))
                                .clipShape(Capsule())
                                .disabled(viewModel.isLoadingMore)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 96) }
            
            .overlay(alignment: .bottomTrailing) {
                Button {
                    Telemetry.shared.logEvent("support_open_from_my_esim_button", parameters: nil)
                    showSupport = true
                } label: {
                    ZStack {
                        Circle().fill(Color.accentColor).frame(width: 56, height: 56)
                        Image(systemName: "message").foregroundColor(.white)
                    }
                }
                .padding(16)
            }
            .background(Color(UIColor.systemGroupedBackground))
        .onAppear {
            viewModel.setAuth(auth)
            viewModel.setPageSize(10)
            DispatchQueue.main.async {
                if auth.isLoggedIn {
                    if viewModel.orders.isEmpty { viewModel.load() }
                    else { viewModel.load(preservePagination: true) }
                } else {
                    viewModel.orders = []
                    viewModel.hasMore = false
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Telemetry.shared.logEvent("app_tab_change", parameters: ["tab": "my_esim"]) 
                Telemetry.shared.logEvent("my_esim_open", parameters: ["page_size": 10])
            }
        }
        .sheet(isPresented: $showAuthSheet) { UIKitNavHost(root: AuthView(auth: auth)) }
        .onChange(of: auth.currentUser) { _, newValue in
            if newValue != nil && showAuthSheet {
                showAuthSheet = false
                viewModel.load()
            }
        }
        .onChange(of: viewModel.error) { _, newValue in
            if let msg = newValue, !msg.isEmpty {
                bannerCenter.enqueue(message: msg, style: .error, source: "my_esim", actionTitle: loc("重试"), onAction: { viewModel.load(preservePagination: true) }, onClose: { withAnimation(.easeInOut(duration: 0.25)) { viewModel.error = nil } })
            }
        }
        .onChange(of: networkMonitor.isOnline) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.25)) { showErrorBanner = false; viewModel.error = nil }
                viewModel.load(preservePagination: true)
            }
        }
        .onChange(of: networkMonitor.backendOnline) { _, newValue in
            if newValue { viewModel.load(preservePagination: true) }
        }
        .sheet(isPresented: $showSupport) { UIKitNavHost(root: SupportView()) }
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    private func shortId(_ id: String) -> String {
        let clean = id.replacingOccurrences(of: "-", with: "").uppercased()
        let n = min(6, clean.count)
        let start = clean.startIndex
        let end = clean.index(start, offsetBy: n)
        return String(clean[start..<end])
    }

    
    
}

#Preview("我的 eSIM") { MyEsimView() }
