// V291ConditionTests.swift
// HL7 v2.9.1's conditions, against the September 2024 print. Pages are footers. CH02 is numbered 2.13.x here and
// CH02A 2A.2.N, one lower than v2.9's. Each definition v2.9 carries a rule for has the same words here by script, or
// differs only by page furniture in the differences read, so those rules are v2.9's strings; GSP-3, GSR-3 and GSC-3 are new.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("v2.9.1 conditions")
struct V291ConditionTests {
    private var grammar: [String: SegmentGrammar] { SegmentGrammarTable.v2_9_1 }

    private func issues(_ type: String = "ADT^A01^ADT_A01", _ lines: String...) throws -> [ValidationIssue] {
        let wire = TestWires.msh(type, "2.9.1") + lines.map { $0 + "\r" }.joined()
        return Validator().validate(try Parser().parse(wire)).issues
    }

    @Test("Each rule and optionality on a field v2.9 also has is v2.9's")
    func rulesCarry() {
        for (id, segment) in grammar {
            guard let earlier = SegmentGrammarTable.v2_9[id] else { continue }
            for field in segment.fields {
                let position = "\(id)-\(field.index)"
                guard let old = earlier.field(field.index) else {
                    #expect(["IN1-56", "TXA-29", "TXA-30", "TXA-31"].contains(position), "\(position)")
                    #expect(field.optionality == .optional && field.condition == nil, "\(position)")
                    continue
                }
                #expect(field.condition == old.condition, "\(position)")
                #expect(field.prohibitedWhen == old.prohibitedWhen, "\(position)")
                #expect(field.prohibitedSeverity == old.prohibitedSeverity, "\(position)")
                #expect(field.additionalProhibitions.map(\.condition) == old.additionalProhibitions.map(\.condition), "\(position)")
                #expect(field.optionality == old.optionality, "\(position)")
            }
        }
    }

    @Test("The fields printed C with no rule are v2.9's, each with a register row")
    func noNewBareConditionals() {
        #expect(bareConditionals(grammar) == V29GrammarTests.registeredBareConditionals)
    }

    /// The wires v2.9's own rules were tested on, declaring 2.9.1: one reports the position, the other does not.
    @Test("v2.9's rule wires hold on 2.9.1", arguments: V29ConditionTests.rules)
    func carriedRuleFiresAndStaysSilent(rule: V29ConditionTests.Rule) throws {
        func reported(_ wire: String) throws -> Bool {
            let declared = wire.replacingOccurrences(of: "|P|2.9", with: "|P|2.9.1")
            let message = try Parser().parse(declared)
            #expect(message.version == .v2_9_1)
            return Validator().validate(message).issues.contains {
                $0.location.segmentID == rule.seg && $0.location.fieldIndex == rule.index
                    && $0.code == (rule.kind == .missing ? .conditionalFieldMissing : .conditionalFieldProhibited)
            }
        }
        #expect(try reported(rule.fires), "fires")
        #expect(try !reported(rule.silent), "silent")
    }

    // MARK: - GSP-3, GSR-3, GSC-3

    /// CH03 3.4.19.3 p222, 3.4.20.3 p224, 3.4.21.3 p227: "conditionally required when the Action Code in GSx-2 indicates
    /// data is not being sent in Snapshot Mode (valued "S")". The rest of each wire meets the segment's R fields.
    @Test("An instance identifier is required unless the action code is S",
          arguments: [("GSP", "76691-5^Gender identity^LN|33791000087105^Identifies as nonbinary gender^SCT"),
                      ("GSR", "F^Female^HL70001"),
                      ("GSC", "specified^Specified^L||PR1^1")])
    func instanceIdentifier(id: String, rest: String) throws {
        func missing(_ line: String) throws -> Bool {
            try issues("ADT^A01^ADT_A01", line).contains {
                $0.code == .conditionalFieldMissing && $0.location.segmentID == id && $0.location.fieldIndex == 3
            }
        }
        #expect(grammar[id]?.field(3)?.condition == "\(id)-2 not in (S)")
        #expect(try missing("\(id)|1|A||\(rest)"))
        #expect(try missing("\(id)|1|U||\(rest)"))
        #expect(try !missing("\(id)|1|S||\(rest)"))
        #expect(try !missing("\(id)|1|A|G1^NS|\(rest)"))
    }

    /// CH03 3.4.19.7 p223, in snapshot mode.
    @Test("The print's GSP lines draw no finding at the segment",
          arguments: ["GSP|1|S||76691-5^Gender identity^LN|446151000124109^Identifies as male gender^SCT|20210101",
                      "GSP|3|S||90778-2^Personal pronouns – Reported^LN|LA29518-0^he/him/his/his/himself^LN|20210101^20210630",
                      "GSP|5|S||76690-7^Sexual orientation^LN|42035005^Bisexual^SCT|20210101"])
    func printedGSPLines(line: String) throws {
        let found = try issues("ADT^A01^ADT_A01", line).filter { $0.location.segmentID == "GSP" }
        #expect(found.isEmpty, "\(found.map(\.message))")
    }

