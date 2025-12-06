import SwiftUI

struct AcceptableUsePolicyView: View {
    @EnvironmentObject private var navBridge: NavigationBridge
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(loc("合理使用政策简介")).font(.headline)
                Text(loc("请合理使用网络资源，禁止滥用或非法用途。"))
                    .foregroundColor(.secondary)
                Text(loc("我们可能在过度使用时采取限制措施。"))
                    .foregroundColor(.secondary)
                Text(loc("更多详尽条款请访问官网合理使用政策页面。"))
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .onAppear { Telemetry.shared.logEvent("acceptable_use_open", parameters: nil) }
    }
}

#Preview("合理使用政策") { NavigationStack { AcceptableUsePolicyView() } }
