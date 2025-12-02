//
//  SimigoTests.swift
//  SimigoTests
//
//  Created by 李杰 on 2025/10/31.
//

import XCTest
@testable import Simigo

final class SimigoTests: XCTestCase {

    func testOrderListItemDecodesArrayAndNumbers() throws {
        let json = """
        {
          "order_id": "OID123",
          "order_reference": "REF1",
          "bundle_code": "B1",
          "bundle_name": "N",
          "bundle_marketing_name": "M",
          "country_code": ["HK", "MO"],
          "country_name": ["中国香港", "中国澳门"],
          "bundle_sale_price": 9.99,
          "reseller_retail_price": "12.34",
          "created_at": 1699999999123,
          "order_status": "paid"
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamOrderRepository.OrderListItemDTO.self, from: json)
        XCTAssertEqual(dto.orderId, "OID123")
        XCTAssertEqual(dto.countryCode?.first, "HK")
        XCTAssertEqual(dto.countryName?.first, "中国香港")
        XCTAssertEqual(dto.bundleSalePrice, "9.99")
        XCTAssertEqual(dto.resellerRetailPrice, "12.34")
        XCTAssertEqual(dto.createdAt, "1699999999")
        XCTAssertEqual(dto.orderStatus, "paid")
    }

    func testOrderListItemDecodesStringCountry() throws {
        let json = """
        {
          "order_id": "OID234",
          "order_reference": "REF2",
          "bundle_code": "B2",
          "country_code": "US",
          "bundle_sale_price": "10",
          "created_at": "1700000000",
          "order_status": "failed"
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamOrderRepository.OrderListItemDTO.self, from: json)
        XCTAssertEqual(dto.orderId, "OID234")
        XCTAssertEqual(dto.countryCode?.first, "US")
        XCTAssertEqual(dto.bundleSalePrice, "10")
        XCTAssertEqual(dto.createdAt, "1700000000")
        XCTAssertEqual(dto.orderStatus, "failed")
    }

