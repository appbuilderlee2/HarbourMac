import XCTest
@testable import HarbourCore

/// Covers the real status-go snapshot schema from cmd/status/metrics.go:
/// cpu.usage, memory.used_percent, network[].rx_rate_mbs/tx_rate_mbs, collected_at.
final class HudTests: XCTestCase {
    private func decode(_ object: [String: Any]) -> HUDMetrics {
        HUDMetrics(object)
    }
    private func parse(_ json: String) throws -> HUDMetrics {
        let data = Data(json.utf8)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return HUDMetrics(object)
    }

    func test_full_snapshot_parses_real_schema() throws {
        let json = """
        {"collected_at":"2026-09-17T10:00:00.123Z","cpu":{"usage":45.5},
         "memory":{"used_percent":62.4,"used":8589934592,"total":17179869184},
         "network":[{"name":"en0","rx_rate_mbs":1.25,"tx_rate_mbs":0.5},
                    {"name":"utun3","rx_rate_mbs":0.75,"tx_rate_mbs":0.5}]}
        """
        let metrics = try parse(json)
        XCTAssertEqual(try XCTUnwrap(metrics.cpu), 45.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(metrics.memory), 62.4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(metrics.received), 2.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(metrics.sent), 1.0, accuracy: 0.001)
        XCTAssertNotNil(metrics.collectedAt)
        XCTAssertTrue(metrics.isFresh(at: metrics.collectedAt!.addingTimeInterval(5)))
    }

    func test_missing_fields_stay_nil_not_zero() {
        let metrics = HUDMetrics(["host": "x"])
        XCTAssertNil(metrics.cpu)
        XCTAssertNil(metrics.memory)
        XCTAssertNil(metrics.received)
        XCTAssertNil(metrics.sent)
        XCTAssertFalse(metrics.isFresh())
        XCTAssertEqual(HUDMetrics.percent(metrics.cpu), "—")
        XCTAssertEqual(HUDMetrics.rate(metrics.received), "—")
    }

    func test_rejects_out_of_range_and_nonfinite() {
        let metrics = HUDMetrics([
            "cpu": ["usage": 120.0],
            "memory": ["used_percent": -3.0],
            "network": [["rx_rate_mbs": Double.infinity], ["tx_rate_mbs": 1.0]]
        ])
        XCTAssertNil(metrics.cpu)
        XCTAssertNil(metrics.memory)
        XCTAssertNil(metrics.received)
        XCTAssertNil(metrics.sent)
    }

    func test_booleans_and_strings_are_not_numbers() {
        let metrics = HUDMetrics([
            "cpu": ["usage": true],
            "memory": ["used_percent": "42"],
            "network": [["rx_rate_mbs": false], ["tx_rate_mbs": "2"]]
        ])
        XCTAssertNil(metrics.cpu)
        XCTAssertNil(metrics.memory)
        XCTAssertNil(metrics.received)
        XCTAssertNil(metrics.sent)
    }

    func test_partial_network_failure_rejected_to_avoid_wrong_total() {
        let metrics = HUDMetrics([
            "network": [["rx_rate_mbs": 1.0], ["rx_rate_mbs": "oops"]]
        ])
        XCTAssertNil(metrics.received)
    }

    func test_stale_snapshot_detected() throws {
        let json = """
        {"collected_at":"2026-09-17T10:00:00.000Z","cpu":{"usage":10}}
        """
        let metrics = try parse(json)
        XCTAssertFalse(metrics.isFresh(at: metrics.collectedAt!.addingTimeInterval(60)))
    }

    func test_missing_collected_at_is_not_fresh() {
        let metrics = HUDMetrics(["cpu": ["usage": 10]])
        XCTAssertFalse(metrics.isFresh())
    }

    func test_formatting() {
        XCTAssertEqual(HUDMetrics.percent(12.4), "12%")
        XCTAssertEqual(HUDMetrics.rate(0.5), "0.50 MB/s")
    }
}
