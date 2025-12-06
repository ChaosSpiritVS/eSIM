import SwiftUI

struct MoreInfoView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var navBridge: NavigationBridge
    var body: some View {
        List {
            Section {
                Button { navBridge.push(AboutDocPage(), auth: auth, settings: settings, network: network, title: loc("关于 Airalo")) } label: { Text(loc("关于 Airalo")) }
                Button { navBridge.push(TermsDocPage(topic: "一般条款"), auth: auth, settings: settings, network: network, title: loc("一般条款")) } label: { Text(loc("一般条款")) }
                Button { navBridge.push(TermsDocPage(topic: "使用条款"), auth: auth, settings: settings, network: network, title: loc("使用条款")) } label: { Text(loc("使用条款")) }
                Button { navBridge.push(TermsDocPage(topic: "合理使用政策"), auth: auth, settings: settings, network: network, title: loc("合理使用政策")) } label: { Text(loc("合理使用政策")) }
                Button { navBridge.push(TermsDocPage(topic: "隐私政策"), auth: auth, settings: settings, network: network, title: loc("隐私政策")) } label: { Text(loc("隐私政策")) }
                Button { navBridge.push(TermsDocPage(topic: "Cookie 政策"), auth: auth, settings: settings, network: network, title: loc("Cookie 政策")) } label: { Text(loc("Cookie 政策")) }
            }
        }
        .listStyle(.insetGrouped)
        
        .onAppear { Telemetry.shared.logEvent("more_open", parameters: nil) }
    }
}

#Preview { NavigationStack { MoreInfoView() } }

struct TermsDocPage: View {
    let topic: String
    @EnvironmentObject private var settings: SettingsManager
    var body: some View {
        let raw = settings.languageCode.lowercased()
        let lang = raw.hasPrefix("zh") ? "zh" : "en"
        let q = topic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? topic
        let url = URL(string: "http://localhost:8000/public/terms/view.html?ios=1&lang=\(lang)&topic=\(q)")!
        HelpWebView(url: url)
    }
}

struct AboutDocPage: View {
    @EnvironmentObject private var settings: SettingsManager
    var body: some View {
        let raw = settings.languageCode.lowercased()
        let lang = raw.hasPrefix("zh") ? "zh" : "en"
        let topic = lang == "zh" ? "关于 eSIM Home" : "About eSIM Home"
        let q = topic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? topic
        let url = URL(string: "http://localhost:8000/public/about/view.html?ios=1&lang=\(lang)&topic=\(q)")!
        HelpWebView(url: url)
    }
}
