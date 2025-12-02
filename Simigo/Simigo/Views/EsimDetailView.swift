import SwiftUI

struct EsimDetailView: View {
    @StateObject private var viewModel: OrderDetailViewModel
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var navBridge: NavigationBridge
    @State private var hasLoadedOnce: Bool = false
    @State private var showCopiedAlert = false
    @State private var showCopiedSmdpAlert = false

    let showOrderEntry: Bool
    init(orderId: String, showOrderEntry: Bool = true) {
        _viewModel = StateObject(wrappedValue: OrderDetailViewModel(orderId: orderId))
        self.showOrderEntry = showOrderEntry
    }

    var body: some View {
        List {
            bundleSummarySection()
            usageSection()
            installationSection()
            if showOrderEntry { entrySection() }
        }
        .listStyle(.insetGrouped)
        
        .onAppear {
            if !hasLoadedOnce {
                viewModel.load()
                hasLoadedOnce = true
            }
            Telemetry.shared.logEvent("esim_detail_open", parameters: [
                "order_id": viewModel.order?.id ?? viewModel.orderId
            ])
        }
        .alert(loc("已复制激活码"), isPresented: $showCopiedAlert) { Button(loc("好的")) {} }
        .alert(loc("已复制 SM-DP+ 地址"), isPresented: $showCopiedSmdpAlert) { Button(loc("好的")) {} }
    }

