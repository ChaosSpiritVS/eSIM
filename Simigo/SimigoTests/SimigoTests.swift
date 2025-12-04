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

    func testOrderDetailEnvelopeSnakeCaseDecodes() throws {
        let json = """
        {
          "code": 200,
          "msg": "ok",
          "data": {
            "order_id": "OID999",
            "order_reference": "REF999",
            "bundle_category": "data",
            "bundle_code": "B999",
            "bundle_marketing_name": "M",
            "bundle_name": "N",
            "country_code": ["HK"],
            "country_name": ["中国香港"],
            "order_status": "paid",
            "activation_code": "ACT-XYZ",
            "smdp_address": "SM-DP+",
            "bundle_expiry_date": "1700000000",
            "expiry_date": "1700005000",
            "iccid": "ICCID123",
            "plan_started": true,
            "plan_status": "active",
            "date_created": 1699999999123
          }
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let env = try dec.decode(Envelope<HTTPUpstreamOrderRepository.OrderDetailDTO>.self, from: json)
        XCTAssertEqual(env.code, 200)
        XCTAssertEqual(env.msg, "ok")
        XCTAssertEqual(env.data.orderId, "OID999")
        XCTAssertEqual(env.data.orderReference, "REF999")
        XCTAssertEqual(env.data.bundleCode, "B999")
        XCTAssertEqual(env.data.countryCode?.first, "HK")
        XCTAssertEqual(env.data.countryName?.first, "中国香港")
        XCTAssertEqual(env.data.orderStatus, "paid")
        XCTAssertEqual(env.data.activationCode, "ACT-XYZ")
        XCTAssertEqual(env.data.smdpAddress, "SM-DP+")
        XCTAssertEqual(env.data.iccid, "ICCID123")
        XCTAssertEqual(env.data.planStarted, true)
        XCTAssertEqual(env.data.planStatus, "active")
    }

    func testGsalaryConsultDTODecodes() throws {
        let json = """
        {
          "payment_options": [
            {
              "payment_method_type": "card",
              "payment_method_logo_name": "visa",
              "payment_method_logo_url": "https://logo.example/visa.png",
              "payment_method_category": "bank_card",
              "payment_method_region": ["HK"],
              "support_card_brands": [
                { "card_brand": "VISA", "brand_logo_name": "visa", "brand_logo_url": "https://logo.example/visa.png" }
              ],
              "card_funding": ["credit"]
            }
          ]
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        let dto = try dec.decode(PaymentPreparationService.GsalaryConsultDTO.self, from: json)
        XCTAssertEqual(dto.payment_options.count, 1)
        let opt = dto.payment_options.first!
        XCTAssertEqual(opt.payment_method_type, "card")
        XCTAssertEqual(opt.payment_method_category, "bank_card")
        XCTAssertEqual(opt.payment_method_region?.first, "HK")
        XCTAssertEqual(opt.support_card_brands?.first?.card_brand, "VISA")
    }

    func testGsalaryCreateDTODecodes() throws {
        let json = """
        {
          "checkoutUrl": "https://api.gsalary.com/checkout?pid=GSALARY-card-ORD-1",
          "paymentId": "PAY-ORD-1",
          "paymentMethodId": "PM-xyz",
          "paymentRequestId": "PAY_ORD_1"
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        let dto = try dec.decode(PaymentPreparationService.GsalaryCreateDTO.self, from: json)
        XCTAssertEqual(dto.checkoutUrl, "https://api.gsalary.com/checkout?pid=GSALARY-card-ORD-1")
        XCTAssertEqual(dto.paymentId, "PAY-ORD-1")
        XCTAssertEqual(dto.paymentMethodId, "PM-xyz")
        XCTAssertEqual(dto.paymentRequestId, "PAY_ORD_1")
    }

    func testGsalaryPayDTODecodesWithSchemeAndApplink() throws {
        let json = """
        {
          "checkoutUrl": "https://api.gsalary.com/checkout?pid=GSALARY-alipay-ORD-2",
          "paymentId": "PAY-ORD-2",
          "schemeUrl": "alipay://pay?id=PAY-ORD-2",
          "applinkUrl": "https://alipay.example/app?id=PAY-ORD-2",
          "appIdentifier": "com.alipay.app"
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        let dto = try dec.decode(PaymentPreparationService.GsalaryPayDTO.self, from: json)
        XCTAssertEqual(dto.paymentId, "PAY-ORD-2")
        XCTAssertEqual(dto.checkoutUrl, "https://api.gsalary.com/checkout?pid=GSALARY-alipay-ORD-2")
        XCTAssertEqual(dto.schemeUrl, "alipay://pay?id=PAY-ORD-2")
        XCTAssertEqual(dto.applinkUrl, "https://alipay.example/app?id=PAY-ORD-2")
        XCTAssertEqual(dto.appIdentifier, "com.alipay.app")
    }
}
