# 别名（Upstream）接口接入说明

本文档说明如何在 iOS 侧启用并使用“别名接口”（Envelope 风格），以及与现有 ViewModel 的对接点。

## 开启方式

- 在 `Simigo/Simigo/Config/AppConfig.swift` 将：
  - `useAliasAPI` 设为 `true`
  - `baseURL` 指向别名服务端地址，例如 `http://127.0.0.1:8000`
  - 如果仍使用模拟数据，则 `isMock` 需为 `false` 才能走真实网络（或直接按需在 ViewModel 注入仓库实例）。

> 注意：真机调试请使用 Mac 局域网 IP，而不是 `127.0.0.1`。

> 端口与本地预览
>
> - 别名服务推荐使用 `http://127.0.0.1:8000`。
> - 如需同时运行静态 HTML 预览（例如在 `Preview/` 目录使用 `python3 -m http.server`），请改用不同端口（如 `8001`），以避免与别名服务端口冲突。
> - 本地 REST 风格开发示例端口为 `3001`（见 `server/README.md`）；切换 `useAliasAPI` 时务必同步更新 iOS 客户端的 `baseURL` 指向正确服务。

## 已接入仓库

- 上游订单仓库：`UpstreamOrderRepository.swift`
  - `/orders/list`、`/orders/detail`、`/orders/consumption`
- 上游套餐仓库：`UpstreamCatalogRepository.swift`
  - `/bundle/list`、`/bundle/networks`、`/bundle/assign`
- 上游代理商仓库：`UpstreamAgentRepository.swift`
  - `/agent/account`、`/agent/bills`

均复用网络层 `Envelope<T>` 与 `postEnvelope` 方法，支持自动注入 `Request-Id` 与统一错误处理，`JSONDecoder` 使用 `convertFromSnakeCase`（兼容蛇形字段）。

## 与 ViewModel 的对接

- `MarketplaceViewModel` 已内置开关：当 `AppConfig.useAliasAPI == true` 时，调用 `HTTPUpstreamCatalogRepository.listBundles(...)` 返回 `ESIMBundle` 列表；否则保持使用现有 `CatalogRepositoryProtocol`。
  - 示例：
    ```swift
    // 默认 pageNumber=1, pageSize=20，可根据 UI 需求调整
    let rid = UUID().uuidString
    let items = try await upstream.listBundles(
        pageNumber: 1,
        pageSize: 20,
        countryCode: nil,
        regionCode: nil,
        bundleCategory: nil,
        sortBy: nil,
        requestId: rid
    )
    ```
- 订单列表已增加别名模式分支：`OrdersListViewModel` 在 `AppConfig.useAliasAPI` 为真时调用 `HTTPUpstreamOrderRepository.listOrders` 并做最小字段映射至现有 `Order` 模型（包括 `orderId`、`bundleCode`、价格、创建时间、状态等），以保证 UI 正常渲染；详情与用量仍走本地接口，后续可逐步切换。
 - 代理商联调（新增）：`AgentCenterViewModel` 提供账户与账单的加载方法，便于在移动端直接联调。
   - 账户：
     ```swift
     let vm = AgentCenterViewModel()
     vm.load() // 内部先获取账户再拉取最近账单
     ```
   - 账单筛选：
     ```swift
     vm.searchBills(reference: "REF-001", startDate: "2024-01-01", endDate: "2024-12-31")
     ```
   - `AgentCenterViewModel` 默认在 `useAliasAPI` 为真时启用上游仓库；若未开启会返回错误提示。
 - 订单详情与用量（新增）：`OrderDetailViewModel` 在 `AppConfig.useAliasAPI` 为真时走别名分支。
   - 先以 `orderId` 调用 `/orders/list` 获取对应的 `orderReference`；若未找到则返回错误提示。
   - 使用 `orderReference` 调用 `/orders/detail` 并做最小映射到现有 `Order`（`id`、`bundleId`、`amount`、`currency`、`createdAt`、`status`、`paymentMethod`）。当前 `amount` 从列表项价格推导（优先代理价，其次卖价），`currency` 默认 `USD`，`paymentMethod` 默认 `paypal`。
   - 对 `createdAt` 做兼容解析：既支持时间戳字符串，也支持 ISO8601 字符串。
   - 用量通过 `/orders/consumption` 获取并映射为 `OrderUsage`（`remainingMB`、`expiresAt`、`lastUpdated`）。`dataUnit` 支持 `GB/MB/KB`，到期时间同样兼容时间戳与 ISO8601。
   - 当 `bundleCode` 缺失时跳过套餐详情加载，UI 会显示“未能加载套餐信息”。

## 请求标识（Request-Id）

- 网络层会在 `postEnvelope` 中自动注入 `Request-Id`（若未显式传入则生成随机 UUID）；服务端也会在响应头附带 `X-Request-Id`。
- 建议在关键用户操作（下单、分配）时生成并记录 `Request-Id`，便于端到端追踪。

## 常见问题

- 看到 `Authorization: Bearer ...` 头？该头用于本地 REST 风格接口；别名上游接口真正向 Provider 透传的令牌由服务端负责设置到 `Access-Token`，iOS 侧无需关心。
- 解析失败？确认服务端字段为蛇形命名；`Envelope<T>` 默认使用 `convertFromSnakeCase`，确保 DTO 属性对应即可。
- `baseURL` 不一致？别名与本地 REST 是两套路径，请在切换模式时同步更新 `baseURL`。

## 后续建议

- 根据需要扩展 `/orders/list` 与 `/orders/detail` 的字段（例如货币与支付方式），以便更准确地渲染现有 UI。
- 在设置页加一个“真实模式 / 别名模式”开关，切换后刷新相关列表。
 - 为代理商账单增加本地缓存与分页加载，优化性能与体验。