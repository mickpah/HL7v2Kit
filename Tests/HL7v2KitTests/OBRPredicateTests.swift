// OBRPredicateTests.swift
// P1 remediation pins for the OBR condition predicates. Wires are built
// field by field (`segment(_:_:)`) so pipe counts cannot drift; the
// pre-condition `#expect`s on path access pin that each value lands on
// the intended field.
//
// Spec citations use each version's own numbering: v2.3 / v2.3.1 put OBR
// at CH4 §4.5.1 and ORC at §4.3.1; v2.4 and later put OBR at CH04 §4.5.3
// and ORC at §4.5.1.

import Testing
@testable import HL7v2Kit

@Suite("OBR predicates (P1 remediation)")
struct OBRPredicateTests {

    // MARK: - Wire and grammar helpers

    /// `ID|f1|f2|...` from an index-to-value map; unset indices are empty.
    static func segment(_ id: String, _ fields: [Int: String]) -> String {
        guard let last = fields.keys.max(), last > 0 else { return id }
        return ([id] + (1...last).map { fields[$0] ?? "" }).joined(separator: "|")
    }

    static func msh(_ messageType: String, _ version: String) -> String {
        "MSH|^~\\&|SENDER|FAC|LAB|FAC|20240401090000||\(messageType)|MSG0001|P|\(version)"
    }

    static func wire(_ segments: [String]) -> String {
        segments.joined(separator: "\r") + "\r"
    }

    static let pid = "PID|1||X123^^^FAC^MR||Doe^Jane||19800101|F"

    static func table(_ version: String) -> [String: SegmentGrammar] {
        switch version {
        case "2.3": return SegmentGrammarTable.v2_3
        case "2.3.1": return SegmentGrammarTable.v2_3_1
        case "2.4": return SegmentGrammarTable.v2_4
        case "2.5.1": return SegmentGrammarTable.v2_5_1
        case "2.6": return SegmentGrammarTable.v2_6
        case "2.8.2": return SegmentGrammarTable.v2_8_2
        default: return [:]
        }
    }

    private func report(_ wire: String) throws -> ValidationReport {
        Validator().validate(try Parser().parse(wire))
    }

    private func conditionalHits(_ wire: String, _ segmentID: String = "OBR", field: Int) throws -> [ValidationIssue] {
        try report(wire).errors.filter {
            $0.code == .conditionalFieldMissing
                && $0.location.segmentID == segmentID
                && $0.location.fieldIndex == field
        }
    }

    // MARK: - P1-1: specimen legs (X-C05, X-C06, V23-C01, V24-C02, V26-C01)

    /// A new placer order where the lab still has to collect the specimen
    /// (OBR-11 = L, Table 0065) and OBR-15 names where it should be
    /// obtained. No specimen accompanies the order, so neither OBR-7
    /// ("a sample has been sent along") nor OBR-14 ("accompanied by a
    /// specimen") is required.
    static func placerOrderNamingSpecimenSource(_ version: String) -> String {
        wire([
            msh(version == "2.8.2" ? "OML^O21^OML_O21" : "ORM^O01", version), pid,
            segment("ORC", [1: "NW", 2: "ORD001"]),
            segment("OBR", [1: "1", 2: "ORD001", 4: "GLUC^Glucose^L", 11: "L", 15: "BLDV^Blood venous^HL70070"]),
        ])
    }

    @Test("X-C05: OBR-15 on a new order does not require OBR-7 or OBR-14",
          arguments: ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.8.2"])
    func specimenSourceAloneRequiresNothing(version: String) throws {
        let wire = Self.placerOrderNamingSpecimenSource(version)
        let message = try Parser().parse(wire)
        #expect(message["OBR-11"] == "L", "Wire mis-counted: L should land at OBR-11")
        #expect(message["OBR-15.1"] == "BLDV", "Wire mis-counted: BLDV should land at OBR-15")
        #expect(try conditionalHits(wire, field: 7).isEmpty, "v\(version) OBR-7")
        #expect(try conditionalHits(wire, field: 14).isEmpty, "v\(version) OBR-14")
    }

    /// v2.5.1 §7.4.3: SPM may describe a "virtual" specimen, so SPM on an
    /// order is not "a sample has been sent along" either.
    @Test("X-C05: SPM on a new order does not require OBR-7",
          arguments: ["2.5.1", "2.6", "2.8.2"])
    func spmOnOrderDoesNotRequireObservationDateTime(version: String) throws {
        let wire = Self.wire([
            Self.msh("OML^O21^OML_O21", version), Self.pid,
            Self.segment("ORC", [1: "NW", 2: "ORD001"]),
            Self.segment("OBR", [1: "1", 2: "ORD001", 4: "GLUC^Glucose^L", 11: "L"]),
            Self.segment("SPM", [1: "1", 4: "BLD^Blood^HL70487"]),
        ])
        #expect(try conditionalHits(wire, field: 7).isEmpty, "v\(version) OBR-7")
    }

    /// V26-C01: v2.5.1 and v2.6 print OBR-14 as B and favour SPM-18
    /// (§4.5.3.14). A result carrying SPM-18 with OBR-14 empty is the
    /// preferred shape and must not error; a populated OBR-14 warns.
    @Test("V26-C01: OBR-14 is B on v2.5.1 and v2.6", arguments: ["2.5.1", "2.6"])
    func obr14IsBackwardCompatible(version: String) throws {
        func result(obr14: String?) -> String {
            var obr: [Int: String] = [1: "1", 2: "ORD001", 3: "FIL001", 4: "GLUC^Glucose^L", 7: "20240401080000", 25: "F"]
            if let obr14 { obr[14] = obr14 }
            return Self.wire([
                Self.msh("ORU^R01^ORU_R01", version), Self.pid,
                Self.segment("ORC", [1: "RE", 2: "ORD001", 3: "FIL001"]),
                Self.segment("OBR", obr),
                Self.segment("SPM", [1: "1", 4: "BLD^Blood^HL70487", 17: "20240401080000", 18: "20240401093000"]),
                Self.segment("OBX", [1: "1", 2: "NM", 3: "GLU^Glucose^L", 5: "5.2", 11: "F"]),
            ])
        }
        let preferred = result(obr14: nil)
        #expect(try Parser().parse(preferred)["SPM-18"] == "20240401093000")
        #expect(try conditionalHits(preferred, field: 14).isEmpty, "v\(version): SPM-18 carries the received time")
        let legacy = try report(result(obr14: "20240401093000"))
        #expect(legacy.warnings.contains {
            $0.code == .fieldNotSupported && $0.location.segmentID == "OBR" && $0.location.fieldIndex == 14
        }, "v\(version): a populated B field warns")
    }

    @Test("X-C05 / X-C06: OBR-7 and OBR-14 metadata carry no specimen atom",
          arguments: ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.8.2"])
    func specimenAtomsGone(version: String) throws {
        let obr = try #require(Self.table(version)["OBR"])
        let obr7 = try #require(obr.field(7)?.condition)
        #expect(!obr7.contains("OBR-15") && !obr7.contains("SPM"), "v\(version) OBR-7: \(obr7)")
        #expect(obr.field(14)?.condition == nil, "v\(version) OBR-14")
        let expected: FieldOptionality = switch version {
        case "2.5.1", "2.6": .backwardCompat
        case "2.8.2": .withdrawn
        default: .conditional
        }
        #expect(obr.field(14)?.optionality == expected, "v\(version) OBR-14 optionality")
    }
}