    @ViewBuilder
    private func bundleSummarySection() -> some View {
        Section(header: Text(loc("套餐摘要"))) {
            if viewModel.isLoadingBundle && viewModel.bundle == nil {
                Text(loc("请稍候…"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            if let b = viewModel.bundle {
                Group {
                    HStack { Text(loc("套餐名称")); Spacer(); Text(b.name).foregroundColor(.secondary) }
                    HStack { Text(loc("流量")); Spacer(); Text(b.dataAmount).foregroundColor(.secondary) }
                    HStack { Text(loc("有效期")); Spacer(); Text(String(format: loc("%d 天"), b.validityDays)).foregroundColor(.secondary) }
                    HStack {
                        Text(loc("价格"));
                        Spacer();
                        let amt = viewModel.order?.amount ?? b.price
                        Text(PriceFormatter.string(amount: amt, currencyCode: settings.currencyCode.uppercased())).foregroundColor(.secondary)
                    }
                    HStack { Text(loc("国家/地区")); Spacer(); Text(viewModel.order?.countryName ?? viewModel.order?.countryCode ?? "-").foregroundColor(.secondary) }
                    if let code = viewModel.order?.bundleId, !code.isEmpty {
                        HStack { Text(loc("套餐代码")); Spacer(); Text(code).foregroundColor(.secondary) }
                    }
                }
                .transition(.opacity)
            } else if let order = viewModel.order {
                Group {
                    HStack { Text(loc("套餐名称")); Spacer(); Text(order.bundleName ?? order.bundleMarketingName ?? "-").foregroundColor(.secondary) }
                    if let exp = order.bundleExpiryDate ?? order.expiryDate {
                        HStack { Text(loc("到期时间")); Spacer(); Text(formatDate(exp)).foregroundColor(.secondary) }
                    }
                    if let name = order.countryName ?? order.countryCode, !name.isEmpty {
                        HStack { Text(loc("国家/地区")); Spacer(); Text(name).foregroundColor(.secondary) }
                    }
                    if !order.bundleId.isEmpty {
                        HStack { Text(loc("套餐代码")); Spacer(); Text(order.bundleId).foregroundColor(.secondary) }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func entrySection() -> some View {
        Section(header: Text(loc("订单"))) {
            Button {
                let short = String(viewModel.orderId.replacingOccurrences(of: "-", with: "").uppercased().prefix(6))
                navBridge.push(OrderDetailView(orderId: viewModel.orderId, showEsimEntry: false), auth: auth, settings: settings, network: networkMonitor, title: String(format: loc("订单 #%@"), String(short)))
            } label: {
                HStack { Image(systemName: "doc.text"); Text(loc("查看订单详情")); Spacer() }
            }
        }
    }

    @ViewBuilder
    private func usageSection() -> some View {
        Section(header: Text(loc("使用情况"))) {
            if viewModel.isLoadingUsage {
                OrderUsageSkeleton()
                    .transition(.opacity)
            } else if let usage = viewModel.usage {
                Group {
                    if let allocated = usage.allocatedMB {
                        HStack { Text(loc("总流量")); Spacer(); Text(formatMB(allocated)).foregroundColor(.secondary) }
                    }
                    if let used = usage.usedMB {
                        HStack { Text(loc("已用流量")); Spacer(); Text(formatMB(used)).foregroundColor(.secondary) }
                    }
                    HStack { Text(loc("剩余流量")); Spacer(); Text(formatMB(usage.remainingMB)).foregroundColor(.secondary) }
                    if let expires = usage.expiresAt {
                        HStack { Text(loc("到期时间")); Spacer(); Text(formatDate(expires)).foregroundColor(.secondary) }
                    }
                    HStack { Text(loc("最后更新")); Spacer(); Text(formatDateTime(usage.lastUpdated)).foregroundColor(.secondary) }
                    Button(loc("刷新用量")) {
                        Telemetry.shared.logEvent("order_usage_refresh_click", parameters: [
                            "order_id": viewModel.order?.id ?? viewModel.orderId
                        ])
                        viewModel.refreshUsage()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!networkMonitor.isOnline)
                }
                .transition(.opacity)
            } else {
                Text(loc("暂未获取到用量信息"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func installationSection() -> some View {
        Section(header: Text(loc("安装信息"))) {
            if viewModel.isLoading {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 8) {
                        QRCodeSkeleton()
                        RoundedRectangle(cornerRadius: 4)
                            .frame(width: 180, height: 10)
                            .foregroundStyle(.secondary.opacity(0.25))
                            .redacted(reason: .placeholder)
                            .shimmer(active: true)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            RoundedRectangle(cornerRadius: 4).frame(width: 60, height: 12)
                            Spacer()
                            RoundedRectangle(cornerRadius: 4).frame(width: 120, height: 14)
                        }
                        RoundedRectangle(cornerRadius: 8).frame(width: 120, height: 30)
                    }
                    .foregroundStyle(.secondary.opacity(0.25))
                    .redacted(reason: .placeholder)
                    .shimmer(active: true)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            RoundedRectangle(cornerRadius: 4).frame(width: 100, height: 12)
                            Spacer()
                            RoundedRectangle(cornerRadius: 4).frame(width: 160, height: 12)
                        }
                        RoundedRectangle(cornerRadius: 8).frame(width: 150, height: 30)
                    }
                    .foregroundStyle(.secondary.opacity(0.25))
                    .redacted(reason: .placeholder)
                    .shimmer(active: true)
                    .accessibilityHidden(true)
                    InstallationStepsSkeleton()
                    DownloadConfigSkeleton()
                    RoundedRectangle(cornerRadius: 4)
                        .frame(width: 260, height: 10)
                        .foregroundStyle(.secondary.opacity(0.25))
                        .redacted(reason: .placeholder)
                        .shimmer(active: true)
                        .accessibilityHidden(true)
                }
                .transition(.opacity)
            } else if let order = viewModel.order, let installation = order.installation {
                VStack(alignment: .leading, spacing: 12) {
                    if let urlStr = installation.qrCodeURL, let url = URL(string: urlStr) {
                        VStack(spacing: 8) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    QRCodeSkeleton()
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 180, height: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .shadow(radius: 4)
                                case .failure:
                                    if let local = localQRCode(from: installation) {
                                        Image(uiImage: local)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 180, height: 180)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .shadow(radius: 4)
                                    } else {
                                        Image(systemName: "qrcode")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 120, height: 120)
                                            .foregroundColor(.secondary)
                                    }
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            Text(loc("扫描二维码以安装 eSIM"))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    } else if let local = localQRCode(from: installation) {
                        VStack(spacing: 8) {
                            Image(uiImage: local)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 180, height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(radius: 4)
                            Text(loc("扫描二维码以安装 eSIM"))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    if let code = installation.activationCode, !code.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(loc("激活码"))
                                Spacer()
                                Text(code)
                                    .font(.body)
                                    .monospaced()
                                    .textSelection(.enabled)
                                    .foregroundColor(.secondary)
                            }
                            Button(loc("复制激活码")) {
                                UIPasteboard.general.string = code
                                showCopiedAlert = true
                                Telemetry.shared.logEvent("order_installation_copy_activation", parameters: ["order_id": viewModel.order?.id ?? "-"])
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    if let smdp = installation.smdpAddress, !smdp.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(loc("SM-DP+ 地址"))
                                Spacer()
                                Text(smdp)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .foregroundColor(.secondary)
                            }
                            Button(loc("复制 SM-DP+ 地址")) {
                                UIPasteboard.general.string = smdp
                                showCopiedSmdpAlert = true
                                Telemetry.shared.logEvent("order_installation_copy_smdp", parameters: ["order_id": viewModel.order?.id ?? "-"])
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    if !installation.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(loc("安装步骤")).font(.subheadline).bold()
                            ForEach(Array(installation.instructions.enumerated()), id: \.offset) { idx, step in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("\(idx + 1).").bold()
                                    Text(step)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(loc("如无法扫描二维码，可输入激活码。"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .transition(.opacity)
            } else {
                Text(loc("支付成功后，您将获得安装二维码与步骤说明。"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Button {
                navBridge.push(ESIMInstallationGuideView(), auth: auth, settings: settings, network: networkMonitor, title: loc("安装指南"))
            } label: {
                Label(loc("查看 eSIM 安装指南"), systemImage: "qrcode.viewfinder")
            }
            .font(.footnote)
        }
    }

    private func localQRCode(from installation: OrderInstallationInfo) -> UIImage? {
        if let profile = installation.profileURL, let url = URL(string: profile) { return QRCodeGenerator.uiImage(from: url.absoluteString) }
        if let code = installation.activationCode, code.uppercased().hasPrefix("LPA:") { return QRCodeGenerator.uiImage(from: code) }
        if let smdp = installation.smdpAddress, let code = installation.activationCode { return QRCodeGenerator.uiImage(from: "LPA:1$\(smdp)$\(code)") }
        if let code = installation.activationCode { return QRCodeGenerator.uiImage(from: code) }
        return nil
    }

    private func formatMB(_ mb: Double) -> String {
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: date)
    }

    private func formatDateTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fmt.string(from: date)
    }
}

#Preview("eSIM 详情") {
    NavigationStack { EsimDetailView(orderId: "demo-001") }
        .environmentObject(NetworkMonitor.shared)
        .environmentObject(AuthManager())
}
