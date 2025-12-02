import SwiftUI

struct CurrencySettingsView: View {
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var navBridge: NavigationBridge
    @State private var query: String = ""
    @State private var pendingCurrency: SettingsManager.CurrencyItem? = nil

    private var filtered: [SettingsManager.CurrencyItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = settings.supportedCurrencies
        guard !q.isEmpty else { return source }
        return source.filter { cur in
            settings.localizedCurrencyName(code: cur.code).localizedCaseInsensitiveContains(q) || cur.code.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    TextField(loc("按货币搜索"), text: $query)
                }
            }
            Section {
                ForEach(filtered) { cur in
                    Button {
                        if settings.currencyCode != cur.code { pendingCurrency = cur }
                    } label: {
                        HStack {
                            Text(settings.localizedCurrencyName(code: cur.code))
                            Spacer()
                            if settings.currencyCode == cur.code {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        
        .task { await settings.loadSettingsIfNeeded() }
        .onAppear { Telemetry.shared.logEvent("settings_currency_open", parameters: nil) }
        .onChange(of: query) { _, newValue in
            Telemetry.shared.logEvent("settings_currency_search_input", parameters: ["q": newValue])
        }
        .alert(item: $pendingCurrency) { cur in
            Alert(
                title: Text(String(format: loc("是否更改为%@ %@?"), settings.localizedCurrencyName(code: cur.code), "")),
                message: Text(loc("价格将以所选货币显示。")),
                primaryButton: .default(Text(loc("更改")), action: {
                    Telemetry.shared.logEvent("settings_currency_change", parameters: [
                        "to": cur.code
                    ])
                    settings.currencyCode = cur.code
                    navBridge.pop()
                }),
                secondaryButton: .cancel(Text(loc("取消")))
            )
        }
    }
}

#Preview { NavigationStack { CurrencySettingsView().environmentObject(SettingsManager()).environmentObject(NavigationBridge()) } }
