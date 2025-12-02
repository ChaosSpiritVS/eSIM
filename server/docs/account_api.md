# 账户信息接口

提供更改邮箱、更新密码与删除账号的 API。所有接口均需要 `Authorization: Bearer <accessToken>`。

## 更改邮箱

- `PUT /me/email`
- 请求体：

```json
{ "email": "new@example.com", "password": "currentPassword" }
```

- 响应：`UserDTO`
- 错误：
  - 400 `您必须创建一个密码才能成功更改电子邮件地址`（当前账户未设置密码）
  - 409 `该电子邮件已被使用`
  - 401 `密码不正确`

## 更新/设置密码

- `PUT /me/password`
- 请求体：

```json
{ "currentPassword": "optional", "newPassword": "atLeast8Chars" }
```

- 在首次设置密码时可省略 `currentPassword`。
- 响应：`{ "success": true }`
- 错误：
  - 400 `密码至少需要 8 位`
  - 401 `当前密码不正确`

## 删除账号

- `DELETE /me`
- 请求体：

```json
{ "reason": "not_needed", "details": "...", "currentPassword": "optional" }
```

- 如果账户有密码，必须提供正确的 `currentPassword`。
- 字段说明：
  - `reason`：删除原因（可选），长度 ≤ 32。建议值：`device`、`security`、`not_needed`、`service`、`ux`、`other`。
  - `details`：补充说明（可选），长度 ≤ 1000 字符，超出部分将被截断。
- 响应：`{ "success": true }`
- 服务器会在删除前记录一条删除日志（包含 `user_id`、删除时快照 `email`、`reason`、`details`、时间戳）。
 - 删除后数据处理：
   - 会话与刷新令牌将被清理，需重新登录；
   - 订单记录将被保留，其 `user_id` 置为 `NULL`（不删除订单）。

## 获取当前用户信息

- `GET /me` → `UserDTO`
- `PUT /me` → 更新 `name`、语言、货币、国家等（已有接口）