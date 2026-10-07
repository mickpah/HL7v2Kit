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
    /// Consumed by HL7au:00044.7.3 (XCN-10 membership, M6-B-5), with
    /// the caller's `localTableExtensions["0200"]` (P12 S3-2).
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

    /// The pattern rows of the same table: `NNxxx`, "National Person
    /// Identifier where the xxx is the ISO table 3166 3-character
    /// (alphabetic) country code" (p. 306). A value set over 0203 passes
    /// these with `table0203` (P12 S2-2), or a conformant `NNAUS` fires.
    static let table0203Patterns: [HL7Table.CodePattern] =
        HL7TableRegistry.table("0203", locale: .auLocalisation)?.patterns ?? []

    /// User-defined Table 0363 — Assigning Authority, the AU-defined
    /// value set printed in AU ADRM-2021 (p. 310). No unconditional
    /// membership rule: the table is user-defined and the ADRM's own
    /// PRD-7 matches table (p. 334) uses vendor authorities outside it
    /// (`Medical-Objects`, `Argus`), so a closed-set check would
    /// misfire (req #4). HL7au:00104.7.2.1 checks it only under
    /// `ValidationOptions.auAssigningAuthorityTable`, with the caller's
    /// vendor authorities from `localTableExtensions["0363"]` (P12 S2-2);
    /// HL7au:00104.7.1.4 reads it to tell vendor authorities apart.
    static let table0363: [String] = auCodes("0363")

    /// ED/RP subtype ⇒ allowed type-of-data values (M6-B-8, for
    /// HL7au:00044.10.1.5/.6 and .11.1.5/.6). Lowercased keys; values
    /// compared case-insensitively (the ADRM's own examples mix
    /// `TEXT^RTF` §4.5.2 and `text^html` §4.5.3). Only spec-STATED
    /// pairs are present — ADRM §3.20.5's type-subtype sections
    /// (image: TIFF/PICT/DICOM/FAX/Jot; audio: basic; application:
    /// octet-stream/PostScript), the 0291 extension rows' own MIME
    /// annotations (pdf ⇒ application/pdf, png ⇒ image/png, xml ⇒
    /// text/xml and application/xml, emf ⇒ image/emf; pp. 169-170, the
    /// rows the AU Table 0291 rendering carries), and the §4.5/§4.26 examples.
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
        // The 0291 MIME row "emf   image/emf" (p. 170, P12 S3-2).
        "emf": ["image"],
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

    /// User defined Table 0396 — Coding System, as printed in AU
    /// ADRM-2021 §3.3.3 (pp. 142–145). Consumed by HL7au:000034.1/.2.
    static let table0396: [String] = auCodes("0396")

    /// The local coding-system forms Table 0396 prints in its "99ZZZ or L"
    /// row (p. 144): "L", and "99zzz, where z is an alphanumeric
    /// character" (the same row: "The 'zzz' SHALL be any printable ASCII
    /// string"), read as the prefix `99`.
    static let localCodingSystemValues: [String] = ["L"]
    static let localCodingSystemPrefixes: [String] = ["99"]

    /// HL7au:000034.1/.2 (P12 S2-2, replacing the M6-B-9 three-system
    /// map, which fired on two public systems): key = a non-local row of
    /// the ADRM's Table 0396 in the ALTERNATE coding-system slot (CE-6);
    /// the PRIMARY slot (CE-3) must then not be local. Read with
    /// `CorrespondenceValueRule.forbidden(prefixes: localCodingSystemPrefixes)`.
    /// A public system outside the printed table, and a local system
    /// spelt other than `L` or `99zzz`, skip (PARTIAL).
    static let localPrimaryForbiddenMap: [String: [String]] = Dictionary(
        uniqueKeysWithValues: table0396
            .filter { code in
                !localCodingSystemValues.contains(code)
                    && !localCodingSystemPrefixes.contains(where: { code.hasPrefix($0) })
            }
            .map { ($0.lowercased(), localCodingSystemValues) }
    )
}
