import os
import json
from app.db import SessionLocal
from app.models.orm import I18nCountryName, I18nRegionName, I18nBundleName
from babel import Locale

def run():
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "esim_data"))
    with open(os.path.join(base_dir, "esim_countries.json"), "r", encoding="utf-8") as f:
        j = json.load(f)
    countries = ((j or {}).get("data") or {}).get("countries") or []
    iso3_to_iso2 = {str(c.get("iso3_code") or "").upper(): str(c.get("iso2_code") or "").upper() for c in countries}
    iso2_to_name_en = {str(c.get("iso2_code") or "").upper(): str(c.get("country_name") or "") for c in countries}
    iso3_to_name_en = {str(c.get("iso3_code") or "").upper(): str(c.get("country_name") or "") for c in countries}

    bundle_files = [os.path.join(base_dir, f"esim_bundles_{str(i).zfill(2)}.json") for i in range(1, 12)]
    bundles_by_code: dict[str, dict] = {}
    for p in bundle_files:
        try:
            with open(p, "r", encoding="utf-8") as f:
                bj = json.load(f)
            items = ((bj or {}).get("data") or {}).get("bundles") or []
            for b in items:
                code = str(b.get("bundle_code") or "").strip()
                if code:
                    bundles_by_code[code] = b
        except Exception:
            pass

    region_to_cldr = {
        "af": "002", "africa": "002",
        "as": "142", "asia": "142",
        "eu": "150", "europe": "150",
        "na": "003", "northamerica": "003", "north_america": "003", "northa": "003",
        "sa": "005", "southamerica": "005", "south_america": "005", "southa": "005",
    }
    middle_east_names = {
        "en": "Middle East", "zh-Hans": "中东", "zh-Hant": "中東", "ja": "中東", "ko": "중동",
        "th": "ตะวันออกกลาง", "id": "Timur Tengah", "es": "Medio Oriente", "pt": "Oriente Médio",
        "ms": "Timur Tengah", "vi": "Trung Đông", "ar": "الشرق الأوسط",
    }
    days_word = {"en": "Days","zh-Hans": "天","zh-Hant": "天","ja": "日","ko": "일","th": "วัน","id": "Hari","es": "días","pt": "dias","ms": "Hari","vi": "ngày","ar": "أيام"}
    unlimited_word = {"en": "Unlimited","zh-Hans": "不限量","zh-Hant": "不限量","ja": "無制限","ko": "무제한","th": "ไม่จำกัด","id": "Tak Terbatas","es": "Ilimitado","pt": "Ilimitado","ms": "Tanpa Had","vi": "Không giới hạn","ar": "غير محدود"}
    langs = ["en","zh-Hans","zh-Hant","ja","ko","th","id","es","pt","ms","vi","ar"]

    summary = {"countries": {}, "regions": {}, "bundles": {}}
    db = SessionLocal()
    try:
        for lang in langs:
            fixed_c = fixed_r = fixed_b = 0
            checked_c = checked_r = checked_b = 0
            mism_c = mism_r = mism_b = 0
            try:
                loc = Locale.parse(lang.replace('-', '_'))
            except Exception:
                loc = None
            rows_c = db.query(I18nCountryName).filter(I18nCountryName.lang_code == lang).all()
            for row in rows_c:
                iso2 = (row.iso2_code or "").upper() or None
                iso3 = (row.iso3_code or "").upper() or None
                if not iso2 and iso3:
                    iso2 = iso3_to_iso2.get(iso3)
                expected = None
                if lang == "en":
                    expected = (iso2 and iso2_to_name_en.get(iso2)) or (iso3 and iso3_to_name_en.get(iso3))
                else:
                    if loc and iso2:
                        expected = loc.territories.get(iso2)
                if expected:
                    checked_c += 1
                    if (row.name or "") != expected:
                        mism_c += 1
                        row.name = expected
                        db.add(row)
                        fixed_c += 1
            rows_r = db.query(I18nRegionName).filter(I18nRegionName.lang_code == lang).all()
            for row in rows_r:
                rcode = (row.region_code or "").lower()
                expected = None
                if rcode == "me":
                    expected = middle_east_names.get(lang)
                else:
                    cldr = region_to_cldr.get(rcode)
                    if loc and cldr:
                        expected = loc.territories.get(cldr)
                if expected:
                    checked_r += 1
                    if (row.name or "") != expected:
                        mism_r += 1
                        row.name = expected
                        db.add(row)
                        fixed_r += 1
            rows_b = db.query(I18nBundleName).filter(I18nBundleName.lang_code == lang).all()
            for row in rows_b:
                code = (row.bundle_code or "").strip()
                b = bundles_by_code.get(code)
                if not b:
                    continue
                mkt = str(b.get("bundle_marketing_name") or "").strip()
                cat = str(b.get("bundle_category") or "").strip().lower()
                translated_mkt = mkt
                if cat == "country":
                    cc_list = b.get("country_code") or []
                    iso3 = str(cc_list[0] if cc_list else "").upper()
                    iso2 = iso3_to_iso2.get(iso3)
                    if loc and iso2:
                        translated_mkt = loc.territories.get(iso2) or translated_mkt
                elif cat == "region":
                    rcode = str(b.get("region_code") or "").strip().lower()
                    if rcode == "me":
                        translated_mkt = middle_east_names.get(lang, translated_mkt)
                    else:
                        cldr = region_to_cldr.get(rcode) or region_to_cldr.get(rcode.replace(" ", ""))
                        if loc and cldr:
                            translated_mkt = loc.territories.get(cldr) or translated_mkt
                else:
                    mm = {
                        "Global": {"en":"Global","zh-Hans":"全球","zh-Hant":"全球","ja":"グローバル","ko":"글로벌","th":"ทั่วโลก","id":"Global","ms":"Global","es":"Global","pt":"Global","vi":"Toàn cầu","ar":"عالمي"},
                        "Cruise": {"en":"Cruise","zh-Hans":"邮轮","zh-Hant":"郵輪","ja":"クルーズ","ko":"크루즈","th":"เรือสำราญ","id":"Kapal Pesiar","ms":"Kapal Persiaran","es":"Crucero","pt":"Cruzeiro","vi":"Du thuyền","ar":"رحلة بحرية"},
                        "Europe": {"en":"Europe","zh-Hans":"欧洲","zh-Hant":"歐洲","ja":"ヨーロッパ","ko":"유럽","th":"ยุโรป","id":"Eropa","ms":"Eropah","es":"Europa","pt":"Europa","vi":"Châu Âu","ar":"أوروبا"},
                        "North America": {"en":"North America","zh-Hans":"北美洲","zh-Hant":"北美洲","ja":"北アメリカ","ko":"북아메리카","th":"อเมริกาเหนือ","id":"Amerika Utara","ms":"Amerika Utara","es":"América del Norte","pt":"América do Norte","vi":"Bắc Mỹ","ar":"أمريكا الشمالية"},
                        "South America": {"en":"South America","zh-Hans":"南美洲","zh-Hant":"南美洲","ja":"南アメリカ","ko":"남아메리카","th":"อเมริกาใต้","id":"Amerika Selatan","ms":"Amerika Selatan","es":"Sudamérica","pt":"América do Sul","vi":"Nam Mỹ","ar":"أمريكا الجنوبية"},
                        "Africa": {"en":"Africa","zh-Hans":"非洲","zh-Hant":"非洲","ja":"アフリカ","ko":"아프리카","th":"แอฟริกา","id":"Afrika","ms":"Afrika","es":"África","pt":"África","vi":"Châu Phi","ar":"أفريقيا"},
                        "Asia": {"en":"Asia","zh-Hans":"亚洲","zh-Hant":"亞洲","ja":"アジア","ko":"아시아","th":"เอเชีย","id":"Asia","ms":"Asia","es":"Asia","pt":"Ásia","vi":"Châu Á","ar":"آسيا"},
                        "Middle East": {"en":"Middle East","zh-Hans":"中东","zh-Hant":"中東","ja":"中東","ko":"중동","th":"ตะวันออกกลาง","id":"Timur Tengah","ms":"Timur Tengah","es":"Medio Oriente","pt":"Oriente Médio","vi":"Trung Đông","ar":"الشرق الأوسط"},
                    }
                    translated_mkt = mm.get(mkt, {}).get(lang, translated_mkt)
                amt = b.get("gprs_limit")
                unit = b.get("data_unit")
                try:
                    val = int(float(str(b.get("validity") or 0)))
                except Exception:
                    val = 0
                amt_i = None
                try:
                    if amt is not None:
                        amt_i = int(float(str(amt)))
                except Exception:
                    amt_i = None
                name_expected = translated_mkt
                if bool(b.get("unlimited")) and val:
                    name_expected = f"{translated_mkt}{unlimited_word.get(lang,'Unlimited')} {val}{days_word.get(lang,'Days')}"
                elif (amt_i is not None) and (amt_i > 0) and unit and val:
                    name_expected = f"{translated_mkt}{amt_i}{unit} {val}{days_word.get(lang,'Days')}"
                checked_b += 1
                changed = False
                if (row.marketing_name or "") != translated_mkt:
                    mism_b += 1
                    row.marketing_name = translated_mkt
                    changed = True
                if (row.name or "") != name_expected:
                    mism_b += 1
                    row.name = name_expected
                    changed = True
                if changed:
                    db.add(row)
                    fixed_b += 1
            db.commit()
            summary["countries"][lang] = {"checked": checked_c, "fixed": fixed_c, "mismatch": mism_c}
            summary["regions"][lang] = {"checked": checked_r, "fixed": fixed_r, "mismatch": mism_r}
            summary["bundles"][lang] = {"checked": checked_b, "fixed": fixed_b, "mismatch": mism_b}
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    finally:
        db.close()

if __name__ == "__main__":
    run()

