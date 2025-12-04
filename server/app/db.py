from __future__ import annotations
import os
from sqlalchemy import create_engine, inspect, text
from sqlalchemy import event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase


class Base(DeclarativeBase):
    pass


def _get_database_url() -> str:
    url = os.getenv("DATABASE_URL")
    if url:
        return url
    try:
        base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        db_path = os.path.join(base_dir, "simigo.db")
        return f"sqlite:///{db_path}"
    except Exception:
        return "sqlite:///./simigo.db"


DATABASE_URL = _get_database_url()

# Create engine (pooling suitable for sync SQLAlchemy)
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
)

# Ensure SQLite enforces foreign key ONDELETE behaviors
@event.listens_for(engine, "connect")
def _set_sqlite_foreign_keys(dbapi_connection, connection_record):
    try:
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()
    except Exception:
        # Best-effort only; ignore failures
        pass

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def init_db():
    """Create all tables if they do not exist."""
    # Import ORM models to register with Base metadata
    from .models import orm  # noqa: F401
    Base.metadata.create_all(bind=engine)
    _drop_operator_i18n_tables()
    _ensure_user_profile_columns()
    _ensure_order_reference_email_columns()
    _seed_settings()
    _seed_i18n_catalog_from_files()


def _ensure_user_profile_columns():
    """Lightweight migration: add profile columns to users table if missing.

    Works for SQLite and Postgres. Safe to call multiple times.
    """
    try:
        inspector = inspect(engine)
        cols = {c["name"] for c in inspector.get_columns("users")}
    except Exception:
        # If inspection fails, bail quietly
        return
    to_add: list[tuple[str, str]] = []
    if "last_name" not in cols:
        to_add.append(("last_name", "VARCHAR(200)"))
    if "language" not in cols:
        to_add.append(("language", "VARCHAR(16)"))
    if "currency" not in cols:
        to_add.append(("currency", "VARCHAR(8)"))
    if "country" not in cols:
        to_add.append(("country", "VARCHAR(2)"))
    if not to_add:
        return
    # Execute ALTER TABLE for each missing column
    with engine.begin() as conn:
        for name, type_sql in to_add:
            try:
                conn.execute(text(f"ALTER TABLE users ADD COLUMN {name} {type_sql}"))
            except Exception:
                # Ignore if cannot alter; developer can migrate manually
                pass

def _ensure_order_reference_email_columns():
    try:
        inspector = inspect(engine)
        cols = {c["name"] for c in inspector.get_columns("order_reference_emails")}
    except Exception:
        return
    to_add: list[tuple[str, str]] = []
    if "provider_order_id" not in cols:
        to_add.append(("provider_order_id", "VARCHAR(64)"))
    if "user_id" not in cols:
        to_add.append(("user_id", "VARCHAR(32)"))
    if "email" not in cols:
        to_add.append(("email", "VARCHAR(255)"))
    if "request_id" not in cols:
        to_add.append(("request_id", "VARCHAR(64)"))
    if "assigned_at" not in cols:
        to_add.append(("assigned_at", "TIMESTAMP"))
    if "updated_at" not in cols:
        to_add.append(("updated_at", "TIMESTAMP"))
    if not to_add:
        return
    with engine.begin() as conn:
        for name, type_sql in to_add:
            try:
                conn.execute(text(f"ALTER TABLE order_reference_emails ADD COLUMN {name} {type_sql}"))
            except Exception:
                pass

def _drop_operator_i18n_tables():
    try:
        with engine.begin() as conn:
            try:
                conn.execute(text("DROP TABLE IF EXISTS i18n_operator_names"))
            except Exception:
                pass
            try:
                conn.execute(text("DROP TABLE IF EXISTS operator_seen_names"))
            except Exception:
                pass
    except Exception:
        pass


