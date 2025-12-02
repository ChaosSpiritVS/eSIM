import SwiftUI

final class SettingsManager: ObservableObject {
    @Published var languageCode: String {
        didSet {
            UserDefaults.standard.set(languageCode, forKey: "simigo.languageCode")
            guard shouldPersistProfileChanges else { return }
            Task { await persistProfile(language: languageCode, currency: nil) }
            Telemetry.shared.logEvent("settings_language_change", parameters: ["code": languageCode])
        }
    }
    @Published var currencyCode: String {
        didSet {
            UserDefaults.standard.set(currencyCode, forKey: "simigo.currencyCode")
            guard shouldPersistProfileChanges else { return }
            Task { await persistProfile(language: nil, currency: currencyCode) }
            Telemetry.shared.logEvent("settings_currency_change", parameters: ["code": currencyCode])
        }
    }
    @Published var analyticsOptIn: Bool {
        didSet {
            UserDefaults.standard.set(analyticsOptIn, forKey: "simigo.analyticsOptIn")
            Telemetry.shared.setAnalyticsEnabled(analyticsOptIn)
            Telemetry.shared.logEvent("settings_analytics_opt_in_change", parameters: ["enabled": analyticsOptIn])
        }
    }
    @Published var crashOptIn: Bool {
        didSet {
            UserDefaults.standard.set(crashOptIn, forKey: "simigo.crashOptIn")
            Telemetry.shared.setCrashEnabled(crashOptIn)
            Telemetry.shared.logEvent("settings_crash_opt_in_change", parameters: ["enabled": crashOptIn])
        }
    }
    @Published var supportedLanguages: [LanguageItem] = []
    @Published var supportedCurrencies: [CurrencyItem] = []
    private var shouldPersistProfileChanges: Bool = true
    private let cacheStore = CatalogCacheStore.shared

    static func canonicalLanguage(_ raw: String) -> String {
        let s = raw.lowercased()
        func any(_ prefixes: [String]) -> Bool { prefixes.contains(where: { s.hasPrefix($0) }) }
        if any(["zh-hans","zh-cn"]) { return "zh-Hans" }
        if any(["zh-hant","zh-tw","zh-hk","zh-mo"]) { return "zh-Hant" }
        if any(["en"]) { return "en" }
        if any(["ja"]) { return "ja" }
        if any(["ko"]) { return "ko" }
        if any(["th"]) { return "th" }
        if any(["id"]) { return "id" }
        if any(["ms"]) { return "ms" }
        if any(["es"]) { return "es" }
        if any(["pt"]) { return "pt" }
        if any(["vi"]) { return "vi" }
        if any(["ar"]) { return "ar" }
        return raw
    }
    init(languageCode: String? = nil, currencyCode: String? = nil) {
        let stored = UserDefaults.standard.string(forKey: "simigo.languageCode")
        let initial = languageCode ?? stored ?? Locale.preferredLanguages.first ?? "zh-Hans"
        self.languageCode = SettingsManager.canonicalLanguage(initial)
        let storedCur = UserDefaults.standard.string(forKey: "simigo.currencyCode")
        let sysCur = Locale.current.currencyCode?.uppercased()
        let allowed: Set<String> = [
            "USD","EUR","GBP","CHF","CNY","HKD","JPY","SGD",
            "KRW","THB","IDR","MYR","VND","BRL","MXN","TWD",
            "AED","SAR","AUD","CAD"
        ]
        let defaultCur = (sysCur != nil && allowed.contains(sysCur!)) ? sysCur! : "USD"
        self.currencyCode = currencyCode ?? storedCur ?? defaultCur
        let analyticsStored = UserDefaults.standard.object(forKey: "simigo.analyticsOptIn") as? Bool
        let crashStored = UserDefaults.standard.object(forKey: "simigo.crashOptIn") as? Bool
        self.analyticsOptIn = analyticsStored ?? false
        self.crashOptIn = crashStored ?? false
        Telemetry.shared.setAnalyticsEnabled(self.analyticsOptIn)
        Telemetry.shared.setCrashEnabled(self.crashOptIn)
    }

