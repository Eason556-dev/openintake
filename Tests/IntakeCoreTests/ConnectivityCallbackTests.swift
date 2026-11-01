import XCTest
import IntakeShared

final class ConnectivityCallbackTests: XCTestCase {
    @MainActor func testLegacyBackgroundReplyHopsToMainActor() async {
        let received = expectation(description: "Main actor receives reply")
        let callback = ConnectivityCallbacks.reply { envelope, receipt in
            MainActor.assertIsolated()
            XCTAssertEqual(envelope, Data([1, 2, 3]))
            XCTAssertEqual(receipt, Data([4, 5]))
            received.fulfill()
        }
        // Mirrors WC calling a stored Obj-C completion off the UI actor.
        await Task.detached { callback(["envelope": Data([1, 2, 3]), "receipt": Data([4, 5])]) }.value
        await fulfillment(of: [received], timeout: 3)
    }
    @MainActor func testRepeatedBackgroundRepliesAndMalformedFieldsRemainSafe() async {
        let received = expectation(description: "All callbacks arrive")
        received.expectedFulfillmentCount = 30
        let callback = ConnectivityCallbacks.reply { envelope, receipt in
            MainActor.assertIsolated()
            XCTAssertNil(envelope); XCTAssertNil(receipt)
            received.fulfill()
        }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<30 { group.addTask { callback(["envelope": "not data", "receipt": 12]) } }
        }
        await fulfillment(of: [received], timeout: 3)
    }
    @MainActor func testBackgroundErrorCallbackDoesNotInheritMainActor() async {
        let callback = ConnectivityCallbacks.ignoreError
        await Task.detached { callback(CocoaError(.fileReadUnknown)) }.value
    }
}
