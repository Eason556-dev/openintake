import XCTest
@testable import IntakeCore
import IntakeShared

final class DashboardTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Toronto")!; return c }
    var date: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))! }
    func event(_ amounts: [NutrientAmount], servings: Double = 1) throws -> IntakeEvent {
        try IntakeEvent(product: Product(name: "Synthetic test", serving: "1 serving", nutrients: amounts, confirmedAt: date), servings: servings, date: date)
    }
    func build(_ events: [IntakeEvent], goals: [DashboardMetric: Double] = [:]) -> DashboardSnapshot {
        DashboardBuilder.build(events: events, goals: goals, language: "en", date: date, calendar: calendar)
    }
    func testUnknownIsNotZeroAndKnownZeroRemainsZero() throws {
        let snapshot = build([try event([.init(.sugar, 0, .g)])])
        XCTAssertEqual(snapshot.metric(.sugar, at: date, calendar: calendar).value, 0)
        XCTAssertNil(snapshot.metric(.protein, at: date, calendar: calendar).value)
    }
    func testServingAndUnitConversionPreservesEstimates() throws {
        let snapshot = build([try event([.init(.water, 0.25, .L), .init(.sodium, 0.5, .g), .init(.protein, 10, .g, origin: .aiEstimate)], servings: 2)])
        XCTAssertEqual(snapshot.metric(.water, at: date, calendar: calendar).value, 500)
        XCTAssertEqual(snapshot.metric(.sodium, at: date, calendar: calendar).value, 1000)
        XCTAssertEqual(snapshot.metric(.protein, at: date, calendar: calendar).value, 20)
        XCTAssertTrue(snapshot.metric(.protein, at: date, calendar: calendar).estimated)
        XCTAssertEqual(snapshot.pendingCount, 1)
    }
    func testUndoExcludesValuesRestoreIncludesExactlyOnceAndOtherDayExcluded() throws {
        var intake = try event([.init(.water, 250, .mL)])
        intake.state = .deletionPending
        XCTAssertNil(build([intake]).metric(.water, at: date, calendar: calendar).value)
        XCTAssertEqual(build([intake]).pendingCount, 1)
        intake.state = .deleted
        XCTAssertEqual(build([intake]).pendingCount, 0)
        intake.state = .pending
        XCTAssertEqual(build([intake]).metric(.water, at: date, calendar: calendar).value, 250)
        intake.date = date.addingTimeInterval(-86400)
        XCTAssertNil(build([intake]).metric(.water, at: date, calendar: calendar).value)
    }
    func testMidnightAndTimezoneInvalidateValuesButKeepGoals() throws {
        let snapshot = build([try event([.init(.water, 250, .mL)])], goals: [.water: 2000])
        XCTAssertNil(snapshot.metric(.water, at: snapshot.dayEnd, calendar: calendar).value)
        XCTAssertEqual(snapshot.metric(.water, at: snapshot.dayEnd, calendar: calendar).goal, 2000)
        var utc = calendar; utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertFalse(snapshot.isCurrent(at: date, calendar: utc))
    }
    func testDayIntervalAccountsForDaylightSaving() {
        let spring = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let snapshot = DashboardSnapshot(updatedAt: spring, calendar: calendar, values: [], pendingCount: 0, language: "en")
        XCTAssertEqual(snapshot.dayEnd.timeIntervalSince(snapshot.dayStart), 23 * 3600)
    }
    func testInvalidGoalsIgnoredAndLimitRingClampedWithoutTruncatingAmount() throws {
        let snapshot = build([try event([.init(.sugar, 60, .g)])], goals: [.sugar: 50, .protein: -.infinity, .energy: 0])
        let sugar = snapshot.metric(.sugar, at: date, calendar: calendar)
        XCTAssertEqual(sugar.value, 60); XCTAssertEqual(sugar.fraction, 1); XCTAssertTrue(sugar.id.isLimit)
        XCTAssertNil(snapshot.metric(.protein, at: date, calendar: calendar).goal)
        XCTAssertNil(snapshot.metric(.energy, at: date, calendar: calendar).goal)
    }
    func testSnapshotValidationAndRoundTrip() throws {
        var snapshot = build([try event([.init(.water, 250, .mL)])])
        XCTAssertTrue(snapshot.isValid)
        XCTAssertEqual(try JSONDecoder().decode(DashboardSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        snapshot.values.append(snapshot.values[0]); XCTAssertFalse(snapshot.isValid)
        snapshot.values.removeLast(); snapshot.schema = 99; XCTAssertFalse(snapshot.isValid)
    }
    func testLanguageResolutionAndSafeInterpolation() {
        XCTAssertEqual(L10n.resolved("system", preferred: ["zh-CA"]), "zh-Hans")
        XCTAssertEqual(L10n.resolved("system", preferred: ["fr-CA"]), "en")
        XCTAssertEqual(L10n.resolved("en", preferred: ["zh-Hans"]), "en")
        XCTAssertEqual(L10n.tr("营养", language: "en"), "Nutrition")
        XCTAssertEqual(L10n.tr("营养", language: "zh-Hans"), "营养")
        let name = "user {1}", amount = 500
        XCTAssertEqual(L10n.tr("\(name) \(amount)", language: "en"), "user {1} 500")
    }
}

extension DashboardTests {
    func testDiagnosticLanguageSwitchPreservesUserArguments() {
        let chinese = "茶 {1}：请填写大于 0 且不超过 10000 mL 的实际摄入量。"
        let english = L10n.diagnostic(chinese, language: "en")
        XCTAssertEqual(english, "茶 {1}: enter an actual quantity greater than 0 and at most 10,000 mL.")
        XCTAssertEqual(L10n.diagnostic(english, language: "zh-Hans"), chinese)
        XCTAssertEqual(L10n.diagnostic("用户自定义产品 {0}", language: "en"), "用户自定义产品 {0}")
        XCTAssertEqual(L10n.diagnostic("正在处理，请稍后重试。", language: "en"), "Processing. Please try again shortly.")
        XCTAssertEqual(L10n.diagnostic("Processing. Please try again shortly.", language: "zh-Hans"), "正在处理，请稍后重试。")
    }
    func testValidationMessagesAndNutrientLabelsHaveEnglishTranslations() {
        let messages = MealValidation.portionIssues([MealPortion(name: "Test", grams: nil)])
            + MealValidation.submissionIssues([], confirmed: false)
        for message in messages {
            XCTAssertNil(L10n.diagnostic(message, language: "en").range(of: #"[\p{Han}]"#, options: .regularExpression), message)
        }
        for nutrient in Nutrient.allCases {
            XCTAssertNil(L10n.tr(.init(stringLiteral: nutrient.title), language: "en").range(of: #"[\p{Han}]"#, options: .regularExpression))
        }
    }
    func testChangingLanguageDoesNotModifyProductIdentityOrWritePlan() throws {
        let previous = UserDefaults.standard.object(forKey: L10n.preferenceKey)
        defer { if let previous { UserDefaults.standard.set(previous, forKey: L10n.preferenceKey) } else { UserDefaults.standard.removeObject(forKey: L10n.preferenceKey) } }
        let userProduct = Product(name: "我的饮料", serving: "100 mL", nutrients: [.init(.sugar, 5, .g)], confirmedAt: Date())
        let event = try IntakeEvent(product: userProduct, servings: 2)
        let plan = try event.healthSamples
        UserDefaults.standard.set("en", forKey: L10n.preferenceKey)
        XCTAssertEqual(userProduct.displayName, "我的饮料")
        XCTAssertEqual(HydrationProgress.product().displayName, "Water")
        UserDefaults.standard.set("zh-Hans", forKey: L10n.preferenceKey)
        XCTAssertEqual(HydrationProgress.product().displayName, "饮水")
        XCTAssertEqual(try event.healthSamples, plan)
        XCTAssertEqual(event.product.name, "我的饮料")
    }
}
