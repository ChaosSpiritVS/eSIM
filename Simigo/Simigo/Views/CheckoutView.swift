import SwiftUI
import UIKit
import Combine

private enum CheckoutRoute: Hashable {
    case terms
    case guide
    case privacy
}

struct CheckoutView: View {
    @StateObject private var viewModel: CheckoutViewModel
    @State private var showErrorBanner: Bool = false
    @State private var navigateToOrderDetail = false
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var bannerCenter: BannerCenter
    @State private var showAuthSheet = false
    @State private var acceptTerms: Bool = false
    @State private var showTermsConfirm: Bool = false
    @State private var showTermsSheet: Bool = false
    @State private var showPrivacySheet: Bool = false

    

    @ViewBuilder
    private var inlineErrorOverlay: some View {
        if let msg = viewModel.error, !msg.isEmpty {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.white)
                Text(msg).foregroundColor(.white).font(.footnote)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.9))
        }
    }

    


    @ViewBuilder
    private var content: some View {
        VStack(spacing: 16) {
            headerRow
            bundleSummary
            orderInfoSection
            Spacer(minLength: 0)
        }
    }

    init(bundle: ESIMBundle, auth: AuthManager) {
        _viewModel = StateObject(wrappedValue: CheckoutViewModel(bundle: bundle, auth: auth))
    }

    init(order: Order, bundle: ESIMBundle? = nil, auth: AuthManager) {
        _viewModel = StateObject(wrappedValue: CheckoutViewModel(order: order, bundle: bundle, auth: auth))
    }

    var body: some View {
        ScrollView { content }
            .padding()
            .safeAreaInset(edge: .bottom) { bottomCheckoutBar }
            .confirmationDialog(loc("购买前确认"), isPresented: $showTermsConfirm, titleVisibility: .visible) {
                Button(loc("同意并继续")) {
                    acceptTerms = true
                    if auth.isLoggedIn { viewModel.placeOrder() } else { showAuthSheet = true }
                }
                Button(loc("查看服务条款")) { navBridge.push(TermsOfServiceView(showCancel: false), auth: auth, settings: settings, network: networkMonitor, title: loc("服务条款")) }
                Button(loc("查看隐私政策")) { navBridge.push(PrivacyPolicyView(showCancel: false), auth: auth, settings: settings, network: networkMonitor, title: loc("隐私政策")) }
                Button(loc("取消"), role: .cancel) { }
            }
            .sheet(isPresented: $showTermsSheet) { UIKitNavHost(root: TermsOfServiceView(showCancel: true)) }
            .sheet(isPresented: $showPrivacySheet) { UIKitNavHost(root: PrivacyPolicyView(showCancel: true)) }
            .sheet(isPresented: $showAuthSheet) { UIKitNavHost(root: AuthView(auth: auth)) }
            .onAppear { onAppearAction() }
            .onChange(of: acceptTerms) { newValue in onAcceptTermsChange(newValue) }
            .onReceive(viewModel.$order) { newValue in onOrderChange(newValue) }
            .onReceive(viewModel.$error.removeDuplicates()) { newValue in onErrorChange(newValue) }
            .onChange(of: networkMonitor.isOnline) { newValue in onNetworkChange(newValue) }
            .onReceive(auth.$currentUser) { newValue in onAuthUserChange(newValue) }
    }

    private func onAppearAction() {
        let id = viewModel.order?.id
        let bundleId = viewModel.bundle?.id
        Telemetry.shared.logEvent("checkout_open", parameters: [
            "order_id": id ?? "",
            "bundle_id": bundleId ?? "",
            "has_order": (id != nil)
        ])
        let raw = (viewModel.bundle?.countryCode) ?? (viewModel.order?.countryCode)
        let code2 = raw.map { RegionCodeConverter.toAlpha2($0) } ?? ""
        Telemetry.shared.logEvent("checkout_region", parameters: ["code": code2])
        Task { await viewModel.loadConsult() }
    }

    private func onAcceptTermsChange(_ newValue: Bool) {
        Telemetry.shared.logEvent("checkout_terms_accept_toggle", parameters: ["accepted": newValue])
    }

    private func onOrderChange(_ newValue: Order?) {
        if let o = newValue {
            Telemetry.shared.logEvent("checkout_order_update", parameters: [
                "order_id": o.id,
                "status": String(describing: o.status),
                "method": String(describing: o.paymentMethod)
            ])
            if o.status == .paid {
                Telemetry.shared.logEvent("checkout_success", parameters: [
                    "order_id": o.id,
                    "method": String(describing: o.paymentMethod),
                    "amount": NSDecimalNumber(decimal: o.amount)
                ])
                navigateToOrderDetail = true
            }
        }
    }

    

    private func onErrorChange(_ newValue: String?) {
        if let err = newValue, !err.isEmpty {
            let cat = PaymentEventBridge.reasonCategory(reason: err, error: nil)
            Telemetry.shared.logEvent("checkout_failure", parameters: [
                "method": String(describing: viewModel.selectedPaymentMethod),
                "error": err,
                "reason_category": cat.category,
                "reason_code": cat.code ?? "-"
            ])
            Telemetry.shared.record(error: NSError(domain: "checkout", code: -1, userInfo: [NSLocalizedDescriptionKey: err]))
            let display = ErrorCopyMapper.paymentFailureDisplay(reason: err, underlying: nil)
            bannerCenter.enqueue(message: display, style: .error, source: "checkout", onClose: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.error = nil
                }
            })
        }
    }

    private func onNetworkChange(_ online: Bool) {
        if online {
            withAnimation(.easeInOut(duration: 0.25)) {
                showErrorBanner = false
                viewModel.error = nil
            }
        }
    }

    private func onAuthUserChange(_ user: User?) {
        if user != nil && showAuthSheet {
            showAuthSheet = false
            viewModel.placeOrder()
        }
    }

    
    private var bottomCheckoutBar: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 0.5)
            
            termsAgreementText
            
            totalPriceRow
            
            placeOrderButton
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(TopRoundedShape(radius: 20))
        .overlay(TopRoundedShape(radius: 20).stroke(Color.black.opacity(0.08), lineWidth: 0.6))
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: -2)
    }
    
    private var termsAgreementText: some View {
        HStack(spacing: 4) {
            Text(loc("购买即表示同意"))
            Button { navBridge.push(TermsOfServiceView(showCancel: false), auth: auth, settings: settings, network: networkMonitor, title: loc("服务条款")) } label: { Text(loc("服务条款")).underline() }
            Text(loc("与"))
            Button { navBridge.push(PrivacyPolicyView(showCancel: false), auth: auth, settings: settings, network: networkMonitor, title: loc("隐私政策")) } label: { Text(loc("隐私政策")).underline() }
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 8) {
            Group {
                if let bundle = viewModel.bundle {
                    if bundle.countryCode.isEmpty {
                        Image(systemName: "globe").foregroundColor(.green)
                    } else {
                        Text(countryFlag(bundle.countryCode))
                    }
                } else if let order = viewModel.order {
                    let code2 = RegionCodeConverter.toAlpha2(order.countryCode ?? "")
                    if code2.isEmpty {
                        Image(systemName: "globe").foregroundColor(.green)
                    } else {
                        Text(countryFlag(code2))
                    }
                }
            }
            .font(.largeTitle)
            .frame(width: 44)
            Text(headerTitle).font(.title2).bold()
            Spacer()
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var bundleSummary: some View {
        if let bundle = viewModel.bundle {
            VStack(alignment: .leading, spacing: 10) {
                Text(loc("套餐")).font(.headline)
                summaryItem(icon: "mappin.and.ellipse", title: loc("服务范围"), value: bundle.name)
                summaryItem(icon: "chart.bar.fill", title: loc("数据"), value: bundle.dataAmount)
                summaryItem(icon: "calendar", title: loc("有效期"), value: String(format: loc("%d 天"), bundle.validityDays))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryRow(icon: String, title: String, value: String) -> some View {
        summaryItem(icon: icon, title: title, value: value)
    }

    private func summaryItem(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
            Text(title)
            Spacer()
            Text(value)
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(UIColor.systemFill))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var totalPriceRow: some View {
        HStack {
            Text(loc("总计")).font(.subheadline).foregroundColor(.secondary)
            Spacer()
            Text(totalPriceString).font(.title3).bold()
        }
    }
    
    
    
    
    
    
    
    
    
    @ViewBuilder
    private var orderInfoSection: some View {
        if let order = viewModel.order {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: loc("订单已创建："), order.id)).font(.subheadline)
                Text(loc("状态：") + order.status.rawValue).foregroundColor(.secondary)
                Text(loc("总计：") + PriceFormatter.string(amount: order.amount, currencyCode: order.currency)).foregroundColor(.secondary)
                Text(loc("支付方式：") + order.paymentMethod.displayName).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var headerTitle: String {
        if let b = viewModel.bundle { return b.name }
        if let o = viewModel.order { return "订单 #" + String(o.id.prefix(6)) }
        return loc("结算")
    }
    
    private func strokeColor(selected: Bool) -> Color {
        selected ? Color.orange : Color.gray.opacity(0.12)
    }
    
    private func strokeWidth(selected: Bool) -> CGFloat {
        selected ? 2 : 1
    }
    
    private func rowBackground(selected: Bool) -> Color {
        selected ? Color.orange.opacity(0.04) : Color.clear
    }
    
    
    
    private var totalPriceString: String {
        let amount = viewModel.order?.amount ?? viewModel.bundle?.price ?? 0
        let currency = viewModel.order?.currency ?? viewModel.bundle?.currency ?? "USD"
        return PriceFormatter.string(amount: amount, currencyCode: currency)
    }
    
    private var placeOrderButton: some View {
        Button(action: handlePlaceOrder) {
            HStack {
                if viewModel.isPlacingOrder { 
                    ProgressView().tint(.white) 
                }
                Text(placeOrderButtonText)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .disabled(isPlaceOrderDisabled)
    }
    
    private func handlePlaceOrder() {
        let methodDesc = viewModel.selectedPaymentMethod?.displayName ?? "-"
        Telemetry.shared.logEvent("checkout_place_order_click", parameters: [
            "method": methodDesc,
            "is_resume": (viewModel.bundle == nil && viewModel.order != nil)
        ])
        if !acceptTerms { 
            showTermsConfirm = true
            return 
        }
        if auth.isLoggedIn {
            viewModel.placeOrder()
        } else {
            showAuthSheet = true
        }
    }
    
    private var placeOrderButtonText: String {
        let isResume = isResumeOrder
        if viewModel.isPlacingOrder {
            return isResume ? loc("正在支付…") : loc("正在下单…")
        }
        return placeOrderCTA
    }
    
    private var isResumeOrder: Bool {
        guard viewModel.bundle == nil, 
              let order = viewModel.order else { 
            return false 
        }
        return order.status == .created || order.status == .failed
    }
    
    private var placeOrderCTA: String {
        if isResumeOrder {
            return viewModel.order!.status == .failed ? loc("重试支付") : loc("继续支付")
        }
        return loc("立即购买")
    }
    
    private var isPlaceOrderDisabled: Bool {
        return viewModel.isPlacingOrder || !networkMonitor.isOnline
    }
}

private struct TopRoundedShape: Shape {
    var radius: CGFloat = 16
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
