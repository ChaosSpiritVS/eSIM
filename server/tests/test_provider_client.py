import os
import unittest
from typing import Any, Dict
from datetime import datetime, timedelta

from server.app.db import init_db
from server.app.provider.client import ProviderClient


class TestProviderClient(unittest.TestCase):
    def setUp(self):
        init_db()

    def test_get_countries_nonfake_normalization(self):
        os.environ["PROVIDER_FAKE"] = "false"
        cli = ProviderClient()
        def fake_post(path: str, payload: Dict[str, Any], extra_headers=None, include_token: bool = False):
            return {
                "data": {
                    "countries": [
                        {"iso2_code": "US", "iso3_code": "USA", "country_name": "United States"},
                        {"code": "GB", "name": "United Kingdom"},
                        {"iso2_code": "", "country_name": ""},
                    ]
                }
            }
        cli.http.post = fake_post  # type: ignore
        items = cli.get_countries()
        self.assertEqual(items[0]["code"], "US")
        self.assertEqual(items[1]["code"], "GB")
        self.assertEqual(len(items), 2)

    def test_get_regions_nonfake_normalization(self):
        os.environ["PROVIDER_FAKE"] = "false"
        cli = ProviderClient()
        def fake_post(path: str, payload: Dict[str, Any], extra_headers=None, include_token: bool = False):
            return {
                "data": {
                    "regions": [
                        {"region_code": "eu", "region_name": "Europe"},
                        {"code": "as", "name": "Asia"},
                    ]
                }
            }
        cli.http.post = fake_post  # type: ignore
        items = cli.get_regions()
        self.assertEqual(items[0]["code"], "eu")
        self.assertEqual(items[1]["code"], "as")

    def test_get_bundle_list_nonfake_sorting_and_count(self):
        os.environ["PROVIDER_FAKE"] = "false"
        cli = ProviderClient()
        bundles = [
            {"gprs_limit": 1, "data_unit": "GB", "unlimited": False},
            {"gprs_limit": 900, "data_unit": "MB", "unlimited": False},
            {"gprs_limit": 0, "data_unit": "GB", "unlimited": True},
        ]
        def fake_post(path: str, payload: Dict[str, Any], extra_headers=None, include_token: bool = False):
            return {"data": {"bundles": bundles, "bundles_count": "3"}}
        cli.http.post = fake_post  # type: ignore
        asc = cli.get_bundle_list(1, 10, sort_by="data_asc")
        dsc = cli.get_bundle_list(1, 10, sort_by="data_dsc")
        self.assertEqual(asc["bundles_count"], 3)
        self.assertEqual(asc["bundles"][0]["gprs_limit"], 900)
        self.assertTrue(dsc["bundles"][0]["unlimited"])

    def test_get_bundle_networks_v2_nonfake_country_filter(self):
        os.environ["PROVIDER_FAKE"] = "false"
        cli = ProviderClient()
        def fake_post(path: str, payload: Dict[str, Any], extra_headers=None, include_token: bool = False):
            return {
                "data": {
                    "networks": [
                        {"country_code": "HKG", "operator_list": ["CSL"]},
                        {"country_code": "CHN", "operator_list": ["CM"]},
                    ],
                    "networks_count": 2,
                }
            }
        cli.http.post = fake_post  # type: ignore
        r = cli.get_bundle_networks_v2(bundle_code="HKG_0110202517200001", country_code="CHN")
        self.assertEqual(len(r["networks"]), 1)
        self.assertEqual(r["networks"][0]["country_code"], "CHN")

    def test_list_orders_v2_fake_filters_parse_dates_and_iccid(self):
        os.environ["PROVIDER_FAKE"] = "true"
        cli = ProviderClient()
        now = datetime.utcnow()
        start = (now - timedelta(days=3)).strftime("%Y/%m/%d %H:%M:%S")
        end = now.strftime("%Y/%m/%d %H:%M:%S")
        r = cli.list_orders_v2(page_number=1, page_size=10, filters={"start_date": start, "end_date": end, "iccid": "ANY"})
        self.assertEqual(r["orders_count"], 0)

    def test_list_orders_fake_sort_status(self):
        os.environ["PROVIDER_FAKE"] = "true"
        cli = ProviderClient()
        items = cli.list_orders(page=1, page_size=10, filters={"sort_by": "status", "sort_order": "asc"})
        self.assertTrue(items[0]["status"] <= items[-1]["status"])

    def test_get_order_consumption_v2_fake(self):
        os.environ["PROVIDER_FAKE"] = "true"
        cli = ProviderClient()
        o = cli.get_order_consumption_v2(order_reference="REF-1")
        self.assertIn("data_remaining", o)

    def test_get_agent_bills_fake(self):
        os.environ["PROVIDER_FAKE"] = "true"
        cli = ProviderClient()
        r = cli.get_agent_bills(page_number=1, page_size=10)
        self.assertGreaterEqual(r.get("bills_count", 0), 1)
