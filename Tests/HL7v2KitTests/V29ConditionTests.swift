// V29ConditionTests.swift
// The v2.9 conditions that are not v2.8.2's: fields new in v2.9 and sentences v2.9 rewrote.
// Each case cites the December 2019 chapters (technical correction of January 2021), section
// and footer page. One wire must report the position, the other must not.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("v2.9 conditions")
struct V29ConditionTests {
    enum Kind: Sendable { case missing, prohibited }

    struct Rule: Sendable, CustomTestStringConvertible {
        let seg: String
        let index: Int
        let kind: Kind
        let fires: String
        let silent: String
        var testDescription: String { "\(seg)-\(index) \(kind)" }

        init(_ seg: String, _ index: Int, _ kind: Kind, fires: [String], silent: [String],
             type: String = "ADT^A01^ADT_A01", silentType: String? = nil) {
            self.seg = seg
            self.index = index
            self.kind = kind
            self.fires = TestWires.msh(type, "2.9") + fires.map { $0 + "\r" }.joined()
            self.silent = TestWires.msh(silentType ?? type, "2.9") + silent.map { $0 + "\r" }.joined()
        }
    }

    private static func s(_ id: String, _ fields: [Int: String]) -> String { TestWires.segment(id, fields) }

    /// The MSH of a v2.9 ADT^A01 with `extra` fields.
    private static func header(_ extra: [Int: String]) -> String {
        var fields = [3: "SND", 4: "FAC", 5: "RCV", 6: "FAC", 7: "20260930120000", 9: "ADT^A01^ADT_A01", 10: "MSG1", 11: "P", 12: "2.9"]
        fields.merge(extra) { _, new in new }
        return "MSH|^~\\&" + (3...fields.keys.max()!).map { "|" + (fields[$0] ?? "") }.joined() + "\r"
    }

    private static func reported(_ wire: String, _ seg: String, _ index: Int, _ kind: Kind) throws -> Bool {
        try Validator().validate(Parser().parse(wire)).issues.contains {
            $0.location.segmentID == seg && $0.location.fieldIndex == index
                && $0.code == (kind == .missing ? .conditionalFieldMissing : .conditionalFieldProhibited)
        }
    }

