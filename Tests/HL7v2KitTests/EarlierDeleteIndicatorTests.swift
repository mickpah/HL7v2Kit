// EarlierDeleteIndicatorTests.swift
// The delete indicator on v2.3 to v2.8.2, each version from its own CH02. `.v2_7` and `.v2_8` follow v2.7.1 and v2.8.2.
//
// A lone "" in a data field. v2.3 2.6 p2-5, v2.3.1 2.6 p2-5, v2.4 2.7 p2-12 and v2.5.1 2.5.3 pp2-7, 2-8: "Except where noted, HL7
// data fields may take on the null value ... If the null value is sent, the old value should be changed to null", and CH06 says
// "send a null value" in GT1-3, a composite. v2.6 2.5.3 p7, v2.7.1 2.5.3.0 p7 and v2.8.2 2.5.3.0 p8: "Null", "the corresponding
// data base element", and "" "for other purposes is prohibited". The two spellings are one field: |ABC^DEF^^| and |ABC^DEF| "are
// equivalent" (v2.3 p2-57, v2.3.1 p2-69, v2.4 p2-87); a component not included is "not present" (v2.5.1 p2-17); and "a Null in
// the first component" (v2.6 p36, v2.7.1 p40, v2.8.2 p41).
//
// The delete segment splits. v2.3 2.23.4.1 p2-86, v2.3.1 pp2-92, 2-93, v2.4 2.15.4.1 p2-104 and v2.5.1 2.10.4.1 p2-36: "delete data"
// "indicated for all fields", and nothing on the first field. v2.6 2.10.4.1 p33 and v2.7.1 p36 lead with "in all fields" and give
// the first field "By agreement among messaging partners or Conformance Profile"; pp34-35 and pp37-38 print NK1|""| and IN1|""|"". A
// validator cannot see an agreement and cannot say none exists, so that wire is silent, as on v2.8.2 p38, "indicated for the first
// field (or all fields)" (ruling R54). The other by-agreement signals stay findings.
//
// The control list is a reading of each print's own sections, which give no such list. v2.3 and v2.3.1 hold them in CH02 2.24, later
// versions in CH02 and CH05. QRD, QRF, URD, URS, EQL, VTQ, SPR and ERQ define or issue a query on the versions that have them.

import Testing
@testable import HL7v2Kit

@Suite("Delete indicator on v2.3 to v2.8.2")
struct EarlierDeleteIndicatorTests {
    private let delete = "\"\""

