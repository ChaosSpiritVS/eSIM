# Orders List API

`GET /orders` supports query parameters for pagination and filtering:

- `page` (default `1`) — page index
- `pageSize` (default `20`) — items per page
- `orderId` — filter by order id
- `orderReference` — filter by order reference
- `bundleId` — filter by bundle code/id
- `status` — filter by order status (`created`, `paid`, `failed`) [validated]
- `createdFrom` — ISO 8601 datetime
- `createdTo` — ISO 8601 datetime
- `sortBy` — sort field (`createdAt`, `amount`, `status`) [validated]
- `sortDir` — sort direction (`asc` or `desc`, default `desc`) [validated]

Upstream payload mapping:

- `page` → `page`
- `pageSize` → `page_size`
- `orderId` → `order_id`
- `orderReference` → `order_reference`
- `bundleId` → `bundle_code`
- `status` → `order_status`
- `createdFrom` → `create_time_from` (ISO 8601)
- `createdTo` → `create_time_to` (ISO 8601)
- `sortBy` → `sort_by`
- `sortDir` → `sort_order`

Behavior:

- Fake mode: filters for `orderId`、`bundleId`、`status` applied locally; returns demo data.
- Real mode: forwards all filters to provider via `POST /orders/list` with token management and unified envelope parsing.

Response headers:

- `X-Page` — current page index
- `X-Page-Size` — requested page size
- `X-Has-Next` — `true` when more items likely exist (approximation based on `len(results) == pageSize`)
- `X-Sort-By` — echoes active sort field when provided
- `X-Sort-Dir` — echoes active sort direction (`asc` or `desc`), default `desc` when `sortBy` is set and `sortDir` omitted

Request ID:

- Clients may send `X-Request-Id` (or `Request-Id`) to correlate logs.
- The server returns `X-Request-Id` in every response; if absent, a UUID is generated.
- In real mode, the server forwards `X-Request-Id` to the upstream provider, aiding end-to-end tracing.

Validation and errors:

- Invalid `status`, `sortBy`, or `sortDir` produce `422 Unprocessable Entity` with a validation error body.
- When `sortBy` is omitted, `sortDir` is ignored.
Validation:

- `page` must be `>= 1`
- `pageSize` must be between `1` and `100`
- Violations return `422 Unprocessable Entity` with validation details