import XCTest
@testable import Moves

/// Cover the pure elapsed-time formatter the Current card uses.
/// Format rules (batch 3 brief):
///   - sub-hour values render `mm:ss`
///   - one hour or more renders `hh:mm:ss`
///   - negative or zero intervals clamp to `00:00`
final class ElapsedTimeTests: XCTestCase {

  func testZero() {
    XCTAssertEqual(ElapsedTime.format(0), "00:00")
  }

  func testSixteenSeconds() {
    XCTAssertEqual(ElapsedTime.format(16), "00:16")
  }

  func testSeventyFiveSeconds() {
    XCTAssertEqual(ElapsedTime.format(75), "01:15")
  }

  func testOneHourOneMinuteOneSecond() {
    XCTAssertEqual(ElapsedTime.format(3661), "01:01:01")
  }

  func testNegativeClampsToZero() {
    XCTAssertEqual(ElapsedTime.format(-5), "00:00")
  }

  func testFractionalSecondsFloorToWholeSeconds() {
    // 16.9s should still read as "00:16" — the digits advance on the
    // wall-clock second, not when the fractional crosses 0.5.
    XCTAssertEqual(ElapsedTime.format(16.9), "00:16")
  }

  func testExactlyOneHour() {
    XCTAssertEqual(ElapsedTime.format(3600), "01:00:00")
  }
}
