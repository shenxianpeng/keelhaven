import Foundation
import KeelhavenCore

/// Everything the wizard collects to create a plan.
///
/// The four settings after `schedule` default to exactly what `BackupPlan`'s
/// own initializer would have applied, so the wizard's Options step (issue
/// #39) changes what a plan *can* be created with, never what an untouched
/// wizard run produces.
struct PlanDraft {
    var name: String
    var sourcePaths: [String]
    var destination: Destination
    var schedule: Schedule
    var excludePatterns: [String] = BackupPlan.defaultExcludePatterns
    var checkCadence: CheckCadence = .weekly
    var retention: RetentionPolicy = .off
    var performance: PerformanceOptions = .off
    var backupOptions: BackupOptions = .off
    /// The wizard's "Start the first backup now" checkbox (issue #42).
    var firstBackupStartsOnCreation: Bool = true
    var password: String
    var s3SecretKey: String?
    var restPassword: String?
    /// True when the destination already holds a repository the user wants to
    /// connect to: the password is verified against it instead of `restic init`.
    var adoptExistingRepository = false
}

/// Creates and deletes plans. For a new repository, secrets go into the
/// Keychain first and `restic init` proves the destination works (secrets are
/// rolled back on failure). When adopting an existing repository, the password
/// is verified against it first — multiple plans may share one repository as
/// long as every adoption proves it holds the same password.
struct PlanManager {
    let keychain: KeychainStoring
    let resticBinaryURL: URL?

    func createPlan(_ draft: PlanDraft) async throws -> BackupPlan {
        guard let binaryURL = resticBinaryURL else {
            throw ResticError.binaryNotFound
        }

        // A local destination that already holds a repository would make
        // `restic init` fail with a cryptic error — catch it up front.
        if !draft.adoptExistingRepository,
           case .local(let path) = draft.destination,
           RepositoryProbe.localPathContainsRepository(path) {
            throw ResticError.repositoryAlreadyExists(message: "config file already exists at \(path)")
        }

        let plan = BackupPlan(
            name: draft.name,
            sourcePaths: draft.sourcePaths,
            destination: draft.destination,
            schedule: draft.schedule,
            excludePatterns: draft.excludePatterns,
            checkCadence: draft.checkCadence,
            retention: draft.retention,
            performance: draft.performance,
            backupOptions: draft.backupOptions,
            firstBackupStartsOnCreation: draft.firstBackupStartsOnCreation
        )

        let credentials = RepoCredentials(
            repositoryPassword: draft.password,
            s3SecretAccessKey: draft.s3SecretKey,
            restPassword: draft.restPassword
        )
        let runner = ResticRunner(binaryURL: binaryURL)

        if draft.adoptExistingRepository {
            // Prove the password opens the existing repository before
            // anything is stored; wrongPassword/repositoryDoesNotExist
            // surface directly in the wizard.
            _ = try await runner.run(
                .catConfig,
                destination: draft.destination,
                credentials: credentials,
                decoding: ResticRepoConfig.self
            )
        }

        try keychain.setSecret(
            draft.password,
            account: KeychainAccount.repositoryPassword(planID: plan.id)
        )
        if let s3SecretKey = draft.s3SecretKey, !s3SecretKey.isEmpty {
            try keychain.setSecret(
                s3SecretKey,
                account: KeychainAccount.s3SecretKey(planID: plan.id)
            )
        }
        if let restPassword = draft.restPassword, !restPassword.isEmpty {
            try keychain.setSecret(
                restPassword,
                account: KeychainAccount.restPassword(planID: plan.id)
            )
        }

        if !draft.adoptExistingRepository {
            do {
                _ = try await runner.run(
                    .initRepository,
                    destination: draft.destination,
                    credentials: credentials,
                    decoding: ResticInitResult.self
                )
            } catch {
                removeSecrets(planID: plan.id)
                throw error
            }
        }

        return plan
    }

    func removeSecrets(planID: UUID) {
        try? keychain.deleteSecret(account: KeychainAccount.repositoryPassword(planID: planID))
        try? keychain.deleteSecret(account: KeychainAccount.s3SecretKey(planID: planID))
        try? keychain.deleteSecret(account: KeychainAccount.restPassword(planID: planID))
    }
}
