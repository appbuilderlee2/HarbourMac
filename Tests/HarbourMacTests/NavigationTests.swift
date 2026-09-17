import XCTest
@testable import HarbourMac

final class NavigationTests: XCTestCase {
    func testEveryPageHasExactlyOneDestination() {
        let grouped = ObservatorySection.allCases.flatMap(\.pages)
        let auxiliary: [Page] = [.history, .protection, .settings]
        XCTAssertEqual(Set(grouped).count, grouped.count)
        XCTAssertEqual(Set(grouped + auxiliary), Set(Page.allCases))
        XCTAssertTrue(Set(grouped).isDisjoint(with: auxiliary))
        XCTAssertEqual(Set(ObservatorySection.allCases.map(\.hotKeyLabel)).count, 5)
    }

    func testSectionDefaultsAndRememberedSubpages() async {
        await MainActor.run {
            let model = AppModel()
            for section in ObservatorySection.allCases {
                model.navigate(to: section)
                XCTAssertEqual(model.page, section.pages.first)
            }
            model.navigate(to: Page.login)
            model.navigate(to: Page.installer)
            model.navigate(to: ObservatorySection.software)
            XCTAssertEqual(model.page, .login)
            model.navigate(to: ObservatorySection.clean)
            XCTAssertEqual(model.page, .installer)
            model.navigate(to: Page.settings)
            model.navigate(to: ObservatorySection.software)
            XCTAssertEqual(model.page, .login)
        }
    }

    func testBusySelectionAndConfirmationBlockBothRoutes() async {
        await MainActor.run {
            let model = AppModel()
            model.navigate(to: Page.login)
            for state in 0..<3 {
                model.runner.busy = state == 0
                model.selecting = state == 1
                model.confirm = state == 2 ? "fixture confirmation" : nil
                XCTAssertFalse(model.canNavigate)
                model.navigate(to: Page.uninstall)
                model.navigate(to: ObservatorySection.clean)
                XCTAssertEqual(model.page, .login)
            }
            model.runner.busy = false
            model.selecting = false
            model.confirm = nil
            XCTAssertTrue(model.canNavigate)
            model.navigate(to: ObservatorySection.clean)
            XCTAssertEqual(model.page, .clean)
            model.navigate(to: ObservatorySection.software)
            XCTAssertEqual(model.page, .login, "Blocked navigation must not change remembered page")
        }
    }
}
