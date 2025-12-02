# API 问题记录

用于记录 eSIM 接口问题与排查线索。每次遇到问题请新增一条记录，严格按照以下模板填写。

## 记录模板

- 问题描述：
- request_id：
- HTTP 响应码：
- 返回值：
- 请求时间：
- 请求 URL：

> 备注：如果方便，请附带请求头（尤其是 `Request-Id`/`Authorization`）与服务端 `X-Request-Id` 响应头，便于端到端追踪。

---

## 示例

- 问题描述：`/bundle/countries` 返回结构和字段与文档不一致（缺少 `iso2_code`/`country_name`，返回了 `code`/`name`）。
- request_id：`b6e9c6dd-1c6a-4f4b-9d57-2b2c1c4b1c0a`
- HTTP 响应码：`200`
- 返回值：
  ```json
  {
    "code": 200,
    "data": [
      { "code": "AF", "name": "Afghanistan" }
    ],
    "msg": ""
  }
  ```
- 请求时间：`2025-11-08 11:02:30 +0800`
- 请求 URL：`POST https://esim-test.tmmapi.com`

---

- 问题描述：`/bundle/regions` 的 `data` 返回为数组（`[{code,name},...]`），返回结构和字段与文档不一致。
- request_id：`b6e9c6dd-1c6a-4f4b-9d57-2b2c1c4b1c0a`
- HTTP 响应码：`200`
- 返回值：
  ```json
  {
    "code": 200,
    "data": [
      { "code": "eu", "name": "Europe" },
      { "code": "sa", "name": "South America" }
    ],
    "msg": ""
  }
  ```
- 请求时间：`2025-11-08 11:02:30 +0800`
- 请求 URL：`POST https://esim-test.tmmapi.com`
