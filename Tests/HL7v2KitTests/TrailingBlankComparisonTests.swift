// TrailingBlankComparisonTests.swift
// ST, v2.9 CH02A 2A.3.76 p82 and v2.9.1 2A.2.76 p83: "String data is left justified (i.e., no leading blank space) with
// trailing blanks optional, which may be trimmed, and SHOULD be ignored on string compare operations for 2 values of type
// ST". ID "follows the formatting rules for an ST field" (p50 on each). By the owner's ruling, value comparisons ignore
// them on these two versions only. v2.3 to v2.8.2 keep the ruling of 7 October, on an ST sentence that stops at
// "trailing blanks optional". Length still counts the blank, a leading blank stays a finding, and only U+0020 is a blank.

import Testing
@testable import HL7v2Kit

@Suite("Trailing blanks in comparisons")
struct TrailingBlankComparisonTests {
    private func issues(_ wire: String, options: ValidationOptions = .default, locale: HL7Locale = .international) throws -> [ValidationIssue] {
        Validator(options: options, locale: locale).validate(try Parser(locale: locale).parse(wire)).issues
    }

    private func wire(_ version: String, type: String = "ADT^A01^ADT_A01", processing: String = "P", tail: String = "", _ lines: String...) -> String {
        "MSH|^~\\&|SND|FAC|RCV|FAC|20260930120000||\(type)|MSG1|\(processing)|\(version)\(tail)\r" + lines.map { $0 + "\r" }.joined()
    }

    private func inTable(_ table: String, _ found: [ValidationIssue]) -> Int {
        found.filter { $0.code == .valueNotInTable(table: table) }.count
    }

    @Test("The era is v2.9 and v2.9.1 alone, and only a trailing U+0020 goes")
    func era() {
        #expect(Version.allCases.filter(\.ignoresTrailingBlanksInComparisons) == [.v2_9, .v2_9_1])
        #expect(Version.v2_9.comparisonValue("P  ") == "P")
        #expect(Version.v2_9_1.comparisonValue(" P ") == " P")
        #expect(Version.v2_9.comparisonValue("P\t") == "P\t")
        #expect(Version.v2_9.comparisonValue("P\u{A0}") == "P\u{A0}")
        #expect(Version.v2_8_2.comparisonValue("P ") == "P ")
    }

    // MARK: - Table checks, component and field

    @Test("A padded MSH-12 draws no 0104", arguments: ["2.9 ", "2.9.1 ", "2.9  ^AUS"])
    func paddedVersion(msh12: String) throws {
        #expect(try inTable("0104", issues(wire(msh12))) == 0)
    }

    @Test("A leading blank in MSH-12 still draws 0104")
    func leadingBlankVersion() throws {
        #expect(try inTable("0104", issues(wire(" 2.9"))) == 1)
    }

    @Test("MSH-11 P with a trailing blank draws no 0103 on v2.9 and v2.9.1, and does on v2.8.2",
          arguments: [("2.9", 0), ("2.9.1", 0), ("2.8.2", 1)])
    func paddedProcessingID(version: String, findings: Int) throws {
        #expect(try inTable("0103", issues(wire(version, processing: "P "))) == findings)
    }

    @Test("Only a trailing U+0020 is ignored: a leading blank and a tab still draw 0103", arguments: ["2.9", "2.9.1"], [" P", "P\t"])
    func otherBlanksStayFindings(version: String, value: String) throws {
        #expect(try inTable("0103", issues(wire(version, processing: value))) == 1)
    }

    /// MSH-15 is a primitive ID, so this is the field-level table check, and its LEN is 2..2.
    @Test("A field-level ID ignores the blank in the table check, and length still counts it", arguments: ["2.9", "2.9.1"])
    func paddedFieldStillDrawsLength(version: String) throws {
        let found = try issues(wire(version, tail: "|||AL |NE"))
        #expect(inTable("0155", found) == 0)
        #expect(found.contains { $0.code == .fieldLengthOutOfRange(length: "2..2", actual: 3) && $0.location.fieldIndex == 15 })
    }

    @Test("v2.8.2's field-level table check still counts the blank")
    func paddedFieldOnV282() throws {
        #expect(try inTable("0155", issues(wire("2.8.2", tail: "|||AL |NE"))) == 1)
    }

