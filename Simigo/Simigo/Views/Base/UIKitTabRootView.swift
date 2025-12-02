import SwiftUI
import UIKit

final class NavigationBridge: ObservableObject {
    weak var currentNav: UINavigationController?
    weak var bannerCenterRef: BannerCenter?
    var keyboardVisible: Bool = false
    fileprivate var afterKeyboardHiddenQueue: [() -> Void] = []
    func endEditing() { currentNav?.view.endEditing(true) }
    func push<V: View>(_ view: V, auth: AuthManager, settings: SettingsManager, network: NetworkMonitor, title: String? = nil, animated: Bool = true) {
        let hosted = UIHostingController(rootView: view
            .environmentObject(auth)
            .environmentObject(settings)
            .environmentObject(network)
            .environmentObject(self)
            .environmentObject(bannerCenterRef ?? BannerCenter())
            .environment(\.locale, settings.locale)
        )
        hosted.hidesBottomBarWhenPushed = true
        hosted.title = title
        if let prev = currentNav?.topViewController {
            prev.navigationItem.backButtonTitle = loc("返回")
        }
        currentNav?.pushViewController(hosted, animated: animated)
    }
    func performAfterKeyboardHidden(_ action: @escaping () -> Void) {
        if keyboardVisible {
            afterKeyboardHiddenQueue.append(action)
        } else {
            action()
        }
    }
    func pop(animated: Bool = true) { currentNav?.popViewController(animated: animated) }
    func dismiss(animated: Bool = true) { currentNav?.dismiss(animated: animated) }
    func popToRoot(animated: Bool = true) { currentNav?.popToRootViewController(animated: animated) }
}

struct UIKitTabRootView: UIViewControllerRepresentable {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var bannerCenter: BannerCenter

    func makeUIViewController(context: Context) -> UITabBarController {
        let tab = UITabBarController()

        func makeNav<V: View>(_ root: V, title: String, image: String, id: String) -> UINavigationController {
            let hosted = UIHostingController(rootView: root
                .environmentObject(auth)
                .environmentObject(settings)
                .environmentObject(networkMonitor)
                .environmentObject(navBridge)
                .environmentObject(bannerCenter)
                .environment(\.locale, settings.locale)
            )
            hosted.title = title
            let nav = UINavigationController(rootViewController: hosted)
            nav.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: image), selectedImage: nil)
            nav.tabBarItem.accessibilityIdentifier = id
            nav.isNavigationBarHidden = false
            nav.delegate = context.coordinator
            return nav
        }

        let marketNav = makeNav(MarketplaceView(), title: loc("商店"), image: "cart", id: "tab.market")
        let esimsNav = makeNav(MyEsimView(), title: loc("我的 eSIM"), image: "simcard", id: "tab.my_esim")
        let accountNav = makeNav(AccountView(), title: loc("个人资料"), image: "person.circle", id: "tab.account")

        tab.viewControllers = [marketNav, esimsNav, accountNav]
        tab.selectedIndex = 0
        navBridge.currentNav = marketNav
        navBridge.bannerCenterRef = bannerCenter
        tab.delegate = context.coordinator
        context.coordinator.tabRef = tab
        context.coordinator.startKeyboardObservers()
        return tab
    }

    func updateUIViewController(_ tab: UITabBarController, context: Context) {
        let titles = [loc("商店"), loc("我的 eSIM"), loc("个人资料")]
        guard let navs = tab.viewControllers as? [UINavigationController] else { return }
        for (idx, nav) in navs.enumerated() {
            if idx < titles.count {
                let t = titles[idx]
                nav.tabBarItem.title = t
                if nav.viewControllers.count <= 1 {
                    nav.viewControllers.first?.title = t
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(navBridge: navBridge) }

    final class Coordinator: NSObject, UITabBarControllerDelegate, UINavigationControllerDelegate {
        let navBridge: NavigationBridge
        weak var tabRef: UITabBarController?
        private var showObserver: NSObjectProtocol?
        private var hideObserver: NSObjectProtocol?
        init(navBridge: NavigationBridge) { self.navBridge = navBridge }
        func startKeyboardObservers() {
            showObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
                self?.navBridge.keyboardVisible = true
                self?.tabRef?.tabBar.isHidden = true
            }
            hideObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                let count = self.navBridge.currentNav?.viewControllers.count ?? 1
                self.navBridge.keyboardVisible = false
                let q = self.navBridge.afterKeyboardHiddenQueue
                self.navBridge.afterKeyboardHiddenQueue.removeAll()
                q.forEach { $0() }
                self.tabRef?.tabBar.isHidden = count > 1
            }
        }
        func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
            let count = navigationController.viewControllers.count
            tabRef?.tabBar.isHidden = count > 1
        }
        deinit {
            if let ob = showObserver { NotificationCenter.default.removeObserver(ob) }
            if let ob = hideObserver { NotificationCenter.default.removeObserver(ob) }
        }
        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            if let nav = viewController as? UINavigationController { navBridge.currentNav = nav }
        }
    }
}

struct UIKitNavHost<V: View>: UIViewControllerRepresentable {
    let root: V
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var bannerCenter: BannerCenter

    func makeUIViewController(context: Context) -> UINavigationController {
        let localBridge = NavigationBridge()
        let hosted = UIHostingController(rootView: root
            .environmentObject(auth)
            .environmentObject(settings)
            .environmentObject(networkMonitor)
            .environmentObject(localBridge)
            .environmentObject(bannerCenter)
            .bannerCenterTopOverlay(center: bannerCenter)
            .environment(\.locale, settings.locale)
        )
        let nav = UINavigationController(rootViewController: hosted)
        nav.isNavigationBarHidden = false
        localBridge.currentNav = nav
        localBridge.bannerCenterRef = bannerCenter
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
