// ConditionalProhibitionTests.swift
// P4: conditional prohibitions ("may only be valued if", "should not be
// used", "not permitted", "not applicable") and the prohibitedSeverity
// axis. Each rule has one firing and one non-firing synthetic wire.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Conditional prohibitions (P4)")
struct ConditionalProhibitionTests {

    private func prohibited(_ wire: String, _ seg: String, _ idx: Int) throws -> [ValidationIssue] {
        Validator().validate(try Parser().parse(wire)).issues.filter {
            $0.code == .conditionalFieldProhibited
                && $0.location.segmentID == seg && $0.location.fieldIndex == idx
        }
    }

    // MARK: - Severity axis and the v2.5.1 set (V251-C08)

    @Test("FieldGrammar.prohibitedSeverity defaults to error and carries an explicit warning")
    func prohibitedSeverityAxis() {
        let strict = FieldGrammar(index: 6, name: "Administration Site Modifier", dataType: "CWE",
                                  optionality: .optional, repeatability: .single,
                                  prohibitedWhen: "RXR-2 empty")
        #expect(strict.prohibitedSeverity == .error)
        let advisory = FieldGrammar(index: 7, name: "Cyclic Entry/Exit Indicator", dataType: "ID",
                                    optionality: .conditional, repeatability: .single,
                                    prohibitedWhen: "TQ2-2 != C", prohibitedSeverity: .warning)
        #expect(advisory.prohibitedSeverity == .warning)
    }

    @Test("RXR-6 may only be populated if RXR-2 is populated (error)", arguments: ["2.5.1", "2.6", "2.8.2"])
    func rxr6(version: String) throws {
        let noSite = TestWires.wire("RDE^O11^RDE_O11", version,
            TestWires.segment("RXR", [1: "IV^Intravenous^HL70162", 6: "L^Left^HL70495"]))
        let fires = try prohibited(noSite, "RXR", 6)
        #expect(fires.count == 1, "v\(version)")
        #expect(fires.first?.severity == .error, "v\(version)")
        // RXR-2 from Table 0550 (Body Parts), the table the spec pairs with a
        // 0495 modifier; a Table 0163 site is one where RXR-6 "should not be populated".
        let sited = TestWires.wire("RDE^O11^RDE_O11", version,
            TestWires.segment("RXR", [1: "IV^Intravenous^HL70162", 2: "ARM^Arm^HL70550", 6: "L^Left^HL70495"]))
        #expect(try prohibited(sited, "RXR", 6).isEmpty, "v\(version)")
    }

    @Test("TQ2-7 should not be populated when TQ2-2 is not C (warning)", arguments: ["2.5.1", "2.6", "2.8.2"])
    func tq27(version: String) throws {
        let sequential = TestWires.wire("OMG^O19^OMG_O19", version,
            TestWires.segment("TQ2", [1: "1", 2: "S", 3: "PL1^SYS", 6: "SS", 7: "*"]))
        let fires = try prohibited(sequential, "TQ2", 7)
        #expect(fires.count == 1, "v\(version)")
        #expect(fires.first?.severity == .warning, "v\(version)")
        let cyclic = TestWires.wire("OMG^O19^OMG_O19", version,
            TestWires.segment("TQ2", [1: "1", 2: "C", 3: "PL1^SYS", 6: "SS", 7: "*"]))
        #expect(try prohibited(cyclic, "TQ2", 7).isEmpty, "v\(version)")
    }

    @Test("STF-1 / PRA-1 should not be used outside MFN; PRA-12 not on MFN (warnings)",
          arguments: ["2.4", "2.5.1", "2.6", "2.8.2"])
    func personnelKeys(version: String) throws {
        let pra = TestWires.segment("PRA", [1: "PG1", 12: "1"])
        let adt = TestWires.wire("ADT^A01^ADT_A01", version, "STF|ID1", pra)
        #expect(try prohibited(adt, "STF", 1).map(\.severity) == [.warning], "v\(version)")
        #expect(try prohibited(adt, "PRA", 1).map(\.severity) == [.warning], "v\(version)")
        #expect(try prohibited(adt, "PRA", 12).isEmpty, "v\(version)")
        let mfn = TestWires.wire("MFN^M02^MFN_M02", version, "STF|ID1", pra)
        #expect(try prohibited(mfn, "STF", 1).isEmpty, "v\(version)")
        #expect(try prohibited(mfn, "PRA", 1).isEmpty, "v\(version)")
        #expect(try prohibited(mfn, "PRA", 12).map(\.severity) == [.warning], "v\(version)")
    }
}
