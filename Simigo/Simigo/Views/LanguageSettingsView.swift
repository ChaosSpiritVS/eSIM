import SwiftUI

struct LanguageSettingsView: View {
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var navBridge: NavigationBridge
    @State private var query: String = ""
    @State private var pendingLang: SettingsManager.LanguageItem? = nil

    private var filteredLanguages: [SettingsManager.LanguageItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = settings.supportedLanguages
        guard !q.isEmpty else { return source }
        return source.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.code.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    TextField(loc("按语言搜索"), text: $query)
                }
            }

            Section {
                ForEach(filteredLanguages) { lang in
                    row(lang)
                }
            }
        }
        .listStyle(.insetGrouped)
        
        .task { await settings.loadSettingsIfNeeded() }
        .onAppear { Telemetry.shared.logEvent("settings_language_open", parameters: nil) }
        .onChange(of: query) { _, newValue in
            Telemetry.shared.logEvent("settings_language_search_input", parameters: ["q": newValue])
        }
        .alert(item: $pendingLang) { lang in
            Alert(
                title: Text(String(format: loc("是否更改为%@?"), lang.name)),
                message: Text(loc("所有信息将以所选语言显示。")),
                primaryButton: .default(Text(loc("更改")), action: {
                    Telemetry.shared.logEvent("settings_language_change", parameters: [
                        "to": lang.code
                    ])
                    settings.languageCode = lang.code
                    navBridge.pop()
                }),
                secondaryButton: .cancel(Text(loc("取消")))
            )
        }
    }

    @ViewBuilder
    private func row(_ lang: SettingsManager.LanguageItem) -> some View {
        Button {
            if settings.languageCode != lang.code { pendingLang = lang }
        } label: {
            HStack {
                Text(lang.name)
                Spacer()
                if settings.languageCode == lang.code {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
    }
}

#Preview { NavigationStack { LanguageSettingsView().environmentObject(SettingsManager()).environmentObject(NavigationBridge()) } }
