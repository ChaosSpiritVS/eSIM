import SwiftUI

struct SupportView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var navBridge: NavigationBridge
    var body: some View {
        List {
            Section(header: Text(loc("帮助与支持"))) {
                Text(loc("如需帮助，您可以通过以下方式联系我们："))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Link(loc("发送邮件至 support@example.com"), destination: URL(string: "mailto:support@example.com")!)
                    .simultaneousGesture(TapGesture().onEnded {
                        Telemetry.shared.logEventDeferred("support_email_open", parameters: [
                            "email": "support@example.com"
                        ])
                    })
                Button { navBridge.push(ESIMInstallationGuideView(showClose: true), auth: auth, settings: settings, network: networkMonitor, title: loc("安装指南")) } label: {
                    Label(loc("eSIM 安装指南"), systemImage: "qrcode.viewfinder")
                }
                
            }
            
        }
        .listStyle(.insetGrouped)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(loc("取消")) { Telemetry.shared.logEvent("support_close_click", parameters: nil); navBridge.dismiss() } } }
        .onAppear { Telemetry.shared.logEvent("support_open", parameters: nil) }
        
    }
}

struct ESIMInstallationGuideView: View {
    let showClose: Bool

    init(showClose: Bool = false) { self.showClose = showClose }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(loc("连接到网络")).font(.headline)
                Text(loc("按照以下步骤使用你的 eSIM，请记住，您的 eSIM 只能在连接到网络时获得支持。"))
                    .foregroundColor(.secondary)

                Text(loc("安装教程")).font(.headline)
                Text(loc("方式一：通过二维码安装")).bold()
                HStack { Image(systemName: "checkmark.circle"); Text(loc("打开 iPhone 设置 > 蜂窝网络 (Cellular)")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("点击 添加蜂窝套餐（Add eSIM / Add Cellular Plan）")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("使用相机扫描订单详情页的 eSIM 激活二维码")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("根据提示信息，添加蜂窝套餐（Add Cellular Plan）")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("返回设置主页，确认 eSIM 套餐状态为“已激活”")) }

                Text(loc("方式二：手动输入激活码安装")).bold()
                HStack { Image(systemName: "checkmark.circle"); Text(loc("打开 设置 > 蜂窝网络 > 添加蜂窝套餐")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("选择 手动输入详细信息（Enter Details Manually）")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("输入以下信息：")) }
                Text(loc("a. SM-DP+ 地址（由运营商提供）"))
                Text(loc("b. 激活码（Activation Code 或 Matching ID）"))
                Text(loc("c. 确认码（Confirmation Code）"))
                HStack { Image(systemName: "checkmark.circle"); Text(loc("点击下一步，等待系统添加套餐，安装完成后即可使用")) }

                Text(loc("激活使用")).font(.headline)
                HStack { Image(systemName: "checkmark.circle"); Text(loc("进入“设置”> 蜂窝网络，然后选择 eSIM")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("打开“启用此线路”")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("进入“设置”> 蜂窝网络 > 蜂窝数据网络，并选择使用该 eSIM")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("关闭并重新打开“蜂窝数据”")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("进入“设置”> 蜂窝网络，然后选择 eSIM")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("根据需要打开“数据漫游”")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("测试网络连接，首次连接可能需要等待一段时间")) }

                Divider().padding(.vertical, 8)

                Text(loc("连接到网络")).font(.headline)
                Text(loc("按照以下步骤使用你的 eSIM，请记住，您的 eSIM 只能在连接到网络时获得支持。"))
                    .foregroundColor(.secondary)

                Text(loc("安装教程")).font(.headline)
                Text(loc("方式一：通过二维码安装")).bold()
                HStack { Image(systemName: "checkmark.circle"); Text(loc("打开 设置 > 网络和互联网 > SIM 卡 或 移动网络")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("选择 添加 eSIM / 添加移动网络")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("选择 使用二维码")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("扫描订单详情页的 eSIM 激活二维码")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("点击 安装/添加，完成安装")) }

                Text(loc("方式二：手动输入激活码安装")).bold()
                HStack { Image(systemName: "checkmark.circle"); Text(loc("进入 设置 > 网络和互联网 > SIM 卡 > 添加 eSIM")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("进入 输入激活码/匹配码")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("手动输入：")) }
                Text(loc("a. SM-DP+ 地址"))
                Text(loc("b. 激活码 / 匹配 ID"))
                Text(loc("c. 确认码（如有）"))
                HStack { Image(systemName: "checkmark.circle"); Text(loc("点击 连接/下载/应用，完成安装")) }

                Text(loc("激活使用")).font(.headline)
                HStack { Image(systemName: "checkmark.circle"); Text(loc("在 设置 > 网络和互联网 > SIM 卡中，打开 eSIM 开关")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("将该 eSIM 设为默认数据线路，必要时启用数据漫游")) }
                HStack { Image(systemName: "checkmark.circle"); Text(loc("测试数据开关或切换飞行模式，如无信号可手动选择网络")) }
            }
            .padding()
        }
        
        
        .onAppear { Telemetry.shared.logEvent("esim_guide_open", parameters: nil) }
    }
}

#Preview("客服与支持") { NavigationStack { SupportView() } }
