import SwiftUI

struct OrdersListView: View {
    @StateObject private var viewModel = OrdersListViewModel()
    @State private var showErrorBanner: Bool = false
    @State private var showInfoBanner: Bool = false
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var bannerCenter: BannerCenter
    @State private var query: String = ""
    @State private var navigateToCheckout: Bool = false
    @State private var orderToPay: Order?
    @State private var showAuthSheet: Bool = false
    @State private var statusFilter: OrderStatusFilter = .all

    var body: some View {
        List {
            searchSection
            filterSection
            ordersSection
        }
        .listStyle(.insetGrouped)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isLoading)
        
        
        .onAppear {
            viewModel.setAuth(auth)
            viewModel.setPageSize(10)
            Telemetry.shared.logEvent("orders_open", parameters: ["page_size": 10])
            if viewModel.orders.isEmpty { viewModel.load() }
            else { viewModel.load(preservePagination: true) }
        }
        
        .sheet(isPresented: $showAuthSheet) { UIKitNavHost(root: AuthView(auth: auth)) }
        
        .onChange(of: viewModel.error) { _, newValue in
            if let msg = newValue, !msg.isEmpty {
                bannerCenter.enqueue(message: msg, style: .error, source: "orders_list", actionTitle: loc("重试"), onAction: { viewModel.load(preservePagination: true) }, onClose: { withAnimation(.easeInOut(duration: 0.25)) { viewModel.error = nil } })
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
        
    }

    @ViewBuilder private var filterSection: some View {
        Section(header: Text(loc("筛选"))) {
            Picker(loc("状态"), selection: $statusFilter) {
                Text(loc("全部")).tag(OrderStatusFilter.all)
                Text(loc("已创建")).tag(OrderStatusFilter.created)
                Text(loc("已支付")).tag(OrderStatusFilter.paid)
                Text(loc("失败")).tag(OrderStatusFilter.failed)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder private var searchSection: some View {
        Section(header: Text(loc("搜索"))) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                TextField(loc("搜索订单ID"), text: $query)
                    .submitLabel(.search)
                    .onSubmit {
                        Telemetry.shared.logEvent("orders_search_submit", parameters: [
                            "query_len": query.trimmingCharacters(in: .whitespacesAndNewlines).count
                        ])
                    }
            }
        }
    }

    @ViewBuilder private var ordersSection: some View {
        Section(header: Text(loc("我的订单"))) {
            if viewModel.isLoading { skeletonGroup } else { ordersContent }
        }
    }

    @ViewBuilder private var skeletonGroup: some View {
        Group { ForEach(0..<6, id: \.self) { _ in OrderRowSkeleton() } }.transition(.opacity)
    }

    @ViewBuilder private var ordersContent: some View {
        Group {
            ForEach(filteredOrders) { order in row(order) }
            if filteredOrders.isEmpty { Text(loc("暂无订单")).foregroundColor(.secondary) }
            if viewModel.hasMore { loadMoreRow }
        }
        .transition(.opacity)
    }

    @ViewBuilder private func row(_ order: Order) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: loc("订单 #%@"), shortId(order.id))).font(.subheadline).bold()
                HStack(spacing: 8) {
                    Text(String(format: loc("创建日期：%@"), formatDate(order.createdAt))).font(.footnote).foregroundColor(.secondary)
                    Text(order.paymentMethod.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(UIColor.systemGray6))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                    Text(order.status == .failed ? loc("失败") : (order.status == .paid ? loc("已支付") : loc("待支付")))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background((order.status == .failed ? Color.red : (order.status == .paid ? Color.green : Color.orange)).opacity(0.15))
                        .foregroundColor(order.status == .failed ? .red : (order.status == .paid ? .green : .orange))
                        .clipShape(Capsule())
                }
            }
            Spacer()
            if order.status == .created || order.status == .failed {
                Button {
                    if networkMonitor.isOnline {
                        orderToPay = order
                        Telemetry.shared.logEvent("orders_inline_continue", parameters: [
                            "order_id": order.id,
                            "status": order.status == .failed ? "retry" : "continue",
                            "source": "inline_button"
                        ])
                        if auth.isLoggedIn {
                            navBridge.push(CheckoutView(order: order, bundle: viewModel.bundleById[order.bundleId], auth: auth), auth: auth, settings: settings, network: networkMonitor, title: order.status == .failed ? loc("重试支付") : loc("继续支付"))
                        } else { showAuthSheet = true }
                    }
                } label: {
                    Text(order.status == .failed ? loc("重试支付") : loc("继续支付"))
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!networkMonitor.isOnline)
            } else {
                HStack(spacing: 8) { Text(PriceFormatter.string(amount: order.amount, currencyCode: order.currency)).font(.subheadline) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            navBridge.push(OrderDetailView(orderId: order.id), auth: auth, settings: settings, network: networkMonitor, title: String(format: loc("订单 #%@"), shortId(order.id)))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if order.status == .created || order.status == .failed {
                Button {
                    if networkMonitor.isOnline {
                        orderToPay = order
                        if auth.isLoggedIn {
                            navBridge.push(CheckoutView(order: order, bundle: viewModel.bundleById[order.bundleId], auth: auth), auth: auth, settings: settings, network: networkMonitor, title: order.status == .failed ? loc("重试支付") : loc("继续支付"))
                        } else { showAuthSheet = true }
                    }
                } label: { Label(order.status == .failed ? loc("重试支付") : loc("继续支付"), systemImage: "arrow.triangle.2.circlepath") }
                .tint(.orange)
                .disabled(!networkMonitor.isOnline)
            }
        }
        .contextMenu {
            if order.status == .created || order.status == .failed {
                Button {
                    if networkMonitor.isOnline {
                        orderToPay = order
                        if auth.isLoggedIn {
                            navBridge.push(CheckoutView(order: order, bundle: viewModel.bundleById[order.bundleId], auth: auth), auth: auth, settings: settings, network: networkMonitor, title: order.status == .failed ? loc("重试支付") : loc("继续支付"))
                        } else { showAuthSheet = true }
                    }
                } label: { Text(order.status == .failed ? loc("重试支付") : loc("继续支付")) }
            }
        }
    }

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            Button {
                Telemetry.shared.logEvent("orders_load_more", parameters: ["page_size": viewModel.pageSize])
                viewModel.loadMore()
            } label: { Text(viewModel.isLoadingMore ? loc("加载中...") : loc("加载更多")).padding(.horizontal, 18).padding(.vertical, 8) }
            .background(Color(UIColor.systemGray5))
            .clipShape(Capsule())
            .disabled(viewModel.isLoadingMore)
            Spacer()
        }
    }

    private var filteredOrders: [Order] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [Order] = {
            if q.isEmpty { return viewModel.orders }
            return viewModel.orders.filter { $0.id.localizedCaseInsensitiveContains(q) }
        }()
        switch statusFilter {
        case .all:
            return base
        case .created:
            return base.filter { $0.status == .created }
        case .paid:
            return base.filter { $0.status == .paid }
        case .failed:
            return base.filter { $0.status == .failed }
        }
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

#Preview("订单列表") {
    NavigationStack { OrdersListView() }
        .environmentObject(NetworkMonitor.shared)
        .environmentObject(AuthManager())
}
