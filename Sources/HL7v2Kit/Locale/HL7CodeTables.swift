// HL7CodeTables.swift
// Internal seed of the HL7 code-table registry (M6-B-4, closing part of
// M6-O6). Each table is the version the AU ADRM-2021 localisation
// PRINTS — that rendering is the normative one for the HL7au points
// that cite it, and it can differ from the base-spec vintage (the
// ADRM's 0203 carries post-v2.4 additions and the AU 0363 values).
//
// (A6b) The four value-set arrays below now READ from the general registry's
// locale axis; the text that follows describes the original M6-B-4 seed.
// This is a SEED, not the general registry M6-O6 asks for: only the
// tables a shipped conformance point consumes are modelled, values
// only (no descriptions), hand-verified against the printed tables.
// Growing it into a per-version, per-locale registry with codegen
// remains the §D capability (permanent-limitations-register.md).

enum HL7CodeTables {
    /// The codes of the AU ADRM-2021 rendering of table `number`. The rows,
    /// with the descriptions the localisation prints, live in
    /// `Resources/tables/locale/au-adrm-2021/` and reach here through the
    /// generated `HL7TableRegistry` (A6b). Codegen emits every file in that
    /// directory, so a missing table is a build-content error, not a
    /// runtime condition: fail loudly rather than hand a profile rule an
    /// empty allowed-value list, which would reject every value.
    private static func auCodes(_ number: String) -> [String] {
        guard let table = HL7TableRegistry.table(number, locale: .auLocalisation) else {
            preconditionFailure("AU ADRM-2021 table \(number) is missing from the generated registry")
        }
        return table.codes
    }

    /// HL7 Table 0074 — Diagnostic Service Section ID, as printed in
    /// AU ADRM-2021 §4.4.1.24 (pp. 225–226). Consumed by
    /// HL7au:000032 / 000032.2 (OBR-24 membership).
    static let table0074: [String] = auCodes("0074")

    /// HL7 Table 0200 — Name Type, as printed in AU ADRM-2021 (p. 62).
    /// Not yet consumed by a shipped rule: XCN-10's HL7au:00044.7.3
    /// stays PARTIAL until the composite-override track grows a
    /// value-set rule (§D).
    static let table0200: [String] = auCodes("0200")

    /// HL7 Table 0203 — Identifier Type, as printed in AU ADRM-2021
    /// (pp. 301–309; the ADRM prints a post-v2.4 vintage). Consumed by
    /// HL7au:00104.7.3.1 (PRD-7.3 membership).
    /// `UPIN` and `NOI` ARE printed there, as `UPIN*` and `NOI**` with
    /// footnotes (p. 309: UPIN "must be used for Australian Medicare
    /// Provider numbers"; NOI is accepted for HL7 v2.9). The M6-B-8 seed
    /// recorded them as accommodations absent from the printed table; the
    /// footnote markers had hidden them from that transcription.
    static let table0203: [String] = auCodes("0203")

    /// User-defined Table 0363 — Assigning Authority, the AU-defined
    /// value set printed in AU ADRM-2021 (p. 310). NOT consumed by a
    /// membership rule: the table is user-defined and the ADRM's own
    /// PRD-7 matches table (p. 334) uses vendor authorities outside it
    /// (`Medical-Objects`, `Argus`), so a closed-set check would
    /// misfire (req #4) — HL7au:00104.7.2.1 is registered instead.
    /// Kept for reference and for the correspondence map's AU keys.
    static let table0363: [String] = auCodes("0363")

    /// ED/RP subtype ⇒ allowed type-of-data values (M6-B-8, for
    /// HL7au:00044.10.1.5/.6 and .11.1.5/.6). Lowercased keys; values
    /// compared case-insensitively (the ADRM's own examples mix
    /// `TEXT^RTF` §4.5.2 and `text^html` §4.5.3). Only spec-STATED
    /// pairs are present — ADRM §3.20.5's type-subtype sections
    /// (image: TIFF/PICT/DICOM/FAX/Jot; audio: basic; application:
    /// octet-stream/PostScript), the 0291 extension rows' own MIME
    /// annotations (pdf ⇒ application/pdf, png ⇒ image/png, xml ⇒
    /// text/xml and application/xml), and the §4.5/§4.26 examples.
    /// Unstated subtypes skip (the IANA registry is unbounded).
    static let subtypeToTypeMap: [String: [String]] = [
        // §3.20.5.1 Image subtypes → 0191 IM (MIME "image" also allowed).
        "tiff": ["IM", "image"],
        "pict": ["IM", "image"],
        "dicom": ["IM", "image", "application"],
        "fax": ["IM", "image"],
        "jot": ["IM", "image"],
        "gif": ["IM", "image"],
        "jpeg": ["IM", "image"],
        "png": ["image", "IM"],
        // §3.20.5.2 Audio subtypes → 0191 AU (MIME "audio").
        "basic": ["AU", "audio"],
        // §3.20.5.3 Application subtypes → 0191 AP (MIME "application").
        "octet-stream": ["AP", "application"],
        "postscript": ["AP", "application"],
        "pdf": ["application", "AP"],
        // Text-family, per the §4.5 display examples and the 0291/xml
        // MIME annotations.
        "rtf": ["TEXT", "text", "application"],
        "html": ["text", "TEXT"],
        "sgml": ["text", "TEXT"],
        "xml": ["text", "application", "TEXT"],
        "csv": ["text"],
        "x-hl7-cda-level-one": ["text", "TEXT", "application"],
        "x-hl7-cda-xdm-zip": ["application"],
    ]

    /// Public coding systems the ADRM names (M6-B-9, HL7au:000034.1/.2):
    /// LN (LOINC — named throughout), SCT (SNOMED CT-AU — the referral
    /// OBR-4 codes §4.4.1.4.1), UCUM (units §4.4.2.6). Used as a
    /// correspondence map: a public system in the ALTERNATE coding-system
    /// slot requires the PRIMARY slot to also be public — i.e. the
    /// public code was not relegated behind a local one. Systems the
    /// ADRM does not name skip (PARTIAL).
    static let publicCodingSystems: [String] = ["LN", "SCT", "UCUM"]

    /// key = a public system appearing in CE/CWE/CNE-6 (alternate);
    /// allowed values for CE-3 (primary) = the public set.
    static let publicInAlternateMap: [String: [String]] = [
        "ln": publicCodingSystems,
        "sct": publicCodingSystems,
        "ucum": publicCodingSystems,
    ]
}
