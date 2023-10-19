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
            // HL7au:000041 (r2) — MSH-17 country code must be "AUS"
            // for Australian originators. The spec says MSH-17 must
            // be specified (required under AU) AND its value must be
            // "AUS". The profileUsage = .required dispatch fires on
            // empty MSH-17; the componentValueSets fire on populated-
            // but-wrong values.
            FieldOverride(
                segmentID: "MSH",
                fieldIndex: 17,
                profileUsage: .required,
                componentValueSets: [
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["AUS"],
                        specCitation: "HL7au:000041 (r2) — MSH-17 country must be \"AUS\""
                    )
                ],
                specCitation: "HL7au:000041 (r2) — MSH-17 country required + narrowed to AUS"
            ),
            // HL7au:000042 — MSH-19 must equal "en^English^ISO639"
            // per AU English-only messaging conformance. Same
            // pattern: profileUsage = .required + per-component
            // value-set checks.
            FieldOverride(
                segmentID: "MSH",
                fieldIndex: 19,
                profileUsage: .required,
                componentValueSets: [
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["en"],
                        specCitation: "HL7au:000042 — MSH-19.1 (identifier) must be \"en\""
                    ),
                    ComponentValueSet(
                        component: 2,
                        allowedValues: ["English"],
                        specCitation: "HL7au:000042 — MSH-19.2 (text) must be \"English\""
                    ),
                    ComponentValueSet(
                        component: 3,
                        allowedValues: ["ISO639"],
                        specCitation: "HL7au:000042 — MSH-19.3 (coding system) must be \"ISO639\""
                    ),
                ],
                specCitation: "HL7au:000042 — MSH-19 language required + narrowed to en/English/ISO639"
            ),
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
        ],
        grammarExtensions: [
            // AU pre-adopts v2.5+ PID fields 35..38 (Species Code,
            // Breed Code, Strain, Production Class Code) on v2.4
            // wires. Grammar definitions mirror the v2.5.1 PID
            // schema, including the conditional predicates added in
            // v0.4-S4-C. Under `.auLocalisation` the Validator merges
            // these into the v2.4 PID grammar so they validate
            // against the same rules they do on v2.5.1 wires. v0.5-
            // S5-D.
            "PID": [
                FieldGrammar(
                    index: 35,
                    name: "Species Code",
                    dataType: "CE",
                    optionality: .conditional,
                    repeatability: .single,
                    condition: "PID-36 populated OR PID-38 populated"
                ),
                FieldGrammar(
                    index: 36,
                    name: "Breed Code",
                    dataType: "CE",
                    optionality: .conditional,
                    repeatability: .single,
                    condition: "PID-37 populated"
                ),
                FieldGrammar(
                    index: 37,
                    name: "Strain",
                    dataType: "ST",
                    optionality: .optional,
                    repeatability: .single
                ),
                FieldGrammar(
                    index: 38,
                    name: "Production Class Code",
                    dataType: "CE",
                    optionality: .optional,
                    repeatability: .single
                ),
            ],
        ],
        compositeOverrides: [
            // CX datatype — HL7au:00044.1 series. Skip 44.1.1 (CX-1
            // must be specified) since the base spec already requires
            // CX-1 (CX.requiredComponents = [(1, "ID Number")]);
            // adding it again would be redundant. The genuinely new
            // AU narrowings are 44.1.2 (CX-4 assigning authority
            // required when CX is populated) and 44.1.3 (CX-5
            // identifier type code required when CX is populated).
            // The "must conform to sub points of HL7au:00044.2"
            // clause on 44.1.2 references NASH/PKI rules that are
            // runtime-dependent and out of scope for parser/validator.
            // v0.5-S5-B-3.
            CompositeOverride(
                dataType: "CX",
                requiredComponents: [
                    ComponentRequirement(
                        component: 4,
                        specCitation: "HL7au:00044.1.2 (r2) — CX-4 assigning authority must be valued"
                    ),
                    ComponentRequirement(
                        component: 5,
                        specCitation: "HL7au:00044.1.3 — CX-5 identifier type code must be valued"
                    ),
                ],
                pairRules: []
            ),
            // CE datatype — HL7au:00044.4 series. Skip 44.4.3 (CE-2
            // "text must be valued") since it carries an explicit
            // "may be blank in some locations" carve-out; also skip
            // 44.4.4 / 44.4.7 / 44.4.8 (value-set / semantic rules
            // not expressible as pair-conditionals — defer to S5-C).
            CompositeOverride(
                dataType: "CE",
                requiredComponents: [],
                pairRules: ceCwePairRules(citePrefix: "HL7au:00044.4")
            ),
            // CNE datatype — HL7au:00044.5 series. Same pair shape.
            CompositeOverride(
                dataType: "CNE",
                requiredComponents: [],
                pairRules: ceCwePairRules(citePrefix: "HL7au:00044.5")
            ),
            // CWE datatype — HL7au:00044.6 series. Same pair shape but
            // the spec numbers components 4 and 5 differently from CE.
            CompositeOverride(
                dataType: "CWE",
                requiredComponents: [],
                pairRules: ceCwePairRules(citePrefix: "HL7au:00044.6")
            ),
        ]
    )

    /// Shared pair-rule set for CE / CNE / CWE. All three composites
    /// follow the same shape: identifier ⇔ coding-system, alternate-
    /// identifier ⇔ alternate-coding-system. Only the HL7au identifier
    /// prefix differs between them.
    ///
    /// The four rules implement:
    /// - `.1` "If identifier set, coding system must be set"
    /// - `.2` "If identifier not set, coding system must not be set"
    /// - `.4` or `.5` "If alternate identifier set, alternate coding system must be set"
    /// - `.5` or `.6` "If alternate identifier not set, alternate coding system must not be set"
    ///
    /// (CE / CNE use `.5` / `.6` for alternate rules; CWE uses `.4` /
    /// `.5`. Spec citations follow this convention.)
    private static func ceCwePairRules(citePrefix: String) -> [PairConditional] {
        let altCite: (Int) -> String
        if citePrefix == "HL7au:00044.6" {
            altCite = { suffix in "\(citePrefix).\(suffix - 1)" }
        } else {
            altCite = { suffix in "\(citePrefix).\(suffix)" }
        }
        return [
            PairConditional(
                ifComponent: 1, condition: .populated,
                thenComponent: 3, requirement: .mustBePopulated,
                specCitation: "\(citePrefix).1 — identifier set ⇒ coding system set"
            ),
            PairConditional(
                ifComponent: 1, condition: .empty,
                thenComponent: 3, requirement: .mustBeEmpty,
                specCitation: "\(citePrefix).2 — identifier empty ⇒ coding system empty"
            ),
            PairConditional(
                ifComponent: 4, condition: .populated,
                thenComponent: 6, requirement: .mustBePopulated,
                specCitation: "\(altCite(5)) — alt identifier set ⇒ alt coding system set"
            ),
            PairConditional(
                ifComponent: 4, condition: .empty,
                thenComponent: 6, requirement: .mustBeEmpty,
                specCitation: "\(altCite(6)) — alt identifier empty ⇒ alt coding system empty"
            ),
        ]
    }
}
