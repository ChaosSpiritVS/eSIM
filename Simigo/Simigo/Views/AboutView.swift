import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section {
                Text(loc("品牌名"))
                Text(loc("版本信息与说明"))
            }
            Section {
                Link(loc("官方网站"), destination: URL(string: "https://example.com")!)
                    .simultaneousGesture(TapGesture().onEnded { Telemetry.shared.logEventDeferred("about_website_open", parameters: ["url": "https://example.com"]) })
            }
        }
        .listStyle(.insetGrouped)
        
        .onAppear { Telemetry.shared.logEvent("about_open", parameters: nil) }
    }
}

#Preview { NavigationStack { AboutView() } }
