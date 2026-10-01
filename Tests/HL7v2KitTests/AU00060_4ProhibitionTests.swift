// AU00060_4ProhibitionTests.swift
// P4-24 — HL7au:00060.4 route B: OBX-2 / OBX-5 under OBX-11 = O. P4-26 moved
// the rule into the base grammar, so AU traffic now gets the base
// `.conditionalFieldProhibited` issue and no AU duplicate.
//
// HL7 v2.4 §7.4.2.11 (OBX-11): "The status of O shall be used to indicate
// that the OBX segment is used for a dynamic specification of the required
// result. An OBX used for a dynamic specification must contain the detailed
// examination code, units, etc., with OBX-11 valued with O, and OBX-2 and
// OBX-5 valued with null."
//
// OBX-2 and OBX-5 are both C elements (v2.4 and ADRM 2021 attribute table),
// so under HL7au:00060.4 a sender of Orders, Results or Referrals must not
// value them while OBX-11 = O. The HL7 null ("") is what the text asks for,
// so it stays silent.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("AU HL7au:00060.4 route B: OBX-2 / OBX-5 null under OBX-11 = O (P4-24, base since P4-26)")
struct AU00060_4ProhibitionTests {

    private static func wire(_ messageType: String, obx: String) -> String {
        TestWires.msh(messageType, "2.4")
            + "PID|1||123^^^HOSP^MR||DOE^JOHN\r"
            + "ORC|NW|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO\r"
            + "OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO||GLU^Glucose^L\r"
            + obx + "\r"
    }

    private static func issues(
        _ wire: String,
        locale: HL7Locale = .auLocalisation
    ) throws -> [ValidationIssue] {
        let message = try Parser(locale: locale).parse(wire)
        return Validator(locale: locale).validate(message).issues
    }

    /// The base dynamic-specification prohibitions on OBX-2 and OBX-5.
    private static func prohibitions(
        _ wire: String,
        locale: HL7Locale = .auLocalisation
    ) throws -> [ValidationIssue] {
        try issues(wire, locale: locale).filter { issue in
            issue.code == .conditionalFieldProhibited && issue.location.segmentID == "OBX"
                && [2, 5].contains(issue.location.fieldIndex)
        }
    }

    @Test("OBX-2 valued while OBX-11 = O raises the base prohibition as an error", arguments: ["ORM^O01", "ORU^R01", "REF^I12"])
    func obx2ValuedUnderDynamicSpecificationFires(messageType: String) throws {
        let issues = try Self.prohibitions(Self.wire(messageType, obx: "OBX|1|NM|GLU-30^Glucose -30 min^L|||mmol/L|||||O"))
        let hit = try #require(issues.first { $0.location.segmentID == "OBX" && $0.location.fieldIndex == 2 })
        #expect(hit.severity == .error)
        #expect(!issues.contains { $0.location.fieldIndex == 5 })
    }

    // P4-16: parameterised to match `obx2ValuedUnderDynamicSpecificationFires`
    // above. The base rule (since P4-26) fires on every message type, not
    // just these three, but the AU candidate set this suite exists to pin
    // is ORM/ORU/REF (CH04/CH07/CH11), so the coverage stays scoped there.
    @Test("OBX-5 valued while OBX-11 = O raises the base prohibition as an error", arguments: ["ORM^O01", "ORU^R01", "REF^I12"])
    func obx5ValuedUnderDynamicSpecificationFires(messageType: String) throws {
        let issues = try Self.prohibitions(Self.wire(messageType, obx: "OBX|1|\"\"|GLU-30^Glucose -30 min^L||5.2|mmol/L|||||O"))
        let hit = try #require(issues.first { $0.location.segmentID == "OBX" && $0.location.fieldIndex == 5 })
        #expect(hit.severity == .error)
        #expect(!issues.contains { $0.location.fieldIndex == 2 })
    }

    @Test("OBX-2 and OBX-5 valued with the HL7 null under OBX-11 = O stay silent")
    func explicitNullIsPermitted() throws {
        let issues = try Self.prohibitions(Self.wire("ORM^O01", obx: "OBX|1|\"\"|GLU-30^Glucose -30 min^L||\"\"|mmol/L|||||O"))
        #expect(issues.isEmpty, "got \(issues.map(\.message))")
    }

    @Test("OBX-2 and OBX-5 valued while OBX-11 is not O stay silent")
    func conditionFalseIsSilent() throws {
        let issues = try Self.prohibitions(Self.wire("ORU^R01", obx: "OBX|1|NM|GLU^Glucose^L||5.2|mmol/L|||||F"))
        #expect(issues.isEmpty, "got \(issues.map(\.message))")
    }

    @Test("The same wire under .international raises the same base prohibition")
    func internationalFiresTheSameBaseIssue() throws {
        let wire = Self.wire("ORM^O01", obx: "OBX|1|NM|GLU-30^Glucose -30 min^L||5.2|mmol/L|||||O")
        let au = try Self.prohibitions(wire)
        let international = try Self.prohibitions(wire, locale: .international)
        #expect(international.map(\.location.fieldIndex) == [2, 5])
        #expect(au.map(\.location.fieldIndex) == international.map(\.location.fieldIndex))
    }

    @Test("AU reports the rule once: no HL7au:00060.4 profile duplicate beside the base issue")
    func auDoesNotDoubleReport() throws {
        let issues = try Self.issues(Self.wire("ORU^R01", obx: "OBX|1|NM|GLU-30^Glucose -30 min^L||5.2|mmol/L|||||O"))
        #expect(!issues.contains { issue in
            guard case .profileConstraintViolation(let rule) = issue.code else { return false }
            return rule.contains("00060.4")
        }, "got \(issues.map(\.message))")
    }
}
