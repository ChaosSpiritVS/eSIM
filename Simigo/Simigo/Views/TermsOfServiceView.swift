import SwiftUI

struct TermsOfServiceView: View {
    @EnvironmentObject private var navBridge: NavigationBridge
    let showCancel: Bool
    init(showCancel: Bool = false) { self.showCancel = showCancel }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(loc("服务条款简介")).font(.headline)
                Text(loc("购买与退款需遵循当地法律与平台规则。"))
                    .foregroundColor(.secondary)
                Text(loc("套餐覆盖与速度以运营商实际为准。"))
                    .foregroundColor(.secondary)
                Text(loc("使用 eSIM 需符合设备与地区要求。"))
                    .foregroundColor(.secondary)
                Text(loc("更多详尽条款请访问官网服务条款页面。"))
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
        .onAppear { Telemetry.shared.logEvent("terms_open", parameters: nil) }
    }
}

#Preview("服务条款") { NavigationStack { TermsOfServiceView() } }