    private func issues(_ version: String, _ lines: String...) throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|HIS|FAC|LAB|FAC|20240301120000||ADT^A01^ADT_A01|MSG00001|P|\(version)\r"
            + lines.joined(separator: "\r") + "\r"
        return Validator().validate(try Parser().parse(wire)).issues
    }

    private func segment(_ segment: String, _ index: Int, _ value: String) -> String {
        segment + String(repeating: "|", count: index) + value
    }

    private func grammars(_ wire: String) throws -> [String: SegmentGrammar] {
        switch try #require(Version(rawValue: wire)) {
        case .v2_3: SegmentGrammarTable.v2_3
        case .v2_3_1: SegmentGrammarTable.v2_3_1
        case .v2_4: SegmentGrammarTable.v2_4
        case .v2_5_1: SegmentGrammarTable.v2_5_1
        case .v2_6: SegmentGrammarTable.v2_6
        case .v2_7_1, .v2_7: SegmentGrammarTable.v2_7_1
        case .v2_8_2, .v2_8: SegmentGrammarTable.v2_8_2
        case .v2_9: SegmentGrammarTable.v2_9
        case .v2_9_1: SegmentGrammarTable.v2_9_1
        }
    }

    private static func isComponentFinding(_ issue: ValidationIssue) -> Bool {
        if issue.location.componentIndex != nil { return true }
        switch issue.code {
        case .requiredComponentMissing, .conditionalComponentMissing, .componentNotSupported: return true
        default: return false
        }
    }

    private func fieldFindings(_ version: String, _ line: String) throws -> [ValidationIssue] {
        let id = String(line.prefix(3))
        return try issues(version, line).filter { $0.location.segmentID == id && $0.location.fieldIndex != nil }
    }

    // MARK: - The switches

    @Test("The first field alone is a delete segment from v2.6",
          arguments: [(Version.v2_3, false), (.v2_3_1, false), (.v2_4, false), (.v2_5_1, false), (.v2_6, true),
                      (.v2_7, true), (.v2_7_1, true), (.v2_8, true), (.v2_8_2, true), (.v2_9, true), (.v2_9_1, true)])
    func switches(version: Version, firstField: Bool) {
        #expect(version.readsFirstFieldAsDeleteSegment == firstField)
    }

    // MARK: - A lone "" draws no component finding

    @Test("No field of a data segment draws a component finding on a lone \"\" or \"\"^",
          arguments: ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.7", "2.7.1", "2.8", "2.8.2"])
    func noComponentFindingAnywhere(version: String) throws {
        var checked = 0
        for (id, grammar) in try grammars(version) where !Validator.messageControlSegments.contains(id) {
            for field in grammar.fields {
                for value in [delete, delete + "^"] {
                    checked += 1
                    let found = try issues(version, segment(id, field.index, value)).filter(Self.isComponentFinding)
                    #expect(found.isEmpty, "\(version) \(id)-\(field.index) \(value): \(found.map(\.message))")
                }
            }
        }
        #expect(checked > 1000)
    }

    /// CH06 says it outright: "if the guarantor is an organization, send a null value" in GT1-3.
    @Test("GT1-3 = \"\" draws nothing at the field, on every version",
          arguments: ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.7", "2.7.1", "2.8", "2.8.2"])
    func guarantorName(version: String) throws {
        let found = try issues(version, segment("GT1", 3, delete)).filter { $0.location.segmentID == "GT1" && $0.location.fieldIndex == 3 }
        #expect(found.isEmpty, "\(found.map(\.message))")
    }

    @Test("A real value is still checked, repetition by repetition, and \"\" with a blank after it is a value",
          arguments: ["2.7", "2.7.1", "2.8", "2.8.2"])
    func realValueStillChecked(version: String) throws {
        func cx5(_ value: String) throws -> [Int?] {
            try issues(version, segment("PID", 3, value)).filter { $0.code == .requiredComponentMissing }.map(\.location.componentIndex)
        }
        #expect(try cx5(delete).isEmpty)
        #expect(try cx5("\(delete)~123") == [5])
        #expect(try cx5("123~\(delete)") == [5])
        #expect(try cx5("\(delete)^B") == [5])
        #expect(try cx5("\(delete)^^^^MR").isEmpty)
        #expect(try cx5("\(delete) ") == [5])
    }

    /// PRD-7.2 is printed `R` on v2.5.1 and v2.6 (the same PLN row), which print CX.5 `O`.
    @Test("On v2.5.1 and v2.6 a real value at PRD-7 is still checked", arguments: ["2.5.1", "2.6"])
    func realValueEarlier(version: String) throws {
        func pln2(_ value: String) throws -> [Int?] {
            try issues(version, segment("PRD", 7, value)).filter { $0.code == .requiredComponentMissing }.map(\.location.componentIndex)
        }
        #expect(try pln2(delete).isEmpty)
        #expect(try pln2("A") == [2])
        #expect(try pln2("\(delete)~A") == [2])
        #expect(try pln2("\(delete) ") == [2])
    }

    // MARK: - Never on a message-control segment

    @Test("MSH-9 = \"\" keeps its errors where the print gives it required components",
          arguments: [("2.5.1", [2, 3]), ("2.6", [2, 3]), ("2.7", [2, 3]), ("2.7.1", [2, 3]), ("2.8", [2, 3]), ("2.8.2", [2, 3]),
                      ("2.3", []), ("2.3.1", []), ("2.4", [])])
    func messageTypeKeepsItsErrors(version: String, components: [Int]) throws {
        let wire = "MSH|^~\\&|HIS|FAC|LAB|FAC|20240301120000||\(delete)|MSG00001|P|\(version)\r"
        let found = Validator().validate(try Parser().parse(wire)).issues.filter {
            $0.code == .requiredComponentMissing && $0.location.segmentID == "MSH" && $0.location.fieldIndex == 9
        }
        #expect(found.compactMap(\.location.componentIndex) == components)
    }

    @Test("A control segment's composite field keeps its finding",
          arguments: [("2.6", "UAC", 2, [2, 4, 5]), ("2.7.1", "UAC", 2, [2, 4, 5]), ("2.8.2", "UAC", 2, [2, 4, 5]),
                      ("2.5.1", "ERR", 2, [2]), ("2.6", "ERR", 2, [2]), ("2.7.1", "ERR", 2, [2]), ("2.8.2", "ERR", 2, [2]),
                      ("2.5.1", "ERQ", 3, [2]), ("2.5.1", "SPR", 4, [2])])
    func controlCompositeStillRead(version: String, id: String, field: Int, components: [Int]) throws {
        let found = try issues(version, segment(id, field, delete)).filter {
            $0.code == .requiredComponentMissing && $0.location.segmentID == id && $0.location.fieldIndex == field
        }
        #expect(found.compactMap(\.location.componentIndex) == components)
    }

    @Test("OVR-4 = \"\" keeps its finding", arguments: ["2.7.1", "2.8.2"])
    func overrideKeepsItsFinding(version: String) throws {
        #expect(try issues(version, segment("OVR", 4, delete)).contains {
            $0.code == .conditionalComponentMissing && $0.location.segmentID == "OVR" && $0.location.fieldIndex == 4
        })
    }

    @Test("\"\" is a delete indicator on a data segment and not on a control segment, on each version's reading of its sections",
          arguments: [("PID", true), ("NTE", true), ("ADD", true), ("DSP", true), ("RDT", true), ("QRI", true),
                      ("MSH", false), ("MSA", false), ("ERR", false), ("DSC", false), ("BHS", false), ("BTS", false), ("FHS", false),
                      ("FTS", false), ("QAK", false), ("RDF", false), ("QID", false), ("QPD", false), ("RCP", false), ("OVR", false),
                      ("SFT", false), ("UAC", false), ("SGH", false), ("SGT", false),
                      ("QRD", false), ("QRF", false), ("URD", false), ("URS", false),
                      ("EQL", false), ("VTQ", false), ("SPR", false), ("ERQ", false)])
    func deleteIndicatorBySegment(id: String, reads: Bool) throws {
        let message = try Parser().parse("MSH|^~\\&|HIS|FAC|LAB|FAC|20240301120000||ADT^A01^ADT_A01|MSG00001|P|2.4\rPID|\(delete)\r")
        let repetition = try #require(message.segments.last?.field(1)?.repetitions.first)
        #expect(Validator().isDeleteIndicator(repetition, segmentID: id) == reads)
    }

    // MARK: - From v2.6: the first field (or all fields)

    @Test("A data segment with \"\" first and nothing else real draws no field-level finding from v2.6",
          arguments: ["2.6", "2.7", "2.7.1", "2.8", "2.8.2"],
          ["IN1|\"\"|\"\"", "PV1|\"\"", "OBX|\"\"", "NK1|\"\"|\"\"|\"\"|\"\"|", "NK1|\"\"|", "DG1|\"\"", "GT1|\"\""])
    func firstFieldIsADeleteSegment(version: String, line: String) throws {
        let found = try fieldFindings(version, line)
        #expect(found.isEmpty, "\(found.map(\.message))")
    }

    @Test("From v2.6 \"\" first with a real value elsewhere, or a later field alone, is checked as any segment is",
          arguments: ["2.6", "2.7", "2.7.1", "2.8", "2.8.2"],
          [("IN1|\"\"|A357", 3), ("OBX|\"\"|NM", 3), ("PV1|\"\"||A", 2), ("IN1||\"\"", 3), ("OBR|\"\" ", 4)])
    func realValueElsewhere(version: String, expected: (line: String, missing: Int)) throws {
        #expect(try fieldFindings(version, expected.line).contains {
            $0.code == .requiredFieldMissing && $0.location.fieldIndex == expected.missing
        })
    }

    @Test("A control segment with \"\" first is not a delete segment from v2.6",
          arguments: ["2.6", "2.7.1", "2.8.2"], [("MSA", 2), ("ERR", 3), ("SFT", 2), ("UAC", 2), ("QID", 2), ("RDF", 2)])
    func controlSegmentIsNotADeleteSegment(version: String, expected: (id: String, requiredField: Int)) throws {
        #expect(try fieldFindings(version, "\(expected.id)|\(delete)").contains {
            $0.code == .requiredFieldMissing && $0.location.fieldIndex == expected.requiredField
        })
    }

    @Test("QRD with \"\" first is not a delete segment on v2.6, its last version")
    func queryDefinitionIsNotADeleteSegment() throws {
        #expect(try fieldFindings("2.6", "QRD|\(delete)").contains { $0.code == .requiredFieldMissing })
    }

    /// A caller's Z grammar reads the same way: ZAU-2 is required, and on a delete segment nothing asks for it.
    @Test("A caller's Z-segment follows the version's reading of the first field",
          arguments: [("2.5.1", true), ("2.6", false), ("2.7.1", false), ("2.8.2", false), ("2.9", false)],
          ["ZAU|\"\"", "ZAU|\"\"||\"\""])
    func callerZGrammar(expected: (version: String, fires: Bool), line: String) throws {
        let options = ZSegmentGrammarTests.options([ZSegmentGrammar(ZSegmentGrammarTests.zau())])
        let found = try ZSegmentGrammarTests.issues(TestWires.msh("ADT^A01^ADT_A01", expected.version) + line + "\r", options)
        #expect(found.contains { $0.code == .requiredFieldMissing && $0.location.fieldIndex == 2 } == expected.fires)
    }

    /// The three printed rows: CX.5 at IN1-3 on `IN1|2|""|""`, read here on the two prints that require it.
    @Test("IN1|2|\"\"|\"\" has a real first field, so its fields are read, and meets them", arguments: ["2.7", "2.7.1", "2.8", "2.8.2"])
    func keyedDelete(version: String) throws {
        #expect(try fieldFindings(version, "IN1|2|\(delete)|\(delete)").isEmpty)
        #expect(try fieldFindings(version, "IN1|2").contains { $0.code == .requiredFieldMissing && $0.location.fieldIndex == 3 })
    }

    // MARK: - v2.3 to v2.5.1: all fields, and the first field alone is not one

    @Test("The first field alone stays checked on v2.3 to v2.5.1, whose prints do not give it",
          arguments: ["2.3", "2.3.1", "2.4", "2.5.1"],
          [("PV1|\"\"", 2), ("IN1|\"\"|\"\"", 3)])
    func firstFieldAloneStaysChecked(version: String, expected: (line: String, field: Int)) throws {
        #expect(try fieldFindings(version, expected.line).contains {
            $0.code == .requiredFieldMissing && $0.location.fieldIndex == expected.field
        })
    }

    /// Every field a data segment defines, each holding "". PYE-3 to 6 drew `conditionalFieldProhibited` from v2.6 before this,
    /// which a lone "" still draws.
    @Test("A data segment with \"\" in all its fields draws no field-level finding",
          arguments: ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.7", "2.7.1", "2.8", "2.8.2"])
    func allFields(version: String) throws {
        var checked = 0
        for (id, grammar) in try grammars(version) where !Validator.messageControlSegments.contains(id) {
            guard let last = grammar.fields.map(\.index).max() else { continue }
            checked += 1
            let found = try fieldFindings(version, id + String(repeating: "|\(delete)", count: last))
            #expect(found.isEmpty, "\(version) \(id): \(found.map(\.message))")
        }
        #expect(checked > 50)
    }

    /// A gap is not "all fields" on v2.3 to v2.5.1, so PV1-2, required and empty, stays a finding.
    @Test("PV1 with \"\" in all fields but one is no delete segment on v2.3 to v2.5.1", arguments: ["2.3", "2.3.1", "2.4", "2.5.1"])
    func allFieldsWithAGap(version: String) throws {
        let last = try #require(try grammars(version)["PV1"]?.fields.map(\.index).max())
        var fields = Array(repeating: delete, count: last)
        fields[1] = ""
        #expect(try fieldFindings(version, "PV1|" + fields.joined(separator: "|")).contains {
            $0.code == .requiredFieldMissing && $0.location.fieldIndex == 2
        })
    }

    @Test("A control segment with \"\" in all its fields is not a delete segment", arguments: ["2.5.1", "2.6", "2.7.1"])
    func allFieldsOnAControlSegment(version: String) throws {
        let last = try #require(try grammars(version)["ERR"]?.fields.map(\.index).max())
        #expect(try !fieldFindings(version, "ERR" + String(repeating: "|\(delete)", count: last)).isEmpty)
    }

    /// The prints' own wires, as sent: the 19-field DG1, and v2.6's and v2.7.1's NK1 pair.
    @Test("The printed DG1 delete wire draws no field-level finding", arguments: ["2.3", "2.3.1", "2.4"])
    func printedDG1(version: String) throws {
        let found = try fieldFindings(version, "DG1" + String(repeating: "|\(delete)", count: 19))
        #expect(found.isEmpty, "\(found.map(\.message))")
    }

    /// v2.5.1 p2-36 prints the same 19 fields, but its DG1 defines 21, so the wire is short of "all fields". It draws no error, and
    /// keeps the deprecation warnings at the B fields it populates: registered as Blocking (ruling R56).
    @Test("v2.5.1's printed DG1 delete wire draws no error, only deprecation warnings")
    func printedDG1OnV251() throws {
        let found = try fieldFindings("2.5.1", "DG1" + String(repeating: "|\(delete)", count: 19))
        #expect(!found.isEmpty && found.allSatisfy { $0.severity == .warning && $0.code == .fieldNotSupported })
    }

    @Test("The printed NK1 delete wires draw no field-level finding",
          arguments: ["2.6", "2.7", "2.7.1"], ["NK1|\"\"|\"\"|\"\"|\"\"|", "NK1|\"\"|"])
    func printedNK1(version: String, line: String) throws {
        let found = try fieldFindings(version, line)
        #expect(found.isEmpty, "\(found.map(\.message))")
    }

    // MARK: - The AU locale

    private func auIssues(_ version: String, type: String = "ORU^R01^ORU_R01", _ line: String) throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|LAB|FAC|GP|FAC|20240101||\(type)|MSG|P|\(version)\r\(line)\r"
        let message = try Parser(locale: .auLocalisation).parse(wire)
        return Validator(options: .default, locale: .auLocalisation).validate(message).issues
    }

    /// OBR-24 is profile-required on an ORU. From v2.6 the delete segment's guard reaches it; on v2.4, the locale's own version,
    /// the first field alone is no delete segment, so it stays.
    @Test("Under the AU locale OBR|\"\" follows the version's print", arguments: [("2.4", 1), ("2.6", 0), ("2.8.2", 0)])
    func auFirstField(version: String, count: Int) throws {
        #expect(try auIssues(version, "OBR|\(delete)").filter {
            $0.location.segmentID == "OBR" && $0.location.fieldIndex == 24
        }.count == count)
    }

    /// v2.4 2.15.4.1 p2-104, "for all fields", on the locale's own version: the AU rules run inside the field loop, so this wire skips
    /// them too. ADRM p396 warns that implementations "incorrectly use null ("") values, sometimes even as a dummy empty value for
    /// Required fields". Registered for the owner.
    @Test("Under the AU locale on v2.4, \"\" in all fields draws no field-level finding", arguments: ["PID", "OBR", "ORC", "PV1", "OBX"])
    func auAllFields(id: String) throws {
        let last = try #require(SegmentGrammarTable.v2_4[id]?.fields.map(\.index).max())
        let found = try auIssues("2.4", id + String(repeating: "|\(delete)", count: last)).filter {
            $0.location.segmentID == id && $0.location.fieldIndex != nil
        }
        #expect(found.isEmpty, "\(found.map(\.message))")
    }

    /// The AU rules reported at one field, as `localeRule` citations.
    private static func profileRules(_ issues: [ValidationIssue], _ id: String, _ field: Int) -> [String] {
        issues.compactMap {
            guard $0.location.segmentID == id, $0.location.fieldIndex == field,
                  case .profileConstraintViolation(let rule) = $0.code else { return nil }
            return rule
        }
    }

    /// ADRM p274 prints OBR-12 = "" on a delete message. A lone "" is the null, which has no components, so the profile's
    /// component rules skip it, as the base grammar does (the owner's ruling). The identifiers of the printed line are left out;
    /// only OBR-4 and OBR-12 matter here.
    @Test("ADRM p274's OBR-12 = \"\" draws no finding at OBR-12, under the locale or without it")
    func auPrintedOBR12() throws {
        let line = "OBR|1|||ALL^ALL^NATA2623||||||||\(delete)"
        let found = try auIssues("2.4", line).filter { $0.location.segmentID == "OBR" && $0.location.fieldIndex == 12 }
        #expect(found.isEmpty, "\(found.map(\.message))")
        #expect(try issues("2.4", line).filter { $0.location.segmentID == "OBR" && $0.location.fieldIndex == 12 }.isEmpty)
    }

    /// Each row is a component rule, from a composite override (CE, XCN, CX) or a field override (EI completeness, PRD-7.3),
    /// and a real value that breaks it. The ADRM states each of a component: p451 "the <name of the coding system> must also be
    /// specified", p455 "XCN <assigning authority (HD)> component must be valued", p449 "CX <assigning authority (HD)>
    /// component must be valued", p419 the EI's "Namespace ID (second component) ... must be populated", p473 "<other
    /// qualifying info (ST)> must be a valued from HL7 Table 0203".
    @Test("Under the AU locale a lone \"\" draws no component rule, and a real value still does",
          arguments: [("ORU^R01^ORU_R01", "OBR", 12, "X^Danger", "HL7au:00044.4.1"),
                      ("ORU^R01^ORU_R01", "OBR", 16, "123^Smith", "HL7au:00044.7.2"),
                      ("ORU^R01^ORU_R01", "PID", 3, "123", "HL7au:00044.1.2"),
                      ("ORU^R01^ORU_R01", "ORC", 2, "123", "HL7au:000005"),
                      ("REF^I12^REF_I12", "PRD", 7, "123^AUSHICPR", "HL7au:00104.7.3.1")])
    func auComponentRulesSkipTheNull(type: String, id: String, field: Int, real: String, rule: String) throws {
        for null in [delete, delete + "^"] {
            let found = Self.profileRules(try auIssues("2.4", type: type, segment(id, field, null)), id, field)
            #expect(found.isEmpty, "\(null): \(found)")
        }
        let once = Self.profileRules(try auIssues("2.4", type: type, segment(id, field, real)), id, field)
        #expect(once.contains { $0.hasPrefix(rule) }, "\(once)")
        // The gate reads each repetition, as the base grammar's does: beside the null, the real value draws its rules once.
        for value in ["\(delete)~\(real)", "\(real)~\(delete)"] {
            let found = Self.profileRules(try auIssues("2.4", type: type, segment(id, field, value)), id, field)
            #expect(found == once, "\(value): \(found)")
        }
    }

    /// Each row is a rule whose text speaks of the field's own value, and so keeps reading the null: ADRM p396 warns that
    /// implementations "incorrectly use null ("") values, sometimes even as a dummy empty value for Required fields". p443 "the
    /// field OBR-24 ... must be valued and must have values from HL7 table 0074"; p421 "the OBX-2 Value Type field must match its
    /// corresponding display format"; p490 "OBX-5 must be valued as" the VMR header's literal.
    @Test("Under the AU locale a rule on the field's own value still reads a lone \"\"",
          arguments: [("ORU^R01^ORU_R01", "OBR|1" + String(repeating: "|", count: 23) + "@", "OBR", 24, "HL7au:000032 "),
                      ("ORU^R01^ORU_R01", "OBX|1|@|HTML^Display format in HTML^AUSPDI||x", "OBX", 2, "HL7au:000008.1.3"),
                      ("REF^I12^REF_I12", "OBX|1|RP|74028-2^Report template ID^LN|1|@", "OBX", 5, "ADRM-prose:P-6")])
    func auFieldRulesReadTheNull(type: String, line: String, id: String, field: Int, rule: String) throws {
        for null in [delete, delete + "^"] {
            let found = Self.profileRules(try auIssues("2.4", type: type, line.replacingOccurrences(of: "@", with: null)), id, field)
            #expect(found.contains { $0.hasPrefix(rule) }, "\(null): \(found)")
        }
    }

    /// A field override's shapes and correspondences are component rules too. The shipped profile holds shapes on MSH only, a
    /// control segment, and every shipped override with either also holds a value set, so test profiles put them on OBR-12
    /// alone, and behind a required-component list whose gate is false.
    @Test("A field override's shapes and correspondences are read on their own, and skip a lone \"\"")
    func auFieldOverrideTracksSkipTheNull() throws {
        let shape = ComponentPattern(component: 1, prefix: "X", specCitation: "test-only:shape")
        let pair = ComponentCorrespondence(keyComponent: 1, valueComponent: 3, map: ["y": ["L"]], specCitation: "test-only:pair")
        let overrides = [
            (FieldOverride(segmentID: "OBR", fieldIndex: 12, componentPatterns: [shape]), "test-only:shape"),
            (FieldOverride(segmentID: "OBR", fieldIndex: 12, componentCorrespondences: [pair]), "test-only:pair"),
            (FieldOverride(segmentID: "OBR", fieldIndex: 12, condition: "messageCode = ADT", requiredComponents: [2],
                           componentPatterns: [shape]), "test-only:shape"),
        ]
        for (override, rule) in overrides {
            let profile = Profile(locale: .auLocalisation, fieldOverrides: [override])
            func found(_ value: String) throws -> [String] {
                let wire = "MSH|^~\\&|LAB|FAC|GP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|2.4\r\(segment("OBR", 12, value))\r"
                return Self.profileRules(Validator(locale: .auLocalisation, testProfileOverride: profile)
                    .validate(try Parser(locale: .auLocalisation).parse(wire)).issues, "OBR", 12)
            }
            #expect(try found("Y^text^Q") == [rule])
            #expect(try found(delete).isEmpty, "\(rule)")
            #expect(try found(delete + "^").isEmpty, "\(rule)")
        }
    }

    /// Every value set a field override holds on a data segment, by side. A new one fails this list, so its author decides
    /// whether its text speaks of the field (`constrainsField`: it reads a lone "") or of a component (it skips one). The flag
    /// is not read on a composite override's value set, since every composite rule is a component rule, so none sets it.
    @Test("Each AU field-override value set on a data segment is on a decided side")
    func auValueSetSides() {
        var sides: [Bool: [String]] = [:]
        for override in Profile.auADRM2021.fieldOverrides
        where !Validator.messageControlSegments.contains(override.segmentID) {
            for set in override.componentValueSets {
                let at = "\(override.segmentID)-\(override.fieldIndex).\(set.component)" + (set.subcomponent.map { ".\($0)" } ?? "")
                sides[set.constrainsField, default: []].append(at + " " + String(set.specCitation?.prefix { $0 != " " } ?? "-"))
            }
        }
        #expect(sides[true, default: []].sorted() == [
            "OBR-24.1 HL7au:000032", "OBR-24.1 HL7au:000032.2",
            "OBX-2.1 HL7au:000008.1.3", "OBX-2.1 HL7au:000008.1.3", "OBX-2.1 HL7au:000008.1.3", "OBX-2.1 HL7au:000008.1.3",
            "OBX-2.1 HL7au:000008.1.3", "OBX-2.1 ADRM-prose:P-6",
            "OBX-5.1 ADRM-prose:P-6", "OBX-5.2.1 ADRM-prose:P-6", "OBX-5.2.2 ADRM-prose:P-6", "OBX-5.2.3 ADRM-prose:P-6",
            "OBX-5.3 ADRM-prose:P-6", "OBX-5.4 ADRM-prose:P-6",
        ].sorted())
        #expect(sides[false, default: []].sorted() == [
            "OBX-3.1 HL7au:000008.1", "OBX-6.3 HL7au:00050.1.5", "PRD-7.2 HL7au:00104.7.2.1", "PRD-7.3 HL7au:00104.7.3.1",
        ].sorted())
        #expect(Profile.auADRM2021.compositeOverrides.allSatisfy { $0.componentValueSets.allSatisfy { !$0.constrainsField } })
    }

    /// Registered, Blocking: pins a misfire as it stands, for a later fix to move. `carriesNonNullValue` reads only `""` as the
    /// null, while `isDeleteIndicator` reads `""^` too (v2.3 p2-57 "are equivalent", v2.5.1 2.6.2 p2-17). So `""^` draws the
    /// AU "not used" warnings (ADRM pp228, 229, 343), and the base OBX-2 and OBX-5 prohibitions under OBX-11 = O on both
    /// locales, where `""` draws neither.
    @Test("Registered: \"\"^ still draws the prohibitions that exempt \"\"")
    func caretNullProhibitions() throws {
        for (type, id, field, rule) in [("ORU^R01^ORU_R01", "OBR", 26, "ADRM-prose:P-11"),
                                         ("ORU^R01^ORU_R01", "OBR", 29, "ADRM-prose:P-13"),
                                         ("REF^I12^REF_I12", "ORC", 24, "ADRM-prose:P-12")] {
            #expect(Self.profileRules(try auIssues("2.4", type: type, segment(id, field, delete)), id, field).isEmpty)
            let found = Self.profileRules(try auIssues("2.4", type: type, segment(id, field, delete + "^")), id, field)
            #expect(found.count == 1 && found[0].hasPrefix(rule), "\(found)")
        }
        for field in [2, 5] {
            var fields = ["OBX", "1", "ST", "X^Y^L", "", "", "", "", "", "", "", "O"]
            if field == 2 { fields[2] = "@" } else { fields[5] = "@" }
            func prohibited(_ null: String) throws -> [ValidationIssue] {
                let line = fields.joined(separator: "|").replacingOccurrences(of: "@", with: null)
                return try (issues("2.4", line) + auIssues("2.4", line)).filter {
                    $0.location.segmentID == "OBX" && $0.location.fieldIndex == field && $0.code == .conditionalFieldProhibited
                }
            }
            #expect(try prohibited(delete).isEmpty)
            #expect(try prohibited(delete + "^").map(\.severity) == [.error, .error], "OBX-\(field)")
        }
    }

    /// MSH is a message control segment, where "" is no delete indicator (`Validator.isDeleteIndicator`), so the CE rule still
    /// reads MSH-19 = "" as a code with no coding system.
    @Test("Under the AU locale a control segment's component rule still reads \"\"", arguments: ["\"\"", "\"\"^"])
    func auControlSegmentKeepsItsRules(null: String) throws {
        let wire = "MSH|^~\\&|LAB|FAC|GP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|2.4|||||||\(null)\r"
        let found = Self.profileRules(Validator(options: .default, locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(wire)).issues, "MSH", 19)
        #expect(found.contains { $0.hasPrefix("HL7au:00044.4.1") }, "\(found)")
    }
}
