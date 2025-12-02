import Foundation
import CoreData

// SWR 缓存存储：仅负责读写与 TTL 判断；调用方（ViewModel）实现“先渲染后校验”
final class CatalogCacheStore {
    static let shared = CatalogCacheStore()
    private let stack = CoreDataStack.shared
    private init() {}

    // 环境前缀：区分 Mock 与真实后端缓存
    private func envPrefix() -> String {
        AppConfig.isMock ? "env:mock" : "env:prod"
    }

    private func userPrefix() -> String {
        if let uid = UserDefaults.standard.string(forKey: "simigo.currentUserId") { return "user:\(uid)" }
        let staleOk = UserDefaults.standard.bool(forKey: "simigo.useStaleCache")
        if staleOk, let sid = UserDefaults.standard.string(forKey: "simigo.staleUserId") { return "user:\(sid)" }
        return "user:-"
    }

    private func canonicalLanguage(_ raw: String) -> String {
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

    private func languageTag() -> String {
        let stored = UserDefaults.standard.string(forKey: "simigo.languageCode")
        let sys = Locale.preferredLanguages.first ?? "en"
        return canonicalLanguage(stored ?? sys)
    }

    private func prefixedKey(_ raw: String) -> String {
        "\(envPrefix()):\(userPrefix()):\(raw)"
    }

    func clearAllForCurrentUser() {
        let prefix = "\(envPrefix()):\(userPrefix()):"
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key BEGINSWITH %@", prefix)
            if let entries = try? stack.context.fetch(req) {
                for e in entries { stack.context.delete(e) }
                try? stack.context.save()
            }
        }
    }