    func testEnvelopeDecodesOrdersListData() throws {
        let json = """
        {
          "code": 200,
          "msg": "ok",
          "data": {
            "orders": [
              {
                "order_id": "OID123",
                "order_reference": "REF1",
                "bundle_code": "B1",
                "country_code": ["HK"],
                "bundle_sale_price": 9.99,
                "created_at": 1699999999123,
                "order_status": "paid"
              }
            ],
            "orders_count": 1
          }
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let env = try dec.decode(Envelope<HTTPUpstreamOrderRepository.OrdersListDataDTO>.self, from: json)
        XCTAssertEqual(env.code, 200)
        XCTAssertEqual(env.msg, "ok")
        XCTAssertEqual(env.data.orders.count, 1)
        XCTAssertEqual(env.data.ordersCount, 1)
        XCTAssertEqual(env.data.orders.first?.countryCode?.first, "HK")
        XCTAssertEqual(env.data.orders.first?.bundleSalePrice, "9.99")
    }

    func testRegionCodeConverterAlpha2Alpha3() throws {
        XCTAssertEqual(RegionCodeConverter.toAlpha2("usa"), "US")
        XCTAssertEqual(RegionCodeConverter.toAlpha2("US"), "US")
        XCTAssertEqual(RegionCodeConverter.toAlpha3("CN"), "CHN")
        XCTAssertEqual(RegionCodeConverter.toAlpha3("CHN"), "CHN")
        XCTAssertEqual(RegionCodeConverter.toAlpha2("ZZZ"), "ZZZ")
        XCTAssertEqual(RegionCodeConverter.toAlpha2(" hk "), "HK")
    }

    func testPaymentProcessorFactoryMapping() throws {
        let f = PaymentProcessorFactory()
        XCTAssertTrue(f.processor(for: .alipay) is GsalaryAlipayProcessor)
        XCTAssertTrue(f.processor(for: .paypal) is GsalaryPayPalProcessor)
        XCTAssertTrue(f.processor(for: .card) is GsalaryCardProcessor)
        XCTAssertTrue(f.processor(for: .applepay) is GsalaryApplePayProcessor)
        XCTAssertNil(f.processor(for: .googlepay))
    }

    func testPaymentEventBridgeNotifications() {
        let exp1 = expectation(forNotification: .paymentSucceeded, object: nil) { note in
            let info = note.userInfo ?? [:]
            return (info["orderId"] as? String) == "OID1" && (info["oldOrderId"] as? String) == "OLD1" && (info["method"] as? String) == "card"
        }
        let exp2 = expectation(forNotification: .paymentFailed, object: nil) { note in
            let info = note.userInfo ?? [:]
            return (info["orderId"] as? String) == "OID2" && (info["reasonCategory"] as? String) == "network" && (info["reasonCode"] as? String) == "offline"
        }
        PaymentEventBridge.paymentSucceeded(orderId: "OID1", oldOrderId: "OLD1", method: "card")
        PaymentEventBridge.paymentFailed(orderId: "OID2", reason: "", method: "paypal", error: NetworkError.offline)
        wait(for: [exp1, exp2], timeout: 1.0)
    }

    func testRequestCenterSingleFlightDedup() async throws {
        let rc = RequestCenter.shared
        var called = 0
        let work: () async throws -> Int = {
            called += 1
            try await Task.sleep(nanoseconds: 200_000_000)
            return 42
        }
        async let r1: Int = try rc.singleFlight(key: "K1", work: work)
        async let r2: Int = try rc.singleFlight(key: "K1", work: work)
        let v1 = try await r1
        let v2 = try await r2
        XCTAssertEqual(v1, 42)
        XCTAssertEqual(v2, 42)
        XCTAssertEqual(called, 1)
    }

    func testRequestCenterCancel() async {
        let rc = RequestCenter.shared
        let key = "KC"
        let t = Task {
            do {
                let _: Int = try await rc.singleFlight(key: key) {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    return 1
                }
                XCTFail("should be cancelled")
            } catch is CancellationError {
            } catch {
                XCTFail("unexpected error")
            }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        await rc.cancel(key: key)
        _ = await t.result
    }

    func testNetworkErrorLocalizedDescription() {
        XCTAssertEqual(NetworkError.invalidURL.localizedDescription, "请求地址无效")
        XCTAssertEqual(NetworkError.badStatus(404).localizedDescription, "服务器返回错误（404）")
        XCTAssertEqual(NetworkError.offline.localizedDescription, "当前无网络连接")
    }
    
    func testOrderListItemDecodesMixedTypes() throws {
        let json = """
        {
          "order_id": 12345,
          "order_reference": "R1",
          "bundle_code": "B1",
          "country_code": "CN",
          "bundle_sale_price": "12.5",
          "reseller_retail_price": 20,
          "currency_code": "CNY",
          "created_at": 1700000000123,
          "status": "200"
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamOrderRepository.OrderListItemDTO.self, from: json)
        XCTAssertEqual(dto.orderId, "12345")
        XCTAssertEqual(dto.countryCode?.first, "CN")
        XCTAssertEqual(dto.bundleSalePrice, "12.5")
        XCTAssertEqual(dto.resellerRetailPrice, "20")
        XCTAssertEqual(dto.currencyCode, "CNY")
        XCTAssertEqual(dto.createdAt, "1700000000")
        XCTAssertEqual(dto.status, 200)
    }

    func testOrderListItemDecodesBooleanValuesAsNil() throws {
        let json = """
        {
          "order_id": "OIDBOOL",
          "order_reference": "RB",
          "currency_code": true,
          "bundle_sale_price": false,
          "order_status": true,
          "created_at": 12.34,
          "reseller_retail_price": 20.0
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamOrderRepository.OrderListItemDTO.self, from: json)
        XCTAssertNil(dto.currencyCode)
        XCTAssertNil(dto.bundleSalePrice)
        XCTAssertNil(dto.orderStatus)
        XCTAssertEqual(dto.createdAt, "12.34")
        XCTAssertEqual(dto.resellerRetailPrice, "20")
    }

    func testOrderListItemMissingKeysDefaultAndNils() throws {
        let json = """
        {
          "order_reference": "R"
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamOrderRepository.OrderListItemDTO.self, from: json)
        XCTAssertEqual(dto.orderId, "")
        XCTAssertEqual(dto.orderReference, "R")
        XCTAssertNil(dto.countryCode)
        XCTAssertNil(dto.createdAt)
        XCTAssertNil(dto.status)
        XCTAssertNil(dto.currencyCode)
    }

