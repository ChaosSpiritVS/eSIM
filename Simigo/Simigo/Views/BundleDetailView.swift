import SwiftUI
import CoreTelephony
import UIKit

struct BundleDetailView: View {
    @StateObject private var viewModel: BundleDetailViewModel
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var bannerCenter: BannerCenter
    @State private var navigateToCheckout = false
    @State private var showAuthSheet = false
    @State private var showErrorBanner: Bool = false

    init(bundle: ESIMBundle) {
        _viewModel = StateObject(wrappedValue: BundleDetailViewModel(bundle: bundle))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Group {
                        if viewModel.bundle.countryCode.isEmpty {
                            Image(systemName: "globe").foregroundColor(.green).font(.largeTitle)
                        } else {
                            Text(countryFlag(viewModel.bundle.countryCode)).font(.largeTitle)
                        }
                    }
                    .frame(width: 44)
                    VStack(alignment: .leading) {
                        Text(viewModel.bundle.name).font(.title2).bold()
                        Text(String(format: loc("%@ • 有效期 %d 天"), viewModel.bundle.dataAmount, viewModel.bundle.validityDays))
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            TagBadge(text: serviceTypeLabel, color: .blue)
                            if viewModel.bundle.unlimited == true { TagBadge(text: loc("不限量"), color: .purple) }
                            if let active = viewModel.bundle.isActive {
                                if active { TagBadge(text: loc("上架中"), color: .green) } else { TagBadge(text: loc("已下架"), color: .red) }
                            }
                        }
                    }
                    Spacer()
                }

                Text(loc("价格：") + PriceFormatter.string(amount: viewModel.bundle.price, currencyCode: viewModel.bundle.currency))
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(loc("此设备是否支持？"))
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: deviceSupportsESIM ? "checkmark.circle" : "xmark.circle")
                            .foregroundColor(deviceSupportsESIM ? .green : .red)
                        Text(deviceSupportsESIM ? loc("是") : loc("否"))
                            .foregroundColor(deviceSupportsESIM ? .green : .red)
                    }
                }
                .padding(12)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if let tags = viewModel.bundle.bundleTag, !tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc("标签")).font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], spacing: 6) {
                            ForEach(tags, id: \.self) { t in TagBadge(text: t, color: .gray) }
                        }
                    }
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Divider()
                if shouldShowDescription {
                    Text(loc("说明")).font(.headline)
                    Text(bundleDescription)
                        .foregroundColor(.secondary)
                }

                // 网络与覆盖（加载骨架/文本展示，支持展开）
                if viewModel.isLoadingNetworks {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc("网络与覆盖")).font(.headline)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4).frame(height: 12)
                            RoundedRectangle(cornerRadius: 4).frame(width: 120, height: 12)
                        }
                        .foregroundStyle(.secondary.opacity(0.25))
                        .redacted(reason: .placeholder)
                        .shimmer(active: true)
                        .accessibilityHidden(true)
                    }
                } else if let text = coverageText {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc("网络与覆盖")).font(.headline)
                        Text(text)
                            .foregroundColor(.secondary)
                            .lineLimit(coverageExpanded ? nil : 4)
                        if let note = viewModel.bundle.coverageNote { Text(note).foregroundColor(.secondary) }
                        if shouldShowCoverageExpandButton {
                            Button(coverageExpanded ? loc("收起") : loc("展开更多")) { coverageExpanded.toggle() }
                                .font(.caption)
                        }
                    }
                }

                if let hotspot = viewModel.bundle.hotspotSupported {
                    HStack {
                        Image(systemName: hotspot ? "personalhotspot" : "wifi.slash")
                            .foregroundColor(hotspot ? .green : .secondary)
                        Text(hotspot ? loc("支持热点共享") : loc("不支持热点共享"))
                            .foregroundColor(.secondary)
                    }
                }

                if let urlStr = viewModel.bundle.termsURL, let url = URL(string: urlStr) {
                    Link(loc("查看服务条款"), destination: url)
                        .font(.footnote)
                        .simultaneousGesture(TapGesture().onEnded { Telemetry.shared.logEventDeferred("bundle_terms_open", parameters: ["bundle_id": viewModel.bundle.id, "url": urlStr]) })
                }

                Text(loc("常见问题解答")).font(.headline)

                Link(loc("打开帮助中心"), destination: URL(string: "https://example.com/help")!)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.accentColor)
                    .simultaneousGesture(TapGesture().onEnded {
                        Telemetry.shared.logEventDeferred("support_help_open", parameters: [
                            "url": "https://example.com/help",
                            "bundle_id": viewModel.bundle.id
                        ])
                    })

                FAQItem(title: loc("应该什么时候购买 eSIM?"), content: loc("您可以在出行前购买 eSIM。有效期不会因为提前购买而开始，只有当首次连接到覆盖区域内的网络时才开始计算。购买前请以套餐详情中的有效期与覆盖说明为准。"))
                FAQItem(title: loc("应该什么时候安装 eSIM?"), content: loc("可以在出发前或到达后安装。若不在覆盖范围内安装，安装成功但不会激活；到达覆盖区域并连接移动网络后即可开始使用。请确保设备支持 eSIM 且网络已解锁，安装二维码与步骤可在我的eSIM详情中查看。"))
                FAQItem(title: loc("可以重复使用我的 eSIM 吗?"), content: loc("当前套餐不支持续费。流量用尽或到期后需要重新购买新的套餐；已安装的 eSIM 不可复用到新的订单。"))

                Text(loc("支持")).font(.headline)
                Text(loc("需要帮助？我们提供全天候多语言支持。"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Button {
                    showSupportSheet = true
                    Telemetry.shared.logEvent("bundle_support_open", parameters: ["bundle_id": viewModel.bundle.id])
                } label: {
                    Text(loc("联系支持团队"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.accentColor)
                }
                

                Spacer(minLength: 0)
                
            }
            .padding()
        }
        
        
        
        .onAppear {
            if AppConfig.useAliasAPI { viewModel.loadNetworks() }
            Telemetry.shared.logEvent("bundle_detail_open", parameters: [
                "bundle_id": viewModel.bundle.id
            ])
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 0.5)
                Button {
                    showInfoSheet = true
                    Telemetry.shared.logEvent("bundle_info_open", parameters: ["bundle_id": viewModel.bundle.id])
                } label: {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text(loc("套餐详细信息"))
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
                Text(loc("完成订单，即表示您确认目标设备支持 eSIM 且网络已解锁。"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                HStack {
                    Text(loc("总计")).font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Text(PriceFormatter.string(amount: viewModel.bundle.price, currencyCode: viewModel.bundle.currency)).font(.title3).bold()
                }
                if viewModel.bundle.isActive == false {
                    Text(loc("该套餐已下架，暂不可购买。"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Button {
                    Telemetry.shared.logEvent("bundle_buy_click", parameters: [
                        "bundle_id": viewModel.bundle.id,
                        "is_logged_in": auth.isLoggedIn
                    ])
                    if auth.isLoggedIn {
                        navBridge.push(CheckoutView(bundle: viewModel.bundle, auth: auth), auth: auth, settings: settings, network: networkMonitor, title: loc("安全结账"))
                    } else {
                        showAuthSheet = true
                    }
                } label: {
                    Text(loc("立即购买")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(!networkMonitor.isOnline)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .clipShape(TopRoundedShape(radius: 20))
            .overlay(TopRoundedShape(radius: 20).stroke(Color.black.opacity(0.08), lineWidth: 0.6))
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: -2)
        }
        
        .sheet(isPresented: $showAuthSheet) { UIKitNavHost(root: AuthView(auth: auth)) }
        .sheet(isPresented: $showInfoSheet) { UIKitNavHost(root: BundleInfoSheetView()) }
        .sheet(isPresented: $showSupportSheet) { UIKitNavHost(root: SupportView()) }
        .onChange(of: auth.currentUser) { _, newValue in
            if newValue != nil && showAuthSheet {
                showAuthSheet = false
                navBridge.push(CheckoutView(bundle: viewModel.bundle, auth: auth), auth: auth, settings: settings, network: networkMonitor, title: loc("安全结账"))
            }
        }
        // 在线恢复：别名接口下网络信息自动刷新
        .onChange(of: networkMonitor.isOnline) { _, newValue in
            if newValue && AppConfig.useAliasAPI && !viewModel.isLoadingNetworks {
                viewModel.loadNetworks()
                withAnimation(.easeInOut(duration: 0.25)) { showErrorBanner = false; viewModel.error = nil }
            }
        }
        .onChange(of: networkMonitor.backendOnline) { _, newValue in
            if newValue && AppConfig.useAliasAPI && !viewModel.isLoadingNetworks {
                viewModel.loadNetworks()
            }
        }
        .onChange(of: viewModel.error) { _, newValue in
            if let msg = newValue, !msg.isEmpty {
                bannerCenter.enqueue(message: msg, style: .error, source: "bundle_detail", actionTitle: loc("重试"), onAction: { if AppConfig.useAliasAPI { viewModel.loadNetworks() } }, onClose: { withAnimation(.easeInOut(duration: 0.25)) { viewModel.error = nil } })
            }
        }
    }

    private var bundleDescription: String {
        if let desc = viewModel.bundle.description, !desc.isEmpty { return desc }
        return loc("该套餐支持即时激活，覆盖指定国家/地区。下单后将获得安装二维码和使用指南。")
    }

    private var deviceSupportsESIM: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let provision = CTCellularPlanProvisioning()
        return provision.supportsCellularPlan()
        #endif
    }

    private var shouldShowDescription: Bool {
        if let desc = viewModel.bundle.description, !desc.isEmpty {
            return desc != viewModel.bundle.name
        }
        return false
    }

    @State private var showInfoSheet = false
    @State private var showSupportSheet = false
    @State private var coverageExpanded = false
    private var coverageText: String? {
        let joiner = ", "
        if !viewModel.networks.isEmpty { return viewModel.networks.joined(separator: joiner) }
        if let networks = viewModel.bundle.supportedNetworks, !networks.isEmpty { return networks.joined(separator: joiner) }
        return nil
    }
    private var shouldShowCoverageExpandButton: Bool {
        guard let text = coverageText else { return false }
        let items = text.split(whereSeparator: { $0 == "，" || $0 == "," })
        return text.count > 160 || items.count > 8
    }
    private var serviceTypeLabel: String {
        if let t = viewModel.bundle.serviceType?.lowercased() {
            if t == "data" { return loc("数据") }
            if t == "voice" { return loc("语音") }
            if t == "sms" { return loc("短信") }
        }
        return loc("数据")
    }
}

struct BundleInfoSheetView: View {
    @EnvironmentObject private var navBridge: NavigationBridge
    var body: some View {
        List {
            Section(header: Text(loc("有效期政策")).font(.headline)) {
                Text(loc("当 eSIM 连接到其覆盖范围内的移动网络时，有限期开始计算。如果您在覆盖范围以外安装 eSIM，则可以在到达后连接到网络。"))
                    .foregroundColor(.secondary)
            }
            Section(header: Text(loc("IP 路由")).font(.headline)) {
                Text(loc("您可能会注意到此 eSIM 有一个备用 IP 地址。这不会影响您使用的流量。"))
                    .foregroundColor(.secondary)
            }
            Section(header: Text(loc("续费/充值")).font(.headline)) {
                Text(loc("当前套餐续费功能暂未开放。流量用完或到期后，请重新购买新的套餐以继续使用。"))
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(loc("取消")) { navBridge.dismiss() } } }
    }
}

private struct TagBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

private struct FAQItem: View {
    let title: String
    let content: String
    @State private var expanded: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline).bold()
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut) { expanded.toggle() } }
            if expanded {
                Text(content)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TopRoundedShape: Shape {
    var radius: CGFloat = 16
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

#Preview("详情") {
    BundleDetailView(bundle: ESIMBundle(
        id: "hk-1",
        name: "中国香港",
        countryCode: "HK",
        price: 3.50,
        currency: "GBP",
        dataAmount: "1GB",
        validityDays: 7,
        description: nil,
        supportedNetworks: ["4G/LTE"],
        hotspotSupported: true,
        coverageNote: nil,
        termsURL: nil
    ))
    .environmentObject(AuthManager())
}
