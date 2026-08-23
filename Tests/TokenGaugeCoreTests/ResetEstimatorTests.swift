import XCTest
@testable import TokenGaugeCore

final class ResetEstimatorTests: XCTestCase {
    func testNoResetDetectedWithoutDrop() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let samples = [
            UsageSample(time: base, value: 0),
            UsageSample(time: base.addingTimeInterval(60), value: 5),
            UsageSample(time: base.addingTimeInterval(120), value: 10),
        ]
        let result = ResetEstimator.estimateNextReset(samples: samples, windowDuration: 3600, now: base.addingTimeInterval(200))
        XCTAssertNil(result)
    }

    func testDetectsDropAndProjectsForward() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let samples = [
            UsageSample(time: base, value: 20),
            UsageSample(time: base.addingTimeInterval(60), value: 40),
            UsageSample(time: base.addingTimeInterval(120), value: 0), // reset happened here
            UsageSample(time: base.addingTimeInterval(180), value: 5),
        ]
        let windowDuration: TimeInterval = 3600
        let now = base.addingTimeInterval(180)
        let result = ResetEstimator.estimateNextReset(samples: samples, windowDuration: windowDuration, now: now)
        XCTAssertEqual(result, base.addingTimeInterval(120 + windowDuration))
    }

    func testProjectsForwardPastMultiplePeriodsWhenStale() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let windowDuration: TimeInterval = 3600
        let samples = [
            UsageSample(time: base, value: 20),
            UsageSample(time: base.addingTimeInterval(60), value: 0), // reset anchor
        ]
        // "now" is 3 full window periods after the anchor plus a bit
        let now = base.addingTimeInterval(60 + windowDuration * 3 + 100)
        let result = ResetEstimator.estimateNextReset(samples: samples, windowDuration: windowDuration, now: now)
        let expectedAnchor = base.addingTimeInterval(60 + windowDuration * 3)
        XCTAssertEqual(result, expectedAnchor.addingTimeInterval(windowDuration))
        XCTAssertGreaterThan(result!, now)
    }

    func testInsufficientSamplesReturnsNil() {
        let result = ResetEstimator.estimateNextReset(samples: [], windowDuration: 3600, now: Date())
        XCTAssertNil(result)
    }
}
