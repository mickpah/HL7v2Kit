// Profile+au_adrm_2021.swift
// Hand-curated AU ADRM-2021 profile content. Mirrors the JSON overlays
// under `Resources/profiles/au-adrm-2021/` — they are the editable spec
// source; this Swift file is what `ProfileLoader` returns at runtime.
// Codegen support for profile overlays is deferred to a future stage
// (when more profiles need this pattern); until then, keep the two
// representations in sync by hand. See ADR-007.
//
// v0.5-S5-B-1 ships the EI-all-components rules for OBR-2/3 + ORC-2/3/4
// per HL7au:000003 / 000004.1 / 000005 / 000006 / 000007 in Appendix 5
// of HL7AUSD-STD-OO-ADRM-2021.1. Each FieldOverride carries the spec
// citation in the source comment.

import Foundation

extension Profile {
    /// HL7 Australia ADRM-2021 profile, layered over base HL7 v2.4.
    /// Returned by `ProfileLoader.load(for: .auLocalisation)`.
    ///
    /// v0.5-S5-B-1 scope: EI-all-components rules for OBR-2 / OBR-3 /
    /// ORC-2 / ORC-3 / ORC-4. Each enforces that when the field is
    /// populated, all four Entity Identifier components (Entity ID,
    /// Namespace ID, Universal ID, Universal ID Type) are populated.
    static let auADRM2021 = Profile(
        locale: .auLocalisation,
        baseVersion: .v2_4,
        fieldOverrides: [
            FieldOverride(
                segmentID: "OBR",
                fieldIndex: 2,
                profileUsage: nil,
                valueSet: nil,
                requiredComponents: [1, 2, 3, 4],
                specCitation: "HL7au:000003 (r2) — OBR-2 EI completeness"
            ),
            FieldOverride(
                segmentID: "OBR",
                fieldIndex: 3,
                profileUsage: nil,
                valueSet: nil,
                requiredComponents: [1, 2, 3, 4],
                specCitation: "HL7au:000004.1 (r3) — OBR-3 EI completeness"
            ),
            FieldOverride(
                segmentID: "ORC",
                fieldIndex: 2,
                profileUsage: nil,
                valueSet: nil,
                requiredComponents: [1, 2, 3, 4],
                specCitation: "HL7au:000005 (r2) — ORC-2 EI completeness"
            ),
            FieldOverride(
                segmentID: "ORC",
                fieldIndex: 3,
                profileUsage: nil,
                valueSet: nil,
                requiredComponents: [1, 2, 3, 4],
                specCitation: "HL7au:000006 (r3) — ORC-3 EI completeness"
            ),
            FieldOverride(
                segmentID: "ORC",
                fieldIndex: 4,
                profileUsage: nil,
                valueSet: nil,
                requiredComponents: [1, 2, 3, 4],
                specCitation: "HL7au:000007 (r2) — ORC-4 EI completeness"
            ),
        ]
    )
}
