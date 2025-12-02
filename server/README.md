# Simigo Backend (FastAPI)

A lightweight backend for the Simigo iOS app. It exposes simplified REST endpoints for orders and usage, while keeping space for integrating upstream eSIM agent APIs.

## Quick Start

1. Install dependencies:

```
pip3 install -r server/requirements.txt
```

2. Run the dev server:

```
uvicorn app.main:app --reload --port 3001 --app-dir server
```

3. API Docs:

- OpenAPI: http://localhost:3001/openapi.json
- Swagger UI: http://localhost:3001/docs

## Endpoints

- Orders
  - `POST /orders` — create order
  - `GET /orders` — list orders (pagination and filters; see `docs/orders_list.md`)
  - `POST /orders/list` — alias; upstream expects POST body (page_number, page_size, bundle_code, order_id, order_reference, start_date, end_date, iccid); returns `{ code, data: { orders, orders_count }, msg }`
  - `POST /orders/detail` — alias; upstream expects POST body (`order_reference`); returns `{ code, data, msg }` where `data` includes `order_id, order_status, bundle_category, bundle_code, bundle_marketing_name, bundle_name, country_code[], country_name[], order_reference, activation_code, bundle_expiry_date, expiry_date?, iccid, plan_started, plan_status, date_created`
  - `POST /orders/consumption` — alias; upstream expects POST body (`order_reference`); returns `{ code, data: { order }, msg }` where `data.order` includes `bundle_expiry_date, iccid, plan_status, data_allocated, data_remaining, data_used, data_unit, minutes_allocated, minutes_remaining, minutes_used, sms_allocated, sms_remaining, sms_used, supports_calls_sms, unlimited`
  - `GET /orders/{id}` — order detail
  - `GET /orders/{id}/usage` — order usage
  - `POST /orders/{id}/refund` — refund request (stub)

- Auth (MVP demo)
  - `POST /auth/register` — register
  - `POST /auth/login` — login
  - `POST /auth/apple` — Apple sign-in (stub)
  - `POST /auth/password-reset` — request password reset (issues token, emails in prod)
  - `POST /auth/password-reset/confirm` — confirm password reset with token

- Catalog
  - `GET /catalog/countries` — list countries
  - `POST /bundle/countries` — alias; upstream expects POST with empty JSON body; returns `{ code, data: CountryDTO[], msg }`
  - `GET /catalog/regions` — list regions
  - `POST /bundle/regions` — alias; upstream expects POST with empty JSON body; returns `{ code, data: RegionDTO[], msg }`
  - `GET /catalog/bundles` — list bundles (optional `country`, `popular`)
  - `POST /bundle/list` — alias; upstream expects POST body (page_number, page_size, country_code, region_code, bundle_category, sort_by); returns `{ code, data: BundleDTO[], msg }`
  - `POST /bundle/networks` — alias; upstream expects POST body (`bundle_code`, optional `country_code`); returns `{ code, data: string[], msg }`
  - `POST /bundle/assign` — alias; upstream expects POST body (`bundle_code`, `order_reference` ≤30 chars, optional `name`, `email`); returns `{ code, data: { orderId, iccid }, msg }`
  - `GET /catalog/bundles/{id}` — bundle detail
  - `GET /catalog/bundles/{id}/networks` — bundle networks

- Agent
  - `GET /agent/account` — fetch agent account info
  - `POST /agent/account` — alias; upstream expects POST; returns `{ code, data: AgentAccountDTO, msg }`
  - `GET /agent/bills` — list agent bills (query: page, pageSize, reference, startDate, endDate)
  - `POST /agent/bills` — alias; upstream expects POST body (page_number, page_size, reference, start_date, end_date); returns `{ code, data: AgentBillsDTO, msg }`

All JSON contracts align with the existing iOS repositories.

### Request IDs

- Clients may include `X-Request-Id` (or `Request-Id`) in requests.
- The server echoes `X-Request-Id` in responses; generates a UUID if absent.
- In real mode, the ID is forwarded to the upstream provider for end-to-end tracing.

### Response Envelope (Upstream-compatible routes)

