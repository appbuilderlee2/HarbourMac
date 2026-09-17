import XCTest
@testable import HarbourCore

final class CleanPreviewEventTests: XCTestCase {
    func line(_ kind: String, _ fields: [String], token: String = "session") -> String {
        (["@@HARBOUR:" + token, kind] + fields.map { Data($0.utf8).base64EncodedString() }).joined(separator: "\t")
    }
    func begin() -> BridgeEvent { BridgeEvent(kind: "clean_preview_begin", fields: ["1", "mole.clean.deduplicated-ledger", "false"]) }
    func item(_ id: String = "0", identity: String = "dev:inode", size: String = "2", count: String = "1", known: String = "true") -> BridgeEvent {
        BridgeEvent(kind: "clean_preview_item", fields: [id, identity, "User caches", "/測試/a\n\t\\$(x)", size, count, known])
    }
    func end(_ rows: String = "1", rc: String = "0") -> BridgeEvent { BridgeEvent(kind: "clean_preview_end", fields: [rows, rc, "3"]) }
    func session(_ events: [BridgeEvent], rc: Int32 = 0) -> CleanPreviewSession {
        var result = CleanPreviewSession()
        for event in events { result.consume(event) }
        result.finish(exitCode: rc)
        return result
    }

    func testRoundTripAndUnknownSize() throws {
        for event in [begin(), item(), end()] {
            let decoded = try XCTUnwrap(BridgeEvent.parse(line(event.kind, event.fields), token: "session"))
            XCTAssertEqual(decoded.fields, event.fields)
        }
        let result = session([begin(), item(), item("1", identity: "second", known: "false"), end("2")])
        XCTAssertTrue(result.isSuccessful)
        guard result.items.count == 2 else { XCTFail("Expected two items"); return }
        XCTAssertEqual(result.items[0].bytes, 2048)
        XCTAssertNil(result.items[1].bytes)
        XCTAssertEqual(result.knownBytes, 2048)
        XCTAssertEqual(result.unknownSizeCount, 1)
        XCTAssertEqual(result.sizingTimeoutCount, 3)
        XCTAssertEqual(result.categories, ["User caches"])
    }

    func testMalformedFieldsAreRejected() {
        let malformed = [
            BridgeEvent(kind: "clean_preview_begin", fields: ["1", "mole.clean.deduplicated-ledger"]),
            BridgeEvent(kind: "clean_preview_begin", fields: ["2", "mole.clean.deduplicated-ledger", "false"]),
            BridgeEvent(kind: "clean_preview_begin", fields: ["1", "other", "false"]),
            BridgeEvent(kind: "clean_preview_begin", fields: ["1", "mole.clean.deduplicated-ledger", "TRUE"]),
            item("x"), item("-1"), item("01"), item(size: "NaN"), item(size: "-1"),
            item(size: "9007199254740992"), item(size: "9223372036854775808"),
            item(count: "0"), item(count: "9223372036854775808"), item(known: "0"),
            end(""), end(rc: "-1"), end(rc: "256"),
            BridgeEvent(kind: "clean_preview_end", fields: ["1", "0", "-2"])
        ]
        for event in malformed {
            XCTAssertNil(BridgeEvent.parse(line(event.kind, event.fields), token: "session"), event.kind + event.fields.description)
            var result = CleanPreviewSession()
            result.consume(event)
            XCTAssertTrue(result.isInvalid)
        }
        XCTAssertNotNil(BridgeEvent.parse(line(item(size: "9007199254740991").kind, item(size: "9007199254740991").fields), token: "session"))
    }

    func testBadTokenBase64AndFieldCounts() {
        XCTAssertNil(BridgeEvent.parse(line(begin().kind, begin().fields, token: "old"), token: "session"))
        XCTAssertNil(BridgeEvent.parse("@@HARBOUR:session\tclean_preview_begin\t!\t!\t!", token: "session"))
        for event in [begin(), item(), end()] {
            XCTAssertNil(BridgeEvent.parse(line(event.kind, Array(event.fields.dropLast())), token: "session"))
            XCTAssertNil(BridgeEvent.parse(line(event.kind, event.fields + ["extra"]), token: "session"))
        }
    }

    func testSequenceAndCompletionFailClosed() {
        for events in [[], [begin()], [item(), end()], [begin(), item()],
                       [begin(), item(), item(), end("2")], [begin(), item("1"), end()],
                       [begin(), item(), end("2")], [begin(), begin(), end("0")],
                       [begin(), item(), end(), end()], [begin(), end("0"), item()],
                       [begin(), item(), item("1"), end("2")], [begin(), item(), end(rc: "124")]] {
            XCTAssertFalse(session(events).isSuccessful, events.map(\.kind).description)
        }
        XCTAssertFalse(session([begin(), item(), end()], rc: 130).isSuccessful)
        XCTAssertFalse(session([begin(), item(), end()], rc: 74).isSuccessful)
        XCTAssertTrue(session([begin(), end("0")]).isSuccessful)
        var unfinished = CleanPreviewSession()
        [begin(), item(), end()].forEach { unfinished.consume($0) }
        XCTAssertFalse(unfinished.isSuccessful, "End alone cannot authorize apply before process completion")
    }

    func testTotalOverflowInvalidatesInsteadOfWrapping() {
        let result = session([begin(), item(size: "9007199254740991"), item("1", identity: "second"), end("2")])
        XCTAssertTrue(result.isInvalid)
        XCTAssertFalse(result.isSuccessful)
    }
}
