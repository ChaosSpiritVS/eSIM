//
//  SimigoUITests.swift
//  SimigoUITests
//
//  Created by 李杰 on 2025/10/31.
//

import XCTest

final class SimigoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAccountOrdersNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        let profileTab = app.tabBars.buttons["tab.account"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        let ordersCell = app.tables.staticTexts["订单"].firstMatch
        XCTAssertTrue(ordersCell.waitForExistence(timeout: 5))
        ordersCell.tap()
        XCTAssertTrue(app.navigationBars["订单"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCheckoutFlowNavigatesToOrderDetail() throws {
        let app = XCUIApplication()
        app.launch()
        let profileTab = app.tabBars.buttons["tab.account"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        let loginRegister = app.tables.staticTexts["登录 / 注册"].firstMatch
        XCTAssertTrue(loginRegister.waitForExistence(timeout: 5))
        loginRegister.tap()
        let appleDev = app.staticTexts["使用模拟 Apple 登录（开发）"].firstMatch
        XCTAssertTrue(appleDev.waitForExistence(timeout: 5))
        appleDev.tap()
        let cancelBtn = app.buttons["取消"].firstMatch
        if cancelBtn.waitForExistence(timeout: 8) { cancelBtn.tap() }
        let marketTab = app.tabBars.buttons["tab.market"]
        XCTAssertTrue(marketTab.waitForExistence(timeout: 5))
        marketTab.tap()
        let hkBundle = app.staticTexts["中国香港"].firstMatch
        XCTAssertTrue(hkBundle.waitForExistence(timeout: 10))
        hkBundle.tap()
        let toCheckout = app.staticTexts["立即购买"].firstMatch
        XCTAssertTrue(toCheckout.waitForExistence(timeout: 5))
        toCheckout.tap()
        let buyNow = app.buttons["立即购买"].firstMatch
        XCTAssertTrue(buyNow.waitForExistence(timeout: 5))
        buyNow.tap()
        let orderIdLabel = app.staticTexts["订单ID"].firstMatch
        XCTAssertTrue(orderIdLabel.waitForExistence(timeout: 10))
    }

    @MainActor
    func testOrdersListAfterLoginAndLogout() throws {
        let app = XCUIApplication()
        app.launch()
        let profileTab = app.tabBars.buttons["个人资料"].firstMatch
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        let loginRegister = app.tables.staticTexts["登录 / 注册"].firstMatch
        XCTAssertTrue(loginRegister.waitForExistence(timeout: 5))
        loginRegister.tap()
        let appleDev = app.staticTexts["使用模拟 Apple 登录（开发）"].firstMatch
        XCTAssertTrue(appleDev.waitForExistence(timeout: 5))
        appleDev.tap()
        let cancelBtn = app.buttons["取消"].firstMatch
        if cancelBtn.waitForExistence(timeout: 8) { cancelBtn.tap() }
        let ordersCell = app.tables.staticTexts["订单"].firstMatch
        XCTAssertTrue(ordersCell.waitForExistence(timeout: 10))
        ordersCell.tap()
        XCTAssertTrue(app.navigationBars["订单"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let logoutBtn = app.tables.staticTexts["退出"].firstMatch
        XCTAssertTrue(logoutBtn.waitForExistence(timeout: 5))
        logoutBtn.tap()
        let confirmLogout = app.buttons["退出"].firstMatch
        XCTAssertTrue(confirmLogout.waitForExistence(timeout: 5))
        confirmLogout.tap()
        let loginRegisterAgain = app.tables.staticTexts["登录 / 注册"].firstMatch
        XCTAssertTrue(loginRegisterAgain.waitForExistence(timeout: 10))
    }
}