    func testOrderListItemCreatedAtThresholdExactInt() throws {
        let json = """
        {
          "order_id": "OID100",
          "order_reference": "R100",
          "created_at": 1000000000000
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamOrderRepository.OrderListItemDTO.self, from: json)
        XCTAssertEqual(dto.createdAt, "1000000000000")
    }

    func testOrderListItemCreatedAtThresholdExactDouble() throws {
        let json = """
        {
          "order_id": "OID101",
          "order_reference": "R101",
          "created_at": 1000000000000.0
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamOrderRepository.OrderListItemDTO.self, from: json)
        XCTAssertEqual(dto.createdAt, "1000000000000")
    }

    func testOrderListItemCreatedAtDoubleMillisConvertsToSeconds() throws {
        let json = """
        {
          "order_id": "OID102",
          "order_reference": "R102",
          "created_at": 1700000000123.0
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamOrderRepository.OrderListItemDTO.self, from: json)
        XCTAssertEqual(dto.createdAt, "1700000000")
    }

    func testOrderListItemCountryNameSingleStringArray() throws {
        let json = """
        {
          "order_id": "OIDCN",
          "order_reference": "RCN",
          "country_name": "中国"
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamOrderRepository.OrderListItemDTO.self, from: json)
        XCTAssertEqual(dto.countryName?.first, "中国")
    }