    static let rules: [Rule] = [
        // CH02 2.14.10.3 p77: "when NTE-9 is populated, the sending system SHALL also populate ... NTE-3"
        Rule("NTE", 3, .missing, fires: [s("NTE", [9: "C^Coded^L"])], silent: [s("NTE", [1: "1"])]),
        // CH03 3.4.14.10 p202: "conditionally required when ARV-2 is NOT valued 'S'"
        Rule("ARV", 10, .missing, fires: [s("ARV", [2: "A^Add^HL70206", 3: "ALL"])], silent: [s("ARV", [2: "S^Snapshot^HL70206", 3: "ALL"])]),
        // CH05 5.5.2.1 p49: "the responding system is required to echo it back as the first field in ... QAK";
        // p38: "The query definition segment is echoed back in the response."
        Rule("QAK", 1, .missing, fires: ["MSA|AA|M1", s("QAK", [2: "OK"]), s("QPD", [1: "Q21", 2: "T1"])],
             silent: ["MSA|AA|M1", s("QAK", [1: "T1", 2: "OK"]), s("QPD", [1: "Q21", 2: "T1"])], type: "RSP^K21^RSP_K21"),
        Rule("QAK", 1, .missing, fires: ["MSA|AA|M1", s("QAK", [2: "OK"]), s("QPD", [1: "Q21", 2: "T1"])],
             silent: ["MSA|AA|M1", s("QAK", [2: "OK"]), s("QPD", [1: "Q21"])], type: "RSP^K21^RSP_K21"),
        // CH04 4.17.1.1-2 pp174-175: "mandatory except when using an eligibility message type in which only
        // DON-9, DON-10, and DON-11 are populated". DPR is the donation itself; the RSP^K34 row pins that a
        // returned donor record, which the print does not limit (4.16.8-9 pp165-166), is left out.
        Rule("DON", 1, .missing, fires: [s("DON", [3: "20260101"])], silent: [s("DON", [9: "Y"])], type: "DPR^O48^DPR_O48", silentType: "DEL^O46^DEL_O46"),
        Rule("DON", 2, .missing, fires: [s("DON", [3: "20260101"])], silent: [s("DON", [9: "Y"])], type: "DPR^O48^DPR_O48", silentType: "DEL^O46^DEL_O46"),
        Rule("DON", 1, .missing, fires: [s("DON", [3: "20260101"])], silent: [s("DON", [9: "Y"])], type: "DPR^O48^DPR_O48", silentType: "RSP^K34^RSP_O34"),
        // CH07 7.3.3 p12: QRY/ORF "withdrawn as of v 2.7", so the no-ORC leg names ORU alone.
        Rule("OBR", 2, .missing, fires: [s("OBR", [1: "1", 4: "GLU^Glucose^L"])], silent: [s("OBR", [1: "1", 4: "GLU^Glucose^L"])], type: "ORU^R01^ORU_R01", silentType: "ORF^R04^ORF_R04"),
        Rule("OBR", 3, .missing, fires: [s("OBR", [1: "1", 4: "GLU^Glucose^L"])], silent: [s("OBR", [1: "1", 4: "GLU^Glucose^L"])], type: "ORU^R01^ORU_R01", silentType: "ORF^R04^ORF_R04"),
        // CH07 7.4.3.11 p80: "If the specimen role value is "G" then ... (SPM-13) must be valued"; any repetition.
        Rule("SPM", 13, .missing, fires: [s("SPM", [1: "1", 11: "G"])], silent: [s("SPM", [1: "1", 11: "L"])], type: "OUL^R22^OUL_R22"),
        Rule("SPM", 13, .missing, fires: [s("SPM", [1: "1", 11: "P~G"])], silent: [s("SPM", [1: "1", 11: "P"])], type: "OUL^R22^OUL_R22"),
        // CH06 6.5.8.29-31 p129, printed C(R/X), C(RE/X), C(R/X): "required if IN3-28 is populated"
        Rule("IN3", 29, .missing, fires: [s("IN3", [28: "20260101"])], silent: [s("IN3", [28: "20260101", 29: "1"])]),
        Rule("IN3", 29, .prohibited, fires: [s("IN3", [29: "1"])], silent: [s("IN3", [28: "20260101", 29: "1"])]),
        Rule("IN3", 31, .missing, fires: [s("IN3", [28: "20260101"])], silent: [s("IN3", [28: "20260101", 31: "7"])]),
        Rule("IN3", 31, .prohibited, fires: [s("IN3", [31: "7"])], silent: [s("IN3", [28: "20260101", 31: "7"])]),
        Rule("IN3", 30, .prohibited, fires: [s("IN3", [30: "1"])], silent: [s("IN3", [28: "20260101", 30: "1"])]),
        // CH07 7.4.2.2 p59: "This field is required if OBX-5, Observation Value, is valued."
        Rule("OBX", 2, .missing, fires: [s("OBX", [1: "1", 3: "O^Obs^L", 5: "5", 11: "F"])], silent: [s("OBX", [1: "1", 3: "O^Obs^L", 11: "F"])]),
        // CH07 7.4.2.32 p75: "This field must be blank if OBX-5, Observation Value, is valued."
        Rule("OBX", 32, .prohibited, fires: [s("OBX", [1: "1", 2: "NM", 3: "O^Obs^L", 5: "5", 11: "F", 32: "A"])], silent: [s("OBX", [1: "1", 3: "O^Obs^L", 11: "F", 32: "A"])]),
        // CH07 7.4.2.11 p67: dynamic specification, "OBX-2 and OBX-5 valued with null"
        Rule("OBX", 5, .prohibited, fires: [s("OBX", [1: "1", 2: "NM", 3: "O^Obs^L", 5: "5", 11: "O"])], silent: [s("OBX", [1: "1", 3: "O^Obs^L", 11: "O"])]),
        // CH08 8.8.16.2-3 p65, printed C(R/X): "Required if OMC-3 is valued" and the reverse
        Rule("OMC", 2, .missing, fires: [s("OMC", [3: "K1"])], silent: [s("OMC", [2: "A", 3: "K1"])]),
        Rule("OMC", 2, .prohibited, fires: [s("OMC", [2: "A"])], silent: [s("OMC", [2: "A", 3: "K1"])]),
        Rule("OMC", 3, .missing, fires: [s("OMC", [2: "A"])], silent: [s("OMC", [2: "A", 3: "K1"])]),
        Rule("OMC", 3, .prohibited, fires: [s("OMC", [3: "K1"])], silent: [s("OMC", [2: "A", 3: "K1"])]),
        // CH08 8.14.2.16 p124: "shall be valued if CRT-17 Parent of Corporation is valued" (CRT is CTR misprinted)
        Rule("CTR", 16, .missing, fires: [s("CTR", [1: "C1", 17: "PARENT"])], silent: [s("CTR", [1: "C1"])]),
        // CH13 13.4.4.1-2 p47: "It is optional in queries INR^U14 and required in all other messages."
        Rule("INV", 1, .missing, fires: [s("INV", [3: "SC"])], silent: [s("INV", [3: "SC"])], type: "INR^U06^INR_U06", silentType: "INR^U14^INR_U14"),
        Rule("INV", 2, .missing, fires: [s("INV", [1: "ID"])], silent: [s("INV", [1: "ID"])], type: "INU^U05^INU_U05", silentType: "INR^U14^INR_U14"),
        // CH13 13.4.4.21-22 p51: "optional when INV-3 ... is not populated and prohibited otherwise"; INV-22 on INV-21
        Rule("INV", 21, .prohibited, fires: [s("INV", [1: "I", 2: "S", 3: "SC", 21: "T"])], silent: [s("INV", [1: "I", 2: "S", 21: "T"])]),
        Rule("INV", 22, .prohibited, fires: [s("INV", [1: "I", 2: "S", 22: "5"])], silent: [s("INV", [1: "I", 2: "S", 21: "T", 22: "5"])]),
        // CH17 17.9.1.2-3 p66: "Either DEV-2 ... or DEV-3 ... must be valued, or both are valued."
        Rule("DEV", 2, .missing, fires: [s("DEV", [1: "A"])], silent: [s("DEV", [1: "A", 3: "T"])]),
        Rule("DEV", 3, .missing, fires: [s("DEV", [1: "A"])], silent: [s("DEV", [1: "A", 2: "ID"])]),
        // CH08 8.5.1.6 p10 (printed R): "Required for MFN-Master File Notification message."
        Rule("MFI", 6, .missing, fires: [s("MFI", [1: "M", 3: "UPD"])], silent: [s("MFI", [1: "M", 3: "UPD"])], type: "MFN^M02^MFN_M02", silentType: "MFK^M02^MFK_M01"),
        // CH07 7.8.1.8 p121 (printed R): "required for the patient registration trigger event (C01)"
        Rule("CSR", 8, .missing, fires: [s("CSR", [1: "S", 4: "P"])], silent: [s("CSR", [1: "S", 4: "P"])], type: "CRM^C01^CRM_C01", silentType: "CRM^C02^CRM_C01"),
        // Usage rules on fields printed O: CH04 4.5.1.25 p65, CH07 7.4.2.12 p67, CH04A 4A.4.2.6 p53
        Rule("ORC", 25, .prohibited, fires: [s("ORC", [1: "NW", 2: "P", 25: "M"])], silent: [s("ORC", [1: "NW", 2: "P", 5: "IP", 25: "M"])]),
        Rule("OBX", 12, .prohibited, fires: [s("OBX", [1: "1", 3: "O", 11: "F", 12: "20260101"])], silent: [s("OBX", [1: "1", 3: "O", 7: "1-5", 11: "F", 12: "20260101"])]),
        Rule("RXR", 6, .prohibited, fires: [s("RXR", [1: "PO", 6: "M"])], silent: [s("RXR", [1: "PO", 2: "S", 6: "M"])]),
    ]

