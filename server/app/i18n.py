from __future__ import annotations
from typing import Optional, List
from .db import SessionLocal
from .models.orm import I18nCountryName, I18nRegionName, I18nBundleName
import re

LANG_WHITELIST: set[str] = {
    "en","zh-Hans","zh-Hant","ja","ko","th","id","es","pt","ms","vi","ar"
}

def canonical_language(raw: Optional[str]) -> str:
    s = (raw or "").strip().lower()
    if s.startswith("zh-hans") or s.startswith("zh-cn"): return "zh-Hans"
    if s.startswith("zh-hant") or s.startswith("zh-tw") or s.startswith("zh-hk") or s.startswith("zh-mo"): return "zh-Hant"
    if s.startswith("en"): return "en"
    if s.startswith("ja"): return "ja"
    if s.startswith("ko"): return "ko"
    if s.startswith("th"): return "th"
    if s.startswith("id"): return "id"
    if s.startswith("es"): return "es"
    if s.startswith("pt"): return "pt"
    if s.startswith("ms"): return "ms"
    if s.startswith("vi"): return "vi"
    if s.startswith("ar"): return "ar"
    return raw or "en"

def resolve_language(
    lang_param: Optional[str],
    accept_language: Optional[str],
    x_language: Optional[str],
    user_language: Optional[str],
) -> str:
    for cand in [lang_param, x_language, accept_language, user_language]:
        if cand:
            c = canonical_language(cand)
            if c in LANG_WHITELIST:
                return c
    return "en"

COUNTRY_NAMES: dict[str, dict[str, str]] = {
    "en": {
        "HK": "Hong Kong", "HKG": "Hong Kong",
        "CN": "China Mainland", "CHN": "China Mainland",
        "GB": "United Kingdom", "GBR": "United Kingdom",
        "FRA": "France", "DEU": "Germany", "ESP": "Spain", "ITA": "Italy", "TUR": "Turkey",
    },
    "zh-Hans": {
        "HK": "中国香港", "HKG": "中国香港",
        "CN": "中国大陆", "CHN": "中国大陆",
        "GB": "英国", "GBR": "英国",
        "FRA": "法国", "DEU": "德国", "ESP": "西班牙", "ITA": "意大利", "TUR": "土耳其",
    },
    "zh-Hant": {
        "HK": "中國香港", "HKG": "中國香港",
        "CN": "中國大陸", "CHN": "中國大陸",
        "GB": "英國", "GBR": "英國",
        "FRA": "法國", "DEU": "德國", "ESP": "西班牙", "ITA": "義大利", "TUR": "土耳其",
    },
    "ja": {"HK": "香港", "HKG": "香港", "CN": "中国本土", "CHN": "中国本土", "GB": "イギリス", "GBR": "イギリス", "FRA": "フランス", "DEU": "ドイツ", "ESP": "スペイン", "ITA": "イタリア", "TUR": "トルコ"},
    "id": {
        "HK": "Hong Kong", "HKG": "Hong Kong",
        "CN": "Tiongkok Daratan", "CHN": "Tiongkok Daratan",
        "GB": "Inggris", "GBR": "Inggris",
        "FRA": "Prancis", "DEU": "Jerman", "ESP": "Spanyol", "ITA": "Italia", "TUR": "Turki",
    },
    "ms": {
        "HK": "Hong Kong", "HKG": "Hong Kong",
        "CN": "China Daratan", "CHN": "China Daratan",
        "GB": "United Kingdom", "GBR": "United Kingdom",
        "FRA": "Perancis", "DEU": "Jerman", "ESP": "Sepanyol", "ITA": "Itali", "TUR": "Turki",
    },
}

REGION_NAMES: dict[str, dict[str, str]] = {
    "en": {"af": "Africa", "as": "Asia", "eu": "Europe", "me": "Middle East", "na": "North America", "sa": "South America"},
    "zh-Hans": {"af": "非洲", "as": "亚洲", "eu": "欧洲", "me": "中东", "na": "北美", "sa": "南美"},
    "zh-Hant": {"af": "非洲", "as": "亞洲", "eu": "歐洲", "me": "中東", "na": "北美", "sa": "南美"},
    "ja": {"af": "アフリカ", "as": "アジア", "eu": "ヨーロッパ", "me": "中東", "na": "北アメリカ", "sa": "南アメリカ"},
    "ms": {"af": "Afrika", "as": "Asia", "eu": "Eropah", "me": "Timur Tengah", "na": "Amerika Utara", "sa": "Amerika Selatan"},
    "id": {"af": "Afrika", "as": "Asia", "eu": "Eropa", "me": "Timur Tengah", "na": "Amerika Utara", "sa": "Amerika Selatan"},
}

