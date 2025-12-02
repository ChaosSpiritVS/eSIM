import SwiftUI

struct SearchContext: Hashable {
    var query: String
    var countryCode: String?
    var regionCode: String?
    var bundleCategory: String?
    var title: String?
}

struct SearchResultsView: View {
    @StateObject private var viewModel: SearchResultsViewModel
    @State private var input: String
    private let navTitle: String?
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var bannerCenter: BannerCenter
    @State private var showErrorBanner: Bool = false

    init(context: SearchContext) {
        _viewModel = StateObject(wrappedValue: SearchResultsViewModel(initialQuery: context.query, countryCode: context.countryCode, regionCode: context.regionCode, bundleCategory: context.bundleCategory))
        _input = State(initialValue: context.query)
        navTitle = context.title
    }

    var body: some View {
        VStack(spacing: 12) {
            // 已移除顶部搜索框：使用进入页面时的上下文查询一次性加载

            // 结果分组展示
            if viewModel.isLoading && viewModel.bundles.isEmpty && viewModel.countryHits.isEmpty && viewModel.regionHits.isEmpty {
                List {
                    Section(header: Text(loc("套餐"))) {
                        ForEach(0..<6, id: \.self) { _ in BundleCardSkeleton() }
                    }
                }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
            } else if viewModel.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 44)).foregroundColor(.secondary)
                    Text(loc("无结果")).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !input.isEmpty && !viewModel.countryHits.isEmpty {
                        Section(header: Text(loc("国家"))) {
                            ForEach(viewModel.countryHits) { c in
                                Button {
                                    Telemetry.shared.logEvent("search_scope_select", parameters: ["type": "country", "code": c.code])
                                    viewModel.applyScope(countryCode: c.code)
                                } label: {
                                    HStack { Text(countryFlag(c.code)).frame(width: 32); Text(c.name); Spacer() }
                                }
                            }
                        }
                    }

                    if !input.isEmpty && !viewModel.regionHits.isEmpty {
                        Section(header: Text(loc("地区"))) {
                            ForEach(viewModel.regionHits) { r in
                                Button {
                                    Telemetry.shared.logEvent("search_scope_select", parameters: ["type": "region", "code": r.code])
                                    viewModel.applyScope(regionCode: r.code)
                                } label: {
                                    HStack { Image(systemName: "globe").foregroundColor(.green).frame(width: 32); Text(r.name); Spacer() }
                                }
                            }
                        }
                    }

                    Section(header: Text(loc("套餐"))) {
                        if viewModel.bundles.isEmpty {
                            Text(loc("未发现匹配的套餐")).foregroundColor(.secondary)
                        }
                        ForEach(Array(viewModel.bundles.enumerated()), id: \.element.id) { idx, b in
                            Button {
                                navBridge.push(BundleDetailView(bundle: b), auth: auth, settings: settings, network: networkMonitor, title: b.name)
                            } label: {
                                BundleCardView(bundle: b)
                            }
                            .buttonStyle(.plain)
                        }
                        if viewModel.canLoadMore {
                            HStack {
                                Spacer()
                                Button {
                                    Telemetry.shared.logEvent("search_results_load_more_click", parameters: ["current_count": viewModel.bundles.count])
                                    viewModel.loadMoreBundles()
                                } label: {
                                    Text(viewModel.isLoadingMore ? loc("加载中...") : loc("加载更多"))
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 8)
                                }
                                .background(Color(UIColor.systemGray5))
                                .clipShape(Capsule())
                                .disabled(viewModel.isLoadingMore)
                                Spacer()
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        
        
        
        .onAppear {
            if viewModel.bundles.isEmpty && viewModel.countryHits.isEmpty && viewModel.regionHits.isEmpty {
                viewModel.performSearch(query: input, commit: false)
            } else {
                viewModel.revalidatePreservingPagination()
            }
        }
        .onChange(of: viewModel.error) { _, newValue in
            if let msg = newValue, !msg.isEmpty {
                bannerCenter.enqueue(message: msg, style: .error, source: "search_results", actionTitle: loc("重试"), onAction: { viewModel.performSearch(query: input, commit: false) }, onClose: { withAnimation(.easeInOut(duration: 0.25)) { viewModel.error = nil } })
            }
        }
        .onChange(of: networkMonitor.isOnline) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.25)) { showErrorBanner = false; viewModel.error = nil }
                viewModel.performSearch(query: input, commit: false)
            }
        }
        .onChange(of: networkMonitor.backendOnline) { _, newValue in
            if newValue {
                viewModel.revalidatePreservingPagination()
            }
        }
    }
}
