// StructureAliasTests.swift
// S4-2: a structure ID the print gives a trigger of its own whose syntax is another printed
// structure's (ADR-019 S4 amendment). v2.4 CH06 6.4.4 (p 6-13) captions QRY^P04^QRY_P04 and
// refers it to "the QRY/DSR transaction, as defined in Chapter 5"; v2.5.1 Table 0354 (p 2-104)
// lists QRY_P04 and CH06 6.4.4 (p 6-8) refers it likewise. QRY_P04 is the alias of QRY_Q01: it
// keeps its own ID (no mismatch, no fold) and is matched against QRY_Q01's elements.

import Testing
@testable import HL7v2Kit

@Suite("Structure alias probes")
struct StructureAliasTests {

    typealias Probe = StructureSlotProbeTests.Probe

    static let probes: [Probe] = [
        Probe(version: "2.4", msh9: "QRY^P04^QRY_P04", structure: "QRY_P04",
              body: ["QRD|20240101|R|I|Q1|||1^RD|1|BIL", "QRF|BIL"], findings: [], note: "declared, clean"),
        Probe(version: "2.4", msh9: "QRY^P04", structure: "QRY_P04",
              body: ["QRD|20240101|R|I|Q1|||1^RD|1|BIL"], findings: [], note: "bare trigger, clean"),
        Probe(version: "2.4", msh9: "QRY^P04^QRY_P04", structure: "QRY_P04",
              body: ["QRF|BIL"], findings: ["missing QRD at QRF[1]"], note: "no QRD"),
        Probe(version: "2.5.1", msh9: "QRY^P04^QRY_P04", structure: "QRY_P04",
              body: ["SFT|1", "QRD|20240101|R|I|Q1|||1^RD|1|BIL"], findings: [], note: "declared, clean"),
        Probe(version: "2.5.1", msh9: "QRY^P04", structure: "QRY_P04",
              body: ["QRD|20240101|R|I|Q1|||1^RD|1|BIL", "QRF|BIL", "QRF|BIL"],
              findings: ["unexpected QRF at QRF[2]"], note: "bare trigger, a second QRF"),
    ]

    @Test("QRY_P04 is matched as its own ID against the QRY_Q01 syntax", arguments: probes)
    func probe(_ p: Probe) throws {
        let version = try #require(Version(rawValue: p.version))
        #expect(MessageStructureTable.structure(p.structure, version: version) != nil,
                "\(p.structure) is not modelled on v\(p.version)")
        let issues = try StructureSlotProbeTests.structureIssues(p.msh9, p.version, p.body)
        #expect(issues.map(StructureSlotProbeTests.describe) == p.findings, "\(p.testDescription): \(issues.map(\.message))")
        #expect(issues.allSatisfy { $0.severity == .error && "\($0.code)".contains(p.structure) },
                "\(p.testDescription): \(issues.map(\.message))")
    }

    @Test("QRY^P04 resolves to QRY_P04, which is no longer registered", arguments: ["2.4", "2.5.1"])
    func resolves(_ raw: String) throws {
        let version = try #require(Version(rawValue: raw))
        let wire = "MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||QRY^P04|MSG00001|P|\(raw)\rQRD|20240101|R|I|Q1"
        let resolved = Validator().resolveStructure(try Parser().parse(wire), severity: .error)
        #expect(resolved.structure?.id == "QRY_P04", "\(resolved.issues.map(\.message))")
        #expect(MessageStructureTable.registration("QRY_P04", version: version) == nil)
        let alias = try #require(MessageStructureTable.structure("QRY_P04", version: version))
        let target = try #require(MessageStructureTable.structure("QRY_Q01", version: version))
        #expect(alias.aliasOf == "QRY_Q01" && alias.elements == target.elements)
        #expect(alias.triggers == ["QRY^P04"] && !target.triggers.contains("QRY^P04"))
    }
}
