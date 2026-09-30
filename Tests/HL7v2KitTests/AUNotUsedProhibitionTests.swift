// AUNotUsedProhibitionTests.swift
// P4-27 — AU "not used" elements: OBR-26 and ORC-24 (ADRM-prose:P-11/P-12).
//
// AU ADRM-2021 §4.4.1.26, p. 228 (OBR-26 Parent Result): "Not used in
// Australian messages. Use observation Sub-ID in OBX-4 to link results."
// Unconditional; no base v2.4 condition exists on OBR-26 (optionality O),
// so nothing else in the spec requires it to be valued. Scope: OBR is
// shared by ORM, ORU and REF, all defined against the same ch. 4 table.
//
// AU ADRM-2021 §7.3.11.24, p. 343 (ORC-24 Ordering Provider Address):
// "This field should not be used. Use ORC-22 for the address of the
// prescriber's facility." AU-specific (base v2.4 and the ADRM's own
// Observation Ordering chapter carry no such note) and scoped to
// Referrals only, where the sentence appears. Modal "should" — warning.
//
// OBR-29 (ADRM §4.4.1.29, same "Not used" sentence as OBR-26) is
// deliberately NOT enforced here — it conflicts with the base v2.4
// condition `ORC-1 = CH AND ORC-8 empty` that makes OBR-29 conditionally
// required (v2.4/OBR.json), and with ORC-8's own mirrored condition
// (v2.4/ORC.json). See task-P4-27-report.md for the NEEDS_CONTEXT
// write-up.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("AU ADRM-prose:P-11 — OBR-26 Parent Result not used in Australia (P4-27)")
struct AUP11OBR26ProhibitionTests {

    private static func wire(_ messageType: String, obr26: String?) -> String {
        var fields: [Int: String] = [1: "1", 2: "PLACER1", 3: "FILLER1", 4: "GLU^Glucose^L"]
        if let obr26 { fields[26] = obr26 }
        return TestWires.msh(messageType, "2.4")
            + "PID|1||123^^^HOSP^MR||DOE^JOHN\r"
            + "ORC|NW|PLACER1^HOSP^1.2.36.1.2001.1003.0.ABC^ISO\r"
            + TestWires.segment("OBR", fields) + "\r"
    }

    private static func prohibitions(
        _ wire: String,
        locale: HL7Locale = .auLocalisation
    ) throws -> [ValidationIssue] {
        let message = try Parser(locale: locale).parse(wire)
        return Validator(locale: locale).validate(message).issues.filter { issue in
            guard case .profileConstraintViolation(let rule) = issue.code else { return false }
            return rule.contains("P-11")
        }
    }

    @Test("OBR-26 valued raises ADRM-prose:P-11 as an error", arguments: ["ORM^O01", "ORU^R01", "REF^I12"])
    func obr26ValuedFires(messageType: String) throws {
        let issues = try Self.prohibitions(Self.wire(messageType, obr26: "1234^GLU-PARENT^HOSP"))
        let hit = try #require(issues.first { $0.location.segmentID == "OBR" && $0.location.fieldIndex == 26 })
        #expect(hit.severity == .error)
    }

    @Test("OBR-26 empty stays silent")
    func obr26EmptyIsSilent() throws {
        let issues = try Self.prohibitions(Self.wire("ORU^R01", obr26: nil))
        #expect(issues.isEmpty, "got \(issues.map(\.message))")
    }

    @Test("OBR-26 valued with the HL7 null stays silent")
    func obr26ExplicitNullIsSilent() throws {
        let issues = try Self.prohibitions(Self.wire("ORU^R01", obr26: "\"\""))
        #expect(issues.isEmpty, "got \(issues.map(\.message))")
    }

    @Test("The same wire under .international raises no ADRM-prose:P-11")
    func internationalIsSilent() throws {
        let issues = try Self.prohibitions(
            Self.wire("ORU^R01", obr26: "1234^GLU-PARENT^HOSP"),
            locale: .international)
        #expect(issues.isEmpty, "got \(issues.map(\.message))")
    }

    @Test("A message type outside Orders, Results and Referrals stays silent")
    func outOfScopeMessageTypeIsSilent() throws {
        let issues = try Self.prohibitions(Self.wire("ADT^A01", obr26: "1234^GLU-PARENT^HOSP"))
        #expect(issues.isEmpty, "got \(issues.map(\.message))")
    }
}

@Suite("AU ADRM-prose:P-12 — ORC-24 Ordering Provider Address not used in Referrals (P4-27)")
struct AUP12ORC24ProhibitionTests {

    private static func wire(_ messageType: String, orc24: String?) -> String {
        var fields: [Int: String] = [1: "NW"]
        if let orc24 { fields[24] = orc24 }
        return TestWires.msh(messageType, "2.4")
            + "PID|1||123^^^HOSP^MR||DOE^JOHN\r"
            + TestWires.segment("ORC", fields) + "\r"
            + "OBR|1|PLACER1|FILLER1|GLU^Glucose^L\r"
    }

    private static func prohibitions(
        _ wire: String,
        locale: HL7Locale = .auLocalisation
    ) throws -> [ValidationIssue] {
        let message = try Parser(locale: locale).parse(wire)
        return Validator(locale: locale).validate(message).issues.filter { issue in
            guard case .profileConstraintViolation(let rule) = issue.code else { return false }
            return rule.contains("P-12")
        }
    }

    @Test("ORC-24 valued on a Referral raises ADRM-prose:P-12 as a warning")
    func orc24ValuedOnReferralFires() throws {
        let issues = try Self.prohibitions(Self.wire("REF^I12", orc24: "1 Clinic St^^Sydney^NSW^2000^AU"))
        let hit = try #require(issues.first { $0.location.segmentID == "ORC" && $0.location.fieldIndex == 24 })
        #expect(hit.severity == .warning)
    }

    @Test("ORC-24 empty on a Referral stays silent")
    func orc24EmptyIsSilent() throws {
        let issues = try Self.prohibitions(Self.wire("REF^I12", orc24: nil))
        #expect(issues.isEmpty, "got \(issues.map(\.message))")
    }

    @Test("The same wire under .international raises no ADRM-prose:P-12")
    func internationalIsSilent() throws {
        let issues = try Self.prohibitions(
            Self.wire("REF^I12", orc24: "1 Clinic St^^Sydney^NSW^2000^AU"),
            locale: .international)
        #expect(issues.isEmpty, "got \(issues.map(\.message))")
    }

    @Test("ORC-24 valued on an Order (not a Referral) stays silent")
    func outOfScopeMessageTypeIsSilent() throws {
        let issues = try Self.prohibitions(Self.wire("ORM^O01", orc24: "1 Clinic St^^Sydney^NSW^2000^AU"))
        #expect(issues.isEmpty, "got \(issues.map(\.message))")
    }
}
