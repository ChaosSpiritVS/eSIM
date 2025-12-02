import Foundation

enum RegionCodeConverter {
    // 精简但覆盖广的 ISO 3166-1 三字母到两字母国家码映射。
    // 对未知代码不做处理，直接返回原始值以避免错误显示。
    private static let alpha3To2: [String: String] = [
        // Global pseudo-code
        "GLB": "WW",
        // 欧洲区域
        "ALB": "AL", "AND": "AD", "AUT": "AT", "BEL": "BE", "BGR": "BG", "BIH": "BA", "HRV": "HR",
        "CYP": "CY", "CZE": "CZ", "DNK": "DK", "EST": "EE", "FIN": "FI", "FRA": "FR", "DEU": "DE",
        "GRC": "GR", "HUN": "HU", "ISL": "IS", "IRL": "IE", "ITA": "IT", "LVA": "LV", "LTU": "LT",
        "LUX": "LU", "MLT": "MT", "MCO": "MC", "MNE": "ME", "MKD": "MK", "NLD": "NL", "NOR": "NO",
        "POL": "PL", "PRT": "PT", "ROU": "RO", "SVK": "SK", "SVN": "SI", "ESP": "ES", "SWE": "SE",
        "CHE": "CH", "GBR": "GB", "UKR": "UA", "RUS": "RU", "SRB": "RS", "MDA": "MD",

        // 亚洲区域
        "AFG": "AF", "ARM": "AM", "AZE": "AZ", "BHR": "BH", "BGD": "BD", "BRN": "BN", "KHM": "KH",
        "CHN": "CN", "GEO": "GE", "HKG": "HK", "IND": "IN", "IDN": "ID", "IRN": "IR", "IRQ": "IQ",
        "ISR": "IL", "JPN": "JP", "JOR": "JO", "KAZ": "KZ", "KWT": "KW", "KGZ": "KG", "LAO": "LA",
        "LBN": "LB", "MAC": "MO", "MYS": "MY", "MNG": "MN", "MMR": "MM", "NPL": "NP", "PRK": "KP",
        "KOR": "KR", "OMN": "OM", "PAK": "PK", "PSE": "PS", "PHL": "PH", "QAT": "QA", "SAU": "SA",
        "SGP": "SG", "LKA": "LK", "SYR": "SY", "TWN": "TW", "THA": "TH", "TUR": "TR", "ARE": "AE",
        "UZB": "UZ", "VNM": "VN", "YEM": "YE",

        // 非洲区域
        "DZA": "DZ", "AGO": "AO", "BEN": "BJ", "BWA": "BW", "BFA": "BF", "BDI": "BI", "CMR": "CM",
        "CPV": "CV", "CAF": "CF", "TCD": "TD", "COM": "KM", "COD": "CD", "COG": "CG", "CIV": "CI",
        "DJI": "DJ", "EGY": "EG", "GNQ": "GQ", "ERI": "ER", "SWZ": "SZ", "ETH": "ET", "GAB": "GA",
        "GMB": "GM", "GHA": "GH", "GIN": "GN", "GNB": "GW", "KEN": "KE", "LSO": "LS", "LBR": "LR",
        "LBY": "LY", "MDG": "MG", "MWI": "MW", "MLI": "ML", "MRT": "MR", "MUS": "MU", "MAR": "MA",
        "MOZ": "MZ", "NAM": "NA", "NER": "NE", "NGA": "NG", "RWA": "RW", "STP": "ST", "SEN": "SN",
        "SYC": "SC", "SLE": "SL", "SOM": "SO", "ZAF": "ZA", "SSD": "SS", "SDN": "SD", "TZA": "TZ",
        "TGO": "TG", "TUN": "TN", "UGA": "UG", "ZMB": "ZM", "ZWE": "ZW",

        // 美洲区域
        "ABW": "AW", "ARG": "AR", "BHS": "BS", "BRB": "BB", "BLZ": "BZ", "BOL": "BO", "BRA": "BR",
        "CAN": "CA", "CHL": "CL", "COL": "CO", "CRI": "CR", "CUB": "CU", "DMA": "DM", "DOM": "DO",
        "ECU": "EC", "SLV": "SV", "GRL": "GL", "GRD": "GD", "GTM": "GT", "GUY": "GY", "HTI": "HT",
        "HND": "HN", "JAM": "JM", "MEX": "MX", "NIC": "NI", "PAN": "PA", "PRY": "PY", "PER": "PE",
        "SUR": "SR", "TTO": "TT", "URY": "UY", "USA": "US", "VEN": "VE",

        // 大洋洲区域
        "AUS": "AU", "NZL": "NZ", "FJI": "FJ", "PNG": "PG", "SLB": "SB", "VUT": "VU", "WSM": "WS",
        "TON": "TO", "KIR": "KI", "NRU": "NR", "TUV": "TV", "MHL": "MH", "PLW": "PW",

        // 其他常见属地（避免与“亚洲”分组重复）
        "GGY": "GG", "JEY": "JE", "IMN": "IM", "BMU": "BM", "GIB": "GI",
        "CYM": "KY", "VIR": "VI", "NCL": "NC", "PYF": "PF"
    ]

    // 由 alpha3To2 反向构建两字母到三字母映射，便于请求需要 ISO3 的场景。
    private static let alpha2To3: [String: String] = {
        var dict: [String: String] = [:]
        for (a3, a2) in alpha3To2 { dict[a2] = a3 }
        return dict
    }()

    /// 将三字母国家码转换为两字母；若已是两字母或无映射则原样返回。
    /// - Parameter code: 两字母或三字母的地区/国家代码（不区分大小写，自动去除空白）。
    /// - Returns: 两字母国家码；若无映射则返回原始值（大写）。
    static func toAlpha2(_ code: String) -> String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.count == 2 { return normalized }
        if let mapped = alpha3To2[normalized] { return mapped }
        return normalized
    }

    /// 将两字母国家码转换为三字母；若已是三字母或无映射则原样返回。
    /// - Parameter code: 两字母或三字母的地区/国家代码（不区分大小写，自动去除空白）。
    /// - Returns: 三字母国家码；若无映射则返回原始值（大写）。
    static func toAlpha3(_ code: String) -> String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.count == 3 { return normalized }
        if let mapped = alpha2To3[normalized] { return mapped }
        return normalized
    }
}