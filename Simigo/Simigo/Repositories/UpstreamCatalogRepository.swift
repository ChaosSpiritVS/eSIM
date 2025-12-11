import Foundation

//
// iOS 侧不再实现目录缓存，统一在后端进行。
//

// MARK: - 上游（alias 风格）商品仓库
protocol UpstreamCatalogRepositoryProtocol {
    // 列表：套餐（支持国家/地区/类别/排序筛选）
    func listBundles(
        pageNumber: Int,
        pageSize: Int,
        countryCode: String?,
        regionCode: String?,
        bundleCategory: String?,
        sortBy: String?,
        requestId: String?
    ) async throws -> [ESIMBundle]

    // 列表：国家
    func listCountries(requestId: String?) async throws -> [Country]

    // 列表：地区
    func listRegions(requestId: String?) async throws -> [Region]

    func getBundleNetworks(bundleCode: String, countryCode: String?, requestId: String?) async throws -> [String]

    func assignBundle(
        bundleCode: String,
        orderReference: String,
        name: String?,
        email: String?,
        requestId: String?
    ) async throws -> (orderId: String, iccid: String)

    func getBundleByCode(bundleCode: String, requestId: String?) async throws -> ESIMBundle
}

struct HTTPUpstreamCatalogRepository: UpstreamCatalogRepositoryProtocol {
    private let service = NetworkService()

    // 目录数据直接从后端获取，缓存由后端负责

    // 将分页大小限制为上游允许的取值，避免触发 1003 错误
    func safePageSize(_ size: Int) -> Int {
        let allowed = [10, 25, 50, 100]
        return allowed.contains(size) ? size : 25
    }