BUNDLE_MARKETING_NAMES: dict[str, dict[str, str]] = {
    "en": {"Hong Kong": "Hong Kong", "China Mainland": "China Mainland", "Europe": "Europe", "North America": "North America", "South America": "South America", "Africa": "Africa", "Asia": "Asia", "Middle East": "Middle East", "Global": "Global", "Cruise": "Cruise"},
    "zh-Hans": {"Hong Kong": "香港", "China Mainland": "中国大陆", "Europe": "欧洲", "North America": "北美洲", "South America": "南美洲", "Africa": "非洲", "Asia": "亚洲", "Middle East": "中东", "Global": "全球", "Cruise": "邮轮"},
    "zh-Hant": {"Hong Kong": "香港", "China Mainland": "中國大陸", "Europe": "歐洲", "North America": "北美洲", "South America": "南美洲", "Africa": "非洲", "Asia": "亞洲", "Middle East": "中東", "Global": "全球", "Cruise": "郵輪"},
    "ja": {"Hong Kong": "香港", "China Mainland": "中国本土", "Europe": "ヨーロッパ", "North America": "北アメリカ", "South America": "南アメリカ", "Africa": "アフリカ", "Asia": "アジア", "Middle East": "中東", "Global": "グローバル", "Cruise": "クルーズ"},
    "ko": {"Hong Kong": "홍콩", "China Mainland": "중국 본토", "Europe": "유럽", "North America": "북아메리카", "South America": "남아메리카", "Africa": "아프리카", "Asia": "아시아", "Middle East": "중동", "Global": "글로벌", "Cruise": "크루즈"},
    "th": {"Hong Kong": "ฮ่องกง", "China Mainland": "จีนแผ่นดินใหญ่", "Europe": "ยุโรป", "North America": "อเมริกาเหนือ", "South America": "อเมริกาใต้", "Africa": "แอฟริกา", "Asia": "เอเชีย", "Middle East": "ตะวันออกกลาง", "Global": "ทั่วโลก", "Cruise": "เรือสำราญ"},
    "id": {"Hong Kong": "Hong Kong", "China Mainland": "Tiongkok Daratan", "Europe": "Eropa", "North America": "Amerika Utara", "South America": "Amerika Selatan", "Africa": "Afrika", "Asia": "Asia", "Middle East": "Timur Tengah", "Global": "Global", "Cruise": "Kapal Pesiar"},
    "ms": {"Hong Kong": "Hong Kong", "China Mainland": "China Daratan", "Europe": "Eropah", "North America": "Amerika Utara", "South America": "Amerika Selatan", "Africa": "Afrika", "Asia": "Asia", "Middle East": "Timur Tengah", "Global": "Global", "Cruise": "Kapal Persiaran"},
    "es": {"Hong Kong": "Hong Kong", "China Mainland": "China Continental", "Europe": "Europa", "North America": "América del Norte", "South America": "Sudamérica", "Africa": "África", "Asia": "Asia", "Middle East": "Medio Oriente", "Global": "Global", "Cruise": "Crucero"},
    "pt": {"Hong Kong": "Hong Kong", "China Mainland": "China Continental", "Europe": "Europa", "North America": "América do Norte", "South America": "América do Sul", "Africa": "África", "Asia": "Ásia", "Middle East": "Oriente Médio", "Global": "Global", "Cruise": "Cruzeiro"},
    "vi": {"Hong Kong": "Hồng Kông", "China Mainland": "Trung Quốc đại lục", "Europe": "Châu Âu", "North America": "Bắc Mỹ", "South America": "Nam Mỹ", "Africa": "Châu Phi", "Asia": "Châu Á", "Middle East": "Trung Đông", "Global": "Toàn cầu", "Cruise": "Du thuyền"},
    "ar": {"Hong Kong": "هونغ كونغ", "China Mainland": "بر الصين الرئيسي", "Europe": "أوروبا", "North America": "أمريكا الشمالية", "South America": "أمريكا الجنوبية", "Africa": "أفريقيا", "Asia": "آسيا", "Middle East": "الشرق الأوسط", "Global": "عالمي", "Cruise": "رحلة بحرية"},
}

