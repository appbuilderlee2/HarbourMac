import XCTest
import SwiftUI
import HarbourCore
@testable import HarbourMac

final class DiskTreemapIntegrationTests: XCTestCase {
    // Synthetic JSON fixtures only; never run analyze-go, Finder or Quick Look.
    private func report() throws -> DiskReport {
        try JSONDecoder().decode(DiskReport.self, from: Data("""
        {"path":"/fixture","total_size":1000,"entries":[
          {"name":"Folder","path":"/fixture/folder","size":600,"is_dir":true},
          {"name":"Small","path":"/fixture/small","size":100,"is_dir":false},
          {"name":"Empty","path":"/fixture/empty","size":0,"is_dir":true}],
         "large_files":[{"name":"Overlap","path":"/fixture/folder/large","size":500}]}
        """.utf8))
    }

    func testMappingUsesOnlyEntriesAndLabelsReturnedScope() throws {
        let content = DiskTreemapContent(report: try report())
        XCTAssertEqual(content.map.totalSize, 700)
        XCTAssertEqual(content.entries.count, 3, "Zero-sized children remain in the accessible fallback")
        XCTAssertEqual(content.map.nodes.flatMap(\.items).map(\.path), ["/fixture/folder", "/fixture/small"])
        XCTAssertTrue(content.scopeNote.contains("正大小"))
        XCTAssertTrue(content.scopeNote.contains("不代表整個磁碟"))
        XCTAssertTrue(content.scopeNote.contains("搜尋"))
    }

    func testNilAndAllZeroReports() throws {
        for json in ["{\"path\":\"/fixture\",\"total_size\":42}",
                     "{\"path\":\"/fixture\",\"total_size\":0,\"entries\":[{\"name\":\"Zero\",\"path\":\"/fixture/zero\",\"size\":0}]}"] {
            let report = try JSONDecoder().decode(DiskReport.self, from: Data(json.utf8))
            XCTAssertTrue(DiskTreemapContent(report: report).map.nodes.isEmpty)
        }
    }

    func testDirectoryActionGuardsBusyAndFileWithoutStartingEngine() throws {
        let entries = try report().entries ?? []
        let folder = try XCTUnwrap(entries.first)
        let file = try XCTUnwrap(entries.dropFirst().first)
        var requests: [String] = []
        DiskTreemapInteraction.open(folder, busy: true) { requests.append($0) }
        DiskTreemapInteraction.open(file, busy: false) { requests.append($0) }
        XCTAssertTrue(requests.isEmpty)
        DiskTreemapInteraction.open(folder, busy: false) { requests.append($0) }
        XCTAssertEqual(requests, [folder.path])
    }

    func testMapIndependentOfListFiltersAndDoesNotChangeSelection() async throws {
        let fixture = try report()
        await MainActor.run {
            let model = AppModel()
            model.disk = fixture
            model.diskQuery = "Overlap"
            model.largeOnly = true
            model.sortByName = true
            model.diskSelection = ["/fixture/folder/large"]
            let content = DiskTreemapContent(report: fixture)
            XCTAssertEqual(content.map.totalSize, 700)
            XCTAssertEqual(model.diskRows.map(\.path), ["/fixture/folder/large"])
            _ = DiskTreemapView(model: model, report: fixture).body
            XCTAssertEqual(model.diskSelection, ["/fixture/folder/large"])
            XCTAssertFalse(model.runner.busy)
            XCTAssertTrue(model.runner.log.isEmpty)
            XCTAssertNil(model.confirm)
            // Exercise the existing model busy guard; it must not launch an engine.
            model.runner.busy = true
            let oldFolder = model.folder
            model.analyze("/fixture/blocked")
            XCTAssertEqual(model.folder, oldFolder)
            XCTAssertNotNil(model.disk)
            model.runner.busy = false
        }
    }
}
