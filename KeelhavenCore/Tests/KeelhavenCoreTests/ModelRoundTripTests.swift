import XCTest
@testable import KeelhavenCore

final class ModelRoundTripTests: XCTestCase {
    // ISO 8601 persistence keeps whole-second precision, so fixed
    // whole-second dates round-trip exactly.
    private let date = Date(timeIntervalSince1970: 1_755_200_000)

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: encoder.encode(value))
    }

    func testBackupPlanRoundTripAllDestinations() throws {
        let destinations: [Destination] = [
            .local(path: "/Volumes/Backup/repo"),
            .s3(S3Config(endpoint: "s3.amazonaws.com", bucket: "b", pathPrefix: "p", accessKeyID: "AKIA")),
            .sftp(SFTPConfig(user: "u", host: "h.local", port: 2222, path: "/data")),
            .rest(RESTConfig(url: "http://127.0.0.1:8000/", username: "restic")),
        ]
        for destination in destinations {
            let plan = BackupPlan(
                name: "Documents",
                sourcePaths: ["/Users/me/Documents"],
                destination: destination,
                schedule: .daily(hour: 21, minute: 30),
                createdAt: date,
                lastRun: BackupRunRecord(
                    date: date,
                    success: true,
                    snapshotID: "c4e6a708",
                    filesNew: 308,
                    dataAddedBytes: 400_775_099,
                    duration: 1.62
                )
            )
            XCTAssertEqual(try roundTrip(plan), plan)
        }
    }

    func testScheduleRoundTrip() throws {
        XCTAssertEqual(try roundTrip(Schedule.hourly), .hourly)
        XCTAssertEqual(try roundTrip(Schedule.daily(hour: 3, minute: 15)), .daily(hour: 3, minute: 15))
        XCTAssertEqual(
            try roundTrip(Schedule.weekly(weekday: 6, hour: 8, minute: 30)),
            .weekly(weekday: 6, hour: 8, minute: 30)
        )
    }

    func testFailedRunRecordRoundTrip() throws {
        let record = BackupRunRecord(
            date: date,
            success: false,
            errorMessage: "Fatal: wrong password or no key found"
        )
        XCTAssertEqual(try roundTrip(record), record)
    }

    func testPlanWithCheckFieldsRoundTrip() throws {
        let plan = BackupPlan(
            name: "Documents",
            sourcePaths: ["/Users/me/Documents"],
            destination: .local(path: "/Volumes/Backup/repo"),
            schedule: .hourly,
            checkCadence: .monthly,
            createdAt: date,
            lastCheck: CheckRunRecord(
                date: date,
                success: false,
                duration: 12.5,
                errorMessage: "error: load <data/1234>: invalid data returned"
            )
        )
        XCTAssertEqual(try roundTrip(plan), plan)
    }

    func testPlanWithRetentionFieldsRoundTrip() throws {
        let plan = BackupPlan(
            name: "Documents",
            sourcePaths: ["/Users/me/Documents"],
            destination: .local(path: "/Volumes/Backup/repo"),
            schedule: .hourly,
            retention: .year,
            createdAt: date,
            lastPrune: PruneRunRecord(
                date: date,
                success: false,
                duration: 42.0,
                errorMessage: "unable to create lock in backend",
                blockedByLock: true
            )
        )
        XCTAssertEqual(try roundTrip(plan), plan)
        XCTAssertEqual(try roundTrip(plan).lastPrune?.blockedByLock, true)
    }

    /// A plan saved before `blockedByLock` existed must decode with it nil —
    /// not false — so the row can tell "no lock problem" from "never checked".
    func testPruneRecordWithoutLockFlagDecodesAsUnknown() throws {
        let record = PruneRunRecord(
            date: date,
            success: false,
            errorMessage: "something else went wrong"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoder.encode(record)) as? [String: Any]
        )
        XCTAssertNil(object["blockedByLock"], "nil must not be encoded at all")
        object.removeValue(forKey: "blockedByLock")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            PruneRunRecord.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertNil(decoded.blockedByLock)
        XCTAssertEqual(decoded, record)
    }

    func testLegacyPlanJSONDecodesWithFeatureDefaults() throws {
        // A plan saved by 0.2.0, before scheduled checks and retention
        // existed: same shape as today's encoder output minus those keys.
        let plan = BackupPlan(
            name: "Documents",
            sourcePaths: ["/Users/me/Documents"],
            destination: .local(path: "/Volumes/Backup/repo"),
            schedule: .daily(hour: 21, minute: 30),
            retention: .month,
            createdAt: date,
            lastCheck: CheckRunRecord(date: date, success: true),
            lastPrune: PruneRunRecord(date: date, success: true)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoder.encode(plan)) as? [String: Any]
        )
        object.removeValue(forKey: "checkCadence")
        object.removeValue(forKey: "lastCheck")
        object.removeValue(forKey: "retention")
        object.removeValue(forKey: "lastPrune")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupPlan.self, from: legacyData)
        XCTAssertEqual(decoded.checkCadence, .weekly)
        XCTAssertNil(decoded.lastCheck)
        XCTAssertEqual(decoded.retention, .off)
        XCTAssertNil(decoded.lastPrune)
        XCTAssertEqual(decoded.name, plan.name)
        XCTAssertEqual(decoded.schedule, plan.schedule)
    }
}
