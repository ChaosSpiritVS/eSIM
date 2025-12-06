import SwiftUI

struct CookiePolicyView: View {
    @EnvironmentObject private var navBridge: NavigationBridge
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(loc("Cookie 政策简介")).font(.headline)
                Text(loc("我们使用 Cookie 与类似技术改善体验与分析性能。"))
                    .foregroundColor(.secondary)
                Text(loc("您可在浏览器或系统设置中管理 Cookie 偏好。"))
                    .foregroundColor(.secondary)
                Text(loc("更多详尽条款请访问官网 Cookie 政策页面。"))
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .onAppear { Telemetry.shared.logEvent("cookie_policy_open", parameters: nil) }
    }
}

#Preview("Cookie 政策") { NavigationStack { CookiePolicyView() } }
