import Foundation

/// Optional throughput knobs handed to restic on argv. Every field is
/// `nil` by default, which means "let restic decide" — the flag is left off
/// the command line entirely rather than passed with restic's own default,
/// so a plan that never opens the Advanced section produces exactly the same
/// arguments it did before this type existed.
///
/// These are the three knobs people actually ask for: capping upload so a
/// backup can't eat a home connection's uplink, lowering read concurrency on
/// a spinning disk (or raising it on an NVMe), and growing the pack size on a
/// high-latency object store where request count is what costs money.
/// Deliberately not a free-form "extra restic arguments" field: `--quiet`
/// would break the `--json` event stream every progress bar is parsed from,
/// `--no-lock` would defeat the concurrency guard, and `--insecure-tls` would
/// silently drop certificate checking.
public struct PerformanceOptions: Codable, Hashable, Sendable {
    /// Upload cap in KiB/s (`--limit-upload`). `nil` is unlimited.
    public var uploadLimitKiBPerSecond: Int?
    /// Files read in parallel during a backup (`--read-concurrency`).
    /// `nil` leaves restic's default of 2.
    public var readConcurrency: Int?
    /// Target pack size in MiB (`--pack-size`). `nil` leaves restic's
    /// default of 16.
    public var packSizeMiB: Int?

    /// restic rejects anything outside these, so clamping here keeps a
    /// hand-edited plans.json from producing a command that always fails.
    public static let readConcurrencyRange = 1...32
    public static let packSizeRangeMiB = 4...128

    /// Every knob at restic's own default.
    public static let off = PerformanceOptions()

    /// Values are clamped rather than rejected: this is the only validation
    /// the app has. The Edit Plan window lives in the UI target, which has no
    /// tests, so the guarantee has to sit in Core where coverage protects it.
    public init(
        uploadLimitKiBPerSecond: Int? = nil,
        readConcurrency: Int? = nil,
        packSizeMiB: Int? = nil
    ) {
        // Zero or negative means "no limit" — the same thing as leaving it
        // unset, so it collapses to nil instead of an argument restic refuses.
        self.uploadLimitKiBPerSecond = uploadLimitKiBPerSecond.flatMap { $0 > 0 ? $0 : nil }
        self.readConcurrency = readConcurrency.map {
            min(max($0, Self.readConcurrencyRange.lowerBound), Self.readConcurrencyRange.upperBound)
        }
        self.packSizeMiB = packSizeMiB.map {
            min(max($0, Self.packSizeRangeMiB.lowerBound), Self.packSizeRangeMiB.upperBound)
        }
    }

    /// Routed through `init` so decoding clamps exactly like construction
    /// does — a stored value out of range can't survive a round trip.
    /// (`encode(to:)` and `CodingKeys` stay synthesized; the synthesized
    /// encoder omits nil fields.)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            uploadLimitKiBPerSecond: try container.decodeIfPresent(Int.self, forKey: .uploadLimitKiBPerSecond),
            readConcurrency: try container.decodeIfPresent(Int.self, forKey: .readConcurrency),
            packSizeMiB: try container.decodeIfPresent(Int.self, forKey: .packSizeMiB)
        )
    }

    /// True when restic is left entirely to its own defaults.
    public var isDefault: Bool {
        uploadLimitKiBPerSecond == nil && readConcurrency == nil && packSizeMiB == nil
    }

    /// The flags for this configuration, empty when nothing is set.
    ///
    /// `--limit-upload` and `--pack-size` are restic global flags and are
    /// accepted by any subcommand; `--read-concurrency` belongs to `backup`
    /// alone and makes restic exit with a usage error anywhere else, hence
    /// the switch rather than one all-purpose argument list.
    public func arguments(includingReadConcurrency: Bool) -> [String] {
        var args: [String] = []
        if let uploadLimitKiBPerSecond {
            args.append("--limit-upload")
            args.append(String(uploadLimitKiBPerSecond))
        }
        if includingReadConcurrency, let readConcurrency {
            args.append("--read-concurrency")
            args.append(String(readConcurrency))
        }
        if let packSizeMiB {
            args.append("--pack-size")
            args.append(String(packSizeMiB))
        }
        return args
    }
}