    @Test("A local table extension and the AU locale read the same value", arguments: ["2.9", "2.9.1"])
    func sharedSites(version: String) throws {
        var options = ValidationOptions.default
        options.localTableExtensions["0155"] = ["ZZ"]
        #expect(try inTable("0155", issues(wire(version, tail: "|||ZZ |NE"), options: options)) == 0)
        #expect(try inTable("0155", issues(wire(version, tail: "|||ZZ |NE"))) == 1)
        #expect(try inTable("0103", issues(wire(version, processing: "P "), locale: .auLocalisation)) == 0)
    }

    // MARK: - MSH-9

    @Test("ACK with a trailing blank in MSH-9.3 resolves on v2.9, and keeps today's mismatch on v2.8.2")
    func paddedStructure() throws {
        let padded = try Parser().parse(wire("2.9", type: "ACK^A01^ACK ", "MSA|AA|MSG0"))
        let resolved = Validator().resolveStructure(padded, severity: .warning)
        #expect(resolved.structure?.id == "ACK")
        #expect(resolved.issues.isEmpty)
        let earlier = Validator().resolveStructure(try Parser().parse(wire("2.8.2", type: "ACK^A01^ACK ", "MSA|AA|MSG0")), severity: .warning)
        #expect(earlier.structure == nil)
        #expect(earlier.issues.map(\.code) == [.messageStructureMismatch(declared: "ACK ", trigger: "ACK^A01")])
    }

    @Test("A padded message code and trigger event select the structure on v2.9")
    func paddedTrigger() throws {
        let resolved = Validator().resolveStructure(try Parser().parse(wire("2.9", type: "ACK ^A01 ^ACK", "MSA|AA|MSG0")), severity: .warning)
        #expect(resolved.structure?.id == "ACK")
        #expect(resolved.issues.isEmpty)
    }

    @Test("A leading blank in MSH-9.3 is still no structure on v2.9")
    func leadingBlankStructure() throws {
        let resolved = Validator().resolveStructure(try Parser().parse(wire("2.9", type: "ACK^A01^ ACK", "MSA|AA|MSG0")), severity: .warning)
        #expect(resolved.structure == nil)
    }

    @Test("The gated message codes read a padded code on v2.9, and not on v2.8.2")
    func paddedGate() {
        func gated(_ version: Version) -> Bool {
            if case .gated = Validator.fallbackScoping(version: version, messageCode: "OUL ") { return true }
            return false
        }
        #expect(gated(.v2_9))
        #expect(gated(.v2_9_1))
        #expect(!gated(.v2_8_2))
    }

    // MARK: - Condition predicates

    private func at(_ id: String, _ index: Int, _ code: IssueCode, _ found: [ValidationIssue]) -> Bool {
        found.contains { $0.code == code && $0.location.segmentID == id && $0.location.fieldIndex == index }
    }

    @Test("= reads a padded MSH-9.1: MFI-6 is required on MFN", arguments: [("2.9", true), ("2.9.1", true), ("2.8.2", false)])
    func paddedEquals(version: String, fires: Bool) throws {
        let found = try issues(wire(version, type: "MFN ^M02", "MFI|PRA^Practitioner^HL70175||UPD"))
        #expect(at("MFI", 6, .conditionalFieldMissing, found) == fires)
    }

    @Test("!= reads a padded field: RCP-4 is not refused when RCP-1 is D", arguments: [("2.9", false), ("2.9.1", false), ("2.8.2", true)])
    func paddedNotEquals(version: String, refused: Bool) throws {
        let found = try issues(wire(version, "RCP|D |||20260101"))
        #expect(at("RCP", 4, .conditionalFieldProhibited, found) == refused)
    }

    @Test("in reads a padded field: LRL-5 is required for RX", arguments: [("2.9", true), ("2.9.1", true), ("2.8.2", false)])
    func paddedIn(version: String, fires: Bool) throws {
        let found = try issues(wire(version, "LRL|LOC|||RX "))
        #expect(at("LRL", 5, .conditionalFieldMissing, found) == fires)
    }

    @Test("not in reads a padded field: MFE-2 is not required for NE", arguments: [("2.9", false), ("2.9.1", false), ("2.8.2", true)])
    func paddedNotIn(version: String, fires: Bool) throws {
        let found = try issues(wire(version, type: "MFN^M02", "MFI|PRA^Practitioner^HL70175||UPD|||NE ", "MFE|MAD|||KEY1"))
        #expect(at("MFE", 2, .conditionalFieldMissing, found) == fires)
    }