    // MARK: - v2.9's rules outside its rule table, on a 2.9.1 wire

    /// CH02 2.13.2.15 p57 and 2.13.6.15 p65. BatchValidator reads one segment at a time, so the "any contained" legs stay registered.
    @Test("BHS-15 and FHS-15 are required when their own 16 or 17 is valued", arguments: [("BHS", "BTS"), ("FHS", "FTS")])
    func envelopeClassification(id: String, trailer: String) throws {
        func hit(_ tail: String) throws -> Bool {
            let header = "\(id)|^~\\&" + String(repeating: "|", count: 13) + tail
            let message = "MSH|^~\\&|SYN|FAC|HOSP|FAC|20240101120000||ADT^A01^ADT_A01|M1|P|2.9.1\rPID|1"
            let file = [header, message, "\(trailer)|1"].joined(separator: "\r") + "\r"
            return try BatchValidator().validate(BatchParser().parse(file)).batchIssues.contains {
                $0.code == .conditionalFieldMissing && $0.location.segmentID == id && $0.location.fieldIndex == 15
            }
        }
        #expect(try hit("|SH"))
        #expect(try hit("||Restricted"))
        #expect(try !hit(""))
        #expect(try !hit("R|SH"))
    }

    /// CH02 2.4.3.1 pp9-10 lists the delete indicator as a state of its own, so "is valued" at CH07 7.4.2.2 p62 and 7.4.2.32
    /// p78 does not reach a lone `""` in OBX-5, which OBX-11 = D sends (7.4.2.11 p69). One real repetition is still a value.
    @Test("The delete indicator in OBX-5 is not a value: OBX-2 is not demanded, OBX-32 is not refused")
    func deleteIndicatorInOBX5() throws {
        func found(_ value: String, reason: String = "") throws -> [ValidationIssue] {
            try issues("ORU^R01^ORU_R01", TestWires.segment("OBX", [1: "1", 3: "O", 5: value, 11: "D", 32: reason])).filter {
                $0.location.segmentID == "OBX" && ($0.location.fieldIndex == 2 || $0.location.fieldIndex == 32)
                    && ($0.code == .conditionalFieldMissing || $0.code == .conditionalFieldProhibited)
            }
        }
        #expect(try found("\"\"", reason: "A").isEmpty)
        #expect(try found("\"\"~5", reason: "A").map(\.location.fieldIndex).sorted { ($0 ?? 0) < ($1 ?? 0) } == [2, 32])
    }

    // MARK: - SN.2 and ERL.3, which Task 10 could not run on the wire

    /// 2A.2.71.2 p80: "SN.2 is also conditionally required if the SN.1 (Comparator) component is populated"; the table
    /// prints C. v2.9 prints O.
    @Test("SN.2 is required when SN.1 is valued on 2.9.1, and not on v2.9")
    func structuredNumeric() throws {
        func num1Missing(_ version: String, _ value: String) throws -> Bool {
            let wire = TestWires.msh("TCU^U10^TCU_U10", version) + "TCC|15074-8^GLUCOSE|GLU-HK^CHEM|SER^SERUM|\(value)\r"
            return Validator().validate(try Parser().parse(wire)).issues.contains {
                $0.code == .conditionalComponentMissing && $0.location.segmentID == "TCC"
                    && $0.location.fieldIndex == 4 && $0.location.componentIndex == 2
            }
        }
        #expect(try num1Missing("2.9.1", ">"))
        #expect(try !num1Missing("2.9", ">"))
        // The print's own values, 2A.2.71.3 p81 and CH13 13.3.3.29 p41.
        for value in [">^100", "^100^-^200", "^1^:^228", "^2^+", "^1^:^5", "^1^+", "^1^:^1"] {
            #expect(try !num1Missing("2.9.1", value), "\(value)")
        }
        #expect(try !num1Missing("2.9.1", ""))
    }