    @Test("Reports the position when the rule holds, and not otherwise", arguments: rules)
    func firesAndStaysSilent(rule: Rule) throws {
        #expect(try Self.reported(rule.fires, rule.seg, rule.index, rule.kind), "fires")
        #expect(try !Self.reported(rule.silent, rule.seg, rule.index, rule.kind), "silent")
    }

    @Test("MSH-15 and MSH-16: both or neither (CH02 2.14.9.15 p70)")
    func acknowledgmentPair() throws {
        #expect(try Self.reported(Self.header([15: "AL"]), "MSH", 16, .missing))
        #expect(try Self.reported(Self.header([16: "NE"]), "MSH", 15, .missing))
        for silent in [Self.header([:]), Self.header([15: "AL", 16: "NE"])] {
            #expect(try !Self.reported(silent, "MSH", 15, .missing))
            #expect(try !Self.reported(silent, "MSH", 16, .missing))
        }
    }

    /// CH07 7.4.2.2 p59: "When OBX-5, Observation Value, is not valued, OBX-2 Value Type MAY be valued".
    /// CH07 7.4.2.11 p67 asks for "null", which CH02 2.5.3.1 p9 says v2.x no longer defines, so neither
    /// field is demanded under OBX-11 = O, and neither OBX-2 nor the delete indicator is refused there.
    @Test("OBX-11 = O demands nothing of OBX-2 and OBX-5, and refuses only a real OBX-5")
    func dynamicSpecification() throws {
        let unvalued = TestWires.wire("ORU^R01^ORU_R01", "2.9", Self.s("OBX", [1: "1", 2: "NM", 3: "O", 11: "O"]))
        #expect(try !Self.reported(unvalued, "OBX", 2, .prohibited))
        #expect(try !Self.reported(unvalued, "OBX", 5, .missing))
        let indicator = TestWires.wire("ORU^R01^ORU_R01", "2.9", Self.s("OBX", [1: "1", 2: "\"\"", 3: "O", 5: "\"\"", 11: "O"]))
        #expect(try !Self.reported(indicator, "OBX", 2, .prohibited))
        #expect(try !Self.reported(indicator, "OBX", 5, .prohibited))
    }

