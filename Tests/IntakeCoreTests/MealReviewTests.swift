import XCTest
@testable import IntakeCore

final class MealReviewTests: XCTestCase {
    let source = "豉油黄炒面 450 克，维他柠檬茶 500 毫升，奥尔良猪排骨 500 克"
    // Synthetic estimates exercise calculations; these are not claims about these foods.
    var rows: [TextFoodProposal] { [
        .init(nameQuote: "豉油黄炒面", sourceQuote: "豉油黄炒面 450 克", quantityQuote: "450 克", estimates: [.init(.carbohydrates, 20, .g, origin: .aiEstimate)]),
        .init(nameQuote: "维他柠檬茶", sourceQuote: "维他柠檬茶 500 毫升", quantityQuote: "500 毫升", estimates: [.init(.sugar, 10, .g, origin: .aiEstimate)], nutrientBasis: .mL),
        .init(nameQuote: "奥尔良猪排骨", sourceQuote: "奥尔良猪排骨 500 克", quantityQuote: "500 克", estimates: [.init(.protein, 15, .g, origin: .aiEstimate)])
    ] }
    func ready() throws -> MealReviewState {
        var state = MealReviewState(); state.text = source; state.parsedText = source
        state.items = try TextMealValidation.build(rows, source: source).items
        return state
    }
    func testTwoFoodsCanConfirmEstimatesAndRecordWithoutEveryNutrient() throws {
        var state = try ready(); state.items.remove(at: 1)
        XCTAssertTrue(state.confirmationIssues.isEmpty)
        state.setAccepted(true); XCTAssertTrue(state.accepted); XCTAssertTrue(state.submissionIssues.isEmpty)
        let product = try state.beginSubmission(requestID: UUID())
        XCTAssertEqual(product.nutrients.count, 2)
        XCTAssertTrue(product.nutrients.allSatisfy { $0.origin == .aiEstimate })
        XCTAssertNil(product.nutrients.first { $0.nutrient == .sodium })
        XCTAssertEqual(product.nutrients.first { $0.nutrient == .protein }?.value, 75)
    }
    func testConfirmationSurvivesIdenticalValueRefreshAndSerializationButEditsInvalidate() throws {
        var state = try ready(); state.setAccepted(true)
        // Body reevaluation and equivalent assignments are deliberately repeated.
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let roundTrip = try JSONDecoder().decode([MealPortion].self, from: encoder.encode(state.items))
        for _ in 0..<50 {
            state.items = roundTrip
            _ = state.submissionIssues
            _ = try MealValidation.product(state.items, confirmed: state.accepted)
            XCTAssertTrue(state.accepted)
        }
        state.items[0].grams = 400; XCTAssertFalse(state.accepted)
        state.setAccepted(true); state.text += "。"; XCTAssertFalse(state.accepted)
        XCTAssertFalse(state.submissionIssues.isEmpty)
    }
    func testInvalidReplacementTextCannotSubmitStaleMeal() throws {
        var state = try ready(); state.setAccepted(true)
        let before = state.items
        XCTAssertThrowsError(try state.prepareText(String(repeating: "a", count: 4001)))
        XCTAssertEqual(state.items, before)
        XCTAssertTrue(state.textNeedsReview); XCTAssertFalse(state.accepted)
        state.setAccepted(true); XCTAssertFalse(state.accepted)
        XCTAssertThrowsError(try state.beginSubmission(requestID: UUID()))
        XCTAssertThrowsError(try state.prepareText(""))
        XCTAssertTrue(state.textNeedsReview)
        try state.prepareText(source)
        XCTAssertFalse(state.textNeedsReview); XCTAssertEqual(state.items.count, 3)
    }
    func testSwitchOffCannotBypassConfirmation() throws {
        var state = try ready(); state.setAccepted(true); state.setAccepted(false)
        XCTAssertThrowsError(try state.beginSubmission(requestID: UUID()))
        XCTAssertFalse(state.submitting)
    }
    func testStaleAICompletionCannotOverwriteOrResetConfirmedRows() throws {
        var state = try ready(); let old = state.startAnalysis()
        state.setAccepted(true); XCTAssertFalse(state.accepted)
        state.cancelAnalysis(); state.setAccepted(true)
        XCTAssertFalse(state.finishAnalysis(old, items: [])); XCTAssertTrue(state.accepted)
        XCTAssertEqual(state.items.count, 3)
        let first = state.startAnalysis(); let second = state.startAnalysis()
        XCTAssertFalse(state.finishAnalysis(first, items: []))
        XCTAssertTrue(state.finishAnalysis(second)); state.setAccepted(true); XCTAssertTrue(state.accepted)
    }
    func testAllThreeItemsAndVolumeBasisReachSnapshotAndHealthAmounts() throws {
        let state = try ready()
        XCTAssertEqual(state.items.map(\.name), ["豉油黄炒面", "维他柠檬茶", "奥尔良猪排骨"])
        XCTAssertEqual(state.items[0].grams, 450); XCTAssertEqual(state.items[2].grams, 500)
        XCTAssertEqual(state.items[1].milliliters, 500); XCTAssertNil(state.items[1].grams)
        let product = try MealValidation.product(state.items, confirmed: true)
        let event = try IntakeEvent(product: product, servings: 1)
        XCTAssertEqual(try event.healthSamples.first { $0.nutrient == .sugar }?.value, 50)
        XCTAssertEqual(product.mealDetails?[1].portionUnit, .mL)
        XCTAssertEqual(try JSONDecoder().decode(Product.self, from: JSONEncoder().encode(product)).mealDetails, state.items)
    }
    func testOmittedDrinkIsRecoveredWithoutInventingNutrition() throws {
        let draft = try TextMealValidation.build([rows[0], rows[2]], source: source)
        XCTAssertEqual(draft.items.count, 3)
        let drink = try XCTUnwrap(draft.items.first { $0.name == "维他柠檬茶" })
        XCTAssertEqual(drink.milliliters, 500); XCTAssertTrue(drink.nutrientsPer100.isEmpty)
        XCTAssertTrue(draft.warnings.contains { $0.contains("维他柠檬茶") })
        let product = try MealValidation.product(draft.items, confirmed: true)
        XCTAssertNil(product.nutrients.first { $0.nutrient == .sugar })
        XCTAssertEqual(product.mealDetails?.count, 3)
        XCTAssertEqual(try TextMealValidation.fallback(source).items.count, 3)
    }
    func testMissingModelQuantityPreservesExplicitUserVolumeAndOverlappingEvidenceDoesNotDoubleCount() throws {
        var drink = rows[1]; drink.quantityQuote = ""
        let draft = try TextMealValidation.build([drink,
            .init(nameQuote: "维他柠檬茶", sourceQuote: "维他柠檬茶")], source: drink.sourceQuote)
        XCTAssertEqual(draft.items.count, 1)
        XCTAssertEqual(draft.items[0].milliliters, 500)
        XCTAssertEqual(draft.items[0].nutrientsPer100.count, 1)
    }
    func testVolumeNeverUsesMassEstimatesAndUnitSwitchClearsValues() throws {
        var wrong = rows[1]; wrong.nutrientBasis = .g
        let drink = try TextMealValidation.build([wrong], source: wrong.sourceQuote).items[0]
        XCTAssertEqual(drink.milliliters, 500); XCTAssertTrue(drink.nutrientsPer100.isEmpty)
        var item = try ready().items[1]; item.changeUnit(to: .g)
        XCTAssertNil(item.quantity); XCTAssertTrue(item.nutrientsPer100.isEmpty)
        let liter = try TextMealValidation.fallback("茶0.5L").items[0]
        XCTAssertEqual(liter.milliliters, 500)
        XCTAssertEqual(try TextMealValidation.fallback("rice 1,000 g, tea 250 mL").items.count, 2)
    }
    func testExplicitTextOrManualRowsBlockPhotoReplacement() throws {
        var state = try ready(); state.setAccepted(true)
        XCTAssertFalse(state.canAnalyzePhoto)
        let before = state.items
        // This is the same guard used by MealEditor when attaching a photo.
        if state.canAnalyzePhoto { _ = state.startAnalysis(); state.items = [] }
        XCTAssertEqual(state.items, before); XCTAssertTrue(state.accepted)
        state.text = ""; XCTAssertFalse(state.canAnalyzePhoto)
        state.items = []; XCTAssertTrue(state.canAnalyzePhoto)
    }
    func testMissingInvalidPortionsAndAllUnknownsExplainBlocking() throws {
        for quantity in [nil, 0, -1, Double.nan, Double.infinity, 10001] as [Double?] {
            var state = try ready(); state.items[0].grams = quantity
            state.setAccepted(true); XCTAssertFalse(state.accepted)
            XCTAssertTrue(state.submissionIssues.contains { $0.contains("豉油黄炒面") && $0.contains("实际摄入量") })
            XCTAssertThrowsError(try state.beginSubmission(requestID: UUID()))
        }
        var state = try ready(); state.items = try TextMealValidation.fallback(source).items
        state.setAccepted(true); XCTAssertTrue(state.accepted) // Unknown nutrition does not jam Toggle.
        XCTAssertTrue(state.submissionIssues.contains { $0.contains("尚无可写入") })
        XCTAssertThrowsError(try state.beginSubmission(requestID: UUID()))
    }
    @MainActor func testRapidSubmissionAndHealthRetryDoNotDuplicateEventsOrSamples() async throws {
        var state = try ready(); state.setAccepted(true); let request = UUID()
        let product = try state.beginSubmission(requestID: request)
        XCTAssertThrowsError(try state.beginSubmission(requestID: request))
        let event = try IntakeEvent(product: product, servings: 1)
        var library = Library(); try library.enqueue(event)
        XCTAssertThrowsError(try library.enqueue(IntakeEvent(product: product, servings: 1)))
        let health = FakeHealth(); health.granted = false
        do { try await EventSync.perform(event, using: health); XCTFail("Denied") } catch { }
        XCTAssertEqual(library.events.count, 1); XCTAssertTrue(health.samples.isEmpty)
        XCTAssertThrowsError(try MealReviewState.validateRequest(request, events: library.events))
        var restored = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        restored.events[0].date = Date(timeIntervalSince1970: 0)
        restored.events[0].state = .deleted
        XCTAssertThrowsError(try MealReviewState.validateRequest(request, events: restored.events))
        XCTAssertNoThrow(try MealReviewState.validateRequest(UUID(), events: restored.events))
        health.granted = true
        try await EventSync.perform(event, using: health); try await EventSync.perform(event, using: health)
        XCTAssertEqual(health.samples.count, 3)
        XCTAssertEqual(health.samples[event.syncID(for: .sugar)], 50)
        state.finishSubmission(succeeded: true)
        XCTAssertThrowsError(try state.beginSubmission(requestID: request))
    }
    func testLegacyMassOnlyJSONDecodesAndNutrientEditsResetConfirmation() throws {
        let id = UUID()
        let data = Data("{\"id\":\"\(id.uuidString)\",\"name\":\"rice\",\"grams\":100,\"per100g\":[],\"notes\":\"\"}".utf8)
        let item = try JSONDecoder().decode(MealPortion.self, from: data)
        XCTAssertEqual(item.portionUnit, .g); XCTAssertNil(item.per100mL)
        var state = try ready(); state.setAccepted(true)
        state.items[0].nutrientsPer100[0].value = 21
        XCTAssertFalse(state.accepted)
    }
}