    /// CH13 13.5.10 p66 prints TCC-4 to TCC-7 as `10|10|0|0`, a number in SN.1, which 2A.2.71.1 p80 defines as a comparator.
    /// The only printed value in the chapters the rule reaches. A defective example, and the message declares 2.9, so
    /// it reads under v2.9's grammar and does not draw this. The spec-example audit for 2.9.1 classifies it.
    @Test("The print's TCC line with a number in the comparator draws SN.2, and only when read as 2.9.1")
    func printedComparator() throws {
        func hits(_ version: String) throws -> [Int?] {
            let wire = "MSH|^~\\&|LASPROG|LASSYS|INSTPROG|AUTINST|19980630080040|SECURITY|TCU^U10^TCU|MSG00001|P|\(version)|\r"
                + "EQU|0001^CHEMISTRYANALYZER|19980630080038\r"
                + "TCC|15074-8^GLUCOSE|GLU-HK^CHEMISTRYANALYZER|SER^SERUM|10|10|0|0|500\r"
            return Validator().validate(try Parser().parse(wire)).issues.filter {
                $0.code == .conditionalComponentMissing && $0.location.componentIndex == 2
            }.map(\.location.fieldIndex)
        }
        #expect(try hits("2.9.1") == [4, 5, 6, 7])
        #expect(try hits("2.9").isEmpty)
    }

    /// 2A.2.28.3 p44: "when Field Repetition (ERL-4) and/or Component Number (ERL-5) are populated". v2.9 names ERL-5 alone.
    @Test("ERL.3 is required when ERL.4 or ERL.5 is valued on 2.9.1; on v2.9, by ERL.5 alone")
    func messageLocation() throws {
        func missing(_ version: String, _ value: String) throws -> Bool {
            let wire = TestWires.msh("ACK^A01^ACK", version) + "MSA|AA|M1\rERR||\(value)|207^x^HL70357|E\r"
            return Validator().validate(try Parser().parse(wire)).issues.contains {
                $0.code == .conditionalComponentMissing && $0.location.segmentID == "ERR"
                    && $0.location.fieldIndex == 2 && $0.location.componentIndex == 3
            }
        }
        #expect(try missing("2.9.1", "PID^1^^1"))
        #expect(try missing("2.9.1", "PID^1^^^2"))
        #expect(try !missing("2.9.1", "PID^1"))
        #expect(try !missing("2.9.1", "PID^1^3^1"))
        #expect(try !missing("2.9", "PID^1^^1"))
        #expect(try missing("2.9", "PID^1^^^2"))
    }

    // MARK: - Tables on the wire, which Task 10 could not run

    /// R36: CH04 p163 prints the group DONOR, and no row of 0391 holds it. RCP-1 is a closed table's control.
    @Test("RCP-7 with DONOR draws nothing; RCP-1 with X still draws 0091")
    func segmentGroup() throws {
        let found = try issues("QBP^Q11^QBP_Q11", "RCP|X||||||DONOR")
        #expect(!found.contains { $0.code == .valueNotInTable(table: "0391") })
        #expect(found.contains { $0.code == .valueNotInTable(table: "0091") })
    }

    /// CH02 2.13.9.18 p72: "Valid values for this field are specified in HL7 Table 0211". Only Appendix A prints UTF-16.
    /// MSH-18's first repetition names the message's own character set, so the parser refuses a set it cannot read
    /// before any validator runs. The table's finding is reached at a later repetition, which names an alternate set.
    @Test("UNICODE UTF-16 at MSH-18 draws 0211 at a later repetition; as the first, the parser refuses it")
    func characterSet() throws {
        func wire(_ value: String) -> String {
            "MSH|^~\\&|SND|FAC|RCV|FAC|20260930120000||ADT^A01^ADT_A01|MSG1|P|2.9.1||||||\(value)\r"
        }
        func hits(_ value: String) throws -> Int {
            Validator().validate(try Parser().parse(wire(value))).issues.filter { $0.code == .valueNotInTable(table: "0211") }.count
        }
        #expect(try hits("UNICODE UTF-8~UNICODE UTF-16") == 1)
        #expect(try hits("UNICODE UTF-8~UNICODE UTF-32") == 1)
        #expect(try hits("UNICODE UTF-8") == 0)
        #expect(try hits("UNICODE UTF-8~8859/1") == 0)
        #expect(throws: ParseError.unsupportedCharacterEncoding(declared: "UNICODE UTF-16")) { try Parser().parse(wire("UNICODE UTF-16")) }
    }

    /// ADR-016, R37: DRG-11 (CH06 6.5.3.11 p51), DG1-25 (6.5.2.25 p47) and ARV-4 (CH03 3.4.14.4 p209) say "User-defined Table".
    @Test("A local code at each User table's governing field draws no table finding",
          arguments: [("DRG", 11, "0415"), ("DG1", 25, "0731"), ("ARV", 4, "0719")])
    func userTableField(id: String, index: Int, table: String) throws {
        #expect(HL7TableRegistry.table(table, version: .v2_9_1)?.kind == .userDefined)
        for value in ["Z", "Z^Local^L", "Z^Local^HL7\(table)"] {
            let line = id + String(repeating: "|", count: index) + value
            #expect(try !issues("ADT^A01^ADT_A01", line).contains { $0.code == .valueNotInTable(table: table) }, "\(value)")
        }
    }
}
