import XCTest
@testable import AnalogAnchorKit

final class StorageTests: XCTestCase {

    func testSharedStoreFallsBackToLocalDirectoryWhenNoAppGroup() {
        // On Linux / unsigned builds the App Group container is unavailable; the
        // store must still resolve a usable directory rather than crash.
        if !SharedStore.isAppGroupAvailable() {
            let directory = SharedStore.directory()
            XCTAssertFalse(directory.path.isEmpty)
            XCTAssertTrue(SharedStore.databaseURL().lastPathComponent.hasSuffix(".store"))
        }
    }

    func testPreferencesStoreRoundTrip() {
        let suite = "com.analoganchor.tests.\(UUID().uuidString)"
        let store = PreferencesStore(suiteName: suite)
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        XCTAssertFalse(store.bool(.isOnboarded))
        store.set(true, for: .isOnboarded)
        XCTAssertTrue(store.bool(.isOnboarded))

        store.set(275, for: .reservePoints)
        XCTAssertEqual(store.int(.reservePoints), 275)

        store.set(26.2285, for: .userLatitude)
        XCTAssertEqual(store.double(.userLatitude), 26.2285, accuracy: 0.0001)

        store.set("Manama", for: .userLocationName)
        XCTAssertEqual(store.string(.userLocationName), "Manama")
    }

    func testScreenTimeStatusPersistence() {
        let suite = "com.analoganchor.tests.\(UUID().uuidString)"
        let store = PreferencesStore(suiteName: suite)
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        store.set(ScreenTimeAuthorizationStatus.approved.rawValue, for: .screenTimeAuthorizationStatus)
        let raw = store.string(.screenTimeAuthorizationStatus)
        XCTAssertEqual(raw, "approved")
        XCTAssertEqual(ScreenTimeAuthorizationStatus(rawValue: raw ?? ""), .approved)
    }
}
