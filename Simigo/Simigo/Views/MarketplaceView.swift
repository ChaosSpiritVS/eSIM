import SwiftUI
import UIKit

// 读取搜索框的布局信息，用于将覆盖层精确定位到“搜索框底部”
private struct SearchBarBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() { value = next }
    }
}

struct MarketplaceView: View {
    @StateObject private var viewModel: MarketplaceViewModel
    @StateObject private var searchVM = SearchViewModel()
    @State private var showErrorBanner: Bool = false
    @State private var showSupport: Bool = false
    @State private var query: String = ""
    @FocusState private var searchFocused: Bool
    @State private var sortOption: SortOption = .priceAsc
    @State private var categoryTab: CategoryTab = .all
    @State private var selectedBundleForDetail: ESIMBundle? = nil
    @State private var navigateToBundleDetail: Bool = false
    // 新增：搜索结果页导航
    @State private var selectedSearchContext: SearchContext? = nil
    @State private var navigateToSearchResults: Bool = false
    // 搜索框底部的 Y 坐标（在命名坐标空间内），用于定位覆盖层起始位置
    @State private var searchBarBottomY: CGFloat = 0
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var bannerCenter: BannerCenter
    @AppStorage("market_query") private var storedQuery: String = ""
    @AppStorage("market_sort_option") private var storedSort: Int = 1
    // 是否需要隐藏 TabBar（用于子页面场景）
    private let hideTabBar: Bool
    private var shouldHideTabBar: Bool { hideTabBar || searchFocused }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var recentBundleHistory: [SearchResult] {
        searchVM.history
    }
    private var allSuggestionResults: [SearchResult] { searchVM.suggestions }

    // 已移除本地过滤与排序，改为完全依赖服务端 sort_by

    // 便捷初始化移动到结构体内部，避免扩展落入局部作用域
    init() {
        self.hideTabBar = false
        _viewModel = StateObject(wrappedValue: MarketplaceViewModel())
    }
    init(countryCode: String? = nil) {
        self.hideTabBar = true
        _viewModel = StateObject(wrappedValue: MarketplaceViewModel(countryCode: countryCode))
    }
    init(regionCode: String? = nil) {
        self.hideTabBar = true
        _viewModel = StateObject(wrappedValue: MarketplaceViewModel(regionCode: regionCode))
    }

