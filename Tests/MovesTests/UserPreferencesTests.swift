import XCTest
@testable import Moves

/// Tests the Phase-6 `UserPreferences` value type, the AppStore wiring for
/// badge-toggle / alert-offsets / onboarding marker, and the label helpers
/// used by the Settings editor.
@MainActor
final class UserPreferencesTests: XCTestCase {

  // MARK: - JSON round-trip

  func testEncodeDecodeRoundTrip() throws {
    let prefs = UserPreferences(
      reminderOffsetsMinutes: [0, 15],
      deadlineTaskOffsetsMinutes: [24 * 60, 60, 0],
      badgeEnabled: false,
      onboardedVersion: "1.0"
    )
    let json = try prefs.encodedJSON()
    let decoded = try XCTUnwrap(UserPreferences.decodedJSON(json))
    XCTAssertEqual(decoded, prefs)
  }

  func testDecodeMissingKeysFallBackToDefaults() throws {
    // Older builds didn't carry deadlineTaskOffsetsMinutes — decode must
    // fill it from defaults rather than nil-trapping.
    let partial = "{\"badgeEnabled\": false}"
    let decoded = try XCTUnwrap(UserPreferences.decodedJSON(partial))
    XCTAssertFalse(decoded.badgeEnabled)
    XCTAssertEqual(decoded.reminderOffsetsMinutes, UserPreferences.default.reminderOffsetsMinutes)
    XCTAssertEqual(decoded.deadlineTaskOffsetsMinutes, UserPreferences.default.deadlineTaskOffsetsMinutes)
    XCTAssertNil(decoded.onboardedVersion)
  }

  func testDecodeMalformedReturnsNil() {
    XCTAssertNil(UserPreferences.decodedJSON("not-json"))
  }

  // MARK: - Defaults

  func testDefaultsMatchPlanContract() {
    let d = UserPreferences.default
    XCTAssertEqual(d.reminderOffsetsMinutes, [0],
                   "reminders default to 'at due time' per Phase 6 plan")
    XCTAssertEqual(d.deadlineTaskOffsetsMinutes, [24 * 60, 60, 0],
                   "deadline tasks default to 'morning of / 1h / at due time' per §8.3")
    XCTAssertTrue(d.badgeEnabled)
    XCTAssertNil(d.onboardedVersion)
  }

  // MARK: - Labels

  func testOffsetLabels() {
    XCTAssertEqual(AlertOffsetLabel.describe(minutes: 0), "at due time")
    XCTAssertEqual(AlertOffsetLabel.describe(minutes: 15), "15m before")
    XCTAssertEqual(AlertOffsetLabel.describe(minutes: 60), "1h before")
    XCTAssertEqual(AlertOffsetLabel.describe(minutes: 90), "1h 30m before")
    XCTAssertEqual(AlertOffsetLabel.describe(minutes: 24 * 60), "morning of")
    XCTAssertEqual(AlertOffsetLabel.describe(minutes: 2 * 24 * 60), "2d before")
  }

  // MARK: - AppStore wiring

  func testSavingPreferencesRoundTripsAcrossRelaunch() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appending(path: "moves-prefs-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let dbPath = tempDir.appending(path: "moves.sqlite3").path(percentEncoded: false)

    do {
      let writer = AppStore(databasePath: dbPath, enableNotifications: false)
      var prefs = UserPreferences.default
      prefs.badgeEnabled = false
      prefs.reminderOffsetsMinutes = [0, 10]
      await writer.saveUserPreferences(prefs)
    }

    let reader = AppStore(databasePath: dbPath, enableNotifications: false)
    await reader.loadUserPreferences()
    XCTAssertFalse(reader.preferences.badgeEnabled)
    XCTAssertEqual(reader.preferences.reminderOffsetsMinutes, [0, 10])
  }

  func testBadgeToggleHidesRenderedCount() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appending(path: "moves-badge-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let dbPath = tempDir.appending(path: "moves.sqlite3").path(percentEncoded: false)

    let store = AppStore(databasePath: dbPath, enableNotifications: false)
    let now = Int64(Date().timeIntervalSince1970)
    let item = Item(
      title: "due now",
      status: .open,
      kind: .reminder,
      dueAt: now - 60,
      dueKind: .datetime,
      interruptionKind: .hard
    )
    try await store.itemRepository.insert(item)
    await store.refreshDueCount()
    XCTAssertEqual(store.dueOrOverdueHardCount, 1)
    XCTAssertEqual(store.renderedBadgeCount, 1, "badge enabled by default")

    var prefs = store.preferences
    prefs.badgeEnabled = false
    await store.saveUserPreferences(prefs)
    XCTAssertEqual(store.dueOrOverdueHardCount, 1, "DB count is unchanged")
    XCTAssertEqual(store.renderedBadgeCount, 0, "toggle hides the rendered count")
  }

  func testOnboardingMarkAndReset() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appending(path: "moves-onboard-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let dbPath = tempDir.appending(path: "moves.sqlite3").path(percentEncoded: false)

    let store = AppStore(databasePath: dbPath, enableNotifications: false)
    XCTAssertNil(store.preferences.onboardedVersion)

    await store.markOnboardingComplete()
    XCTAssertEqual(store.preferences.onboardedVersion, UserPreferences.currentOnboardingVersion)

    await store.resetOnboarding()
    XCTAssertNil(store.preferences.onboardedVersion)
  }
}