    var locale: Locale { Locale(identifier: languageCode) }

    // 简化的展示名称映射，便于在个人资料页显示
    var languageDisplayName: String {
        let map: [String: String] = [
            "en": "English",
            "zh-Hans": "简体中文",
            "zh-Hant": "繁體中文",
            "ja": "日本語",
            "ko": "한국어",
            "th": "ไทย",
            "id": "Bahasa Indonesia",
            "es": "Español",
            "pt": "Português",
            "ms": "Bahasa Melayu",
            "vi": "Tiếng Việt",
            "ar": "العربية"
        ]
        return map[languageCode] ?? (Locale.current.localizedString(forIdentifier: languageCode) ?? languageCode)
    }

    var currencyDisplayName: String { localizedCurrencyName(code: currencyCode) }

    func localizedCurrencyName(code: String) -> String {
        switch code.uppercased() {
        case "USD": return loc("货币名_USD")
        case "EUR": return loc("货币名_EUR")
        case "GBP": return loc("货币名_GBP")
        case "CHF": return loc("货币名_CHF")
        case "CNY": return loc("货币名_CNY")
        case "HKD": return loc("货币名_HKD")
        case "JPY": return loc("货币名_JPY")
        case "SGD": return loc("货币名_SGD")
        case "KRW": return loc("货币名_KRW")
        case "THB": return loc("货币名_THB")
        case "IDR": return loc("货币名_IDR")
        case "MYR": return loc("货币名_MYR")
        case "VND": return loc("货币名_VND")
        case "BRL": return loc("货币名_BRL")
        case "MXN": return loc("货币名_MXN")
        case "TWD": return loc("货币名_TWD")
        case "AED": return loc("货币名_AED")
        case "SAR": return loc("货币名_SAR")
        case "AUD": return loc("货币名_AUD")
        case "CAD": return loc("货币名_CAD")
        default: return code
        }
    }

    // MARK: - Types
    struct LanguageItem: Identifiable, Codable, Hashable { let code: String; let name: String; var id: String { code } }
    struct CurrencyItem: Identifiable, Codable, Hashable { let code: String; let name: String; let symbol: String?; var id: String { code } }

    // MARK: - Remote loading
    @MainActor
    func loadSettingsIfNeeded() async {
        if supportedLanguages.isEmpty || supportedCurrencies.isEmpty {
            await loadSettings()
        }
    }