    @ViewBuilder private var content: some View {
        ZStack {
            if searchFocused {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { endEditingAndClear() }
                    .zIndex(9)
            }
            // 将分类选项卡与列表内容统一放入 List，使其在列表中一起滑动
            List {
                Section {
                    Picker(loc("分类"), selection: $categoryTab) {
                        Text(loc("全部")).tag(CategoryTab.all)
                        Text(loc("本地")).tag(CategoryTab.country)
                        Text(loc("区域")).tag(CategoryTab.region)
                        Text(loc("全球")).tag(CategoryTab.global)
                    }
                    .pickerStyle(.segmented)
                }
                if viewModel.isLoading {
                    Section(header: Text(loc("可用套餐"))) {
                        ForEach(0..<6, id: \.self) { _ in BundleCardSkeleton() }
                    }
                } else {
                    Section(header: Text(loc("可用套餐"))) {
                        if viewModel.error == nil || viewModel.error?.isEmpty == true {
                            if viewModel.bundles.isEmpty {
                                Text(loc("未找到匹配的套餐"))
                                    .foregroundColor(.secondary)
                            }
                        }
                        if !viewModel.bundles.isEmpty {
                            Text(String(format: loc("共 %d 个套餐"), viewModel.bundles.count))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        ForEach(viewModel.bundles) { bundle in
                            Button {
                                Telemetry.shared.logEvent("market_bundle_open", parameters: ["bundle_id": bundle.id])
                                navBridge.push(BundleDetailView(bundle: bundle), auth: auth, settings: settings, network: networkMonitor, title: bundle.name)
                            } label: {
                                BundleCardView(bundle: bundle)
                            }
                            .buttonStyle(.plain)
                        }
                        if viewModel.bundles.count == 10 {
                            HStack {
                                Spacer()
                                Button {
                                    Telemetry.shared.logEvent("market_view_more", parameters: ["query": trimmedQuery, "category": viewModel.currentBundleCategory ?? apiCategory(for: categoryTab) ?? "-"])
                                    let ctx = SearchContext(
                                        query: trimmedQuery,
                                        countryCode: viewModel.currentCountryCode,
                                        regionCode: viewModel.currentRegionCode,
                                        bundleCategory: viewModel.currentBundleCategory ?? apiCategory(for: categoryTab),
                                        title: tabTitle(for: categoryTab)
                                    )
                                    navBridge.push(SearchResultsView(context: ctx), auth: auth, settings: settings, network: networkMonitor, title: ctx.title ?? loc("搜索"))
                                } label: {
                                    Text(loc("查看更多"))
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 8)
                                }
                                .background(Color(UIColor.systemGray5))
                                .clipShape(Capsule())
                                Spacer()
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        // 置顶悬浮的搜索框：像通讯录的 section header 一样固定在顶部
        .safeAreaInset(edge: .top) {
            HStack(spacing: 8) {
                if searchVM.isLoading { ProgressView().frame(width: 16, height: 16) }
                else { Image(systemName: "magnifyingglass") }
                TextField(loc("您需要哪里的 eSIM?"), text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if searchFocused || !query.isEmpty {
                    Button {
                        endEditingAndClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .accessibilityLabel(loc("退出编辑"))
                }
                Spacer()
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(searchFocused ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.35), lineWidth: searchFocused ? 2 : 1.25)
            )
            .padding(.horizontal)
            // 读取搜索框在根视图坐标空间内的 frame，供覆盖层计算偏移
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SearchBarBoundsPreferenceKey.self,
                        value: proxy.frame(in: .named("MarketplaceRoot"))
                    )
                }
            )
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: shouldHideTabBar ? 0 : 96) }
        // 搜索建议与最近搜索作为覆盖层：顶部从搜索框底部开始，层级在选项卡和列表之上
        .overlay(alignment: .top) {
            // 仅当已成功获取搜索框底部坐标时再显示覆盖层，避免初始化阶段遮挡搜索框
            if searchBarBottomY > 0 {
                VStack(spacing: 8) {
                    if searchFocused && trimmedQuery.isEmpty {
                        if !recentBundleHistory.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(loc("最近搜索"))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                ScrollView {
                                    VStack(spacing: 0) {
                                        ForEach(recentBundleHistory) { r in
                                            Button { handleSuggestion(r) } label: {
                                                SuggestionRowView(result: r)
                                                    .padding(.horizontal)
                                                    .padding(.vertical, 6)
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .frame(maxHeight: 280)
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(radius: 4)
                                .padding(.horizontal)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    } else if searchFocused && !trimmedQuery.isEmpty {
                        if !allSuggestionResults.isEmpty {
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(allSuggestionResults) { r in
                                        Button { handleSuggestion(r) } label: {
                                            SuggestionRowView(result: r)
                                                .padding(.horizontal)
                                                .padding(.vertical, 6)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxHeight: 320)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 4)
                            .padding(.horizontal)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            VStack(spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass.circle")
                                        .foregroundColor(.secondary)
                                    Text(loc("未找到相关内容"))
                                        .font(.subheadline)
                                }
                                Text(loc("试试更短的关键词，或切换分类"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 4)
                            .padding(.horizontal)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.top, 6) // 与搜索框留出 6pt 间距
                .offset(y: searchBarBottomY) // 将覆盖层起点精确移动到搜索框底部
                .zIndex(10)
            }
        }
        // 注册坐标空间并监听偏好键变化，以计算覆盖层的起始偏移量
        .coordinateSpace(name: "MarketplaceRoot")
        .onPreferenceChange(SearchBarBoundsPreferenceKey.self) { rect in
            searchBarBottomY = rect?.maxY ?? 0
        }
    }

    var body: some View {
        content
            .toolbar(shouldHideTabBar ? .hidden : .automatic, for: .tabBar)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    Telemetry.shared.logEvent("support_open_from_market_button", parameters: nil)
                    showSupport = true
                } label: {
                    ZStack {
                        Circle().fill(Color.accentColor).frame(width: 56, height: 56)
                        Image(systemName: "message").foregroundColor(.white)
                    }
                }
                .accessibilityIdentifier("support.fab")
                .padding(16)
            }
            .sheet(isPresented: $showSupport) {
                UIKitNavHost(root: SupportView())
                    
            }
            .task { await searchVM.refreshHistoryIfPossible() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { togglePriceSort() } label: {
                            Text({
                                switch sortOption {
                                case .priceAsc: return loc("价格（↑）")
                                case .priceDesc: return loc("价格（↓）")
                                default: return loc("价格")
                                }
                            }())
                        }
                        Button { toggleDataSort() } label: {
                            Text({
                                switch sortOption {
                                case .dataAsc: return loc("流量（↑）")
                                case .dataDesc: return loc("流量（↓）")
                                default: return loc("流量")
                                }
                            }())
                        }
                        Button { sortOption = .name } label: {
                            HStack {
                                Text(loc("名称"))
                                if sortOption == .name { Image(systemName: "checkmark").foregroundColor(.accentColor) }
                            }
                        }
                    } label: { Label(loc("排序"), systemImage: "arrow.up.arrow.down") }
                }
            }
            
            .onChange(of: viewModel.error) { _, newValue in
            if let msg = newValue, !msg.isEmpty {
                bannerCenter.enqueue(
                    message: msg,
                    style: .error,
                    source: "marketplace",
                    actionTitle: loc("重试"),
                    onAction: { viewModel.reload(bundleCategory: apiCategory(for: categoryTab), sortBy: apiSort(for: sortOption)) },
                    onClose: { withAnimation(.easeInOut(duration: 0.25)) { viewModel.error = nil } }
                )
            }
            }
        .onDisappear { endEditingAndClear() }
        .onAppear {
            query = storedQuery
            sortOption = sortFromRaw(storedSort)
            DispatchQueue.main.async {
                viewModel.reload(bundleCategory: apiCategory(for: categoryTab), sortBy: apiSort(for: sortOption))
                if !viewModel.bundles.isEmpty { viewModel.revalidatePreservingShortList() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Telemetry.shared.logEvent("app_tab_change", parameters: ["tab": "market"])
                Telemetry.shared.logEvent("market_open", parameters: [
                    "category": String(describing: categoryTab),
                    "sort": String(describing: sortOption),
                    "has_query": !query.isEmpty
                ])
            }
        }
        .onChange(of: query) { _, newValue in
            storedQuery = newValue
            let iface = networkMonitor.interfaceType
            let limited = networkMonitor.isConstrained || networkMonitor.isExpensive
            let limit: Int = {
                if iface == "wifi" && !limited { return 100 }
                if limited { return 50 }
                if iface == "cellular" { return 50 }
                return 50
            }()
            searchVM.debounceSearch(query: newValue, include: ["country","region","bundle"], limit: limit)
            Telemetry.shared.logEvent("search_input", parameters: ["q": newValue, "limit": limit])
        }
        .onChange(of: sortOption) { _, newValue in
            storedSort = sortRaw(newValue)
            viewModel.reload(sortBy: apiSort(for: newValue))
            Telemetry.shared.logEvent("market_sort_change", parameters: ["sort": String(describing: newValue)])
        }
        .onChange(of: categoryTab) { _, newValue in viewModel.switchCategoryAndReload(to: apiCategory(for: newValue)) }
        .onChange(of: categoryTab) { _, newValue in Telemetry.shared.logEvent("market_category_change", parameters: ["category": String(describing: newValue)]) }
        .onChange(of: networkMonitor.isOnline) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.25)) { showErrorBanner = false; viewModel.error = nil }
                if !viewModel.isLoading { viewModel.reload(bundleCategory: apiCategory(for: categoryTab), sortBy: apiSort(for: sortOption)) }
            }
        }
        .onChange(of: networkMonitor.backendOnline) { _, newValue in
            if newValue {
                if !viewModel.isLoading { viewModel.reload(bundleCategory: apiCategory(for: categoryTab), sortBy: apiSort(for: sortOption)) }
                }
            }
        .onChange(of: auth.currentUser) { _, _ in
            Task { await searchVM.refreshHistoryIfPossible() }
        }
        .onChange(of: settings.languageCode) { _, _ in
            viewModel.reload(bundleCategory: apiCategory(for: categoryTab), sortBy: apiSort(for: sortOption))
            Task { await searchVM.refreshHistoryIfPossible() }
            searchVM.cancel()
            if !trimmedQuery.isEmpty {
                let iface = networkMonitor.interfaceType
                let limited = networkMonitor.isConstrained || networkMonitor.isExpensive
                let limit: Int = {
                    if iface == "wifi" && !limited { return 100 }
                    if limited { return 50 }
                    if iface == "cellular" { return 50 }
                    return 50
                }()
                searchVM.debounceSearch(query: query, include: ["country","region","bundle"], limit: limit)
            }
        }
    }

    private func handleSuggestion(_ r: SearchResult) {
        searchVM.recordSelection(r)
        Telemetry.shared.logEvent("search_suggestion_select", parameters: [
            "kind": r.kind.rawValue,
            "id": r.id,
            "title": r.title
        ])
        switch r.kind {
        case .country:
            if let code = r.countryCode {
                endEditingAndClear()
                let ctx = SearchContext(query: r.title, countryCode: code, regionCode: nil, bundleCategory: nil, title: loc("本地"))
                navBridge.performAfterKeyboardHidden {
                    navBridge.push(SearchResultsView(context: ctx), auth: auth, settings: settings, network: networkMonitor, title: ctx.title ?? loc("搜索结果"))
                }
            }
        case .region:
            if let code = r.regionCode {
                endEditingAndClear()
                let ctx = SearchContext(query: r.title, countryCode: nil, regionCode: code, bundleCategory: nil, title: loc("区域"))
                navBridge.performAfterKeyboardHidden {
                    navBridge.push(SearchResultsView(context: ctx), auth: auth, settings: settings, network: networkMonitor, title: ctx.title ?? loc("搜索结果"))
                }
            }
        case .bundle:
            // SearchResult.id 映射到 ESIMBundle.id；用 id 进行详情跳转
            endEditingAndClear()
            let id = r.id
            navBridge.performAfterKeyboardHidden {
                openBundleDetail(bundleId: id)
            }
        }
    }

    private func openBundleDetail(bundleId: String) {
        Task {
            if let local = viewModel.bundles.first(where: { $0.id == bundleId }) {
                Telemetry.shared.logEvent("market_bundle_open", parameters: ["bundle_id": bundleId, "source": "local"])
                navBridge.push(BundleDetailView(bundle: local), auth: auth, settings: settings, network: networkMonitor, title: local.name)
                endEditingAndClear()
                return
            }
            let cache = CatalogCacheStore.shared
            if let cached = cache.loadBundleDetail(id: bundleId, ttl: AppConfig.catalogCacheTTL), !cached.isExpired {
                Telemetry.shared.logEvent("market_bundle_open", parameters: ["bundle_id": bundleId, "source": "cache"])
                navBridge.push(BundleDetailView(bundle: cached.item), auth: auth, settings: settings, network: networkMonitor, title: cached.item.name)
                endEditingAndClear()
                return
            }
            let repo: CatalogRepositoryProtocol = AppConfig.isMock ? MockCatalogRepository() : HTTPCatalogRepository()
            do {
                let b = try await repo.fetchBundle(id: bundleId)
                cache.saveBundleDetail(b, id: bundleId)
                Telemetry.shared.logEvent("market_bundle_open", parameters: ["bundle_id": bundleId, "source": "network"])
                navBridge.push(BundleDetailView(bundle: b), auth: auth, settings: settings, network: networkMonitor, title: b.name)
                endEditingAndClear()
            } catch {
                viewModel.error = loc("未能加载套餐详情")
                withAnimation(.easeInOut(duration: 0.25)) { showErrorBanner = true }
            }
        }
    }
    // 统一退出编辑为点击 X 的效果：退出编辑、取消搜索并清空输入
    private func endEditingAndClear() {
        searchFocused = false
        searchVM.cancel()
        query = ""
        navBridge.endEditing()
    }

    // 切换价格排序：在升序/降序之间切换，若当前为其他维度则切到升序
    private func togglePriceSort() {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch sortOption {
            case .priceAsc:
                sortOption = .priceDesc
            case .priceDesc:
                sortOption = .priceAsc
            default:
                sortOption = .priceAsc
            }
        }
    }

    // 切换流量排序：在升序/降序之间切换，若当前为其他维度则切到升序
    private func toggleDataSort() {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch sortOption {
            case .dataAsc:
                sortOption = .dataDesc
            case .dataDesc:
                sortOption = .dataAsc
            default:
                sortOption = .dataAsc
            }
        }
    }
}

// 上述 init 已在结构体内部定义

private enum SortOption: Hashable {
    case priceDesc
    case priceAsc
    case dataDesc
    case dataAsc
    case name
}

private enum CategoryTab: Hashable { case all, country, region, global }

private func sortRaw(_ s: SortOption) -> Int {
    switch s {
    case .priceDesc: return 0
    case .priceAsc: return 1
    case .dataDesc: return 2
    case .dataAsc: return 3
    case .name: return 4
    }
}

private func sortFromRaw(_ r: Int) -> SortOption {
    switch r {
    case 0: return .priceDesc
    case 1: return .priceAsc
    case 2: return .dataDesc
    case 3: return .dataAsc
    case 4: return .name
    default: return .priceDesc
    }
}

// 将本地排序枚举映射到服务端 API 的 sort_by 值
private func apiSort(for opt: SortOption) -> String? {
    switch opt {
    case .priceDesc: return "price_dsc"
    case .priceAsc: return "price_asc"
    case .dataDesc: return "data_dsc"
    case .dataAsc: return "data_asc"
    case .name: return "bundle_name"
    }
}

// 将分类选项映射到 bundle_category
private func apiCategory(for tab: CategoryTab) -> String? {
    switch tab {
    case .all: return nil
    case .country: return "country"
    case .region: return "region"
    case .global: return "global"
    }
}

private func tabTitle(for tab: CategoryTab) -> String {
    switch tab {
    case .all: return loc("全部")
    case .country: return loc("本地")
    case .region: return loc("区域")
    case .global: return loc("全球")
    }
}

// 已删除 dataValue/价格/数据/有效期区间枚举与持久化，避免本地过滤与排序

private func decimalToDouble(_ d: Decimal) -> Double {
    NSDecimalNumber(decimal: d).doubleValue
}


struct BundleCardView: View {
    let bundle: ESIMBundle
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if bundle.countryCode.isEmpty {
                    Image(systemName: "globe")
                        .foregroundColor(.green)
                        .font(.largeTitle)
                } else {
                    Text(countryFlag(bundle.countryCode))
                        .font(.largeTitle)
                }
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(bundle.description ?? bundle.name).font(.headline)
            }
            Spacer()
            Text(PriceFormatter.string(amount: bundle.price, currencyCode: bundle.currency))
                .font(.headline)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct TagView: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

private struct SuggestionRowView: View {
    let result: SearchResult
    var body: some View {
        HStack(spacing: 12) {
            switch result.kind {
            case .country:
                Text(countryFlag(result.countryCode ?? ""))
                    .font(.title2)
                    .frame(width: 32)
            case .region:
                Image(systemName: "globe")
                    .foregroundColor(.green)
                    .frame(width: 32)
            case .bundle:
                Image(systemName: "simcard")
                    .foregroundColor(.blue)
                    .frame(width: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                if let sub = result.subtitle, !sub.isEmpty {
                    Text(sub).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }
}

#Preview("商店") { MarketplaceView() }
