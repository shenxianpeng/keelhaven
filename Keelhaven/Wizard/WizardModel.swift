import Foundation
import Observation
import KeelhavenCore

enum DestinationType: String, CaseIterable, Identifiable {
    case local
    case s3
    case sftp
    case rest

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .local: return String(localized: "Local / External Drive")
        case .s3: return String(localized: "S3-Compatible")
        case .sftp: return String(localized: "SFTP / NAS")
        case .rest: return String(localized: "REST Server")
        }
    }
}

enum ScheduleKind: String, CaseIterable, Identifiable {
    case hourly
    case daily
    case weekly

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .hourly: return String(localized: "Every hour")
        case .daily: return String(localized: "Once a day")
        case .weekly: return String(localized: "Once a week")
        }
    }
}

/// Draft state for the 3-step wizard, with per-step validation.
@MainActor
@Observable
final class WizardModel {
    static let stepCount = 3

    var step = 0
    var name = ""
    var sourcePaths: [String] = []

    /// Verification, retention, excludes and the throughput knobs — the four
    /// settings the wizard used to skip entirely (issue #41), now behind the
    /// schedule step's collapsed Customize section. Starts at the same
    /// defaults `BackupPlan.init` applies, so a wizard run that never opens
    /// that section builds the plan it always built.
    var options = PlanOptionsDraft()

    var destinationType: DestinationType = .local
    var localPath = ""
    var s3Endpoint = ""
    var s3Bucket = ""
    var s3Prefix = ""
    var s3AccessKey = ""
    var s3SecretKey = ""
    var sftpUser = ""
    var sftpHost = ""
    var sftpPort = "22"
    var sftpPath = ""
    var restURL = ""
    var restUsername = ""
    var restPassword = ""
    var password = ""
    var passwordConfirm = ""
    var passwordWasGenerated = false
    /// Connect to a repository that already exists at the destination:
    /// the password is verified against it instead of running `restic init`.
    var adoptExistingRepository = false {
        didSet {
            guard adoptExistingRepository != oldValue else { return }
            if adoptExistingRepository {
                // The auto-generated password (created on entering step 2,
                // before this toggle existed to veto it) can't be the existing
                // repository's — clear it so the field starts empty. A password
                // the user actually typed is left alone.
                if passwordWasGenerated {
                    password = ""
                    passwordConfirm = ""
                    passwordWasGenerated = false
                }
                passwordVerificationError = nil
            } else {
                // Back to the new-repository flow: regenerate (guards inside
                // ensure it never overwrites anything the user typed).
                autoGeneratePasswordIfNeeded()
            }
        }
    }

    /// While adopting, the password is checked the moment the user leaves
    /// step 2 (issue #30) — not at final Create — so the error appears next
    /// to the field that caused it.
    var isVerifyingPassword = false
    var passwordVerificationError: String?

    /// Proves the entered password opens the existing repository.
    /// Returns true on success; on failure stores the error for inline display.
    func verifyExistingRepositoryPassword(binaryURL: URL) async -> Bool {
        isVerifyingPassword = true
        passwordVerificationError = nil
        defer { isVerifyingPassword = false }

        let draft = buildDraft()
        let credentials = RepoCredentials(
            repositoryPassword: draft.password,
            s3SecretAccessKey: draft.s3SecretKey,
            restPassword: draft.restPassword
        )
        do {
            let runner = ResticRunner(binaryURL: binaryURL)
            _ = try await runner.run(
                .catConfig,
                destination: draft.destination,
                credentials: credentials,
                decoding: ResticRepoConfig.self
            )
            return true
        } catch {
            let message = (error as? ResticError)?.localizedDescription ?? error.localizedDescription
            passwordVerificationError = message
            return false
        }
    }

    /// "Start the first backup now", on by default — the behaviour every
    /// plan had before the checkbox existed (issue #42).
    var firstBackupStartsOnCreation = true

    var scheduleKind: ScheduleKind = .daily
    var dailyTime = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()
    /// Calendar weekday (1 = Sunday); defaults to the region's first weekday.
    var weekday = Calendar.current.firstWeekday

    var isCreating = false
    var creationError: String?

    /// Repository locations of already-configured plans, injected by the
    /// wizard window. Two plans must never share one repository: the second
    /// init would fail, and the passwords could diverge (issues #4/#5).
    var existingRepositoryLocations: [String] = []

    // MARK: - Validation

    var sourcesStepValid: Bool {
        !sourcePaths.isEmpty
    }

    var destinationStepValid: Bool {
        destinationFieldsValid && passwordValid
    }

