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

extension DashboardTests {
    // Deliberately synthetic values, not a user's meal or health history.
    var nutrientSummaryFixture: String {
        """
        Fixture meal: example food.
        Energy: 720 kcal
        Protein: 32 g
        Carbohydrates: 70 g
        Total Fat: 20 g
        Dietary Fiber: 6 g
        Saturated Fat: 5 g
        Sugar: 8 g
        Sodium: 900 mg
        Water: 250 mL
        """
    }
    func testNutritionSummaryBecomesFieldsRatherThanFoodsOnEveryDashboard() throws {
        var review = MealReviewState(); try review.prepareText(nutrientSummaryFixture)
        XCTAssertEqual(review.items.count, 1)
        XCTAssertTrue(review.recordsProvidedTotals)
        let product = try review.beginRecording(requestID: UUID())
        let event = try IntakeEvent(product: product, servings: 1, date: date)
        XCTAssertEqual(try event.healthSamples.count, 9)
        let snapshot = build([event])
        let expected: [DashboardMetric: Double] = [.energy:720,.protein:32,.carbohydrates:70,.fat:20,.fiber:6,.saturatedFat:5,.sugar:8,.sodium:900,.water:250]
        for (metric, amount) in expected {
            XCTAssertEqual(snapshot.metric(metric, at:date, calendar:calendar).value,amount,"\(metric)")
        }
        XCTAssertNil(snapshot.metric(.protein, at:date, calendar:calendar).goal)
        let envelope = WatchEnvelope(dashboard:snapshot,products:[])
        let watch = try JSONDecoder().decode(WatchEnvelope.self,from:JSONEncoder().encode(envelope))
        XCTAssertEqual(watch.dashboard,snapshot)
        XCTAssertEqual(watch.dashboard.metric(.fat,at:date,calendar:calendar).value,20)
    }
    func testChineseNutrientsAndExactUnitConversionRemainUnknownWhenMissing() throws {
        var review=MealReviewState();try review.prepareText("蛋白质32克；碳水化合物70克；总脂肪20克；膳食纤维6克；饱和脂肪5克；糖8克；钠0.9克；饮水0.25升")
        XCTAssertTrue(review.items.isEmpty);XCTAssertTrue(review.recordingIssues.isEmpty)
        let event=try IntakeEvent(product:review.beginRecording(requestID:UUID()),servings:1,date:date)
        let snapshot=build([event])
        XCTAssertEqual(snapshot.metric(.protein,at:date,calendar:calendar).value,32)
        XCTAssertEqual(snapshot.metric(.sodium,at:date,calendar:calendar).value,900)
        XCTAssertEqual(snapshot.metric(.water,at:date,calendar:calendar).value,250)
        XCTAssertNil(snapshot.metric(.energy,at:date,calendar:calendar).value)
    }
    func testEveryDashboardMetricResolvesToOneOf39ActualNutritionTypes() {
        for metric in DashboardMetric.allCases {
            let nutrient=Nutrient(rawValue:metric.nutrientID)
            XCTAssertNotNil(nutrient)
            XCTAssertTrue(NutritionRegistry.entries.contains { $0.internalID==metric.nutrientID && $0.writeCandidate })
        }
    }
    func testExplicitAll39FieldsDoNotNeed39FoodPortions() throws {
        let text=Nutrient.allCases.map { "\($0.rawValue): 1 \($0 == .energyConsumed ? "kcal" : $0 == .water ? "mL" : "g")" }.joined(separator:"\n")
        var review=MealReviewState();try review.prepareText(text)
        XCTAssertTrue(review.items.isEmpty);XCTAssertTrue(review.recordingIssues.isEmpty)
        XCTAssertEqual(try review.beginRecording(requestID:UUID()).nutrients.count,39)
    }
    func testNoUnrelatedFoodsFormsOrAddedSugarsAreSilentlyMapped() throws {
        for name in ["Protein shake","Vitamin C gummies","Vitamin A RAE","Folate DFE","Omega-3","Added Sugars"] {
            XCTAssertNil(MealNutritionText.resolve(name),name)
        }
        XCTAssertThrowsError(try MealNutritionText.extract("Protein: 32 mL"))
        XCTAssertThrowsError(try MealNutritionText.extract("Sodium: 900"))
        XCTAssertThrowsError(try MealNutritionText.extract("Vitamin D: 400 IU"))
        XCTAssertThrowsError(try MealNutritionText.extract("Protein: -1 g"))
        XCTAssertThrowsError(try MealNutritionText.extract("Per 100g\nProtein:32g"))
    }
    func testBilingualDuplicatesCoalesceButConflictsNeverSum() throws {
        let result=try MealNutritionText.extract("Protein:32g\n蛋白质:32克\nSodium:900mg\n钠:0.9g\nSugar:unknown\nIron:0mg")
        XCTAssertEqual(result.nutrients.count,3)
        XCTAssertEqual(result.nutrients.first { $0.nutrient == .protein }?.value,32)
        XCTAssertEqual(result.nutrients.first { $0.nutrient == .iron }?.value,0)
        XCTAssertFalse(result.nutrients.contains { $0.nutrient == .sugar })
        XCTAssertThrowsError(try MealNutritionText.extract("Protein:32g\n蛋白质:40克"))
    }
    func testNutrientReparseRetainsManualEditsAndClearsRemovedSourceFields() throws {
        var review=MealReviewState();try review.prepareText("Protein:32g\nFat:20g")
        review.nutrientOverrides.removeAll { $0.nutrient == .protein }
        review.nutrientOverrides.append(.init(.protein,35,.g))
        try review.prepareText("Protein:32g\nFat:22g")
        XCTAssertEqual(review.nutrientOverrides.first { $0.nutrient == .protein }?.value,35)
        XCTAssertEqual(review.nutrientOverrides.first { $0.nutrient == .fatTotal }?.value,22)
        try review.prepareText("Protein:32g")
        XCTAssertFalse(review.nutrientOverrides.contains { $0.nutrient == .fatTotal })
    }
    func legacyNutritionEvent() throws -> IntakeEvent {
        var product=Product(name:"Synthetic legacy meal",serving:"1",nutrients:[.init(.energyConsumed,720,.kcal)],confirmedAt:date)
        product.kind = .food; product.mealInputText=nutrientSummaryFixture
        product.mealDetails=[.init(name:"Fixture meal: example food."),.init(name:"Protein:",grams:32),.init(name:"Total Fat:",grams:20),.init(name:"Sodium:900mg"),.init(name:"Water:",milliliters:250,per100mL:[])]
        var event=try IntakeEvent(product:product,servings:1,date:date)
        event.state = .synced;event.healthVerifiedAt=date
        return event
    }
    func testLegacyRecoveryIsReviewedAndKeepsExistingOverridesAndTimestamp() throws {
        let event=try legacyNutritionEvent()
        XCTAssertEqual(MealNutritionRecovery.missing(in:event).count,8)
        XCTAssertNil(build([event]).metric(.protein,at:date,calendar:calendar).value)
        XCTAssertEqual(try event.healthSamples.count,1) // diagnosis must not mutate history
        var review=MealReviewState();try review.prepareRecovery(event)
        XCTAssertEqual(review.items.count,1);XCTAssertNil(review.items[0].grams)
        let replacement=try review.beginRecording(requestID:UUID())
        var library=Library();try library.enqueue(event);try library.editMeal(event.id,product:replacement)
        XCTAssertEqual(library.events.count,1);XCTAssertEqual(library.events[0].id,event.id);XCTAssertEqual(library.events[0].date,event.date)
        XCTAssertEqual(library.events[0].syncVersion,2)
        XCTAssertTrue(MealNutritionRecovery.missing(in:library.events[0]).isEmpty)
        XCTAssertEqual(build(library.events).metric(.protein,at:date,calendar:calendar).value,32)
        XCTAssertEqual(build(library.events).metric(.sodium,at:date,calendar:calendar).value,900)
        var changed=event;changed.healthWriteSnapshot?.append(.init(.protein,35,.g))
        try review.prepareRecovery(changed)
        XCTAssertEqual(review.nutrientOverrides.first { $0.nutrient == .protein }?.value,35)
    }
    @MainActor func testRecoveredNutritionWritesAllFieldsOnceAndSupportsPermissionRetryUndo() async throws {
        let event=try legacyNutritionEvent();var review=MealReviewState();try review.prepareRecovery(event)
        let product=try review.beginRecording(requestID:UUID())
        var library=Library();try library.enqueue(event);try library.editMeal(event.id,product:product)
        let health=FakeHealth();health.granted=false
        do { try await EventSync.perform(library.events[0],using:health);XCTFail() } catch {}
        XCTAssertEqual(library.events[0].state,.pending);XCTAssertTrue(health.samples.isEmpty)
        health.granted=true;health.failWrite=true
        do { try await EventSync.perform(library.events[0],using:health);XCTFail() } catch {}
        health.failWrite=false
        try await EventSync.perform(library.events[0],using:health);library.completeSync(event.id)
        XCTAssertEqual(health.samples.count,9)
        XCTAssertEqual(health.samples[event.syncID(for:.protein)],32)
        XCTAssertEqual(health.samples[event.syncID(for:.sodium)],0.9)
        try await EventSync.perform(library.events[0],using:health)
        XCTAssertEqual(health.samples.count,9)
        try library.revoke(event.id);try await EventSync.perform(library.events[0],using:health);library.completeSync(event.id)
        XCTAssertTrue(health.samples.isEmpty)
        XCTAssertNil(build(library.events).metric(.protein,at:date,calendar:calendar).value)
    }
}

