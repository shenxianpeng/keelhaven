import XCTest
@testable import KeelhavenCore

final class PrunePolicyTests: XCTestCase {
    private let created = Date(timeIntervalSince1970: 1_755_200_000)
    private let week: TimeInterval = 7 * 86400

    private func makePlan(
        retention: RetentionPolicy,
        lastPrune: PruneRunRecord? = nil
    ) -> BackupPlan {
        BackupPlan(
            name: "Test",
            sourcePaths: ["/tmp/src"],
            destination: .local(path: "/tmp/repo"),
            schedule: .hourly,
            retention: retention,
            createdAt: created,
            lastPrune: lastPrune
        )
    }

    func testOffIsNeverDue() {
        let plan = makePlan(retention: .off)
        XCTAssertFalse(PrunePolicy.isDue(plan, now: created.addingTimeInterval(365 * 86400)))
    }

    func testNewPlanWaitsAFullInterval() {
        // A brand-new plan has nothing to reclaim, so the first pass waits a
        // week from creation.
        let plan = makePlan(retention: .year)
        XCTAssertFalse(PrunePolicy.isDue(plan, now: created))
        XCTAssertFalse(PrunePolicy.isDue(plan, now: created.addingTimeInterval(week - 1)))
        XCTAssertTrue(PrunePolicy.isDue(plan, now: created.addingTimeInterval(week)))
    }

    func testPrunedPlanCountsFromLastPass() {
        let prunedAt = created.addingTimeInterval(3 * 86400)
        let plan = makePlan(
            retention: .month,
            lastPrune: PruneRunRecord(date: prunedAt, success: true)
        )
        XCTAssertFalse(PrunePolicy.isDue(plan, now: prunedAt.addingTimeInterval(week - 1)))
        XCTAssertTrue(PrunePolicy.isDue(plan, now: prunedAt.addingTimeInterval(week)))
    }

    func testFailedPassStillAdvancesTheClock() {
        // A destination that keeps failing prunes retries weekly, not after
        // every backup — the anchor is the last attempt, pass or fail.
        let failedAt = created.addingTimeInterval(week)
        let plan = makePlan(
            retention: .year,
            lastPrune: PruneRunRecord(date: failedAt, success: false, errorMessage: "repository is locked")
        )
        XCTAssertFalse(PrunePolicy.isDue(plan, now: failedAt.addingTimeInterval(86400)))
        XCTAssertTrue(PrunePolicy.isDue(plan, now: failedAt.addingTimeInterval(week)))
    }
}

/// `RetentionPolicy.lastN` — the one policy whose behaviour is chosen by a
/// number a person types, so the tests are mostly about what happens when
/// that number is wrong (issue #52).
final class RetentionKeepLastTests: XCTestCase {
    func testKeepLastRendersOnlyTheCountFlag() {
        XCTAssertEqual(RetentionPolicy.lastN(10).keepArguments, ["--keep-last", "10"])
        XCTAssertEqual(RetentionPolicy.lastN(1).keepArguments, ["--keep-last", "1"])
    }

    /// The presets are unchanged — this case must not have altered them.
    func testPresetsAreUntouched() {
        XCTAssertEqual(RetentionPolicy.off.keepArguments, [])
        XCTAssertEqual(
            RetentionPolicy.year.keepArguments,
            ["--keep-last", "3", "--keep-daily", "7", "--keep-weekly", "5", "--keep-monthly", "12"]
        )
        XCTAssertEqual(
            RetentionPolicy.month.keepArguments,
            ["--keep-last", "3", "--keep-daily", "7", "--keep-weekly", "4"]
        )
    }

    /// The assertion that matters most: no count, however wrong, may render a
    /// `forget` that keeps nothing. Zero and negatives clamp up to one.
    func testAnOutOfRangeCountCanNeverKeepNothing() {
        for count in [0, -1, Int.min + 1] {
            let arguments = RetentionPolicy.lastN(count).keepArguments
            XCTAssertEqual(arguments, ["--keep-last", "1"], "count \(count) must clamp to the floor")
            XCTAssertFalse(arguments.isEmpty, "an empty policy would make restic refuse or delete")
        }
        XCTAssertEqual(RetentionPolicy.lastN(Int.max).keepArguments, ["--keep-last", "999"])
        XCTAssertEqual(RetentionPolicy.lastN(1000).keepArguments, ["--keep-last", "999"])
    }

    func testKeepLastCountReportsTheClampedValueAndNilForPresets() {
        XCTAssertEqual(RetentionPolicy.lastN(10).keepLastCount, 10)
        XCTAssertEqual(RetentionPolicy.lastN(0).keepLastCount, 1)
        XCTAssertNil(RetentionPolicy.off.keepLastCount)
        XCTAssertNil(RetentionPolicy.year.keepLastCount)
        XCTAssertNil(RetentionPolicy.month.keepLastCount)
    }

    /// `.lastN` must be due for a prune like any other deleting policy, and
    /// `.off` must still never be.
    func testKeepLastIsSubjectToThePrunePolicy() {
        let created = Date(timeIntervalSince1970: 1_755_000_000)
        func plan(_ retention: RetentionPolicy) -> BackupPlan {
            BackupPlan(
                name: "Test",
                sourcePaths: ["/tmp/src"],
                destination: .local(path: "/tmp/repo"),
                schedule: .daily(hour: 21, minute: 0),
                retention: retention,
                createdAt: created
            )
        }
        let later = created.addingTimeInterval(30 * 24 * 3600)
        XCTAssertTrue(PrunePolicy.isDue(plan(.lastN(10)), now: later))
        XCTAssertFalse(PrunePolicy.isDue(plan(.off), now: later))
    }
}