    var passwordValid: Bool {
        if adoptExistingRepository {
            // The existing repository's password; verified at create time,
            // so no length or confirmation rules apply.
            return !password.isEmpty
        }
        return password.count >= 8 && password == passwordConfirm
    }

    /// Live check: the chosen local folder already holds a restic repository
    /// (e.g. left over from a deleted plan). Caught here on step 2 rather
    /// than at Create time (issue #18). Remote destinations can't be probed
    /// without network access, so those still surface at Create.
    var localDestinationHasRepository: Bool {
        destinationType == .local && RepositoryProbe.localPathContainsRepository(localPath)
    }

    /// The current destination type's required fields are all filled in.
    /// Split from the conflict checks so `blockingHint` can tell "not filled
    /// in yet" (gray guidance) apart from "conflicts" (red errors).
    var destinationFieldsComplete: Bool {
        switch destinationType {
        case .local:
            return !localPath.isEmpty
        case .s3:
            return !s3Endpoint.isEmpty && !s3Bucket.isEmpty && !s3AccessKey.isEmpty && !s3SecretKey.isEmpty
        case .sftp:
            return !sftpUser.isEmpty && !sftpHost.isEmpty && !sftpPath.isEmpty && Int(sftpPort) != nil
        case .rest:
            return !restURL.isEmpty
        }
    }

    /// The endpoint being typed is Backblaze B2, which needs a bucket-side
    /// lifecycle rule or deleted data keeps being billed forever (issue #47).
    /// Guidance, not a conflict: the destination is perfectly valid, so this
    /// deliberately has no effect on `destinationHasConflict` or on Next.
    var destinationIsBackblazeB2: Bool {
        guard destinationType == .s3 else { return false }
        return S3Config(
            endpoint: s3Endpoint,
            bucket: s3Bucket,
            pathPrefix: s3Prefix,
            accessKeyID: s3AccessKey
        ).isBackblazeB2
    }

    /// A REST URL pasted with restic-docs-style embedded credentials
    /// ("https://user:pass@host/"). Refused because the URL is persisted to
    /// plans.json in plain text — the separate fields keep the password in
    /// the Keychain (see RESTConfig.urlEmbedsCredentials).
    var restURLEmbedsCredentials: Bool {
        destinationType == .rest && RESTConfig(url: restURL).urlEmbedsCredentials
    }

    /// The destination conflicts with existing state (all shown as red
    /// inline errors in the destination step).
    var destinationHasConflict: Bool {
        if localDestinationInsideSource { return true }
        if restURLEmbedsCredentials { return true }
        if adoptExistingRepository { return false }
        if destinationAlreadyUsed { return true }
        return localDestinationHasRepository
    }

    var destinationFieldsValid: Bool {
        destinationFieldsComplete && !destinationHasConflict
    }

    /// True when the draft destination matches an existing plan's repository.
    var destinationAlreadyUsed: Bool {
        existingRepositoryLocations.contains(currentDestination.repositoryLocation)
    }

    private var currentDestination: Destination {
        switch destinationType {
        case .local:
            return .local(path: localPath)
        case .s3:
            return .s3(S3Config(
                endpoint: s3Endpoint,
                bucket: s3Bucket,
                pathPrefix: s3Prefix,
                accessKeyID: s3AccessKey
            ))
        case .sftp:
            return .sftp(SFTPConfig(
                user: sftpUser,
                host: sftpHost,
                port: Int(sftpPort) ?? 22,
                path: sftpPath
            ))
        case .rest:
            return .rest(RESTConfig(url: restURL, username: restUsername))
        }
    }

    /// Backing up a folder into itself would recursively back up the repository.
    var localDestinationInsideSource: Bool {
        guard destinationType == .local, !localPath.isEmpty else { return false }
        let destination = localPath.hasSuffix("/") ? localPath : localPath + "/"
        return sourcePaths.contains { source in
            let prefix = source.hasSuffix("/") ? source : source + "/"
            return destination.hasPrefix(prefix)
        }
    }

    var canAdvance: Bool {
        switch step {
        case 0: return sourcesStepValid
        case 1: return destinationStepValid
        default: return true
        }
    }

