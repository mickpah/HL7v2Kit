// V291DeleteIndicatorTests.swift
// The delete indicator on v2.9.1, from its own CH02, which prints v2.9's words under other numbers. 2.4.3.1 pp9-10:
// "Populated with Delete Indicator" is a state of its own, defined by "the corresponding data base element", and ""
// "for other purposes is prohibited". 2.9.4.1 p43: to delete a repeating group, "a single segment with "delete data"
// indicated for the first field (or all fields)"; p44 prints NK1|""|""|""|"" and NK1|""|, and p45 IN1|""|"". The further
// signals on p43 are "By agreement among messaging partners or Conformance Profile", which a validator cannot know, so
// they stay findings. The control list is a reading of CH02 2.13 and CH05 5.4, which print no such list. CX.5 is
// printed R at CH02A 2A.2.14. GSP, GSR and GSC are CH03's (3.4.19 to 3.4.21), so they are data segments.

import Testing
@testable import HL7v2Kit

@Suite("v2.9.1 delete indicator")
struct V291DeleteIndicatorTests {
    private let delete = "\"\""

    private func issues(_ version: String, _ lines: String...) throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|HIS|FAC|LAB|FAC|20240301120000||ADT^A01^ADT_A01|MSG00001|P|\(version)\r"
            + lines.joined(separator: "\r") + "\r"
        return Validator().validate(try Parser().parse(wire)).issues
    }

    /// `value` at `segment-index`, the other fields empty.
    private func segment(_ segment: String, _ index: Int, _ value: String) -> String {
        segment + String(repeating: "|", count: index) + value
    }

    private static func isComponentFinding(_ issue: ValidationIssue) -> Bool {
        if issue.location.componentIndex != nil { return true }
        switch issue.code {
        case .requiredComponentMissing, .conditionalComponentMissing, .componentNotSupported: return true
        default: return false
        }
    }

    // MARK: - (b) a repetition holding only the delete indicator

    @Test("A lone \"\" or \"\"^ draws nothing at a live composite field",
          arguments: [("IN1", 3), ("PID", 3), ("PID", 40), ("PV1", 7)], ["\"\"", "\"\"^"])
    func noFindingAtTheField(field: (String, Int), value: String) throws {
        let found = try issues("2.9.1", segment(field.0, field.1, value)).filter {
            $0.location.segmentID == field.0 && $0.location.fieldIndex == field.1
        }
        #expect(found.isEmpty, "\(found.map(\.message))")
    }

    @Test("No field of a v2.9.1 data segment draws a component finding on a lone \"\" or \"\"^")
    func noComponentFindingAnywhere() throws {
        var checked = 0
        for (id, grammar) in SegmentGrammarTable.v2_9_1 where !Validator.messageControlSegments.contains(id) {
            for field in grammar.fields {
                for value in [delete, delete + "^"] {
                    checked += 1
                    let found = try issues("2.9.1", segment(id, field.index, value)).filter(Self.isComponentFinding)
                    #expect(found.isEmpty, "\(id)-\(field.index) \(value): \(found.map(\.message))")
                }
            }
        }
        #expect(checked > 5000)
    }

    @Test("A real value is still checked, repetition by repetition")
    func realValueStillChecked() throws {
        func cx5(_ value: String) throws -> [Int?] {
            try issues("2.9.1", segment("PID", 3, value)).filter { $0.code == .requiredComponentMissing }
                .map(\.location.componentIndex)
        }
        #expect(try cx5("\(delete)~123") == [5])
        #expect(try cx5("123~\(delete)") == [5])
        #expect(try cx5("\(delete)~A^B") == [5])
        #expect(try cx5("A^\(delete)") == [5])
        #expect(try cx5("\(delete)^B") == [5])
        #expect(try cx5("\(delete)^^^^MR").isEmpty)
    }

    // MARK: - (a) never on a message-control segment

    @Test("MSH-9 = \"\" keeps its errors: a message type has no data base element")
    func messageTypeKeepsItsErrors() throws {
        let wire = "MSH|^~\\&|HIS|FAC|LAB|FAC|20240301120000||\(delete)|MSG00001|P|2.9.1\r"
        let found = Validator().validate(try Parser().parse(wire)).issues.filter {
            $0.code == .requiredComponentMissing && $0.location.segmentID == "MSH" && $0.location.fieldIndex == 9
        }
        #expect(found.map(\.location.componentIndex) == [2, 3])
    }

    @Test("A control segment's composite field is still read: UAC-2 holds \"\"")
    func controlCompositeStillRead() throws {
        let found = try issues("2.9.1", "UAC|KERB|\(delete)").filter {
            $0.code == .requiredComponentMissing && $0.location.fieldIndex == 2
        }
        #expect(found.map(\.location.componentIndex) == [2, 4, 5])
    }

    @Test("A control segment with \"\" first is not a delete segment",
          arguments: [("MSA", 2), ("ERR", 3), ("SFT", 2), ("UAC", 2), ("QID", 2), ("RDF", 2)])
    func controlSegmentIsNotADeleteSegment(id: String, requiredField: Int) throws {
        let found = try issues("2.9.1", "\(id)|\(delete)").filter {
            $0.code == .requiredFieldMissing && $0.location.segmentID == id && $0.location.fieldIndex == requiredField
        }
        #expect(found.count == 1)
    }

    @Test("OVR-4 = \"\" keeps its component finding: an override holds no data base element")
    func overrideKeepsItsFinding() throws {
        let found = try issues("2.9.1", "OVR||||\(delete)").filter {
            $0.location.segmentID == "OVR" && $0.location.fieldIndex == 4
        }
        #expect(found.contains { $0.code == .conditionalComponentMissing })
    }

    /// QPD-1's R is met by "", and nothing else in QPD is unconditionally required, so this wire has no finding
    /// to keep, on v2.9.1 or on v2.8.2. What the list decides is the reading: the "" is not a delete indicator.
    @Test("QPD|\"\" draws nothing, as on v2.8.2, and its \"\" is not read as a delete indicator")
    func queryIsNotADeleteSegment() throws {
        for version in ["2.9.1", "2.8.2"] {
            #expect(try issues(version, "QPD|\(delete)").filter {
                $0.location.segmentID == "QPD" && $0.location.fieldIndex != nil
            }.isEmpty)
        }
    }

    /// CH05 5.4 prints eight segments and no list of control segments. QID "contains the information necessary to uniquely
    /// identify a query" (5.4.3 p51) and RDF "defines the content of the row data segments" (5.4.7 p55), so neither has a data base
    /// element. DSP carries data, and DSP-3 is R (5.4.1 p48): as a delete segment it is the control.
    @Test("In the query section QID and RDF keep their findings, and DSP, a data segment, reads as deleted")
    func querySectionReading() throws {
        func required(_ line: String, _ id: String) throws -> [Int?] {
            try issues("2.9.1", line).filter { $0.code == .requiredFieldMissing && $0.location.segmentID == id }.map(\.location.fieldIndex)
        }
        #expect(try required("QID|\(delete)", "QID") == [2])
        #expect(try required("RDF|\(delete)", "RDF") == [2])
        #expect(try required("DSP|\(delete)", "DSP").isEmpty)
        #expect(try required("DSP|1", "DSP") == [3])
    }

    @Test("\"\" is a delete indicator on a data segment and not on a control segment; the list is a reading of CH02 2.13 and CH05 5.4",
          arguments: [("PID", true), ("NTE", true), ("ADD", true), ("GSP", true), ("GSR", true), ("GSC", true),
                      ("DSC", false), ("SGH", false), ("SGT", false), ("OVR", false),
                      ("QAK", false), ("QID", false), ("QPD", false), ("RCP", false), ("RDF", false),
                      ("DSP", true), ("QRI", true), ("RDT", true),
                      ("MSH", false), ("BHS", false), ("FHS", false), ("BTS", false), ("FTS", false),
                      ("MSA", false), ("ERR", false), ("SFT", false), ("UAC", false)])
    func deleteIndicatorBySegment(id: String, reads: Bool) throws {
        let message = try Parser().parse("MSH|^~\\&|HIS|FAC|LAB|FAC|20240301120000||ADT^A01^ADT_A01|MSG00001|P|2.9.1\rPID|\(delete)\r")
        let repetition = try #require(message.segments.last?.field(1)?.repetitions.first)
        #expect(Validator().isDeleteIndicator(repetition, segmentID: id) == reads)
    }

    // MARK: - (c) the print's delete segment

    @Test("A data segment with \"\" first and nothing else real draws no field-level finding",
          arguments: ["IN1|\"\"|\"\"", "PV1|\"\"", "OBX|\"\"", "NK1|\"\"|\"\"|\"\"|\"\"", "NK1|\"\"|", "DG1|\"\"", "GT1|\"\"",
                      "GSP|\"\"", "GSR|\"\"", "GSC|\"\""])
    func deleteSegmentIsSilent(line: String) throws {
        let id = String(line.prefix(3))
        let found = try issues("2.9.1", line).filter { $0.location.segmentID == id && $0.location.fieldIndex != nil }
        #expect(found.isEmpty, "\(found.map(\.message))")
    }

    @Test("IN1|2|\"\"|\"\" has a real first field, so its fields are read, and meets them")
    func keyedDeleteStaysAsItWas() throws {
        let found = try issues("2.9.1", "IN1|2|\(delete)|\(delete)").filter {
            $0.location.segmentID == "IN1" && $0.location.fieldIndex != nil
        }
        #expect(found.isEmpty)
        #expect(try issues("2.9.1", "IN1|2").contains { $0.code == .requiredFieldMissing && $0.location.fieldIndex == 3 })
    }

    @Test("\"\" first and a real value elsewhere is checked as any segment is",
          arguments: [("IN1|\"\"|A357", 3), ("OBX|\"\"|NM", 3), ("PV1|\"\"||A", 2)])
    func realValueElsewhere(line: String, missing: Int) throws {
        let id = String(line.prefix(3))
        #expect(try issues("2.9.1", line).contains {
            $0.code == .requiredFieldMissing && $0.location.segmentID == id && $0.location.fieldIndex == missing
        })
    }

    @Test("A delete indicator only in a later field is by agreement, so it stays a finding")
    func laterFieldOnlyStaysAFinding() throws {
        let found = try issues("2.9.1", "IN1||\(delete)").filter {
            $0.code == .requiredFieldMissing && $0.location.segmentID == "IN1"
        }
        #expect(found.map(\.location.fieldIndex) == [1, 3])
    }

    // MARK: - The AU locale

    private func auIssues(_ line: String) throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|LAB|FAC|GP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|2.9.1\r\(line)\r"
        let message = try Parser(locale: .auLocalisation).parse(wire)
        return Validator(options: .default, locale: .auLocalisation).validate(message).issues
    }

    /// OBR-24 is profile-required on an ORU (AU profile, `profileUsage: .required`). The usage check runs inside
    /// `checkField`, so the delete segment's guard reaches it.
    @Test("Under the AU locale a delete segment is silent, and a populated segment still draws its AU finding")
    func auLocaleOnDeleteSegment() throws {
        func obr24(_ line: String) throws -> [ValidationIssue] {
            try auIssues(line).filter { $0.location.segmentID == "OBR" && $0.location.fieldIndex == 24 }
        }
        #expect(try obr24("OBR|\(delete)").isEmpty)
        #expect(try auIssues("OBR|\(delete)").filter { $0.location.segmentID == "OBR" && $0.location.fieldIndex != nil }.isEmpty)
        let populated = try obr24("OBR|1")
        #expect(populated.count == 1)
        #expect(populated.first?.message.contains("profile-required") == true)
    }
}