extension DashboardTests {
    func testSharedPromptFieldAliasesAndCodeBlockMatchAll39Types() throws {
        XCTAssertEqual(MealNutritionText.resolve("Thiamin (B1)"),.thiamin)
        XCTAssertEqual(MealNutritionText.resolve("Riboflavin (B2)"),.riboflavin)
        let fields=Nutrient.allCases.map { "\($0.rawValue): 1 \($0 == .energyConsumed ? "kcal" : $0 == .water ? "mL" : "g")" }.joined(separator:"\n")
        var review=MealReviewState();try review.prepareText("```text\nMeal: Synthetic full-schema meal\n"+fields+"\n```")
        XCTAssertEqual(review.items.count,1)
        XCTAssertEqual(review.nutrientOverrides.count,39)
        let product=try review.beginRecording(requestID:UUID())
        XCTAssertTrue(product.nutrients.allSatisfy { $0.origin == .manualEstimate })
        XCTAssertTrue(build([try IntakeEvent(product:product,servings:1,date:date)]).metric(.protein,at:date,calendar:calendar).estimated)
    }
    func testExternalTemplateZerosRequireReviewAndDoNotWriteUnknowns() throws {
        let fields=Nutrient.allCases.map { "\($0.rawValue): \($0 == .energyConsumed ? 720 : 0) \($0 == .energyConsumed ? "kcal" : $0 == .water ? "mL" : "g")" }.joined(separator:"\n")
        var review=MealReviewState();try review.prepareText("Meal: Synthetic zero-placeholder schema\n"+fields)
        XCTAssertEqual(review.pendingPlaceholderZeros.count,38)
        XCTAssertThrowsError(try review.beginRecording(requestID:UUID()))
        review.resolvePlaceholderZero(.sugar,knownZero:true)
        review.discardPlaceholderZeros()
        XCTAssertTrue(review.pendingPlaceholderZeros.isEmpty)
        let product=try review.beginRecording(requestID:UUID())
        XCTAssertEqual(product.nutrients.count,2)
        XCTAssertEqual(product.nutrients.first { $0.nutrient == .sugar }?.value,0)
        XCTAssertEqual(product.nutrients.first { $0.nutrient == .sugar }?.origin,.manual)
        XCTAssertFalse(product.nutrients.contains { $0.nutrient == .iron })
        let snapshot=build([try IntakeEvent(product:product,servings:1,date:date)])
        XCTAssertNil(snapshot.metric(.protein,at:date,calendar:calendar).value)
        XCTAssertEqual(snapshot.metric(.sugar,at:date,calendar:calendar).value,0)
    }
}

extension DashboardTests {
    func testDiscardedPlaceholderZerosDoNotBecomeLegacyRepairCandidates() throws {
        let fields=Nutrient.allCases.map { "\($0.rawValue): \($0 == .energyConsumed ? 720 : 0) \($0 == .energyConsumed ? "kcal" : $0 == .water ? "mL" : "g")" }.joined(separator:"\n")
        var review=MealReviewState();try review.prepareText("Meal: Synthetic unknowns\n"+fields)
        review.discardPlaceholderZeros()
        let product=try review.beginRecording(requestID:UUID())
        XCTAssertEqual(product.mealUnknownNutrients?.count,38)
        var event=try IntakeEvent(product:product,servings:1,date:date);event.state = .synced
        XCTAssertTrue(MealNutritionRecovery.missing(in:event).isEmpty)
        let decoded=try JSONDecoder().decode(IntakeEvent.self,from:JSONEncoder().encode(event))
        XCTAssertTrue(MealNutritionRecovery.missing(in:decoded).isEmpty)
        XCTAssertEqual(try decoded.healthSamples.count,1)
    }
}
