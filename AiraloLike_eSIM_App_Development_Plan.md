# Airalo 风格 eSIM iOS 应用开发计划（MVP+迭代）

## 1. 项目概述

- 目标：打造一款类似 Airalo 的 eSIM 市场与管理 App，支持国家/地区套餐浏览、下单购买、引导式安装与使用状态展示；后期增加分享/邀请与奖励体系。
- 平台与架构：iOS（Swift + SwiftUI，MVVM + Repository 模式），后端自研用户 API，代理商 API 由 eSIM 供应商提供（Agent/Bundles/Orders）。
- 约束与假设：
  - 移动端无法直接使用运营商安装私有权限，MVP采用“二维码/SM-DP+ + Activation Code”的引导式安装。
  - 移动端不暴露代理商密钥，所有供应商调用经由自有后端转发。
  - 支付合规按电信服务范畴处理（Stripe+Apple Pay），同时评估 App Store 审核政策风险。

## 2. MVP 范围（首版上线）

### 2.1 移动端功能

1) 套餐商城：
   - 国家/地区/全球 Tab（列表、热门、搜索）。
   - 套餐卡片展示（价格、流量、有效期、覆盖网络）。
   - 套餐详情页（更详尽的说明、支持网络、FAQ、安装须知）。

2) 下单与支付：
   - 下单确认（选择套餐与数量，展示价格与条款）。
   - 支付：Stripe（含 Apple Pay 支持）。
   - 下单成功后展示 eSIM 信息（SM-DP+、激活码、二维码）。

3) 引导式安装：
   - 步骤化教程（设置→蜂窝网络→添加 eSIM →扫描二维码/输入激活信息）。
   - 常见问题与错误处理（激活失败、设备不支持、漫游设置）。

4) 我的 eSIM / 订单：
   - 已购套餐列表、订单详情、状态（已激活/未激活/过期）。
   - 使用情况（通过供应商 Orders/Usage 接口展示剩余流量、到期时间）。

5) 账号与基础：
   - 登录（邮箱验证码/Apple Sign-In 二选一即可）。
   - 基本资料（昵称、语言、国家）。
   - 多语言（中文/英文）。
   - 客服入口（链接到聊天或反馈页）。
   - 崩溃与统计（Firebase Crashlytics + Analytics 或 Sentry）。

### 2.2 后端功能

1) 用户与会话：
   - 用户注册/登录/刷新令牌（JWT）。
   - 用户资料查询/更新。

2) 目录与缓存：
   - 同步国家/地区/套餐/网络列表（来自供应商 Bundles API），本地缓存与定时刷新。
   - 对移动端提供聚合接口（分页、排序、检索）。

3) 订单与采购：
   - 移动端提交订单 → 后端创建我方订单 → 调用供应商“购买 eSIM 套餐” → 回填 eSIM 信息（SM-DP+、激活码、二维码）。
   - 订单查询、交易状态跟踪、退款与异常日志（MVP 可仅支持查询与退单占位）。

4) 支付与结算：
   - Stripe 后端密钥管理、支付意图创建、Webhook 入账校验。
   - 对账与审计（每日对账报表、订单状态校验）。

5) 安全与合规：
   - 代理商凭证保密（KMS/Env），速率限制与审计日志。
   - eSIM 激活信息加密存储（仅在已购订单且登录态下可访问）。

## 3. 迭代版本规划（MVP 后）

### V1.1（分享与奖励、体验优化）
- 分享/邀请：生成邀请码或分享链接，被邀请用户首购享折扣，邀请者获得奖励（Airmoney 类似）。
- 钱包/积分：记录奖励余额、消费记录；在支付时可抵扣。
- FAQ 与指引中心升级（视频、动图、机型适配）。
- 更丰富的多语言与货币显示（GBP、USD、CNY）。

