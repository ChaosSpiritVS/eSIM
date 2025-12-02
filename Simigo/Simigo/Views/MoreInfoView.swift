import SwiftUI

struct MoreInfoView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var navBridge: NavigationBridge
    var body: some View {
        List {
            Section {
                Button { navBridge.push(AboutView(), auth: auth, settings: settings, network: network, title: loc("关于")) } label: { Text(loc("关于")) }
                Button { navBridge.push(PrivacyPolicyView(showCancel: false), auth: auth, settings: settings, network: network, title: loc("隐私政策")) } label: { Text(loc("隐私政策")) }
                Button { navBridge.push(TermsOfServiceView(showCancel: false), auth: auth, settings: settings, network: network, title: loc("服务条款")) } label: { Text(loc("服务条款")) }
                Button { navBridge.push(AgentCenterView(), auth: auth, settings: settings, network: network, title: loc("代理商中心")) } label: { Text(loc("代理商中心")) }
            }
        }
        .listStyle(.insetGrouped)
        
        .onAppear { Telemetry.shared.logEvent("more_open", parameters: nil) }
    }
}

#Preview { NavigationStack { MoreInfoView() } }