    func testOrderListItemBundleSalePriceDoubleIntegerToStringInt() throws {
        let json = """
        {
          "order_id": "OIDPRC",
          "order_reference": "RPRC",
          "bundle_sale_price": 15.0
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamOrderRepository.OrderListItemDTO.self, from: json)
        XCTAssertEqual(dto.bundleSalePrice, "15")
    }

    func testOrderDetailDTODecodesMixedTypes() throws {
        let json = """
        {
          "orderId": 12345.0,
          "orderReference": "REFX",
          "bundleCategory": "country",
          "bundleCode": "B2",
          "bundleMarketingName": "M2",
          "bundleName": "N2",
          "countryCode": ["CN"],
          "countryName": ["中国"],
          "activationCode": "ACT",
          "smdpAddress": "SMDP",
          "matchingId": "MID",
          "bundleExpiryDate": 1700000100,
          "expiryDate": "1700000200",
          "planStarted": true,
          "planStatus": "active",
          "orderStatus": "paid",
          "dateCreated": 1700000000456
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        let dto = try dec.decode(HTTPUpstreamOrderRepository.OrderDetailDTO.self, from: json)
        XCTAssertEqual(dto.orderId, "12345")
        XCTAssertEqual(dto.orderReference, "REFX")
        XCTAssertEqual(dto.bundleCategory, "country")
        XCTAssertEqual(dto.bundleCode, "B2")
        XCTAssertEqual(dto.bundleMarketingName, "M2")
        XCTAssertEqual(dto.bundleName, "N2")
        XCTAssertEqual(dto.countryCode?.first, "CN")
        XCTAssertEqual(dto.countryName?.first, "中国")
        XCTAssertEqual(dto.activationCode, "ACT")
        XCTAssertEqual(dto.smdpAddress, "SMDP")
        XCTAssertEqual(dto.matchingId, "MID")
        XCTAssertEqual(dto.bundleExpiryDate, "1700000100")
        XCTAssertEqual(dto.expiryDate, "1700000200")
        XCTAssertEqual(dto.planStarted, true)
        XCTAssertEqual(dto.planStatus, "active")
        XCTAssertEqual(dto.orderStatus, "paid")
        XCTAssertEqual(dto.dateCreated, "1700000000")
    }

    func testRegionDTODecodesSnakeCase() throws {
        let json = """
        {
          "region_code": "asia",
          "region_name": "亚洲"
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamCatalogRepository.RegionDTO.self, from: json)
        XCTAssertEqual(dto.code, "asia")
        XCTAssertEqual(dto.name, "亚洲")
    }

    func testRegionDTODecodesPlainKeys() throws {
        let json = """
        {
          "code": "eu",
          "name": "欧洲"
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        let dto = try dec.decode(HTTPUpstreamCatalogRepository.RegionDTO.self, from: json)
        XCTAssertEqual(dto.code, "eu")
        XCTAssertEqual(dto.name, "欧洲")
    }

    func testEnvelopeDecodesArrayData() throws {
        let json = """
        {
          "code": 201,
          "msg": "ok",
          "data": ["x","y"]
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        let env = try dec.decode(Envelope<[String]>.self, from: json)
        XCTAssertEqual(env.code, 201)
        XCTAssertEqual(env.msg, "ok")
        XCTAssertEqual(env.data.count, 2)
        XCTAssertEqual(env.data[0], "x")
    }

    func testCountryFlagEmoji() {
        XCTAssertEqual(countryFlag("US"), "🇺🇸")
        XCTAssertEqual(countryFlag("chn"), "🇨🇳")
        XCTAssertEqual(countryFlag("ZZZ"), "ZZZ")
    }
    
    func testAgentAccountDTODecodesSnakeCase() throws {
        let json = """
        {
          "agent_id": "A1",
          "username": "u1",
          "name": "n1",
          "balance": 12.3,
          "revenue_rate": 15,
          "status": 1,
          "created_at": 1700000000
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamAgentRepository.AgentAccountDTO.self, from: json)
        XCTAssertEqual(dto.agentId, "A1")
        XCTAssertEqual(dto.username, "u1")
        XCTAssertEqual(dto.name, "n1")
        XCTAssertEqual(dto.balance, 12.3, accuracy: 0.0001)
        XCTAssertEqual(dto.revenueRate, 15)
        XCTAssertEqual(dto.status, 1)
        XCTAssertEqual(dto.createdAt, 1700000000)
    }

    func testAgentBillsDTODecodesSnakeCaseAndCount() throws {
        let json = """
        {
          "bills": [
            {"bill_id": "B1", "trade": 1, "amount": 9.99, "reference": "r1", "description": "d1", "created_at": 1700000000},
            {"bill_id": "B2", "trade": -1, "amount": 5.0, "reference": "r2", "description": "d2", "created_at": 1700000100}
          ],
          "bills_count": 2
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamAgentRepository.AgentBillsDTO.self, from: json)
        XCTAssertEqual(dto.bills.count, 2)
        XCTAssertEqual(dto.billsCount, 2)
        XCTAssertEqual(dto.bills.first?.billId, "B1")
        if let trade = dto.bills.last?.trade {
            XCTAssertEqual(trade, -1)
        } else {
            XCTFail("trade is nil")
        }
        if let amount = dto.bills.first?.amount {
            XCTAssertEqual(amount, 9.99, accuracy: 0.0001)
        } else {
            XCTFail("amount is nil")
        }
        if let createdAt = dto.bills.last?.createdAt {
            XCTAssertEqual(createdAt, 1700000100)
        } else {
            XCTFail("createdAt is nil")
        }
    }

    func testCountriesDataDTODecodesObject() throws {
        let json = """
        {
          "countries": [
            {"iso2_code":"US","iso3_code":"USA","country_name":"美国"},
            {"code":"cn","name":"中国","iso3_code":"CHN","iso2_code":"CN"}
          ],
          "countries_count": 2
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        let dto = try dec.decode(HTTPUpstreamCatalogRepository.CountriesDataDTO.self, from: json)
        XCTAssertEqual(dto.countriesCount, 2)
        XCTAssertEqual(dto.countries[0].iso2Code, "US")
        XCTAssertEqual(dto.countries[1].iso3Code.uppercased(), "CHN")
        XCTAssertEqual(dto.countries[1].countryName, "中国")
    }

    func testCountriesDataDTODecodesArray() throws {
        let json = """
        [
          {"iso2_code":"GB","iso3_code":"GBR","country_name":"英国"},
          {"code":"hk","name":"中国香港","iso3_code":"HKG","iso2_code":"HK"}
        ]
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        let dto = try dec.decode(HTTPUpstreamCatalogRepository.CountriesDataDTO.self, from: json)
        XCTAssertEqual(dto.countriesCount, 2)
        XCTAssertEqual(dto.countries[0].iso3Code, "GBR")
        XCTAssertEqual(dto.countries[1].iso2Code, "HK")
    }

    func testNetworksItemDTODecodesSnakeCase() throws {
        let json = """
        {
          "country_code": "CN",
          "operator_list": ["CMCC","CUCC"]
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        let dto = try dec.decode(HTTPUpstreamCatalogRepository.NetworksItemDTO.self, from: json)
        XCTAssertEqual(dto.countryCode, "CN")
        XCTAssertEqual(dto.operatorList.count, 2)
        XCTAssertEqual(dto.operatorList[0], "CMCC")
    }

    func testOperatorsDataDTODecodesCountVariants() throws {
        let json1 = """
        {
          "operators": ["A"],
          "operators_count": 1
        }
        """.data(using: .utf8)!
        let json2 = """
        {
          "operators": ["A","B"],
          "operatorsCount": 2
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        let dto1 = try dec.decode(HTTPUpstreamCatalogRepository.OperatorsDataDTO.self, from: json1)
        let dto2 = try dec.decode(HTTPUpstreamCatalogRepository.OperatorsDataDTO.self, from: json2)
        XCTAssertEqual(dto1.operatorsCount, 1)
        XCTAssertEqual(dto1.operators.first, "A")
        XCTAssertEqual(dto2.operatorsCount, 2)
        XCTAssertEqual(dto2.operators.last, "B")
    }

    func testOrderConsumptionDTODecodesVariousFields() throws {
        let json = """
        {
          "bundle_expiry_date": "1700000200",
          "data_allocated": 1024.0,
          "data_remaining": 512.0,
          "data_unit": "MB",
          "data_used": 512.0,
          "iccid": "ICCID1",
          "minutes_allocated": 100.0,
          "minutes_remaining": 50.0,
          "minutes_used": 50.0,
          "plan_status": "active",
          "policy_status": "ok",
          "profile_status": "enabled",
          "supports_calls_sms": true,
          "unlimited": false,
          "profile_expiry_date": "1700000300"
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamOrderRepository.OrderConsumptionDTO.self, from: json)
        XCTAssertEqual(dto.bundleExpiryDate, "1700000200")
        XCTAssertEqual(dto.dataAllocated, 1024.0)
        XCTAssertEqual(dto.dataRemaining, 512.0)
        XCTAssertEqual(dto.dataUnit, "MB")
        XCTAssertEqual(dto.dataUsed, 512.0)
        XCTAssertEqual(dto.iccid, "ICCID1")
        XCTAssertEqual(dto.minutesAllocated, 100.0)
        XCTAssertEqual(dto.minutesRemaining, 50.0)
        XCTAssertEqual(dto.minutesUsed, 50.0)
        XCTAssertEqual(dto.planStatus, "active")
        XCTAssertEqual(dto.policyStatus, "ok")
        XCTAssertEqual(dto.profileStatus, "enabled")
        XCTAssertEqual(dto.supportsCallsSms, true)
        XCTAssertEqual(dto.unlimited, false)
        XCTAssertEqual(dto.profileExpiryDate, "1700000300")
    }

    func testRefundDataDTODecodesStatesAndStepsStringDates() throws {
        let json = """
        {
          "accepted": true,
          "state": "requested",
          "steps": [
            {"state":"requested","updatedAt":"1700000000","note":"N1"},
            {"state":"reviewing","updatedAt":"2024-01-01 12:00:00"}
          ]
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        let dto = try dec.decode(HTTPUpstreamOrderRepository.RefundDataDTO.self, from: json)
        XCTAssertEqual(dto.accepted, true)
        XCTAssertEqual(dto.state, "requested")
        XCTAssertEqual(dto.steps?.count, 2)
        XCTAssertEqual(dto.steps?.first?.state, "requested")
        XCTAssertEqual(dto.steps?.first?.note, "N1")
    }

    func testQRCodeGeneratorEmptyString() {
        XCTAssertNil(QRCodeGenerator.uiImage(from: ""))
    }
    
    func testBundleDTODecodesSnakeCase() throws {
        let json = """
        {
          "bundle_category": "country",
          "bundle_code": "B100",
          "bundle_marketing_name": "M100",
          "bundle_name": "N100",
          "bundle_tag": ["popular"],
          "country_code": ["CN","US"],
          "country_name": ["中国","美国"],
          "data_unit": "GB",
          "gprs_limit": 5.0,
          "is_active": true,
          "region_code": "asia",
          "region_name": "亚洲",
          "service_type": "data",
          "sms_amount": 0,
          "support_topup": true,
          "supports_calls_sms": false,
          "unlimited": false,
          "validity": 7,
          "voice_amount": 0,
          "reseller_retail_price": 9.99,
          "bundle_price_final": 8.88
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamCatalogRepository.BundleDTO.self, from: json)
        XCTAssertEqual(dto.bundleCategory, "country")
        XCTAssertEqual(dto.bundleCode, "B100")
        XCTAssertEqual(dto.bundleMarketingName, "M100")
        XCTAssertEqual(dto.countryCode.first, "CN")
        XCTAssertEqual(dto.regionCode, "asia")
        XCTAssertEqual(dto.resellerRetailPrice, 9.99, accuracy: 0.0001)
        XCTAssertEqual(dto.bundlePriceFinal, 8.88, accuracy: 0.0001)
        XCTAssertEqual(dto.supportsCallsSms, false)
    }

    func testSimpleBundleDTODecodes() throws {
        let json = """
        {
          "id": "B200",
          "name": "中国香港 5GB/7天",
          "countryCode": "HK",
          "price": 15.5,
          "currency": "HKD",
          "dataAmount": "5GB",
          "validityDays": 7,
          "description": "说明",
          "supportedNetworks": ["CMHK"],
          "hotspotSupported": true,
          "coverageNote": "城市覆盖为主",
          "termsUrl": "https://example.com/terms"
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        let dto = try dec.decode(HTTPUpstreamCatalogRepository.SimpleBundleDTO.self, from: json)
        XCTAssertEqual(dto.id, "B200")
        XCTAssertEqual(dto.countryCode, "HK")
        XCTAssertEqual(dto.price, 15.5, accuracy: 0.0001)
        XCTAssertEqual(dto.currency, "HKD")
        XCTAssertEqual(dto.validityDays, 7)
        XCTAssertEqual(dto.hotspotSupported, true)
        XCTAssertEqual(dto.termsUrl, "https://example.com/terms")
    }

    func testOrderDTODecodesWithInstallation() throws {
        let json = """
        {
          "id": "OIDX",
          "bundleId": "B300",
          "amount": 12.34,
          "currency": "USD",
          "createdAt": "2024-01-01T12:34:56Z",
          "status": "paid",
          "paymentMethod": "paypal",
          "installation": {
            "qrCodeUrl": "https://example.com/qr",
            "activationCode": "ACT1",
            "instructions": ["step1","step2"],
            "profileUrl": "https://example.com/p",
            "smdp": "SMDP1"
          }
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let dto = try dec.decode(HTTPOrderRepository.OrderDTO.self, from: json)
        XCTAssertEqual(dto.id, "OIDX")
        XCTAssertEqual(dto.bundleId, "B300")
        XCTAssertEqual(dto.currency, "USD")
        XCTAssertEqual(dto.status, "paid")
        XCTAssertEqual(dto.paymentMethod, "paypal")
        XCTAssertEqual(dto.installation?.activationCode, "ACT1")
        XCTAssertEqual(dto.installation?.smdp, "SMDP1")
    }

    func testOrderWithUsageItemDTODecodes() throws {
        let json = """
        {
          "order": {
            "id": "OID9",
            "bundleId": "B9",
            "amount": 15.5,
            "currency": "USD",
            "createdAt": "2024-01-02T00:00:00Z",
            "status": "paid",
            "paymentMethod": "paypal"
          },
          "usage": {
            "data_allocated": 500.0,
            "data_remaining": 200.0
          }
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .iso8601
        let dto = try dec.decode(HTTPUpstreamOrderRepository.OrderWithUsageItemDTO.self, from: json)
        XCTAssertEqual(dto.order.id, "OID9")
        XCTAssertEqual(dto.order.bundleId, "B9")
        XCTAssertEqual(dto.order.currency, "USD")
        XCTAssertEqual(dto.usage?.dataAllocated, 500.0)
        XCTAssertEqual(dto.usage?.dataRemaining, 200.0)
    }

    func testOrdersListWithUsageDataDTOCounts() throws {
        let json = """
        {
          "items": [
            {
              "order": {
                "id": "OID10",
                "bundleId": "B10",
                "amount": 10.0,
                "currency": "EUR",
                "createdAt": "2024-02-02T00:00:00Z",
                "status": "paid",
                "paymentMethod": "paypal"
              }
            }
          ],
          "orders_count": 1
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .iso8601
        let dto = try dec.decode(HTTPUpstreamOrderRepository.OrdersListWithUsageDataDTO.self, from: json)
        XCTAssertEqual(dto.ordersCount, 1)
        XCTAssertEqual(dto.items.count, 1)
        XCTAssertEqual(dto.items.first?.order.bundleId, "B10")
    }

    func testLocFallbackReturnsKeyWhenMissing() {
        UserDefaults.standard.set("xx", forKey: "simigo.languageCode")
        let key = "__missing_key__"
        XCTAssertEqual(loc(key), key)
    }

    func testEnvelopeDataDTODecodesInEnvelope() throws {
        let json = """
        {
          "code": 200,
          "msg": "ok",
          "data": {
            "id": "B300",
            "name": "香港 5GB/7天",
            "countryCode": "HKG",
            "price": 15.5,
            "currency": "HKD",
            "dataAmount": "5GB",
            "validityDays": 7,
            "description": "说明",
            "supportedNetworks": ["CMHK"],
            "hotspotSupported": true,
            "coverageNote": "城市覆盖",
            "termsUrl": "https://example.com/terms",
            "bundleTag": ["popular"],
            "isActive": true,
            "serviceType": "data",
            "supportTopup": true,
            "unlimited": false
          }
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        let env = try dec.decode(Envelope<HTTPUpstreamCatalogRepository.EnvelopeDataDTO>.self, from: json)
        XCTAssertEqual(env.code, 200)
        XCTAssertEqual(env.msg, "ok")
        XCTAssertEqual(env.data.id, "B300")
        XCTAssertEqual(env.data.countryCode, "HKG")
        XCTAssertEqual(env.data.currency, "HKD")
        XCTAssertEqual(env.data.validityDays, 7)
    }

    func testLocEnglish() {
        UserDefaults.standard.set("en", forKey: "simigo.languageCode")
        XCTAssertEqual(loc("商店"), "Store")
    }

    func testLocChineseSimplified() {
        UserDefaults.standard.set("zh-cn", forKey: "simigo.languageCode")
        XCTAssertEqual(loc("商店"), "商店")
    }

    func testBundleListDataDTODecodesObject() throws {
        let json = """
        {
          "bundles": [
            {
              "bundle_category": "country",
              "bundle_code": "B1",
              "bundle_marketing_name": "M1",
              "bundle_name": "N1",
              "bundle_tag": [],
              "country_code": ["US"],
              "country_name": ["美国"],
              "data_unit": "GB",
              "gprs_limit": 5.0,
              "is_active": true,
              "region_code": "america",
              "region_name": "美洲",
              "service_type": "data",
              "sms_amount": 0,
              "support_topup": true,
              "supports_calls_sms": false,
              "unlimited": false,
              "validity": 7,
              "voice_amount": 0,
              "reseller_retail_price": 10.0,
              "bundle_price_final": 9.0
            }
          ],
          "bundlesCount": 1
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamCatalogRepository.BundleListDataDTO.self, from: json)
        XCTAssertEqual(dto.bundles.count, 1)
        XCTAssertEqual(dto.bundlesCount, 1)
        XCTAssertEqual(dto.bundles.first?.bundleCode, "B1")
    }

    func testBundleListDataDTODecodesArray() throws {
        let json = """
        [
          {
            "bundle_category": "country",
            "bundle_code": "B1",
            "bundle_marketing_name": "M1",
            "bundle_name": "N1",
            "bundle_tag": [],
            "country_code": ["US"],
            "country_name": ["美国"],
            "data_unit": "GB",
            "gprs_limit": 5.0,
            "is_active": true,
            "region_code": "america",
            "region_name": "美洲",
            "service_type": "data",
            "sms_amount": 0,
            "support_topup": true,
            "supports_calls_sms": false,
            "unlimited": false,
            "validity": 7,
            "voice_amount": 0,
            "reseller_retail_price": 10.0,
            "bundle_price_final": 9.0
          },
          {
            "bundle_category": "country",
            "bundle_code": "B2",
            "bundle_marketing_name": "M2",
            "bundle_name": "N2",
            "bundle_tag": [],
            "country_code": ["CN"],
            "country_name": ["中国"],
            "data_unit": "GB",
            "gprs_limit": 5.0,
            "is_active": true,
            "service_type": "data",
            "sms_amount": 0,
            "support_topup": true,
            "supports_calls_sms": false,
            "unlimited": false,
            "validity": 15,
            "voice_amount": 0,
            "reseller_retail_price": 20.0,
            "bundle_price_final": 18.0
          }
        ]
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try dec.decode(HTTPUpstreamCatalogRepository.BundleListDataDTO.self, from: json)
        XCTAssertEqual(dto.bundles.count, 2)
        XCTAssertEqual(dto.bundlesCount, 2)
        XCTAssertEqual(dto.bundles.last?.bundleCode, "B2")
    }

    func testBundleAssignResultDTODecodes() throws {
        let json = """
        {"orderId":"OIDASSIGN","iccid":"ICCIDX"}
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        let dto = try dec.decode(HTTPUpstreamCatalogRepository.BundleAssignResultDTO.self, from: json)
        XCTAssertEqual(dto.orderId, "OIDASSIGN")
        XCTAssertEqual(dto.iccid, "ICCIDX")
    }

    func testEnvelopeMetaDecodes() throws {
        let json = """
        {"code":201,"msg":"ok"}
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        let meta = try dec.decode(EnvelopeMeta.self, from: json)
        XCTAssertEqual(meta.code, 201)
        XCTAssertEqual(meta.msg, "ok")
    }

    func testNetworkMonitorBackendReachabilityToggle() {
        NetworkMonitor.shared.reportBackendReachable(false)
        XCTAssertEqual(NetworkMonitor.shared.backendOnline, false)
        NetworkMonitor.shared.reportBackendReachable(true)
        XCTAssertEqual(NetworkMonitor.shared.backendOnline, true)
    }

    func testPriceFormatterUsesSelectedCurrency() {
        UserDefaults.standard.set("usd", forKey: "simigo.currencyCode")
        let amount = Decimal(string: "1234.56")!
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "USD"
        let expected = nf.string(from: amount as NSDecimalNumber)
        let actual = PriceFormatter.string(amount: amount, currencyCode: "EUR")
        XCTAssertEqual(actual, expected)
    }

    func testPriceFormatterFallsBackToPassedCurrency() {
        UserDefaults.standard.set("ABC", forKey: "simigo.currencyCode")
        let amount = Decimal(string: "99.5")!
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "EUR"
        let expected = nf.string(from: amount as NSDecimalNumber)
        let actual = PriceFormatter.string(amount: amount, currencyCode: "EUR")
        XCTAssertEqual(actual, expected)
    }

    func testSelectedCurrencyAllowed() {
        UserDefaults.standard.set("gbp", forKey: "simigo.currencyCode")
        let actual = selectedCurrency(fallback: "USD")
        XCTAssertEqual(actual, "GBP")
    }

    func testSelectedCurrencyFallback() {
        UserDefaults.standard.set("zzz", forKey: "simigo.currencyCode")
        let actual = selectedCurrency(fallback: "HKD")
        XCTAssertEqual(actual, "HKD")
    }

    func testSafePageSizeCatalog() {
        let repo = HTTPUpstreamCatalogRepository()
        XCTAssertEqual(repo.safePageSize(10), 10)
        XCTAssertEqual(repo.safePageSize(999), 25)
    }

    func testSafePageSizeAgent() {
        let repo = HTTPUpstreamAgentRepository()
        XCTAssertEqual(repo.safePageSize(50), 50)
        XCTAssertEqual(repo.safePageSize(7), 25)
    }
}