    /// `""` is a state, not a value (CH02 2.4.3.1): a delete indicator with a blank after it is left as it was, so
    /// `OBX-5 populated AND anyRepeat(OBX-5) != ""` still reads it as a value.
    @Test("The delete indicator's literal is compared as sent", arguments: ["2.9", "2.9.1"])
    func deleteIndicatorLiteral(version: String) throws {
        let padded = try issues(wire(version, type: "ORU^R01^ORU_R01", TestWires.segment("OBX", [1: "1", 3: "O", 5: "\"\" ", 11: "D"])))
        #expect(at("OBX", 2, .conditionalFieldMissing, padded))
        let exact = try issues(wire(version, type: "ORU^R01^ORU_R01", TestWires.segment("OBX", [1: "1", 3: "O", 5: "\"\"", 11: "D"])))
        #expect(!at("OBX", 2, .conditionalFieldMissing, exact))
    }

    /// The same at `isDeleteIndicator`: `"" ` first is no delete segment, so the segment's fields are read.
    @Test("OBR with \"\" first is a delete segment, and with a blank after it is not", arguments: ["2.9", "2.9.1"])
    func deleteSegmentCompared(version: String) throws {
        func required(_ line: String) throws -> [Int?] {
            try issues(wire(version, type: "ORU^R01^ORU_R01", line)).filter {
                $0.code == .requiredFieldMissing && $0.location.segmentID == "OBR"
            }.map(\.location.fieldIndex)
        }
        #expect(try required("OBR|\"\" ").contains(4))
        #expect(try required("OBR|\"\"").isEmpty)
    }

    // MARK: - Other comparisons of wire values

    @Test("OBX-2 with a trailing blank names OBX-5's datatype on v2.9 and v2.9.1", arguments: ["2.9", "2.9.1"])
    func paddedValueType(version: String) throws {
        let found = try issues(wire(version, type: "ORU^R01^ORU_R01", "OBX|1|NM |85^Report^L||NOTANUMBER||||||F"))
        #expect(inTable("0125", found) == 0)
        #expect(found.contains { $0.code == .valueFormatInvalid(dataType: "NM") && $0.location.fieldIndex == 5 })
    }

    @Test("On v2.8.2 the same OBX-2 draws 0125, and names no datatype")
    func paddedValueTypeOnV282() throws {
        let found = try issues(wire("2.8.2", type: "ORU^R01^ORU_R01", "OBX|1|NM |85^Report^L||NOTANUMBER||||||F"))
        #expect(inTable("0125", found) == 1)
        #expect(!found.contains { $0.code == .valueFormatInvalid(dataType: "NM") })
    }

    @Test("ORC-2 and OBR-2 compare without a trailing blank", arguments: [("2.9", false), ("2.9.1", false), ("2.8.2", true)])
    func paddedPair(version: String, mismatch: Bool) throws {
        let found = try issues(wire(version, type: "ORU^R01^ORU_R01", "ORC|RE|P1 ", "OBR|1|P1||93000^EKG^C4"))
        #expect(found.contains { if case .pairedFieldMismatch = $0.code { return $0.location.fieldIndex == 2 } else { return false } } == mismatch)
    }

    @Test("A coding system with a trailing blank still claims table 0953 on v2.9 and v2.9.1", arguments: ["2.9", "2.9.1"])
    func paddedSystemClaim(version: String) throws {
        let found = try issues(wire(version, tail: String(repeating: "|", count: 15) + "BOGUS^x^HL70953 "))
        #expect(inTable("0953", found) == 1)
    }

    @Test("The printed Table OID with a trailing blank still names table 0953 on v2.9.1")
    func paddedOIDClaim() throws {
        let cwe = "BOGUS" + String(repeating: "^", count: 13) + "2.16.840.1.113883.12.953 "
        #expect(try inTable("0953", issues(wire("2.9.1", tail: String(repeating: "|", count: 15) + cwe))) == 1)
    }

    @Test("A coding system with a trailing blank is still an HL7 table to CWE.7's conformance rule", arguments: ["2.9", "2.9.1"])
    func paddedHL7Table(version: String) throws {
        var options = ValidationOptions.default
        options.conformanceConditionSeverity = .error
        func cwe7(_ system: String) throws -> Bool {
            try issues(wire(version, type: "ORU^R01^ORU_R01", "OBX|1|ST|85^Report^\(system)||x||||||F"), options: options).contains {
                $0.code == .conformanceConditionMissing && $0.location.segmentID == "OBX"
                    && $0.location.fieldIndex == 3 && $0.location.componentIndex == 7
            }
        }
        #expect(try !cwe7("HL70136"))
        #expect(try !cwe7("HL70136 "))
        #expect(try cwe7("L"))
    }
}
