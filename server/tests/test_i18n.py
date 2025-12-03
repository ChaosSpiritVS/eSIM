import unittest
from server.app.db import init_db, SessionLocal
from server.app.models.orm import I18nCountryName, I18nRegionName, I18nBundleName
from server.app.i18n import canonical_language, resolve_language, translate_country, translate_region, translate_marketing, translate_bundle_name


class TestI18n(unittest.TestCase):
    def setUp(self):
        init_db()

    def test_canonical_and_resolve_language(self):
        self.assertEqual(canonical_language("zh-CN"), "zh-Hans")
        self.assertEqual(canonical_language("zh-TW"), "zh-Hant")
        self.assertEqual(canonical_language("en-US"), "en")
        self.assertEqual(resolve_language("ja", None, None, None), "ja")
        self.assertEqual(resolve_language(None, "id", None, None), "id")

    def test_translate_country_db_and_static(self):
        db = SessionLocal()
        try:
            if db.query(I18nCountryName).filter(I18nCountryName.lang_code == "en", I18nCountryName.iso2_code == "GB").count() == 0:
                db.add(I18nCountryName(iso2_code="GB", iso3_code="GBR", lang_code="en", name="United Kingdom", logo=None))
                db.commit()
        finally:
            db.close()
        t = translate_country("GBR", None, "zh-Hans")
        self.assertIsInstance(t, str)

    def test_translate_region_db_and_fallback(self):
        db = SessionLocal()
        try:
            if db.query(I18nRegionName).filter(I18nRegionName.lang_code == "zh-Hans", I18nRegionName.region_code == "eu").count() == 0:
                db.add(I18nRegionName(region_code="eu", lang_code="zh-Hans", name="欧洲"))
                db.commit()
        finally:
            db.close()
        self.assertEqual(translate_region("eu", None, "zh-Hans"), "欧洲")
        self.assertEqual(translate_region("na", None, "zh-Hans"), "北美洲")

    def test_translate_marketing_canonical_plus(self):
        self.assertEqual(translate_marketing("Europe+", "zh-Hans", None), "欧洲+")

    def test_translate_bundle_name_variants(self):
        self.assertEqual(translate_bundle_name("Hong Kong", "en", None, None, None, 3, "Hong Kong", True), "Hong Kong Unlimited 3 Days")
        self.assertEqual(translate_bundle_name("Europe", "zh-Hans", None, 1, "GB", 7, "Europe", False), "欧洲 1GB 7天")

    def test_translate_bundle_name_db(self):
        db = SessionLocal()
        try:
            if db.query(I18nBundleName).filter(I18nBundleName.lang_code == "en", I18nBundleName.bundle_code == "HKG_0110202517200001").count() == 0:
                db.add(I18nBundleName(bundle_code="HKG_0110202517200001", lang_code="en", name="Hong Kong 1GB3Days", marketing_name="Hong Kong"))
                db.commit()
        finally:
            db.close()
        v = translate_bundle_name("HK", "en", "HKG_0110202517200001", None, None, None, None, None)
        self.assertIsInstance(v, str)