    // MARK: - Bundles 列表缓存
    // 返回 (列表, 是否过期)；若无缓存返回 nil
    func loadBundles(key: String, ttl: TimeInterval) -> (list: [ESIMBundle], isExpired: Bool)? {
        var result: (list: [ESIMBundle], isExpired: Bool)? = nil
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            let rawKey = key
            let envKey = prefixedKey(rawKey)
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", envKey, rawKey)
            req.fetchLimit = 1
            if let entry = try? stack.context.fetch(req).first {
                let age = Date().timeIntervalSince(entry.updatedAt)
                if let list = try? JSONDecoder().decode([ESIMBundle].self, from: entry.value) {
                    result = (list, age > ttl)
                }
            }
        }
        return result
    }

    func saveBundles(_ list: [ESIMBundle], key: String) {
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            let rawKey = key
            let envKey = prefixedKey(rawKey)
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", envKey, rawKey)
            req.fetchLimit = 1
            let entry: CacheEntry
            if let found = try? stack.context.fetch(req).first { entry = found }
            else {
                entry = CacheEntry(entity: stack.model.entitiesByName["CacheEntry"]!, insertInto: stack.context)
                entry.key = envKey
            }
            // 统一迁移到带前缀的 key
            entry.key = envKey
            entry.updatedAt = Date()
            entry.value = (try? JSONEncoder().encode(list)) ?? Data()
            try? stack.context.save()
        }
    }

    // MARK: - 通用键规则（bundles 列表）
    // 统一 key 版本，避免未来字段调整导致命中问题
    func bundlesKey(pageNumber: Int,
                    pageSize: Int,
                    countryCode: String?,
                    regionCode: String?,
                    bundleCategory: String?,
                    sortBy: String?) -> String {
        let v = "v1" // key 版本
        let c = countryCode ?? "-"
        let r = regionCode ?? "-"
        let b = bundleCategory ?? "-"
        let s = sortBy ?? "-"
        let l = languageTag()
        return "bundles:\(v):p\(pageNumber)-\(pageSize):c\(c):r\(r):b\(b):s\(s):l\(l)"
    }

    // MARK: - Countries 列表缓存
    func loadCountries(ttl: TimeInterval) -> (list: [Country], isExpired: Bool)? {
        let rawKey = countriesKey()
        let key = prefixedKey(rawKey)
        var result: (list: [Country], isExpired: Bool)? = nil
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            if let entry = try? stack.context.fetch(req).first {
                let age = Date().timeIntervalSince(entry.updatedAt)
                if let list = try? JSONDecoder().decode([Country].self, from: entry.value) {
                    result = (list, age > ttl)
                }
            }
        }
        return result
    }

    func saveCountries(_ list: [Country]) {
        let rawKey = countriesKey()
        let key = prefixedKey(rawKey)
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            let entry: CacheEntry
            if let found = try? stack.context.fetch(req).first { entry = found }
            else {
                entry = CacheEntry(entity: stack.model.entitiesByName["CacheEntry"]!, insertInto: stack.context)
                entry.key = key
            }
            entry.key = key
            entry.updatedAt = Date()
            entry.value = (try? JSONEncoder().encode(list)) ?? Data()
            try? stack.context.save()
        }
    }

    func countriesKey() -> String {
        let v = "v1"
        let l = languageTag()
        return "countries:\(v):l\(l)"
    }

    // MARK: - Regions 列表缓存
    func loadRegions(ttl: TimeInterval) -> (list: [Region], isExpired: Bool)? {
        let rawKey = regionsKey()
        let key = prefixedKey(rawKey)
        var result: (list: [Region], isExpired: Bool)? = nil
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            if let entry = try? stack.context.fetch(req).first {
                let age = Date().timeIntervalSince(entry.updatedAt)
                if let list = try? JSONDecoder().decode([Region].self, from: entry.value) {
                    result = (list, age > ttl)
                }
            }
        }
        return result
    }

    func saveRegions(_ list: [Region]) {
        let rawKey = regionsKey()
        let key = prefixedKey(rawKey)
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            let entry: CacheEntry
            if let found = try? stack.context.fetch(req).first { entry = found }
            else {
                entry = CacheEntry(entity: stack.model.entitiesByName["CacheEntry"]!, insertInto: stack.context)
                entry.key = key
            }
            entry.key = key
            entry.updatedAt = Date()
            entry.value = (try? JSONEncoder().encode(list)) ?? Data()
            try? stack.context.save()
        }
    }

    func regionsKey() -> String {
        let v = "v1"
        let l = languageTag()
        return "regions:\(v):l\(l)"
    }

    // MARK: - Orders 列表缓存
    func loadOrders(ttl: TimeInterval) -> (list: [Order], isExpired: Bool)? {
        let rawKey = ordersKey()
        let key = prefixedKey(rawKey)
        var result: (list: [Order], isExpired: Bool)? = nil
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            if let entry = try? stack.context.fetch(req).first {
                let age = Date().timeIntervalSince(entry.updatedAt)
                if let list = try? JSONDecoder().decode([Order].self, from: entry.value) {
                    let staleOk = UserDefaults.standard.bool(forKey: "simigo.useStaleCache")
                    result = (list, staleOk ? false : (age > ttl))
                }
            }
        }
        return result
    }

    func saveOrders(_ list: [Order]) {
        let rawKey = ordersKey()
        let key = prefixedKey(rawKey)
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            let entry: CacheEntry
            if let found = try? stack.context.fetch(req).first { entry = found }
            else {
                entry = CacheEntry(entity: stack.model.entitiesByName["CacheEntry"]!, insertInto: stack.context)
                entry.key = key
            }
            entry.key = key
            entry.updatedAt = Date()
            entry.value = (try? JSONEncoder().encode(list)) ?? Data()
            try? stack.context.save()
        }
    }

    func ordersKey() -> String {
        let v = "v1"
        return "orders:\(v)"
    }

    // MARK: - 单个 Order 缓存
    func loadOrder(id: String, ttl: TimeInterval) -> (item: Order, isExpired: Bool)? {
        let rawKey = orderKey(id: id)
        let key = prefixedKey(rawKey)
        var result: (item: Order, isExpired: Bool)? = nil
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            if let entry = try? stack.context.fetch(req).first {
                let age = Date().timeIntervalSince(entry.updatedAt)
                if let item = try? JSONDecoder().decode(Order.self, from: entry.value) {
                    let staleOk = UserDefaults.standard.bool(forKey: "simigo.useStaleCache")
                    result = (item, staleOk ? false : (age > ttl))
                }
            }
        }
        return result
    }

    func saveOrder(_ item: Order, id: String) {
        let rawKey = orderKey(id: id)
        let key = prefixedKey(rawKey)
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            let entry: CacheEntry
            if let found = try? stack.context.fetch(req).first { entry = found }
            else {
                entry = CacheEntry(entity: stack.model.entitiesByName["CacheEntry"]!, insertInto: stack.context)
                entry.key = key
            }
            entry.key = key
            entry.updatedAt = Date()
            entry.value = (try? JSONEncoder().encode(item)) ?? Data()
            try? stack.context.save()
        }
    }

    func orderKey(id: String) -> String {
        let v = "v1"
        return "order:\(v):\(id)"
    }

    // MARK: - OrderUsage 缓存（短 TTL）
    func loadOrderUsage(orderId: String, ttl: TimeInterval) -> (item: OrderUsage, isExpired: Bool)? {
        let rawKey = orderUsageKey(orderId: orderId)
        let key = prefixedKey(rawKey)
        var result: (item: OrderUsage, isExpired: Bool)? = nil
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            if let entry = try? stack.context.fetch(req).first {
                let age = Date().timeIntervalSince(entry.updatedAt)
                if let item = try? JSONDecoder().decode(OrderUsage.self, from: entry.value) {
                    let staleOk = UserDefaults.standard.bool(forKey: "simigo.useStaleCache")
                    result = (item, staleOk ? false : (age > ttl))
                }
            }
        }
        return result
    }

    func saveOrderUsage(_ item: OrderUsage, orderId: String) {
        let rawKey = orderUsageKey(orderId: orderId)
        let key = prefixedKey(rawKey)
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            let entry: CacheEntry
            if let found = try? stack.context.fetch(req).first { entry = found }
            else {
                entry = CacheEntry(entity: stack.model.entitiesByName["CacheEntry"]!, insertInto: stack.context)
                entry.key = key
            }
            entry.key = key
            entry.updatedAt = Date()
            entry.value = (try? JSONEncoder().encode(item)) ?? Data()
            try? stack.context.save()
        }
    }

    // 显式失效订单用量缓存（退款、充值、安装变更等场景可触发）
    func invalidateOrderUsage(orderId: String) {
        let rawKey = orderUsageKey(orderId: orderId)
        let key = prefixedKey(rawKey)
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            if let entries = try? stack.context.fetch(req) {
                for entry in entries { stack.context.delete(entry) }
                try? stack.context.save()
            }
        }
    }

    func orderUsageKey(orderId: String) -> String {
        let v = "v1"
        return "order:usage:\(v):\(orderId)"
    }

    // MARK: - Agent 账户缓存
    func loadAgentAccount(ttl: TimeInterval) -> (item: HTTPUpstreamAgentRepository.AgentAccountDTO, isExpired: Bool)? {
        let rawKey = agentAccountKey()
        let key = prefixedKey(rawKey)
        var result: (item: HTTPUpstreamAgentRepository.AgentAccountDTO, isExpired: Bool)? = nil
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            if let entry = try? stack.context.fetch(req).first {
                let age = Date().timeIntervalSince(entry.updatedAt)
                if let item = try? JSONDecoder().decode(HTTPUpstreamAgentRepository.AgentAccountDTO.self, from: entry.value) {
                    result = (item, age > ttl)
                }
            }
        }
        return result
    }

    func saveAgentAccount(_ item: HTTPUpstreamAgentRepository.AgentAccountDTO) {
        let rawKey = agentAccountKey()
        let key = prefixedKey(rawKey)
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            let entry: CacheEntry
            if let found = try? stack.context.fetch(req).first { entry = found }
            else {
                entry = CacheEntry(entity: stack.model.entitiesByName["CacheEntry"]!, insertInto: stack.context)
                entry.key = key
            }
            entry.key = key
            entry.updatedAt = Date()
            entry.value = (try? JSONEncoder().encode(item)) ?? Data()
            try? stack.context.save()
        }
    }

    func agentAccountKey() -> String {
        let v = "v1"
        return "agent:account:\(v)"
    }

    // MARK: - Agent 账单缓存（带筛选条件）
    func loadAgentBills(pageNumber: Int, pageSize: Int, reference: String?, startDate: String?, endDate: String?, ttl: TimeInterval) -> (list: [HTTPUpstreamAgentRepository.AgentBillDTO], isExpired: Bool)? {
        let rawKey = agentBillsKey(pageNumber: pageNumber, pageSize: pageSize, reference: reference, startDate: startDate, endDate: endDate)
        let key = prefixedKey(rawKey)
        var result: (list: [HTTPUpstreamAgentRepository.AgentBillDTO], isExpired: Bool)? = nil
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            if let entry = try? stack.context.fetch(req).first {
                let age = Date().timeIntervalSince(entry.updatedAt)
                if let list = try? JSONDecoder().decode([HTTPUpstreamAgentRepository.AgentBillDTO].self, from: entry.value) {
                    result = (list, age > ttl)
                }
            }
        }
        return result
    }

    func saveAgentBills(_ list: [HTTPUpstreamAgentRepository.AgentBillDTO], pageNumber: Int, pageSize: Int, reference: String?, startDate: String?, endDate: String?) {
        let rawKey = agentBillsKey(pageNumber: pageNumber, pageSize: pageSize, reference: reference, startDate: startDate, endDate: endDate)
        let key = prefixedKey(rawKey)
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            let entry: CacheEntry
            if let found = try? stack.context.fetch(req).first { entry = found }
            else {
                entry = CacheEntry(entity: stack.model.entitiesByName["CacheEntry"]!, insertInto: stack.context)
                entry.key = key
            }
            entry.key = key
            entry.updatedAt = Date()
            entry.value = (try? JSONEncoder().encode(list)) ?? Data()
            try? stack.context.save()
        }
    }

    func agentBillsKey(pageNumber: Int, pageSize: Int, reference: String?, startDate: String?, endDate: String?) -> String {
        let v = "v1"
        let p = "p\(pageNumber)-\(pageSize)"
        let ref = (reference?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? "-" : reference!
        let s = (startDate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? "-" : startDate!
        let e = (endDate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? "-" : endDate!
        return "agent:bills:\(v):\(p):ref=\(ref):s=\(s):e=\(e)"
    }

    // MARK: - Bundle 网络列表缓存
    func loadBundleNetworks(bundleCode: String, ttl: TimeInterval) -> (list: [String], isExpired: Bool)? {
        let rawKey = bundleNetworksKey(bundleCode: bundleCode)
        let key = prefixedKey(rawKey)
        var result: (list: [String], isExpired: Bool)? = nil
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            if let entry = try? stack.context.fetch(req).first {
                let age = Date().timeIntervalSince(entry.updatedAt)
                if let list = try? JSONDecoder().decode([String].self, from: entry.value) {
                    result = (list, age > ttl)
                }
            }
        }
        return result
    }

    func saveBundleName(_ name: String, bundleId: String) {
        let rawKey = bundleNameKey(bundleId: bundleId)
        let key = prefixedKey(rawKey)
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            let entry: CacheEntry
            if let found = try? stack.context.fetch(req).first { entry = found }
            else {
                entry = CacheEntry(entity: stack.model.entitiesByName["CacheEntry"]!, insertInto: stack.context)
                entry.key = key
            }
            entry.key = key
            entry.updatedAt = Date()
            entry.value = (try? JSONEncoder().encode(name)) ?? Data()
            try? stack.context.save()
        }
    }

    func loadBundleName(bundleId: String, ttl: TimeInterval) -> (name: String, isExpired: Bool)? {
        let rawKey = bundleNameKey(bundleId: bundleId)
        let key = prefixedKey(rawKey)
        var result: (name: String, isExpired: Bool)? = nil
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            if let entry = try? stack.context.fetch(req).first {
                let age = Date().timeIntervalSince(entry.updatedAt)
                if let name = try? JSONDecoder().decode(String.self, from: entry.value) {
                    result = (name, age > ttl)
                }
            }
        }
        return result
    }

    func bundleNameKey(bundleId: String) -> String {
        let v = "v1"
        return "bundle:name:\(v):\(bundleId)"
    }

    func saveBundleNetworks(_ list: [String], bundleCode: String) {
        let rawKey = bundleNetworksKey(bundleCode: bundleCode)
        let key = prefixedKey(rawKey)
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            let entry: CacheEntry
            if let found = try? stack.context.fetch(req).first { entry = found }
            else {
                entry = CacheEntry(entity: stack.model.entitiesByName["CacheEntry"]!, insertInto: stack.context)
                entry.key = key
            }
            entry.key = key
            entry.updatedAt = Date()
            entry.value = (try? JSONEncoder().encode(list)) ?? Data()
            try? stack.context.save()
        }
    }

    func bundleNetworksKey(bundleCode: String) -> String {
        let v = "v1"
        return "bundle:networks:\(v):\(bundleCode)"
    }

    func loadBundleDetail(id: String, ttl: TimeInterval) -> (item: ESIMBundle, isExpired: Bool)? {
        let rawKey = bundleDetailKey(id: id)
        let key = prefixedKey(rawKey)
        var result: (item: ESIMBundle, isExpired: Bool)? = nil
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            if let entry = try? stack.context.fetch(req).first {
                let age = Date().timeIntervalSince(entry.updatedAt)
                if let item = try? JSONDecoder().decode(ESIMBundle.self, from: entry.value) {
                    result = (item, age > ttl)
                }
            }
        }
        return result
    }

    func saveBundleDetail(_ item: ESIMBundle, id: String) {
        let rawKey = bundleDetailKey(id: id)
        let key = prefixedKey(rawKey)
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            let entry: CacheEntry
            if let found = try? stack.context.fetch(req).first { entry = found }
            else {
                entry = CacheEntry(entity: stack.model.entitiesByName["CacheEntry"]!, insertInto: stack.context)
                entry.key = key
            }
            entry.key = key
            entry.updatedAt = Date()
            entry.value = (try? JSONEncoder().encode(item)) ?? Data()
            try? stack.context.save()
        }
    }

    func bundleDetailKey(id: String) -> String {
        let v = "v1"
        return "bundle:detail:\(v):\(id)"
    }

    // MARK: - 设置项缓存（语言/货币）
    func loadLanguages(ttl: TimeInterval) -> (list: [SettingsManager.LanguageItem], isExpired: Bool)? {
        let rawKey = languagesKey()
        let key = prefixedKey(rawKey)
        var result: (list: [SettingsManager.LanguageItem], isExpired: Bool)? = nil
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            if let entry = try? stack.context.fetch(req).first {
                let age = Date().timeIntervalSince(entry.updatedAt)
                if let list = try? JSONDecoder().decode([SettingsManager.LanguageItem].self, from: entry.value) {
                    result = (list, age > ttl)
                }
            }
        }
        return result
    }

    func saveLanguages(_ list: [SettingsManager.LanguageItem]) {
        let rawKey = languagesKey()
        let key = prefixedKey(rawKey)
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            let entry: CacheEntry
            if let found = try? stack.context.fetch(req).first { entry = found }
            else {
                entry = CacheEntry(entity: stack.model.entitiesByName["CacheEntry"]!, insertInto: stack.context)
                entry.key = key
            }
            entry.key = key
            entry.updatedAt = Date()
            entry.value = (try? JSONEncoder().encode(list)) ?? Data()
            try? stack.context.save()
        }
    }

    func languagesKey() -> String {
        let v = "v1"
        return "settings:languages:\(v)"
    }

    func loadCurrencies(ttl: TimeInterval) -> (list: [SettingsManager.CurrencyItem], isExpired: Bool)? {
        let rawKey = currenciesKey()
        let key = prefixedKey(rawKey)
        var result: (list: [SettingsManager.CurrencyItem], isExpired: Bool)? = nil
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            if let entry = try? stack.context.fetch(req).first {
                let age = Date().timeIntervalSince(entry.updatedAt)
                if let list = try? JSONDecoder().decode([SettingsManager.CurrencyItem].self, from: entry.value) {
                    result = (list, age > ttl)
                }
            }
        }
        return result
    }

    func saveCurrencies(_ list: [SettingsManager.CurrencyItem]) {
        let rawKey = currenciesKey()
        let key = prefixedKey(rawKey)
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            let entry: CacheEntry
            if let found = try? stack.context.fetch(req).first { entry = found }
            else {
                entry = CacheEntry(entity: stack.model.entitiesByName["CacheEntry"]!, insertInto: stack.context)
                entry.key = key
            }
            entry.key = key
            entry.updatedAt = Date()
            entry.value = (try? JSONEncoder().encode(list)) ?? Data()
            try? stack.context.save()
        }
    }

    func currenciesKey() -> String {
        let v = "v2"
        return "settings:currencies:\(v)"
    }

    func loadSearchSuggestions(q: String, include: [String]?, limit: Int, ttl: TimeInterval) -> (list: [SearchResult], isExpired: Bool)? {
        let rawKey = searchSuggestionsKey(q: q, include: include, limit: limit)
        let key = prefixedKey(rawKey)
        var result: (list: [SearchResult], isExpired: Bool)? = nil
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            if let entry = try? stack.context.fetch(req).first {
                let age = Date().timeIntervalSince(entry.updatedAt)
                if let list = try? JSONDecoder().decode([SearchResult].self, from: entry.value) {
                    result = (list, age > ttl)
                }
            }
        }
        return result
    }

    func saveSearchSuggestions(_ list: [SearchResult], q: String, include: [String]?, limit: Int) {
        let rawKey = searchSuggestionsKey(q: q, include: include, limit: limit)
        let key = prefixedKey(rawKey)
        stack.context.performAndWait {
            let req = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
            req.predicate = NSPredicate(format: "key == %@ OR key == %@", key, rawKey)
            req.fetchLimit = 1
            let entry: CacheEntry
            if let found = try? stack.context.fetch(req).first { entry = found }
            else {
                entry = CacheEntry(entity: stack.model.entitiesByName["CacheEntry"]!, insertInto: stack.context)
                entry.key = key
            }
            entry.key = key
            entry.updatedAt = Date()
            entry.value = (try? JSONEncoder().encode(list)) ?? Data()
            try? stack.context.save()
        }
    }

    func searchSuggestionsKey(q: String, include: [String]?, limit: Int) -> String {
        let v = "v1"
        let l = languageTag()
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        let inc = (include?.sorted() ?? []).joined(separator: ",")
        return "search:suggestions:\(v):l\(l):q=\(t):inc=\(inc.isEmpty ? "-" : inc):limit=\(limit)"
    }
}
