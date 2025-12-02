//
//  SimigoUITests.swift
//  SimigoUITests
//
//  Created by 李杰 on 2025/10/31.
//

import XCTest

final class SimigoUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    @MainActor
    func testSupportLegalNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        // 切换到“个人资料”标签
        let profileTab = app.tabBars.buttons["tab.account"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()

        // 进入“客服与支持”
        let supportFab = app.buttons["support.fab"].firstMatch
        XCTAssertTrue(supportFab.waitForExistence(timeout: 5))
        supportFab.tap()

        // 进入“隐私政策”
        let privacyCell = app.tables.staticTexts["隐私政策"].firstMatch
        XCTAssertTrue(privacyCell.waitForExistence(timeout: 5))
        privacyCell.tap()

        // 验证导航到隐私政策页面
        XCTAssertTrue(app.navigationBars["隐私政策"].waitForExistence(timeout: 5))

        // 返回 Support
        app.navigationBars.buttons.firstMatch.tap()

        // 进入“服务条款”
        let termsCell = app.tables.staticTexts["服务条款"].firstMatch
        XCTAssertTrue(termsCell.waitForExistence(timeout: 5))
        termsCell.tap()

        // 验证导航到服务条款页面
        XCTAssertTrue(app.navigationBars["服务条款"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAccountOrdersNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        // 切换到“个人资料”标签
        let profileTab = app.tabBars.buttons["tab.account"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()

        // 进入“订单”
        let ordersCell = app.tables.staticTexts["订单"].firstMatch
        XCTAssertTrue(ordersCell.waitForExistence(timeout: 5))
        ordersCell.tap()

        // 验证导航到订单列表页面
        XCTAssertTrue(app.navigationBars["订单"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCheckoutFlowNavigatesToOrderDetail() throws {
        let app = XCUIApplication()
        app.launch()

        // 在商城选择任一热门套餐（使用中文 Mock 数据：例如“中国香港”）
        let hkBundle = app.staticTexts["中国香港"].firstMatch
        XCTAssertTrue(hkBundle.waitForExistence(timeout: 10))
        hkBundle.tap()

        // 进入结算页
        let toCheckout = app.staticTexts["立即购买"].firstMatch
        XCTAssertTrue(toCheckout.waitForExistence(timeout: 5))
        toCheckout.tap()

        // 结算页下单
        let buyNow = app.buttons["立即购买"].firstMatch
        XCTAssertTrue(buyNow.waitForExistence(timeout: 5))
        buyNow.tap()

        // 等待跳转到订单详情（Mock 流程会自动支付）
        let orderIdLabel = app.staticTexts["订单ID"].firstMatch
        XCTAssertTrue(orderIdLabel.waitForExistence(timeout: 10))
    }

    @MainActor
    func testCheckoutTermsLinkNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        // 在商城进入某套餐详情
        let hkBundle = app.staticTexts["中国香港"].firstMatch
        XCTAssertTrue(hkBundle.waitForExistence(timeout: 10))
        hkBundle.tap()

        // 跳转到结算页
        let toCheckout = app.staticTexts["立即购买"].firstMatch
        XCTAssertTrue(toCheckout.waitForExistence(timeout: 5))
        toCheckout.tap()

        // 查找并点击“查看服务条款”导航链接（可能需要滚动）
        var termsLink = app.staticTexts["查看服务条款"].firstMatch
        var attempts = 0
        while !termsLink.exists && attempts < 5 {
            app.swipeUp()
            termsLink = app.staticTexts["查看服务条款"].firstMatch
            attempts += 1
        }
        XCTAssertTrue(termsLink.waitForExistence(timeout: 5))
        termsLink.tap()

        // 验证导航到服务条款页面内容/标题
        let termsTitle = app.navigationBars["服务条款"].firstMatch
        let termsIntro = app.staticTexts["服务条款简介"].firstMatch
        XCTAssertTrue(termsTitle.waitForExistence(timeout: 5) || termsIntro.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSupportPrivacyEnglishLocalization() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        // 切换到 Profile 标签
        let profileTabEN = app.tabBars.buttons["tab.account"].firstMatch
        XCTAssertTrue(profileTabEN.waitForExistence(timeout: 5))
        profileTabEN.tap()

        // 进入 Support
        let supportFabEN = app.buttons["support.fab"].firstMatch
        XCTAssertTrue(supportFabEN.waitForExistence(timeout: 5))
        supportFabEN.tap()

        // 进入 Privacy Policy
        let privacyCellEN = app.tables.staticTexts["Privacy Policy"].firstMatch
        XCTAssertTrue(privacyCellEN.waitForExistence(timeout: 5))
        privacyCellEN.tap()

        // 验证英文页面是否正常显示
        let privacyNavEN = app.navigationBars["Privacy Policy"].firstMatch
        let privacyIntroEN = app.staticTexts["Privacy Policy Overview"].firstMatch
        XCTAssertTrue(privacyNavEN.waitForExistence(timeout: 5) || privacyIntroEN.waitForExistence(timeout: 5))
    }

    @MainActor
    func testAuthAppleDevLoginFromAccount() throws {
        let app = XCUIApplication()
        app.launch()

        let profileTab = app.tabBars.buttons["tab.account"].firstMatch
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

        let logoutBtn = app.tables.staticTexts["退出"].firstMatch
        XCTAssertTrue(logoutBtn.waitForExistence(timeout: 10))
    }

    @MainActor
    func testSettingsLanguageAndCurrencyChange() throws {
        let app = XCUIApplication()
        app.launch()

        let profileTab = app.tabBars.buttons["个人资料"].firstMatch
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()

        let langRow = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "语言：")).firstMatch
        XCTAssertTrue(langRow.waitForExistence(timeout: 5))
        langRow.tap()

        let english = app.tables.staticTexts["English"].firstMatch
        if english.waitForExistence(timeout: 5) { english.tap() }
        let changeBtn = app.buttons["更改"].firstMatch
        if changeBtn.waitForExistence(timeout: 5) { changeBtn.tap() }

        let currencyRow = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "货币：")).firstMatch
        XCTAssertTrue(currencyRow.waitForExistence(timeout: 5))
        currencyRow.tap()

        let gbp = app.tables.staticTexts["英镑 (GBP)"].firstMatch
        if gbp.waitForExistence(timeout: 5) { gbp.tap() }
        let changeCur = app.buttons["更改"].firstMatch
        if changeCur.waitForExistence(timeout: 5) { changeCur.tap() }
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

    @MainActor
    func testAuthForgotPasswordAndConfirmFlow() throws {
        let app = XCUIApplication()
        app.launch()

        let profileTab = app.tabBars.buttons["个人资料"].firstMatch
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()

        let loginRegister = app.tables.staticTexts["登录 / 注册"].firstMatch
        XCTAssertTrue(loginRegister.waitForExistence(timeout: 5))
        loginRegister.tap()

        let forgot = app.buttons["忘记密码"].firstMatch
        XCTAssertTrue(forgot.waitForExistence(timeout: 5))
        forgot.tap()

        let sendReset = app.buttons["发送重置邮件"].firstMatch
        XCTAssertTrue(sendReset.waitForExistence(timeout: 5))

        let toConfirm = app.staticTexts["我已有重置令牌，去设置新密码"].firstMatch
        XCTAssertTrue(toConfirm.waitForExistence(timeout: 5))
        toConfirm.tap()

        let tokenField = app.textFields["重置令牌"].firstMatch
        XCTAssertTrue(tokenField.waitForExistence(timeout: 5))

        let cancelBtn = app.buttons["取消"].firstMatch
        XCTAssertTrue(cancelBtn.waitForExistence(timeout: 5))
        cancelBtn.tap()

        let cancelBtn2 = app.buttons["取消"].firstMatch
        XCTAssertTrue(cancelBtn2.waitForExistence(timeout: 5))
        cancelBtn2.tap()
    }

    @MainActor
    func testAuthRegisterTermsAndPrivacySheets() throws {
        let app = XCUIApplication()
        app.launch()

        let profileTab = app.tabBars.buttons["个人资料"].firstMatch
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()

        let loginRegister = app.tables.staticTexts["登录 / 注册"].firstMatch
        XCTAssertTrue(loginRegister.waitForExistence(timeout: 5))
        loginRegister.tap()

        let registerSeg = app.segmentedControls.buttons["注册"].firstMatch
        XCTAssertTrue(registerSeg.waitForExistence(timeout: 5))
        registerSeg.tap()

        let tos = app.buttons["条款与条件"].firstMatch
        XCTAssertTrue(tos.waitForExistence(timeout: 5))
        tos.tap()
        let termsTitle = app.navigationBars["服务条款"].firstMatch
        let termsIntro = app.staticTexts["服务条款简介"].firstMatch
        XCTAssertTrue(termsTitle.waitForExistence(timeout: 5) || termsIntro.waitForExistence(timeout: 5))
        app.buttons["取消"].firstMatch.tap()

        let privacy = app.buttons["隐私政策"].firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        privacy.tap()
        let privacyTitle = app.navigationBars["隐私政策"].firstMatch
        let privacyIntro = app.staticTexts["隐私政策简介"].firstMatch
        XCTAssertTrue(privacyTitle.waitForExistence(timeout: 5) || privacyIntro.waitForExistence(timeout: 5))
        app.buttons["取消"].firstMatch.tap()
    }

    @MainActor
    func testAccountSupportOverlayOpensSupport() throws {
        let app = XCUIApplication()
        app.launch()

        let profileTab = app.tabBars.buttons["个人资料"].firstMatch
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()

        let overlay = app.buttons["message"].firstMatch
        if overlay.waitForExistence(timeout: 5) {
            overlay.tap()
        } else {
            let supportCell = app.tables.staticTexts["客服与支持"].firstMatch
            XCTAssertTrue(supportCell.waitForExistence(timeout: 5))
            supportCell.tap()
        }
        let title = app.staticTexts["帮助与支持"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.buttons["取消"].firstMatch.tap()
    }

    @MainActor
    func testAccountMoreInfoNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        let profileTab = app.tabBars.buttons["个人资料"].firstMatch
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()

        let more = app.tables.staticTexts["更多信息"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()

        let about = app.tables.staticTexts["关于"].firstMatch
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.tap()
        XCTAssertTrue(app.navigationBars["关于"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        let privacy = app.tables.staticTexts["隐私政策"].firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        privacy.tap()
        XCTAssertTrue(app.navigationBars["隐私政策"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        let terms = app.tables.staticTexts["服务条款"].firstMatch
        XCTAssertTrue(terms.waitForExistence(timeout: 5))
        terms.tap()
        XCTAssertTrue(app.navigationBars["服务条款"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        let agent = app.tables.staticTexts["代理商中心"].firstMatch
        XCTAssertTrue(agent.waitForExistence(timeout: 5))
        agent.tap()
        XCTAssertTrue(app.navigationBars["代理商中心"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBundleInfoSheetOpensAndDismisses() throws {
        let app = XCUIApplication()
        app.launch()

        let hkBundle = app.staticTexts["中国香港"].firstMatch
        XCTAssertTrue(hkBundle.waitForExistence(timeout: 10))
        hkBundle.tap()

        let infoBtn = app.buttons["套餐详细信息"].firstMatch
        XCTAssertTrue(infoBtn.waitForExistence(timeout: 5))
        infoBtn.tap()

        let cancel = app.buttons["取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
    }

    @MainActor
    func testSupportInstallationGuideOpens() throws {
        let app = XCUIApplication()
        app.launch()

        let profileTab = app.tabBars.buttons["个人资料"].firstMatch
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()

        let supportCell = app.tables.staticTexts["客服与支持"].firstMatch
        XCTAssertTrue(supportCell.waitForExistence(timeout: 5))
        supportCell.tap()

        let guide = app.tables.staticTexts["eSIM 安装指南"].firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        guide.tap()

        let tutorialHeader = app.staticTexts["安装教程"].firstMatch
        let connectHeader = app.staticTexts["连接到网络"].firstMatch
        XCTAssertTrue(tutorialHeader.waitForExistence(timeout: 5) || connectHeader.waitForExistence(timeout: 5))
    }

    @MainActor
    func testAppleContinueSaveProfile() throws {
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

        let nameField = app.textFields["名字"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 8))
        nameField.tap()
        nameField.typeText("小明")

        let lastNameField = app.textFields["姓氏（可选）"].firstMatch
        if lastNameField.waitForExistence(timeout: 5) {
            lastNameField.tap()
            lastNameField.typeText("张")
        }

        let cont = app.buttons["继续"].firstMatch
        XCTAssertTrue(cont.waitForExistence(timeout: 5))
        cont.tap()

        XCTAssertFalse(cont.waitForExistence(timeout: 5))
    }

    @MainActor
    func testAccountCreatePasswordAndEditEmailSheetOpen() throws {
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

        let infoCell = app.tables.staticTexts["账号信息"].firstMatch
        XCTAssertTrue(infoCell.waitForExistence(timeout: 10))
        infoCell.tap()

        let createPw = app.buttons["创建密码"].firstMatch
        XCTAssertTrue(createPw.waitForExistence(timeout: 5))
        createPw.tap()

        let pw1 = app.secureTextFields["新密码（至少 8 位，含大小写/数字/符号）"].firstMatch
        let pw2 = app.secureTextFields["确认新密码"].firstMatch
        XCTAssertTrue(pw1.waitForExistence(timeout: 5))
        XCTAssertTrue(pw2.waitForExistence(timeout: 5))
        pw1.tap(); pw1.typeText("Abcdef1!")
        pw2.tap(); pw2.typeText("Abcdef1!")

        let savePw = app.buttons["保存密码"].firstMatch
        XCTAssertTrue(savePw.waitForExistence(timeout: 5))
        savePw.tap()

        let editEmail = app.buttons["编辑邮箱"].firstMatch
        XCTAssertTrue(editEmail.waitForExistence(timeout: 8))
        editEmail.tap()

        let cancel = app.buttons["取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
    }

    @MainActor
    func testAccountDeleteSheetOpenAndCancel() throws {
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

        let infoCell = app.tables.staticTexts["账号信息"].firstMatch
        XCTAssertTrue(infoCell.waitForExistence(timeout: 10))
        infoCell.tap()

        let deleteEntry = app.staticTexts["删除账户"].firstMatch
        XCTAssertTrue(deleteEntry.waitForExistence(timeout: 5))
        deleteEntry.tap()

        let confirmDelete = app.buttons["确认删除"].firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))

        let cancel = app.buttons["取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
    }

    @MainActor
    func testMarketplaceSearchNoResultsOverlayAndClear() throws {
        let app = XCUIApplication()
        app.launch()

        let marketTab = app.tabBars.buttons["商城"].firstMatch
        XCTAssertTrue(marketTab.waitForExistence(timeout: 5))
        marketTab.tap()

        let searchField = app.textFields["您需要哪里的 eSIM?"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("zzzzzzzzzz")

        let noResult = app.staticTexts["未找到相关内容"].firstMatch
        XCTAssertTrue(noResult.waitForExistence(timeout: 5))

        let clearBtn = app.buttons["退出编辑"].firstMatch
        XCTAssertTrue(clearBtn.waitForExistence(timeout: 5))
        clearBtn.tap()
    }

    @MainActor
    func testOrderDetailOpensInstallationGuide() throws {
        let app = XCUIApplication()
        app.launch()

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

        let guideBtn = app.buttons["查看 eSIM 安装指南"].firstMatch
        XCTAssertTrue(guideBtn.waitForExistence(timeout: 5))
        guideBtn.tap()

        let tutorialHeader = app.staticTexts["安装教程"].firstMatch
        XCTAssertTrue(tutorialHeader.waitForExistence(timeout: 5))
    }

    @MainActor
    func testOrderDetailCopyActivationAndSmdp() throws {
        let app = XCUIApplication()
        app.launch()

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

        let copyCode = app.buttons["复制激活码"].firstMatch
        if copyCode.waitForExistence(timeout: 6) {
            copyCode.tap()
            let copied = app.alerts["已复制激活码"].firstMatch
            XCTAssertTrue(copied.waitForExistence(timeout: 5))
            copied.buttons["好的"].firstMatch.tap()
        }

        let copySmdp = app.buttons["复制 SM-DP+ 地址"].firstMatch
        if copySmdp.waitForExistence(timeout: 6) {
            copySmdp.tap()
            let copiedS = app.alerts["已复制 SM-DP+ 地址"].firstMatch
            XCTAssertTrue(copiedS.waitForExistence(timeout: 5))
            copiedS.buttons["好的"].firstMatch.tap()
        }
    }

    @MainActor
    func testOrderRefundSheetOpenAndCancel() throws {
        let app = XCUIApplication()
        app.launch()

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

        let refundBtn = app.buttons["申请退款"].firstMatch
        XCTAssertTrue(refundBtn.waitForExistence(timeout: 5))
        refundBtn.tap()

        let reasonField = app.textFields["请输入退款原因"].firstMatch
        XCTAssertTrue(reasonField.waitForExistence(timeout: 5))
        let submitBtn = app.buttons["提交退款申请"].firstMatch
        XCTAssertTrue(submitBtn.waitForExistence(timeout: 5))

        reasonField.tap(); reasonField.typeText("abc")
        XCTAssertFalse(submitBtn.isEnabled)
        reasonField.typeText("de")
        XCTAssertTrue(submitBtn.isEnabled)

        let cancel = app.buttons["取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
    }

    @MainActor
    func testOrderDetailRedirectToEsimDetail() throws {
        let app = XCUIApplication()
        app.launch()

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

        let goEsim = app.buttons["前往我的 eSIM 查看安装与用量"].firstMatch
        XCTAssertTrue(goEsim.waitForExistence(timeout: 5))
        goEsim.tap()

        let installHeader = app.staticTexts["安装信息"].firstMatch
        XCTAssertTrue(installHeader.waitForExistence(timeout: 5))
    }

    @MainActor
    func testAgentCenterFilterButtonExists() throws {
        let app = XCUIApplication()
        app.launch()

        let profileTab = app.tabBars.buttons["个人资料"].firstMatch
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()

        let more = app.tables.staticTexts["更多信息"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()

        let agent = app.tables.staticTexts["代理商中心"].firstMatch
        XCTAssertTrue(agent.waitForExistence(timeout: 5))
        agent.tap()

        let filterBtn = app.buttons["筛选账单"].firstMatch
        XCTAssertTrue(filterBtn.waitForExistence(timeout: 8))
        filterBtn.tap()
    }

    @MainActor
    func testOrderRefundSubmitShowsSuccessAndProgress() throws {
        let app = XCUIApplication()
        app.launch()

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

        let refundBtn = app.buttons["申请退款"].firstMatch
        XCTAssertTrue(refundBtn.waitForExistence(timeout: 5))
        refundBtn.tap()

        let reasonField = app.textFields["请输入退款原因"].firstMatch
        XCTAssertTrue(reasonField.waitForExistence(timeout: 5))
        reasonField.tap()
        reasonField.typeText("abcdef")

        let submitBtn = app.buttons["提交退款申请"].firstMatch
        XCTAssertTrue(submitBtn.waitForExistence(timeout: 5))
        XCTAssertTrue(submitBtn.isEnabled)
        submitBtn.tap()

        let okText = app.staticTexts["退款申请已提交"].firstMatch
        XCTAssertTrue(okText.waitForExistence(timeout: 8))

        let accepted = app.staticTexts["已受理"].firstMatch
        XCTAssertTrue(accepted.waitForExistence(timeout: 8))
    }

    @MainActor
    func testEsimUsageRefreshButtonTap() throws {
        let app = XCUIApplication()
        app.launch()

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

        let goEsim = app.buttons["前往我的 eSIM 查看安装与用量"].firstMatch
        XCTAssertTrue(goEsim.waitForExistence(timeout: 6))
        goEsim.tap()

        let refreshBtn = app.buttons["刷新用量"].firstMatch
        XCTAssertTrue(refreshBtn.waitForExistence(timeout: 6))
        refreshBtn.tap()

        let lastUpdated = app.staticTexts["最后更新"].firstMatch
        XCTAssertTrue(lastUpdated.waitForExistence(timeout: 6))
    }

    @MainActor
    func testMarketplaceViewMoreNavigatesAndLoadMore() throws {
        let app = XCUIApplication()
        app.launch()

        let marketTab = app.tabBars.buttons["商城"].firstMatch
        XCTAssertTrue(marketTab.waitForExistence(timeout: 5))
        marketTab.tap()

        var viewMore = app.staticTexts["查看更多"].firstMatch
        var attempts = 0
        while !viewMore.exists && attempts < 8 {
            app.swipeUp()
            viewMore = app.staticTexts["查看更多"].firstMatch
            attempts += 1
        }
        XCTAssertTrue(viewMore.waitForExistence(timeout: 8))
        viewMore.tap()

        var loadMore = app.buttons["加载更多"].firstMatch
        attempts = 0
        while !loadMore.exists && attempts < 8 {
            app.swipeUp()
            loadMore = app.buttons["加载更多"].firstMatch
            attempts += 1
        }
        XCTAssertTrue(loadMore.waitForExistence(timeout: 8))
        loadMore.tap()
    }

    @MainActor
    func testOrdersRowSwipeActionsContinueOrRetry() throws {
        let app = XCUIApplication()
        app.launch()

        let profileTab = app.tabBars.buttons["个人资料"].firstMatch
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()

        let ordersCell = app.tables.staticTexts["订单"].firstMatch
        XCTAssertTrue(ordersCell.waitForExistence(timeout: 8))
        ordersCell.tap()
        XCTAssertTrue(app.navigationBars["订单"].waitForExistence(timeout: 5))

        var inline = app.buttons["继续支付"].firstMatch
        if inline.waitForExistence(timeout: 4) {
            inline.tap()
        } else {
            inline = app.buttons["重试支付"].firstMatch
            if inline.waitForExistence(timeout: 4) {
                inline.tap()
            } else {
                let firstRow = app.tables.cells.firstMatch
                XCTAssertTrue(firstRow.waitForExistence(timeout: 6))
                firstRow.swipeLeft()
                var swipeBtn = app.buttons["继续支付"].firstMatch
                if swipeBtn.waitForExistence(timeout: 4) { swipeBtn.tap() }
                else {
                    swipeBtn = app.buttons["重试支付"].firstMatch
                    if swipeBtn.waitForExistence(timeout: 4) { swipeBtn.tap() }
                }
            }
        }
    }
}
