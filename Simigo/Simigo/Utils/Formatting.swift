import Foundation

/// 价格格式化工具：将 `Decimal` 金额按指定货币代码格式化为本地化货币字符串。
enum PriceFormatter {
    static func string(amount: Decimal, currencyCode: String) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        let selected = (UserDefaults.standard.string(forKey: "simigo.currencyCode") ?? "").uppercased()
        let allowed = (UserDefaults.standard.array(forKey: "simigo.allowedCurrencies") as? [String])?.map { $0.uppercased() } ?? [
            "USD","EUR","GBP","CHF","CNY","HKD","JPY","SGD","KRW","THB","IDR","MYR","VND","BRL","MXN","TWD","AED","SAR","AUD","CAD"
        ]
        nf.currencyCode = Set(allowed).contains(selected) ? selected : currencyCode
        return nf.string(from: amount as NSDecimalNumber) ?? "\(currencyCode) \(amount)"
    }
}

private func canonicalLang(_ raw: String) -> String {
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

func loc(_ key: String) -> String {
    let stored = UserDefaults.standard.string(forKey: "simigo.languageCode")
    let codeRaw = stored ?? Locale.preferredLanguages.first ?? "en"
    let code = canonicalLang(codeRaw)
    if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let b = Bundle(path: path) {
        let v = b.localizedString(forKey: key, value: key, table: nil)
        if code == "zh-Hans" || code == "zh-Hant" { return v }
        if v != key { return v }
    }
    let s = NSLocalizedString(key, comment: "")
    if s != key { return s }
    if let path = Bundle.main.path(forResource: "en", ofType: "lproj"), let b = Bundle(path: path) {
        return b.localizedString(forKey: key, value: key, table: nil)
    }
    return key
}
/// 国家/地区旗帜渲染：将国家码转换为 emoji 旗帜。
/// 会先把三字母国家码转换为两字母（若无映射则原样返回），再构造区域指示符。
func countryFlag(_ code: String) -> String {
    let normalized = RegionCodeConverter.toAlpha2(code)
    guard normalized.count == 2 else { return normalized }
    let base: UInt32 = 127397
    var s = ""
    for v in normalized.unicodeScalars {
        if let scalar = UnicodeScalar(base + v.value) { s.append(String(scalar)) }
    }
    return s
}
