import SwiftUI
import WebKit

struct HelpCenterView: View {
    var showClose: Bool = true
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var navBridge: NavigationBridge
    private var url: URL {
        let canonical = SettingsManager.canonicalLanguage(settings.languageCode)
        let langUI = canonical.hasPrefix("zh") ? "zh" : "en"
        let v = Int(Date().timeIntervalSince1970)
        return URL(string: "http://localhost:8000/public/help/index.html?ios=1&lang=\(langUI)&locale=\(canonical)&v=\(v)")!
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
                .navigationTitle(loc("帮助中心"))
        }
    }
}

struct HelpWebView: UIViewRepresentable {
    let url: URL
    var showProgress: Bool = false
    class Coordinator: NSObject, WKNavigationDelegate {
        var progressObs: NSKeyValueObservation?
        var progressView: UIProgressView?
        func attach(web: WKWebView, pv: UIProgressView?) {
            progressView = pv
            progressObs = web.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                guard let bar = self?.progressView else { return }
                bar.isHidden = (wv.estimatedProgress >= 1.0) || (bar.progress >= 0.999)
                bar.setProgress(Float(wv.estimatedProgress), animated: true)
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let conf = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: conf)
        web.translatesAutoresizingMaskIntoConstraints = false
        web.allowsBackForwardNavigationGestures = true
        let progress = UIProgressView(progressViewStyle: .bar)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = .systemBlue
        progress.trackTintColor = .systemGray5
        progress.isHidden = !showProgress
        container.addSubview(progress)
        container.addSubview(web)
        NSLayoutConstraint.activate([
            progress.topAnchor.constraint(equalTo: container.topAnchor),
            progress.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.topAnchor.constraint(equalTo: progress.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        web.navigationDelegate = context.coordinator
        context.coordinator.attach(web: web, pv: progress)
        web.load(req)
        return container
    }
    func updateUIView(_ view: UIView, context: Context) {}
}
