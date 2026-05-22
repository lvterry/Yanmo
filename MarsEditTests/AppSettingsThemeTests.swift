import XCTest
@testable import MarsEdit

final class AppSettingsThemeTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID())")!
    }

    func testMigrationLightTheme() {
        let d = makeDefaults()
        d.set("solarized-light", forKey: "selectedThemeId")
        AppSettings.migrateIfNeeded(defaults: d)
        XCTAssertEqual(d.string(forKey: "selectedLightThemeId"), "solarized-light")
        XCTAssertNil(d.string(forKey: "selectedThemeId"))
    }

    func testMigrationDarkTheme() {
        let d = makeDefaults()
        d.set("nord", forKey: "selectedThemeId")
        AppSettings.migrateIfNeeded(defaults: d)
        XCTAssertEqual(d.string(forKey: "selectedDarkThemeId"), "nord")
        XCTAssertNil(d.string(forKey: "selectedThemeId"))
    }

    func testMigrationUnknownIdIsDiscarded() {
        let d = makeDefaults()
        d.set("nonexistent-theme", forKey: "selectedThemeId")
        AppSettings.migrateIfNeeded(defaults: d)
        XCTAssertNil(d.string(forKey: "selectedThemeId"))
        XCTAssertNil(d.string(forKey: "selectedLightThemeId"))
        XCTAssertNil(d.string(forKey: "selectedDarkThemeId"))
    }

    func testMigrationSkipsWhenKeyAbsent() {
        let d = makeDefaults()
        d.set("solarized-light", forKey: "selectedLightThemeId")
        AppSettings.migrateIfNeeded(defaults: d)
        XCTAssertEqual(d.string(forKey: "selectedLightThemeId"), "solarized-light")
    }
}
