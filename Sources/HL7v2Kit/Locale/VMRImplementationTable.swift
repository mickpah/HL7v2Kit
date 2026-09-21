// VMRImplementationTable.swift
// The AU ADRM-2021 HL7v2 Virtual Medical Record OBX implementation table
// (Appendix 9, Normative, table A9.T.1, pp. 492-515). The rows live in
// `Generated/VMRImplementationTable+au_adrm_2021.swift`, emitted by
// `HL7v2KitCodegen` from `Resources/profiles/au-adrm-2021/vmr-table.json`,
// which `scripts/extract-vmr-table.py` extracts from the ADRM PDF. Internal:
// it backs the sub-ID tree rules and is not public API.

/// One row of the VMR implementation table.
struct VMRElement: Sendable, Equatable, Hashable {
    /// The OBX-4 sub-ID path, rooted at "1"; `*` stands for a repeat index
    /// (the table's `RepeatOf[...]`). `1.2.1.*.3` matches `1.2.1.7.3`.
    let path: String
    /// The printed element or section heading.
    let name: String
    /// The OBX-2 the table prints, or "" for a STRUCTURAL row. Recorded, not
    /// enforced: the appendix's own example (p. 516) uses CE where this says CWE.
    let obx2: String
    let min: Int
    /// `nil` is the table's `*` (unbounded).
    let max: Int?
    /// The VMR DATATYPE column: ENTRY, SECTION, STRUCTURAL, COLLECTION, or a value type.
    let kind: String
}

enum VMRImplementationTable {
    /// The row whose path pattern `relativePath` (rooted at "1") instantiates, if any.
    /// Segment-wise match: a `*` segment accepts any unsigned integer.
    static func element(matching relativePath: String, in rows: [VMRElement]) -> VMRElement? {
        let wanted = relativePath.split(separator: ".", omittingEmptySubsequences: false)
        return rows.first { row in
            let pattern = row.path.split(separator: ".", omittingEmptySubsequences: false)
            guard pattern.count == wanted.count else { return false }
            return zip(pattern, wanted).allSatisfy { p, w in
                p == "*" ? (!w.isEmpty && w.allSatisfy(\.isNumber)) : p == w
            }
        }
    }
}
