// AttributeUsageTable.swift
// The segment attribute tables of a localisation, as it prints them: for the AU ADRM 2021.1,
// the OPT cell of every row of its 23 tables. The rows live in
// `Generated/AttributeUsageTable+au_adrm_2021.swift`, emitted by `HL7v2KitCodegen` from
// `Resources/profiles/au-adrm-2021/attribute-tables.json`, which a private script extracts
// from the ADRM PDF. Internal: the public read is `HL7Locale.fieldUsage`.

/// One row of a localisation's segment attribute table.
struct AttributeUsageRow: Sendable, Equatable, Hashable {
    let segment: String
    /// 1-based field index (the table's SEQ).
    let field: Int
    /// The OPT cell without its footnote marks ("R", "O", "C", "B", "X"), or "" where the
    /// table prints none (a reserved field, and PV2-39).
    let code: String
    /// The page of the localisation the row is printed on.
    let page: Int
}

enum AttributeUsageTable {
    /// The row for `segment` and `field`, or nil when the localisation prints none.
    static func row(segment: String, field: Int, in rows: [AttributeUsageRow]) -> AttributeUsageRow? {
        rows.first { $0.segment == segment && $0.field == field }
    }
}