def _seed_settings():
    """Sync default language and currency options with the MVP whitelist."""
    try:
        from .models.orm import LanguageOption, CurrencyOption
        db = SessionLocal()
        try:
            # MVP language whitelist (code -> display name)
            allowed_langs = {
                "en": "English",
                "zh-Hans": "简体中文",
                "zh-Hant": "繁體中文",
                "ja": "日本語",
                "ko": "한국어",
                "th": "ไทย",
                "id": "Bahasa Indonesia",
                "es": "Español",
                "pt": "Português",
                "ms": "Bahasa Melayu",
                "vi": "Tiếng Việt",
                "ar": "العربية",
            }

            # Seed or reconcile languages
            existing_codes = {row.code for row in db.query(LanguageOption).all()}
            if not existing_codes:
                db.add_all([LanguageOption(code=c, name=n) for c, n in allowed_langs.items()])
            else:
                # Remove languages not in whitelist
                to_remove = existing_codes.difference(allowed_langs.keys())
                if to_remove:
                    db.query(LanguageOption).filter(LanguageOption.code.in_(list(to_remove))).delete(synchronize_session=False)
                # Insert missing languages
                to_insert = set(allowed_langs.keys()).difference(existing_codes)
                if to_insert:
                    db.add_all([LanguageOption(code=c, name=allowed_langs[c]) for c in to_insert])

            # Seed or reconcile currencies to payment-supported set (20 total)
            allowed_currs = {
                "USD": ("美元 (USD)", "$"),
                "EUR": ("欧元 (EUR)", "€"),
                "GBP": ("英镑 (GBP)", "£"),
                "CHF": ("瑞士法郎 (CHF)", "CHF"),
                "CNY": ("人民币 (CNY)", "¥"),
                "HKD": ("港币 (HKD)", "HK$"),
                "JPY": ("日元 (JPY)", "¥"),
                "SGD": ("新加坡元 (SGD)", "S$"),
                "KRW": ("韩元 (KRW)", "₩"),
                "THB": ("泰铢 (THB)", "฿"),
                "IDR": ("印尼卢比 (IDR)", "Rp"),
                "MYR": ("马来西亚林吉特 (MYR)", "RM"),
                "VND": ("越南盾 (VND)", "₫"),
                "BRL": ("巴西雷亚尔 (BRL)", "R$"),
                "MXN": ("墨西哥比索 (MXN)", "MX$"),
                "TWD": ("新台币 (TWD)", "NT$"),
                "AED": ("阿联酋迪拉姆 (AED)", "AED"),
                "SAR": ("沙特里亚尔 (SAR)", "SAR"),
                "AUD": ("澳大利亚元 (AUD)", "A$"),
                "CAD": ("加拿大元 (CAD)", "C$"),
            }
            existing_cur_rows = db.query(CurrencyOption).all()
            existing_cur_codes = {row.code for row in existing_cur_rows}
            if not existing_cur_codes:
                db.add_all([CurrencyOption(code=c, name=n, symbol=s) for c, (n, s) in allowed_currs.items()])
            else:
                to_remove = existing_cur_codes.difference(allowed_currs.keys())
                if to_remove:
                    db.query(CurrencyOption).filter(CurrencyOption.code.in_(list(to_remove))).delete(synchronize_session=False)
                to_insert = set(allowed_currs.keys()).difference(existing_cur_codes)
                if to_insert:
                    db.add_all([CurrencyOption(code=c, name=allowed_currs[c][0], symbol=allowed_currs[c][1]) for c in to_insert])
                # Ensure names/symbols up-to-date
                for row in existing_cur_rows:
                    if row.code in allowed_currs:
                        name, symbol = allowed_currs[row.code]
                        row.name = name
                        row.symbol = symbol
                        db.add(row)
            db.commit()
        finally:
            db.close()
    except Exception:
        # Best-effort; ignore failures
        pass