extension MealReviewTests {
    func testManualOnlyTextWorkflowDoesNotInventNutritionAndRequiresConfirmation() throws {
        var state = MealReviewState()
        try state.prepareText("Rice 150 g, Tea 250 mL")
        XCTAssertEqual(state.items.count, 2)
        XCTAssertTrue(state.items.allSatisfy { $0.nutrientsPer100.isEmpty })
        XCTAssertEqual(state.items[0].quantity, 150)
        XCTAssertEqual(state.items[1].portionUnit, .mL)
        XCTAssertEqual(state.items[1].quantity, 250)
        state.setAccepted(true)
        XCTAssertFalse(state.submissionIssues.isEmpty) // No known nutrition yet.
        state.items[1].nutrientsPer100 = [.init(.sugar, 10, .g, origin: .manual)]
        XCTAssertFalse(state.accepted)
        XCTAssertThrowsError(try state.beginSubmission(requestID: UUID()))
        state.setAccepted(true)
        let product = try state.beginSubmission(requestID: UUID())
        let event = try IntakeEvent(product: product, servings: 1)
        XCTAssertEqual(try event.healthSamples.count, 1)
        XCTAssertEqual(try event.healthSamples.first?.value, 25)
        XCTAssertEqual(try event.healthSamples.first?.origin, .manual)
        XCTAssertNil(try event.healthSamples.first { $0.nutrient == .sodium })
        XCTAssertEqual(event.state, .pending)
        XCTAssertNil(event.healthVerifiedAt)
        state.finishSubmission(succeeded: true)
        XCTAssertThrowsError(try state.beginSubmission(requestID: product.id))
    }

