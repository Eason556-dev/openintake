import XCTest
@testable import IntakeCore

final class OfflineFoodTests: XCTestCase {
    func testBundledReferenceAndScaling() throws {
        let db = try XCTUnwrap(FoodReference.bundled)
        let rice = try XCTUnwrap(db.food(id: "169757"))
        let portion = try rice.portion(quantity: 200, unit: .g)
        let totals = try MealCalculation.summarize([portion])
        let energy = try XCTUnwrap(totals.first { $0.nutrient == .energyConsumed }?.value)
        XCTAssertEqual(energy, 260, accuracy: 0.001)
        XCTAssertEqual(portion.referenceFoodID, "169757")
        XCTAssertEqual(rice.cookingState, .cooked)
        XCTAssertFalse(rice.category.isEmpty)
        XCTAssertTrue(rice.nutrientCoverage.contains(.protein))
        XCTAssertTrue(portion.notes.contains("USDA"))
    }
    func testEnglishMultipleFoodsAndBeefAmbiguity() throws {
        let rows = try OfflineMealParser.parse("200g cooked white rice and 150g cooked beef")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].item.grams, 200)
        XCTAssertFalse(rows[0].item.nutrientsPer100.isEmpty)
        XCTAssertEqual(rows[1].item.grams, 150)
        XCTAssertGreaterThan(rows[1].candidates.count, 1)
        XCTAssertTrue(rows[1].item.nutrientsPer100.isEmpty)
    }
    func testChineseAndRawCooked() throws {
        let rows = try OfflineMealParser.parse("200克米饭，150克牛肉")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].item.referenceFoodID, "169757")
        let raw = try OfflineMealParser.parse("200克生米")
        XCTAssertEqual(raw.first?.item.referenceFoodID, "169756")
        XCTAssertNotEqual(rows[0].item.nutrientsPer100, raw[0].item.nutrientsPer100)
    }
    func testUnknownAndDrinkNeverDroppedOrSubstituted() throws {
        let rows = try OfflineMealParser.parse("豉油黄炒面450克，维他柠檬茶500毫升，奥尔良猪排骨500克")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1].item.milliliters, 500)
        XCTAssertTrue(rows.allSatisfy { $0.item.nutrientsPer100.isEmpty })
    }
    func testUnitsNoGenericDensityOrHouseholdGuess() throws {
        XCTAssertEqual(try FoodQuantityUnit.kg.grams(0.2), 200)
        XCTAssertEqual(try FoodQuantityUnit.oz.grams(1), 28.349523125)
        XCTAssertThrowsError(try FoodQuantityUnit.mL.grams(250))
        XCTAssertThrowsError(try FoodQuantityUnit.serving("cup").grams(1))
        XCTAssertEqual(try FoodQuantityUnit.serving("cup").grams(2, servings: [.init(name:"cup",grams:158)]),316)
        XCTAssertEqual(try OfflineMealParser.parse("7 oz cooked rice").first?.item.grams ?? 0,198.446661875,accuracy:0.00001)
    }
    func testMissingVersusKnownZeroAndPartialAggregation() throws {
        let items = [MealPortion(name:"A",grams:200,per100g:[.init(.protein,2,.g,origin:.database),.init(.sugar,0,.g,origin:.database)]),MealPortion(name:"B",grams:100)]
        let totals = try MealCalculation.summarize(items)
        let sugar = try XCTUnwrap(totals.first { $0.nutrient == .sugar })
        XCTAssertEqual(sugar.value,0); XCTAssertFalse(sugar.complete); XCTAssertEqual(sugar.knownItems,1)
        XCTAssertNil(totals.first { $0.nutrient == .iron }?.value)
        let product = try MealValidation.product(items,confirmed:true)
        XCTAssertEqual(product.nutrients.first { $0.nutrient == .protein }?.value,4)
        XCTAssertEqual(product.nutrients.first { $0.nutrient == .sugar }?.value,0)
        XCTAssertEqual(product.nutrients.first?.origin,.database)
    }
    func testOverridesRetainedAcrossRecalculationAndRefresh() throws {
        var review = MealReviewState()
        try review.prepareText("200g cooked rice")
        review.nutrientOverrides = [.init(.protein,45,.g)]
        review.items[0].grams = 300
        let rendered = review
        XCTAssertEqual(rendered.nutrientOverrides.first?.value,45)
        let product = try review.beginRecording(requestID:UUID())
        XCTAssertEqual(product.nutrients.first { $0.nutrient == .protein }?.value,45)
        XCTAssertEqual(product.mealOverrides?.first?.origin,.manual)
        XCTAssertThrowsError(try review.beginRecording(requestID:UUID()))
    }
    func testInvalidQuantityAndDimensionsBlockSaving() throws {
        XCTAssertFalse(MealValidation.portionIssues([.init(name:"Rice")]).isEmpty)
        XCTAssertThrowsError(try MealCalculation.apply(overrides:[.init(.protein,4,.mL)],to:[]))
        XCTAssertThrowsError(try MealCalculation.apply(overrides:[.init(.protein,-1,.g)],to:[]))
    }
    func testRegistryConversionsAndCoverage() throws {
        XCTAssertEqual(Nutrient.allCases.count,39)
        XCTAssertEqual(Set(Nutrient.allCases.map(\.healthKitIdentifier)).count,39)
        XCTAssertEqual(try NutritionRegistry.converted(.init(.energyConsumed,130,.kcal),to:.kcal),130)
        XCTAssertEqual(try NutritionRegistry.converted(.init(.energyConsumed,543.92,.kJ),to:.kcal),130,accuracy:0.001)
        XCTAssertEqual(try NutritionRegistry.converted(.init(.sodium,500,.mg),to:.g),0.5)
        XCTAssertEqual(try NutritionRegistry.converted(.init(.vitaminD,5,.mcg),to:.mg),0.005,accuracy:0.0000001)
    }
    @MainActor func testEditingRecoveryUsesUnionAndStableIdentity() async throws {
        let original = try MealValidation.product([.init(name:"A",grams:100,per100g:[.init(.protein,10,.g),.init(.sodium,10,.mg)])],confirmed:true)
        var library=Library(); let event=try IntakeEvent(product:original,servings:1); try library.enqueue(event); library.completeSync(event.id)
        let replacement = try MealValidation.product([.init(name:"B",grams:200,per100g:[.init(.protein,20,.g)])],confirmed:true)
        try library.editMeal(event.id,product:replacement)
        let pending = try JSONDecoder().decode(Library.self,from:JSONEncoder().encode(library)).events[0]
        XCTAssertEqual(pending.id,event.id);XCTAssertEqual(pending.date,event.date);XCTAssertEqual(pending.syncVersion,2)
        let backend = EditBackend();backend.failWrite=true
        do { try await EventSync.perform(pending,using:backend);XCTFail() } catch {}
        XCTAssertEqual(Set(backend.deleted),Set([.protein,.sodium]))
        XCTAssertEqual(library.events[0].state,.pending)
        backend.failWrite=false;try await EventSync.perform(pending,using:backend); library.completeSync(event.id)
        XCTAssertEqual(library.events.count,1);XCTAssertNil(library.events[0].replacedHealthSamples)
        XCTAssertEqual(backend.saved[.protein],40)
        try library.revoke(event.id);try await EventSync.perform(library.events[0],using:backend);library.completeSync(event.id)
        XCTAssertTrue(backend.saved.isEmpty)
    }
    @MainActor func testEditPermissionFailureDoesNotDeleteOldSamples() async throws {
        let product = try MealValidation.product([.init(name:"A",grams:100,per100g:[.init(.protein,10,.g)])],confirmed:true)
        var library=Library();let event=try IntakeEvent(product:product,servings:1);try library.enqueue(event);library.completeSync(event.id);try library.editMeal(event.id,product:product)
        let backend=EditBackend();backend.denied=true
        do { try await EventSync.perform(library.events[0],using:backend);XCTFail() } catch {}
        XCTAssertTrue(backend.deleted.isEmpty)
    }
}
@MainActor private final class EditBackend: NutritionHealthStore {
    var denied=false,failWrite=false
    var deleted:[Nutrient]=[]
    var saved:[Nutrient:Double]=[:]
    func authorize(_ nutrients:[Nutrient]) async throws { if denied { throw IntakeError.permission } }
    func write(_ event:IntakeEvent) async throws {
        if failWrite { throw IntakeError.permission }
        for amount in try event.healthSamples { saved[amount.nutrient]=event.canonicalValue(for:amount) }
    }
    func delete(_ event:IntakeEvent) async throws { for amount in try event.healthSamples { deleted.append(amount.nutrient);saved[amount.nutrient]=nil } }
}