    // MARK: - 数据传输对象（DTO）
    struct BundleDTO: Decodable {
        let bundleCategory: String
        let bundleCode: String
        let bundleMarketingName: String
        let bundleName: String
        let bundleTag: [String]?
        let countryCode: [String]
        let countryName: [String]
        let dataUnit: String
        let gprsLimit: Double
        let isActive: Bool
        let regionCode: String?
        let regionName: String?
        let serviceType: String
        let smsAmount: Int
        let supportTopup: Bool
        let supportsCallsSms: Bool
        let unlimited: Bool
        let validity: Int
        let voiceAmount: Int?
        let resellerRetailPrice: Double
        let bundlePriceFinal: Double
        let status: Int?
        let allocateStatus: Int?
        let bundleSubscribePrice: Double?
        let bundleSalePrice: Double?
        let customSalePrice: Double?
        let bundlePriceActual: Double?
        private enum CodingKeys: String, CodingKey {
            case bundleCategory, bundleCode, bundleMarketingName, bundleName, bundleTag
            case countryCode, countryName, dataUnit, gprsLimit, isActive
            case regionCode, regionName, serviceType, smsAmount, supportTopup
            case supportsCallsSms, unlimited, validity, voiceAmount
            case resellerRetailPrice, bundlePriceFinal
            case status, allocateStatus
            case bundleSubscribePrice, bundleSalePrice, customSalePrice, bundlePriceActual
        }
        init(
            bundleCategory: String,
            bundleCode: String,
            bundleMarketingName: String,
            bundleName: String,
            bundleTag: [String]?,
            countryCode: [String],
            countryName: [String],
            dataUnit: String,
            gprsLimit: Double,
            isActive: Bool,
            regionCode: String?,
            regionName: String?,
            serviceType: String,
            smsAmount: Int,
            supportTopup: Bool,
            supportsCallsSms: Bool,
            unlimited: Bool,
            validity: Int,
            voiceAmount: Int?,
            resellerRetailPrice: Double,
            bundlePriceFinal: Double,
            status: Int? = nil,
            allocateStatus: Int? = nil,
            bundleSubscribePrice: Double? = nil,
            bundleSalePrice: Double? = nil,
            customSalePrice: Double? = nil,
            bundlePriceActual: Double? = nil
        ) {
            self.bundleCategory = bundleCategory
            self.bundleCode = bundleCode
            self.bundleMarketingName = bundleMarketingName
            self.bundleName = bundleName
            self.bundleTag = bundleTag
            self.countryCode = countryCode
            self.countryName = countryName
            self.dataUnit = dataUnit
            self.gprsLimit = gprsLimit
            self.isActive = isActive
            self.regionCode = regionCode
            self.regionName = regionName
            self.serviceType = serviceType
            self.smsAmount = smsAmount
            self.supportTopup = supportTopup
            self.supportsCallsSms = supportsCallsSms
            self.unlimited = unlimited
            self.validity = validity
            self.voiceAmount = voiceAmount
            self.resellerRetailPrice = resellerRetailPrice
            self.bundlePriceFinal = bundlePriceFinal
            self.status = status
            self.allocateStatus = allocateStatus
            self.bundleSubscribePrice = bundleSubscribePrice
            self.bundleSalePrice = bundleSalePrice
            self.customSalePrice = customSalePrice
            self.bundlePriceActual = bundlePriceActual
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func decodeDoubleOrZero(for key: CodingKeys) -> Double {
                if let v = try? c.decode(Double.self, forKey: key) { return v }
                if let s = try? c.decode(String.self, forKey: key), let v = Double(s) { return v }
                return 0.0
            }
            func decodeIntOrZero(for key: CodingKeys) -> Int {
                if let v = try? c.decode(Int.self, forKey: key) { return v }
                if let s = try? c.decode(String.self, forKey: key), let v = Int(s) { return v }
                return 0
            }
            func decodeOptionalInt(for key: CodingKeys) -> Int? {
                if let v = try? c.decode(Int.self, forKey: key) { return v }
                if let s = try? c.decode(String.self, forKey: key), let v = Int(s) { return v }
                return nil
            }
            func decodeOptionalDouble(for key: CodingKeys) -> Double? {
                if let v = try? c.decode(Double.self, forKey: key) { return v }
                if let s = try? c.decode(String.self, forKey: key), let v = Double(s) { return v }
                return nil
            }
            self.bundleCategory = (try? c.decode(String.self, forKey: .bundleCategory)) ?? ""
            self.bundleCode = (try? c.decode(String.self, forKey: .bundleCode)) ?? ""
            self.bundleMarketingName = (try? c.decode(String.self, forKey: .bundleMarketingName)) ?? ""
            self.bundleName = (try? c.decode(String.self, forKey: .bundleName)) ?? ""
            self.bundleTag = try? c.decode([String].self, forKey: .bundleTag)
            self.countryCode = (try? c.decode([String].self, forKey: .countryCode)) ?? []
            self.countryName = (try? c.decode([String].self, forKey: .countryName)) ?? []
            self.dataUnit = (try? c.decode(String.self, forKey: .dataUnit)) ?? ""
            self.gprsLimit = decodeDoubleOrZero(for: .gprsLimit)
            self.isActive = (try? c.decode(Bool.self, forKey: .isActive)) ?? false
            self.regionCode = try? c.decode(String.self, forKey: .regionCode)
            self.regionName = try? c.decode(String.self, forKey: .regionName)
            self.serviceType = (try? c.decode(String.self, forKey: .serviceType)) ?? ""
            self.smsAmount = decodeIntOrZero(for: .smsAmount)
            self.supportTopup = (try? c.decode(Bool.self, forKey: .supportTopup)) ?? false
            self.supportsCallsSms = (try? c.decode(Bool.self, forKey: .supportsCallsSms)) ?? false
            self.unlimited = (try? c.decode(Bool.self, forKey: .unlimited)) ?? false
            self.validity = decodeIntOrZero(for: .validity)
            self.voiceAmount = decodeOptionalInt(for: .voiceAmount)
            self.resellerRetailPrice = decodeDoubleOrZero(for: .resellerRetailPrice)
            self.bundlePriceFinal = decodeDoubleOrZero(for: .bundlePriceFinal)
            self.status = (try? c.decode(Int.self, forKey: .status)) ?? ((try? c.decode(String.self, forKey: .status)).flatMap { Int($0) })
            self.allocateStatus = (try? c.decode(Int.self, forKey: .allocateStatus)) ?? ((try? c.decode(String.self, forKey: .allocateStatus)).flatMap { Int($0) })
            self.bundleSubscribePrice = decodeOptionalDouble(for: .bundleSubscribePrice)
            self.bundleSalePrice = decodeOptionalDouble(for: .bundleSalePrice)
            self.customSalePrice = decodeOptionalDouble(for: .customSalePrice)
            self.bundlePriceActual = decodeOptionalDouble(for: .bundlePriceActual)
        }
    }