# Build a canonical index that maps any localized marketing name back to the
# English canonical key. This allows translate_marketing to recognize inputs
# provided in non-English and re-localize correctly per requested language.
def _norm(s: str) -> str:
    x = s.strip().lower()
    x = x.replace("＋", "+")
    x = x.replace("plus", "+")
    x = x.replace("  ", " ")
    return x

MARKETING_CANONICAL_MAP: dict[str, str] = {}
try:
    en_map = BUNDLE_MARKETING_NAMES.get("en", {})
    # For every language, map each translation back to English canonical key
    for canon, en_val in en_map.items():
        # English form
        MARKETING_CANONICAL_MAP[_norm(en_val)] = canon
        MARKETING_CANONICAL_MAP[_norm(canon)] = canon
    for lang_key, trans_map in BUNDLE_MARKETING_NAMES.items():
        for canon, val in trans_map.items():
            MARKETING_CANONICAL_MAP[_norm(val)] = canon
except Exception:
    # Safe fallback: leave map possibly empty
    pass

_REGION_ALIASES: dict[str, str] = {
    "europe": "eu",
    "asia": "as",
    "middle east": "me",
    "global": "global",
}

_TERRITORY_ALIASES: dict[str, str] = {
    "turkiye": "Turkey",
    "튀르키예": "Turkey",
    "터키": "Turkey",
    "터키어": "Turkey",
    "turki": "Turkey",
    "emiriah arab bersatu": "United Arab Emirates",
    "jerman": "Germany",
    "perancis": "France",
    "sepanyol": "Spain",
    "itali": "Italy",
    "uni emirat arab": "United Arab Emirates",
    "uni emirat arab bersatu": "United Arab Emirates",
    "inggris": "United Kingdom",
    "britania raya": "United Kingdom",
    "prancis": "France",
    "spanyol": "Spain",
    "italia": "Italy",
    "czech republic": "Czechia",
    "uae": "United Arab Emirates",
    "u.a.e": "United Arab Emirates",
    "uk": "United Kingdom",
    "gb": "United Kingdom",
}

def translate_country(code: str, name: Optional[str], lang: str) -> str:
    c = (code or "").upper()
    if not c:
        return name or ""
    # DB lookup first
    try:
        db = SessionLocal()
        try:
            rows = db.query(I18nCountryName).filter(I18nCountryName.lang_code == lang).filter((I18nCountryName.iso2_code == c) | (I18nCountryName.iso3_code == c)).all()
            if rows:
                row = next((r for r in rows if (r.iso2_code or "").upper() == c), rows[0])
                val = row.name
                try:
                    if lang != "en" and val and re.fullmatch(r"[\w\s\-\(\)]+", val):
                        from babel import Locale  # type: ignore
                        loc = Locale.parse(lang.replace('-', '_'))
                        iso2 = (row.iso2_code or row.iso3_code or "").upper()
                        if len(iso2) == 3:
                            iso2 = None
                        t = loc.territories.get(iso2 or c)
                        if t:
                            return t
                except Exception:
                    pass
                # Fallback to static mapping when DB contains non-localized value or Babel is unavailable
                try:
                    iso2 = (row.iso2_code or "").upper()
                    iso3 = (row.iso3_code or "").upper()
                    m = COUNTRY_NAMES.get(lang) or {}
                    alt = m.get(c) or m.get(iso2) or m.get(iso3)
                    if alt:
                        return alt
                except Exception:
                    pass
                return val
        finally:
            db.close()
    except Exception:
        pass
    # Fallback via Babel CLDR when possible (iso2 only)
    try:
        from babel import Locale  # type: ignore
        loc = Locale.parse(lang.replace('-', '_'))
        iso2 = None
        if len(c) == 2:
            iso2 = c
        elif len(c) == 3:
            db2 = SessionLocal()
            try:
                r = db2.query(I18nCountryName).filter(I18nCountryName.iso3_code == c).first()
                if r and r.iso2_code:
                    iso2 = (r.iso2_code or "").upper()
            finally:
                db2.close()
        if iso2:
            t = loc.territories.get(iso2)
            if t:
                return t
    except Exception:
        pass
    # Fallback to static mapping then given name/code
    m = COUNTRY_NAMES.get(lang) or COUNTRY_NAMES.get("en", {})
    return m.get(c, name or c)