    /// CH02 2.5.3.1 pp8-9 gives "valued" as a synonym of Populated, and lists "Populated with Delete
    /// Indicator" as a state of its own, so OBX-2's and OBX-32's "is valued" (CH07 7.4.2.2 p59, 7.4.2.32 p75)
    /// does not reach a lone `""` in OBX-5. OBX-11 = D is the case that sends one (7.4.2.11 p66).
    @Test("The delete indicator in OBX-5 is not a value: OBX-2 is not demanded, OBX-32 is not refused")
    func deleteIndicator() throws {
        func wire(status: String, value: String, absentReason: String = "") -> String {
            TestWires.wire("ORU^R01^ORU_R01", "2.9", Self.s("OBX", [1: "1", 3: "O", 5: value, 11: status, 32: absentReason]))
        }
        for status in ["D", "O"] {
            #expect(try !Self.reported(wire(status: status, value: "\"\""), "OBX", 2, .missing), "OBX-11 = \(status)")
            #expect(try !Self.reported(wire(status: status, value: "\"\"", absentReason: "A"), "OBX", 32, .prohibited), "OBX-11 = \(status)")
        }
        // A lone indicator is the rule's whole exception: one real repetition is still a value.
        #expect(try Self.reported(wire(status: "F", value: "\"\"~5"), "OBX", 2, .missing))
        #expect(try Self.reported(wire(status: "F", value: "\"\"~5", absentReason: "A"), "OBX", 32, .prohibited))
        // An empty repetition adds no value: `""~` and `~""` read as `""`, and `5~` as `5`.
        for value in ["\"\"~", "~\"\""] {
            #expect(try !Self.reported(wire(status: "F", value: value), "OBX", 2, .missing), "\(value)")
            #expect(try !Self.reported(wire(status: "F", value: value, absentReason: "A"), "OBX", 32, .prohibited), "\(value)")
        }
        for value in ["5", "5~"] {
            #expect(try Self.reported(wire(status: "F", value: value), "OBX", 2, .missing), "\(value)")
            #expect(try Self.reported(wire(status: "F", value: value, absentReason: "A"), "OBX", 32, .prohibited), "\(value)")
        }
    }

