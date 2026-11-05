// StructureV291ProbeTests.swift
// v2.9-T12 (requirement 4 evidence): hand-built 2.9.1 messages, one compliant with the chapter print and
// one variant that breaks it, per structure family. Under messageStructureSeverity = .error the compliant
// message draws no structure issue and the variant draws the expected finding. Bodies are minimal and
// synthetic, and only structure issues are read.

import Testing
@testable import HL7v2Kit

@Suite("v2.9.1 structure probes")
struct StructureV291ProbeTests {

    struct Probe: Sendable, CustomTestStringConvertible {
        let structure: String
        let msh9: String
        let compliant: [String]
        let variant: [String]
        /// "missing SEG" or "unexpected SEG": the variant's finding (for a structure
        /// flagged requiresExactMatch, the one finding at the furthest position).
        let finding: String
        var testDescription: String { "\(structure) \(msh9)" }
    }

    // Each compliant body follows the print cited in the structure's JSON
    // (Resources/structures/v2.9.1/<ID>.json); the variant names what it breaks.
    static let probes: [Probe] = [
        // CH03 3.3.1 pp 6 to 8: EVN is required; GSP, GSR and GSC follow PD1, in that order.
        Probe(structure: "ADT_A01", msh9: "ADT^A01^ADT_A01",
              compliant: ["EVN|A01", "PID|1", "GSP|1", "GSR|1", "GSC|1", "PV1|1|I"],
              variant: ["PID|1", "PV1|1|I"], finding: "missing EVN"),
        Probe(structure: "ADT_A01", msh9: "ADT^A01^ADT_A01",
              compliant: ["EVN|A01", "PID|1", "NK1|1", "GSP|1", "GSR|1", "PV1|1|I", "GT1|1", "GSP|2", "GSR|2", "IN1|1", "GSP|3", "GSR|3"],
              variant: ["EVN|A01", "PID|1", "NK1|1", "GSC|1", "PV1|1|I"], finding: "unexpected GSC"),
        // CH03 3.3.15 pp 42 to 43 prints '{{ PRT }}' after PV2, read as [{ PRT }] by a cited erratum: PRT is optional.
        Probe(structure: "ADT_A15", msh9: "ADT^A15^ADT_A15",
              compliant: ["EVN|A15", "PID|1", "PV1|1|I"],
              variant: ["EVN|A15", "PID|1", "PV1|1|I", "PV1|2|I"], finding: "unexpected PV1"),
        // CH11 11.6.1 p 29: PARTICIPATION_CLINICAL_HISTORY_OBJECT is a choice of ROL, PRT or PRD; the print
        // leaves the bar off the ROL row. PATIENT_VISITS is required.
        Probe(structure: "CCM_I21", msh9: "CCM^I21^CCM_I21",
              compliant: ["PID|1", "ORC|1", "ROL|1", "PV1|1"],
              variant: ["PID|1", "ORC|1", "ROL|1"], finding: "missing PV1"),
        Probe(structure: "CCM_I21", msh9: "CCM^I21^CCM_I21",
              compliant: ["PID|1", "ORC|1", "PRT|1", "PV1|1"],
              variant: ["PID|1", "ORC|1", "PRT|1"], finding: "missing PV1"),
        Probe(structure: "CCM_I21", msh9: "CCM^I21^CCM_I21",
              compliant: ["PID|1", "ORC|1", "PRD|1", "PV1|1"],
              variant: ["PID|1", "ORC|1", "PRD|1"], finding: "missing PV1"),
        // CH04 4.16.10 p 169: the row closing DONOR_OBSERVATIONS prints 'begin'; the group ends there,
        // so an OBX after the donor's NTE belongs to nothing.
        Probe(structure: "DRG_O43", msh9: "DRG^O43^DRG_O43",
              compliant: ["PID|1", "OBX|1", "PRT|1", "OBX|2", "NTE|1", "AL1|1", "PV1|1", "PRT|2", "NTE|2"],
              variant: ["PID|1", "OBX|1", "NTE|1", "OBX|2"], finding: "unexpected OBX"),
        // CH04 4.16.12 p 171: the DONOR group (mark printed 'Donor') is optional, DONATION_ORDER required.
        Probe(structure: "DEO_O45", msh9: "DEO^O45^DEO_O45",
              compliant: ["PID|1", "OBX|1", "NTE|1", "PV1|1", "OBR|1", "NTE|2", "OBX|2", "NTE|3"],
              variant: ["PID|1", "OBX|1"], finding: "missing OBR"),
        // CH06 6.4.3 pp 8 to 10: a footnote mark a line above its row ('1  --- COMMON_ORDER begin' over '[ {',
        // '4  Guarantor' over '[ { GT1 } ]') is not the end of the table: FINANCIAL is required after it.
        Probe(structure: "DFT_P03", msh9: "DFT^P03^DFT_P03",
              compliant: ["EVN|P03", "PID|1", "ORC|1", "FT1|1", "ORC|2", "DG1|1", "DRG|1", "GT1|1", "GT1|2", "IN1|1", "ACC|1"],
              variant: ["EVN|P03", "PID|1", "ORC|1"], finding: "missing FT1"),
        Probe(structure: "DFT_P03", msh9: "DFT^P03^DFT_P03",
              compliant: ["EVN|P03", "PID|1", "FT1|1", "DG1|1", "GT1|1", "GT1|2", "IN1|1"],
              variant: ["EVN|P03", "PID|1", "FT1|1", "GT1|1", "DG1|1"], finding: "unexpected DG1"),
        // CH06 6.4.8 pp 17 to 20: '6' over '[ {', 'DG1 7' and '8' over '[ DRG ]'. DIAGNOSIS repeats; DRG does
        // not; FINANCIAL is required; GSP and GSR follow the guarantor (p 18).
        Probe(structure: "DFT_P11", msh9: "DFT^P11^DFT_P11",
              compliant: ["EVN|P11", "PID|1", "ORC|1", "DG1|1", "DG1|2", "DRG|1", "GT1|1", "GSP|1", "GSR|1", "IN1|1", "GSP|2", "GSR|2", "FT1|1", "DG1|3", "DRG|2", "GT1|2", "IN1|2"],
              variant: ["EVN|P11", "PID|1", "DRG|1", "DRG|2", "FT1|1"], finding: "unexpected DRG"),
        // New in v2.9. CH04 4.4.7.2 p 18: the patient is optional, MSA is not.
        Probe(structure: "ORL_O53", msh9: "ORL^O53^ORL_O53",
              compliant: ["MSA|AA|1", "ORC|OK", "OBR|1", "SPM|1", "SAC|1"],
              variant: ["PID|1", "ORC|OK"], finding: "missing MSA"),
        // CH04 4.4.20 p 49: an order carries its document: OBX then TXA.
        Probe(structure: "OMQ_O57", msh9: "OMQ^O57^OMQ_O57",
              compliant: ["ORC|NW", "OBX|1", "TXA|1"],
              variant: ["ORC|NW", "OBX|1"], finding: "missing TXA"),
        // CH04 4.4.21 p 52: TXA is required in ORDER.
        Probe(structure: "ORX_O58", msh9: "ORX^O58^ORX_O58",
              compliant: ["MSA|AA|1", "PID|1", "ORC|OK", "TXA|1"],
              variant: ["MSA|AA|1", "PID|1", "ORC|OK"], finding: "missing TXA"),
        // CH04 4.4.18 p 47: ORDER_STATUS is required; the patient is not.
        Probe(structure: "OSU_O51", msh9: "OSU^O51^OSU_O51",
              compliant: ["ORC|SC", "PRT|1"],
              variant: ["PID|1"], finding: "missing ORC"),
        // CH11 11.3.3 p 15: 2.9.1 prints NEXT_OF_KIN after PID where v2.9 prints [{NTE}].
        Probe(structure: "RPR_I03", msh9: "RPR^I03^RPR_I03",
              compliant: ["MSA|AA|1", "PRD|1", "PID|1", "GSP|1", "NK1|1", "GSP|2", "GSR|2"],
              variant: ["MSA|AA|1", "PRD|1", "PID|1", "NTE|1"], finding: "unexpected NTE"),
        // CH07 7.16.1 pp 171 to 173: NEXT_OF_KIN inside each subject group, whose marks print over three lines.
        Probe(structure: "OSM_R26", msh9: "OSM^R26^OSM_R26",
              compliant: ["SHP|1", "PRT|1", "PAC|1", "SPM|1", "PID|1", "NK1|1", "GSP|1", "GSR|1", "PV1|1", "NK1|2", "GSP|2"],
              variant: ["SHP|1", "PRT|1", "PAC|1", "SPM|1", "PID|1", "GSP|1"], finding: "unexpected GSP"),
        // CH10 10.3 p 14 and 10.4 p 21 print PV1 with no brackets inside PATIENT, where v2.9 prints [ PV1 ].
        // SIU_S12 is exact-matched: one finding, at the furthest position, where RGS stands in place of PV1.
        Probe(structure: "SIU_S12", msh9: "SIU^S12^SIU_S12",
              compliant: ["SCH|1", "PID|1", "PV1|1", "RGS|1"],
              variant: ["SCH|1", "PID|1", "RGS|1"], finding: "unexpected RGS"),
        Probe(structure: "SRM_S01", msh9: "SRM^S01^SRM_S01",
              compliant: ["ARQ|1", "PID|1", "PV1|1", "RGS|1"],
              variant: ["ARQ|1", "PID|1", "RGS|1"], finding: "missing PV1"),
        // CH10 10.3 p 16 prints it inside an optional PATIENT_VISIT, so SRR_S01 needs no PV1.
        Probe(structure: "SRR_S01", msh9: "SRR^S01^SRR_S01",
              compliant: ["MSA|AA|1", "SCH|1", "PID|1", "RGS|1"],
              variant: ["MSA|AA|1", "SCH|1", "PID|1", "PV2|1", "RGS|1"], finding: "unexpected PV2"),
    ]