def translate_region(code: Optional[str], name: Optional[str], lang: str) -> str:
    key = str(code or "").lower()
    if not key:
        return name or ""
    try:
        db = SessionLocal()
        try:
            row = db.query(I18nRegionName).filter(I18nRegionName.lang_code == lang, I18nRegionName.region_code == key).first()
            if row:
                return row.name
            row2 = db.query(I18nRegionName).filter(I18nRegionName.lang_code == lang, I18nRegionName.region_code == "default").first()
            if row2:
                return row2.name
        finally:
            db.close()
    except Exception:
        pass
    m = REGION_NAMES.get(lang) or REGION_NAMES.get("en", {})
    return m.get(key, name or key)

def translate_marketing(name: Optional[str], lang: str, bundle_code: Optional[str] = None) -> str:
    base = (name or "").strip()
    # Prefer DB by bundle_code when available
    code = (bundle_code or "").strip()
    if code:
        try:
            db = SessionLocal()
            try:
                row = db.query(I18nBundleName).filter(I18nBundleName.lang_code == lang, I18nBundleName.bundle_code == code).first()
                if row and (row.marketing_name or row.name):
                    return (row.marketing_name or row.name)
            finally:
                db.close()
        except Exception:
            pass
    # Attempt canonical mapping across all languages to derive the English key
    # Strip trailing data amount / days segments to isolate the place/region name
    import re as _re
    lead = base
    try:
        lead = (_re.split(r"\s*\d", base, maxsplit=1)[0] or base).strip()
    except Exception:
        lead = base
    base_norm = lead.strip().lower().replace("+", "").replace("plus", "").strip()
    canon = MARKETING_CANONICAL_MAP.get(base_norm)
    if canon:
        translated = (BUNDLE_MARKETING_NAMES.get(lang, {}).get(canon)
                      or BUNDLE_MARKETING_NAMES.get("en", {}).get(canon)
                      or canon)
        # Preserve trailing '+' if present in original
        if "+" in (name or ""):
            return translated + "+"
        return translated
    # Direct language-specific table lookup using original base as key
    m = BUNDLE_MARKETING_NAMES.get(lang) or BUNDLE_MARKETING_NAMES.get("en", {})
    val = m.get(lead) or m.get(base)
    if val:
        return val
    try:
        from babel import Locale  # type: ignore
        loc_en = Locale.parse("en")
        loc_t = Locale.parse(lang.replace('-', '_'))
        base_norm = lead.strip().lower().replace("+", "").replace("plus", "").strip()
        if base_norm in _REGION_ALIASES:
            rc = _REGION_ALIASES[base_norm]
            return translate_region(rc, base, lang)
        ali = _TERRITORY_ALIASES.get(base_norm)
        if ali:
            base_norm = ali.strip().lower()
        target = None
        for iso2, en_name in (loc_en.territories or {}).items():
            if str(en_name).strip().lower() == base_norm:
                target = (loc_t.territories or {}).get(iso2)
                break
        if target:
            if "+" in base:
                return target + "+"
            return target
    except Exception:
        pass
    # Fallback via DB English name -> ISO code -> translate_country when Babel not available
    try:
        canon_en = (_TERRITORY_ALIASES.get(base_norm) or base_norm).strip()
        from app.db import SessionLocal, I18nCountryName  # type: ignore
        db = SessionLocal()
        try:
            row = db.query(I18nCountryName).filter(I18nCountryName.lang_code == "en", I18nCountryName.name == canon_en).first()
            if not row:
                row = db.query(I18nCountryName).filter(I18nCountryName.lang_code == "en", I18nCountryName.name == canon_en.title()).first()
            if row:
                code = (row.iso2_code or row.iso3_code or "")
                t = translate_country(code, row.name, lang)
                if t:
                    if "+" in base:
                        return t + "+"
                    return t
        finally:
            db.close()
    except Exception:
        pass
    return base

