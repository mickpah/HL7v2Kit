// ZSegmentGrammarTests.swift
// P00 S4-1 (ADR-003 amended): a caller-supplied Z-segment grammar is applied by the
// validator like any segment grammar, optionally only for some sending applications
// (MSH-3.1). Parsing is unchanged.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Caller-supplied Z-segment grammars")
struct ZSegmentGrammarTests {
    /// ZAU: 1 Set ID (O), 2 Account Code (R, LEN 10), 3 Note (O, repeating).
    static func zau(requiring required: Int = 2) -> SegmentGrammar {
        SegmentGrammar(segmentID: "ZAU", version: "2.5.1", fields: [
            FieldGrammar(index: 1, name: "Set ID", dataType: "SI", optionality: .optional, repeatability: .single),
            FieldGrammar(index: 2, name: "Account Code", dataType: "ST",
                         optionality: required == 2 ? .required : .optional, repeatability: .single, length: "10"),
            FieldGrammar(index: 3, name: "Note", dataType: "ST",
                         optionality: required == 3 ? .required : .optional, repeatability: .multiple),
        ])
    }

    static func options(_ grammars: [ZSegmentGrammar], policy: ZSegmentPolicy = .ignore) -> ValidationOptions {
        var options = ValidationOptions.default
        options.zSegmentPolicy = policy
        // The structure check is not under test, and it reports a missing segment at the last segment, often the Z-segment.
        options.messageStructureSeverity = nil
        options.zSegmentGrammars = grammars
        return options
    }

    static func issues(_ wire: String, _ options: ValidationOptions, segment: String = "ZAU") throws -> [ValidationIssue] {
        Validator(options: options).validate(try Parser().parse(wire)).issues.filter { $0.location.segmentID == segment }
    }

    @Test("A required field missing from a defined Z-segment is reported at its position")
    func requiredFieldMissing() throws {
        let found = try Self.issues(TestWires.adt("PID|1", "ZAU|1"), Self.options([ZSegmentGrammar(Self.zau())]))
        #expect(found.map(\.code) == [.requiredFieldMissing])
        #expect(found.first?.location.fieldIndex == 2)
    }

    @Test("A Z-segment that meets its grammar is clean; its length is checked")
    func cleanAndLength() throws {
        let options = Self.options([ZSegmentGrammar(Self.zau())])
        #expect(try Self.issues(TestWires.adt("PID|1", "ZAU|1|ACC1|a~b"), options).isEmpty)
        let long = try Self.issues(TestWires.adt("PID|1", "ZAU|1|ACCOUNT0011"), options)
        #expect(long.map(\.code) == [.fieldLengthOutOfRange(length: "10", actual: 11)])
    }

    @Test("zSegmentPolicy no longer applies to a defined Z-segment; an undefined one still draws it")
    func policyOnlyForUndefined() throws {
        let wire = TestWires.adt("PID|1", "ZAU|1|ACC1", "ZXX|1")
        for policy in [ZSegmentPolicy.warnPresence, .reject] {
            let options = Self.options([ZSegmentGrammar(Self.zau())], policy: policy)
            #expect(try Self.issues(wire, options).isEmpty, "\(policy)")
            #expect(try Self.issues(wire, options, segment: "ZXX").map(\.code) == [.zSegmentPresent], "\(policy)")
        }
    }

    @Test("A grammar scoped to one sending application is not applied to another")
    func senderScope() throws {
        let options = Self.options([ZSegmentGrammar(Self.zau(), sendingApplications: ["LAB"])])
        #expect(try Self.issues(TestWires.oru("PID|1", "ZAU|1"), options).map(\.code) == [.requiredFieldMissing])
        #expect(try Self.issues(TestWires.adt("PID|1", "ZAU|1"), options).isEmpty)
    }

    @Test("The first matching grammar in array order applies")
    func arrayOrder() throws {
        let options = Self.options([
            ZSegmentGrammar(Self.zau(requiring: 3), sendingApplications: ["LAB"]),
            ZSegmentGrammar(Self.zau(requiring: 2)),
        ])
        let lab = try Self.issues(TestWires.oru("PID|1", "ZAU|1|ACC1"), options)
        #expect(lab.map(\.code) == [.requiredFieldMissing])
        #expect(lab.first?.location.fieldIndex == 3)
        #expect(try Self.issues(TestWires.adt("PID|1", "ZAU|1|ACC1"), options).isEmpty)
    }

    @Test("A grammar for an ID not beginning with Z is never used")
    func nonZIgnored() throws {
        let xyz = SegmentGrammar(segmentID: "XYZ", version: "2.5.1", fields: [
            FieldGrammar(index: 2, name: "Code", dataType: "ST", optionality: .required, repeatability: .single),
        ])
        // The structure check is off in these options; segmentNotInVersionGrammar comes from the grammar lookup.
        let found = try Self.issues(TestWires.adt("PID|1", "XYZ|1"), Self.options([ZSegmentGrammar(xyz)]), segment: "XYZ")
        #expect(found.contains { $0.code == .segmentNotInVersionGrammar })
        #expect(!found.contains { $0.code == .requiredFieldMissing })
    }