    func testHistoricalEstimateSnapshotRetainsOriginWithoutModel() throws {
        let product = try MealValidation.product([.init(name: "Legacy synthetic", grams: 100,
            per100g: [.init(.protein, 10, .g, origin: .aiEstimate)])], confirmed: true)
        let event = try IntakeEvent(product: product, servings: 1)
        let restored = try JSONDecoder().decode(IntakeEvent.self, from: JSONEncoder().encode(event))
        XCTAssertEqual(restored.id, event.id)
        XCTAssertEqual(try restored.healthSamples, try event.healthSamples)
        XCTAssertEqual(try restored.healthSamples.first?.origin, .aiEstimate)
        XCTAssertEqual(restored.product.mealDetails?.first?.per100g.first?.origin, .aiEstimate)
    }
}

extension MealReviewTests {
    @MainActor func testRecordTapWithoutCheckboxSavesUnknownMealLocallyAndCanUndoRestore() async throws {
        var state = MealReviewState()
        try state.prepareText("Rice 150 g, Tea 250 mL")
        XCTAssertFalse(state.accepted)
        XCTAssertTrue(state.recordingIssues.isEmpty)
        let request = UUID()
        let product = try state.beginRecording(requestID: request)
        XCTAssertTrue(product.nutrients.isEmpty)
        XCTAssertNil(product.ingredients)
        XCTAssertEqual(product.mealDetails?.count, 2)
        XCTAssertThrowsError(try state.beginRecording(requestID: request))
        let event = try IntakeEvent(product: product, servings: 1)
        let health = FakeHealth(); health.granted = false
        var library = Library(); try library.enqueue(event)
        try await EventSync.perform(event, using: health); library.completeSync(event.id)
        XCTAssertEqual(library.events[0].state, .localOnly)
        XCTAssertNil(library.events[0].healthVerifiedAt)
        XCTAssertEqual(health.authorizations, 0); XCTAssertEqual(health.writes, 0)
        try library.revoke(event.id)
        try await EventSync.perform(library.events[0], using: health); library.completeSync(event.id)
        XCTAssertEqual(library.events[0].state, .deleted)
        try library.restore(event.id)
        try await EventSync.perform(library.events[0], using: health); library.completeSync(event.id)
        XCTAssertEqual(library.events[0].state, .localOnly)
        XCTAssertEqual(library.events.count, 1)
        XCTAssertEqual(library.events[0].id, event.id)
        XCTAssertTrue(health.samples.isEmpty)
        let restored = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(restored.events[0].product.mealDetails, product.mealDetails)
    }
    @MainActor func testRecordTapKnownValuesStillUseHealthOutboxAndRetry() async throws {
        var state = MealReviewState(); try state.prepareText("Tea 250 mL")
        state.items[0].nutrientsPer100 = [.init(.sugar, 10, .g, origin: .manual)]
        let product = try state.beginRecording(requestID: UUID())
        let event = try IntakeEvent(product: product, servings: 1)
        let health = FakeHealth(); health.granted = false
        do { try await EventSync.perform(event, using: health); XCTFail("Permission must block") } catch { }
        XCTAssertTrue(health.samples.isEmpty)
        health.granted = true
        try await EventSync.perform(event, using: health); try await EventSync.perform(event, using: health)
        XCTAssertEqual(health.samples.count, 1)
        XCTAssertEqual(health.samples[event.syncID(for: .sugar)], 25)
        XCTAssertNil(try event.healthSamples.first { $0.nutrient == .sodium })
    }
    func testRecordingWithoutCheckboxStillRejectsMissingPortionsAndStaleText() throws {
        var state = MealReviewState(); try state.prepareText("Rice")
        XCTAssertFalse(state.recordingIssues.isEmpty)
        XCTAssertThrowsError(try state.beginRecording(requestID: UUID()))
        try state.prepareText("Rice 150 g"); state.text = "Rice 300 g"
        XCTAssertFalse(state.recordingIssues.isEmpty)
        XCTAssertThrowsError(try state.beginRecording(requestID: UUID()))
    }
    func testEmptyProductCannotPretendToBeLocalMeal() throws {
        var product = Product(name: "Empty", serving: "1", confirmedAt: Date()); product.kind = .food
        XCTAssertThrowsError(try product.validate())
        product.mealDetails = [.init(name: "Rice", grams: nil)]
        XCTAssertThrowsError(try product.validate())
        product.mealDetails = [.init(name: "Rice", grams: 150, per100g: [.init(.protein, 10, .g)])]
        XCTAssertThrowsError(try product.validate()) // Cannot hide known values in an empty write plan.
    }
}
