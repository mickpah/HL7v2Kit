// HL7TableRegistry.swift
// Entry point for per-version HL7 code-table lookup. The per-version
// dictionaries live in `Generated/HL7TableRegistry+v<X_Y_Z>.swift`,
// emitted by `HL7v2KitCodegen` from `Resources/tables/<version>/`. To
// add or correct a table, edit (or re-extract) the JSON and run
// `bash scripts/regenerate-typed-segments.sh`.

/// Per-version lookup of HL7 code tables. M6-O6.
public enum HL7TableRegistry {
    /// The table `number` (e.g. `"0074"`) as printed by `version`, or
    /// `nil` when that version does not define it. `.v2_8` owns no tables;
    /// the ``Validator`` checks a `2.8` message against the v2.8.2 tables
    /// via ``Version/grammarVersion`` (ADR-018).
    public static func table(_ number: String, version: Version) -> HL7Table? {
        tables(for: version)[number]
    }

    /// A locale's own printed rendering of table `number`, or `nil` when the
    /// locale does not reprint it. A localisation may widen or narrow a base
    /// table: AU ADRM-2021 back-ports `UNICODE UTF-8` into its v2.4 Table
    /// 0211 (p. 55 footnote). `.international` adds nothing to the base spec.
    public static func table(_ number: String, locale: HL7Locale) -> HL7Table? {
        switch locale {
        case .international:  return nil
        case .auLocalisation: return au_adrm_2021[number]
        }
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
