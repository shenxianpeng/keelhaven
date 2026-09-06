import XCTest
@testable import KeelhavenCore

/// End-to-end tests against a real restic REST server (rest-server) with the
/// real restic binary — the same path a self-hosted rest-server user takes.
/// v1 targets rest-server's default mode only: no `--private-repos`, no
/// `--append-only`, no self-signed TLS (see docs/ARCHITECTURE.md). CI starts
/// a `--no-auth` rest-server for these (see .github/workflows/ci.yml).
///
/// Locally:
///
///   brew install go && go install github.com/restic/rest-server/cmd/rest-server@latest
///   rest-server --listen 127.0.0.1:8000 --path /tmp/rest-server-data --no-auth
///
/// Overrides (for pointing at another server): KEELHAVEN_TEST_REST_URL.
final class ResticRESTIntegrationTests: XCTestCase {
    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeelhavenRESTIntegration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
    }

    func testFullBackupCycleAndWrongPassword() async throws {
        guard let binary = IntegrationTestSupport.locateRestic() else {
            throw XCTSkip("restic is not installed; run: brew install restic")
        }
        let url = IntegrationTestSupport.environmentValue(
            "KEELHAVEN_TEST_REST_URL", default: "http://127.0.0.1:8000/")
        guard await IntegrationTestSupport.httpEndpointIsReachable(url) else {
            throw XCTSkip("no REST server at \(url); start rest-server (see this file's header)")
        }

        let config = RESTConfig(url: url)
        let destination = Destination.rest(config)
        let credentials = RepoCredentials(repositoryPassword: "rest-integration-password")

        try await IntegrationTestSupport.runFullBackupCycle(
            binary: binary,
            destination: destination,
            credentials: credentials,
            workDirectory: workDirectory
        )

        // Wrong repository password must classify the same over REST as
        // locally (the exit code has to survive the HTTP backend).
        let runner = ResticRunner(binaryURL: binary)
        do {
            _ = try await runner.run(
                .snapshots,
                destination: destination,
                credentials: RepoCredentials(repositoryPassword: "wrong"),
                decoding: [ResticSnapshot].self
            )
            XCTFail("Expected wrongPassword error")
        } catch let error as ResticError {
            guard case .wrongPassword = error else {
                return XCTFail("Expected wrongPassword, got \(error)")
            }
        }
    }
}
