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
        case "2.7.1": return SegmentGrammarTable.v2_7_1
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
          arguments: ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.7.1", "2.8.2"])
    func specimenAtomsGone(version: String) throws {
        let obr = try #require(Self.table(version)["OBR"])
        let obr7 = try #require(obr.field(7)?.condition)
        #expect(!obr7.contains("OBR-15") && !obr7.contains("SPM"), "v\(version) OBR-7: \(obr7)")
        #expect(obr.field(14)?.condition == nil, "v\(version) OBR-14")
        let expected: FieldOptionality = switch version {
        case "2.5.1", "2.6": .backwardCompat
        case "2.7.1", "2.8.2": .withdrawn
        default: .conditional
        }
        #expect(obr.field(14)?.optionality == expected, "v\(version) OBR-14 optionality")
    }

    // MARK: - P1-2: report-message set (X-C07)

    struct MessageCase: Sendable, CustomTestStringConvertible {
        let version: String
        let messageType: String
        var testDescription: String { "v\(version) \(messageType)" }
    }

    /// Report messages per version (plan table in P1-2). Each must require
    /// OBR-7 and OBR-25.
    static let reportCases: [MessageCase] = [
        .init(version: "2.3", messageType: "ORU^R01"), .init(version: "2.3", messageType: "ORF^R04"),
        .init(version: "2.3.1", messageType: "ORU^R01"), .init(version: "2.3.1", messageType: "ORF^R04"),
        .init(version: "2.4", messageType: "ORU^R01^ORU_R01"), .init(version: "2.4", messageType: "ORF^R04^ORF_R04"),
        .init(version: "2.4", messageType: "OUL^R21^OUL_R21"),
        .init(version: "2.5.1", messageType: "ORU^R01^ORU_R01"), .init(version: "2.5.1", messageType: "ORU^R30^ORU_R30"),
        .init(version: "2.5.1", messageType: "ORF^R04^ORF_R04"), .init(version: "2.5.1", messageType: "OUL^R21^OUL_R21"),
        .init(version: "2.5.1", messageType: "OUL^R22^OUL_R22"), .init(version: "2.5.1", messageType: "OUL^R23^OUL_R23"),
        .init(version: "2.5.1", messageType: "OUL^R24^OUL_R24"),
        .init(version: "2.6", messageType: "ORU^R01^ORU_R01"), .init(version: "2.6", messageType: "ORU^R30^ORU_R30"),
        .init(version: "2.6", messageType: "ORF^R04^ORF_R04"), .init(version: "2.6", messageType: "OUL^R21^OUL_R21"),
        .init(version: "2.6", messageType: "OUL^R22^OUL_R22"), .init(version: "2.6", messageType: "OUL^R23^OUL_R23"),
        .init(version: "2.6", messageType: "OUL^R24^OUL_R24"), .init(version: "2.6", messageType: "OPU^R25^OPU_R25"),
        .init(version: "2.8.2", messageType: "ORU^R01^ORU_R01"), .init(version: "2.8.2", messageType: "ORU^R30^ORU_R30"),
        .init(version: "2.8.2", messageType: "ORU^R40^ORU_R01"), .init(version: "2.8.2", messageType: "OUL^R21^OUL_R21"),
        .init(version: "2.8.2", messageType: "OUL^R22^OUL_R22"), .init(version: "2.8.2", messageType: "OUL^R23^OUL_R23"),
        .init(version: "2.8.2", messageType: "OUL^R24^OUL_R24"), .init(version: "2.8.2", messageType: "OPU^R25^OPU_R25"),
    ]

    /// Orders, plus ORF on v2.8.2 (withdrawn as of v2.7, CH07 §7.3.3):
    /// OBR-7 and OBR-25 must stay silent.
    static let nonReportCases: [MessageCase] = [
        .init(version: "2.3", messageType: "ORM^O01"), .init(version: "2.3.1", messageType: "ORM^O01"),
        .init(version: "2.4", messageType: "ORM^O01^ORM_O01"), .init(version: "2.5.1", messageType: "OML^O21^OML_O21"),
        .init(version: "2.6", messageType: "OML^O21^OML_O21"), .init(version: "2.8.2", messageType: "OML^O21^OML_O21"),
        .init(version: "2.8.2", messageType: "ORF^R04^ORF_R04"),
    ]

    /// One order group with OBR-7 and OBR-25 empty; order numbers valued
    /// on both sides so no XOR rule is in play.
    static func obrWithoutResultFields(_ c: MessageCase, orderControl: String) -> String {
        wire([
            msh(c.messageType, c.version), pid,
            segment("ORC", [1: orderControl, 2: "ORD001", 3: "FIL001"]),
            segment("OBR", [1: "1", 2: "ORD001", 3: "FIL001", 4: "GLUC^Glucose^L"]),
            segment("OBX", [1: "1", 2: "NM", 3: "GLU^Glucose^L", 5: "5.2", 11: "F"]),
        ])
    }

    @Test("X-C07: every report message requires OBR-7 and OBR-25", arguments: reportCases)
    func reportMessagesRequireResultFields(_ c: MessageCase) throws {
        let wire = Self.obrWithoutResultFields(c, orderControl: "RE")
        #expect(try conditionalHits(wire, field: 7).count == 1, "\(c.testDescription) OBR-7")
        #expect(try conditionalHits(wire, field: 25).count == 1, "\(c.testDescription) OBR-25")
    }

    @Test("X-C07: orders (and withdrawn ORF on v2.8.2) do not require OBR-7 or OBR-25", arguments: nonReportCases)
    func nonReportMessagesDoNotRequireResultFields(_ c: MessageCase) throws {
        let wire = Self.obrWithoutResultFields(c, orderControl: "NW")
        #expect(try conditionalHits(wire, field: 7).isEmpty, "\(c.testDescription) OBR-7")
        #expect(try conditionalHits(wire, field: 25).isEmpty, "\(c.testDescription) OBR-25")
    }

    // MARK: - P1-3: order numbers without ORC (X-C08)

    /// ORU / ORF with no ORC: the placer (OBR-2) and filler (OBR-3) order
    /// numbers must be in OBR (v2.3 §4.3.1.2-3; v2.4+ §4.5.1.2-3, §4.5.3.2-3).
    static func resultWithoutORC(_ messageType: String, _ version: String, placer: String?, filler: String?) -> String {
        var obr: [Int: String] = [1: "1", 4: "GLUC^Glucose^L", 7: "20240401080000", 25: "F"]
        if let placer { obr[2] = placer }
        if let filler { obr[3] = filler }
        return wire([
            msh(messageType, version), pid,
            segment("OBR", obr),
            segment("OBX", [1: "1", 2: "NM", 3: "GLU^Glucose^L", 5: "5.2", 11: "F"]),
        ])
    }

    @Test("X-C08: ORU / ORF without ORC require OBR-3, and OBR-2 where the version says so",
          arguments: ["2.3", "2.3.1", "2.4", "2.5.1", "2.6"], ["ORU^R01", "ORF^R04"])
    func orderNumbersRequiredWithoutORC(version: String, messageType: String) throws {
        let noPlacer = Self.resultWithoutORC(messageType, version, placer: nil, filler: "FIL001")
        #expect(try Parser().parse(noPlacer)["OBR-25"] == "F", "Wire mis-counted")
        // P4-7: v2.3 / v2.3.1 CH07 §7.3.1.0 and v2.4 CH07 §7.4.1.0 let the placer
        // number be blank when the filler initiates the order; v2.5.1 drops that.
        let placerMayBeBlank = ["2.3", "2.3.1", "2.4"].contains(version)
        #expect(try conditionalHits(noPlacer, field: 2).count == (placerMayBeBlank ? 0 : 1),
                "v\(version) \(messageType) OBR-2")
        let noFiller = Self.resultWithoutORC(messageType, version, placer: "ORD001", filler: nil)
        #expect(try conditionalHits(noFiller, field: 3).count == 1, "v\(version) \(messageType) OBR-3")
        let both = Self.resultWithoutORC(messageType, version, placer: "ORD001", filler: "FIL001")
        #expect(try conditionalHits(both, field: 2).isEmpty, "v\(version) \(messageType) OBR-2 valued")
        #expect(try conditionalHits(both, field: 3).isEmpty, "v\(version) \(messageType) OBR-3 valued")
    }

    /// OUL R24 prints OBR before [ORC] (v2.5.1 CH07 §7.3.9). The trailing
    /// ORC carries the numbers; the ORU/ORF gate keeps the ORC-absent leg
    /// from misfiring here.
    @Test("X-C08 guard: OUL R24 with a trailing ORC stays silent", arguments: ["2.5.1", "2.6"])
    func trailingORCDoesNotMisfire(version: String) throws {
        let wire = Self.wire([
            Self.msh("OUL^R24^OUL_R24", version), Self.pid,
            Self.segment("OBR", [1: "1", 4: "GLUC^Glucose^L", 7: "20240401080000", 25: "F"]),
            Self.segment("ORC", [1: "RE", 2: "ORD001", 3: "FIL001"]),
            Self.segment("OBX", [1: "1", 2: "NM", 3: "GLU^Glucose^L", 5: "5.2", 11: "F"]),
        ])
        #expect(try conditionalHits(wire, field: 2).isEmpty, "v\(version) OBR-2")
        #expect(try conditionalHits(wire, field: 3).isEmpty, "v\(version) OBR-3")
    }

    /// P1 fix wave: pins the ORC-absent leg's scope. OUL is not ORU/ORF, so
    /// a v2.4 OUL^R21 with no ORC and empty OBR-2/OBR-3 must stay silent
    /// (the ORC-absent leg is scoped to ORU/ORF by design, X-C08).
    @Test("X-C08 scope pin: v2.4 OUL R21 without ORC and empty OBR-2/OBR-3 stays silent")
    func oulR21WithoutORCDoesNotMisfire() throws {
        let wire = Self.resultWithoutORC("OUL^R21^OUL_R21", "2.4", placer: nil, filler: nil)
        #expect(try conditionalHits(wire, field: 2).isEmpty, "v2.4 OUL^R21 OBR-2")
        #expect(try conditionalHits(wire, field: 3).isEmpty, "v2.4 OUL^R21 OBR-3")
    }

    // MARK: - P1-4: OBR-29 child-order rule (V24-C11, V251-C05b, V26-C13)

    private func triggers(_ condition: String, onOBRof wire: String) throws -> Bool {
        let message = try Parser().parse(wire)
        let index = try #require(message.segments.firstIndex { $0.segmentID == "OBR" })
        return Validator().conditionTriggers(
            condition, in: message.segments[index], segmentIndex: index,
            message: message, currentSegmentID: "OBR"
        )
    }

    /// `ORC-1 = CH` on OBR resolves through the OBR's own group, while
    /// `ORC absent` asserts that group has no ORC. They cannot both hold.
    @Test("V24-C11: the OBR-29 leg `ORC-1 = CH AND ORC absent` is never true")
    func obr29FirstLegIsUnsatisfiable() throws {
        let leg = "ORC-1 = CH AND ORC absent"
        let noORC = Self.wire([Self.msh("ORU^R01", "2.4"), Self.pid,
                               Self.segment("OBR", [1: "1", 2: "ORD002", 3: "FIL002", 4: "GLUC^Glucose^L"])])
        let childORC = Self.wire([Self.msh("ORM^O01", "2.4"), Self.pid,
                                  Self.segment("ORC", [1: "CH", 2: "ORD002"]),
                                  Self.segment("OBR", [1: "1", 2: "ORD002", 4: "GLUC^Glucose^L"])])
        let trailingChildORC = Self.wire([Self.msh("OUL^R24^OUL_R24", "2.5.1"), Self.pid,
                                          Self.segment("OBR", [1: "1", 2: "ORD002", 4: "GLUC^Glucose^L"]),
                                          Self.segment("ORC", [1: "CH", 2: "ORD002"])])
        for wire in [noORC, childORC, trailingChildORC] {
            #expect(try !triggers(leg, onOBRof: wire))
        }
    }

    @Test("V24-C11: OBR-29 metadata is the satisfiable child-order rule",
          arguments: ["2.3", "2.3.1", "2.4", "2.5.1", "2.6"])
    func obr29Condition(version: String) {
        // P4-7: gated off the OBR-before-ORC structures on v2.5.1 (OUL) and
        // v2.6 (OUL, OPU, OPL) until P8 group ranges.
        let gate = ["2.5.1": " AND messageCode not in (OUL)", "2.6": " AND messageCode not in (OUL, OPU, OPL)"][version] ?? ""
        #expect(Self.table(version)["OBR"]?.field(29)?.condition == "ORC-1 = CH AND ORC-8 empty" + gate, "v\(version)")
    }

    @Test("OBR-29 still fires on a child order with no parent anywhere",
          arguments: ["2.3", "2.3.1", "2.4", "2.5.1", "2.6"])
    func obr29FiresOnChildWithoutParent(version: String) throws {
        let wire = Self.wire([
            Self.msh(version == "2.3" || version == "2.3.1" ? "ORM^O01" : "ORM^O01^ORM_O01", version), Self.pid,
            Self.segment("ORC", [1: "CH", 2: "ORD002"]),
            Self.segment("OBR", [1: "1", 2: "ORD002", 4: "GLUC^Glucose^L"]),
        ])
        #expect(try conditionalHits(wire, field: 29).count == 1, "v\(version)")
    }
}
