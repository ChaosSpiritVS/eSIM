import SwiftUI
import WebKit

struct HelpCenterView: View {
    var showClose: Bool = true
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var navBridge: NavigationBridge
    private var url: URL {
        let appLang = settings.languageCode.lowercased()
        let lang = appLang.hasPrefix("zh") ? "zh" : "en"
        return URL(string: "http://localhost:8000/public/help/index.html?ios=1&lang=\(lang)")!
    }
    var body: some View {
        VStack(spacing: 0) {
            HelpWebView(url: url)
                .toolbar {
                    if showClose {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(loc("关闭")) { navBridge.dismiss() }
                        }
                    }
                }
        }
    }
}

struct HelpWebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let conf = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: conf)
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: url))
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
