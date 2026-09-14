import XCTest
@testable import HarbourCore

final class SystemDataTests: XCTestCase {
    func testMissingAndZeroThermalAreNotStoppedFans() {
        XCTAssertNil(SystemData.positiveReading(nil))
        XCTAssertNil(SystemData.positiveReading(0))
        XCTAssertNil(SystemData.positiveReading(-1))
        XCTAssertNil(SystemData.positiveReading(Double.nan))
        XCTAssertEqual(SystemData.positiveReading(2400), 2400)
        // A real zero-percent battery must remain visible.
        XCTAssertEqual(SystemData.percentage("0%"), 0)
        XCTAssertNil(SystemData.percentage("Unknown"))
        XCTAssertNil(SystemData.percentage(101))
    }
    func testBluetoothComponentsAndConnectionGroups() throws {
        let data = Data(#"{"SPBluetoothDataType":[{"device_connected":[{"AirPods":{"device_batteryLevelLeft":"0%","device_batteryLevelRight":"75%","device_batteryLevelCase":"invalid"}}],"device_not_connected":[{"Mouse":{}}]}]}"#.utf8)
        let rows = try SystemData.accessories(data)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows[0].connected)
        XCTAssertEqual(rows[0].levels.map(\.value), [0, 75])
        XCTAssertFalse(rows[1].connected)
        XCTAssertTrue(rows[1].levels.isEmpty)
        XCTAssertThrowsError(try SystemData.accessories(Data("{}".utf8)))
    }
    func testBrewFormulaAndCaskVersionsAndInvalidNames() throws {
        let data = Data(#"{"formulae":[{"name":"wget","installed_versions":["1.0"],"current_version":"2.0"},{"name":"--force","installed_versions":[],"current_version":"1"}],"casks":[{"name":"sample-app","installed_versions":"1.5","current_version":"2.0"}]}"#.utf8)
        let rows = try SystemData.brewUpdates(data)
        XCTAssertEqual(rows.map(\.name), ["wget", "sample-app"])
        XCTAssertEqual(rows[1].installed, "1.5")
        XCTAssertTrue(rows[1].cask)
        XCTAssertThrowsError(try SystemData.brewUpdates(Data("{}".utf8)))
    }
    func testAppcastReadsMinimumSystemAndChannel() throws {
        let data = Data("""
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:shortVersionString>2.4</sparkle:shortVersionString>
        <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
        <sparkle:channel>beta</sparkle:channel><enclosure url="https://example.org/app.zip"/></item>
        <item><enclosure sparkle:shortVersionString="2.3" url="https://example.org/app.zip"/></item>
        </channel></rss>
        """.utf8)
        let releases = try AppcastReader().read(data)
        XCTAssertEqual(releases.count, 2)
        XCTAssertEqual(releases[0].minimumOS, "13.0")
        XCTAssertEqual(releases[0].channel, "beta")
        XCTAssertEqual(releases[1].version, "2.3")
        XCTAssertTrue(AppcastReader.newer("2.10", than: "2.9"))
        XCTAssertFalse(AppcastReader.newer("2.4-beta", than: "2.3"))
        XCTAssertFalse(AppcastReader.newer("2.3", than: "unknown"))
        XCTAssertThrowsError(try AppcastReader().read(Data("<rss>".utf8)))
    }
}
