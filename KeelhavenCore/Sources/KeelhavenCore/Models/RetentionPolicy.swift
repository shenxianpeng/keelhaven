import Foundation

/// How much snapshot history a plan keeps. `off` means Keelhaven never
/// deletes a snapshot and is the default: deletion is strictly opt-in.
///
/// Three of the four choices are presets rather than free-form keep counts,
/// so retention stays something a person can read instead of five numeric
/// fields. They map to restic's `forget --keep-*` flags, and both keep the
/// three most recent snapshots unconditionally so a burst of runs can never
/// thin away everything recent.
///
/// `lastN` is the one count anyone asked for (issue #52): keep the last N
/// backups and nothing else, which is a shape no time-based preset can
/// express. It is deliberately the only parameterised case — the doc comment
/// above is a rule, not a description, and a second number field would break
/// it.
///
/// No longer `String`-backed or `CaseIterable`: neither survives an
/// associated value, and nothing used them (the picker tags each case by
/// hand). `Codable` is written out below instead, and still reads every value
/// written before this case existed.
public enum RetentionPolicy: Codable, Hashable, Sendable {
    /// Keep every snapshot.
    case off
    /// About a year of history: 7 daily, 5 weekly, 12 monthly keepers.
    case year
    /// About a month of history: 7 daily, 4 weekly keepers.
    case month
    /// Keep the last `count` backups and nothing else.
    ///
    /// The payload is not trusted anywhere it matters: `keepArguments`
    /// clamps it, so a hand-edited `plans.json` cannot produce a `forget`
    /// restic refuses — or worse, one that keeps nothing.
    case lastN(Int)

    /// What `lastN` accepts. One is the floor because zero would mean
    /// "delete every snapshot", which no retention setting should be able to
    /// say; the ceiling only keeps the argument sane.
    public static let keepLastRange = 1...999

    /// The `restic forget` keep flags for this policy. Empty for `.off`,
    /// which callers must treat as "never run forget" — restic rejects a
    /// forget with no policy rather than deleting anything.
    public var keepArguments: [String] {
        switch self {
        case .off:
            return []
        case .year:
            return [
                "--keep-last", "3",
                "--keep-daily", "7",
                "--keep-weekly", "5",
                "--keep-monthly", "12",
            ]
        case .month:
            return [
                "--keep-last", "3",
                "--keep-daily", "7",
                "--keep-weekly", "4",
            ]
        case .lastN(let count):
            return ["--keep-last", String(Self.clamped(count))]
        }
    }

    /// The count this policy keeps, already clamped — nil for the presets,
    /// which have no single number to show.
    public var keepLastCount: Int? {
        guard case .lastN(let count) = self else { return nil }
        return Self.clamped(count)
    }

    private static func clamped(_ count: Int) -> Int {
        min(max(count, keepLastRange.lowerBound), keepLastRange.upperBound)
    }

    // MARK: - Codable

    /// Encoded as a single string, so `plans.json` stays readable and the
    /// field keeps the shape it has always had: `off`, `year`, `month`, or
    /// `last:10`.
    private var encodedValue: String {
        switch self {
        case .off: return "off"
        case .year: return "year"
        case .month: return "month"
        case .lastN(let count): return "last:\(Self.clamped(count))"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "off":
            self = .off
        case "year":
            self = .year
        case "month":
            self = .month
        default:
            guard raw.hasPrefix("last:"), let count = Int(raw.dropFirst(5)) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath,
                          debugDescription: "Unrecognised retention policy: \(raw)")
                )
            }
            self = .lastN(Self.clamped(count))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encodedValue)
    }
}
