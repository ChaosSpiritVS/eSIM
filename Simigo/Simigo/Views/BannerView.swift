import SwiftUI

struct BannerView: View {
    let message: String
    var backgroundColor: Color = .red
    var foregroundColor: Color = .white
    var iconSystemName: String? = nil
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    var style: BannerStyle = .error
    var autoDismissAfter: Double? = nil
    var telemetrySource: String? = nil

    var body: some View {
        HStack {
            if let icon = iconSystemName {
                Image(systemName: icon).foregroundColor(foregroundColor)
            }
            Text(BannerCopy.normalized(style: style, message: message)).foregroundColor(foregroundColor)
            Spacer()
            if let actionTitle = actionTitle, let onAction = onAction {
                Button(action: {
                    Telemetry.shared.logEvent("banner_action_click", parameters: [
                        "type": style.name,
                        "source": telemetrySource ?? "-",
                        "action": actionTitle
                    ])
                    onAction()
                }) {
                    Text(actionTitle)
                        .font(.footnote)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(foregroundColor.opacity(0.15))
                        .foregroundColor(foregroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            if let onClose = onClose {
                Button(action: {
                    Telemetry.shared.logEvent("banner_close", parameters: [
                        "type": style.name,
                        "source": telemetrySource ?? "-"
                    ])
                    onClose()
                }) {
                    Image(systemName: "xmark").foregroundColor(foregroundColor)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(1)
        .onAppear {
            Telemetry.shared.logEvent("banner_show", parameters: [
                "type": style.name,
                "source": telemetrySource ?? "-"
            ])
            let resolved: Double? = {
                if let explicit = autoDismissAfter { return explicit > 0 ? explicit : nil }
                if actionTitle != nil { return nil }
                return style.defaultAutoDismiss
            }()
            if let delay = resolved, let onClose = onClose {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { onClose() }
            }
        }
    }
}

enum BannerStyle {
    case error
    case success
    case warning
    case info

    var background: Color {
        switch self {
        case .error: return .red
        case .success: return .green
        case .warning: return .orange
        case .info: return .blue
        }
    }

    var foreground: Color { .white }

    var defaultIcon: String? {
        switch self {
        case .error: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.circle"
        case .info: return "info.circle"
        }
    }

    var name: String {
        switch self {
        case .error: return "error"
        case .success: return "success"
        case .warning: return "warning"
        case .info: return "info"
        }
    }

    var defaultAutoDismiss: TimeInterval? {
        switch self {
        case .error: return AppConfig.bannerDefaultDismiss(for: .error)
        case .success: return AppConfig.bannerDefaultDismiss(for: .success)
        case .warning: return AppConfig.bannerDefaultDismiss(for: .warning)
        case .info: return AppConfig.bannerDefaultDismiss(for: .info)
        }
    }
}

extension BannerView {
    init(message: String, style: BannerStyle, actionTitle: String? = nil, onAction: (() -> Void)? = nil, onClose: (() -> Void)? = nil, autoDismissAfter: Double? = nil, telemetrySource: String? = nil) {
        self.message = message
        self.backgroundColor = style.background
        self.foregroundColor = style.foreground
        self.iconSystemName = style.defaultIcon
        self.actionTitle = actionTitle
        self.onAction = onAction
        self.onClose = onClose
        self.style = style
        self.autoDismissAfter = autoDismissAfter
        self.telemetrySource = telemetrySource
    }
}

struct BannerCopy {
    static func normalized(style: BannerStyle, message: String) -> String {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        switch style {
        case .error:
            if m.contains("失败") || m.contains("不可用") || m.contains("离线") || m.contains("支付") { return m }
            return String(format: loc("请求失败：%@，请重试"), m)
        case .success:
            if m.contains("成功") { return m }
            return String(format: loc("操作成功：%@"), m)
        case .warning:
            if m.contains("提示") || m.contains("警告") { return m }
            return String(format: loc("提示：%@"), m)
        case .info:
            return m.isEmpty ? "" : m
        }
    }
}

 

struct BannerItem: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let style: BannerStyle
    let actionTitle: String?
    let onAction: (() -> Void)?
    let onClose: (() -> Void)?
    let source: String
    let priority: BannerPriority
    let timestamp: TimeInterval
    static func == (lhs: BannerItem, rhs: BannerItem) -> Bool { lhs.message == rhs.message && lhs.style.name == rhs.style.name && lhs.source == rhs.source }
}

 

enum BannerPriority: Int {
    case low = 0
    case normal = 1
    case high = 2
}

final class BannerCenter: ObservableObject {
    @Published private(set) var items: [BannerItem] = []
    var current: BannerItem? {
        items.sorted { a, b in
            if a.priority != b.priority { return a.priority.rawValue > b.priority.rawValue }
            return a.timestamp < b.timestamp
        }.first
    }
    func enqueue(message: String, style: BannerStyle, source: String, priority: BannerPriority = .normal, actionTitle: String? = nil, onAction: (() -> Void)? = nil, onClose: (() -> Void)? = nil) {
        let item = BannerItem(message: message, style: style, actionTitle: actionTitle, onAction: onAction, onClose: onClose, source: source, priority: priority, timestamp: Date().timeIntervalSince1970)
        if !items.contains(item) { items.append(item) }
    }
    func dismissCurrent() {
        if let cur = current {
            items.removeAll { $0.id == cur.id }
            cur.onClose?()
        }
    }
    func clear(source: String? = nil) {
        if let s = source { items.removeAll { $0.source == s } } else { items.removeAll() }
    }
}

struct BannerCenterTopModifier: ViewModifier {
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @ObservedObject var center: BannerCenter
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let item = center.current, AppConfig.bannersEnabled {
                BannerView(message: item.message, style: item.style, actionTitle: item.actionTitle, onAction: item.onAction, onClose: { center.dismissCurrent() }, telemetrySource: item.source)
            }
        }
    }
}

extension View {
    func bannerCenterTopOverlay(center: BannerCenter) -> some View { modifier(BannerCenterTopModifier(center: center)) }
}

struct ErrorCopyMapper {
    static func paymentFailureDisplay(reason: String, underlying: Error?) -> String {
        let cat = PaymentEventBridge.reasonCategory(reason: reason, error: underlying)
        switch cat.category {
        case "network": return String(format: loc("支付失败：网络异常，请检查网络后重试（%@）"), reason)
        case "balance": return String(format: loc("支付失败：余额不足或发卡行拒绝（%@）"), reason)
        case "sdk": return String(format: loc("支付失败：支付组件异常，请重试或更新（%@）"), reason)
        case "server": return String(format: loc("支付失败：服务暂时不可用，请稍后重试（%@）"), reason)
        default: return String(format: loc("支付失败：%@"), reason)
        }
    }

    static func networkFailureDisplay(message: String) -> String {
        let m = message.lowercased()
        if m.contains("timeout") || m.contains("timed out") || m.contains("network") { return String(format: loc("网络异常：请检查网络后重试（%@）"), message) }
        if m.contains("connect") || m.contains("unreachable") || m.contains("server") { return String(format: loc("服务暂时不可用，请稍后重试（%@）"), message) }
        return String(format: loc("请求失败：%@，请重试"), message)
    }
}
