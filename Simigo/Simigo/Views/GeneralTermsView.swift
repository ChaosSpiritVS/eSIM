import SwiftUI

struct GeneralTermsView: View {
    @EnvironmentObject private var navBridge: NavigationBridge
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(loc("一般条款简介")).font(.headline)
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
        .onAppear { Telemetry.shared.logEvent("general_terms_open", parameters: nil) }
    }
}

#Preview("一般条款") { NavigationStack { GeneralTermsView() } }