- HTTP status is always `200` for upstream alias routes.
- JSON envelope: `{ code, data, msg }`.
  - Success: `code=200`, `data`为正常数据，`msg=""`。
  - Validation failure (request didn’t enter processing): `code=422`, `data={}`, `msg="invalid request"`。
  - Processing failure: `code=200`, `data={ err_code, err_msg }`，`msg=""`。
- Common `err_code` examples and tips:
  - `1003` 参数校验错误 → 根据 `err_msg` 与文档修正参数
  - `1004` 资源不存在 → 处理为失败或反馈
  - `1005` 无权限 → 检查越权
  - `1060` 余额不足 → 检查余额
  - `1070` 套餐不可用 → 资源不存在或过期
  - `1080` 交易不存在 → 检查业务侧交易编号
  - `1081` 交易编号重复 → 处理为失败或反馈

## Configuration

The provider client supports two modes:

- Fake mode (default): no external calls, returns demo data
- Real mode: calls upstream agent APIs and maps unified envelopes

Environment variables:

- `PROVIDER_FAKE` (default `true`) — set to `false` to enable real calls
- `PROVIDER_BASE_URL` — upstream base URL (e.g., `https://agent.example.com`)
- `PROVIDER_ACCESS_TOKEN` — optional initial token; will be refreshed when supported
- `PROVIDER_AGENT_USERNAME` — upstream agent username (for `/agent/login`)
- `PROVIDER_AGENT_PASSWORD` — upstream agent password (for `/agent/login`)

Using .env:

- Create a `.env` at project root with:

```
PROVIDER_FAKE=false
PROVIDER_BASE_URL=https://esim-test.tmmapi.com
PROVIDER_AGENT_USERNAME=test
PROVIDER_AGENT_PASSWORD=123456
PROVIDER_LOGIN_PATH=/agent/login
PROVIDER_REFRESH_PATH=/agent/refreshToken
```
The app loads `.env` automatically via `python-dotenv`.

### Email (AWS SES)

To enable production password reset emails via AWS SES, set these environment variables:

```
# Enable and select provider
EMAIL_ENABLED=true
EMAIL_PROVIDER=ses

# AWS SES configuration
SES_REGION=us-east-1
SES_SENDER=noreply@yourdomain.com
# Optional: configuration set for deliverability/metrics
# SES_CONFIGURATION_SET=SimigoDefault

# Password reset link base (used in email and dev logs)
RESET_CONFIRM_BASE_URL=https://app.yourdomain.com/reset
# Token validity (minutes)
RESET_TOKEN_MINUTES=30

# In production, do not expose the token in API responses
RESET_DEV_EXPOSE_TOKEN=false

# Standard AWS credentials (via env or instance profile)
# AWS_ACCESS_KEY_ID=...
# AWS_SECRET_ACCESS_KEY=...
# AWS_SESSION_TOKEN=... # optional
```

Notes:
- When `EMAIL_ENABLED=true` and `EMAIL_PROVIDER=ses`, the backend attempts to send the reset email using AWS SES.
- If SES is not fully configured or `boto3` is missing, the gateway gracefully degrades to no-op; API still returns success to avoid email enumeration.
- In development, you can keep `RESET_DEV_EXPOSE_TOKEN=true` (default) and use the token directly in the app to complete the reset without email.

Install dependencies:

```
pip3 install -r server/requirements.txt
```

Run dev server:

```
uvicorn app.main:app --reload --port 3001 --app-dir server
```

Token management:

- In real mode, tokens are obtained via `/agent/login` and refreshed via `/agent/refreshToken` automatically when expired or on upstream `411` responses.

Error mapping:

- Success can be `code==0` or `code==200` (provider-dependent).
- When response contains `data.err_code`, treat as failure and map:
  - 1003→400, 1070→404, 1081→409, 1016→401, 411→401 (auto-refresh+retry)

## 接入前必读

- 接入须知
  - 在接入 API 服务前，请熟悉产品说明、错误定义、数据同步策略等基础信息。
  - 本服务对上游兼容路由统一返回 `{ code, data, msg }`，HTTP 状态固定为 `200`（详见上文“Response Envelope”）。
  - 建议在每次请求中携带并记录 `Request-Id`，服务端会在响应头回显并在真实模式中透传到上游，便于端到端排查（详见“Request IDs”）。

