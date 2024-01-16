// HL7CodeTables.swift
// Internal seed of the HL7 code-table registry (M6-B-4, closing part of
// M6-O6). Each table is the version the AU ADRM-2021 localisation
// PRINTS — that rendering is the normative one for the HL7au points
// that cite it, and it can differ from the base-spec vintage (the
// ADRM's 0203 carries post-v2.4 additions and the AU 0363 values).
//
// This is a SEED, not the general registry M6-O6 asks for: only the
// tables a shipped conformance point consumes are modelled, values
// only (no descriptions), hand-verified against the printed tables.
// Growing it into a per-version, per-locale registry with codegen
// remains the §D capability (permanent-limitations-register.md).

enum HL7CodeTables {
    /// HL7 Table 0074 — Diagnostic Service Section ID, as printed in
    /// AU ADRM-2021 §4.4.1.24 (pp. 225–226). Consumed by
    /// HL7au:000032 / 000032.2 (OBR-24 membership).
    static let table0074: [String] = [
        "AU", "BG", "BLB", "CG", "CUS", "CTH", "CT", "CH", "CP", "EC",
        "EN", "HM", "ICU", "IMM", "LAB", "MB", "MCB", "MYC", "NMR",
        "NMS", "NRS", "OUS", "OT", "OTH", "OSL", "PHR", "PT", "PHY",
        "PF", "RAD", "RUS", "RC", "RT", "RX", "SR", "SP", "TX", "VUS",
        "VR", "XRC",
    ]

    /// HL7 Table 0200 — Name Type, as printed in AU ADRM-2021 (p. 62).
    /// Not yet consumed by a shipped rule: XCN-10's HL7au:00044.7.3
    /// stays PARTIAL until the composite-override track grows a
    /// value-set rule (§D).
    static let table0200: [String] = [
        "A", "B", "C", "D", "I", "L", "M", "N", "P", "R", "S", "T", "U",
    ]

    /// HL7 Table 0203 — Identifier Type, as printed in AU ADRM-2021
    /// (pp. 301–309; the ADRM prints a post-v2.4 vintage). Consumed by
    /// HL7au:00104.7.3.1 (PRD-7.3 membership).
    static let table0203: [String] = [
        "ACSN", "AM", "AMA", "AN", "ANON", "ANC", "AND", "ANT", "APRN",
        "ASID", "BA", "BC", "BCT", "BR", "BRN", "BSNR", "CC", "CONM",
        "CZ", "CY", "DDS", "DEA", "DI", "DFN", "DL", "DN", "DO", "DP",
        "DPM", "DR", "DS", "DVW", "DVG", "DVO", "DV", "EI", "EN", "ESN",
        "FI", "GI", "GL", "GN", "HC", "JHN", "IND", "LACSN", "LANR",
        "LI", "LN", "LR", "MA", "MB", "MC", "MCD", "MCN", "MCR", "MCT",
        "MD", "MI", "MR", "MRT", "MS", "NBSNR", "NCT", "NE", "NH", "NI",
        "NII", "NIIP", "NP", "NPI", "NPIO", "OD", "PA", "PC", "PCN",
        "PE", "PEN", "PI", "PN", "PNT", "PPIN", "PPN", "PRC", "PRES",
        "PRN", "PT", "QA", "RI", "RPH", "RN", "RR", "RRI", "RRP", "SID",
        "SL", "SN", "SP", "SR", "SS", "TAX", "TN", "TPR", "U", "USID",
        "VDI", "VN", "VP", "VS", "WC", "WCN", "WP", "XX",
    ]

    /// User-defined Table 0363 — Assigning Authority, the AU-defined
    /// value set printed in AU ADRM-2021 (p. 310). Consumed by
    /// HL7au:00104.7.2.1 (PRD-7.2 membership).
    static let table0363: [String] = [
        "AUSHIC", "AUSDVA", "AUSNATA", "AUSLINK", "AUSHICPR", "IHI",
    ]
}
