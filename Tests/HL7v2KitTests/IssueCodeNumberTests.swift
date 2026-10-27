// IssueCodeNumberTests.swift
// X1 task 2: IssueCode.number, the stable numeric code of each check. The table below is the
// contract: a number in it is never changed or reused, and a new case takes the next free
// number in its band.

import Foundation
import Testing
import HL7v2Kit

@Suite("Issue code numbers")
struct IssueCodeNumberTests {
    /// Every case's number. Bands: 1 structure and profile, 2 cardinality and type, 3 primitive
    /// and value, 4 binding and terminology, 5 invariant, 9 not evaluated.
    static let numbers: [String: Int] = [
        "fieldNotSupported": 1001, "zSegmentPresent": 1002, "profileConstraintViolation": 1003,
        "segmentNotInVersionGrammar": 1004, "segmentWithdrawnInVersion": 1005,
        "versionGrammarSubstituted": 1006, "versionNotRecognised": 1007, "componentNotSupported": 1008,
        "messageStructureSegmentMissing": 1009, "messageStructureSegmentUnexpected": 1010,
        "messageStructureMismatch": 1011, "messageStructureNotModelled": 1012,
        "batchEnvelopeMalformed": 1013,
        "requiredFieldMissing": 2001, "requiredComponentMissing": 2002, "cardinalityExceeded": 2003,
        "profileMaximumExceeded": 2004, "segmentCardinalityBelowMinimum": 2005,
        "segmentCardinalityAboveMaximum": 2006, "extraComponentsInPrimitiveField": 2007,
        "extraComponentsInCompositeField": 2008, "batchCountMismatch": 2009,
        "pairedFieldMismatch": 3001, "fieldLengthOutOfRange": 3002, "componentLengthOutOfRange": 3003,
        "valueFormatInvalid": 3004,
        "valueNotInTable": 4001,
        "conditionalFieldMissing": 5001, "conditionalComponentMissing": 5002,
        "conformanceConditionMissing": 5003, "conditionalFieldProhibited": 5004,
        "conditionNotEvaluated": 9001,
    ]

    @Test("Every case has the number the table gives it")
    func everyCaseHasItsNumber() {
        #expect(Self.numbers.count == ValidationArticleCoverageTests.everyCode.count)
        for code in ValidationArticleCoverageTests.everyCode {
            let name = ValidationArticleCoverageTests.name(of: code)
            #expect(code.number == Self.numbers[name], "\(name)")
        }
    }

    @Test("Numbers are distinct, in the six bands, and run from x001 with no gap in each band")
    func numbersAreDenseInTheirBands() {
        let numbers = ValidationArticleCoverageTests.everyCode.map(\.number)
        #expect(Set(numbers).count == numbers.count)
        let bands = Dictionary(grouping: numbers) { $0 / 1000 }
        #expect(Set(bands.keys) == [1, 2, 3, 4, 5, 9])
        for (band, members) in bands {
            #expect(members.sorted() == Array(band * 1000 + 1 ... band * 1000 + members.count), "band \(band)")
        }
    }

    @Test("Associated values do not change the number")
    func payloadDoesNotChangeTheNumber() {
        #expect(IssueCode.valueNotInTable(table: "0001").number == IssueCode.valueNotInTable(table: "0396").number)
    }

    @Test("Validation.md lists every number on the row that links its case")
    func articleListsEveryNumber() throws {
        let article = try String(
            contentsOf: ValidationArticleCoverageTests.root
                .appendingPathComponent("Sources/HL7v2Kit/HL7v2Kit.docc/Validation.md"),
            encoding: .utf8)
        let rows = article.split(separator: "\n").filter { $0.hasPrefix("| ") }
        for code in ValidationArticleCoverageTests.everyCode {
            let name = ValidationArticleCoverageTests.name(of: code)
            let listed = rows.contains { row in
                row.hasPrefix("| \(code.number) | ")
                    && (row.contains("IssueCode/\(name)``") || row.contains("IssueCode/\(name)("))
            }
            #expect(listed, "Validation.md has no row \(code.number) linking IssueCode/\(name)")
        }
    }
}