### V1.2（可观测与客服、性能）
- 监控大盘、异常告警、慢请求分析。
- App 内客服（工单或聊天 SDK 接入）。
- 列表离线缓存与增量同步、启动速度优化。

### V2.0（产品拓展）
- 订阅/自动续费套餐（需与供应商确认支持）。
- 组合包与跨地区套餐、动态推荐与 A/B 测试。
- 企业账号与批量采购、发票与税务支持。

## 4. 技术架构设计

### 4.1 总体架构

- 客户端（iOS）：SwiftUI + MVVM + Repository，使用 `async/await` 或 Combine，`URLSession` 网络层，`Keychain` 令牌与隐私数据，`UserDefaults/CoreData` 轻量缓存。
- 后端：任意主流框架（NestJS/Express/FastAPI/Go 皆可），PostgreSQL/MySQL，Redis（缓存/队列），对象存储（二维码图/附件可选）。
- 供应商：Agent 登录/刷新、Bundles 列表与购买、Orders 查询与用量。
- 部署：Cloud（Render/Fly.io/Vercel + Supabase/PlanetScale/自建均可），GitHub Actions CI。

文字版架构图：

```
 iOS App ──REST──▶ 自有后端 API ──M2M──▶ eSIM 供应商 API
            │                        
            ├─▶ 支付网关（Stripe）
            └─▶ 对象存储/日志/监控
```

### 4.2 iOS 客户端目录建议

```
App/
  ├─ Application.swift / AppState
  ├─ Config/ (常量、环境、路由)
  ├─ Services/ (NetworkService, AuthService, PaymentService)
  ├─ Repositories/ (CatalogRepository, OrderRepository, UserRepository)
  ├─ Models/ (Country, Region, Bundle, Network, Order, EsimProfile, User)
  ├─ ViewModels/ (...VM)
  ├─ Views/ (Marketplace, BundleDetail, Checkout, MyEsim, Account)
  ├─ Utils/ (ErrorMapper, Formatter, QRGenerator)
  └─ Resources/ (Localizable.strings, Assets)
```

### 4.3 后端接口草案

- 认证：`POST /auth/signup`，`POST /auth/login`，`POST /auth/refresh`，`GET /me`
- 目录：`GET /catalog/countries`，`GET /catalog/regions`，`GET /catalog/bundles?country=HK`，`GET /catalog/bundle/:id`
- 订单：`POST /orders`（创建并采购），`GET /orders/:id`，`GET /orders`，`POST /orders/:id/refund`（占位）
- 用量：`GET /usage/:orderId`
- 支付：`POST /payments/intent`，`POST /payments/webhook`
- 分享/奖励（迭代）：`POST /referrals/link`，`GET /wallet/balance`，`POST /wallet/redeem`

### 4.4 供应商 API 对接点（示例）

- Agent：登录、刷新访问凭证、查询账户/账单（仅后端使用）。
- Bundles：可用国家列表、可用地区列表、可用套餐列表、套餐网络列表、购买 eSIM 套餐。
- Orders：交易订单记录、交易详情、套餐使用情况。
- 定时任务：每 6~12 小时刷新目录缓存；下单后拉取状态与用量。

## 5. 数据模型草案

- `users(id, email, apple_id, nickname, locale, created_at)`
- `sessions(user_id, refresh_token, expired_at)`
- `countries(code, name_zh, name_en)`，`regions(code, name)`
- `bundles(id, country_code, name, data_amount, validity_days, price, networks, provider_bundle_id)`
- `orders(id, user_id, bundle_id, status, price_paid, provider_order_id, created_at)`
- `esim_profiles(order_id, smdp, activation_code, qr_url, encrypted_payload)`
- `payments(id, order_id, stripe_intent_id, amount, currency, status)`
- （迭代）`referrals(id, inviter_id, invitee_id, reward_amount)`、`wallets(user_id, balance)`、`transactions(...)`

## 6. 安全与合规

