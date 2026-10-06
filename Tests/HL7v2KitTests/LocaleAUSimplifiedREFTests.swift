// LocaleAUSimplifiedREFTests.swift
// P12 S1-1 (ADR-019 "HL7au:00060.1", amendment "P12 S1"; owner ruling G-AU3): ADRM-2021
// Appendix 8, the simplified REF profile. A REF^I12 whose MSH-12.3.1 declares the profile
// (A8.3, p 483) is matched under .auLocalisation against the constrained REF_I12 of A8.5
// (pp 484 to 485), a variant of the AU REF_I12 profile structure selected by the declaration;
// a REF^I12 without it keeps the full AU REF_I12 (section 7.2.1, pp 324 to 325).

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("AU HL7au:00060.1: the Appendix 8 simplified REF profile structure (P12 S1-1)")
struct LocaleAUSimplifiedREFTests {

    static let rule = "HL7au:00060.1"
    static let level2 = "HL7AU-OO-REF-SIMPLIFIED-201706"
    static let level1 = "HL7AU-OO-REF-SIMPLIFIED-201706-L1"

    /// MSH-12 as A8.3 prints it for `profile`, or the bare version when nil.
    static func vid(_ profile: String?) -> String {
        profile.map { "2.4^AUS&Australia&ISO3166_1^\($0)&&L" } ?? "2.4"
    }

