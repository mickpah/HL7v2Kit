// VersionPredicateWireTests.swift
// V23-C14 / V26-C15 (with the v2.7.1 and v2.8.2 equivalents, P7-7): wire-level fire and
// silent pairs for predicates that were pinned only by condition-string equality. Each pair states the final behaviour of a predicate
// the remediation leaves unchanged. The wires are minimal (one segment under test), so
// they are not structure-conformant; the pairs read only the conditional finding.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Per-version predicate wire pairs")
struct VersionPredicateWireTests {
    struct Pair: Sendable, CustomTestStringConvertible {
        let label: String
        let fireWire: String
        let silentWire: String
        let segment: String
        let field: Int
        var testDescription: String { label }
    }

    static func wire(_ type: String, _ version: String, _ segments: String...) -> String {
        (["MSH|^~\\&|SYNTH_A|SYNTH_FAC|SYNTH_B|SYNTH_FAC|20240101120000||\(type)|SYN-PAIR|P|\(version)"] + segments)
            .joined(separator: "\r") + "\r"
    }

    /// `SEG|f1|f2|...` from sparse field values.
    static func seg(_ id: String, _ fields: [Int: String]) -> String {
        let last = max(fields.keys.max() ?? 1, 1)
        return ([id] + (1...last).map { fields[$0] ?? "" }).joined(separator: "|")
    }

    static func shared(_ v: String) -> [Pair] {
        let obr = seg("OBR", [1: "1", 4: "K^Potassium^L"])
        return [
            Pair(label: "\(v) CSR-9 on C01",
                 fireWire: wire("CRM^C01", v, seg("CSR", [1: "SYN-STUDY-01"])),
                 silentWire: wire("CRM^C01", v, seg("CSR", [1: "SYN-STUDY-01", 9: "20240101"])),
                 segment: "CSR", field: 9),
            Pair(label: "\(v) CSR-14 on C04",
                 fireWire: wire("CRM^C04", v, seg("CSR", [1: "SYN-STUDY-01"])),
                 silentWire: wire("CRM^C04", v, seg("CSR", [1: "SYN-STUDY-01", 14: "20240101"])),
                 segment: "CSR", field: 14),
            Pair(label: "\(v) CTI-2 when CTI-3 populated",
                 fireWire: wire("CRM^C01", v, seg("CTI", [1: "SYN-STUDY-01", 3: "SYN-ARM-01"])),
                 silentWire: wire("CRM^C01", v, seg("CTI", [1: "SYN-STUDY-01", 2: "SYN-PHASE-01", 3: "SYN-ARM-01"])),
                 segment: "CTI", field: 2),
            Pair(label: "\(v) RQ1-2 when RQ1-4 empty",
                 fireWire: wire("RQA^I08", v, seg("RQ1", [1: "10"])),
                 silentWire: wire("RQA^I08", v, seg("RQ1", [1: "10", 2: "SYN-MFR-01", 3: "SYN-CAT-01",
                                                              4: "SYN-VND-01", 5: "SYN-VCAT-01"])),
                 segment: "RQ1", field: 2),
            Pair(label: "\(v) RQD-2 when RQD-3 and RQD-4 empty",
                 fireWire: wire("RQA^I08", v, seg("RQD", [1: "1"])),
                 silentWire: wire("RQA^I08", v, seg("RQD", [1: "1", 3: "SYN-ITEM-01"])),
                 segment: "RQD", field: 2),
            // ORC-2 is needed only when no order number is valued anywhere: ORC-3,
            // OBR-2 and OBR-3 all empty (the either-placer-or-filler rule).
            Pair(label: "\(v) ORC-2 when ORC-3, OBR-2 and OBR-3 are empty",
                 fireWire: wire("ORM^O01", v, seg("ORC", [1: "NW"]), obr),
                 silentWire: wire("ORM^O01", v, seg("ORC", [1: "NW", 2: "SYN-P-01^SYNTH_HIS"]), obr),
                 segment: "ORC", field: 2),
        ]
    }

    static let v23Pairs: [Pair] = shared("2.3")

    static let v26Pairs: [Pair] = shared("2.6") + [
        Pair(label: "2.6 PYE-3 when PYE-2 = PERS",
             fireWire: wire("EHC^E01^EHC_E01", "2.6", seg("PYE", [1: "1", 2: "PERS"])),
             silentWire: wire("EHC^E01^EHC_E01", "2.6", seg("PYE", [1: "1", 2: "ORG"])),
             segment: "PYE", field: 3),
        Pair(label: "2.6 PYE-4 when PYE-2 = ORG",
             fireWire: wire("EHC^E01^EHC_E01", "2.6", seg("PYE", [1: "1", 2: "ORG"])),
             silentWire: wire("EHC^E01^EHC_E01", "2.6", seg("PYE", [1: "1", 2: "PERS"])),
             segment: "PYE", field: 4),
        Pair(label: "2.6 DG1-20 on P12 only",
             fireWire: wire("BAR^P12^BAR_P12", "2.6",
                            seg("DG1", [1: "1", 3: "I10^Essential hypertension^I10", 6: "A"])),
             silentWire: wire("ADT^A01^ADT_A01", "2.6",
                              seg("DG1", [1: "1", 3: "I10^Essential hypertension^I10", 6: "A"])),
             segment: "DG1", field: 20),
    ]

    static let laterPairs: [Pair] = shared("2.7.1") + shared("2.8.2")

    static func fires(_ wire: String, _ segment: String, _ field: Int) throws -> Bool {
        let report = Validator().validate(try Parser().parse(wire))
        return report.issues.contains {
            $0.code == .conditionalFieldMissing && $0.location.segmentID == segment && $0.location.fieldIndex == field
        }
    }

    @Test("v2.3 predicate pairs fire and stay silent on the wire", arguments: v23Pairs)
    func v23(_ pair: Pair) throws {
        #expect(try Self.fires(pair.fireWire, pair.segment, pair.field), "\(pair.label) did not fire")
        #expect(try Self.fires(pair.silentWire, pair.segment, pair.field) == false, "\(pair.label) fired when satisfied")
    }

    @Test("v2.6 predicate pairs fire and stay silent on the wire", arguments: v26Pairs)
    func v26(_ pair: Pair) throws {
        #expect(try Self.fires(pair.fireWire, pair.segment, pair.field), "\(pair.label) did not fire")
        #expect(try Self.fires(pair.silentWire, pair.segment, pair.field) == false, "\(pair.label) fired when satisfied")
    }

    @Test("v2.7.1 and v2.8.2 predicate pairs fire and stay silent on the wire", arguments: laterPairs)
    func later(_ pair: Pair) throws {
        #expect(try Self.fires(pair.fireWire, pair.segment, pair.field), "\(pair.label) did not fire")
        #expect(try Self.fires(pair.silentWire, pair.segment, pair.field) == false, "\(pair.label) fired when satisfied")
    }
}
