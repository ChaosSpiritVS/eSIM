from __future__ import annotations
from datetime import datetime
from typing import Optional, List, Literal
from pydantic import BaseModel, Field, ConfigDict


class InstallationDTO(BaseModel):
    qrCodeUrl: Optional[str] = None
    activationCode: Optional[str] = None
    instructions: Optional[List[str]] = None
    profileUrl: Optional[str] = None
    smdp: Optional[str] = Field(default=None, description="SMDP 地址")


class OrderDTO(BaseModel):
    id: str
    bundleId: str
    amount: float
    currency: str
    createdAt: datetime
    status: str
    paymentMethod: str
    installation: Optional[InstallationDTO] = None


class CreateOrderBody(BaseModel):
    bundleId: str
    paymentMethod: str


class UsageDTO(BaseModel):
    remainingMb: float
    expiresAt: Optional[datetime] = None
    lastUpdated: Optional[datetime] = None


class RefundStepDTO(BaseModel):
    state: Literal["requested", "reviewing", "completed", "rejected"]
    updatedAt: datetime
    note: Optional[str] = None

class RefundDTO(BaseModel):
    accepted: bool
    state: Optional[str] = None
    steps: Optional[List[RefundStepDTO]] = None


# ===== 认证相关 DTO =====
class UserDTO(BaseModel):
    id: str
    name: str
    lastName: Optional[str] = None
    email: Optional[str] = None
    # 是否已设置密码（由服务器根据 password_hash 推导）
    hasPassword: bool = False
    language: Optional[str] = None
    currency: Optional[str] = None
    country: Optional[str] = None


class RegisterBody(BaseModel):
    name: str
    lastName: Optional[str] = None
    email: str
    password: str
    marketingOptIn: bool = False
    verificationCode: Optional[str] = None


class LoginBody(BaseModel):
    email: str
    password: str


class AppleLoginBody(BaseModel):
    userId: str
    identityToken: Optional[str] = None


class PasswordResetBody(BaseModel):
    email: str


class ResetDTO(BaseModel):
    success: bool = True
    # 仅用于开发环境：可选暴露令牌以便测试
    devToken: Optional[str] = None


class PasswordResetConfirmBody(BaseModel):
    token: str
    newPassword: str


# ===== JWT/认证令牌 DTO =====
class AuthTokensDTO(BaseModel):
    accessToken: str
    refreshToken: str


class AuthResponseDTO(BaseModel):
    user: UserDTO
    accessToken: str
    refreshToken: str


class RefreshBody(BaseModel):
    refreshToken: str


class LogoutBody(BaseModel):
    refreshToken: str


# ===== 个人资料 DTO =====
class UpdateProfileBody(BaseModel):
    name: Optional[str] = None
    lastName: Optional[str] = None
    language: Optional[str] = None
    currency: Optional[str] = None
    country: Optional[str] = None


# ===== 账户相关 DTO =====
class ChangeEmailBody(BaseModel):
    email: str
    password: str
    verificationCode: Optional[str] = None


class UpdatePasswordBody(BaseModel):
    currentPassword: Optional[str] = None
    newPassword: str


class DeleteAccountBody(BaseModel):
    reason: Optional[str] = Field(default=None, max_length=32)
    details: Optional[str] = Field(default=None, max_length=1000, description="用户补充说明，最长 1000 字符")
    currentPassword: Optional[str] = None


class SuccessDTO(BaseModel):
    success: bool = True

class EmailCodeRequestBody(BaseModel):
    email: str
    purpose: Literal["register", "change_email"]

class EmailCodeDTO(BaseModel):
    success: bool = True
    # 开发环境可选暴露验证码，便于测试
    devCode: Optional[str] = None


# ===== 设置项 DTO =====
class LanguageOptionDTO(BaseModel):
    code: str
    name: str


class CurrencyOptionDTO(BaseModel):
    code: str
    name: str
    symbol: Optional[str] = None


# ===== 商品目录 DTO =====
class BundleDTO(BaseModel):
    id: str
    name: str
    countryCode: str
    price: float
    currency: str
    dataAmount: str
    validityDays: int
    description: Optional[str] = None
    supportedNetworks: Optional[List[str]] = None
    hotspotSupported: Optional[bool] = None
    coverageNote: Optional[str] = None
    termsUrl: Optional[str] = None


class CountryDTO(BaseModel):
    code: str
    name: str


# ===== 上游 alias 风格：国家列表 DTO =====
class AliasCountryDTO(BaseModel):
    iso2_code: str
    iso3_code: str
    country_name: str


class AliasCountriesDTO(BaseModel):
    countries: List[AliasCountryDTO]
    countries_count: int

class AliasRegionDTO(BaseModel):
    region_code: str
    region_name: str

class AliasRegionsDTO(BaseModel):
    regions: List[AliasRegionDTO]
    regions_count: int


