// Profile+au_adrm_2021.swift
// Hand-curated AU ADRM-2021 profile content. This Swift file is the
// SINGLE SOURCE OF TRUTH for the AU profile — it is what `Profile.load`
// returns at runtime, and it is validated by the Swift compiler (the
// rule types are type-checked at build time, unlike a hand-synced JSON
// mirror would be).
//
// v0.14 retired the orphaned `Resources/profiles/au-adrm-2021/*.json`
// overlay files that ADR-007 originally envisioned: they were never
// consumed at runtime (profile loading always returned this Swift) and
// had drifted stale (missing the v0.8 MSH-12, v0.11 cardinality, and
// v0.13 composite-inequality rules). A JSON-driven codegen path (per
// ADR-004) is deferred until a SECOND localisation profile makes shared
// tooling worthwhile — see ADR-007 (v0.14 status note).
//
// v0.5-S5-B-1 ships the EI-all-components rules for OBR-2/3 + ORC-2/3/4
// per HL7au:000003 / 000004.1 / 000005 / 000006 / 000007 in Appendix 5
// of HL7AUSD-STD-OO-ADRM-2021.1. Each FieldOverride carries the spec
// citation in the source comment.

import Foundation

extension Profile {
    /// HL7 Australia ADRM-2021 profile, layered over base HL7 v2.4.
    /// Returned by `Profile.load(for: .auLocalisation)`.
    ///
    /// v0.5-S5-B-1 scope: EI-all-components rules for OBR-2 / OBR-3 /
    /// ORC-2 / ORC-3 / ORC-4. Each enforces that when the field is
    /// populated, all four Entity Identifier components (Entity ID,
    /// Namespace ID, Universal ID, Universal ID Type) are populated.
    static let auADRM2021 = Profile(
        locale: .auLocalisation,
        fieldOverrides: [
            // HL7au:000040 — MSH-12 Version ID Field Conformance Points
            // (AU ADRM-2021 pp. 445-446, extracted via PDFKit recipe).
            // Five subrules in the spec; 040.5 is receiver runtime
            // behaviour (out of scope for a validator). v0.8 (ADR-009)
            // ships .1, .2, .3, .4 as follows:
            //
            // 040.1/.2 (Senders Orders, Results, Referrals, ACK, RRI):
            //   - VID-1 (Version ID) = "2.4"
            //   - VID-2 (Internationalization Code, CE):
            //       .1 = "AUS", .2 = "Australia", .3 = "ISO3166_1"
            //   v0.8-S3b (review): the spec enumerates these five
            //   message-type categories; gating prevents over-fire on
            //   message types outside scope (e.g. ADT).
            //
            // 040.3 (Senders Orders, Results — messageCode in
            //   (ORM, ORU)):
            //   - VID-3 (Internal Version ID, CE) = "HL7AU-OO-201701&&L"
            //     literal, i.e. .1 = "HL7AU-OO-201701", .2 = empty,
            //     .3 = "L". v0.8-S3b adds the .2 = "" pin for full
            //     literal conformance.
            //
            // 040.4 (Senders Referrals, RRI — messageCode in
            //   (REF, RRI)):
            //   - VID-3 = "HL7AU-OO-REF-SIMPLIFIED-201706&&L" (Level 2)
            //     OR "HL7AU-OO-REF-SIMPLIFIED-201706-L1&&L" (Level 1),
            //     each with empty .2 and .3 = "L".
            //
            // profileUsage stays nil because MSH-12 is already R in
            // the base HL7 v2 grammar — base-spec checkRequired
            // catches the empty case; the AU rules add value-set
            // narrowings on top.
            //
            // Reused gating predicates:
            //   universal40 = "messageCode in (ORM, ORU, REF, RRI, ACK)"
            //   orders     = "messageCode in (ORM, ORU)"
            //   referrals  = "messageCode in (REF, RRI)"
            FieldOverride(
                segmentID: "MSH",
                fieldIndex: 12,
                componentValueSets: [
                    // 040.1/.2: VID-1 = "2.4"
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["2.4"],
                        condition: "messageCode in (ORM, ORU, REF, RRI, ACK)",
                        specCitation: "HL7au:000040.1/.2 (r2) — MSH-12.1 (Version ID) must be \"2.4\" on Senders Orders/Results/Referrals/ACK/RRI"
                    ),
                    // 040.1/.2: VID-2.1 = "AUS"
                    ComponentValueSet(
                        component: 2,
                        subcomponent: 1,
                        allowedValues: ["AUS"],
                        condition: "messageCode in (ORM, ORU, REF, RRI, ACK)",
                        specCitation: "HL7au:000040.1/.2 (r2) — MSH-12.2.1 (Internationalization Code identifier) must be \"AUS\""
                    ),
                    // 040.1/.2: VID-2.2 = "Australia"
                    ComponentValueSet(
                        component: 2,
                        subcomponent: 2,
                        allowedValues: ["Australia"],
                        condition: "messageCode in (ORM, ORU, REF, RRI, ACK)",
                        specCitation: "HL7au:000040.1/.2 (r2) — MSH-12.2.2 (Internationalization Code text) must be \"Australia\""
                    ),
                    // 040.1/.2: VID-2.3 = "ISO3166_1"
                    ComponentValueSet(
                        component: 2,
                        subcomponent: 3,
                        allowedValues: ["ISO3166_1"],
                        condition: "messageCode in (ORM, ORU, REF, RRI, ACK)",
                        specCitation: "HL7au:000040.1/.2 (r2) — MSH-12.2.3 (Internationalization Code coding system) must be \"ISO3166_1\""
                    ),
                    // 040.3 (Orders/Results only): VID-3.1 = "HL7AU-OO-201701"
                    ComponentValueSet(
                        component: 3,
                        subcomponent: 1,
                        allowedValues: ["HL7AU-OO-201701"],
                        condition: "messageCode in (ORM, ORU)",
                        specCitation: "HL7au:000040.3 — MSH-12.3.1 (Internal Version ID identifier) must be \"HL7AU-OO-201701\" on Orders/Results"
                    ),
                    // 040.3 (Orders/Results only): VID-3.2 must be empty
                    // per the literal "HL7AU-OO-201701&&L" form.
                    ComponentValueSet(
                        component: 3,
                        subcomponent: 2,
                        allowedValues: [""],
                        condition: "messageCode in (ORM, ORU)",
                        specCitation: "HL7au:000040.3 — MSH-12.3.2 (Internal Version ID text) must be empty per literal \"HL7AU-OO-201701&&L\" on Orders/Results"
                    ),
                    // 040.3 (Orders/Results only): VID-3.3 = "L"
                    ComponentValueSet(
                        component: 3,
                        subcomponent: 3,
                        allowedValues: ["L"],
                        condition: "messageCode in (ORM, ORU)",
                        specCitation: "HL7au:000040.3 — MSH-12.3.3 (Internal Version ID coding system) must be \"L\" on Orders/Results"
                    ),
                    // 040.4 (Referrals/RRI only): VID-3.1 in {Level 2, Level 1}
                    ComponentValueSet(
                        component: 3,
                        subcomponent: 1,
                        allowedValues: [
                            "HL7AU-OO-REF-SIMPLIFIED-201706",
                            "HL7AU-OO-REF-SIMPLIFIED-201706-L1",
                        ],
                        condition: "messageCode in (REF, RRI)",
                        specCitation: "HL7au:000040.4 (r2) — MSH-12.3.1 (Internal Version ID identifier) must be HL7AU-OO-REF-SIMPLIFIED-201706 (Level 2) or HL7AU-OO-REF-SIMPLIFIED-201706-L1 (Level 1) on Referrals/RRI"
                    ),
                    // 040.4 (Referrals/RRI only): VID-3.2 must be empty
                    // per the literal "...&&L" form.
                    ComponentValueSet(
                        component: 3,
                        subcomponent: 2,
                        allowedValues: [""],
                        condition: "messageCode in (REF, RRI)",
                        specCitation: "HL7au:000040.4 (r2) — MSH-12.3.2 (Internal Version ID text) must be empty per literal \"...&&L\" on Referrals/RRI"
                    ),
                    // 040.4 (Referrals/RRI only): VID-3.3 = "L"
                    ComponentValueSet(
                        component: 3,
                        subcomponent: 3,
                        allowedValues: ["L"],
                        condition: "messageCode in (REF, RRI)",
                        specCitation: "HL7au:000040.4 (r2) — MSH-12.3.3 (Internal Version ID coding system) must be \"L\" on Referrals/RRI"
                    ),
                ],
                specCitation: "HL7au:000040 (r2) — MSH-12 Version ID Field Conformance Points"
            ),
            // HL7au:000041 (r2) — MSH-17 country code must be "AUS"
            // for Australian originators. The spec says MSH-17 must
            // be specified (required under AU) AND its value must be
            // "AUS". The profileUsage = .required dispatch fires on
            // empty MSH-17; the componentValueSets fire on populated-
            // but-wrong values.
            //
            // M6-D3 (2026-09-04): both halves are gated on the message
            // types Appendix 5 names for this point ("Orders, Results,
            // Referrals, Acknowledgement, Referral Response"). They
            // used to be ungated and fired on ADT, SIU, MDM and every
            // other message type the localisation never addressed.
            FieldOverride(
                segmentID: "MSH",
                fieldIndex: 17,
                profileUsage: .required,
                condition: "messageCode in (ORM, ORU, REF, RRI, ACK)",
                componentValueSets: [
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["AUS"],
                        condition: "messageCode in (ORM, ORU, REF, RRI, ACK)",
                        specCitation: "HL7au:000041 (r2) — MSH-17 country must be \"AUS\""
                    )
                ],
                specCitation: "HL7au:000041 (r2) — MSH-17 country required + narrowed to AUS"
            ),
            // HL7au:000042 — MSH-19 must equal "en^English^ISO639"
            // per AU English-only messaging conformance. Same
            // pattern: profileUsage = .required + per-component
            // value-set checks, and the same M6-D3 message-type gate.
            FieldOverride(
                segmentID: "MSH",
                fieldIndex: 19,
                profileUsage: .required,
                condition: "messageCode in (ORM, ORU, REF, RRI, ACK)",
                componentValueSets: [
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["en"],
                        condition: "messageCode in (ORM, ORU, REF, RRI, ACK)",
                        specCitation: "HL7au:000042 — MSH-19.1 (identifier) must be \"en\""
                    ),
                    ComponentValueSet(
                        component: 2,
                        allowedValues: ["English"],
                        condition: "messageCode in (ORM, ORU, REF, RRI, ACK)",
                        specCitation: "HL7au:000042 — MSH-19.2 (text) must be \"English\""
                    ),
                    ComponentValueSet(
                        component: 3,
                        allowedValues: ["ISO639"],
                        condition: "messageCode in (ORM, ORU, REF, RRI, ACK)",
                        specCitation: "HL7au:000042 — MSH-19.3 (coding system) must be \"ISO639\""
                    ),
                ],
                specCitation: "HL7au:000042 — MSH-19 language required + narrowed to en/English/ISO639"
            ),
            // ---- M6-A stage 1: MSH envelope literals -------------
            // Eleven Appendix 5 conformance points, all fixed-value or
            // presence assertions on the message header. Message-type
            // scopes are taken verbatim from the Appendix 5 table and
            // differ between points, so each carries its own gate:
            //   "Orders, Results, Referrals" → (ORM, ORU, REF)
            //   "Orders, Results"            → (ORM, ORU)

            // HL7au:000024.1 — the field separator must be "|". MSH-1
            // (and FHS-1 / BHS-1) IS the separator character, parsed as
            // a scalar, so this is a one-value value set on component 1.
            // A wire like "MSH!^~\&!..." parses cleanly with "!" as the
            // separator and is exactly what this point rejects.
            FieldOverride(
                segmentID: "MSH",
                fieldIndex: 1,
                componentValueSets: [
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["|"],
                        condition: "messageCode in (ORM, ORU, REF)",
                        specCitation: "HL7au:000024.1 — MSH-1 field separator must be \"|\""
                    )
                ],
                specCitation: "HL7au:000024.1 — field separator narrowed to \"|\""
            ),
            // HL7au:000024.2/.3/.4/.5 — the four encoding characters.
            // MSH-2 is parsed as one scalar literal (no internal split),
            // so the conjunction of the four points is a single pin:
            // MSH-2 == "^~\&".
            //
            // KNOWN GAP, registered: .2 (component separator) is scoped
            // to Orders, Results AND Referrals, while .3/.4/.5 are
            // Orders/Results only. Pinning the whole literal on REF
            // would enforce .3/.4/.5 where the spec does not, so the
            // gate is the (ORM, ORU) intersection and .2-on-Referrals
            // goes unenforced. Expressing it needs character-position
            // addressing inside a component — see M6-B in
            // `docs/design/m6-adrm-2021-localisation-audit.md`.
            FieldOverride(
                segmentID: "MSH",
                fieldIndex: 2,
                componentValueSets: [
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["^~\\&"],
                        condition: "messageCode in (ORM, ORU)",
                        specCitation: "HL7au:000024.2/.3/.4/.5 — MSH-2 encoding characters must be \"^~\\&\" (component, repeat, escape, sub-component)"
                    )
                ],
                specCitation: "HL7au:000024.2/.3/.4/.5 — encoding characters narrowed to the AU literal"
            ),
            // HL7au:00049.2 / .3 — MSH-9 trigger event and message
            // structure must both be valued. 00049.1 (message code) is
            // not restated: MSG-1 is already `MSG.requiredComponents`
            // in the base model, so the base check fires first.
            FieldOverride(
                segmentID: "MSH",
                fieldIndex: 9,
                condition: "messageCode in (ORM, ORU, REF)",
                requiredComponents: [2, 3],
                specCitation: "HL7au:00049.2/.3 — MSH-9 trigger event (MSG-2) and message structure (MSG-3) must be valued"
            ),
            // HL7au:00047.1 — MSH-15 must be valued "AL". Base v2.4 has
            // MSH-15 optional, so this needs both halves: the usage
            // narrowing for the absent case, the value set for the
            // populated-but-wrong case.
            FieldOverride(
                segmentID: "MSH",
                fieldIndex: 15,
                profileUsage: .required,
                condition: "messageCode in (ORM, ORU, REF)",
                componentValueSets: [
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["AL"],
                        condition: "messageCode in (ORM, ORU, REF)",
                        specCitation: "HL7au:00047.1 — MSH-15 (Accept acknowledgement type) must be \"AL\""
                    )
                ],
                specCitation: "HL7au:00047.1 — MSH-15 required + narrowed to \"AL\""
            ),
            // HL7au:00047.2 — MSH-16 must be valued "AL". Same shape.
            FieldOverride(
                segmentID: "MSH",
                fieldIndex: 16,
                profileUsage: .required,
                condition: "messageCode in (ORM, ORU, REF)",
                componentValueSets: [
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["AL"],
                        condition: "messageCode in (ORM, ORU, REF)",
                        specCitation: "HL7au:00047.2 — MSH-16 (Application acknowledgement type) must be \"AL\""
                    )
                ],
                specCitation: "HL7au:00047.2 — MSH-16 required + narrowed to \"AL\""
            ),
            // HL7au:00048.3.1 — MSH-18 may only carry "" (unvalued),
            // "ASCII", or by site agreement "UNICODE UTF-8" / "8859/1".
            // No usage narrowing: the point permits an unvalued MSH-18,
            // and the value-set track only runs on populated fields.
            // MSH-18 repeats; each repetition is checked.
            FieldOverride(
                segmentID: "MSH",
                fieldIndex: 18,
                componentValueSets: [
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["", "ASCII", "UNICODE UTF-8", "8859/1"],
                        condition: "messageCode in (ORM, ORU, REF)",
                        specCitation: "HL7au:00048.3.1 — MSH-18 (Character set) must be \"\", \"ASCII\", or by site agreement \"UNICODE UTF-8\" / \"8859/1\""
                    )
                ],
                specCitation: "HL7au:00048.3.1 — MSH-18 character set value set"
            ),
            FieldOverride(
                segmentID: "OBR",
                fieldIndex: 2,
                profileUsage: nil,
                requiredComponents: [1, 2, 3, 4],
                specCitation: "HL7au:000003 (r2) — OBR-2 EI completeness"
            ),
            FieldOverride(
                segmentID: "OBR",
                fieldIndex: 3,
                profileUsage: nil,
                requiredComponents: [1, 2, 3, 4],
                specCitation: "HL7au:000004.1 (r3) — OBR-3 EI completeness"
            ),
            FieldOverride(
                segmentID: "ORC",
                fieldIndex: 2,
                profileUsage: nil,
                requiredComponents: [1, 2, 3, 4],
                specCitation: "HL7au:000005 (r2) — ORC-2 EI completeness"
            ),
            FieldOverride(
                segmentID: "ORC",
                fieldIndex: 3,
                profileUsage: nil,
                requiredComponents: [1, 2, 3, 4],
                specCitation: "HL7au:000006 (r3) — ORC-3 EI completeness"
            ),
            FieldOverride(
                segmentID: "ORC",
                fieldIndex: 4,
                profileUsage: nil,
                requiredComponents: [1, 2, 3, 4],
                specCitation: "HL7au:000007 (r2) — ORC-4 EI completeness"
            ),
            // HL7au:000008.1 (r2) — Display Segments (v0.11-S2, ADR-010).
            // OBX-3 display-format identifier value set, gated on
            // AUSPDI coding system. Spec text (AU ADRM-2021 p. 420-421):
            //   "Display segments must use the appropriate valid values
            //    within the AUSPDI coding system in OBX-3 for the
            //    content that is represented in it: HTML / PDF / RTF /
            //    TXT (deprecated PIT still supported by receivers)."
            // Value set from Display Format codes table on p. 247.
            // Gate `OBX-3.3 = AUSPDI` uses ADR-010 Extension 3
            // (subcomponent-granular field-refs on the atom LHS) so the
            // overlay only fires when the segment IS a display segment
            // — atomic OBX segments (any other coding system in
            // OBX-3.3) pass through unaltered.
            // Note: ADR-010 §"Rules expressed…" wrote `component: 3` for
            // the overlay by editorial oversight — component 3 IS the
            // AUSPDI gate itself. The value-set check is on component 1
            // (Identifier), per HL7au:000008.1 verbatim. ADR post-hoc
            // clarification added 2026-07-03.
            FieldOverride(
                segmentID: "OBX",
                fieldIndex: 3,
                componentValueSets: [
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["HTML", "PDF", "RTF", "TXT", "PIT"],
                        condition: "OBX-3.3 = AUSPDI",
                        specCitation: "HL7au:000008.1 (r2) — OBX-3.1 (Identifier) must be HTML / PDF / RTF / TXT (deprecated PIT permitted) on display segments (AUSPDI); AU ADRM-2021 pp. 420-421, table p. 247"
                    )
                ],
                specCitation: "HL7au:000008.1 (r2) — OBX-3 display-format identifier value set on AUSPDI display segments"
            ),
            // M6-B-1 — HL7au:00104.7.0 (r3): "PRD-7 must have at least
            // 1 repeat (for providers receiving electronic
            // communication specified by IR - Intended Recipient in
            // PRD-1)." A populated field has ≥1 repeat, so this is a
            // per-instance required-usage narrowing on the IR PRD.
            // PRD-1 repeats, hence the anyRepeat gate (req #4: "IR" in
            // a later repetition still identifies the intended
            // recipient).
            FieldOverride(
                segmentID: "PRD",
                fieldIndex: 7,
                profileUsage: .required,
                condition: "messageCode = REF AND anyRepeat(PRD-1) = IR",
                componentValueSets: [
                    // M6-B-4 — HL7au:00104.7.2.1: "PRD-7 <type of ID
                    // number (IS)> must be valued from User-defined
                    // Table 0363 - Assigning Authority." The value-set
                    // check runs per populated repetition, so every
                    // provider identifier in the repeat list is held to
                    // the table.
                    ComponentValueSet(
                        component: 2,
                        allowedValues: HL7CodeTables.table0363,
                        condition: "messageCode = REF",
                        specCitation: "HL7au:00104.7.2.1 — PRD-7.2 (type of ID number) must be valued from User-defined Table 0363 (Assigning Authority) on Senders Referrals; AU ADRM-2021 Appendix 5 p. 472, table p. 310"
                    ),
                    // M6-B-4 — HL7au:00104.7.3.1: "<other qualifying
                    // info (ST)> must be a valued from HL7 Table 0203 -
                    // Identifier Type."
                    ComponentValueSet(
                        component: 3,
                        allowedValues: HL7CodeTables.table0203,
                        condition: "messageCode = REF",
                        specCitation: "HL7au:00104.7.3.1 — PRD-7.3 (other qualifying info) must be valued from HL7 Table 0203 (Identifier Type) on Senders Referrals; AU ADRM-2021 Appendix 5 p. 472, table p. 301"
                    ),
                ],
                specCitation: "HL7au:00104.7.0 (r3) — PRD-7 must have at least 1 repeat on the Intended Recipient (PRD-1 = IR) PRD in the REF message; AU ADRM-2021 Appendix 5 p. 472"
            ),
            // M6-B-4 — HL7au:000032 / 000032.2: "the field OBR-24
            // 'Diagnostic serv sect ID' must be valued and must have
            // values from HL7 table 0074." Presence on ORU and REF via
            // the gated usage narrowing; membership per leg below.
            // 000032.2's second half ("appropriate for the content in
            // the OBR/OBX group") is receiver-judgement over content —
            // membership is enforced, appropriateness is not (PARTIAL).
            FieldOverride(
                segmentID: "OBR",
                fieldIndex: 24,
                profileUsage: .required,
                condition: "messageCode in (ORU, REF)",
                componentValueSets: [
                    ComponentValueSet(
                        component: 1,
                        allowedValues: HL7CodeTables.table0074,
                        condition: "messageCode = ORU",
                        specCitation: "HL7au:000032 — OBR-24 must be valued from HL7 Table 0074 (Diagnostic Service Section) on Senders Results; AU ADRM-2021 Appendix 5 p. 444, table pp. 225-226"
                    ),
                    ComponentValueSet(
                        component: 1,
                        allowedValues: HL7CodeTables.table0074,
                        condition: "messageCode = REF",
                        specCitation: "HL7au:000032.2 — OBR-24 must be valued from HL7 Table 0074 on Senders Referrals (content-appropriateness half not machine-checkable); AU ADRM-2021 Appendix 5 p. 444"
                    ),
                ],
                specCitation: "HL7au:000032 / 000032.2 — OBR-24 (Diagnostic Serv Sect ID) must be valued on Senders Results/Referrals; AU ADRM-2021 Appendix 5 p. 444"
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
                // M6-D4: HL7au:00044.1 series is scoped to
                // "Orders, Results, Referrals".
                condition: "messageCode in (ORM, ORU, REF)",
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
            // CE datatype — HL7au:00044.4 series.
            // - 44.4.1/.2/.5/.6: identifier ⇔ coding-system pairs (pairRules).
            // - 44.4.8 (v0.13, ADR-011): alternate coding system (CE-6)
            //   must differ from primary coding system (CE-3).
            // - 44.4.4 (v0.13, ADR-011): LOINC (LN) must be the primary
            //   coding system, not the alternate — machine-checkable
            //   necessary condition "CE-6 must not be LN" on Orders/Results.
            // Still NOT shipped (documented in the audit doc as permanent
            // limitations): 44.4.3 (CE-2 text — "may be blank in some
            // locations" carve-out, would over-fire) and 44.4.7 (concept-
            // match — requires a terminology service, not wire-checkable).
            // ---- M6-A stage 2: XCN required components ------------
            // HL7au:00044.7 series, scoped to "Orders, Results,
            // Referrals". Component indices from the v2.4 XCN
            // definition (CH02 §2.9.52).
            //
            // .7.1 is NOT restated: XCN-1 is already
            // `XCN.requiredComponents` in the base model.
            // .7.6 (<given name> "should" be valued) is advisory, not a
            // "must", so it is not enforced.
            //
            // PARTIAL, registered: .7.3 and .7.4 each require the
            // component to be valued AND to carry a value from an HL7
            // code table (0200 and 0203). The presence half ships here;
            // the value-set half cannot — HL7 code tables are not
            // modelled at all (the schemas drop the spec's TBL# column
            // and there is no table registry). See M6-O6.
            CompositeOverride(
                dataType: "XCN",
                // M6-D4: HL7au:00044.7 series is scoped to
                // "Orders, Results, Referrals".
                condition: "messageCode in (ORM, ORU, REF)",
                requiredComponents: [
                    ComponentRequirement(
                        component: 2,
                        subcomponent: 1,
                        specCitation: "HL7au:00044.7.5 — XCN-2.1 (family name → surname) must be valued"
                    ),
                    ComponentRequirement(
                        component: 9,
                        specCitation: "HL7au:00044.7.2 — XCN-9 (assigning authority) must be valued"
                    ),
                    ComponentRequirement(
                        component: 10,
                        specCitation: "HL7au:00044.7.3 — XCN-10 (name type code) must be valued"
                    ),
                    ComponentRequirement(
                        component: 13,
                        specCitation: "HL7au:00044.7.4 — XCN-13 (identifier type code) must be valued"
                    ),
                ],
                // M6-B-5 — the membership halves that held .7.3/.7.4 at
                // PARTIAL, now expressible via the composite value-set
                // track over the HL7CodeTables seed. Populated-only:
                // presence stays the requiredComponents' job above.
                componentValueSets: [
                    ComponentValueSet(
                        component: 10,
                        allowedValues: HL7CodeTables.table0200,
                        specCitation: "HL7au:00044.7.3 — XCN-10 (name type code) must be a valid value from HL7 Table 0200 (Name Type); AU ADRM-2021 table p. 62"
                    ),
                    ComponentValueSet(
                        component: 13,
                        allowedValues: HL7CodeTables.table0203,
                        specCitation: "HL7au:00044.7.4 — XCN-13 (identifier type code) must be a valid value from HL7 Table 0203 (Identifier Type); AU ADRM-2021 table pp. 301-309"
                    ),
                ]
            ),
            CompositeOverride(
                dataType: "CE",
                // M6-D4: HL7au:00044.4 series is scoped to
                // "Orders, Results, Referrals".
                condition: "messageCode in (ORM, ORU, REF)",
                requiredComponents: [],
                pairRules: ceCwePairRules(citePrefix: "HL7au:00044.4"),
                componentInequalities: [
                    ComponentInequality(
                        componentA: 3,
                        componentB: 6,
                        specCitation: "HL7au:00044.4.8 — CE alternate coding system (CE-6) must differ from primary coding system (CE-3)"
                    )
                ],
                valueConditionals: [
                    ComponentValueConditional(
                        component: 6,
                        deniedValues: ["LN"],
                        condition: "messageCode in (ORM, ORU)",
                        specCitation: "HL7au:00044.4.4 — LOINC (LN) must be the primary coding system (CE-3), not the alternate (CE-6), on Orders/Results"
                    )
                ]
            ),
            // CNE datatype — HL7au:00044.5 series. Pair shape + 44.5.3
            // (v0.13): CNE-2 <text> must be valued (no carve-out, unlike
            // CE-2). The concept-match leg (44.5.7) is marked "Removed"
            // in ADRM r2 — not shipped.
            CompositeOverride(
                dataType: "CNE",
                // M6-D4: HL7au:00044.5 series is scoped to
                // "Orders, Results, Referrals".
                condition: "messageCode in (ORM, ORU, REF)",
                requiredComponents: [
                    ComponentRequirement(
                        component: 2,
                        specCitation: "HL7au:00044.5.3 — CNE <text> component must be valued (display to user)"
                    )
                ],
                pairRules: ceCwePairRules(citePrefix: "HL7au:00044.5")
            ),
            // CWE datatype — HL7au:00044.6 series. Pair shape + 44.6.3
            // (v0.13): CWE-2 <text> must be valued. Concept-match leg
            // (44.6.7) marked "Removed" in ADRM r2 — not shipped.
            CompositeOverride(
                dataType: "CWE",
                // M6-D4: HL7au:00044.6 series is scoped to
                // "Orders, Results, Referrals".
                condition: "messageCode in (ORM, ORU, REF)",
                requiredComponents: [
                    ComponentRequirement(
                        component: 2,
                        specCitation: "HL7au:00044.6.3 — CWE <text> component must be valued (display to user)"
                    )
                ],
                pairRules: ceCwePairRules(citePrefix: "HL7au:00044.6")
            ),
        ],
        cardinalityExtensions: [
            // M6-A-3 — the two ADRM-2021 prohibitions. Both are
            // "count of matching segments must be zero", which the
            // minimum-only cardinality model of v0.11 could not state;
            // `SegmentCardinalityRule.maxCount` adds the upper bound.
            // Attached to MSH because `.messageWide` resolves its group
            // from the anchor and MSH occurs exactly once — the rule
            // then fires at most once per message.
            "MSH": [
                // HL7au:000021 — "Data type TX must NOT be used as a
                // value in the OBX-2 Value Type field." Appendix 5
                // scopes it to "Results, Referrals(L2)": the Results
                // leg gates on ORU; the Referrals(L2) leg gates on the
                // profile the sender declares in MSH-12.3.1 — the ADRM
                // states "the <internal version ID (CE)> component must
                // be valued ... to indicate the profile that is being
                // adhered [to]" and its profile table names
                // HL7AU-OO-REF-SIMPLIFIED-201706 as Level 2 (M6-B-6;
                // the earlier "MSH-21" note in the audit doc was a
                // misidentification, corrected there).
                SegmentCardinalityRule(
                    countedSegmentID: "OBX",
                    scope: .messageWide,
                    minCount: 0,
                    maxCount: 0,
                    predicate: "OBX-2 = TX",
                    applicableWhen: "messageCode = ORU",
                    specCitation: "HL7au:000021 — OBX-2 must not be valued TX on Senders Results; AU ADRM-2021 Appendix 5 p. 439"
                ),
                SegmentCardinalityRule(
                    countedSegmentID: "OBX",
                    scope: .messageWide,
                    minCount: 0,
                    maxCount: 0,
                    predicate: "OBX-2 = TX",
                    applicableWhen: "messageCode = REF AND MSH-12.3.1 = HL7AU-OO-REF-SIMPLIFIED-201706",
                    specCitation: "HL7au:000021 — OBX-2 must not be valued TX on Senders Referrals(L2), the profile MSH-12.3.1 declares; AU ADRM-2021 Appendix 5 p. 439"
                ),
                // HL7au:000023 — "The NTE segment must NOT be used in
                // messages." Scoped to "Orders, Results, Referrals";
                // plain "Referrals" is every REF profile (Appendix 5
                // preamble), so the gate is the three message codes.
                //
                // Empty predicate: the prohibition is on the segment
                // itself, not on any field of it.
                SegmentCardinalityRule(
                    countedSegmentID: "NTE",
                    scope: .messageWide,
                    minCount: 0,
                    maxCount: 0,
                    predicate: "",
                    applicableWhen: "messageCode in (ORM, ORU, REF)",
                    specCitation: "HL7au:000023 — the NTE segment must not be used on Senders Orders/Results/Referrals; AU ADRM-2021 Appendix 5 p. 440"
                ),
                // M6-B-1 — the two PRD exactly-one rules. PRD-1 is a
                // repeating CE, so the predicate uses the anyRepeat
                // atom: a provider with roles "RP~AP" carries AP in a
                // later repetition and the first-repetition scalar
                // convention would have missed it (req #4).
                //
                // HL7au:00104.1.1 — "There must be exactly one PRD
                // with a PRD-1 value of 'AP' (Authoring Provider) in
                // the REF message."
                SegmentCardinalityRule(
                    countedSegmentID: "PRD",
                    scope: .messageWide,
                    minCount: 1,
                    maxCount: 1,
                    predicate: "anyRepeat(PRD-1) = AP",
                    applicableWhen: "messageCode = REF",
                    specCitation: "HL7au:00104.1.1 — exactly one PRD with PRD-1 = AP (Authoring Provider) in the REF message; AU ADRM-2021 Appendix 5 p. 472"
                ),
                // HL7au:00104.2.1 — "There must be exactly one PRD
                // with a PRD-1 value of 'IR' (Intended Recipient) in
                // the REF message."
                SegmentCardinalityRule(
                    countedSegmentID: "PRD",
                    scope: .messageWide,
                    minCount: 1,
                    maxCount: 1,
                    predicate: "anyRepeat(PRD-1) = IR",
                    applicableWhen: "messageCode = REF",
                    specCitation: "HL7au:00104.2.1 — exactly one PRD with PRD-1 = IR (Intended Recipient) in the REF message; AU ADRM-2021 Appendix 5 p. 472"
                ),
                // M6-B-2 — the Z-prefix prohibitions (p. 439-440).
                //
                // HL7au:000020 — "All message types and trigger event
                // codes beginning with the letter 'Z' are reserved for
                // locally-defined messages and must NOT be used."
                // Scoped Orders/Results/Referrals(L2). The trigger-event
                // leg ships on (ORM, ORU) and — since M6-B-6 — on
                // Referrals(L2) via the MSH-12.3.1 profile gate. Still
                // PARTIAL for the message-CODE leg: a wholly-Z message
                // code (ZAA^...) never satisfies any message-type gate,
                // so that half is undecidable inside this rule shape.
                SegmentCardinalityRule(
                    countedSegmentID: "MSH",
                    scope: .messageWide,
                    minCount: 0,
                    maxCount: 0,
                    predicate: "triggerEvent startsWith Z",
                    applicableWhen: "messageCode in (ORM, ORU)",
                    specCitation: "HL7au:000020 — trigger event codes beginning with Z are reserved and must not be used on Senders Orders/Results; AU ADRM-2021 Appendix 5 p. 439"
                ),
                SegmentCardinalityRule(
                    countedSegmentID: "MSH",
                    scope: .messageWide,
                    minCount: 0,
                    maxCount: 0,
                    predicate: "triggerEvent startsWith Z",
                    applicableWhen: "messageCode = REF AND MSH-12.3.1 = HL7AU-OO-REF-SIMPLIFIED-201706",
                    specCitation: "HL7au:000020 — Z trigger events must not be used on Senders Referrals(L2), the profile MSH-12.3.1 declares; AU ADRM-2021 Appendix 5 p. 439"
                ),
                // HL7au:000023.1 — "User defined segments (Z segments)
                // must not be used in messages." Counted by the Z*
                // prefix pattern; empty predicate counts every match.
                SegmentCardinalityRule(
                    countedSegmentID: "Z*",
                    scope: .messageWide,
                    minCount: 0,
                    maxCount: 0,
                    predicate: "",
                    applicableWhen: "messageCode in (ORM, ORU, REF)",
                    specCitation: "HL7au:000023.1 — user-defined Z segments must not be used on Senders Orders/Results/Referrals; AU ADRM-2021 Appendix 5 p. 440"
                ),
            ],
            // HL7au:000008 (r2) — Display Segments parent rule (v0.11-S3,
            // ADR-010 Extension 2). AU ADRM-2021 p. 420:
            //   "The message must contain at least one OBX display
            //    segment per OBR/OBX group."
            // Applicable to: Senders Results, Referrals. Message codes
            // ORU and REF (per HL7au:000008 header in Appendix 5;
            // HL7au:000040.4 uses "Referrals, RRI" separately, so
            // "Referrals" alone means REF here). Rule fires when a
            // resolved OBR/OBX group contains zero OBX segments whose
            // OBX-3.3 = AUSPDI. Attached to OBR grammar so it evaluates
            // once per OBR-headed group (the group-scan dedupes via
            // (scope, groupHeadIndex) so multi-OBR-per-ORC groups still
            // fire the correct number of times).
            "OBR": [
                SegmentCardinalityRule(
                    countedSegmentID: "OBX",
                    scope: .obrObxGroup,
                    minCount: 1,
                    predicate: "OBX-3.3 = AUSPDI",
                    applicableWhen: "messageCode in (ORU, REF)",
                    specCitation: "HL7au:000008 (r2) — ≥1 AUSPDI display OBX per OBR/OBX group on Senders Results/Referrals; AU ADRM-2021 p. 420"
                ),
                // M6-B-1 — HL7au:000008.3.1, both legs. Every Referrals
                // profile requires ≥1 display OBX in {HTML, PDF, TXT}
                // per OBR/OBX group (PDF satisfies the disjunction, so
                // this rule is a necessary condition under both legs);
                // Level 1 additionally requires the display to be PDF —
                // enforced since M6-B-6 via the profile the sender
                // declares in MSH-12.3.1 (the L1 rule below).
                SegmentCardinalityRule(
                    countedSegmentID: "OBX",
                    scope: .obrObxGroup,
                    minCount: 1,
                    predicate: "OBX-3.3 = AUSPDI AND OBX-3.1 in (HTML, PDF, TXT)",
                    applicableWhen: "messageCode = REF",
                    specCitation: "HL7au:000008.3.1 — each OBR/OBX group must contain ≥1 display OBX in HTML/PDF/TXT on Senders Referrals; AU ADRM-2021 Appendix 5 p. 423"
                ),
                // The Level-1-specific leg: "For Referrals Level 1: The
                // single OBR/OBX group of the message must contain an
                // OBX display segment in PDF format." Gated on the L1
                // profile ID in MSH-12.3.1 (cross-segment via the
                // previousSegment position atom — MSH always precedes
                // the OBR anchor).
                SegmentCardinalityRule(
                    countedSegmentID: "OBX",
                    scope: .obrObxGroup,
                    minCount: 1,
                    predicate: "OBX-3.3 = AUSPDI AND OBX-3.1 = PDF",
                    applicableWhen: "messageCode = REF AND previousSegment(MSH).MSH-12.3.1 = HL7AU-OO-REF-SIMPLIFIED-201706-L1",
                    specCitation: "HL7au:000008.3.1 — on Referrals Level 1 (MSH-12.3.1 = HL7AU-OO-REF-SIMPLIFIED-201706-L1) the OBR/OBX group must contain a PDF display OBX; AU ADRM-2021 Appendix 5 p. 423"
                )
            ]
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
    /// - `.N` "If alternate identifier set, alternate coding system must be set"
    /// - `.N+1` "If alternate identifier not set, alternate coding system must not be set"
    ///
    /// ADRM-2021 Appendix 5 numbers the alternate-identifier pair only
    /// consistently for two of the three composites: **CE uses `.5` /
    /// `.6`; CNE and CWE both use `.4` / `.5`.** Getting CNE wrong cites
    /// `HL7au:00044.5.6`, which revision r2 **removed** — corrected by
    /// M6-D1 (2026-09-04), found by the Appendix 5 diff. See
    /// `docs/design/m6-adrm-2021-localisation-audit.md`.
    private static func ceCwePairRules(citePrefix: String) -> [PairConditional] {
        let altBase = citePrefix == "HL7au:00044.4" ? 5 : 4
        let altCite: (Int) -> String = { offset in "\(citePrefix).\(altBase + offset)" }
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
                specCitation: "\(altCite(0)) — alt identifier set ⇒ alt coding system set"
            ),
            PairConditional(
                ifComponent: 4, condition: .empty,
                thenComponent: 6, requirement: .mustBeEmpty,
                specCitation: "\(altCite(1)) — alt identifier empty ⇒ alt coding system empty"
            ),
        ]
    }
}