extension OfflineFoodTests {
    func testGenericBeefNeverAutomaticallyAssumesRaw() throws {
        let row = try XCTUnwrap(OfflineMealParser.parse("150g beef").first)
        XCTAssertGreaterThan(row.candidates.count,1)
        XCTAssertNil(row.item.referenceFoodID)
    }
    func testReferenceOnlyEquivalentsNeverEnterHealthPlan() throws {
        let food = try XCTUnwrap(FoodReference.bundled?.food(id:"169757"))
        let portion = try food.portion(quantity:200,unit:.g)
        XCTAssertTrue(portion.referenceOnlyNutrients?.contains { $0.id == "foodMoisture" } == true)
        let product = try MealValidation.product([portion],confirmed:true)
        XCTAssertFalse(try HealthPlan.samples(for:product).contains { $0.nutrient == .water })
        XCTAssertFalse(try HealthPlan.samples(for:product).contains { $0.nutrient == .vitaminA })
        XCTAssertEqual(NutritionRegistry.entries.filter(\.writeCandidate).count,39)
        XCTAssertNil(NutritionRegistry.entries.first { $0.internalID == "addedSugars" }?.healthKitIdentifier)
    }
    func testKnownZeroCanBeExplicitlySavedAndUnknownCannot() throws {
        let product = try MealValidation.product([.init(name:"Label food",grams:100,per100g:[.init(.sugar,0,.g,origin:.labelOCR)])],confirmed:true)
        let samples = try HealthPlan.samples(for:product)
        XCTAssertEqual(samples.count,1);XCTAssertEqual(samples[0].value,0)
        XCTAssertFalse(samples.contains { $0.nutrient == .sodium })
    }
    func testEnergyAndParentChecksDoNotGuessReplacementValues() throws {
        let contradictory = MealPortion(name:"Check",grams:100,per100g:[.init(.protein,10,.g),.init(.carbohydrates,10,.g),.init(.fatTotal,10,.g),.init(.energyConsumed,800,.kcal)])
        XCTAssertTrue(MealCalculation.energyNeedsReview(contradictory))
        XCTAssertEqual(contradictory.nutrientsPer100.last?.value,800)
        XCTAssertThrowsError(try MealValidation.validate(.init(name:"Invalid",per100g:[.init(.sugar,50,.g),.init(.carbohydrates,10,.g)])))
    }
    func testOfflineDatabaseUnavailableFailsWithoutInventingFood() throws {
        let db=FoodReference(url:URL(fileURLWithPath:"/not-an-openintake-food-database"))
        XCTAssertThrowsError(try db.search("rice"))
        let rows=try OfflineMealParser.parse("200g cooked rice",reference:nil)
        XCTAssertEqual(rows.first?.item.grams,200);XCTAssertTrue(rows[0].item.nutrientsPer100.isEmpty)
    }
    func testVolumeKilogramsAndOriginalNamesSurvive() throws {
        let rows=try OfflineMealParser.parse("0.2kg cooked rice and 0.5L tea")
        XCTAssertEqual(rows.count,2);XCTAssertEqual(rows[0].item.grams,200);XCTAssertEqual(rows[1].item.milliliters,500)
        XCTAssertEqual(rows[0].item.name,"cooked rice")
    }
    @MainActor func testAll39PassSharedOutboxWithCorrectCanonicalUnits() async throws {
        let amounts=Nutrient.allCases.map { NutrientAmount($0,$0 == .energyConsumed ? 130 : $0 == .water ? 250 : 1,$0 == .energyConsumed ? .kcal : $0 == .water ? .mL : .mg) }
        let product=Product(name:"Synthetic mapping fixture",serving:"1",nutrients:amounts,confirmedAt:Date())
        let backend=EditBackend();let event=try IntakeEvent(product:product,servings:1)
        try await EventSync.perform(event,using:backend)
        XCTAssertEqual(backend.saved.count,39);XCTAssertEqual(backend.saved[.energyConsumed],130);XCTAssertEqual(backend.saved[.sodium],0.001);XCTAssertEqual(backend.saved[.water],250)
    }
    @MainActor func testEditingToUnknownOnlyDeletesOldSamplesThenBecomesLocal() async throws {
        let original=try MealValidation.product([.init(name:"A",grams:100,per100g:[.init(.protein,10,.g)])],confirmed:true)
        var library=Library();let event=try IntakeEvent(product:original,servings:1);try library.enqueue(event);library.completeSync(event.id)
        let unknown=try MealValidation.product([.init(name:"A",grams:100)],confirmed:true,allowLocalOnly:true)
        try library.editMeal(event.id,product:unknown)
        let backend=EditBackend();backend.saved[.protein]=10
        try await EventSync.perform(library.events[0],using:backend);library.completeSync(event.id)
        XCTAssertEqual(library.events[0].state,.localOnly);XCTAssertTrue(backend.saved.isEmpty);XCTAssertEqual(backend.deleted,[.protein])
    }
    func testReusableMealCatalogUsesExistingWatchIdentity() throws {
        let product=try MealValidation.product([.init(name:"Saved",grams:100,per100g:[.init(.protein,10,.g)])],confirmed:true)
        let catalog=WatchIntake.catalog([product]);XCTAssertEqual(catalog.count,1);XCTAssertEqual(catalog[0].id,product.id)
        let resolved=try QuickIntake.resolve(productID:product.id,quantity:2,products:[product])
        let event=try IntakeEvent(product:resolved.0,servings:resolved.1)
        XCTAssertEqual(try event.healthSamples.first.map { event.canonicalValue(for:$0) },20)
    }
}