class RegionDTO(BaseModel):
    code: str
    name: str


# ===== 搜索 DTO =====
class SearchResultDTO(BaseModel):
    kind: Literal["country", "region", "bundle"]
    id: str
    title: str
    subtitle: Optional[str] = None
    countryCode: Optional[str] = None
    regionCode: Optional[str] = None
    bundleCode: Optional[str] = None

class SearchLogBody(BaseModel):
    kind: Literal["country", "region", "bundle"]
    id: Optional[str] = None
    title: Optional[str] = None
    subtitle: Optional[str] = None
    countryCode: Optional[str] = None
    regionCode: Optional[str] = None
    bundleCode: Optional[str] = None


# ===== 代理（Agent）相关 DTO =====
class AgentAccountDTO(BaseModel):
    agent_id: str
    username: str
    name: str
    balance: float
    revenue_rate: int
    status: int
    created_at: int


class AgentBillDTO(BaseModel):
    bill_id: str
    trade: int
    amount: float
    reference: str
    description: str
    created_at: int


class AgentBillsDTO(BaseModel):
    bills: List[AgentBillDTO]
    bills_count: int


class AgentBillsQuery(BaseModel):
    page_number: int
    page_size: int
    reference: Optional[str] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None

# ===== 套餐列表查询（上游 alias 风格） =====
class BundleListQuery(BaseModel):
    page_number: int
    page_size: int
    country_code: Optional[str] = None
    region_code: Optional[str] = None
    bundle_category: Optional[str] = None
    sort_by: Optional[str] = None
    bundle_code: Optional[str] = None
    q: Optional[str] = None

class BundleNetworksQuery(BaseModel):
    bundle_code: str
    country_code: Optional[str] = None

# ===== 订单列表（上游 alias 风格） =====
class OrdersListQuery(BaseModel):
    page_number: int
    page_size: Literal[10, 25, 50, 100]
    bundle_code: Optional[str] = None
    order_id: Optional[str] = None
    order_reference: Optional[str] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    iccid: Optional[str] = None

# ===== 订单详情（上游 alias 风格） =====
class OrdersDetailQuery(BaseModel):
    order_reference: str

# 通过上游订单ID桥接详情
class OrdersDetailByIdQuery(BaseModel):
    order_id: str = Field(..., alias="orderId")
    model_config = ConfigDict(populate_by_name=True)

# ===== 订单用量（上游 alias 风格） =====
class OrdersConsumptionQuery(BaseModel):
    order_reference: str

class OrdersConsumptionByIdQuery(BaseModel):
    order_id: str

# 订单详情归一化查询
class OrdersDetailNormalizedQuery(BaseModel):
    order_id: Optional[str] = None
    order_reference: Optional[str] = None

# 批量订单用量查询
class OrdersConsumptionBatchQuery(BaseModel):
    order_references: Optional[List[str]] = None
    order_ids: Optional[List[str]] = None

# 订单列表归一化查询
class OrdersListNormalizedQuery(BaseModel):
    page_number: int
    page_size: Literal[10, 25, 50, 100]
    bundle_code: Optional[str] = None
    order_id: Optional[str] = None
    order_reference: Optional[str] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    iccid: Optional[str] = None

class OrdersListWithUsageQuery(BaseModel):
    page_number: int
    page_size: Literal[10, 25, 50, 100]
    bundle_code: Optional[str] = None
    order_id: Optional[str] = None
    order_reference: Optional[str] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    iccid: Optional[str] = None

# 扁平运营商列表查询
class BundleNetworksFlatQuery(BaseModel):
    bundle_code: str
    country_code: Optional[str] = None
# 通过 bundle_code 获取套餐详情
class BundleCodeQuery(BaseModel):
    bundle_code: str
# ===== 套餐指派（上游 alias 风格） =====
class BundleAssignBody(BaseModel):
    bundle_code: str
    order_reference: str = Field(..., max_length=30)
    name: Optional[str] = None
    email: Optional[str] = None

class BundleAssignResultDTO(BaseModel):
    orderId: str
    iccid: str


# ===== i18n 管理 DTO（Upsert） =====
class I18nCountryUpsertItem(BaseModel):
    iso2_code: Optional[str] = None
    iso3_code: Optional[str] = None
    lang_code: str
    name: str
    logo: Optional[str] = None

class I18nCountryUpsertBody(BaseModel):
    items: List[I18nCountryUpsertItem]


class I18nRegionUpsertItem(BaseModel):
    region_code: str
    lang_code: str
    name: str

class I18nRegionUpsertBody(BaseModel):
    items: List[I18nRegionUpsertItem]


class I18nBundleUpsertItem(BaseModel):
    bundle_code: str
    lang_code: str
    marketing_name: Optional[str] = None
    name: Optional[str] = None
    description: Optional[str] = None

class I18nBundleUpsertBody(BaseModel):
    items: List[I18nBundleUpsertItem]
