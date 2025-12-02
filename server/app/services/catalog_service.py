from __future__ import annotations
from typing import List, Optional
import os
import time

from ..models.dto import (
    BundleDTO,
    CountryDTO,
    RegionDTO,
    SearchResultDTO,
    AliasCountryDTO,
    AliasCountriesDTO,
    AliasRegionDTO,
    AliasRegionsDTO,
)
from ..provider.client import ProviderClient
from ..db import SessionLocal
from ..models.orm import I18nCountryName, I18nRegionName


class CatalogService:
    def __init__(self):
        self.provider = ProviderClient()
        # 列表缓存 TTL（秒），默认 3600，可通过环境变量覆盖
        self._list_ttl_seconds: int = int(os.getenv("CATALOG_LIST_TTL_SECONDS", "3600"))
        # 国家列表缓存
        self._countries_cache: Optional[List[CountryDTO]] = None
        self._countries_expires_at: Optional[float] = None
        # 上游 alias 风格国家列表缓存
        self._countries_alias_cache: Optional[AliasCountriesDTO] = None
        self._countries_alias_expires_at: Optional[float] = None
        # 地区列表缓存
        self._regions_cache: Optional[List[RegionDTO]] = None
        self._regions_expires_at: Optional[float] = None
        self._regions_alias_cache: Optional[AliasRegionsDTO] = None
        self._regions_alias_expires_at: Optional[float] = None
        # 套餐列表缓存（按筛选参数维度），减少上游压力
        self._bundle_list_cache: dict[str, dict] = {}
        self._bundle_list_expires_at: dict[str, float] = {}
        # 套餐网络缓存（v2 聚合）
        self._bundle_networks_v2_cache: dict[str, dict] = {}
        self._bundle_networks_v2_expires_at: dict[str, float] = {}

    def _now(self) -> float:
        return time.time()

    def get_countries(self, request_id: Optional[str] = None) -> List[CountryDTO]:
        # 命中缓存且未过期则直接返回
        if (
            self._countries_cache is not None
            and self._countries_expires_at is not None
            and self._now() < self._countries_expires_at
        ):
            return self._countries_cache

        # 拉取上游并转换为 DTO
        items: List[CountryDTO] = []
        try:
            countries = self.provider.get_countries(request_id=request_id)
            items = [CountryDTO(code=c.get("code") or str(c.get("iso2_code")), name=c.get("name") or str(c.get("country_name"))) for c in countries if (c.get("code") or c.get("iso2_code")) and (c.get("name") or c.get("country_name"))]
        except Exception:
            items = []
        if not items:
            try:
                db = SessionLocal()
                rows = db.query(I18nCountryName).filter(I18nCountryName.lang_code == "en").all()
                items = [CountryDTO(code=row.country_code, name=row.name) for row in rows]
            except Exception:
                items = []
        # 写入缓存
        self._countries_cache = items
        self._countries_expires_at = self._now() + self._list_ttl_seconds
        return items

    def get_countries_alias(self, request_id: Optional[str] = None) -> AliasCountriesDTO:
        # 命中缓存且未过期则直接返回
        if (
            self._countries_alias_cache is not None
            and self._countries_alias_expires_at is not None
            and self._now() < self._countries_alias_expires_at
        ):
            return self._countries_alias_cache

        # 拉取上游并转换为 alias 风格 DTO
        countries = self.provider.get_countries(request_id=request_id)
        alias_items: List[AliasCountryDTO] = []
        for c in countries:
            iso2 = c.get("iso2_code") or c.get("code")
            iso3 = c.get("iso3_code")
            name = c.get("country_name") or c.get("name")
            if not (iso2 and iso3 and name):
                # 严格按文档要求，缺失任一字段则跳过
                continue
            alias_items.append(AliasCountryDTO(iso2_code=str(iso2), iso3_code=str(iso3), country_name=str(name)))
        result = AliasCountriesDTO(countries=alias_items, countries_count=len(alias_items))
        # 写入缓存
        self._countries_alias_cache = result
        self._countries_alias_expires_at = self._now() + self._list_ttl_seconds
        return result

    def get_regions(self, request_id: Optional[str] = None) -> List[RegionDTO]:
        # 命中缓存且未过期则直接返回
        if (
            self._regions_cache is not None
            and self._regions_expires_at is not None
            and self._now() < self._regions_expires_at
        ):
            return self._regions_cache

        # 拉取上游并转换为 DTO
        items: List[RegionDTO] = []
        try:
            regions = self.provider.get_regions(request_id=request_id)
            items = [RegionDTO(code=str(r.get("code") or r.get("region_code")), name=str(r.get("name") or r.get("region_name"))) for r in regions if (r.get("code") or r.get("region_code")) and (r.get("name") or r.get("region_name"))]
        except Exception:
            items = []
        if not items:
            try:
                db = SessionLocal()
                rows = db.query(I18nRegionName).filter(I18nRegionName.lang_code == "en").all()
                items = [RegionDTO(code=row.region_code, name=row.name) for row in rows]
            except Exception:
                items = []
        # 写入缓存
        self._regions_cache = items
        self._regions_expires_at = self._now() + self._list_ttl_seconds
        return items

    def get_regions_alias(self, request_id: Optional[str] = None) -> AliasRegionsDTO:
        if (
            self._regions_alias_cache is not None
            and self._regions_alias_expires_at is not None
            and self._now() < self._regions_alias_expires_at
        ):
            return self._regions_alias_cache

        regions = self.provider.get_regions(request_id=request_id)
        alias_items: List[AliasRegionDTO] = []
        for r in regions:
            code = r.get("region_code") or r.get("code")
            name = r.get("region_name") or r.get("name")
            if not (code and name):
                continue
            alias_items.append(AliasRegionDTO(region_code=str(code), region_name=str(name)))
        result = AliasRegionsDTO(regions=alias_items, regions_count=len(alias_items))
        self._regions_alias_cache = result
        self._regions_alias_expires_at = self._now() + self._list_ttl_seconds
        return result

    def get_bundles(self, country: Optional[str] = None, popular: bool = False) -> List[BundleDTO]:
        bundles = self.provider.get_bundles(country_code=country, popular=popular)
        return [
            BundleDTO(
                id=b["id"],
                name=b["name"],
                countryCode=b["country_code"],
                price=float(b["price"]),
                currency=b.get("currency", "GBP"),
                dataAmount=b["data_amount"],
                validityDays=int(b["validity_days"]),
                description=b.get("description"),
                supportedNetworks=b.get("supported_networks"),
                hotspotSupported=b.get("hotspot_supported"),
                coverageNote=b.get("coverage_note"),
                termsUrl=b.get("terms_url"),
            )
            for b in bundles
        ]

    def get_bundle(self, bundle_id: str) -> Optional[BundleDTO]:
        b = self.provider.get_bundle(bundle_id)
        if not b:
            return None
        return BundleDTO(
            id=b["id"],
            name=b["name"],
            countryCode=b["country_code"],
            price=float(b["price"]),
            currency=b.get("currency", "GBP"),
            dataAmount=b["data_amount"],
            validityDays=int(b["validity_days"]),
            description=b.get("description"),
            supportedNetworks=b.get("supported_networks"),
            hotspotSupported=b.get("hotspot_supported"),
            coverageNote=b.get("coverage_note"),
            termsUrl=b.get("terms_url"),
        )

    def get_bundle_networks(self, bundle_id: str) -> List[str]:
        return self.provider.get_bundle_networks(bundle_id)

    def get_bundle_networks_v2(
        self,
        bundle_code: str,
        country_code: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> dict:
        key = "|".join([
            "bundle:networks:v2",
            str(bundle_code),
            str(country_code or "-")
        ])
        now = self._now()
        if key in self._bundle_networks_v2_cache and (self._bundle_networks_v2_expires_at.get(key) or 0) > now:
            data = self._bundle_networks_v2_cache[key]
        else:
            data = self.provider.get_bundle_networks_v2(
                bundle_code=bundle_code,
                country_code=country_code,
                request_id=request_id,
            )
            self._bundle_networks_v2_cache[key] = data
            self._bundle_networks_v2_expires_at[key] = now + self._list_ttl_seconds
        networks = data.get("networks") or []
        count = data.get("networks_count")
        try:
            networks_count = int(float(str(count))) if count is not None else len(networks)
        except Exception:
            networks_count = len(networks)
        return {"networks": networks, "networks_count": int(networks_count)}

    def get_bundle_operators_flat(
        self,
        bundle_code: str,
        country_code: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> dict:
        data = self.get_bundle_networks_v2(bundle_code=bundle_code, country_code=country_code, request_id=request_id)
        networks = data.get("networks") or []
        if country_code:
            cc = str(country_code).upper()
            for item in networks:
                if str(item.get("country_code") or "").upper() == cc:
                    ops = [str(x) for x in (item.get("operator_list") or [])]
                    return {"operators": ops, "operators_count": len(ops)}
            return {"operators": [], "operators_count": 0}
        ops_set: set[str] = set()
        for item in networks:
            for op in (item.get("operator_list") or []):
                ops_set.add(str(op))
        ops = sorted(list(ops_set))
        return {"operators": ops, "operators_count": len(ops)}

    def bundle_list(
        self,
        page_number: int,
        page_size: int,
        country_code: Optional[str] = None,
        region_code: Optional[str] = None,
        bundle_category: Optional[str] = None,
        sort_by: Optional[str] = None,
        bundle_code: Optional[str] = None,
        q: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> dict:
        # 构造缓存 key（空值统一为 "-"，避免 None/"" 混用）
        def _n(x):
            return str(x).strip() if (x is not None and str(x).strip() != "") else "-"
        key = "|".join([
            "bundles:list:v1",
            str(page_number),
            str(page_size),
            _n(country_code),
            _n(region_code),
            _n(bundle_category),
            _n(sort_by),
            _n(bundle_code),
            _n(q),
        ])
        now = self._now()
        if key in self._bundle_list_cache and (self._bundle_list_expires_at.get(key) or 0) > now:
            bundles_data = self._bundle_list_cache[key]
        else:
            bundles_data = self.provider.get_bundle_list(
                page_number=page_number,
                page_size=page_size,
                country_code=country_code,
                region_code=region_code,
                bundle_category=bundle_category,
                sort_by=sort_by,
                bundle_code=bundle_code,
                request_id=request_id,
            )
            self._bundle_list_cache[key] = bundles_data
            self._bundle_list_expires_at[key] = now + self._list_ttl_seconds
        bundles = bundles_data.get("bundles") or []
        if q:
            ql = str(q).strip().lower()
            def _match(*texts):
                for t in texts:
                    if isinstance(t, str) and ql in t.lower():
                        return True
                return False
            filtered = []
            for b in bundles:
                name = str(b.get("bundle_name") or b.get("bundle_marketing_name") or "")
                desc = str(b.get("description") or "")
                cc = str((b.get("country_code") or [""])[0])
                data_amt = str(b.get("gprs_limit") or "") + " " + str(b.get("data_unit") or "")
                if _match(name, desc, cc, data_amt):
                    filtered.append(b)
            bundles = filtered
        return {"bundles": bundles, "bundles_count": int(bundles_data.get("bundles_count", 0))}

    def get_bundle_by_code(self, bundle_code: str, request_id: Optional[str] = None) -> Optional[BundleDTO]:
        data = self.provider.get_bundle_list(
            page_number=1,
            page_size=100,
            country_code=None,
            region_code=None,
            bundle_category=None,
            sort_by=None,
            bundle_code=bundle_code,
            request_id=request_id,
        )
        bundles = data.get("bundles") or []
        if not bundles:
            return None
        b = bundles[0]
        try:
            price = float(b.get("bundle_price_final", b.get("reseller_retail_price", 0.0)))
        except Exception:
            price = 0.0
        try:
            validity = int(float(str(b.get("validity", 0))))
        except Exception:
            validity = 0
        return BundleDTO(
            id=str(b.get("bundle_code")),
            name=str(b.get("bundle_name") or b.get("bundle_marketing_name") or ""),
            countryCode=(b.get("country_code") or [""])[0] if (b.get("country_code") or []) else "",
            price=price,
            currency=str(b.get("currency") or "GBP"),
            dataAmount=(str(b.get("gprs_limit") or "") + " " + str(b.get("data_unit") or "")).strip(),
            validityDays=validity,
            description=str(b.get("bundle_marketing_name") or ""),
            supportedNetworks=None,
            hotspotSupported=None,
            coverageNote=None,
            termsUrl=None,
        )

    # ===== 搜索聚合 =====
    def search(
        self,
        q: str,
        include: Optional[List[str]] = None,
        limit: int = 20,
        dedupe: bool = False,
        lang: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> List[SearchResultDTO]:
        term = (q or "").strip()
        if not term:
            return []
        q_lower = term.lower()
        kinds = [k.strip().lower() for k in (include or ["country", "region", "bundle"])]

        results: List[SearchResultDTO] = []

        def _norm(s: Optional[str]) -> str:
            x = str(s or "").strip().lower()
            x = x.replace("＋", "+")
            x = x.replace("plus", "+")
            x = x.replace(" ", " ")
            x = x.replace("+", "")
            return x

        def build_tokens(term: str) -> List[str]:
            base = _norm(term)
            toks: List[str] = [base]
            try:
                from app.i18n import MARKETING_CANONICAL_MAP, _REGION_ALIASES, _TERRITORY_ALIASES  # type: ignore
                canon = MARKETING_CANONICAL_MAP.get(base)
                if canon:
                    toks.append(_norm(canon))
                    rc = _REGION_ALIASES.get(_norm(canon))
                    if rc:
                        toks.append(_norm(rc))
                ali = _TERRITORY_ALIASES.get(base)
                if ali:
                    toks.append(_norm(ali))
                if lang:
                    try:
                        from babel import Locale  # type: ignore
                        loc = Locale.parse(lang.replace('-', '_'))
                        for iso2, name in (loc.territories or {}).items():
                            if _norm(name) == base:
                                toks.append(_norm(iso2))
                                break
                    except Exception:
                        pass
                add_iso3: List[str] = []
                try:
                    from app.db import SessionLocal, I18nCountryName  # type: ignore
                    db = SessionLocal()
                    try:
                        for t in toks:
                            if len(t) == 2:
                                r = db.query(I18nCountryName).filter(I18nCountryName.iso2_code == t.upper()).first()
                                if r and r.iso3_code:
                                    add_iso3.append(_norm(r.iso3_code))
                    finally:
                        db.close()
                except Exception:
                    pass
                toks.extend(add_iso3)
            except Exception:
                pass
            return list(dict.fromkeys(toks))

        tokens = build_tokens(term)

        def match_tokens(*texts: Optional[str]) -> bool:
            for t in texts:
                s = _norm(t)
                for tok in tokens:
                    if tok and tok in s:
                        return True
            return False

        # Countries
        if "country" in kinds:
            for c in self.get_countries(request_id=request_id):
                if match_tokens(c.name, c.code):
                    results.append(
                        SearchResultDTO(
                            kind="country",
                            id=c.code,
                            title=c.name,
                            subtitle=None,
                            countryCode=c.code,
                        )
                    )
                    if len(results) >= limit:
                        return results[:limit]

        # Regions
        if "region" in kinds:
            for r in self.get_regions(request_id=request_id):
                if match_tokens(r.name, r.code):
                    results.append(
                        SearchResultDTO(
                            kind="region",
                            id=r.code,
                            title=r.name,
                            subtitle=None,
                            regionCode=r.code,
                        )
                    )
                    if len(results) >= limit:
                        return results[:limit]

        # Bundles（轻量搜索：首屏分页 + 本地筛选，使用上游 alias 字段）
        if "bundle" in kinds:
            try:
                page_size = max(10, min(100, limit * 2))
                bundles_page = self.provider.get_bundle_list(
                    page_number=1,
                    page_size=page_size,
                    country_code=None,
                    region_code=None,
                    bundle_category=None,
                    sort_by="bundle_name",
                    request_id=request_id,
                )
                for b in (bundles_page.get("bundles") or []):
                    name = str(b.get("bundle_name") or b.get("bundle_marketing_name") or "")
                    desc = str(b.get("bundle_marketing_name") or "")
                    cc_list = list(b.get("country_code") or [])
                    cc = str(cc_list[0]) if cc_list else ""
                    data_amt = (str(b.get("gprs_limit") or "") + " " + str(b.get("data_unit") or "")).strip()
                    valid = 0
                    try:
                        valid = int(float(str(b.get("validity") or 0)))
                    except Exception:
                        valid = 0
                    cnames = " ".join([str(x) for x in (b.get("country_name") or [])])
                    if match_tokens(name, desc, cc, cnames, data_amt):
                        results.append(
                            SearchResultDTO(
                                kind="bundle",
                                id=str(b.get("bundle_code") or name),
                                title=name,
                                subtitle=f"{data_amt} · {valid}d",
                                bundleCode=str(b.get("bundle_code") or ""),
                                countryCode=str(cc),
                            )
                        )
                        if len(results) >= limit:
                            return results[:limit]
            except Exception:
                pass

        if dedupe:
            seen: set[tuple[str, str]] = set()
            deduped: List[SearchResultDTO] = []
            for r in results:
                key = (r.kind, r.id)
                if key in seen:
                    continue
                seen.add(key)
                deduped.append(r)
            results = deduped
        return results[:limit]
