import XCTest
@testable import HarbourCore

final class ProtocolTests: XCTestCase {
    func event(_ kind: String, _ fields: [String], token: String = "session") -> String {
        (["@@HARBOUR:" + token, kind] + fields.map { Data($0.utf8).base64EncodedString() }).joined(separator: "\t")
    }
    func testUnicodePathsAreData() {
        let path = "/Users/我/Downloads/a\n$(touch nope)\t'\".dmg"
        let value = BridgeEvent.parse(event("row", ["0", "測試", path, "3 MB", "false"]), token: "session")
        XCTAssertEqual(value?.fields[2], path)
    }
    func testWrongSessionCannotPrompt() {
        XCTAssertNil(BridgeEvent.parse(event("confirm", ["delete"], token: "old"), token: "session"))
    }
    func testMalformedPayloadDoesNotBecomeConfirmation() {
        XCTAssertNil(BridgeEvent.parse("@@HARBOUR:session\tconfirm\t!", token: "session"))
        XCTAssertNil(BridgeEvent.parse(event("confirm", []), token: "session"))
        XCTAssertNil(BridgeEvent.parse(event("confirm", ["one", "two"]), token: "session"))
    }
    func testInvalidSelectionIsDenied() {
        XCTAssertNil(TextFormat.selection([], available: [0, 1]))
        XCTAssertNil(TextFormat.selection([2], available: [0, 1]))
        XCTAssertNil(TextFormat.selection([-1], available: [-1, 0]))
        XCTAssertEqual(TextFormat.selection([1, 0], available: [0, 1, 2]), "0,1\n")
    }
    func testANSIIsRemovedWithoutChangingPaths() {
        XCTAssertEqual(TextFormat.plain("\u{001B}[31m/測試/a[1]\u{001B}[0m"), "/測試/a[1]")
    }
}
