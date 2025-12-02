# eSIM SDK 回调接入说明

本文档说明如何在集成第三方 eSIM 安装 SDK 后，将安装结果回传到应用并触发用量刷新。

> 新增：支付事件桥接用于在支付成功后自动刷新订单详情与列表用量，并在启用别名模式时正确切换到上游订单 ID。

## 回调桥

文件：`Simigo/Simigo/Services/ESIMSDKBridge.swift`

提供以下方法用于在 SDK 成功/失败回调中调用：

```swift
// 安装成功
ESIMSDKBridge.installationSucceeded(orderId: "<ORDER_ID>", iccid: "<OPTIONAL_ICCID>")

// 安装失败
ESIMSDKBridge.installationFailed(orderId: "<ORDER_ID>", reason: "<OPTIONAL_REASON>")
```

说明：
- `orderId` 为业务订单 ID，用于定位对应的订单并刷新其用量缓存。
- `iccid` 可选，如果 SDK 提供设备 ICCID 可一并传入，后续如需联动可扩展。
- `reason` 可选，失败原因或错误码。

文件：`Simigo/Simigo/Services/PaymentEventBridge.swift`

提供以下方法用于在支付流程成功/失败后调用：

```swift
// 支付成功（可选携带别名模式下的旧ID）
PaymentEventBridge.paymentSucceeded(orderId: "<ORDER_ID>", oldOrderId: "<OPTIONAL_OLD_ID>", method: "<PAY_METHOD>")

// 支付失败（显示错误提示并刷新对应页面）
PaymentEventBridge.paymentFailed(orderId: "<ORDER_ID>", reason: "<OPTIONAL_REASON>", method: "<PAY_METHOD>")
```

说明：
- `orderId` 为当前生效的订单 ID；若启用别名模式并完成上游分配，`orderId` 为上游订单 ID。
- `oldOrderId` 可选，支付前的本地订单 ID；用于列表/详情在事件比对时兼容旧 ID。
- `method` 可选，支付方式标识（如 `paypal`）。
- `reason` 可选，失败原因会在列表与详情页的顶部错误横幅中展示。

## 应用内响应

已在以下 ViewModel 内订阅支付事件：

- `OrdersListViewModel`
  - 收到成功事件后，会：
    - 显式失效该订单的用量缓存。
    - 强制重新拉取最新用量（避免命中未过期缓存）。
    - 监听支付成功事件后会重载列表以反映订单状态/ID 变化，并对目标订单用量做一次强制刷新。
  - 收到失败事件后，会：
    - 显示错误提示横幅（包含失败原因，如有）。
    - 重载列表以尽快反映订单状态变化（如从 created -> failed）。

- `OrderDetailViewModel`
  - 收到成功事件（且订单 ID 匹配当前详情页）后，会：
    - 显式失效当前订单用量缓存。
    - 执行一次 `load()` 重拉订单详情与用量（状态与用量同步更新）。
  - 收到失败事件（且订单 ID 匹配当前详情页）后，会：
    - 显示错误提示横幅（包含失败原因，如有）。
    - 执行一次 `load()` 重拉订单详情以反映最新状态。

> 轻提示：支付成功显示绿色提示横幅，支付失败显示红色错误横幅；提示在 3–5 秒后自动消隐。

UI：
- 列表与详情页的错误横幅内置“重试支付”按钮，点击后跳转到 `CheckoutView` 重新发起支付。

## 集成示例（伪代码）

```swift
func onEsimInstallCallback(result: SDKInstallResult, orderId: String) {
    switch result {
    case .success(let iccid):
        ESIMSDKBridge.installationSucceeded(orderId: orderId, iccid: iccid)
    case .failure(let error):
        ESIMSDKBridge.installationFailed(orderId: orderId, reason: error.localizedDescription)
    }
}
```

支付成功事件示例（在 `CheckoutViewModel` 支付成功后触发）：

```swift
// 在支付成功分支中：
PaymentEventBridge.paymentSucceeded(orderId: newOrderId, oldOrderId: originalOrderId, method: String(describing: selectedPaymentMethod))
```

支付失败事件示例（在支付流程抛出异常或返回失败状态时触发）：

```swift
// 当支付处理器抛出异常：
PaymentEventBridge.paymentFailed(orderId: current.id, reason: error.localizedDescription, method: String(describing: selectedPaymentMethod))

// 当支付状态为 failed（无明确原因也可传 nil）：
PaymentEventBridge.paymentFailed(orderId: current.id, reason: nil, method: String(describing: selectedPaymentMethod))
```

## 验证步骤

- 模拟调用：在调试环境手动调用 `ESIMSDKBridge.installationSucceeded(orderId:)`，观察：
  - 订单列表中对应订单的“使用情况”会在短延迟后更新。
  - 打开订单详情页（或已在详情页）时，用量会自动刷新。
- 日志/调试：如使用 Charles/Proxyman，确认安装成功后的用量接口被调用，缓存键使用了环境前缀且写入了最新数据。

- 支付事件验证：在支付成功后，应观察到：
  - 订单详情页自动重拉并显示最新状态与用量。
  - 订单列表刷新，若启用别名模式，订单 ID 切换为上游返回的 ID；对应订单用量做强制刷新。

- 支付失败事件验证：在支付失败后，应观察到：
  - 列表页顶部显示错误提示横幅，并重载列表以反映状态变化。
  - 详情页（若当前订单匹配）显示错误提示横幅，并重拉详情以反映失败状态。