    // 国家 DTO（别名风格 /bundle/countries，文档字段：iso2_code、iso3_code、country_name、countries_count）
    struct CountryDTO: Decodable {
        let iso2Code: String
        let iso3Code: String
        let countryName: String

        private enum CodingKeys: String, CodingKey {
            case iso2Code
            case iso3Code
            case countryName
            // 兼容非规范返回：code/name
            case code
            case name
            // 显式蛇形（若未启用转换或服务端不一致）
            case iso2_code
            case iso3_code
            case country_name
        }

        init(iso2Code: String, iso3Code: String, countryName: String) {
            self.iso2Code = iso2Code
            self.iso3Code = iso3Code
            self.countryName = countryName
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // 优先使用文档字段，其次蛇形兼容，最后回退到 code/name
            let iso2 = (try? c.decode(String.self, forKey: .iso2Code))
                ?? (try? c.decode(String.self, forKey: .iso2_code))
                ?? (try? c.decode(String.self, forKey: .code))
            let name = (try? c.decode(String.self, forKey: .countryName))
                ?? (try? c.decode(String.self, forKey: .country_name))
                ?? (try? c.decode(String.self, forKey: .name))
            let iso3 = (try? c.decode(String.self, forKey: .iso3Code))
                ?? (try? c.decode(String.self, forKey: .iso3_code))

            guard let iso2Code = iso2, let countryName = name, let iso3Code = iso3 else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: c.codingPath, debugDescription: "Missing iso2/iso3/countryName in CountryDTO")
                )
            }
            self.iso2Code = iso2Code
            self.iso3Code = iso3Code
            self.countryName = countryName
        }
    }
    struct CountriesDataDTO: Decodable {
        let countries: [CountryDTO]
        let countriesCount: Int

        private enum CodingKeys: String, CodingKey {
            case countries
            case countriesCount
        }

        init(countries: [CountryDTO], countriesCount: Int) {
            self.countries = countries
            self.countriesCount = countriesCount
        }

        init(from decoder: Decoder) throws {
            // 兼容两种返回：
            // 1) 对象 { countries: [...], countries_count: N }
            // 2) 直接数组 [...]
            if let keyed = try? decoder.container(keyedBy: CodingKeys.self) {
                let items = (try? keyed.decode([CountryDTO].self, forKey: .countries)) ?? []
                let count = try? keyed.decode(Int.self, forKey: .countriesCount)
                self.countries = items
                self.countriesCount = count ?? items.count
                return
            }
            var unkeyed = try decoder.unkeyedContainer()
            var arr: [CountryDTO] = []
            while !unkeyed.isAtEnd {
                let item = try unkeyed.decode(CountryDTO.self)
                arr.append(item)
            }
            self.countries = arr
            self.countriesCount = arr.count
        }
    }

    // 地区 DTO（别名风格 /bundle/regions）
    struct RegionDTO: Decodable {
        let code: String
        let name: String

        private enum CodingKeys: String, CodingKey {
            case code
            case name
            case region_code
            case region_name
        }

        init(code: String, name: String) {
            self.code = code
            self.name = name
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let code = (try? c.decode(String.self, forKey: .code))
                ?? (try? c.decode(String.self, forKey: .region_code))
            let name = (try? c.decode(String.self, forKey: .name))
                ?? (try? c.decode(String.self, forKey: .region_name))
            guard let code = code, let name = name else {
                throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Missing region code/name"))
            }
            self.code = code
            self.name = name
        }
    }
    struct RegionsDataDTO: Decodable {
        let regions: [RegionDTO]
        let regionsCount: Int

        private enum CodingKeys: String, CodingKey {
            case regions
            case regionsCount
        }

        init(regions: [RegionDTO], regionsCount: Int) {
            self.regions = regions
            self.regionsCount = regionsCount
        }

        init(from decoder: Decoder) throws {
            // 兼容两种返回：
            // 1) 对象 { regions: [...], regions_count: N }
            // 2) 直接数组 [...]
            if let keyed = try? decoder.container(keyedBy: CodingKeys.self) {
                let items = (try? keyed.decode([RegionDTO].self, forKey: .regions)) ?? []
                let count = try? keyed.decode(Int.self, forKey: .regionsCount)
                self.regions = items
                self.regionsCount = count ?? items.count
                return
            }
            var unkeyed = try decoder.unkeyedContainer()
            var arr: [RegionDTO] = []
            while !unkeyed.isAtEnd {
                let item = try unkeyed.decode(RegionDTO.self)
                arr.append(item)
            }
            self.regions = arr
            self.regionsCount = arr.count
        }
    }

    struct NetworksItemDTO: Decodable {
        let countryCode: String
        let operatorList: [String]

        private enum CodingKeys: String, CodingKey {
            case countryCode
            case operatorList
            case country_code
            case operator_list
        }

        init(countryCode: String, operatorList: [String]) {
            self.countryCode = countryCode
            self.operatorList = operatorList
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let code = (try? c.decode(String.self, forKey: .countryCode))
                ?? (try? c.decode(String.self, forKey: .country_code))
            let ops = (try? c.decode([String].self, forKey: .operatorList))
                ?? (try? c.decode([String].self, forKey: .operator_list))
                ?? []
            guard let code = code else {
                throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Missing countryCode in NetworksItemDTO"))
            }
            self.countryCode = code
            self.operatorList = ops
        }
    }

    struct NetworksDataDTO: Decodable {
        let networks: [NetworksItemDTO]
        let networksCount: Int

        private enum CodingKeys: String, CodingKey {
            case networks
            case networksCount
        }

        init(networks: [NetworksItemDTO], networksCount: Int) {
            self.networks = networks
            self.networksCount = networksCount
        }

        init(from decoder: Decoder) throws {
            if let keyed = try? decoder.container(keyedBy: CodingKeys.self) {
                let items = (try? keyed.decode([NetworksItemDTO].self, forKey: .networks)) ?? []
                let count = try? keyed.decode(Int.self, forKey: .networksCount)
                self.networks = items
                self.networksCount = count ?? items.count
                return
            }
            var unkeyed = try decoder.unkeyedContainer()
            var arr: [NetworksItemDTO] = []
            while !unkeyed.isAtEnd {
                let item = try unkeyed.decode(NetworksItemDTO.self)
                arr.append(item)
            }
            self.networks = arr
            self.networksCount = arr.count
        }
    }

    struct OperatorsDataDTO: Decodable {
        let operators: [String]
        let operatorsCount: Int

        private enum CodingKeys: String, CodingKey {
            case operators
            case operatorsCount
            case operators_count
        }

        init(operators: [String], operatorsCount: Int) {
            self.operators = operators
            self.operatorsCount = operatorsCount
        }

        init(from decoder: Decoder) throws {
            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            let ops = (try? keyed.decode([String].self, forKey: .operators)) ?? []
            let countCamel = try? keyed.decode(Int.self, forKey: .operatorsCount)
            let countSnake = try? keyed.decode(Int.self, forKey: .operators_count)
            self.operators = ops
            self.operatorsCount = countCamel ?? countSnake ?? ops.count
        }
    }

    struct BundleListDataDTO: Decodable {
        let bundles: [BundleDTO]
        let bundlesCount: Int?

        private enum CodingKeys: String, CodingKey {
            case bundles
            case bundlesCount
        }

        init(bundles: [BundleDTO], bundlesCount: Int?) {
            self.bundles = bundles
            self.bundlesCount = bundlesCount
        }

        init(from decoder: Decoder) throws {
            if let keyed = try? decoder.container(keyedBy: CodingKeys.self) {
                let bundles = (try? keyed.decode([BundleDTO].self, forKey: .bundles)) ?? []
                let count = try? keyed.decode(Int.self, forKey: .bundlesCount)
                self.bundles = bundles
                self.bundlesCount = count ?? bundles.count
                return
            }
            var unkeyed = try decoder.unkeyedContainer()
            var arr: [BundleDTO] = []
            while !unkeyed.isAtEnd {
                let item = try unkeyed.decode(BundleDTO.self)
                arr.append(item)
            }
            self.bundles = arr
            self.bundlesCount = arr.count
        }
    }

    struct SimpleBundleDTO: Decodable {
        let id: String
        let name: String
        let countryCode: String
        let price: Double
        let currency: String
        let dataAmount: String
        let validityDays: Int
        let description: String?
        let supportedNetworks: [String]?
        let hotspotSupported: Bool?
        let coverageNote: String?
        let termsUrl: String?
    }

    struct BundleListBody: Encodable {
        let pageNumber: Int
        let pageSize: Int
        let countryCode: String?
        let regionCode: String?
        let bundleCategory: String?
        let sortBy: String?
    }

    struct BundleNetworksBody: Encodable { let bundleCode: String; let countryCode: String? }

    struct BundleAssignBody: Encodable {
        let bundleCode: String
        let orderReference: String
        let name: String?
        let email: String?
    }
    struct BundleAssignResultDTO: Decodable { let orderId: String; let iccid: String }

    // MARK: - 接口方法
    func listBundles(
        pageNumber: Int,
        pageSize: Int,
        countryCode: String? = nil,
        regionCode: String? = nil,
        bundleCategory: String? = nil,
        sortBy: String? = nil,
        requestId: String? = nil
    ) async throws -> [ESIMBundle] {
        let lang = UserDefaults.standard.string(forKey: "simigo.languageCode") ?? Locale.preferredLanguages.first ?? "en"
        let iso3Country = countryCode.map { RegionCodeConverter.toAlpha3($0) }
        let key = "bundle:list|\(lang)|\(pageNumber)|\(safePageSize(pageSize))|\(iso3Country ?? "-")|\(regionCode ?? "-")|\(bundleCategory ?? "-")|\(sortBy ?? "-")"

        let useGET = (regionCode == nil) && (bundleCategory == nil) && (sortBy == nil) && (pageNumber == 1)

        if useGET {
            let q: [String: String]? = {
                if let c2 = countryCode, !c2.isEmpty { return ["country": c2] }
                return nil
            }()
            let list: [ESIMBundle] = try await RequestCenter.shared.singleFlight(key: key) {
                let dtos: [SimpleBundleDTO] = try await service.get("/catalog/bundles", query: q)
                let mapped = dtos.map { dto in
                    ESIMBundle(
                        id: dto.id,
                        name: dto.name,
                        countryCode: RegionCodeConverter.toAlpha2(dto.countryCode),
                        price: Decimal(dto.price),
                        currency: dto.currency,
                        dataAmount: dto.dataAmount,
                        validityDays: dto.validityDays,
                        description: dto.description,
                        supportedNetworks: dto.supportedNetworks,
                        hotspotSupported: dto.hotspotSupported,
                        coverageNote: dto.coverageNote,
                        termsURL: dto.termsUrl
                    )
                }
                if mapped.count > safePageSize(pageSize) {
                    return Array(mapped.prefix(safePageSize(pageSize)))
                }
                return mapped
            }
            return list
        }

        let body = BundleListBody(
            pageNumber: pageNumber,
            pageSize: safePageSize(pageSize),
            countryCode: iso3Country,
            regionCode: regionCode,
            bundleCategory: bundleCategory,
            sortBy: sortBy
        )
        let bundles: [ESIMBundle] = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<BundleListDataDTO> = try await service.postEnvelope("/bundle/list", body: body, requestId: requestId)
            return env.data.bundles.map { dto in
                let isRegional = dto.bundleCategory.lowercased() != "country"
                let code2 = isRegional ? "" : RegionCodeConverter.toAlpha2(dto.countryCode.first ?? "")
                let name = dto.bundleMarketingName
                let amountStr: String = {
                    let v = dto.gprsLimit
                    let u = dto.dataUnit
                    if u.isEmpty { return String(format: "%.0f", v) }
                    return String(format: "%g %@", v, u)
                }()
                let priceResolved: Double = {
                    if let p = dto.bundlePriceActual, p > 0 { return p }
                    if let p = dto.bundleSalePrice, p > 0 { return p }
                    if let p = dto.customSalePrice, p > 0 { return p }
                    if dto.bundlePriceFinal > 0 { return dto.bundlePriceFinal }
                    if dto.resellerRetailPrice > 0 { return dto.resellerRetailPrice }
                    return 0.0
                }()
                return ESIMBundle(
                    id: dto.bundleCode,
                    name: name,
                    countryCode: code2,
                    price: Decimal(priceResolved),
                    currency: "GBP",
                    dataAmount: amountStr,
                    validityDays: dto.validity,
                    description: dto.bundleMarketingName,
                    supportedNetworks: nil,
                    hotspotSupported: nil,
                    coverageNote: nil,
                    termsURL: nil,
                    bundleTag: dto.bundleTag,
                    isActive: dto.isActive,
                    serviceType: dto.serviceType,
                    supportTopup: dto.supportTopup,
                    unlimited: dto.unlimited
                )
            }
        }
        return bundles
    }

    struct BundleDetailBody: Encodable { let bundleCode: String }
    struct EnvelopeDataDTO: Decodable { let id: String; let name: String; let countryCode: String; let price: Double; let currency: String; let dataAmount: String; let validityDays: Int; let description: String?; let supportedNetworks: [String]?; let hotspotSupported: Bool?; let coverageNote: String?; let termsUrl: String?; let bundleTag: [String]?; let isActive: Bool?; let serviceType: String?; let supportTopup: Bool?; let unlimited: Bool? }

    func getBundleByCode(bundleCode: String, requestId: String? = nil) async throws -> ESIMBundle {
        let key = ["bundle:detail:code", bundleCode].joined(separator: "|")
        let bundle: ESIMBundle = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<EnvelopeDataDTO> = try await service.postEnvelope("/bundle/detail-by-code", body: BundleDetailBody(bundleCode: bundleCode), requestId: requestId)
            let dto = env.data
            return ESIMBundle(
                id: dto.id,
                name: dto.name,
                countryCode: RegionCodeConverter.toAlpha2(dto.countryCode),
                price: Decimal(dto.price),
                currency: dto.currency,
                dataAmount: dto.dataAmount,
                validityDays: dto.validityDays,
                description: dto.description,
                supportedNetworks: dto.supportedNetworks,
                hotspotSupported: dto.hotspotSupported,
                coverageNote: dto.coverageNote,
                termsURL: dto.termsUrl,
                bundleTag: dto.bundleTag,
                isActive: dto.isActive,
                serviceType: dto.serviceType,
                supportTopup: dto.supportTopup,
                unlimited: dto.unlimited
            )
        }
        return bundle
    }

    func listCountries(requestId: String? = nil) async throws -> [Country] {
        // POST /bundle/countries，Envelope 形式
        struct EmptyBody: Encodable {}
        let lang = UserDefaults.standard.string(forKey: "simigo.languageCode") ?? Locale.preferredLanguages.first ?? "en"
        let key = "bundle:countries|\(lang)"
        let countries: [Country] = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<CountriesDataDTO> = try await service.postEnvelope("/bundle/countries", body: EmptyBody(), requestId: requestId)
            return env.data.countries.map { Country(code: $0.iso2Code.uppercased(), name: $0.countryName) }
        }
        return countries
    }

    func listRegions(requestId: String? = nil) async throws -> [Region] {
        // POST /bundle/regions，Envelope 形式
        struct EmptyBody: Encodable {}
        let lang = UserDefaults.standard.string(forKey: "simigo.languageCode") ?? Locale.preferredLanguages.first ?? "en"
        let key = "bundle:regions|\(lang)"
        let regions: [Region] = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<RegionsDataDTO> = try await service.postEnvelope("/bundle/regions", body: EmptyBody(), requestId: requestId)
            // 保留服务端原始大小写，避免与筛选使用的值不一致
            return env.data.regions.map { Region(code: $0.code, name: $0.name) }
        }
        return regions
    }

    func getBundleNetworks(bundleCode: String, countryCode: String? = nil, requestId: String? = nil) async throws -> [String] {
        let iso3Country = countryCode.map { RegionCodeConverter.toAlpha3($0) }
        let body = BundleNetworksBody(bundleCode: bundleCode, countryCode: iso3Country)
        let key = ["bundle:networks", bundleCode, iso3Country ?? "-"] .joined(separator: "|")
        let operators: [String] = try await RequestCenter.shared.singleFlight(key: key) {
            let env: Envelope<OperatorsDataDTO> = try await service.postEnvelope("/bundle/networks/flat", body: body, requestId: requestId)
            return env.data.operators
        }
        return operators
    }

    func assignBundle(
        bundleCode: String,
        orderReference: String,
        name: String? = nil,
        email: String? = nil,
        requestId: String? = nil
    ) async throws -> (orderId: String, iccid: String) {
        let body = BundleAssignBody(bundleCode: bundleCode, orderReference: orderReference, name: name, email: email)
        let env: Envelope<BundleAssignResultDTO> = try await service.postEnvelope("/bundle/assign", body: body, requestId: requestId)
        return (env.data.orderId, env.data.iccid)
    }
}