- 接入步骤
  
  一 代理商注册
  - 账号申请：联系对接人员创建上游代理商账号，获取 `username`、`password` 等敏感信息，并妥善保管。
  - 授权认证：在真实模式下，后端使用上述账号自动调用上游登录以获取 `access_token`，移动端无需直接与上游认证交互。相关配置见“Configuration”。
  - 缓存凭证：`access_token` 通常有效期为 24 小时；后端会在过期或上游返回 `411/401` 时自动刷新并重试。客户端无需在每次调用前重复登录。

  二 开发对接
  - 流程概览：
    1) 完成代理商账号注册（或由我们统一托管）
    2) 签名算法：由后端实现并与上游兼容，移动端无需参与
    3) 访问授权：由后端自动处理并缓存
    4) 获取国家/地区/套餐选项：调用以下接口并按建议缓存
  - 路由与缓存建议：
    - `POST /bundle/countries`：可用国家列表，建议缓存 1 小时
    - `POST /bundle/regions`：可用地区列表，建议缓存 1 小时
    - `POST /bundle/list`：可用套餐列表，可按国家/地区等过滤
    - 订单相关：
      - `POST /orders/list`：订单列表，支持分页与过滤
      - `POST /orders/detail`：订单详情，含 `activation_code` 等字段
      - `POST /orders/consumption`：套餐使用情况（数据/通话/SMS）

- 问题反馈
  - 先查阅常见错误解决方案（见“Response Envelope”中的错误示例与排查建议）。
  - 若仍无法解决，请提供以下信息给对接人员：
    - 问题描述（必填）
    - `request_id`（必填，来自请求头或响应头 `X-Request-Id`）
    - HTTP 响应码与返回值（必填）
    - 请求时间
    - 请求 URL

- 接入必知问题
  - 接口是否区分大小写？区分。所有路径与字段必须严格遵循文档，勿更改大小写。
  - 测试帐号余额不足怎么办？联系对接人员为测试帐号充值。上游常见错误码为 `1060`。
  - 如何生成激活 eSIM 的二维码？购买成功后通过交易详情（`POST /orders/detail`）获取 `activation_code`，以此内容生成二维码即可。

- 基本要求
  - 在日志中记录请求参数与返回值，尤其是 `request_id`，便于排查。
  - 严格遵守接口规范：请求方式、请求格式、参数结构均按文档执行。上游兼容路由统一使用 `POST` 与 JSON 请求体。

- 上线使用
  - 应用测试完成后，请联系对接人员创建生产环境账号与接入信息。
  - 自托管后端需在环境中配置 `PROVIDER_BASE_URL`、`PROVIDER_AGENT_USERNAME`、`PROVIDER_AGENT_PASSWORD`，并将 `PROVIDER_FAKE=false` 以启用真实模式。
## 参数大小写规范与示例

以下规则适用于 `POST /bundle/list` 请求，并由服务端在转发上游前进行规范化：

- `bundle_category`: 使用小写枚举值 `global | region | country | cruise`，服务端会统一转为小写。
- `region_code`: 使用小写枚举（例如 `eu`、`sa`），服务端会统一转为小写。
- `country_code`: 使用 ISO3 大写（例如 `DEU`、`FRA`），服务端会统一转为大写。

示例：

```bash
curl -s -X POST http://127.0.0.1:8000/bundle/list \
  -H 'Content-Type: application/json' \
  -d '{"page_number":1,"page_size":10,"bundle_category":"region","region_code":"eu"}'

curl -s -X POST http://127.0.0.1:8000/bundle/list \
  -H 'Content-Type: application/json' \
  -d '{"page_number":1,"page_size":10,"bundle_category":"region","region_code":"EU"}'

curl -s -X POST http://127.0.0.1:8000/bundle/list \
  -H 'Content-Type: application/json' \
  -d '{"page_number":1,"page_size":10,"bundle_category":"country","country_code":"DEU"}'
```

说明：
- 上述两个 `region` 示例（`eu` 与 `EU`）返回一致，因为服务端会规范化为小写。
- 如果上游暂无 `global` 类别数据，返回为空属正常现象。