    private static func structureIssues(_ msh9: String, _ body: [String] = []) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|2.9.1"] + body).joined(separator: "\r")
        return Validator(options: options).validate(try Parser().parse(wire)).issues.filter(\.code.isMessageStructure)
    }

    private static func describe(_ code: IssueCode) -> String {
        switch code {
        case .messageStructureSegmentMissing(_, let segment, _): "missing \(segment)"
        case .messageStructureSegmentUnexpected(_, let segment): "unexpected \(segment)"
        default: "\(code)"
        }
    }

    @Test("A compliant message draws no structure issue; the variant draws the finding", arguments: probes)
    func probe(_ p: Probe) throws {
        #expect(MessageStructureTable.structure(p.structure, version: .v2_9_1) != nil, "\(p.structure) is not modelled")
        let ok = try Self.structureIssues(p.msh9, p.compliant)
        #expect(ok.isEmpty, "\(p.testDescription): \(ok.map(\.message))")
        let bad = try Self.structureIssues(p.msh9, p.variant)
        #expect(bad.contains { Self.describe($0.code) == p.finding && $0.severity == .error },
                "\(p.testDescription): \(bad.map { Self.describe($0.code) })")
    }

    // CH01 p 4, "Applied the errata that were identified with V2.9": v2.9's per-trigger prints are gone.
    @Test("What v2.9's own print of a trigger allowed is a finding on 2.9.1, whose print agrees with the default",
          arguments: [
            // CH03 3.3.13 p 36 prints [ OH3 ] where v2.9's p 32 prints [{ OH3 }].
            ("ADT^A13^ADT_A01", ["EVN|A13", "PID|1", "OH3|1", "OH3|2", "PV1|1|I"], "unexpected OH3"),
            // CH03 3.3.28 p 62 prints NK1 required in NEXT_OF_KIN where v2.9's p 55 prints [{ NK1 }].
            ("ADT^A28^ADT_A05", ["EVN|A28", "PID|1", "PRT|1", "OH2|1", "PV1|1|I"], "unexpected OH2"),
            // CH07 7.3.12 p 36 prints PRT required in OBSERVATION_PARTICIPATION where v2.9's pp 32 to 34 print [{PRT}].
            ("ORU^R40^ORU_R01", ["OBR|1", "DEV|1", "TQ1|1"], "unexpected TQ1"),
          ] as [(String, [String], String)])
    func variantsGone(_ c: (msh9: String, body: [String], finding: String)) throws {
        let found = try Self.structureIssues(c.msh9, c.body)
        #expect(found.map { Self.describe($0.code) } == [c.finding], "\(c.msh9): \(found.map(\.message))")
    }

    // CH04A 4A.3.6 pp 9 to 10 names the RXC group COMPONENT, 4A.3.16 pp 25 to 26 COMPONENTS; the segments agree.
    @Test("RDE^O25 selects its own print, which differs in a group name")
    func rdeVariant() throws {
        let rde = try #require(MessageStructureTable.structure("RDE_O11", version: .v2_9_1))
        #expect(rde.variants.map(\.triggers) == [["RDE^O25"]])
        let body = ["ORC|1", "RXO|1", "RXR|1", "RXC|1", "RXE|1", "TQ1|1", "RXR|2"]
        #expect(try Self.structureIssues("RDE^O25^RDE_O11", body).isEmpty)
        #expect(try Self.structureIssues("RDE^O11^RDE_O11", body).isEmpty)
    }

    // What the print gives but no syntax: each is information naming the structure, never a mismatch.
    @Test("A printed ID with no syntax is information, whatever the trigger",
          arguments: [
            // CH02C pp 347 to 348: SET rows naming no event, so any event is reported the same way.
            ("SET^S38^SET_S38", "SET_S38"), ("SET^S39^SET_S38", "SET_S38"), ("SET^S52^SET_S52", "SET_S52"),
            // CH02C p 342: the row misprints INR_U14 as INV_U14.
            ("INV^U14^INV_U14", "INV_U14"), ("INR^U14^INV_U14", "INV_U14"),
            // CH02C p 346, CH05 5.1.6 p 14: withdrawn, and no chapter prints it.
            ("RDR^RDR^RDR_RDR", "RDR_RDR"), ("RDR^RDR", "RDR^RDR"), ("UDM^Q05^UDM_Q05", "UDM_Q05"),
            // CH02C p 341 prints an event on this Deprecated row, where v2.9's prints none.
            ("ADR^A19^ADR_A19", "ADR_A19"), ("ADR^A19", "ADR^A19"),
            // Acknowledgment Choreography cells: CH03 p 106, CH11 p 25, CH16 p 29, CH03 p 72, CH10 p 16.
            ("RSP^K24^RSP_K24", "RSP_K24"), ("RPI^I12^RPI_I12", "RPI_I12"), ("RPI^I15^RPI_I12", "RPI_I12"),
            ("RSP^E22^RSP_E03", "RSP_E03"), ("ADT^A37^ACK", "ACK"), ("ACK^S01^SRR_S01", "SRR_S01"), ("ACK^S11^SRR_S01", "SRR_S01"),
            // CH05 5.3 (pp 38 to 40): 'may specify a unique trigger event value in its Query Profile'.
            ("QBP^Q11^QBP_Q11", "QBP_Q11"), ("QBP^Q31^QBP_Q11", "QBP_Q11"), ("QBP^Q61^QBP_Q11", "QBP_Q11"), ("QBP^Q11", "QBP^Q11"),
            ("QBP^Q15^QBP_Q15", "QBP_Q15"), ("QBP^Q41^QBP_Q15", "QBP_Q15"),
            ("RSP^K11^RSP_K11", "RSP_K11"), ("RSP^K61^RSP_K11", "RSP_K11"),
            ("QBP^Q13^QBP_Q13", "QBP_Q13"), ("QBP^Q40^QBP_Q13", "QBP_Q13"),
          ] as [(String, String)])
    func registered(_ c: (msh9: String, structure: String)) throws {
        let issues = try Self.structureIssues(c.msh9)
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: c.structure)], "\(c.msh9): \(issues.map(\.message))")
        #expect(issues.first?.severity == .info, "\(c.msh9)")
    }

    // CH05 5.3.5 pp 44 to 45 gives QVR no varying event ('Event Q17'), so its list stays closed.
    @Test("QVR_Q17 keeps its one printed trigger")
    func qvrClosed() throws {
        #expect(try Self.structureIssues("QVR^Q17^QVR_Q17").map(\.code) == [.messageStructureNotModelled(structure: "QVR_Q17")])
        let other = try Self.structureIssues("QVR^Q61^QVR_Q17")
        #expect(other.map(\.code) == [.messageStructureMismatch(declared: "QVR_Q17", trigger: "QVR^Q61")], "\(other.map(\.message))")
    }

    // CH04A 4A.3.16 p 27 prints RRE^O26^RRE_O12 in the cells where v2.9's p 25 printed RRE^O26^RRE_O26.
    @Test("RRE^O26^RRE_O26 is printed on v2.9 and not on 2.9.1, so it draws the mismatch here")
    func correctedCell() throws {
        #expect(MessageStructureTable.registration("RRE_O26", version: .v2_9) != nil)
        #expect(MessageStructureTable.registration("RRE_O26", version: .v2_9_1) == nil)
        let found = try Self.structureIssues("RRE^O26^RRE_O26")
        #expect(found.map(\.code) == [.messageStructureMismatch(declared: "RRE_O26", trigger: "RRE^O26")], "\(found.map(\.message))")
    }

    // MARK: - Under the AU locale

    private static func underAU(_ msh9: String, _ body: [String], version: String = "2.9.1") throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|\(version)"] + body).joined(separator: "\r")
        return Validator(options: options, locale: .auLocalisation).validate(try Parser(locale: .auLocalisation).parse(wire)).issues
    }

    @Test("Under the AU locale a 2.9.1 message is matched against 2.9.1's print",
          arguments: [("ORU^R01^ORU_R01", ["PID|1", "OBR|1", "OBX|1"]),
                      ("REF^I12^REF_I12", ["RF1|1", "PRD|1", "PID|1"]),
                      ("OML^O21^OML_O21", ["ORC|NW", "OBR|1"])] as [(String, [String])])
    func auBase(_ c: (msh9: String, body: [String])) throws {
        let found = try Self.underAU(c.msh9, c.body).filter(\.code.isMessageStructure)
        #expect(found.isEmpty, "\(c.msh9): \(found.map(\.message))")
    }

    // The ADRM's structures rest on v2.4, so structure.baseVersion == base.version never holds on 2.9.1.
    @Test("The ADRM's structures do not reach 2.9.1: an ORU with no PID fires HL7au:00060.1 on v2.4 alone")
    func auProfileStructure() throws {
        func fired(_ version: String) throws -> Bool {
            try Self.underAU("ORU^R01^ORU_R01", ["OBR|1", "OBX|1"], version: version).contains {
                if case .profileConstraintViolation(let rule) = $0.code { rule.hasPrefix("HL7au:00060.1") } else { false }
            }
        }
        #expect(try fired("2.4"))
        #expect(try !fired("2.9.1"))
    }

    // ORM_O01 prints no syntax on 2.9.1 (Table 0354 p 345, Deprecated): information under the base rule, as on any locale.
    @Test("Under the AU locale a 2.9.1 ORM stays information: the print has no syntax")
    func auORM() throws {
        let found = try Self.underAU("ORM^O01^ORM_O01", ["PID|1", "ORC|NW", "OBR|1"]).filter(\.code.isMessageStructure)
        #expect(found.map(\.code) == [.messageStructureNotModelled(structure: "ORM_O01")], "\(found.map(\.message))")
    }

    @Test("Under the AU locale a 2.9.1 structure defect is still the base finding")
    func auDefect() throws {
        let found = try Self.underAU("ORU^R01^ORU_R01", ["PID|1"]).filter(\.code.isMessageStructure)
        #expect(found.map { Self.describe($0.code) } == ["missing OBR"], "\(found.map(\.message))")
    }
}