    @Test("Parsing is unchanged: the segment stays UnknownSegment and round-trips")
    func parsingUnchanged() throws {
        let wire = TestWires.adt("PID|1", "ZAU|1|ACC1")
        let message = try Parser().parse(wire)
        #expect(message.segments.contains { if case .unknown(let u) = $0 { return u.segmentID == "ZAU" } else { return false } })
        #expect(message.serialize() == Data(wire.utf8))
        #expect(message["ZAU-2"] == "ACC1")
    }

    /// ZAU with a single field 2 (ST) of the given LEN, declared in `version`.
    static func zauLength(_ length: String, version: String) -> SegmentGrammar {
        SegmentGrammar(segmentID: "ZAU", version: version, fields: [
            FieldGrammar(index: 2, name: "Account Code", dataType: "ST", optionality: .optional,
                         repeatability: .single, length: length),
        ])
    }

    @Test("P00 S4 fix: LEN is read in the grammar's declared version, not the message's")
    func lengthReadInDeclaredVersion() throws {
        let long = "ZAU|1|ACCOUNT0011"
        let a = try Self.issues(TestWires.wire("ADT^A01^ADT_A01", "2.8.2", "PID|1", long),
                                Self.options([ZSegmentGrammar(Self.zauLength("10", version: "2.5.1"))]))
        #expect(a.map(\.code) == [.fieldLengthOutOfRange(length: "10", actual: 11)])
        #expect(a.first?.message.contains("supplied ZAU grammar") == true)
        let b = try Self.issues(TestWires.wire("ADT^A01^ADT_A01", "2.4", "PID|1", long),
                                Self.options([ZSegmentGrammar(Self.zauLength("1..10", version: "2.8.2"))]))
        #expect(b.map(\.code) == [.fieldLengthOutOfRange(length: "1..10", actual: 11)])
    }

    @Test("P00 S4 fix: a scoped grammar is not applied when MSH-3 is absent or empty; an unscoped one is")
    func scopeNeedsSender() throws {
        let noSender = "MSH|^~\\&||FAC|RCV|FAC|20260930120000||ADT^A01^ADT_A01|MSG1|P|2.5.1\rPID|1\rZAU|1\r"
        let noMSH3 = "MSH|^~\\&|||RCV|FAC|20260930120000||ADT^A01^ADT_A01|MSG1|P|2.5.1\rPID|1\rZAU|1\r"
        for wire in [noSender, noMSH3] {
            #expect(try Self.issues(wire, Self.options([ZSegmentGrammar(Self.zau(), sendingApplications: ["LAB"])])).isEmpty)
            #expect(try Self.issues(wire, Self.options([ZSegmentGrammar(Self.zau(), sendingApplications: [""])])).isEmpty)
            #expect(try Self.issues(wire, Self.options([ZSegmentGrammar(Self.zau())])).map(\.code) == [.requiredFieldMissing])
        }
    }

    @Test("P00 S4 fix: the structure findings are the same with and without a Z grammar")
    func structureTransparent() throws {
        let wire = TestWires.oru("ZAU|1|ACC1", "PID|1")
        func structure(_ grammars: [ZSegmentGrammar]) throws -> [ValidationIssue] {
            var options = ValidationOptions.default
            options.zSegmentGrammars = grammars
            return Validator(options: options).validate(try Parser().parse(wire)).issues
                .filter { String(describing: $0.code).hasPrefix("messageStructure") }
        }
        let without = try structure([])
        #expect(!without.isEmpty)
        #expect(try structure([ZSegmentGrammar(Self.zau())]) == without)
    }

    @Test("P00 S4 fix: under the AU locale a typed CWE Z field draws the AU CWE rules on an ORU only")
    func auCWERulesReachZField() throws {
        let cwe = SegmentGrammar(segmentID: "ZAU", version: "2.4", fields: [
            FieldGrammar(index: 1, name: "Code", dataType: "CWE", optionality: .optional, repeatability: .single),
        ])
        let locale = HL7Locale.auLocalisation
        func found(_ type: String) throws -> [ValidationIssue] {
            let wire = "MSH|^~\\&|LAB|FAC|GP|FAC|20240101||\(type)|MSG|P|2.4\rZAU|SH1\r"
            var options = Self.options([ZSegmentGrammar(cwe)])
            options.messageStructureSeverity = nil
            return Validator(options: options, locale: locale).validate(try Parser(locale: locale).parse(wire)).issues
                .filter { $0.location.segmentID == "ZAU" }
        }
        let oru = try found("ORU^R01^ORU_R01")
        let rules = oru.compactMap { issue -> String? in
            if case .profileConstraintViolation(let rule) = issue.code { return rule } else { return nil }
        }
        #expect(rules.count == 2)
        #expect(rules.allSatisfy { $0.hasPrefix("HL7au:00044.6") })
        let adt = try found("ADT^A01^ADT_A01")
        #expect(adt.isEmpty)
    }
}
