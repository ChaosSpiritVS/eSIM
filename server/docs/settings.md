# Settings API

提供应用的语言与货币选项列表，并在用户资料更新时进行白名单校验。

## GET `/settings/languages`

- 返回：`[{ code: string, name: string }]`
- 数据来源：数据库表 `settings_languages`（应用启动时自动种子）。
- 排序：按 `code` 升序。

示例：

```json
[
  { "code": "zh-Hans", "name": "简体中文" },
  { "code": "zh-Hant", "name": "繁體中文" },
  { "code": "en", "name": "English" }
]
```

## GET `/settings/currencies`

- 返回：`[{ code: string, name: string, symbol?: string }]`
- 数据来源：数据库表 `settings_currencies`（应用启动时自动种子）。
- 排序：按 `code` 升序。

示例：

```json
[
  { "code": "USD", "name": "美元 (USD)", "symbol": "$" },
  { "code": "EUR", "name": "欧元 (EUR)", "symbol": "€" },
  { "code": "JPY", "name": "日元 (JPY)", "symbol": "¥" }
]
```

## PUT `/me`

- 请求体（可选字段）：`{ name?: string, language?: string, currency?: string, country?: string }`
- 行为：
  - 当 `language` 不在 `settings_languages.code` 白名单中，返回 `400 Unsupported language`。
  - 当 `currency` 不在 `settings_currencies.code` 白名单中，返回 `400 Unsupported currency`。
  - 其他字段将按原逻辑更新。

示例（成功）：

```bash
curl -X PUT http://127.0.0.1:3001/me \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"language":"en","currency":"USD"}'
```

示例（失败）：

```bash
curl -X PUT http://127.0.0.1:3001/me \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"language":"xx","currency":"ZZZ"}'
# 返回：400
```

## 种子与维护

- 首次启动时，`init_db()` 将在空表场景下写入基础语言与货币选项。
- 可通过 SQL 插入扩充选项，例如：

```sql
INSERT INTO settings_languages (code, name) VALUES ('fr', 'Français');
INSERT INTO settings_currencies (code, name, symbol) VALUES ('CNY', '人民币 (CNY)', '¥');
```

## 调试命令

```bash
curl -sS http://127.0.0.1:3001/health
curl -sS http://127.0.0.1:3001/settings/languages | jq .
curl -sS http://127.0.0.1:3001/settings/currencies | jq .
```