    private func issues(_ msh9: String, _ body: [String], declaring profile: String? = Self.level2,
                        locale: HL7Locale = .auLocalisation) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .warning
        let wire = TestWires.msh(msh9, Self.vid(profile)) + body.map { $0 + "\r" }.joined()
        return Validator(options: options, locale: locale).validate(try Parser(locale: locale).parse(wire)).issues
    }

    private func au(_ issues: [ValidationIssue]) -> [ValidationIssue] {
        issues.filter { $0.code == .profileConstraintViolation(localeRule: Self.rule) }
    }

    private func base(_ issues: [ValidationIssue]) -> [ValidationIssue] {
        issues.filter {
            switch $0.code {
            case .messageStructureSegmentMissing, .messageStructureSegmentUnexpected, .messageStructureMismatch: return true
            default: return false
            }
        }
    }

    static let conformant = ["RF1|A", "PRD|RP", "PID|1", "AL1|1", "OBR|1", "OBX|1", "OBX|2", "OBR|2", "OBX|3",
                             "PV1|1", "PV2|", "ORC|NW", "RXO|1", "RXR|1", "RXC|B", "OBX|4"]

    @Test("A REF^I12 declaring either level of the simplified profile in the A8.5 shape is clean",
          arguments: [Self.level2, Self.level1])
    func conformantIsClean(_ profile: String) throws {
        let all = try issues("REF^I12^REF_I12", Self.conformant, declaring: profile)
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
    }

    @Test("Declared simplified REF^I12 without the OBR group: 00060.1 requires OBR (A8.5 prints {OBR {OBX}}); the full profile accepts it")
    func withoutObservationGroup() throws {
        let body = ["RF1|A", "PRD|RP", "PID|1", "PV1|1"]
        let found = au(try issues("REF^I12^REF_I12", body))
        try #require(found.count == 1, "\(found.map(\.message))")
        #expect(found[0].message.contains("requires OBR"), "\(found[0].message)")
        #expect(found[0].message.contains("Appendix 8"), "\(found[0].message)")
        #expect(found[0].location.pathDescription == "PV1[1]")
        #expect(au(try issues("REF^I12^REF_I12", body, declaring: nil)).isEmpty)
        #expect(au(try issues("REF^I12^REF_I12", body, locale: .international)).isEmpty)
    }

    @Test("Declared simplified REF^I12 with an OBR and no OBX: 00060.1 requires OBX; the full profile accepts it")
    func withoutOBX() throws {
        let body = ["RF1|A", "PRD|RP", "PID|1", "OBR|1", "PV1|1"]
        let found = au(try issues("REF^I12^REF_I12", body))
        try #require(found.count == 1, "\(found.map(\.message))")
        #expect(found[0].message.contains("requires OBX in group OBSERVATION before PV1[1]"), "\(found[0].message)")
        #expect(found[0].location.pathDescription == "PV1[1]")
        #expect(au(try issues("REF^I12^REF_I12", body, declaring: nil)).isEmpty)
    }

    @Test("Declared simplified REF^I12 with an ORC and no RXO: 00060.1 requires RXO and RXR; the full profile accepts it")
    func orderWithoutRXO() throws {
        let body = ["RF1|A", "PRD|RP", "PID|1", "OBR|1", "OBX|1", "PV1|1", "ORC|NW"]
        let found = au(try issues("REF^I12^REF_I12", body))
        // A8.5 prints `ORC RXO {RXR}`: both RXO and RXR are required after the ORC.
        try #require(found.count == 2, "\(found.map(\.message))")
        #expect(found[0].message.contains("requires RXO in group ORC_GROUP at the end of the message"), "\(found[0].message)")
        #expect(found[1].message.contains("requires RXR in group ORC_GROUP"), "\(found[1].message)")
        #expect(found.allSatisfy { $0.location.pathDescription == "ORC[1]" })
        #expect(au(try issues("REF^I12^REF_I12", body, declaring: nil)).isEmpty)
    }

    @Test("Declared simplified REF^I12 with a segment A8.5 omits (PD1, DG1): not a 00060.1 finding (ADR-019 decision 7)")
    func omittedSegmentIsNotAFinding() throws {
        let all = try issues("REF^I12^REF_I12", ["RF1|A", "PRD|RP", "PID|1", "PD1|", "DG1|1", "OBR|1", "OBX|1", "PV1|1"])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
    }

    @Test("A REF^I12 declaring another internal version ID keeps the full AU profile (p 42: identifiers are not parsed)",
          arguments: ["HL7AU-OO-REF-SIMPLIFIED-201801", "HL7AU-OO-REF-201701", "hl7au-oo-ref-simplified-201706"])
    func otherDeclarationKeepsFullProfile(_ profile: String) throws {
        #expect(au(try issues("REF^I12^REF_I12", ["RF1|A", "PRD|RP", "PID|1", "PV1|1"], declaring: profile)).isEmpty)
        let found = au(try issues("REF^I12^REF_I12", ["RF1|A", "PRD|RP", "PID|1"], declaring: profile))
        #expect(found.count == 1 && found.first?.message.contains("requires PV1") == true, "\(found.map(\.message))")
    }

    @Test("RRI^I12 declaring the simplified profile keeps the chapter 7 RRI_I12 (A8.5: the same RRI_I12 structure)")
    func rriIsUnchanged() throws {
        let found = au(try issues("RRI^I12^RRI_I12", ["RF1|A", "PRD|RP", "PID|1"]))
        try #require(found.count == 1, "\(found.map(\.message))")
        #expect(found[0].message.contains("requires MSA"), "\(found[0].message)")
        #expect(au(try issues("RRI^I12^RRI_I12", ["MSA|AA|1"])).isEmpty)
    }

    @Test("The AU REF_I12 carries one variant, selected by the two A8.3 declarations, never by the trigger alone")
    func variantData() throws {
        let structure = try #require(MessageStructureTable.auADRM2021["REF_I12"])
        try #require(structure.variants.count == 1)
        let variant = structure.variants[0]
        #expect(variant.triggers == ["REF^I12"])
        #expect(variant.profileIdentifiers == [Self.level2, Self.level1])
        #expect(variant.citation.contains("Appendix 8"))
        #expect(structure.variant(messageCode: "REF", triggerEvent: "I12") == nil)
        #expect(structure.selectingVariant(messageCode: "REF", triggerEvent: "I12", declaredProfile: Self.level1).elements
                == variant.elements)
        #expect(structure.selectingVariant(messageCode: "REF", triggerEvent: "I12", declaredProfile: nil).elements
                == structure.elements)
        // Base structures carry no profile-selected variant.
        for id in ["REF_I12", "RRI_I12"] {
            let baseStructure = try #require(MessageStructureTable.structure(id, version: .v2_4))
            #expect(baseStructure.variants.allSatisfy { $0.profileIdentifiers.isEmpty }, "\(id)")
        }
    }

    @Test("The test decoder admits profileIdentifiers in a profile file only, and requires them there")
    func decoderGatesProfileIdentifiers() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/structures/profiles/au-adrm-2021/REF_I12.json")
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for key in ["profile", "baseVersion", "rule"] { object.removeValue(forKey: key) }
        func decode(_ object: [String: Any], profile: Bool) throws -> MessageStructure {
            try StructureJSONDecoder.decode(try JSONSerialization.data(withJSONObject: object), id: "REF_I12", version: "2.4",
                                            profile: profile)
        }
        #expect(try decode(object, profile: true).variants.first?.profileIdentifiers == [Self.level2, Self.level1])
        #expect(throws: (any Error).self) { try decode(object, profile: false) }
        var variants = try #require(object["variants"] as? [[String: Any]])
        variants[0].removeValue(forKey: "profileIdentifiers")
        object["variants"] = variants
        #expect(throws: (any Error).self) { try decode(object, profile: true) }
    }
}
