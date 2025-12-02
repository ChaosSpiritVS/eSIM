import Foundation

#if DEBUG
public enum SyncStringsOrderTool {
public static func run() {
let baseDir = FileManager.default.currentDirectoryPath
let projDir = URL(fileURLWithPath: baseDir).appendingPathComponent("Simigo/Simigo")
let langs = ["ar","en","es","id","ja","ko","ms","pt","th","vi","zh-Hans","zh-Hant"]
let files = langs.map { projDir.appendingPathComponent("\($0).lproj/Localizable.strings").path }

struct Entry { let key: String; let value: String }
struct Cat { let name: String; let regexes: [NSRegularExpression] }

func R(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }

func parse(_ text: String) -> [String: String] {
    var dict: [String: String] = [:]
    for lineSub in text.split(separator: "\n") {
        let line = String(lineSub)
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("/*") { continue }
        guard let kRange1 = line.range(of: "\"") else { continue }
        guard let kRange2 = line.range(of: "\"", range: kRange1.upperBound..<line.endIndex) else { continue }
        let key = String(line[kRange1.upperBound..<kRange2.lowerBound])
        guard let vRange1 = line.range(of: "\"", range: kRange2.upperBound..<line.endIndex) else { continue }
        guard let vRange2 = line.range(of: "\"", range: vRange1.upperBound..<line.endIndex) else { continue }
        let value = String(line[vRange1.upperBound..<vRange2.lowerBound])
        if !key.isEmpty { if dict[key] == nil { dict[key] = value } }
    }
    return dict
}

func readFile(_ path: String) -> String {
    (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
}

func writeFile(_ path: String, _ content: String) {
    try? content.write(toFile: path, atomically: true, encoding: .utf8)
}

let enPath = projDir.appendingPathComponent("en.lproj/Localizable.strings").path
let zhHansPath = projDir.appendingPathComponent("zh-Hans.lproj/Localizable.strings").path
let enText = readFile(enPath)
let zhHansText = readFile(zhHansPath)
let enMap = parse(enText)
let zhHansMap = parse(zhHansText)

// Canonical order: English keys in current order, then any extras from other languages (stable by appearance order)
// Canonical order strictly from zh-Hans keys and their current order
var order: [String] = []
var seen = Set<String>()
for line in zhHansText.split(separator: "\n") {
    let s = String(line)
    if s.trimmingCharacters(in: .whitespaces).hasPrefix("/*") { continue }
    guard let k1 = s.range(of: "\"") else { continue }
    guard let k2 = s.range(of: "\"", range: k1.upperBound..<s.endIndex) else { continue }
    let key = String(s[k1.upperBound..<k2.lowerBound])
    if seen.insert(key).inserted { order.append(key) }
}

// Collect union
// Do NOT add extras from other languages; keys must be exactly zh-Hans set
let unionKeys = Set(order)

// Define functional groups (Chinese headings), match by keyword regex
let cats: [Cat] = [
    Cat(name: "导航", regexes: [R("^(商店|我的 eSIM|个人资料|订单|客服与支持|热门)$")]),
    Cat(name: "市集与搜索", regexes: [R("查看套餐"), R("搜索"), R("排序"), R("价格"), R("流量"), R("分类"), R("可用套餐"), R("未找到匹配的套餐"), R("查看更多"), R("您需要哪里的 eSIM\\?"), R("退出编辑"), R("最近搜索"), R("未找到相关内容"), R("搜索结果")]),
    Cat(name: "订单列表", regexes: [R("订单 #"), R("创建日期"), R("刷新订单"), R("重置筛选"), R("^状态$"), R("全部"), R("已创建"), R("已支付"), R("失败"), R("待支付"), R("我的订单"), R("搜索订单ID")]),
    Cat(name: "订单详情", regexes: [R("订单详情"), R("订单信息"), R("订单ID"), R("套餐名称"), R("创建时间"), R("金额"), R("支付方式"), R("计划状态"), R("套餐代码"), R("订单已创建："), R("状态："), R("总计："), R("支付方式：")]),
    Cat(name: "支付与结算", regexes: [R("支付"), R("结算"), R("请选择付款方式"), R("缺少套餐信息"), R("当前付款方式不可用"), R("上游分配失败")]),
    Cat(name: "安装指南", regexes: [R("安装指南"), R("eSIM 安装指南"), R("二维码"), R("激活码"), R("SM-DP\\+ 地址"), R("安装步骤"), R("蜂窝网络"), R("手动输入"), R("匹配码"), R("确认码"), R("连接/下载/应用"), R("启用此线路"), R("数据漫游"), R("网络和互联网"), R("SIM 卡")]),
    Cat(name: "用量与到期", regexes: [R("剩余流量"), R("总流量"), R("已用流量"), R("最后更新"), R("刷新用量"), R("暂未获取到用量信息"), R("到期时间"), R("不限量")]),
    Cat(name: "账号与认证", regexes: [R("登录"), R("注册"), R("电子邮件"), R("密码"), R("登录 / 注册"), R("忘记密码"), R("发送重置邮件"), R("显示密码"), R("隐藏密码"), R("密码设置提示"), R("最少 8 个字符"), R("请输入有效的电子邮件地址"), R("请输入至少"), R("请填写至少"), R("验证码"), R("重新发送验证码"), R("输入代码"), R("重置令牌"), R("重置密码"), R("密码已重置"), R("重置失败"), R("我已有重置令牌"), R("账号信息"), R("请输入名称"), R("名称"), R("姓氏"), R("编辑邮箱"), R("保存资料"), R("尚未设置密码"), R("创建密码"), R("当前密码"), R("新密码"), R("更新密码"), R("删除您的账户"), R("永久删除"), R("删除账户"), R("当前邮箱"), R("验证与新邮箱"), R("新的电子邮件地址"), R("保存邮箱")]),
    Cat(name: "代理商中心与账单", regexes: [R("代理商中心"), R("账单列表"), R("代理商ID"), R("用户名"), R("余额"), R("分成比例"), R("暂无账户数据"), R("账单筛选"), R("参考号"), R("开始日期"), R("结束日期"), R("筛选账单"), R("暂无账单"), R("类型：%@ · 时间：%@"), R("活跃"), R("禁用"), R("状态\\(%@\\)"), R("收入"), R("支出"), R("按货币搜索"), R("代理商名称"), R("别名模式未开启或仓库不可用")]),
    Cat(name: "政策与条款", regexes: [R("隐私政策简介"), R("服务条款简介"), R("条款与条件"), R("我们收集的信息"), R("我们仅用于"), R("您可通过设置"), R("更多详尽条款"), R("服务条款页面")]),
    Cat(name: "覆盖与说明", regexes: [R("说明"), R("网络与覆盖"), R("支持热点共享"), R("不支持热点共享"), R("服务范围"), R("数据"), R("有效期")]),
    Cat(name: "网络与错误", regexes: [R("当前处于离线状态"), R("服务暂时不可用"), R("网络异常"), R("请求失败"), R("未能加载套餐信息"), R("未能加载套餐详情"), R("无结果"), R("发送失败")]),
    Cat(name: "其他", regexes: [])
]

func firstCategory(for key: String) -> String {
    for c in cats { for r in c.regexes { if r.firstMatch(in: key, range: NSRange(location: 0, length: key.utf16.count)) != nil { return c.name } } }
    return "其他"
}

// Ensure English contains all keys
// Ensure English contains all zh-Hans keys
do {
    var enOutLines: [String] = []
    for k in order {
        let v = enMap[k] ?? k
        enOutLines.append("\"\(k)\" = \"\(v)\";")
    }
    writeFile(enPath, enOutLines.joined(separator: "\n"))
}

// Prepare grouped order: preserve stable per-category order based on canonical 'order'
var grouped: [String: [String]] = [:]
for c in cats { grouped[c.name] = [] }
for k in order {
    let cat = firstCategory(for: k)
    grouped[cat, default: []].append(k)
}

// Rewrite each language in grouped canonical order, with comments headings
for (idx, path) in files.enumerated() {
    let lang = langs[idx]
    let map = parse(readFile(path))
    var out: [String] = []
    for c in cats {
        let keys = grouped[c.name] ?? []
        guard !keys.isEmpty else { continue }
        out.append("/* \(c.name) */")
        for k in keys {
            let enV = enMap[k] ?? k
            if let v = map[k] {
                let hasChinese = v.range(of: "[\\u4e00-\\u9fa5]", options: .regularExpression) != nil
                if hasChinese && !(lang == "zh-Hans" || lang == "zh-Hant") {
                    out.append("\"\(k)\" = \"\(enV)\";")
                } else {
                    out.append("\"\(k)\" = \"\(v)\";")
                }
            } else {
                if lang == "zh-Hans" || lang == "zh-Hant" {
                    out.append("\"\(k)\" = \"\(k)\";")
                } else {
                    out.append("\"\(k)\" = \"\(enV)\";")
                }
            }
        }
        out.append("")
    }
    writeFile(path, out.joined(separator: "\n"))
}

print("Synced grouped order with headings for \(files.count) files; keys: \(order.count)")
}
}
#endif