    /// CH07 7.4.3.13 p81: "would only be valued if SPM-11 Specimen Role has the value "G" or "L"".
    @Test("SPM-13 warns outside roles G and L", arguments: [("P", true), ("G", false), ("L", false), ("", true)])
    func groupedSpecimenCount(role: String, warns: Bool) throws {
        let wire = TestWires.wire("OUL^R22^OUL_R22", "2.9", Self.s("SPM", [1: "1", 11: role, 13: "3"]))
        let hits = Validator().validate(try Parser().parse(wire)).issues.filter {
            $0.code == .conditionalFieldProhibited && $0.location.segmentID == "SPM" && $0.location.fieldIndex == 13
        }
        #expect(hits.count == (warns ? 1 : 0), "role \(role)")
        #expect(hits.allSatisfy { $0.severity == .warning })
    }

    private static func envelope(_ id: String, _ fields: [Int: String]) -> String {
        "\(id)|^~\\&" + (3...fields.keys.max()!).map { "|" + (fields[$0] ?? "") }.joined()
    }

    private static func batchMessage() -> String {
        "MSH|^~\\&|SYN|FAC|HOSP|FAC|20240101120000||ADT^A01^ADT_A01|M1|P|2.9\rPID|1"
    }

    /// CH02 2.14.2.15 p56 and 2.14.6.15 p64. The "any contained" legs are registered; the legs on the
    /// envelope's own fields are what a batch can check, since BatchValidator reads one segment at a time.
    @Test("BHS-15 and FHS-15 are required when their own 16 or 17 is valued",
          arguments: [("BHS", "BTS"), ("FHS", "FTS")])
    func envelopeClassification(id: String, trailer: String) throws {
        func hit(_ fields: [Int: String]) throws -> Bool {
            let file = [Self.envelope(id, fields), Self.batchMessage(), "\(trailer)|1"].joined(separator: "\r") + "\r"
            return try BatchValidator().validate(BatchParser().parse(file)).batchIssues.contains {
                $0.code == .conditionalFieldMissing && $0.location.segmentID == id && $0.location.fieldIndex == 15
            }
        }
        #expect(try hit([16: "SH"]))
        #expect(try hit([17: "Restricted"]))
        #expect(try !hit([3: "APP"]))
        #expect(try !hit([15: "R", 16: "SH"]))
    }

    @Test("The v2.9 envelope tables read no other segment, so one-segment checks hold")
    func envelopePredicatesAreSelfContained() throws {
        let references = try NSRegularExpression(pattern: #"\b([A-Z][A-Z0-9]{2})-\d+"#)
        for id in ["FHS", "BHS", "BTS", "FTS"] {
            for field in try #require(SegmentGrammarTable.v2_9[id]).fields {
                let text = [field.condition, field.prohibitedWhen].compactMap { $0 }.joined(separator: " ")
                for match in references.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    #expect((text as NSString).substring(with: match.range(at: 1)) == id, "\(id)-\(field.index)")
                }
            }
        }
    }

    static let limitationsRegister = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("private/design/permanent-limitations-register.md")

    // The register is a private record outside the repository, so this guard runs only in a checkout with private/.
    @Test("Every registered bare C has a row in the permanent-limitations register",
          .enabled(if: FileManager.default.fileExists(atPath: limitationsRegister.path), "the register is a private record, absent here"))
    func registeredReasonsAreWritten() throws {
        let register = try String(contentsOf: Self.limitationsRegister, encoding: .utf8)
        let unnamed = V29GrammarTests.registeredBareConditionals.filter { !BareConditionalGuardTests.names(register, $0) }
        #expect(unnamed.isEmpty, "\(unnamed.sorted())")
    }
}
