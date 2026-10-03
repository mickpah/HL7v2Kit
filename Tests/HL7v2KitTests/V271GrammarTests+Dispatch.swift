// V271GrammarTests+Dispatch.swift
// P10-6: `Version.v2_7_1` dispatches to the v2.7.1 code tables, datatype grammar and
// segment grammar, and sits with v2.8.2 on every era rule. Each era pin cites the v2.7.1
// print (Final Standard, July 2012).

import Testing
@testable import HL7v2Kit

extension V271GrammarTests {

    // MARK: - P10-6: dispatch

    static let adt271 = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01^ADT_A01|MSG00001|P|2.7.1\r"
        + "EVN||20240301120000\rPID|1||123456^^^HOSP^MR||Smith^John||19800101|M\rPV1|1|I\r"

    @Test("A 2.7.1 wire parses as v2.7.1 and validates against its own grammar under every preset",
          arguments: ["lenient", "default", "strict"])
    func dispatch(_ preset: String) throws {
        let options: ValidationOptions = switch preset {
        case "lenient": .lenient
        case "strict": .strict
        default: .default
        }
        let message = try Parser().parse(Self.adt271)
        #expect(message.version == .v2_7_1)
        #expect(message.version.grammarVersion == .v2_7_1)
        let codes = Validator(options: options).validate(message).issues.map(\.code)
        #expect(!codes.contains(.zSegmentPresent))
        #expect(!codes.contains { if case .segmentNotInVersionGrammar = $0 { return true } else { return false } })
        #expect(!codes.contains { if case .versionNotRecognised = $0 { return true } else { return false } })
        #expect(!codes.contains { if case .versionGrammarSubstituted = $0 { return true } else { return false } })
    }

    @Test("Every per-version dispatch returns the generated v2.7.1 table")
    func dispatchTables() {
        #expect(Validator.grammarTable(for: .v2_7_1).count == SegmentGrammarTable.v2_7_1.count)
        #expect(Validator.grammarTable(for: .v2_7_1).count == 170)
        #expect(HL7TableRegistry.tables(for: .v2_7_1).count == HL7TableRegistry.v2_7_1.count)
        #expect(HL7TableRegistry.table("0136", version: .v2_7_1) != nil)
        #expect(DataTypeGrammarTable.grammars(for: .v2_7_1).count == DataTypeGrammarTable.v2_7_1.count)
        #expect(DataTypeGrammarTable.grammar("XPN", version: .v2_7_1) != nil)
        // v2.7.1 prints component tables for every composite: no field-local grammar.
        #expect(DataTypeGrammarTable.fieldGrammars(for: .v2_7_1).isEmpty)
    }

    @Test("Era placement: v2.7.1 sits with v2.8.2 on every rule")
    func eraPlacement() {
        // CH02 §2.5.3.2 and §2.5.3.3 (p8), §2.5.5.0 Normative Length (p10), §2.5.5.3
        // Conformance Length (p12): LEN is normative, C.LEN a conformance length.
        #expect(!Version.v2_7_1.printsMaximumLength)
        // CH02 §2.5.5 (pp10-12) defines neither 65536 nor 99999.
        #expect(!Version.v2_7_1.printsLengthSymbols)
        // CH02A §2.A.69 (p80): "This allows for a number between 0 and 9999 to be specified."
        #expect(Version.v2_7_1.boundsSequenceID)
        // CH02A §2.A.71 SNM (p81) is a primitive; TS is withdrawn (§2.A.78, p85).
        let primitives = Validator.primitiveTypes(.v2_7_1)
        #expect(primitives == Validator.primitiveTypes(.v2_8_2))
        #expect(primitives.contains("SNM") && !primitives.contains("TS"))
        // CH02A §2.A.44 (p56): MSG.3 Message Structure is `3,7 ID R 0354`.
        let msg = DataTypeGrammarTable.grammar("MSG", version: .v2_7_1)
        #expect(msg?.components.count == 3)
        #expect(msg?.components.last?.optionalityCode == "R")
        #expect(msg?.components.last?.tables == ["0354"])
    }
}
