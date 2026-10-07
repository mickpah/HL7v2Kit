// FieldLengthSpecConflictTests.swift
// P6-6 fix round 1, owner ruling G10: where a pre-v2.7 LEN cell is shorter than values its
// own spec defines as valid, the schema carries the smallest length that admits every valid
// value, with a cited LENGTH_WHITELIST entry (scripts/private/audit-schemas.py) and a row in the
// permanent-limitations register, section C. The guard below keeps the class closed.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Field length: spec-internal conflicts (G10)")
struct FieldLengthSpecConflictTests {

    /// (version, segment, field, corrected LEN). Each value is derived in the whitelist
    /// citation: the longest code of the bound HL7 table, or for MSH-9 the three message-type
    /// components' longest codes plus two component separators.
    static let corrections: [(Version, String, Int, String)] = [
        (.v2_3, "MSH", 18, "10"),     // Table 0211 "JIS X 0202"
        (.v2_3, "OBX", 2, "3"),       // Table 0125 three-letter codes ("XAD")
        (.v2_3, "PEO", 25, "2"),      // Table 0243 "NA"
        (.v2_3_1, "MSH", 9, "15"),    // 0076 (3) ^ 0003 (3) ^ 0354 (7)
        (.v2_3_1, "PEO", 25, "2"),
        (.v2_3_1, "TXA", 3, "11"),    // Table 0191 "Application" (section 2.8.36)
        (.v2_4, "MSH", 9, "15"),
        (.v2_4, "OBX", 2, "3"),
        (.v2_4, "OM3", 7, "3"),
        (.v2_4, "PEO", 25, "2"),
        (.v2_4, "TXA", 3, "9"),       // Table 0191 "multipart"
        (.v2_5_1, "OBX", 2, "3"),
        (.v2_5_1, "OM3", 7, "3"),
        (.v2_5_1, "PEO", 25, "2"),
        (.v2_5_1, "TXA", 3, "9"),
        (.v2_6, "PEO", 25, "2"),
        (.v2_6, "PSL", 21, "4"),      // Table 0532 "ASKU" / "NASK"
        (.v2_6, "TXA", 3, "9"),
    ]

    @Test("Each G10 field carries the length that admits every valid value")
    func corrected() {
        for (version, segment, index, length) in Self.corrections {
            let stored = Validator.grammarTable(for: version)[segment]?.field(index)?.length
            #expect(stored == length, "\(version.rawValue) \(segment)-\(index)")
        }
    }

    @Test("v2.4 MSH-9 ADT^A01^ADT_A01 and v2.5.1 OBX-2 CWE raise no length issue")
    func noLongerFlagged() throws {
        let msh24 = "MSH|^~\\&|A|B|C|D|20240101120000||ADT^A01^ADT_A01|M1|P|2.4\r"
        let msh251 = "MSH|^~\\&|A|B|C|D|20240101120000||ORU^R01^ORU_R01|M1|P|2.5.1\r"
        let report24 = Validator().validate(try Parser().parse(msh24))
        let report251 = Validator().validate(try Parser().parse(msh251 + "OBX|1|CWE|X^Y||A^B\r"))
        for issue in report24.issues + report251.issues {
            if case .fieldLengthOutOfRange = issue.code { Issue.record("\(issue.message)") }
        }
    }

    /// The longest code a table defines, skipping the printed range rows ("2 ... 99") and the
    /// "varies" placeholder, which are not codes.
    static func longestCode(_ table: HL7Table) -> Int? {
        table.codes.filter { !$0.isEmpty && !$0.contains("..") && $0.lowercased() != "varies" }
            .map(\.count).max()
    }

    /// The longest value a composite admits when every component is an ID bound to one HL7
    /// table: the components' longest codes plus the separators between them. nil when any
    /// component is not such an ID, since a free-text component has no defined maximum below
    /// the datatype's own, and v2.5.1 section 2.5.3.2 lets a field length fall anywhere between
    /// the datatype's bounds.
    static func closedCompositeMaximum(_ dataType: String, version: Version) -> Int? {
        guard let grammar = DataTypeGrammarTable.grammar(dataType, version: version),
              !grammar.components.isEmpty else { return nil }
        var total = grammar.components.count - 1
        for component in grammar.components {
            guard component.dataType == "ID", component.tables.count == 1,
                  let table = HL7TableRegistry.table(component.tables[0], version: version),
                  table.kind == .hl7, let longest = longestCode(table) else { return nil }
            total += longest
        }
        return total
    }

    // Guard (G10). Pre-v2.7 only: from v2.7 a field LEN is either a normative length the spec
    // derives from the value domain or a conformance length that bounds storage. The composite
    // half needs a component grammar; v2.3 to v2.4 define MSH-9 (CM) in field prose with no
    // component table, so the three MSH-9 rows above are derived by hand and pinned by
    // `corrected`, not by this guard.
    @Test("Every pre-v2.7 table-bound ID or IS field, and closed-coded composite, admits its longest valid value",
          arguments: Version.allCases.filter { $0.printsMaximumLength })
    func guardAgainstShortLengths(_ version: Version) {
        var short: [String] = []
        for (segmentID, grammar) in Validator.grammarTable(for: version) {
            for field in grammar.fields {
                guard let cell = field.length, case .maximum(let length)? = FieldLengthRule.parse(cell, version: version)
                else { continue }
                var longest: Int?
                if ["ID", "IS"].contains(field.dataType), let number = field.table,
                   let table = HL7TableRegistry.table(number, version: version), table.kind == .hl7 {
                    longest = Self.longestCode(table)
                } else {
                    longest = Self.closedCompositeMaximum(field.dataType, version: version)
                }
                if let longest, longest > length {
                    short.append("\(version.rawValue) \(segmentID)-\(field.index) LEN \(length) < \(longest)")
                }
            }
        }
        #expect(short.isEmpty, "\(short.sorted())")
    }
}
