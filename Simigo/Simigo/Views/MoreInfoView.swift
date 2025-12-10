import SwiftUI

struct MoreInfoView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var navBridge: NavigationBridge
    var body: some View {
        List {
            Section {
                Button { navBridge.push(AboutDocPage(), auth: auth, settings: settings, network: network, title: loc("关于 eSIM Home")) } label: { Text(loc("关于 eSIM Home")) }
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
    var showClose: Bool = false
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var navBridge: NavigationBridge
    var body: some View {
        let raw = settings.languageCode.lowercased()
        let canonical = SettingsManager.canonicalLanguage(raw)
        let locale = canonical
        let lang = canonical.hasPrefix("zh") ? "zh" : "en"
        let q = topic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? topic
        let v = Int(Date().timeIntervalSince1970)
        let url = URL(string: "http://localhost:8000/public/terms/view.html?ios=1&lang=\(lang)&locale=\(locale)&topic=\(q)&v=\(v)")!
        VStack(spacing: 0) {
            HelpWebView(url: url, showProgress: true)
        }
        .navigationTitle(loc(topic))
        .toolbar {
            if showClose {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(loc("关闭")) { navBridge.dismiss() }
                }
            }
        }
    }
}

struct AboutDocPage: View {
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var navBridge: NavigationBridge
    var showClose: Bool = false
    var body: some View {
        let canonical = SettingsManager.canonicalLanguage(settings.languageCode)
        let locale = canonical
        let lang = canonical.hasPrefix("zh") ? "zh" : "en"
        let topic = "关于 eSIM Home"
        let q = topic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? topic
        let v = Int(Date().timeIntervalSince1970)
        let url = URL(string: "http://localhost:8000/public/about/view.html?ios=1&lang=\(lang)&locale=\(locale)&topic=\(q)&v=\(v)")!
        VStack(spacing: 0) {
            HelpWebView(url: url, showProgress: true)
        }
        .navigationTitle(loc(topic))
        .toolbar {
            if showClose {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(loc("关闭")) { navBridge.dismiss() }
                }
            }
        }
    }
}