- 秘钥管理：后端仅持有代理商密钥，使用 KMS 或环境变量与最小权限部署。
- 个人数据保护：遵循 GDPR/CCPA 最小化采集；eSIM 激活信息加密（行级加密）。
- 访问控制：JWT + 细粒度授权；速率限制与 IP 黑名单。
- 审计与合规：订单与支付留痕；隐私政策与用户协议（上线前完成）。

## 7. 测试与质量保障

- 单元测试（ViewModel、Repository、后端 Service）。
- 集成测试（目录聚合、下单采购、Webhook 验证）。
- 端到端（沙箱环境：下单→支付→回填 eSIM →安装流程）。
- 覆盖率与崩溃率指标；灰度发布与监控。

## 8. 发布与运营

- 内测（TestFlight 50–100 人），收集性能与安装成功率。
- 上架文案与截图（中文/英文），隐私政策、支持网址。
- 运营报表：日活、下单转化、失败率、退款率、客服问题分布。

## 9. 开发周期与里程碑（单人）

> 适用于 6–8 周 MVP 节奏，后续两期迭代各 2–3 周。

- 第 1 周：
  - 需求细化与原型；iOS 项目脚手架（SwiftUI+MVVM）；后端项目初始化与基础认证。
  - 供应商 Agent 接入（登录/刷新）；国家/地区/套餐 API 校验。

- 第 2 周：
  - 商城列表、搜索与详情页；目录缓存（后端）与分页。
  - 我的 eSIM / 订单列表框架；崩溃与统计接入。

- 第 3 周：
  - 下单与支付（Stripe Intent + Apple Pay）；订单创建与采购打通；Webhook 验证入账。

- 第 4 周：
  - 引导式安装（二维码/SM-DP+）；订单详情与状态展示；用量页面。

- 第 5 周：
  - 多语言与设定页；客服入口与 FAQ；性能优化与离线缓存。

- 第 6 周：
  - 全面测试与修复；隐私与条款；上架准备与灰度发布。

- V1.1（2–3 周）：分享与奖励、钱包抵扣、目录体验优化。
- V1.2（2–3 周）：监控与客服、性能与启动速度、更多语言与货币。

## 10. 风险清单与缓解

- eSIM 安装受限：无法使用运营商私有安装 API → 采用二维码/SM-DP+ 激活与清晰教程；收集安装失败原因并优化。
- 支付与审核：电信服务是否必须 IAP → 走 Stripe+Apple Pay 同时预案 IAP；与 App Review 沟通并准备说明文档。
- 供应商稳定性：接口限流或波动 → 后端缓存与重试、监控告警、降级展示；与供应商约定 SLA。
- 单人开发瓶颈：并行度有限 → 明确优先级，减少非关键需求，拉齐迭代节奏。
- 数据安全：eSIM 激活信息极敏感 → 加密存储与访问审计，最小化暴露（仅订单页可见）。
- 多机型与系统差异：安装流程不同 → 设计机型分支教程与常见错误页。

## 11. 验收标准（MVP）

- 能够浏览并搜索国家/地区套餐，详情信息完整。
- 完成下单与支付，订单能采购成功并展示 eSIM 激活信息。
- 用户可依教程完成安装并连接网络；App 能展示用量与到期信息。
- 账号登录稳定，多语言与客服入口可用；崩溃率低于 1%。

## 12. 资源与工具建议

- 技术：Swift 5.9+、SwiftUI、Combine/`async/await`、URLSession、Firebase 或 Sentry、Stripe SDK。
- 后端：Node.js 18+/NestJS、PostgreSQL、Redis、BullMQ/Sidekiq 类队列、GitHub Actions。
- 设计与管理：Figma、Linear/Jira、Notion；监控：Grafana/Prometheus（可选）。

## 13. 立即下一步

- 创建 iOS 与后端项目骨架；拉通供应商沙箱；完成国家/地区/套餐列表与详情展示；制定支付与审核路径。