DAYS_WORD: dict[str, str] = {
    "en": "Days",
    "zh-Hans": "天",
    "zh-Hant": "天",
    "ja": "日",
    "ko": "일",
    "th": "วัน",
    "id": "Hari",
    "es": "días",
    "pt": "dias",
    "ms": "Hari",
    "vi": "ngày",
    "ar": "أيام",
}

UNLIMITED_WORD: dict[str, str] = {
    "en": "Unlimited",
    "zh-Hans": "不限量",
    "zh-Hant": "不限量",
    "ja": "無制限",
    "ko": "무제한",
    "th": "ไม่จำกัด",
    "id": "Tak Terbatas",
    "es": "Ilimitado",
    "pt": "Ilimitado",
    "ms": "Tanpa Had",
    "vi": "Không giới hạn",
    "ar": "غير محدود",
}

PLAN_STATUS_MAP: dict[str, dict[str, str]] = {
    "en": {
        "not_started": "Plan Not Started",
        "pending": "Pending",
        "active": "Active",
        "expired": "Expired",
        "suspended": "Suspended",
        "successful": "Successful",
        "failed": "Failed",
    },
    "zh-Hans": {
        "not_started": "套餐未开始",
        "pending": "待处理",
        "active": "已激活",
        "expired": "已过期",
        "suspended": "已暂停",
        "successful": "成功",
        "failed": "失败",
    },
    "zh-Hant": {
        "not_started": "套餐未開始",
        "pending": "待處理",
        "active": "已啟用",
        "expired": "已過期",
        "suspended": "已暫停",
        "successful": "成功",
        "failed": "失敗",
    },
    "ja": {
        "not_started": "未開始",
        "pending": "保留",
        "active": "有効",
        "expired": "期限切れ",
        "suspended": "一時停止",
        "successful": "成功",
        "failed": "失敗",
    },
}

def translate_plan_status(status: Optional[str], lang: str) -> str:
    s = (status or "").strip().lower()
    key = ""
    if not s:
        return status or ""
    if "not" in s and "start" in s:
        key = "not_started"
    elif "pend" in s:
        key = "pending"
    elif any(k in s for k in ("active", "success")):
        key = "successful" if ("success" in s) else "active"
    elif "expire" in s:
        key = "expired"
    elif "suspend" in s:
        key = "suspended"
    elif "fail" in s:
        key = "failed"
    else:
        key = s.replace(" ", "_")
    m = PLAN_STATUS_MAP.get(lang) or PLAN_STATUS_MAP.get("en", {})
    return m.get(key, status or key)

def translate_bundle_name(
    name: Optional[str],
    lang: str,
    bundle_code: Optional[str] = None,
    amount: Optional[float] = None,
    unit: Optional[str] = None,
    validity_days: Optional[int] = None,
    marketing_name: Optional[str] = None,
    unlimited: Optional[bool] = None,
) -> str:
    code = (bundle_code or "").strip()
    if code:
        try:
            db = SessionLocal()
            try:
                row = db.query(I18nBundleName).filter(I18nBundleName.lang_code == lang, I18nBundleName.bundle_code == code).first()
                if row and row.name:
                    return row.name
            finally:
                db.close()
        except Exception:
            pass
    mkt = translate_marketing(marketing_name or name, lang, bundle_code)
    if unlimited and validity_days is not None:
        dword = DAYS_WORD.get(lang) or DAYS_WORD.get("en", "Days")
        uword = UNLIMITED_WORD.get(lang) or UNLIMITED_WORD.get("en", "Unlimited")
        return f"{mkt} {uword} {int(validity_days)} {dword}"
    if amount is not None and validity_days is not None and unit:
        try:
            amt = int(float(str(amount)))
            amt_str = str(amt)
        except Exception:
            amt_str = str(amount)
        dword = DAYS_WORD.get(lang) or DAYS_WORD.get("en", "Days")
        mkts = (mkt or "")
        # Only treat as fully localized if the target language's day word appears.
        # This avoids returning a Chinese string when English is requested.
        if (amt_str in mkts) and (str(validity_days) in mkts) and (dword in mkts):
            return mkt
        if lang.startswith("zh-"):
            return f"{mkt} {amt_str}{unit} {int(validity_days)}{dword}"
        return f"{mkt} {amt_str} {unit} {int(validity_days)} {dword}"
    base = (name or "").strip()
    return mkt or base
