// HL7TableRegistry.swift
// Entry point for per-version HL7 code-table lookup. The per-version
// dictionaries live in `Generated/HL7TableRegistry+v<X_Y_Z>.swift`,
// emitted by `HL7v2KitCodegen` from `Resources/tables/<version>/`. To
// add or correct a table, edit (or re-extract) the JSON and run
// `bash scripts/regenerate-typed-segments.sh`.

/// Per-version lookup of HL7 code tables. M6-O6.
public enum HL7TableRegistry {
    /// The table `number` (e.g. `"0074"`) as printed by `version`, or
    /// `nil` when that version does not define it. The grammar-less
    /// `.v2_8` has no tables (ADR-013).
    public static func table(_ number: String, version: Version) -> HL7Table? {
        tables(for: version)[number]
    }

    /// Every table printed by `version`, keyed by table number. Empty
    /// for versions HL7v2Kit does not carry tables for.
    static func tables(for version: Version) -> [String: HL7Table] {
        switch version {
        case .v2_3:   return v2_3
        case .v2_3_1: return v2_3_1
        case .v2_4:   return v2_4
        case .v2_5_1: return v2_5_1
        case .v2_6:   return v2_6
        case .v2_8_2: return v2_8_2
        default:      return [:]
        }
    }
}
