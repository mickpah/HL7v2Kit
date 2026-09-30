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
        // An empty TQ2-2 is "not equal to a 'C'" under the literal reading, so
        // the SHOULD-NOT fires; the warning severity keeps it advisory.
        let unflagged = TestWires.wire("OMG^O19^OMG_O19", version,
            TestWires.segment("TQ2", [1: "1", 3: "PL1^SYS", 6: "SS", 7: "*"]))
        #expect(try prohibited(unflagged, "TQ2", 7).map(\.severity) == [.warning], "v\(version)")
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

    // MARK: - v2.6 family (V26-C08, V26-C09)

    @Test("ORC-25 may only be populated if ORC-5 is valued", arguments: ["2.4", "2.5.1", "2.6", "2.8.2"])
    func orc25(version: String) throws {
        let noStatus = TestWires.wire("OMG^O19^OMG_O19", version,
            TestWires.segment("ORC", [1: "NW", 2: "PL1", 25: "HOLD^On hold"]))
        #expect(try prohibited(noStatus, "ORC", 25).map(\.severity) == [.error], "v\(version)")
        let withStatus = TestWires.wire("OMG^O19^OMG_O19", version,
            TestWires.segment("ORC", [1: "NW", 2: "PL1", 5: "IP", 25: "HOLD^On hold"]))
        #expect(try prohibited(withStatus, "ORC", 25).isEmpty, "v\(version)")
    }

    @Test("OBX-12 can be valued only if OBX-7 is populated", arguments: ["2.5.1", "2.6", "2.8.2"])
    func obx12(version: String) throws {
        func obx(_ range: String) -> String {
            TestWires.wire("ORU^R01^ORU_R01", version,
                TestWires.segment("OBX", [1: "1", 2: "NM", 3: "GLU^Glucose^LN", 5: "5.5",
                                          7: range, 11: "F", 12: "20260101"]))
        }
        #expect(try prohibited(obx(""), "OBX", 12).map(\.severity) == [.error], "v\(version)")
        #expect(try prohibited(obx("3.5-7.8"), "OBX", 12).isEmpty, "v\(version)")
    }

    @Test("SPM-13 would only be valued if a SPM-11 role is G (warning)", arguments: ["2.5.1", "2.6", "2.8.2"])
    func spm13(version: String) throws {
        func spm(_ role: String) -> String {
            TestWires.wire("OML^O33^OML_O33", version,
                TestWires.segment("SPM", [1: "1", 4: "BLD^Blood^HL70487", 11: role, 13: "3"]))
        }
        // Single-occurrence SPM-11 (no repetition marker): a matching role
        // silences the prohibition, a non-matching one fires it.
        #expect(try prohibited(spm("P^Patient^HL70369"), "SPM", 13).map(\.severity) == [.warning], "v\(version)")
        #expect(try prohibited(spm("G^Group^HL70369"), "SPM", 13).isEmpty, "v\(version)")
        // A wholly empty SPM-11 (no role stated at all) is not "the value G"
        // either, so the composition `SPM-11 empty OR noRepeat(SPM-11) = G`
        // fires here too — see the ADR-010 P4-2 amendment on full universal
        // negation.
        let noRole = TestWires.wire("OML^O33^OML_O33", version,
            TestWires.segment("SPM", [1: "1", 4: "BLD^Blood^HL70487", 13: "3"]))
        #expect(try prohibited(noRole, "SPM", 13).map(\.severity) == [.warning], "v\(version) empty SPM-11")
    }

    @Test("PYE-3..6 are not permitted outside their payee types", arguments: ["2.6", "2.8.2"])
    func pyeNotPermitted(version: String) throws {
        func pye(_ payeeType: String) -> String {
            TestWires.wire("EHC^E01^EHC_E01", version,
                TestWires.segment("PYE", [1: "1", 2: payeeType, 3: "PT", 4: "Acme Clinic",
                                          5: "Doe^Jane", 6: "1 Main St^^Town"]))
        }
        let org = pye("ORG")
        #expect(try prohibited(org, "PYE", 3).count == 1, "v\(version) PYE-3 on ORG")
        #expect(try prohibited(org, "PYE", 5).count == 1, "v\(version) PYE-5 on ORG")
        #expect(try prohibited(org, "PYE", 6).count == 1, "v\(version) PYE-6 on ORG")
        #expect(try prohibited(org, "PYE", 4).isEmpty, "v\(version) PYE-4 permitted on ORG")
        let person = pye("PERS")
        #expect(try prohibited(person, "PYE", 4).count == 1, "v\(version) PYE-4 on PERS")
        #expect(try prohibited(person, "PYE", 3).isEmpty, "v\(version) PYE-3 permitted on PERS")
    }

    // MARK: - v2.8.2 PRT (V282-C06, V282-C07)

    @Test("PRT-7 may only be valued if PRT-5 is valued (v2.8.2 §7.4.4.7)")
    func prt7FollowsPrintedSubject() throws {
        func prt(_ fields: [Int: String]) -> String {
            TestWires.wire("ORU^R01^ORU_R01", "2.8.2", TestWires.segment("PRT", fields))
        }
        // PRT-5 valued, PRT-8 empty, PRT-7 valued: spec-permitted, must stay silent.
        let person = prt([1: "1", 2: "AD", 4: "AP", 5: "1234^SMITH^JOHN", 7: "WARD^Ward Unit"])
        #expect(try prohibited(person, "PRT", 7).isEmpty)
        // PRT-5 empty, PRT-8 valued, PRT-7 valued: the printed subject is missing.
        let organisation = prt([1: "1", 2: "AD", 4: "AP", 7: "WARD^Ward Unit", 8: "Acme Lab"])
        #expect(try prohibited(organisation, "PRT", 7).count == 1)
    }

    @Test("PRT-14 is required when PRT-4 is POMD (v2.8.2 §7.4.4.14, partial)")
    func prt14() throws {
        func missing(_ participation: String) throws -> [ValidationIssue] {
            let wire = TestWires.wire("ORU^R01^ORU_R01", "2.8.2",
                TestWires.segment("PRT", [1: "1", 2: "AD", 4: participation, 5: "1234^SMITH^JOHN"]))
            return Validator().validate(try Parser().parse(wire)).errors.filter {
                $0.code == .conditionalFieldMissing
                    && $0.location.segmentID == "PRT" && $0.location.fieldIndex == 14
            }
        }
        #expect(try missing("POMD^Performing Organization Medical Director^HL70912").count == 1)
        #expect(try missing("OP^Ordering Provider^HL70912").isEmpty)
    }
}