extension OfflineFoodTests {
    func testCaffeineUsesCaffeineSourceNotTransFat() throws {
        let coffee=try XCTUnwrap(FoodReference.bundled?.food(id:"171890"))
        let caffeine=try XCTUnwrap(coffee.nutrients.first { $0.nutrient == .caffeine })
        XCTAssertEqual(caffeine.value,40);XCTAssertEqual(caffeine.unit,.mg)
        let product=try MealValidation.product([coffee.portion(quantity:200,unit:.g)],confirmed:true)
        XCTAssertEqual(product.nutrients.first { $0.nutrient == .caffeine }?.value,0.08)
    }
    func testDuplicateServingNamesRequireExplicitSourcePortion() throws {
        let servings=[FoodServing(name:"piece",grams:20),FoodServing(name:"piece",grams:30)]
        XCTAssertThrowsError(try FoodQuantityUnit.serving("piece").grams(1,servings:servings))
        XCTAssertEqual(try FoodQuantityUnit.referenceServing(1).grams(2,servings:servings),60)
    }
    func testFrozenWritePlanRejectsWrongUnitsAndDuplicateTypes() throws {
        let product=try MealValidation.product([.init(name:"A",grams:100,per100g:[.init(.protein,10,.g)])],confirmed:true)
        var event=try IntakeEvent(product:product,servings:1)
        event.healthWriteSnapshot=[.init(.protein,10,.mL)]
        XCTAssertThrowsError(try event.healthSamples)
        event.healthWriteSnapshot=[.init(.protein,10,.g),.init(.protein,10,.g)]
        XCTAssertThrowsError(try event.healthSamples)
    }
}

