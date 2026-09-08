import Foundation

/// Outcome of a single backup run, kept for history and menu bar display.
public struct BackupRunRecord: Codable, Hashable, Sendable {
    public var date: Date
    public var success: Bool
    public var snapshotID: String?
    public var filesNew: Int?
    public var filesChanged: Int?
    public var dataAddedBytes: Int64?
    public var duration: TimeInterval?
    public var errorMessage: String?
    /// True when the run succeeded but wrote no snapshot because the content
    /// was identical to the parent (`--skip-if-unchanged`). Optional so
    /// records written before the option existed decode as nil, and read as
    /// `== true` at every use site — the same shape as
    /// `PruneRunRecord.blockedByLock`.
    public var skippedUnchanged: Bool?

    public init(
        date: Date,
        success: Bool,
        snapshotID: String? = nil,
        filesNew: Int? = nil,
        filesChanged: Int? = nil,
        dataAddedBytes: Int64? = nil,
        duration: TimeInterval? = nil,
        errorMessage: String? = nil,
        skippedUnchanged: Bool? = nil
    ) {
        self.date = date
        self.success = success
        self.snapshotID = snapshotID
        self.filesNew = filesNew
        self.filesChanged = filesChanged
        self.dataAddedBytes = dataAddedBytes
        self.duration = duration
        self.errorMessage = errorMessage
        self.skippedUnchanged = skippedUnchanged
    }
}
