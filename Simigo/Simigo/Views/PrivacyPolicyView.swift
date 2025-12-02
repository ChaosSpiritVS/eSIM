import SwiftUI

struct PrivacyPolicyView: View {
    @EnvironmentObject private var navBridge: NavigationBridge
    let showCancel: Bool
    init(showCancel: Bool = false) { self.showCancel = showCancel }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(loc("隐私政策简介")).font(.headline)
                Text(loc("我们收集的信息包括：设备标识、使用数据与诊断。"))
                    .foregroundColor(.secondary)
                Text(loc("我们仅用于提供服务、改进体验与安全风控。"))
                    .foregroundColor(.secondary)
                Text(loc("您可通过设置控制数据与删除账户请求。"))
                    .foregroundColor(.secondary)
                Text(loc("更多详尽条款请访问官网隐私政策页面。"))
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        
        .toolbar {
            if showCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("取消")) { navBridge.dismiss() }
                }
            }
        }
        .onAppear { Telemetry.shared.logEvent("privacy_open", parameters: nil) }
    }
}

#Preview("隐私政策") { NavigationStack { PrivacyPolicyView() } }