def _seed_i18n_catalog_from_files():
    """Seed i18n tables from local esim_data JSON files.

    Best-effort: inserts English entries if tables are empty or missing items.
    """
    try:
        from .models.orm import I18nCountryName, I18nRegionName, I18nBundleName
        base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
        data_dir = os.path.join(base_dir, "esim_data")
        countries_path = os.path.join(data_dir, "esim_countries.json")
        bundle_files = [os.path.join(data_dir, f"esim_bundles_{str(i).zfill(2)}.json") for i in range(1, 12)]
        import json
        # Try to use Babel CLDR for accurate territory translations
        has_babel = False
        try:
            from babel import Locale  # type: ignore
            has_babel = True
        except Exception:
            has_babel = False
        db = SessionLocal()
        try:
            target_langs = [
                "en","zh-Hans","zh-Hant","ja","ko","th","id","es","pt","ms","vi","ar"
            ]
            # Countries (en)
            try:
                with open(countries_path, "r", encoding="utf-8") as f:
                    j = json.load(f)
                items = ((j or {}).get("data") or {}).get("countries") or []
                # Seed base EN rows
                existing_en = db.query(I18nCountryName).filter(I18nCountryName.lang_code == "en").all()
                by_iso2_en = {row.iso2_code for row in existing_en if row.iso2_code}
                by_iso3_en = {row.iso3_code for row in existing_en if row.iso3_code}
                to_add_en: list[I18nCountryName] = []
                for c in items:
                    iso2 = str(c.get("iso2_code") or "").upper() or None
                    iso3 = str(c.get("iso3_code") or "").upper() or None
                    name = str(c.get("country_name") or "").strip()
                    logo = c.get("logo") or None
                    if iso2 and iso2 in by_iso2_en:
                        pass
                    elif iso3 and iso3 in by_iso3_en:
                        pass
                    else:
                        to_add_en.append(I18nCountryName(iso2_code=iso2, iso3_code=iso3, lang_code="en", name=name or (iso2 or iso3 or ""), logo=logo))
                if to_add_en:
                    db.add_all(to_add_en)
                    db.commit()
                # Build iso3 -> iso2 mapping for later use
                iso3_to_iso2: dict[str, str] = {}
                for c in items:
                    iso2 = str(c.get("iso2_code") or "").upper()
                    iso3 = str(c.get("iso3_code") or "").upper()
                    if iso2 and iso3:
                        iso3_to_iso2[iso3] = iso2

                # Replicate to other languages. If Babel is available, use CLDR translations.
                for lang in target_langs:
                    if lang == "en":
                        continue
                    existing_lang = db.query(I18nCountryName).filter(I18nCountryName.lang_code == lang).all()
                    by_iso2 = {row.iso2_code for row in existing_lang if row.iso2_code}
                    by_iso3 = {row.iso3_code for row in existing_lang if row.iso3_code}
                    to_add: list[I18nCountryName] = []
                    # Prepare Babel locale
                    loc = None
                    if has_babel:
                        try:
                            loc = Locale.parse(lang.replace('-', '_'))
                        except Exception:
                            loc = None
                    for c in items:
                        iso2 = str(c.get("iso2_code") or "").upper() or None
                        iso3 = str(c.get("iso3_code") or "").upper() or None
                        # Prefer Babel translation when available
                        if has_babel and loc and iso2:
                            name = (loc.territories.get(iso2) or str(c.get("country_name") or "")).strip()
                        else:
                            name = str(c.get("country_name") or "").strip()
                        logo = c.get("logo") or None
                        if (iso2 and iso2 in by_iso2) or (iso3 and iso3 in by_iso3):
                            # If row exists but has fallback EN, update to Babel translation
                            try:
                                row = db.query(I18nCountryName).filter(
                                    (I18nCountryName.iso2_code == iso2) | (I18nCountryName.iso3_code == iso3),
                                    I18nCountryName.lang_code == lang,
                                ).first()
                                if row and name and row.name != name:
                                    row.name = name
                                    db.add(row)
                            except Exception:
                                pass
                        else:
                            to_add.append(I18nCountryName(iso2_code=iso2, iso3_code=iso3, lang_code=lang, name=name or (iso2 or iso3 or ""), logo=logo))
                    if to_add:
                        db.add_all(to_add)
                        db.commit()
            except Exception:
                pass

            # Bundles & Regions (en)
            for p in bundle_files:
                try:
                    with open(p, "r", encoding="utf-8") as f:
                        j = json.load(f)
                except Exception:
                    continue
                items = ((j or {}).get("data") or {}).get("bundles") or []
                if not items:
                    continue
                # Seed EN
                existing_b_en = db.query(I18nBundleName).filter(I18nBundleName.lang_code == "en").all()
                existing_b_codes_en = {row.bundle_code for row in existing_b_en}
                existing_r_en = db.query(I18nRegionName).filter(I18nRegionName.lang_code == "en").all()
                existing_r_codes_en = {row.region_code for row in existing_r_en}
                existing_c_en = db.query(I18nCountryName).filter(I18nCountryName.lang_code == "en").all()
                existing_iso3_en = {row.iso3_code for row in existing_c_en if row.iso3_code}
                new_b_en: list[I18nBundleName] = []
                new_r_en: list[I18nRegionName] = []
                new_c_en: list[I18nCountryName] = []
                # Babel locale for EN not needed
                for b in items:
                    bcode = str(b.get("bundle_code") or "").strip()
                    mkt = str(b.get("bundle_marketing_name") or "").strip()
                    name = str(b.get("bundle_name") or "").strip()
                    desc = None
                    if bcode and bcode not in existing_b_codes_en:
                        new_b_en.append(I18nBundleName(bundle_code=bcode, lang_code="en", marketing_name=mkt or name or bcode, name=name or None, description=desc))
                    rcode = str(b.get("region_code") or "").strip().lower()
                    rname = str(b.get("region_name") or "").strip()
                    if rcode and (rcode not in existing_r_codes_en):
                        new_r_en.append(I18nRegionName(region_code=rcode, lang_code="en", name=rname or rcode))
                    cc_list = b.get("country_code") or []
                    cn_list = b.get("country_name") or []
                    for i, iso3 in enumerate(cc_list):
                        code3 = str(iso3 or "").upper()
                        cname = str(cn_list[i] if i < len(cn_list) else "")
                        if code3 and (code3 not in existing_iso3_en):
                            new_c_en.append(I18nCountryName(iso2_code=None, iso3_code=code3, lang_code="en", name=cname or code3, logo=None))
                if new_b_en:
                    db.add_all(new_b_en)
                if new_r_en:
                    db.add_all(new_r_en)
                if new_c_en:
                    db.add_all(new_c_en)
                if new_b_en or new_r_en or new_c_en:
                    db.commit()
                # Replicate EN values to other languages, translating when possible via Babel
                for lang in target_langs:
                    if lang == "en":
                        continue
                    existing_b_lang = db.query(I18nBundleName).filter(I18nBundleName.lang_code == lang).all()
                    existing_b_codes = {row.bundle_code for row in existing_b_lang}
                    existing_r_lang = db.query(I18nRegionName).filter(I18nRegionName.lang_code == lang).all()
                    existing_r_codes = {row.region_code for row in existing_r_lang}
                    existing_c_lang = db.query(I18nCountryName).filter(I18nCountryName.lang_code == lang).all()
                    existing_iso3 = {row.iso3_code for row in existing_c_lang if row.iso3_code}
                    new_b: list[I18nBundleName] = []
                    new_r: list[I18nRegionName] = []
                    new_c: list[I18nCountryName] = []
                    loc = None
                    if has_babel:
                        try:
                            loc = Locale.parse(lang.replace('-', '_'))
                        except Exception:
                            loc = None
                    # Region code -> CLDR territory code map (support aliases)
                    region_to_cldr = {
                        "af": "002", "africa": "002",
                        "as": "142", "asia": "142",
                        "eu": "150", "europe": "150",
                        "na": "003", "northamerica": "003", "north_america": "003", "northa": "003",
                        "sa": "005", "southamerica": "005", "south_america": "005", "southa": "005",
                    }
                    # Middle East manual translations
                    middle_east_names = {
                        "en": "Middle East",
                        "zh-Hans": "中东",
                        "zh-Hant": "中東",
                        "ja": "中東",
                        "ko": "중동",
                        "th": "ตะวันออกกลาง",
                        "id": "Timur Tengah",
                        "es": "Medio Oriente",
                        "pt": "Oriente Médio",
                        "ms": "Timur Tengah",
                        "vi": "Trung Đông",
                        "ar": "الشرق الأوسط",
                    }
                    # Other marketing names (non-country/region)
                    other_marketing = {
                        "Global": {
                            "en": "Global", "zh-Hans": "全球", "zh-Hant": "全球", "ja": "グローバル", "ko": "글로벌",
                            "th": "ทั่วโลก", "id": "Global", "ms": "Global", "es": "Global", "pt": "Global",
                            "vi": "Toàn cầu", "ar": "عالمي",
                        },
                        "Cruise": {
                            "en": "Cruise", "zh-Hans": "邮轮", "zh-Hant": "郵輪", "ja": "クルーズ", "ko": "크루즈",
                            "th": "เรือสำราญ", "id": "Kapal Pesiar", "ms": "Kapal Persiaran", "es": "Crucero", "pt": "Cruzeiro",
                            "vi": "Du thuyền", "ar": "رحلة بحرية",
                        },
                        "Europe": {
                            "en": "Europe", "zh-Hans": "欧洲", "zh-Hant": "歐洲", "ja": "ヨーロッパ", "ko": "유럽",
                            "th": "ยุโรป", "id": "Eropa", "ms": "Eropah", "es": "Europa", "pt": "Europa",
                            "vi": "Châu Âu", "ar": "أوروبا",
                        },
                        "North America": {
                            "en": "North America", "zh-Hans": "北美洲", "zh-Hant": "北美洲", "ja": "北アメリカ", "ko": "북아메리카",
                            "th": "อเมริกาเหนือ", "id": "Amerika Utara", "ms": "Amerika Utara", "es": "América del Norte", "pt": "América do Norte",
                            "vi": "Bắc Mỹ", "ar": "أمريكا الشمالية",
                        },
                        "South America": {
                            "en": "South America", "zh-Hans": "南美洲", "zh-Hant": "南美洲", "ja": "南アメリカ", "ko": "남아메리카",
                            "th": "อเมริกาใต้", "id": "Amerika Selatan", "ms": "Amerika Selatan", "es": "Sudamérica", "pt": "América do Sul",
                            "vi": "Nam Mỹ", "ar": "أمريكا الجنوبية",
                        },
                    }
                    days_word = {
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
                    unlimited_word = {
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
                    for b in items:
                        bcode = str(b.get("bundle_code") or "").strip()
                        mkt = str(b.get("bundle_marketing_name") or "").strip()
                        name = str(b.get("bundle_name") or "").strip()
                        desc = None
                        # Translate marketing name for country/region bundles when possible
                        translated_mkt = mkt
                        cat = str(b.get("bundle_category") or "").strip().lower()
                        if cat == "country":
                            # Use first ISO3 to fetch country translation
                            cc_list = b.get("country_code") or []
                            iso3 = str(cc_list[0] if cc_list else "").upper()
                            iso2 = iso3_to_iso2.get(iso3)
                            if has_babel and loc and iso2:
                                translated_mkt = loc.territories.get(iso2) or translated_mkt
                        elif cat == "region":
                            rcode = str(b.get("region_code") or "").strip().lower()
                            if rcode == "me":
                                translated_mkt = middle_east_names.get(lang, mkt)
                            else:
                                cldr = region_to_cldr.get(rcode) or region_to_cldr.get(rcode.replace(" ", ""))
                                if has_babel and loc and cldr:
                                    translated_mkt = loc.territories.get(cldr) or translated_mkt
                                else:
                                    # Fallback by marketing text mapping
                                    translated_mkt = other_marketing.get(mkt, {}).get(lang, translated_mkt)
                        else:
                            translated_mkt = other_marketing.get(mkt, {}).get(lang, translated_mkt)
                        # Upsert or insert
                        amt = b.get("gprs_limit")
                        unit = b.get("data_unit")
                        try:
                            val = int(float(str(b.get("validity") or 0)))
                        except Exception:
                            val = 0
                        try:
                            amt_i = int(float(str(amt))) if amt is not None else None
                            amt_s = str(amt_i) if amt_i is not None else str(amt)
                        except Exception:
                            amt_s = str(amt)
                        name_local = translated_mkt
                        if bool(b.get("unlimited")) and val:
                            name_local = f"{translated_mkt}{unlimited_word.get(lang,'Unlimited')} {val}{days_word.get(lang,'Days')}"
                        elif (amt_i is not None) and (amt_i > 0) and unit and val:
                            name_local = f"{translated_mkt}{amt_i}{unit} {val}{days_word.get(lang,'Days')}"
                        if bcode:
                            row = db.query(I18nBundleName).filter(I18nBundleName.bundle_code == bcode, I18nBundleName.lang_code == lang).first()
                            if row:
                                if translated_mkt and row.marketing_name != translated_mkt:
                                    row.marketing_name = translated_mkt
                                if name_local and row.name != name_local:
                                    row.name = name_local
                                db.add(row)
                            else:
                                new_b.append(I18nBundleName(bundle_code=bcode, lang_code=lang, marketing_name=translated_mkt or (name or bcode), name=name_local or name or None, description=desc))
                        rcode = str(b.get("region_code") or "").strip().lower()
                        rname = str(b.get("region_name") or "").strip()
                        # Translate region name
                        translated_rname = rname
                        if rcode == "me":
                            translated_rname = middle_east_names.get(lang, rname or rcode)
                        else:
                            cldr = region_to_cldr.get(rcode)
                            if has_babel and loc and cldr:
                                translated_rname = loc.territories.get(cldr) or rname or rcode
                        if rcode:
                            row_r = db.query(I18nRegionName).filter(I18nRegionName.region_code == rcode, I18nRegionName.lang_code == lang).first()
                            if row_r:
                                if translated_rname and row_r.name != translated_rname:
                                    row_r.name = translated_rname
                                    db.add(row_r)
                            elif rcode not in existing_r_codes:
                                new_r.append(I18nRegionName(region_code=rcode, lang_code=lang, name=translated_rname or rcode))
                        cc_list = b.get("country_code") or []
                        cn_list = b.get("country_name") or []
                        for i, iso3 in enumerate(cc_list):
                            code3 = str(iso3 or "").upper()
                            cname = str(cn_list[i] if i < len(cn_list) else "")
                            # If missing country record for this lang, insert; name fallback will be translated via Babel later
                            if code3 and (code3 not in existing_iso3):
                                # Prefer Babel translation if we can map iso3 -> iso2
                                iso2 = iso3_to_iso2.get(code3)
                                translated = None
                                if has_babel and loc and iso2:
                                    translated = loc.territories.get(iso2)
                                new_c.append(I18nCountryName(iso2_code=iso2, iso3_code=code3, lang_code=lang, name=(translated or cname or code3), logo=None))
                    if new_b:
                        db.add_all(new_b)
                    if new_r:
                        db.add_all(new_r)
                    if new_c:
                        db.add_all(new_c)
                    if new_b or new_r or new_c:
                        db.commit()
                # If Babel present, also update existing non-EN country rows to translated names
                if has_babel:
                    for lang in target_langs:
                        if lang == "en":
                            continue
                        try:
                            loc = Locale.parse(lang.replace('-', '_'))
                        except Exception:
                            loc = None
                        if not loc:
                            continue
                        rows = db.query(I18nCountryName).filter(I18nCountryName.lang_code == lang).all()
                        for row in rows:
                            iso2 = (row.iso2_code or "").upper()
                            translated = loc.territories.get(iso2) if iso2 else None
                            if translated and row.name != translated:
                                row.name = translated
                                db.add(row)
                        db.commit()
        finally:
            db.close()
    except Exception:
        # Best-effort only
        pass

