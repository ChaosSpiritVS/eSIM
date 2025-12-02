import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct OrderDetailView: View {
    @StateObject private var viewModel: OrderDetailViewModel
    @State private var showErrorBanner: Bool = false
    @State private var showInfoBanner: Bool = false
    @State private var navigateToCheckout: Bool = false
    @State private var orderToPay: Order?
    @State private var hasLoadedOnce: Bool = false
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var bannerCenter: BannerCenter
    @State private var showAuthSheet: Bool = false
    @State private var pendingOpenRefund: Bool = false
    
    private enum OrderDetailRoute: Hashable {
        case checkout(Order, ESIMBundle?)
        case bundle(ESIMBundle)
    }

    let showEsimEntry: Bool
    init(orderId: String, showEsimEntry: Bool = true) {
        _viewModel = StateObject(wrappedValue: OrderDetailViewModel(orderId: orderId))
        self.showEsimEntry = showEsimEntry
    }

    var body: some View {
        List {
            orderInfoSection()
            actionsSection()
            if showEsimEntry { esimRedirectSection() }
            afterSalesSection()
        }
        .listStyle(.insetGrouped)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isLoadingBundle)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isLoadingUsage)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isRequestingRefund)
        
        
        .onAppear {
            if !hasLoadedOnce {
                viewModel.load()
                hasLoadedOnce = true
            }
            Telemetry.shared.logEvent("order_detail_open_view", parameters: [
                "order_id": viewModel.order?.id ?? viewModel.orderId
            ])
        }
        
        
        .onChange(of: viewModel.refundSucceeded) { _, newValue in
            if let ok = newValue {
                Telemetry.shared.logEvent("order_refund_request_result", parameters: [
                    "order_id": viewModel.order?.id ?? viewModel.orderId,
                    "success": ok
                ])
            }
        }
        .onChange(of: viewModel.error) { _, newValue in
            if let err = newValue, !err.isEmpty {
                let cat = PaymentEventBridge.reasonCategory(reason: err, error: nil)
                let display = ErrorCopyMapper.paymentFailureDisplay(reason: err, underlying: nil)
                bannerCenter.enqueue(
                    message: display,
                    style: .error,
                    source: "order_detail",
                    actionTitle: loc("重试支付"),
                    onAction: {
                        if networkMonitor.isOnline {
                            if let o = viewModel.order {
                                Telemetry.shared.logEvent("order_checkout_open", parameters: [
                                    "order_id": o.id,
                                    "status": "retry",
                                    "source": "error_banner",
                                    "reason_category": cat.category,
                                    "reason_code": cat.code ?? "-"
                                ])
                                orderToPay = o
                                if auth.isLoggedIn { navigateToCheckout = true } else { showAuthSheet = true }
                            }
                        } else {
                            viewModel.error = loc("当前离线，请连接网络后再重试支付")
                        }
                    },
                    onClose: { withAnimation(.easeInOut(duration: 0.25)) { viewModel.error = nil } }
                )
            }
        }
        .onChange(of: viewModel.info) { _, newValue in
            if let msg = newValue, !msg.isEmpty {
                bannerCenter.enqueue(message: msg, style: .success, source: "order_detail", onClose: { withAnimation(.easeInOut(duration: 0.25)) { viewModel.info = nil } })
            }
        }
        // 在线恢复：无条件清理错误横幅与错误状态；在未加载时刷新详情
        .onChange(of: networkMonitor.isOnline) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showErrorBanner = false
                    viewModel.error = nil
                }
                if !viewModel.isLoading {
                    viewModel.load()
                }
            }
        }
        // 离线提示（轻量）：在底部显示当前离线状态
        
        .alert(loc("已复制激活码"), isPresented: $showCopiedAlert) {
            Button(loc("好的"), role: .cancel) {}
        }
        .alert(loc("已复制 SM-DP+ 地址"), isPresented: $showCopiedSmdpAlert) {
            Button(loc("好的"), role: .cancel) {}
        }
            .sheet(isPresented: $showAuthSheet) { UIKitNavHost(root: AuthView(auth: auth)) }
        .onChange(of: auth.currentUser) { _, newValue in
            if newValue != nil && showAuthSheet {
                showAuthSheet = false
                if pendingOpenRefund {
                    pendingOpenRefund = false
                    showRefundSheet = true
                } else if orderToPay != nil {
                    navigateToCheckout = true
                }
            }
        }
    }

    @ViewBuilder
    private func actionsSection() -> some View {
        Section(header: Text(loc("操作"))) {
            if viewModel.isLoadingBundle {
                OrderActionSkeleton()
                    .transition(.opacity)
            }
            if !viewModel.isLoadingBundle && viewModel.bundle == nil && viewModel.order != nil {
                Text(loc("未能加载套餐信息"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            if let order = viewModel.order {
                if order.status == .created || order.status == .failed {
                    Button {
                        if networkMonitor.isOnline {
                            orderToPay = order
                            if auth.isLoggedIn {
                                navigateToCheckout = true
                            } else {
                                showAuthSheet = true
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(order.status == .failed ? loc("重试支付") : loc("继续支付"))
                            Spacer()
                        }
                    }
                    .disabled(!networkMonitor.isOnline)
                }
                if let bundle = viewModel.bundle {
                    Button {
                        navBridge.push(BundleDetailView(bundle: bundle), auth: auth, settings: settings, network: networkMonitor, title: bundle.name)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text(loc("查看套餐详情"))
                            Spacer()
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text(loc("查看套餐详情"))
                        Spacer()
                        Text(loc("请稍候…")).foregroundColor(.secondary)
                    }
                }
            } else {
                Text(loc("订单加载完成后可查看套餐或支付"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func esimRedirectSection() -> some View {
        Section(header: Text("eSIM")) {
            Button {
                Telemetry.shared.logEvent("order_detail_redirect_esim_click", parameters: [
                    "order_id": viewModel.order?.id ?? viewModel.orderId
                ])
                let title = (viewModel.bundle?.name)
                    ?? (viewModel.order?.bundleName)
                    ?? (viewModel.order?.bundleMarketingName)
                    ?? loc("我的 eSIM")
                navBridge.push(EsimDetailView(orderId: viewModel.orderId, showOrderEntry: false), auth: auth, settings: settings, network: networkMonitor, title: title)
            } label: {
                HStack { Image(systemName: "qrcode.viewfinder"); Text(loc("前往我的 eSIM 查看安装与用量")); Spacer() }
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
                                            .onAppear {
                                                Telemetry.shared.logEvent("order_installation_qr_local_fallback", parameters: [
                                                    "order_id": viewModel.order?.id ?? viewModel.orderId
                                                ])
                                            }
                                    } else {
                                        Image(systemName: "qrcode")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 120, height: 120)
                                            .foregroundColor(.secondary)
                                            .onAppear {
                                                Telemetry.shared.logEvent("order_installation_qr_unavailable", parameters: [
                                                    "order_id": viewModel.order?.id ?? viewModel.orderId
                                                ])
                                            }
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

    @ViewBuilder
    private func afterSalesSection() -> some View {
        Section(header: Text(loc("售后"))) {
            if viewModel.isRequestingRefund {
                OrderAfterSalesSkeleton()
                    .transition(.opacity)
            }
            Button(loc("申请退款")) {
                Telemetry.shared.logEvent("order_refund_request_click", parameters: [
                    "order_id": viewModel.order?.id ?? viewModel.orderId
                ])
                if auth.isLoggedIn {
                    showRefundSheet = true
                } else {
                    pendingOpenRefund = true
                    showAuthSheet = true
                }
            }
            .disabled(!networkMonitor.isOnline || viewModel.isRequestingRefund || !viewModel.isRefundAllowed)
            .sheet(isPresented: $showRefundSheet) {
                UIKitNavHost(root: Form {
                        Section(header: Text(loc("退款原因"))) {
                            TextField(loc("请输入退款原因"), text: $refundReason)
                                .onChange(of: refundReason) { _, newValue in
                                    refundReasonError = newValue.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 ? nil : loc("请至少输入 5 个字符")
                                }
                            if let err = refundReasonError {
                                Text(err).foregroundColor(.red)
                            }
                        }
                        Section {
                            Button(loc("提交退款申请")) {
                                Telemetry.shared.logEvent("order_refund_request_confirm", parameters: [
                                    "order_id": viewModel.order?.id ?? viewModel.orderId,
                                    "reason_len": refundReason.count
                                ])
                                viewModel.requestRefund(reason: refundReason.trimmingCharacters(in: .whitespacesAndNewlines))
                                showRefundSheet = false
                                refundReason = ""
                                refundReasonError = nil
                            }
                            .disabled(!networkMonitor.isOnline || viewModel.isRequestingRefund || (refundReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 5))
                        }
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(loc("取消")) { showRefundSheet = false } } }
                )
            }
            if let ok = viewModel.refundSucceeded {
                Text(ok ? loc("退款申请已提交") : loc("退款申请失败"))
                    .foregroundColor(ok ? .green : .red)
            }
            if !viewModel.refundProgress.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.refundProgress, id: \.updatedAt) { step in
                        HStack {
                            Text(displayRefund(step.state))
                            Spacer()
                            Text(formatDateTime(step.updatedAt)).foregroundColor(.secondary)
                        }
                        if let note = step.note, !note.isEmpty {
                            Text(note).font(.footnote).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func orderInfoSection() -> some View {
        Section(header: Text(loc("订单信息"))) {
            if viewModel.isLoading {
                OrderInfoSkeleton()
                    .transition(.opacity)
            }
            if let order = viewModel.order {
                Group {
                    HStack { Text(loc("订单ID")); Spacer(); Text(order.id).foregroundColor(.secondary) }
                    HStack { Text(loc("套餐名称")); Spacer(); Text(viewModel.bundle?.name ?? order.bundleName ?? order.bundleMarketingName ?? "-").foregroundColor(.secondary) }
                    HStack { Text(loc("创建时间")); Spacer(); Text(formatDateTime(order.createdAt)).foregroundColor(.secondary) }
                    HStack { Text(loc("金额")); Spacer(); Text(PriceFormatter.string(amount: order.amount, currencyCode: settings.currencyCode.uppercased())).foregroundColor(.secondary) }
                    HStack { Text(loc("状态")); Spacer(); Text(order.orderStatusText ?? "-").foregroundColor(.secondary) }
                    HStack { Text(loc("支付方式")); Spacer(); Text(order.paymentMethod.displayName).foregroundColor(.secondary) }
                    if let cat = order.bundleCategory, !cat.isEmpty {
                        HStack { Text(loc("套餐类型")); Spacer(); Text(cat).foregroundColor(.secondary) }
                    }
                    if let name = order.countryName ?? order.countryCode, !name.isEmpty {
                        HStack { Text(loc("国家/地区")); Spacer(); Text(name).foregroundColor(.secondary) }
                    }
                    if viewModel.usage?.expiresAt == nil {
                        if let exp = order.bundleExpiryDate ?? order.expiryDate {
                            HStack { Text(loc("到期时间")); Spacer(); Text(formatDate(exp)).foregroundColor(.secondary) }
                        }
                    }
                    if (order.status == .paid) || (viewModel.usage != nil) {
                        if let started = order.planStarted {
                            HStack { Text(loc("已开始")); Spacer(); Text(started ? loc("是") : loc("否")).foregroundColor(.secondary) }
                        }
                        if let pst = order.planStatusText, !pst.isEmpty {
                            HStack { Text(loc("计划状态")); Spacer(); Text(pst).foregroundColor(.secondary) }
                        }
                    }
                    if !order.bundleId.isEmpty {
                        HStack { Text(loc("套餐代码")); Spacer(); Text(order.bundleId).foregroundColor(.secondary) }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    @State private var showCopiedAlert = false
    @State private var showRefundSheet = false
    @State private var refundReason: String = ""
    @State private var refundReasonError: String? = nil
    @State private var showCopiedSmdpAlert = false

    private func localQRCode(from installation: OrderInstallationInfo) -> UIImage? {
        if let profile = installation.profileURL, let url = URL(string: profile) {
            return QRCodeGenerator.uiImage(from: url.absoluteString)
        }
        if let code = installation.activationCode, code.uppercased().hasPrefix("LPA:") {
            return QRCodeGenerator.uiImage(from: code)
        }
        if let smdp = installation.smdpAddress, let code = installation.activationCode {
            let payload = "LPA:1$\(smdp)$\(code)"
            return QRCodeGenerator.uiImage(from: payload)
        }
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

    private func displayRefund(_ state: RefundState) -> String {
        switch state {
        case .requested: return loc("已受理")
        case .reviewing: return loc("审核中")
        case .completed: return loc("已完成")
        case .rejected: return loc("已拒绝")
        }
    }
}

#Preview("订单详情") {
    NavigationStack { OrderDetailView(orderId: "demo-001") }
        .environmentObject(NetworkMonitor.shared)
        .environmentObject(AuthManager())
}