    @MainActor
    func loadSettings() async {
        let service = NetworkService()
        var langExpired = true
        var curExpired = true
        if let langsCached = cacheStore.loadLanguages(ttl: AppConfig.settingsCacheTTL) {
            supportedLanguages = langsCached.list
            langExpired = langsCached.isExpired
            let codes: Set<String> = ["en","zh-Hans","zh-Hant","ja","ko","th","id","es","pt","ms","vi","ar"]
            let filtered = supportedLanguages.filter { codes.contains($0.code) }
            if !filtered.isEmpty { supportedLanguages = filtered; cacheStore.saveLanguages(filtered) }
            UserDefaults.standard.set(supportedLanguages.map { $0.code }, forKey: "simigo.allowedLanguages")
        }
        if let currsCached = cacheStore.loadCurrencies(ttl: AppConfig.settingsCacheTTL) {
            supportedCurrencies = currsCached.list
            curExpired = currsCached.isExpired
            let codes: Set<String> = [
                "USD","EUR","GBP","CHF","CNY","HKD","JPY","SGD",
                "KRW","THB","IDR","MYR","VND","BRL","MXN","TWD",
                "AED","SAR","AUD","CAD"
            ]
            let filtered = supportedCurrencies.filter { codes.contains($0.code.uppercased()) }
            if !filtered.isEmpty { supportedCurrencies = filtered; cacheStore.saveCurrencies(filtered) }
            UserDefaults.standard.set(supportedCurrencies.map { $0.code.uppercased() }, forKey: "simigo.allowedCurrencies")
            // keep TTL-based expiry only; do not force by count
        }
        if supportedLanguages.isEmpty || langExpired || supportedLanguages.count < 12 {
            if let langs: [LanguageItem] = try? await service.get("/settings/languages") {
                let codes: Set<String> = ["en","zh-Hans","zh-Hant","ja","ko","th","id","es","pt","ms","vi","ar"]
                let filtered = langs.filter { codes.contains($0.code) }
                if !filtered.isEmpty { supportedLanguages = filtered; cacheStore.saveLanguages(filtered) }
                UserDefaults.standard.set(supportedLanguages.map { $0.code }, forKey: "simigo.allowedLanguages")
            }
        }
        if supportedCurrencies.isEmpty || curExpired {
            if let currs: [CurrencyItem] = try? await service.get("/settings/currencies") {
                let codes: Set<String> = [
                    "USD","EUR","GBP","CHF","CNY","HKD","JPY","SGD",
                    "KRW","THB","IDR","MYR","VND","BRL","MXN","TWD",
                    "AED","SAR","AUD","CAD"
                ]
                let filtered = currs.filter { codes.contains($0.code.uppercased()) }
                supportedCurrencies = filtered.isEmpty ? currs : filtered
                cacheStore.saveCurrencies(supportedCurrencies)
                UserDefaults.standard.set(supportedCurrencies.map { $0.code.uppercased() }, forKey: "simigo.allowedCurrencies")
            }
        }
        if supportedLanguages.isEmpty {
            supportedLanguages = [
                LanguageItem(code: "en", name: "English"),
                LanguageItem(code: "zh-Hans", name: "简体中文"),
                LanguageItem(code: "zh-Hant", name: "繁體中文"),
                LanguageItem(code: "ja", name: "日本語"),
                LanguageItem(code: "ko", name: "한국어"),
                LanguageItem(code: "th", name: "ไทย"),
                LanguageItem(code: "id", name: "Bahasa Indonesia"),
                LanguageItem(code: "es", name: "Español"),
                LanguageItem(code: "pt", name: "Português"),
                LanguageItem(code: "ms", name: "Bahasa Melayu"),
                LanguageItem(code: "vi", name: "Tiếng Việt"),
                LanguageItem(code: "ar", name: "العربية")
            ]
            cacheStore.saveLanguages(supportedLanguages)
            UserDefaults.standard.set(supportedLanguages.map { $0.code }, forKey: "simigo.allowedLanguages")
        }
        if supportedCurrencies.isEmpty {
            supportedCurrencies = [
                CurrencyItem(code: "USD", name: "美元 (USD)", symbol: "$"),
                CurrencyItem(code: "EUR", name: "欧元 (EUR)", symbol: "€"),
                CurrencyItem(code: "GBP", name: "英镑 (GBP)", symbol: "£"),
                CurrencyItem(code: "CHF", name: "瑞士法郎 (CHF)", symbol: "CHF"),
                CurrencyItem(code: "CNY", name: "人民币 (CNY)", symbol: "¥"),
                CurrencyItem(code: "HKD", name: "港币 (HKD)", symbol: "HK$"),
                CurrencyItem(code: "JPY", name: "日元 (JPY)", symbol: "¥"),
                CurrencyItem(code: "SGD", name: "新加坡元 (SGD)", symbol: "S$"),
                CurrencyItem(code: "KRW", name: "韩元 (KRW)", symbol: "₩"),
                CurrencyItem(code: "THB", name: "泰铢 (THB)", symbol: "฿"),
                CurrencyItem(code: "IDR", name: "印尼卢比 (IDR)", symbol: "Rp"),
                CurrencyItem(code: "MYR", name: "马来西亚林吉特 (MYR)", symbol: "RM"),
                CurrencyItem(code: "VND", name: "越南盾 (VND)", symbol: "₫"),
                CurrencyItem(code: "BRL", name: "巴西雷亚尔 (BRL)", symbol: "R$"),
                CurrencyItem(code: "MXN", name: "墨西哥比索 (MXN)", symbol: "MX$"),
                CurrencyItem(code: "TWD", name: "新台币 (TWD)", symbol: "NT$"),
                CurrencyItem(code: "AED", name: "阿联酋迪拉姆 (AED)", symbol: "AED"),
                CurrencyItem(code: "SAR", name: "沙特里亚尔 (SAR)", symbol: "SAR"),
                CurrencyItem(code: "AUD", name: "澳大利亚元 (AUD)", symbol: "A$"),
                CurrencyItem(code: "CAD", name: "加拿大元 (CAD)", symbol: "C$")
            ]
            cacheStore.saveCurrencies(supportedCurrencies)
            UserDefaults.standard.set(supportedCurrencies.map { $0.code.uppercased() }, forKey: "simigo.allowedCurrencies")
        }
        let codesNow = Set(supportedLanguages.map { $0.code })
        if !codesNow.contains(languageCode) {
            let normalized = SettingsManager.canonicalLanguage(languageCode)
            if codesNow.contains(normalized) {
                shouldPersistProfileChanges = false
                languageCode = normalized
                shouldPersistProfileChanges = true
            }
        }
        let curCodesNow = Set(supportedCurrencies.map { $0.code.uppercased() })
        if !curCodesNow.contains(currencyCode.uppercased()) {
            shouldPersistProfileChanges = false
            currencyCode = curCodesNow.contains("USD") ? "USD" : (supportedCurrencies.first?.code ?? currencyCode)
            shouldPersistProfileChanges = true
        }
    }

