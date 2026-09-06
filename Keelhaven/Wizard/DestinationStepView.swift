import SwiftUI

struct DestinationStepView: View {
    @Bindable var model: WizardModel
    @State private var drives: [ExternalDrive] = []
    @State private var advancedExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Where should the encrypted backup go?")
                    .font(.title3)

                if model.destinationType == .local {
                    driveList
                    localFolderRow
                }

                advancedOptions

                if !model.adoptExistingRepository {
                    if model.localDestinationHasRepository && !model.destinationAlreadyUsed {
                        HintCallout(.error, "This folder already contains a backup repository. Connect to it under Advanced options, or choose an empty folder.")
                    }
                    if model.destinationAlreadyUsed {
                        HintCallout(.error, "Another plan already backs up to this destination. Connect to its repository under Advanced options, or pick a different folder or bucket path.")
                    }
                }

                // The password block only appears once there is a valid
                // destination: one decision at a time, and a conflict callout
                // above keeps the page focused on fixing it (issue #50).
                if model.destinationFieldsValid {
                    Divider()

                    passwordSection
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.bottom, 4)
            .animation(.default, value: model.destinationFieldsValid)
        }
        .onAppear {
            drives = ExternalDriveService.detect()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            drives = ExternalDriveService.detect()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            drives = ExternalDriveService.detect()
        }
    }

    // MARK: - Simple face: external drives

    @ViewBuilder
    private var driveList: some View {
        if drives.isEmpty {
            Label("Plug in a USB backup drive and it will appear here.", systemImage: "externaldrive.badge.questionmark")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 6) {
                ForEach(drives) { drive in
                    driveRow(drive)
                }
            }
        }
    }

    private func driveRow(_ drive: ExternalDrive) -> some View {
        let selected = model.localPath == ExternalDriveService.proposedBackupPath(on: drive)
        return Button {
            model.destinationType = .local
            model.localPath = ExternalDriveService.proposedBackupPath(on: drive)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive")
                    .font(.title2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(drive.name)
                        .font(.title3)
                    if !drive.isWritable {
                        Text("Read-only — can't back up here")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if let free = drive.freeBytes {
                        Text("\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!drive.isWritable)
        .accessibilityLabel(
            selected
                ? String(localized: "\(drive.name), selected as backup drive")
                : String(localized: "Back up to \(drive.name)")
        )
    }

    private var localFolderRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(drives.isEmpty ? "Or choose any folder:" : "Or choose a folder instead:")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                TextField("Destination folder", text: $model.localPath, prompt: Text("/Volumes/BackupDrive/Keelhaven"))
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") {
                    if let url = FolderPicker.pickFolder() {
                        model.localPath = url.path
                    }
                }
            }
            if model.localDestinationInsideSource {
                HintCallout(.error, "The destination can't be inside a folder you're backing up.")
            } else if model.destinationType == .local, model.localPath.isEmpty {
                // Gray guidance, not red: nothing is wrong yet (issue #38).
                Text("No destination chosen yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Advanced options

    // Hand-rolled disclosure instead of DisclosureGroup: the whole two-line
    // row is one large click target, not just the tiny chevron (issue #50).
    private var advancedOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                advancedExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(advancedExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Advanced options")
                        Text("S3, SFTP, REST server, or an existing repository")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(advancedExpanded ? [.isSelected] : [])

            if advancedExpanded {
                advancedContent
            }
        }
        .animation(.default, value: advancedExpanded)
        .onChange(of: advancedExpanded) { _, expanded in
            // Collapsing must not leave a hidden half-filled S3/SFTP form active.
            if !expanded && model.destinationType != .local {
                model.destinationType = .local
            }
        }
    }

    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Destination type", selection: $model.destinationType) {
                ForEach(DestinationType.allCases) { type in
                    Text(type.localizedTitle).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            remoteForms

            Toggle("Connect to an existing repository at this destination", isOn: $model.adoptExistingRepository)
                .toggleStyle(.checkbox)
            Text("For a repository created earlier — by another plan, a previous install, or another Mac. Your password is verified against it; no new repository is created.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var remoteForms: some View {
        switch model.destinationType {
        case .local:
            EmptyView()
        case .s3:
            Form {
                TextField("Endpoint", text: $model.s3Endpoint, prompt: Text("s3.amazonaws.com"))
                TextField("Bucket", text: $model.s3Bucket)
                TextField("Path prefix (optional)", text: $model.s3Prefix)
                TextField("Access key ID", text: $model.s3AccessKey)
                SecureField("Secret access key", text: $model.s3SecretKey)
            }
            .formStyle(.columns)
            .textFieldStyle(.roundedBorder)
            if !model.destinationFieldsComplete {
                Text("All fields except the path prefix are required.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .sftp:
            Form {
                TextField("User", text: $model.sftpUser)
                TextField("Host", text: $model.sftpHost, prompt: Text("nas.local"))
                TextField("Port", text: $model.sftpPort)
                TextField("Path on server", text: $model.sftpPath, prompt: Text("/backups/mac"))
            }
            .formStyle(.columns)
            .textFieldStyle(.roundedBorder)
            Text("Uses your existing SSH keys (~/.ssh) or ssh-agent for authentication.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if !model.destinationFieldsComplete {
                Text("All fields are required.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .rest:
            Form {
                TextField("Server URL", text: $model.restURL, prompt: Text("http://127.0.0.1:8000/"))
                TextField("Username (optional)", text: $model.restUsername)
                SecureField("Password (optional)", text: $model.restPassword)
            }
            .formStyle(.columns)
            .textFieldStyle(.roundedBorder)
            Text("For a restic REST server (rest-server) using default settings — no TLS, no --private-repos, no --append-only. Leave username and password blank if the server has no authentication set up.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if !model.destinationFieldsComplete {
                Text("Server URL is required.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Password

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Encryption password")
                .font(.headline)
            if model.adoptExistingRepository {
                Text("Enter the password of the existing repository. It is checked when you click Next.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                SecureField("Existing repository password", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.password) { _, _ in
                        model.passwordVerificationError = nil
                    }
                if let verificationError = model.passwordVerificationError {
                    HintCallout(.error, verbatim: verificationError, lineLimit: 3)
                        .help(verificationError)
                }
            } else {
                newPasswordFields
            }
        }
    }

    @ViewBuilder
    private var newPasswordFields: some View {
        Text("Backups are encrypted before leaving your Mac. This password is stored in your Keychain — without it, backups cannot be restored.")
            .font(.callout)
            .foregroundStyle(.secondary)
        if model.passwordWasGenerated {
            HStack {
                Text(model.password)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(model.password, forType: .string)
                }
            }
            HintCallout(.warning, "Write this down or store it in a password manager now — without it, your backups cannot be restored.")
        } else {
            SecureField("Password (at least 8 characters)", text: $model.password)
                .textFieldStyle(.roundedBorder)
            SecureField("Confirm password", text: $model.passwordConfirm)
                .textFieldStyle(.roundedBorder)
        }
        Button(model.passwordWasGenerated ? "Type My Own Instead" : "Generate Strong Password") {
            if model.passwordWasGenerated {
                model.password = ""
                model.passwordConfirm = ""
                model.passwordWasGenerated = false
            } else {
                model.generatePassword()
            }
        }
        if !model.password.isEmpty && !model.passwordValid {
            HintCallout(.error, model.password.count < 8
                ? "Password must be at least 8 characters."
                : "Passwords don't match.")
        } else if model.password.isEmpty {
            Text("A password is required to encrypt the backup.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