    /// Why Next is disabled, as one gray guidance sentence — the first
    /// missing requirement in top-to-bottom order (issue #38). Nil whenever
    /// the step can advance.
    var blockingHint: String? {
        guard !canAdvance else { return nil }
        switch step {
        case 0:
            return String(localized: "Add at least one folder to continue.")
        case 1:
            if !destinationFieldsComplete {
                switch destinationType {
                case .local:
                    return String(localized: "Choose a destination folder to continue.")
                case .s3:
                    return String(localized: "Fill in the remaining S3 fields.")
                case .sftp:
                    return String(localized: "Fill in the remaining SFTP fields.")
                case .rest:
                    return String(localized: "Enter the REST server URL.")
                }
            }
            if destinationHasConflict {
                return String(localized: "Fix the destination issue shown above.")
            }
            if adoptExistingRepository {
                return String(localized: "Enter the repository password.")
            }
            if password.isEmpty {
                return String(localized: "A password is required to encrypt the backup.")
            }
            if password.count < 8 {
                return String(localized: "Password must be at least 8 characters.")
            }
            return String(localized: "Passwords don't match.")
        default:
            return nil
        }
    }

    /// Simple-mode default: entering the destination step with untouched
    /// password fields auto-generates a strong password so nobody has to
    /// invent one. Never fires when connecting to an existing repository or
    /// after the user typed anything.
    func autoGeneratePasswordIfNeeded() {
        guard !adoptExistingRepository,
              password.isEmpty,
              passwordConfirm.isEmpty,
              !passwordWasGenerated
        else { return }
        generatePassword()
    }

    /// Fills both password fields with a generated passphrase. Ambiguous
    /// characters (0/O, 1/l/I) are excluded since users may need to type it
    /// during a future restore.
    func generatePassword() {
        let charset = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        password = String((0..<20).compactMap { _ in charset.randomElement() })
        passwordConfirm = password
        passwordWasGenerated = true
    }

    // MARK: - Draft assembly

    var defaultName: String {
        if let first = sourcePaths.first {
            return URL(fileURLWithPath: first).lastPathComponent
        }
        return String(localized: "My Backup")
    }

    /// The name this model last wrote into `name` itself. Lets
    /// `syncAutofilledName` distinguish its own writes from user input.
    private var lastAutofilledName: String?

    /// Keeps the name field showing the first folder's name as real,
    /// editable text instead of a grayed-out placeholder — so users can see
    /// the field is theirs to change. Never overwrites a name the user typed.
    func syncAutofilledName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty || trimmed == lastAutofilledName else { return }
        if let first = sourcePaths.first {
            name = URL(fileURLWithPath: first).lastPathComponent
            lastAutofilledName = name
        } else {
            name = ""
            lastAutofilledName = nil
        }
    }

    func buildDraft() -> PlanDraft {
        let destination = currentDestination

        let schedule = Schedule(kind: scheduleKind, dailyTime: dailyTime, weekday: weekday)

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        return PlanDraft(
            name: trimmedName.isEmpty ? defaultName : trimmedName,
            sourcePaths: sourcePaths,
            destination: destination,
            schedule: schedule,
            excludePatterns: options.excludePatterns,
            checkCadence: options.checkCadence,
            retention: options.builtRetention(),
            performance: options.builtPerformance(),
            backupOptions: options.builtBackupOptions(),
            firstBackupStartsOnCreation: firstBackupStartsOnCreation,
            password: password,
            s3SecretKey: destinationType == .s3 ? s3SecretKey : nil,
            restPassword: destinationType == .rest ? restPassword : nil,
            adoptExistingRepository: adoptExistingRepository
        )
    }

    func reset() {
        let fresh = WizardModel()
        step = fresh.step
        name = fresh.name
        sourcePaths = fresh.sourcePaths
        options = fresh.options
        destinationType = fresh.destinationType
        localPath = fresh.localPath
        s3Endpoint = fresh.s3Endpoint
        s3Bucket = fresh.s3Bucket
        s3Prefix = fresh.s3Prefix
        s3AccessKey = fresh.s3AccessKey
        s3SecretKey = fresh.s3SecretKey
        sftpUser = fresh.sftpUser
        sftpHost = fresh.sftpHost
        sftpPort = fresh.sftpPort
        sftpPath = fresh.sftpPath
        restURL = fresh.restURL
        restUsername = fresh.restUsername
        restPassword = fresh.restPassword
        password = fresh.password
        passwordConfirm = fresh.passwordConfirm
        passwordWasGenerated = fresh.passwordWasGenerated
        adoptExistingRepository = fresh.adoptExistingRepository
        isVerifyingPassword = fresh.isVerifyingPassword
        passwordVerificationError = fresh.passwordVerificationError
        firstBackupStartsOnCreation = fresh.firstBackupStartsOnCreation
        scheduleKind = fresh.scheduleKind
        dailyTime = fresh.dailyTime
        weekday = fresh.weekday
        isCreating = fresh.isCreating
        creationError = fresh.creationError
        lastAutofilledName = fresh.lastAutofilledName
    }
}
