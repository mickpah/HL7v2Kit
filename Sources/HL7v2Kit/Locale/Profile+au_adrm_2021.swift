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
            // M32 — the wire-decidable half of the NASH/SMD addressing
            // family, on the two fields the ADRM's own grouper names:
            // "(HL7au:00044.2) HD Datatype conformance points for MSH-4,
            // and MSH-6". Every point in the family is gated "when using
            // SMD with NASH certificates", a transport fact absent from
            // the wire, so ValidationOptions.auNASHTransport carries it.
            //
            //   .2.2 — "the HD Universal ID component must contain the
            //          HPI-O formatted as "1.2.36.1.2001.1003.0."
            //          concatenated with the HPI-O". The HPI-O's width
            //          comes from HL7au:000043.1, which spells MSH-4 out
            //          in full: "...^1.2.36.1.2001.1003.0.<hpio>^ISO"
            //          where <hpio> is a 16-digit number.
            //   .2.3 — "the HD Universal ID Type component must be ISO".
            //
            // Siblings deliberately NOT shipped: .2.1 and 00044.3.2 name
            // the organisation name "as registered in the Medicare
            // Australia HPOS/HI service" (needs the directory); .2.4 and
            // the second .3.4 compare against a vendor X.509 certificate;
            // 00043.2 is an anti-spoofing check the ADRM marks "applies
            // only to SMD Agent implementers ... before handing off a the
            // message to the receiving system". The EI twins (00044.3.3 /
            // .3.4) are registered pending a scope pass: EI carries
            // identifiers echoed from other organisations, whose HPI-O is
            // not the sender's, so a datatype-wide rule would over-fire.
            FieldOverride(
                segmentID: "MSH",
                fieldIndex: 4,
                componentValueSets: [
                    ComponentValueSet(
                        component: 3,
                        allowedValues: ["ISO"],
                        condition: "auNASHTransport populated",
                        specCitation: "HL7au:00044.2.3 (r2) — when using SMD with NASH certificates the HD Universal ID Type component must be \"ISO\". Applied on the caller's NASH-transport assertion."
                    ),
                ],
                componentPatterns: [
                    ComponentPattern(
                        component: 2,
                        prefix: "1.2.36.1.2001.1003.0.",
                        digitsAfterPrefix: 16,
                        condition: "auNASHTransport populated",
                        specCitation: "HL7au:00044.2.2 (r2) — when using SMD with NASH certificates the HD Universal ID component must contain the HPI-O formatted as \"1.2.36.1.2001.1003.0.\" concatenated with the HPI-O; the HPI-O is a 16-digit number (HL7au:000043.1). Applied on the caller's NASH-transport assertion."
                    ),
                ],
                specCitation: "HL7au:00044.2 — HD datatype conformance points for MSH-4 and MSH-6 (caller-asserted NASH transport)"
            ),
            FieldOverride(
                segmentID: "MSH",
                fieldIndex: 6,
                componentValueSets: [
                    ComponentValueSet(
                        component: 3,
                        allowedValues: ["ISO"],
                        condition: "auNASHTransport populated",
                        specCitation: "HL7au:00044.2.3 (r2) — when using SMD with NASH certificates the HD Universal ID Type component must be \"ISO\". Applied on the caller's NASH-transport assertion."
                    ),
                ],
                componentPatterns: [
                    ComponentPattern(
                        component: 2,
                        prefix: "1.2.36.1.2001.1003.0.",
                        digitsAfterPrefix: 16,
                        condition: "auNASHTransport populated",
                        specCitation: "HL7au:00044.2.2 (r2) — when using SMD with NASH certificates the HD Universal ID component must contain the HPI-O formatted as \"1.2.36.1.2001.1003.0.\" concatenated with the HPI-O; the HPI-O is a 16-digit number (HL7au:000043.1). Applied on the caller's NASH-transport assertion."
                    ),
                ],
                specCitation: "HL7au:00044.2 — HD datatype conformance points for MSH-4 and MSH-6 (caller-asserted NASH transport)"
            ),
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
                    // M7-P2 / P-5a — chapter 8 pins the acknowledgement
                    // profile in the same component: "MSH-12-3 must be
                    // valued 'HL7AU-OO-ACK-READ-2020006'" for user read
                    // acknowledgements (§8.4) and "... 'HL7AU-OO-ACK-
                    // 201701'" for general acknowledgements (§8.5), both
                    // p. 372. The two sections partition ACK usage and
                    // the flavour is only distinguishable by this value,
                    // so on ACK the component is required and closed
                    // over the pair. Prose-only: Appendix 5 carries no
                    // ACK-scoped MSH-12.3 row.
                    ComponentValueSet(
                        component: 3,
                        subcomponent: 1,
                        allowedValues: [
                            "HL7AU-OO-ACK-201701",
                            "HL7AU-OO-ACK-READ-2020006",
                        ],
                        condition: "messageCode = ACK",
                        specCitation: "ADRM-prose:P-5a — on ACK messages MSH-12.3.1 must be HL7AU-OO-ACK-201701 (general, §8.5) or HL7AU-OO-ACK-READ-2020006 (user read, §8.4); AU ADRM-2021 p. 372"
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
            // the `MSG` CompositeOverride below: the base model requires
            // MSG-1 only from v2.5.1, and v2.4 (the AU version) types
            // MSH-9 as CM with no component optionality.
            FieldOverride(
                segmentID: "MSH",
                fieldIndex: 9,
                condition: "messageCode in (ORM, ORU, REF)",
                requiredComponents: [2, 3],
                componentValueSets: [
                    // M7-P2 / P-3 — §7.3.1.9 (p. 326): "For the patient
                    // referral message this field must be valued as:
                    // REF^I12^REF_I12. For the referral response
                    // indication message this must be valued as
                    // RRI^I12^RRI_I12." Component 1 is the gate itself;
                    // components 2 and 3 pin per message code.
                    ComponentValueSet(
                        component: 2,
                        allowedValues: ["I12"],
                        condition: "messageCode = REF",
                        specCitation: "ADRM-prose:P-3 — MSH-9 on a patient referral must be REF^I12^REF_I12 (§7.3.1.9 p. 326)"
                    ),
                    ComponentValueSet(
                        component: 3,
                        allowedValues: ["REF_I12"],
                        condition: "messageCode = REF",
                        specCitation: "ADRM-prose:P-3 — MSH-9 on a patient referral must be REF^I12^REF_I12 (§7.3.1.9 p. 326)"
                    ),
                    ComponentValueSet(
                        component: 2,
                        allowedValues: ["I12"],
                        condition: "messageCode = RRI",
                        specCitation: "ADRM-prose:P-3 — MSH-9 on a referral response must be RRI^I12^RRI_I12 (§7.3.1.9 p. 326)"
                    ),
                    ComponentValueSet(
                        component: 3,
                        allowedValues: ["RRI_I12"],
                        condition: "messageCode = RRI",
                        specCitation: "ADRM-prose:P-3 — MSH-9 on a referral response must be RRI^I12^RRI_I12 (§7.3.1.9 p. 326)"
                    ),
                ],
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
            // ---- M7-P2: prose-sweep findings ----------------------
            // These carry no HL7au identifier — Appendix 5 has no row
            // for them. Each is quoted verbatim from chapter prose in
            // `docs/design/m7-adrm-prose-sweep.md`, cited as
            // "ADRM-prose:P-n" with the section and printed page.
            //
            // P-1 — "PID-1 is mandatory in the Australian context.
            // Variance to HL7 International." (PID attribute-table
            // footnote †††, p. 61). Base v2.4 has PID-1 optional.
            // Gated to the message types the guide carries PID in
            // (Orders, Results, Referrals, Referral Response — the RRI
            // echoes the REF's PID per §7.1, p. 325).
            FieldOverride(
                segmentID: "PID",
                fieldIndex: 1,
                profileUsage: .required,
                condition: "messageCode in (ORM, ORU, REF, RRI)",
                specCitation: "ADRM-prose:P-1 — PID-1 (Set ID) is mandatory in the Australian context (variance to HL7 International); AU ADRM-2021 p. 61"
            ),
            // P-5b — read acknowledgements: "Valid formats for the user
            // details in MSH-3 (Sending Application) are:
            // Username^<Medicare Australia provider number>^AUSHICPR
            // [or] Username^<HPI-I>@<HPI-O>^NPIO" (§8.4, p. 372). The
            // decidable component is MSH-3.3 (the scheme); the ID
            // formats themselves are content patterns and stay in the
            // sweep register. Gated on the read-ack profile ID the
            // message itself declares.
            FieldOverride(
                segmentID: "MSH",
                fieldIndex: 3,
                componentValueSets: [
                    ComponentValueSet(
                        component: 3,
                        allowedValues: ["AUSHICPR", "NPIO"],
                        condition: "messageCode = ACK AND MSH-12.3.1 = HL7AU-OO-ACK-READ-2020006",
                        specCitation: "ADRM-prose:P-5b — on user read acknowledgements MSH-3.3 must be AUSHICPR or NPIO (§8.4 p. 372)"
                    )
                ],
                specCitation: "ADRM-prose:P-5b — read-acknowledgement MSH-3 user-detail scheme"
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
            // ADRM-prose:P-11 (P4-27) — ADRM-2021 §4.4.1.26, p. 228: "Not
            // used in Australian messages. Use observation Sub-ID in OBX-4
            // to link results." Unconditional, no Appendix 5 HL7au ID.
            // OBR-26 carries no base condition (v2.4/OBR.json: optionality
            // O, no `condition`), so unlike OBR-29 there is no conflicting
            // requirement elsewhere in the spec that forces this field to
            // be valued — see task-P4-27-report.md for the OBR-29 check.
            // Scope: OBR appears in the ORM, ORU and REF structures alike
            // (ADRM ch. 4 "Observation Reporting" is OBR's home chapter;
            // ch. 5 "Observation Ordering" and ch. 7 "Patient Referral"
            // both use the same OBR without redefining this field).
            FieldOverride(
                segmentID: "OBR",
                fieldIndex: 26,
                prohibitions: [
                    ProfileFieldProhibition(
                        condition: "messageCode in (ORM, ORU, REF)",
                        severity: .error,
                        specCitation: "ADRM-prose:P-11 — OBR-26 (Parent Result) must not be valued in Australian messages; use the OBX-4 Sub-ID to link results instead; AU ADRM-2021 §4.4.1.26 p. 228"
                    ),
                ],
                specCitation: "ADRM-prose:P-11 — OBR-26 not used in Australia"
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
            // ADRM-prose:P-12 (P4-27) — ADRM-2021 §7.3.11.24, p. 343:
            // "This field should not be used. Use ORC-22 for the address
            // of the prescriber's facility." Unconditional, no Appendix 5
            // HL7au ID. Base v2.4 CH04 §4.5.1.24 has no such note (ADRM
            // ch. 5 §5.4.1.24, the Observation Ordering/ORM leg, is
            // likewise plain), so the prohibition is AU-specific and
            // scoped to Referrals only — ch. 7 "Patient Referral" is
            // where the sentence appears. No base condition exists on
            // ORC-24 (v2.4/ORC.json: optionality O, no `condition`), so
            // there is no conflicting requirement forcing it to be
            // valued. Modal verb "should" — warning, not error.
            FieldOverride(
                segmentID: "ORC",
                fieldIndex: 24,
                prohibitions: [
                    ProfileFieldProhibition(
                        condition: "messageCode = REF",
                        severity: .warning,
                        specCitation: "ADRM-prose:P-12 — ORC-24 (Ordering Provider Address) should not be used in Referrals; use ORC-22 for the prescriber's facility address instead; AU ADRM-2021 §7.3.11.24 p. 343"
                    ),
                ],
                specCitation: "ADRM-prose:P-12 — ORC-24 should not be used in Referrals"
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
                // M6-B-9 — HL7au:000034.1/.2: on OBX-3, when both a
                // public and a local terminology are transmitted, the
                // public code must be the PRIMARY triplet (1-3) and the
                // local the alternate (4-6). Encoded as: a public
                // coding system in the ALTERNATE slot (key CE-6)
                // requires the primary slot (CE-3) to be public too.
                // Public set = the systems the ADRM names (LN,
                // SNOMED CT-AU as SCT, UCUM); others skip — PARTIAL.
                componentCorrespondences: [
                    ComponentCorrespondence(
                        keyComponent: 6,
                        valueComponent: 3,
                        map: HL7CodeTables.publicInAlternateMap,
                        condition: "messageCode in (ORU, REF)",
                        specCitation: "HL7au:000034.1/.2 — when both public and local terminology are transmitted in OBX-3, the public code must be primary and the local the alternate; AU ADRM-2021 Appendix 5 pp. 441-442"
                    ),
                ],
                specCitation: "HL7au:000008.1 (r2) — OBX-3 display-format identifier value set on AUSPDI display segments"
            ),
            // M6-B-9 — HL7au:000034.1's OBX-5 leg (the point names
            // "either OBX-3 ... or as an Observation Value").
            FieldOverride(
                segmentID: "OBX",
                fieldIndex: 5,
                componentValueSets: [
                    // M7-P4 / ADRM-prose:P-6 — the VMR header OBX
                    // (Appendix 9, p. 490): "OBX-5 must be valued as
                    // 'HL7V2-VMR.v1^HL7V2 VMR&99A-9AAC5A649D18B6F2&L^
                    // TX^Octet-stream'" — the full RP literal, pinned
                    // per component/subcomponent like the 000040.3
                    // literal pins. Gated on the header's own OBX-3
                    // discriminator (74028-2, Report template ID).
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["HL7V2-VMR.v1"],
                        condition: "messageCode = REF AND OBX-3.1 = 74028-2",
                        specCitation: "ADRM-prose:P-6 — VMR header OBX-5.1 (pointer) must be \"HL7V2-VMR.v1\"; AU ADRM-2021 Appendix 9 p. 490"
                    ),
                    ComponentValueSet(
                        component: 2,
                        subcomponent: 1,
                        allowedValues: ["HL7V2 VMR"],
                        condition: "messageCode = REF AND OBX-3.1 = 74028-2",
                        specCitation: "ADRM-prose:P-6 — VMR header OBX-5.2.1 (application namespace) must be \"HL7V2 VMR\"; AU ADRM-2021 Appendix 9 p. 490"
                    ),
                    ComponentValueSet(
                        component: 2,
                        subcomponent: 2,
                        allowedValues: ["99A-9AAC5A649D18B6F2"],
                        condition: "messageCode = REF AND OBX-3.1 = 74028-2",
                        specCitation: "ADRM-prose:P-6 — VMR header OBX-5.2.2 (universal ID) must be \"99A-9AAC5A649D18B6F2\"; AU ADRM-2021 Appendix 9 p. 490"
                    ),
                    ComponentValueSet(
                        component: 2,
                        subcomponent: 3,
                        allowedValues: ["L"],
                        condition: "messageCode = REF AND OBX-3.1 = 74028-2",
                        specCitation: "ADRM-prose:P-6 — VMR header OBX-5.2.3 (universal ID type) must be \"L\"; AU ADRM-2021 Appendix 9 p. 490"
                    ),
                    ComponentValueSet(
                        component: 3,
                        allowedValues: ["TX"],
                        condition: "messageCode = REF AND OBX-3.1 = 74028-2",
                        specCitation: "ADRM-prose:P-6 — VMR header OBX-5.3 (type of data) must be \"TX\"; AU ADRM-2021 Appendix 9 p. 490"
                    ),
                    ComponentValueSet(
                        component: 4,
                        allowedValues: ["Octet-stream"],
                        condition: "messageCode = REF AND OBX-3.1 = 74028-2",
                        specCitation: "ADRM-prose:P-6 — VMR header OBX-5.4 (data subtype) must be \"Octet-stream\"; AU ADRM-2021 Appendix 9 p. 490"
                    ),
                ],
                componentCorrespondences: [
                    ComponentCorrespondence(
                        keyComponent: 6,
                        valueComponent: 3,
                        map: HL7CodeTables.publicInAlternateMap,
                        condition: "messageCode in (ORU, REF)",
                        specCitation: "HL7au:000034.1 — when both public and local terminology are transmitted in a coded Observation Value, the public code must be primary; AU ADRM-2021 Appendix 5 p. 441"
                    ),
                ],
                // P4-24 — HL7au:00060.4 route B. OBX-5 is C (v2.4 and the
                // ADRM OBX attribute table, p. 235). HL7 v2.4 §7.4.2.11: "An
                // OBX used for a dynamic specification must contain the
                // detailed examination code, units, etc., with OBX-11 valued
                // with O, and OBX-2 and OBX-5 valued with null." The HL7 null
                // ("") is therefore permitted; any other value is not.
                prohibitions: [
                    ProfileFieldProhibition(
                        condition: "messageCode in (ORM, ORU, REF) AND OBX-11 = O",
                        severity: .error,
                        specCitation: "HL7au:00060.4 — OBX-5 (C) must not be valued when OBX-11 = O (dynamic specification: \"OBX-2 and OBX-5 valued with null\"); HL7 v2.4 §7.4.2.11, AU ADRM-2021 Appendix 5 p. 466"
                    ),
                ],
                specCitation: "HL7au:000034.1 — public-before-local coding-system precedence on coded OBX-5 values"
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
                    // M6-B-4 — HL7au:00104.7.3.1: "<other qualifying
                    // info (ST)> must be a valued from HL7 Table 0203 -
                    // Identifier Type." (00104.7.2.1's 0363 membership
                    // was withdrawn at M6-B-8: table 0363 is
                    // user-defined and the ADRM's own PRD-7 matches
                    // table uses vendor authorities outside it —
                    // registered, see permanent-limitations-register.)
                    ComponentValueSet(
                        component: 3,
                        allowedValues: HL7CodeTables.table0203,
                        condition: "messageCode = REF",
                        specCitation: "HL7au:00104.7.3.1 — PRD-7.3 (other qualifying info) must be valued from HL7 Table 0203 (Identifier Type) on Senders Referrals; AU ADRM-2021 Appendix 5 p. 472, table p. 301"
                    ),
                ],
                // M6-B-8 — HL7au:00104.7.1.4: "the correct matching
                // <type of ID number> and <other qualifying info> must
                // be used as per Table 7.3.3.7.1" (p. 334). The table
                // states pairs for the closed AU authorities; vendor
                // authorities are open-ended examples and skip.
                componentCorrespondences: [
                    ComponentCorrespondence(
                        keyComponent: 2,
                        valueComponent: 3,
                        map: [
                            "aushicpr": ["UPIN"],
                            "aushic": ["NPIO", "NOI"],
                        ],
                        condition: "messageCode = REF",
                        specCitation: "HL7au:00104.7.1.4 — PRD-7 authority => qualifying-info pairs per Table 7.3.3.7.1 (AUSHICPR => UPIN, AUSHIC => NPIO/NOI); AU ADRM-2021 p. 334 (vendor authorities are open-ended and skip)"
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
            // M6-B-8 — HL7au:000008.1.3: "the OBX-2 Value Type field
            // must match its corresponding display format specified in
            // OBX-3 Identifier" per the Display Format codes table
            // (p. 247): RTF/HTML/PDF => ED, TXT/PIT => FT. Five gated
            // value sets — OBX-3 does not repeat, so the gate reads a
            // stable value. Scoped Results per Appendix 5.
            // M29 — HL7au:00050.1.5: OBX-6.3 (Units coding system) must be
            // UCUM, scoped "Senders (Pathology only)", Results (Appendix 5
            // p. 465). The sender's discipline is not on the wire; the
            // caller asserts it through ValidationOptions.auPathologySender,
            // and the gate reads that assertion as a message-context noun.
            // Populated-only, like every component value set: an OBX with
            // no units, or units with no coding system, is presence's job.
            FieldOverride(
                segmentID: "OBX",
                fieldIndex: 6,
                componentValueSets: [
                    ComponentValueSet(
                        component: 3,
                        allowedValues: ["UCUM"],
                        condition: "messageCode = ORU AND auPathologySender populated",
                        specCitation: "HL7au:00050.1.5 — the OBX-6 (Units) name of coding system component must be UCUM; Senders (Pathology only), Results; AU ADRM-2021 Appendix 5 p. 465. Applied on the caller's pathology-sender assertion."
                    ),
                ],
                specCitation: "HL7au:00050.1.5 — OBX-6 units coding system on pathology Results (caller-asserted)"
            ),
            FieldOverride(
                segmentID: "OBX",
                fieldIndex: 2,
                componentValueSets: [
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["ED"],
                        condition: "messageCode = ORU AND OBX-3.3 = AUSPDI AND OBX-3.1 = RTF",
                        specCitation: "HL7au:000008.1.3 — an RTF display segment's OBX-2 must be ED; AU ADRM-2021 Display Format codes p. 247"
                    ),
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["ED"],
                        condition: "messageCode = ORU AND OBX-3.3 = AUSPDI AND OBX-3.1 = HTML",
                        specCitation: "HL7au:000008.1.3 — an HTML display segment's OBX-2 must be ED; AU ADRM-2021 Display Format codes p. 247"
                    ),
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["ED"],
                        condition: "messageCode = ORU AND OBX-3.3 = AUSPDI AND OBX-3.1 = PDF",
                        specCitation: "HL7au:000008.1.3 — a PDF display segment's OBX-2 must be ED; AU ADRM-2021 Display Format codes p. 247"
                    ),
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["FT"],
                        condition: "messageCode = ORU AND OBX-3.3 = AUSPDI AND OBX-3.1 = TXT",
                        specCitation: "HL7au:000008.1.3 — a TXT display segment's OBX-2 must be FT; AU ADRM-2021 Display Format codes p. 247"
                    ),
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["FT"],
                        condition: "messageCode = ORU AND OBX-3.3 = AUSPDI AND OBX-3.1 = PIT",
                        specCitation: "HL7au:000008.1.3 — a PIT display segment's OBX-2 must be FT; AU ADRM-2021 Display Format codes p. 247"
                    ),
                    // M7-P4 / ADRM-prose:P-6 — the VMR header OBX
                    // (Appendix 9, p. 490): "This header OBX must have
                    // a OBX-2 Datatype field value of 'RP'". The header
                    // is identified by its own OBX-3 discriminator
                    // ("OBX-3 field must have the value
                    // 74028-2^Report template ID^LN").
                    ComponentValueSet(
                        component: 1,
                        allowedValues: ["RP"],
                        condition: "messageCode = REF AND OBX-3.1 = 74028-2",
                        specCitation: "ADRM-prose:P-6 — the VMR header OBX (OBX-3.1 = 74028-2) must have OBX-2 = RP; AU ADRM-2021 Appendix 9 p. 490"
                    ),
                ],
                // P4-24 — HL7au:00060.4 route B. OBX-2 is C (v2.4 and the
                // ADRM OBX attribute table, p. 235). HL7 v2.4 §7.4.2.11: "An
                // OBX used for a dynamic specification must contain the
                // detailed examination code, units, etc., with OBX-11 valued
                // with O, and OBX-2 and OBX-5 valued with null." The HL7 null
                // ("") is therefore permitted; any other value is not.
                prohibitions: [
                    ProfileFieldProhibition(
                        condition: "messageCode in (ORM, ORU, REF) AND OBX-11 = O",
                        severity: .error,
                        specCitation: "HL7au:00060.4 — OBX-2 (C) must not be valued when OBX-11 = O (dynamic specification: \"OBX-2 and OBX-5 valued with null\"); HL7 v2.4 §7.4.2.11, AU ADRM-2021 Appendix 5 p. 466"
                    ),
                ],
                specCitation: "HL7au:000008.1.3 — OBX-2 must match the OBX-3.1 display format per the Display Format codes table; AU ADRM-2021 p. 247"
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
            // MSG datatype (MSH-9 only) — HL7au:00049.1: "MSH-9 Message
            // type <message type (ID)> component must be valued."
            // Ungated: a `messageStructure`/`triggerEvent` scope (Orders,
            // Results, Referrals) was expressible but not chosen — ACK
            // reuses trigger events across message families, so it would
            // not distinguish an in-scope ACK from an out-of-scope one,
            // and the rule only ever catches a non-conformant message
            // (MSH-9.1 empty) regardless, so a narrower gate buys nothing.
            // `yieldsToBase`: v2.5.1 and later already require MSG.1 in
            // the base model; this restatement fires only where the
            // grammar version does not (v2.3, v2.3.1, v2.4). P3-4.
            CompositeOverride(
                dataType: "MSG",
                requiredComponents: [
                    ComponentRequirement(
                        component: 1,
                        specCitation: "HL7au:00049.1 — MSH-9 message type (MSG-1) must be valued (ADRM 2021 Appendix 5)",
                        yieldsToBase: true
                    )
                ]
            ),
            // CX datatype — HL7au:00044.1 series: 44.1.1 (CX-1 must be
            // specified), 44.1.2 (CX-4 assigning authority) and 44.1.3
            // (CX-5 identifier type code), each required when CX is
            // populated. 44.1.1 is `yieldsToBase`: CX.1 is R in the base
            // model from v2.5.1, but v2.4 CX (the AU base) carries no
            // component optionality, so the profile must state it for
            // v2.3/v2.3.1/v2.4 traffic (P3 fix wave). Its "valid according
            // to the identifier scheme" half needs identifier-scheme
            // recognition and is not checked.
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
                        component: 1,
                        specCitation: "HL7au:00044.1.1 — CX-1 ID number must be specified",
                        yieldsToBase: true
                    ),
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
            // .7.1 (XCN-1 must be specified): no modelled version requires
            // XCN.1 (O on v2.5.1/v2.6, C on v2.8.2, no optionality on
            // v2.3-v2.4), so the profile states it outright. Its "valid
            // according to the identifier scheme" half needs
            // identifier-scheme recognition and is not checked. P3 fix
            // wave (absorbs P4-19). On v2.8.2, with XCN.1 and XCN.2 both
            // empty, XCN.1's absence is reported twice: here under
            // HL7au:00044.7.1, and by the base condition for XCN.1
            // (conditionalComponentMissing; "XCN.1 is required if XCN.2 is
            // not populated", conditions.json "2 empty"). The empty family
            // name is reported separately, by XCN.2's own base condition
            // ("1 empty") and by HL7au:00044.7.5. Every one is violated, so
            // all are reported by design, as for EI-1 below.
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
                        component: 1,
                        specCitation: "HL7au:00044.7.1 — XCN-1 ID number must be specified"
                    ),
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
            // M6-B-7 — the ED/RP series (HL7au:00044.10 / .11), reachable
            // since the composite dispatch resolves OBX-5's effective
            // datatype from OBX-2. Components per the v2.4 definitions:
            // ED = source app (1) ^ type of data (2) ^ subtype (3) ^
            // encoding (4) ^ data (5); RP = pointer (1) ^ application
            // ID (2) ^ type of data (3) ^ subtype (4). Scoped
            // "Results, Referrals" per Appendix 5.
            CompositeOverride(
                dataType: "ED",
                condition: "messageCode in (ORU, REF)",
                requiredComponents: [
                    ComponentRequirement(
                        component: 2,
                        specCitation: "HL7au:00044.10.1.1 — ED <type of data> must be valued"
                    ),
                    ComponentRequirement(
                        component: 3,
                        specCitation: "HL7au:00044.10.1.2 — ED <data subtype> must be valued"
                    ),
                    ComponentRequirement(
                        component: 4,
                        specCitation: "HL7au:00044.10.1.3 — ED <encoding> must be valued"
                    ),
                    ComponentRequirement(
                        component: 5,
                        specCitation: "HL7au:00044.10.1.4 — ED <data> must be valued"
                    ),
                ],
                // M6-B-8 — HL7au:00044.10.1.5/.6: the subtype in ED-3
                // determines ED-2's type. Keys are the pairs the spec
                // STATES (ADRM §3.20.5 type-subtype combinations; the
                // 0291 extension rows' own MIME annotations; the §4.5
                // display examples). Unstated subtypes skip: PARTIAL —
                // the IANA MIME registry is external and unbounded.
                componentCorrespondences: [
                    ComponentCorrespondence(
                        keyComponent: 3,
                        valueComponent: 2,
                        map: HL7CodeTables.subtypeToTypeMap,
                        specCitation: "HL7au:00044.10.1.5/.6 — ED subtype => type of data correspondence (MIME and HL7 Table 0291 => 0191); AU ADRM-2021 §3.20 pp. 167-171, §4.5 examples"
                    ),
                ]
            ),
            // M6-B-9 — HL7au:00044.8.1: "Correct timezone must be
            // specified." The TS format conditions the offset on time
            // being transmitted ("If a precision of Hour or greater is
            // used a time zone should be specified", §3.26), so the rule
            // fires on hour-plus values without +/-ZZZZ. PARTIAL: offset
            // presence is checkable, offset CORRECTNESS is not.
            CompositeOverride(
                dataType: "TS",
                condition: "messageCode in (ORM, ORU, REF)",
                timezoneRequiredCitation: "HL7au:00044.8.1 — a TS with hour-or-greater precision must specify the timezone offset on Senders Orders/Results/Referrals; AU ADRM-2021 §3.26 p. 183"
            ),
            CompositeOverride(
                dataType: "RP",
                condition: "messageCode in (ORU, REF)",
                requiredComponents: [
                    ComponentRequirement(
                        component: 1,
                        specCitation: "HL7au:00044.11.1.1 — RP <pointer> must be valued"
                    ),
                    ComponentRequirement(
                        component: 2,
                        specCitation: "HL7au:00044.11.1.2 — RP <application ID> must be valued"
                    ),
                    ComponentRequirement(
                        component: 3,
                        specCitation: "HL7au:00044.11.1.3 — RP <type of data> must be valued"
                    ),
                    ComponentRequirement(
                        component: 4,
                        specCitation: "HL7au:00044.11.1.4 — RP <subtype> must be valued"
                    ),
                ],
                // M6-B-8 — HL7au:00044.11.1.5/.6: same correspondence,
                // RP's subtype is component 4 and its type component 3.
                componentCorrespondences: [
                    ComponentCorrespondence(
                        keyComponent: 4,
                        valueComponent: 3,
                        map: HL7CodeTables.subtypeToTypeMap,
                        specCitation: "HL7au:00044.11.1.5/.6 — RP subtype => type of data correspondence (MIME and HL7 Table 0291 => 0191); AU ADRM-2021 §3.20 pp. 167-171"
                    ),
                ]
            ),
            // M33 — the EI twins of what M32 shipped for HD, under the same
            // NASH assertion. The ADRM's grouper reads "(HL7au:00044.3) EI
            // datatype conformance points" with no field list, so the rules
            // are datatype-wide; on the AU profile that reaches ORC-2/-3/-4
            // and OBR-2/-3, the five EI fields HL7au:000006 / 000007 already
            // require complete.
            //
            //   .3.4 — "the EI Universal ID component must contain the HPI-O
            //          formatted as "1.2.36.1.2001.1003.0." concatenated
            //          with the HPI-O". The sentence constrains the SHAPE,
            //          not whose HPI-O it is: an identifier echoed from
            //          another organisation carries that organisation's
            //          HPI-O and satisfies it unchanged.
            //   .3.3 — "the EI Universal ID Type component must be ISO".
            //
            // `allowEmpty` on the pattern because the completeness rules
            // above already report a missing EI-3; without it one defect
            // would be reported twice. The value-set track is populated-only
            // already. HL7au:00044.3.2 (the HPOS/HI registered organisation
            // name) still needs the directory and stays out.
            //
            //   .3.1 — "the EI Entity identifier component must be valued".
            //          No modelled version requires EI.1 (O on v2.5.1+, no
            //          optionality on v2.3-v2.4), so the profile states it
            //          outright; on the five fields above it coincides with
            //          the field-level completeness point, and both are
            //          reported because both are violated. The "unique within
            //          the sender facility namespace" half is cross-message
            //          and not checked. P3 fix wave (absorbs P4-19).
            CompositeOverride(
                dataType: "EI",
                // The 00044.3 series is scoped "Orders, Results, Referrals".
                condition: "messageCode in (ORM, ORU, REF)",
                requiredComponents: [
                    ComponentRequirement(
                        component: 1,
                        specCitation: "HL7au:00044.3.1 (r2) — EI-1 entity identifier must be valued"
                    ),
                ],
                componentValueSets: [
                    ComponentValueSet(
                        component: 4,
                        allowedValues: ["ISO"],
                        condition: "auNASHTransport populated",
                        specCitation: "HL7au:00044.3.3 (r2) — when using SMD with NASH certificates the EI Universal ID Type component must be \"ISO\". Applied on the caller's NASH-transport assertion."
                    ),
                ],
                componentPatterns: [
                    ComponentPattern(
                        component: 3,
                        prefix: "1.2.36.1.2001.1003.0.",
                        digitsAfterPrefix: 16,
                        condition: "auNASHTransport populated",
                        allowEmpty: true,
                        specCitation: "HL7au:00044.3.4 (r2) — when using SMD with NASH certificates the EI Universal ID component must contain the HPI-O formatted as \"1.2.36.1.2001.1003.0.\" concatenated with the HPI-O; the HPI-O is a 16-digit number (HL7au:000043.1). Applied on the caller's NASH-transport assertion."
                    ),
                ]
            ),
            CompositeOverride(
                dataType: "CE",
                // M6-D4: HL7au:00044.4 series is scoped to
                // "Orders, Results, Referrals".
                condition: "messageCode in (ORM, ORU, REF)",
                requiredComponents: [
                    // M30 — HL7au:00044.4.3: CE-2 <text> "must be valued as
                    // what is intended for display to the user. (In some
                    // locations user display is not intended and the text
                    // may be blank.)" The locations are not on the wire;
                    // the caller asserts display is intended through
                    // ValidationOptions.auDisplayIntended. Unlike the CNE
                    // and CWE text rules (44.5.3, 44.6.3), which carry no
                    // carve-out and ship unconditionally.
                    ComponentRequirement(
                        component: 2,
                        specCitation: "HL7au:00044.4.3 — CE <text> component must be valued as what is intended for display to the user; applied on the caller's display-intended assertion (the ADRM exempts locations where display is not intended)",
                        condition: "auDisplayIntended populated"
                    ),
                ],
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
                // M7-P2 / P-2 — §7.4.2 "Disallowed segments" (p. 363):
                // "The following segments … must not be used by
                // senders": ACC, AUT, CTD, DRG, DSC, DSP, GT1, IN2,
                // NTE, PR1. Prose-only — Appendix 5 has no row. NTE is
                // already prohibited by HL7au:000023 above (wider
                // scope), so the remaining nine ship here, gated to
                // referral messages (§7.4.2 is chapter 7, REF).
                SegmentCardinalityRule(
                    countedSegmentID: "ACC",
                    scope: .messageWide,
                    minCount: 0,
                    maxCount: 0,
                    predicate: "",
                    applicableWhen: "messageCode = REF",
                    specCitation: "ADRM-prose:P-2 — the ACC segment must not be used by senders in referral messages; AU ADRM-2021 §7.4.2 p. 363"
                ),
                SegmentCardinalityRule(
                    countedSegmentID: "AUT",
                    scope: .messageWide,
                    minCount: 0,
                    maxCount: 0,
                    predicate: "",
                    applicableWhen: "messageCode = REF",
                    specCitation: "ADRM-prose:P-2 — the AUT segment must not be used by senders in referral messages; AU ADRM-2021 §7.4.2 p. 363"
                ),
                SegmentCardinalityRule(
                    countedSegmentID: "CTD",
                    scope: .messageWide,
                    minCount: 0,
                    maxCount: 0,
                    predicate: "",
                    applicableWhen: "messageCode = REF",
                    specCitation: "ADRM-prose:P-2 — the CTD segment must not be used by senders in referral messages; AU ADRM-2021 §7.4.2 p. 363"
                ),
                SegmentCardinalityRule(
                    countedSegmentID: "DRG",
                    scope: .messageWide,
                    minCount: 0,
                    maxCount: 0,
                    predicate: "",
                    applicableWhen: "messageCode = REF",
                    specCitation: "ADRM-prose:P-2 — the DRG segment must not be used by senders in referral messages; AU ADRM-2021 §7.4.2 p. 363"
                ),
                SegmentCardinalityRule(
                    countedSegmentID: "DSC",
                    scope: .messageWide,
                    minCount: 0,
                    maxCount: 0,
                    predicate: "",
                    applicableWhen: "messageCode = REF",
                    specCitation: "ADRM-prose:P-2 — the DSC segment must not be used by senders in referral messages; AU ADRM-2021 §7.4.2 p. 363"
                ),
                SegmentCardinalityRule(
                    countedSegmentID: "DSP",
                    scope: .messageWide,
                    minCount: 0,
                    maxCount: 0,
                    predicate: "",
                    applicableWhen: "messageCode = REF",
                    specCitation: "ADRM-prose:P-2 — the DSP segment must not be used by senders in referral messages; AU ADRM-2021 §7.4.2 p. 363"
                ),
                SegmentCardinalityRule(
                    countedSegmentID: "GT1",
                    scope: .messageWide,
                    minCount: 0,
                    maxCount: 0,
                    predicate: "",
                    applicableWhen: "messageCode = REF",
                    specCitation: "ADRM-prose:P-2 — the GT1 segment must not be used by senders in referral messages; AU ADRM-2021 §7.4.2 p. 363"
                ),
                SegmentCardinalityRule(
                    countedSegmentID: "IN2",
                    scope: .messageWide,
                    minCount: 0,
                    maxCount: 0,
                    predicate: "",
                    applicableWhen: "messageCode = REF",
                    specCitation: "ADRM-prose:P-2 — the IN2 segment must not be used by senders in referral messages; AU ADRM-2021 §7.4.2 p. 363"
                ),
                SegmentCardinalityRule(
                    countedSegmentID: "PR1",
                    scope: .messageWide,
                    minCount: 0,
                    maxCount: 0,
                    predicate: "",
                    applicableWhen: "messageCode = REF",
                    specCitation: "ADRM-prose:P-2 — the PR1 segment must not be used by senders in referral messages; AU ADRM-2021 §7.4.2 p. 363"
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
                ),
                // M6-B-9 — HL7au:000008.3.2 (structural half): "If an
                // RTF display segment is sent in an OBR/OBX group, then
                // the same content must be sent in one of either HTML,
                // PDF, or TXT (HL7 FT) same OBR/OBX group." The sibling
                // requirement activates only when an RTF display exists
                // in the group; the "same content" half is a rendered-
                // payload comparison and is not machine-checkable
                // (PARTIAL). Scoped Referrals(L2) via MSH-12.3.1.
                SegmentCardinalityRule(
                    countedSegmentID: "OBX",
                    scope: .obrObxGroup,
                    minCount: 1,
                    activationPredicate: "OBX-3.3 = AUSPDI AND OBX-3.1 = RTF",
                    predicate: "OBX-3.3 = AUSPDI AND OBX-3.1 in (HTML, PDF, TXT)",
                    applicableWhen: "messageCode = REF AND previousSegment(MSH).MSH-12.3.1 = HL7AU-OO-REF-SIMPLIFIED-201706",
                    specCitation: "HL7au:000008.3.2 — an RTF display OBX in an OBR/OBX group requires an HTML/PDF/TXT sibling in the same group on Referrals(L2) (content equality not machine-checkable); AU ADRM-2021 Appendix 5 p. 423"
                )
            ]
        ],
        // M6-B-9 — HL7au:000028 / 000028.2: "the OBR-3 Filler order
        // number must be unique within messages" (Results; Referrals
        // states it per OBR/OBX group, which message-wide uniqueness
        // implies). Key = OBR-3.1 (the entity identifier).
        uniquenessRules: [
            FieldUniquenessRule(
                segmentID: "OBR",
                fieldIndex: 3,
                component: 1,
                applicableWhen: "messageCode = ORU",
                specCitation: "HL7au:000028 — OBR-3 Filler Order Number must be unique within the message on Senders Results; AU ADRM-2021 Appendix 5 p. 442"
            ),
            FieldUniquenessRule(
                segmentID: "OBR",
                fieldIndex: 3,
                component: 1,
                applicableWhen: "messageCode = REF",
                specCitation: "HL7au:000028.2 — each OBR/OBX group's OBR-3 Filler Order Number must be unique in the REF message; AU ADRM-2021 Appendix 5 p. 442"
            ),
        ],
        // M7-P3 / ADRM-prose:P-4 — the §3.1.1.5/.6 escape-sequence
        // prohibitions, variances to HL7 International (p. 136;
        // reiterated p. 159). Chapter 3 datatype variances apply
        // across the guide's message scope, so the gate matches the
        // universal 000040 gate.
        escapeProhibitions: [
            EscapeProhibition(
                lead: "X",
                applicableWhen: "messageCode in (ORM, ORU, REF, RRI, ACK)",
                specCitation: "ADRM-prose:P-4 — the hexadecimal escape sequence (\\Xdddd...\\) must not be used (variance to HL7 International); AU ADRM-2021 §3.1.1.5 p. 136"
            ),
            EscapeProhibition(
                lead: "C",
                applicableWhen: "messageCode in (ORM, ORU, REF, RRI, ACK)",
                specCitation: "ADRM-prose:P-4 — the single-byte character escape sequence (\\Cxxyy\\) must not be used (variance to HL7 International); AU ADRM-2021 §3.1.1.6 p. 136"
            ),
            EscapeProhibition(
                lead: "M",
                applicableWhen: "messageCode in (ORM, ORU, REF, RRI, ACK)",
                specCitation: "ADRM-prose:P-4 — the multi-byte character escape sequence (\\Mxxyyzz\\) must not be used (variance to HL7 International); AU ADRM-2021 §3.1.1.6 p. 136"
            ),
        ],
        // M12 — the HL7v2 VMR sub-ID tree (Appendix 9, Normative). Gate: the
        // same message-type gate as P-6 (the VMR header pins), the referral
        // message in which chapter 7 (p. 362) places VMR content.
        subIDTrees: [
            SubIDTreeRule(
                headerObservationID: "74028-2",
                tableRoot: "1",
                elements: VMRImplementationTable.au_adrm_2021,
                virtualKind: "STRUCTURAL",
                applicableWhen: "messageCode = REF",
                unknownPathCitation: "ADRM-prose:P-8 — \"Observations which are not specified by the HL7v2 VMR must not have a OBX-4 subID sharing the same root\"; AU ADRM-2021 Appendix 9 A9.2.3.4 p. 515 (table A9.T.1 pp. 492-515)",
                virtualRowCitation: "ADRM-prose:P-9 — rows marked STRUCTURAL \"must not be written to OBX segments\"; AU ADRM-2021 Appendix 9 A9.2.3.4 p. 515",
                headerShapeCitation: "ADRM-prose:P-10 — the VMR header must \"specify an OBX-4 sub-ID which must be a dotted decimal value\"; AU ADRM-2021 Appendix 9 A9.2.1 p. 490"
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