extension OfflineFoodTests {
    func testRenamingReferenceFoodInvalidatesDatabaseValuesButRetainsManualEntries() throws {
        var item=try XCTUnwrap(FoodReference.bundled?.food(id:"169757")).portion(quantity:200,unit:.g)
        item.nutrientsPer100.removeAll { $0.nutrient == .sodium }
        item.nutrientsPer100.append(.init(.sodium,10,.mg))
        item.rename("Different food")
        XCTAssertEqual(item.grams,200);XCTAssertNil(item.referenceFoodID);XCTAssertNil(item.referenceOnlyNutrients)
        XCTAssertEqual(item.nutrientsPer100,[.init(.sodium,10,.mg)])
    }
    func testGenericChineseEggAndVegetablesRequirePreparationSelection() throws {
        for name in ["鸡蛋","胡萝卜","西兰花","菠菜"] {
            let row=try XCTUnwrap(OfflineMealParser.parse("150克"+name).first)
            XCTAssertNil(row.item.referenceFoodID);XCTAssertGreaterThan(row.candidates.count,1)
        }
    }
}

extension OfflineFoodTests {
    func testDirectMealEnergyWithoutInventingWeight() throws {
        var review = MealReviewState()
        review.energyKilocalories = 650
        XCTAssertTrue(review.recordingIssues.isEmpty)
        let product = try review.beginRecording(requestID: UUID())
        XCTAssertEqual(product.mealDetails?.count, 0)
        XCTAssertEqual(product.nutrients, [.init(.energyConsumed, 650, .kcal)])
        try product.validate()
        let event = try IntakeEvent(product: product, servings: 1)
        XCTAssertEqual(try event.healthSamples.count, 1)
        XCTAssertEqual(try event.healthSamples.first?.nutrient, .energyConsumed)
        let coverage = NutritionRegistry.coverage(.energyConsumed, events: [event], date: event.date)
        XCTAssertEqual(coverage.known, 1); XCTAssertEqual(coverage.total, 1)
    }
    func testEnglishChineseEnergyOnlyAndKilojoules() throws {
        for text in ["Lunch 650 kcal", "午餐650大卡", "能量650千卡", "Lunch 650 Calories", "能量2719.6千焦", "Lunch 2719.6 kJ"] {
            var review = MealReviewState(); try review.prepareText(text)
            XCTAssertEqual(review.energyKilocalories ?? 0, 650, accuracy: 0.000001, text)
            XCTAssertTrue(review.items.isEmpty, text)
            XCTAssertTrue(review.recordingIssues.isEmpty, text)
            let product = try review.beginRecording(requestID: UUID())
            XCTAssertEqual(product.nutrients.first?.value ?? 0, 650, accuracy: 0.000001)
        }
    }
    func testTextPerFoodEnergyReplacesReferenceValueWithoutDoubleCounting() throws {
        var review = MealReviewState()
        try review.prepareText("米饭200g 300kcal，鸡肉150g 250kcal，柠檬茶500mL 180kcal")
        XCTAssertEqual(review.items.count, 3)
        XCTAssertEqual(review.items[0].name, "米饭")
        XCTAssertEqual(review.items[0].grams, 200)
        XCTAssertEqual(review.items[2].milliliters, 500)
        XCTAssertEqual(review.items[0].nutrientsPer100.filter { $0.nutrient == .energyConsumed }.count, 1)
        let product = try review.beginRecording(requestID: UUID())
        XCTAssertEqual(product.nutrients.first { $0.nutrient == .energyConsumed }?.value, 730)
        XCTAssertEqual(product.nutrients.first { $0.nutrient == .energyConsumed }?.origin, .manual)
    }
    func testExplicitWholeMealTotalOverridesFoodSumOnce() throws {
        var review = MealReviewState(); try review.prepareText("200g cooked rice, 能量650kcal")
        XCTAssertEqual(review.items.count, 1)
        XCTAssertEqual(review.energyKilocalories, 650)
        let product = try review.beginRecording(requestID: UUID())
        XCTAssertEqual(product.nutrients.first { $0.nutrient == .energyConsumed }?.value, 650)
        XCTAssertEqual(product.mealOverrides?.first?.value, 650)
    }
    func testEnergyRequiresExplicitUnitsAndDoesNotGuessFromNames() throws {
        var review = MealReviewState(); try review.prepareText("午餐650")
        XCTAssertNil(review.energyKilocalories); XCTAssertFalse(review.recordingIssues.isEmpty)
        XCTAssertThrowsError(try OfflineMealParser.draft("每100克米饭130kcal"))
        XCTAssertThrowsError(try OfflineMealParser.draft("Lunch 600kcal 2500kJ"))
        XCTAssertThrowsError(try OfflineMealParser.draft("米饭200g，鸡肉250kcal"))
        review = MealReviewState(); review.energyKilocalories = -1
        XCTAssertFalse(review.recordingIssues.isEmpty); XCTAssertThrowsError(try review.beginRecording(requestID: UUID()))
    }
    func testChangingTextClearsParsedEnergyButKeepsManualOverride() throws {
        var review = MealReviewState(); try review.prepareText("午餐650kcal")
        try review.prepareText("200g cooked rice")
        XCTAssertNil(review.energyKilocalories)
        review.energyKilocalories = 700
        try review.prepareText("250g cooked rice")
        XCTAssertEqual(review.energyKilocalories, 700)
    }
    @MainActor func testMealEnergyOutboxPermissionRetryDuplicateGuardAndUndo() async throws {
        var review = MealReviewState(); try review.prepareText("午餐650kcal")
        let requestID = UUID(); let product = try review.beginRecording(requestID: requestID)
        let event = try IntakeEvent(product: product, servings: 1)
        var library = Library(); try library.enqueue(event)
        let backend = FakeHealth(); backend.granted = false
        do { try await EventSync.perform(event, using: backend); XCTFail() } catch {}
        XCTAssertEqual(library.events[0].state, .pending); XCTAssertTrue(backend.samples.isEmpty)
        backend.granted = true; try await EventSync.perform(event, using: backend); library.completeSync(event.id)
        XCTAssertEqual(backend.authorizedNutrients, [.energyConsumed])
        XCTAssertEqual(backend.samples[event.syncID(for: .energyConsumed)], 650)
        XCTAssertThrowsError(try MealReviewState.validateRequest(requestID, events: library.events))
        try library.revoke(event.id); try await EventSync.perform(library.events[0], using: backend); library.completeSync(event.id)
        XCTAssertTrue(backend.samples.isEmpty)
    }
}

extension OfflineFoodTests {
    func testManualEnergyCanRecordNamedMealWithUnknownWeightButNotInvalidWeight() throws {
        var review = MealReviewState(); try review.prepareText("自制午餐")
        review.energyKilocalories = 650
        XCTAssertTrue(review.recordsEnergyOnly); XCTAssertTrue(review.recordingIssues.isEmpty)
        let product = try review.beginRecording(requestID: UUID())
        XCTAssertNil(product.mealDetails?.first?.grams)
        XCTAssertEqual(try HealthPlan.samples(for: product), [.init(.energyConsumed, 650, .kcal)])
        review = MealReviewState(); review.items = [.init(name: "Lunch", grams: -1)]; review.energyKilocalories = 650
        XCTAssertFalse(review.recordingIssues.isEmpty)
        review.items = [.init(name: "Lunch", per100g: [.init(.protein, 10, .g)])]
        XCTAssertFalse(review.recordingIssues.isEmpty)
    }
}
