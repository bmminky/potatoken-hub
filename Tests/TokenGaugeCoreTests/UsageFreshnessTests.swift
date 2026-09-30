import Foundation
import XCTest
@testable import TokenGaugeCore

final class UsageFreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_757_600)

    func testCodexChoosesNewestRecordRatherThanNewestModifiedFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let olderRecord = directory.appendingPathComponent("recent-file.jsonl")
        let newerRecord = directory.appendingPathComponent("older-file.jsonl")
        try codexLine(at: now.addingTimeInterval(-300), used: 20, minutes: 300)
            .write(to: olderRecord, atomically: true, encoding: .utf8)
        try codexLine(at: now.addingTimeInterval(-60), used: 30, minutes: 300)
            .write(to: newerRecord, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: olderRecord.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-30)], ofItemAtPath: newerRecord.path)

        let snapshot = CodexUsageReader.readSnapshot(sessionsDir: directory, now: now)
        XCTAssertEqual(snapshot.lastRecordDate, now.addingTimeInterval(-60))
        XCTAssertEqual(snapshot.fiveHourRemainingPercent, 70)
    }

    func testCodexDoesNotPutWeeklyValueInFiveHourBadge() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("weekly.jsonl")
        try codexLine(at: now.addingTimeInterval(-60), used: 26, minutes: 10080)
            .write(to: file, atomically: true, encoding: .utf8)

        let snapshot = CodexUsageReader.readSnapshot(sessionsDir: directory, now: now)
        XCTAssertEqual(snapshot.windows.first?.remainingPercent, 74)
        XCTAssertNil(snapshot.fiveHourRemainingPercent)
    }

    func testPlusChoosesFiveHourWindowForMenuBar() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("plus.jsonl")
        try codexLine(at: now.addingTimeInterval(-60), used: 30, minutes: 300,
                      planType: "plus", secondaryUsed: 20, secondaryMinutes: 10080)
            .write(to: file, atomically: true, encoding: .utf8)

        let snapshot = CodexUsageReader.readSnapshot(sessionsDir: directory, now: now)
        XCTAssertEqual(snapshot.codexPlan, .plus)
        XCTAssertEqual(snapshot.menuBarWindow?.windowMinutes, 300)
        XCTAssertEqual(snapshot.menuBarWindow?.remainingPercent, 70)
    }

    func testProChoosesWeeklyWindowEvenWhenFiveHourIsPresent() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("pro.jsonl")
        try codexLine(at: now.addingTimeInterval(-60), used: 29, minutes: 10080,
                      planType: "prolite", secondaryUsed: 60, secondaryMinutes: 300)
            .write(to: file, atomically: true, encoding: .utf8)

        let snapshot = CodexUsageReader.readSnapshot(sessionsDir: directory, now: now)
        XCTAssertEqual(snapshot.codexPlan, .pro)
        XCTAssertEqual(snapshot.menuBarWindow?.windowMinutes, 10080)
        XCTAssertEqual(snapshot.menuBarWindow?.remainingPercent, 71)
    }

    func testCodexIgnoresNewerSeparateModelLimit() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("mixed-limits.jsonl")
        let general = codexLine(at: now.addingTimeInterval(-60), used: 29,
                                minutes: 10080, planType: "prolite", limitId: "codex")
        let separate = codexLine(at: now.addingTimeInterval(-30), used: 90,
                                 minutes: 10080, planType: "prolite", limitId: "codex_bengalfox")
        try (general + separate).write(to: file, atomically: true, encoding: .utf8)

        let snapshot = CodexUsageReader.readSnapshot(sessionsDir: directory, now: now)
        XCTAssertEqual(snapshot.lastRecordDate, now.addingTimeInterval(-60))
        XCTAssertEqual(snapshot.menuBarWindow?.remainingPercent, 71)
    }

    func testCodexFreshnessUsesRecordTimeNotFileMtime() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("stale.jsonl")
        try codexLine(at: now.addingTimeInterval(-1800), used: 40, minutes: 300)
            .write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)

        let snapshot = CodexUsageReader.readSnapshot(sessionsDir: directory, now: now)
        XCTAssertEqual(snapshot.freshness, .stale)
        XCTAssertTrue(snapshot.hidingStaleUsage.windows.isEmpty)
        XCTAssertEqual(snapshot.hidingStaleUsage.lastRecordDate, now.addingTimeInterval(-1800))
    }

    func testCodexReadsLatestEventAcrossChunkBoundary() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("large.jsonl")
        let oldLine = codexLine(at: now.addingTimeInterval(-120), used: 20, minutes: 300)
        let largeUnrelatedLine = "{\"unrelated\":\"\(String(repeating: "x", count: 70_000))\"}\n"
        let newLine = codexLine(at: now.addingTimeInterval(-30), used: 35, minutes: 300)
        try (oldLine + newLine + largeUnrelatedLine)
            .write(to: file, atomically: true, encoding: .utf8)

        let snapshot = CodexUsageReader.readSnapshot(sessionsDir: directory, now: now)
        XCTAssertEqual(snapshot.lastRecordDate, now.addingTimeInterval(-30))
        XCTAssertEqual(snapshot.fiveHourRemainingPercent, 65)
    }

    func testClaudeFreshnessUsesLatestSampleTimeNotFileMtime() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("plan-usage-history.json")
        let sampleMillis = Int64(now.addingTimeInterval(-1800).timeIntervalSince1970 * 1000)
        try "{\"version\":2,\"samples\":[{\"t\":\(sampleMillis),\"u\":{\"fh\":20,\"sd\":50}}]}"
            .write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)

        let snapshot = ClaudeUsageReader.readSnapshot(at: file, now: now)
        XCTAssertEqual(snapshot.freshness, .stale)
        XCTAssertEqual(snapshot.lastRecordDate, now.addingTimeInterval(-1800))
        XCTAssertTrue(snapshot.hidingStaleUsage.windows.isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func codexLine(at date: Date, used: Int, minutes: Int,
                           planType: String? = nil, secondaryUsed: Int? = nil,
                           secondaryMinutes: Int = 10080, limitId: String? = nil) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: date)
        let plan = planType.map { "\"plan_type\":\"\($0)\"," } ?? ""
        let limit = limitId.map { "\"limit_id\":\"\($0)\"," } ?? ""
        let secondary = secondaryUsed.map {
            "{\"used_percent\":\($0),\"window_minutes\":\(secondaryMinutes),\"resets_at\":null}"
        } ?? "null"
        return "{\"timestamp\":\"\(timestamp)\",\"payload\":{\"rate_limits\":{\(limit)\(plan)\"primary\":{\"used_percent\":\(used),\"window_minutes\":\(minutes),\"resets_at\":null},\"secondary\":\(secondary)}}}\n"
    }
}
