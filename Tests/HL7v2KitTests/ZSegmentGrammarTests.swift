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
}
