import SwiftUI

struct AgentCenterView: View {
    @EnvironmentObject private var settings: SettingsManager
    @StateObject private var viewModel = AgentCenterViewModel()
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var bannerCenter: BannerCenter

    @State private var reference: String = ""
    @State private var startDate: String = ""
    @State private var endDate: String = ""
    @State private var showErrorBanner: Bool = false

    var body: some View {
        List {
            if viewModel.isLoading {
                loadingSections()
                    .transition(.opacity)
            } else {
                accountSection()
                filterSection()
                billsSection()
                    .transition(.opacity)
            }
        }
        .listStyle(.insetGrouped)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isLoading)
        
        .task { Telemetry.shared.logEvent("agent_center_open", parameters: nil); viewModel.load() }
        
        // 在线恢复：无条件清理错误状态；在未加载时刷新账户与账单
        .onChange(of: networkMonitor.isOnline) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.error = nil
                }
                if !viewModel.isLoading {
                    viewModel.load()
                }
            }
        }
        .onChange(of: networkMonitor.backendOnline) { _, newValue in
            if newValue {
                viewModel.load()
            }
        }
        .onChange(of: viewModel.bills.count) { newCount in
            Telemetry.shared.logEvent("agent_bills_result", parameters: [
                "count": newCount
            ])
        }
        .onChange(of: viewModel.error) { _, newValue in
            if let msg = newValue, !msg.isEmpty {
                bannerCenter.enqueue(message: msg, style: .error, source: "agent_center", actionTitle: loc("重试"), onAction: { viewModel.load() }, onClose: { withAnimation(.easeInOut(duration: 0.25)) { viewModel.error = nil } })
            }
        }
    }

    @ViewBuilder
    private func loadingSections() -> some View {
        Section(header: Text(loc("账户信息"))) { AgentAccountSkeleton() }
        Section(header: Text(loc("账单列表"))) { ForEach(0..<6, id: \.self) { _ in AgentBillRowSkeleton() } }
    }

    

    @ViewBuilder
    private func accountSection() -> some View {
        Section(header: Text(loc("账户信息"))) {
            if let acc = viewModel.account {
                HStack { Text(loc("代理商ID")); Spacer(); Text(acc.agentId).foregroundColor(.secondary) }
                HStack { Text(loc("用户名")); Spacer(); Text(acc.username).foregroundColor(.secondary) }
                HStack { Text(loc("代理商名称")); Spacer(); Text(acc.name).foregroundColor(.secondary) }
                HStack {
                    Text(loc("余额"))
                    Spacer()
                    Text(PriceFormatter.string(amount: Decimal(acc.balance), currencyCode: settings.currencyCode.uppercased()))
                        .foregroundColor(.secondary)
                }
                HStack { Text(loc("分成比例")); Spacer(); Text("\(acc.revenueRate)%").foregroundColor(.secondary) }
                HStack { Text(loc("状态")); Spacer(); Text(agentStatusText(acc.status)).foregroundColor(.secondary) }
                HStack { Text(loc("创建时间")); Spacer(); Text(formatDate(fromTimestamp: acc.createdAt)).foregroundColor(.secondary) }
            } else {
                Text(loc("暂无账户数据或别名模式未开启"))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func filterSection() -> some View {
        Section(header: Text(loc("账单筛选"))) {
            TextField(loc("参考号（可选）"), text: $reference)
            TextField(loc("开始日期 YYYY-MM-DD（可选）"), text: $startDate)
                .keyboardType(.numbersAndPunctuation)
            TextField(loc("结束日期 YYYY-MM-DD（可选）"), text: $endDate)
                .keyboardType(.numbersAndPunctuation)
            Button(action: {
                Telemetry.shared.logEvent("agent_bills_filter", parameters: [
                    "has_ref": !(reference.nilIfBlank == nil),
                    "has_start": !(startDate.nilIfBlank == nil),
                    "has_end": !(endDate.nilIfBlank == nil)
                ])
                viewModel.searchBills(reference: reference.nilIfBlank, startDate: startDate.nilIfBlank, endDate: endDate.nilIfBlank)
            }) {
                Label(loc("筛选账单"), systemImage: "line.3.horizontal.decrease.circle")
            }
            .disabled(viewModel.isLoading || !networkMonitor.isOnline)
        }
    }

    @ViewBuilder
    private func billsSection() -> some View {
        Section(header: Text(loc("账单列表"))) {
            if viewModel.bills.isEmpty {
                Text(loc("暂无账单"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.bills, id: \.billId) { bill in
                    billRow(bill)
                        .contentShape(Rectangle())
                        .onTapGesture { Telemetry.shared.logEvent("agent_bill_row_tap", parameters: ["bill_id": bill.billId, "trade": bill.trade]) }
                }
            }
        }
    }

    @ViewBuilder
    private func billRow(_ bill: HTTPUpstreamAgentRepository.AgentBillDTO) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(bill.reference)
                    .font(.subheadline)
                Text(bill.description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text(String(format: loc("类型：%@ · 时间：%@"), tradeText(bill.trade), formatDate(fromTimestamp: bill.createdAt)))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(PriceFormatter.string(amount: Decimal(bill.amount), currencyCode: settings.currencyCode.uppercased()))
                .font(.subheadline)
        }
    }

    private func agentStatusText(_ status: Int) -> String {
        switch status {
        case 1: return loc("活跃")
        case 0: return loc("禁用")
        default: return String(format: loc("状态(%@)"), String(status))
        }
    }

    private func tradeText(_ t: Int) -> String {
        switch t {
        case 1, 10: return loc("收入")
        case -1, 20: return loc("支出")
        default: return loc("其他")
        }
    }

    private func formatDate(fromTimestamp ts: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

#Preview("代理商中心") {
    NavigationStack { AgentCenterView() }
        .environmentObject(SettingsManager())
        .environmentObject(NetworkMonitor.shared)
}