    // MARK: - Profile sync
    @MainActor
    func syncProfileFromServer() async {
        let service = NetworkService()
        struct MeDTO: Decodable { let id: String; let name: String; let lastName: String?; let email: String?; let language: String?; let currency: String? }
        do {
            let me: MeDTO = try await service.get("/me")
            shouldPersistProfileChanges = false
            if let lng = me.language { self.languageCode = SettingsManager.canonicalLanguage(lng) }
            if let cur = me.currency { self.currencyCode = cur }
            shouldPersistProfileChanges = true
        } catch {
            // Ignore
        }
    }

    @MainActor
    func syncProfileToServer() async {
        await persistProfile(language: languageCode, currency: currencyCode)
    }

    @MainActor
    func syncProfileMergeWithServer() async {
        let service = NetworkService()
        struct MeDTO: Decodable { let id: String; let name: String; let lastName: String?; let email: String?; let language: String?; let currency: String? }
        do {
            let me: MeDTO = try await service.get("/me")
            let serverLang = me.language.map { SettingsManager.canonicalLanguage($0) }
            let serverCur = me.currency
            let localLang = SettingsManager.canonicalLanguage(languageCode)
            let localCur = currencyCode
            let finalLang = localLang
            let finalCur = localCur
            shouldPersistProfileChanges = false
            languageCode = finalLang
            currencyCode = finalCur
            shouldPersistProfileChanges = true
            await persistProfile(language: finalLang, currency: finalCur)
        } catch {
            await persistProfile(language: languageCode, currency: currencyCode)
        }
    }

    private func persistProfile(language: String?, currency: String?) async {
        // Only persist when logged in
        let token = await TokenStore.shared.getAccessToken()
        guard token != nil else { return }
        let service = NetworkService()
        struct UpdateBody: Encodable { let language: String?; let currency: String? }
        struct MeDTO: Decodable { let id: String; let name: String; let lastName: String?; let email: String?; let language: String?; let currency: String? }
        do {
            let _: MeDTO = try await service.put("/me", body: UpdateBody(language: language, currency: currency))
        } catch {
            // Silently ignore; UI will remain updated locally
        }
    }

    // Persist when selection changes
    // didSet hooks via property observers are already applied to languageCode and currencyCode
}

extension SettingsManager {
    // didSet hooks to persist profile changes
    // Note: Swift does not allow didSet on published with extension, so implement property observers manually via willSet/didSet on properties.
}
