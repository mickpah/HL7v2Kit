// PatientCareParticipationTests.swift
// v2.9 and 2.9.1 CH12 (12.3.1 to 12.3.4) print every participation group of PGL_PC6, PPR_PC1,
// PPP_PCB and PPG_PCG as ROL, status B ("For backwards compatibility only as of V2.9"), then PRT,
// both without brackets. CH02 reads B as "left in for backward compatibility with previous versions
// of HL7" (v2.9 2.5.3.6 p 10), and CH15 15.4.7 (p 35) refers the reader of ROL to PRT, so a message
// may leave ROL out; PRT, printed with no status, stays required. v2.7.1 and v2.8.2 print ROL alone
// in these groups (the *_ROLE groups), with no status.

import Testing
@testable import HL7v2Kit

@Suite("CH12 participation groups")
struct PatientCareParticipationTests {

    struct Site: Sendable, CustomTestStringConvertible {
        let version: String
        let msh9: String
        let structure: String
        let group: String
        /// The segments after MSH that open the participation group's parent.
        let path: [String]
        var testDescription: String { "v\(version) \(structure) \(group)" }
    }

    // Each participation group of the four prints, with the shortest body that reaches it.
    static let sites: [Site] = ["2.9", "2.9.1"].flatMap { v -> [Site] in
        let head = ["PID|1", "PRD|1"]
        return [
            Site(version: v, msh9: "PGL^PC6^PGL_PC6", structure: "PGL_PC6", group: "GOAL_PARTICIPATION",
                 path: head + ["GOL|1"]),
            Site(version: v, msh9: "PGL^PC6^PGL_PC6", structure: "PGL_PC6", group: "PROBLEM_PARTICIPATION",
                 path: head + ["GOL|1", "PRB|1"]),
            Site(version: v, msh9: "PPR^PC1^PPR_PC1", structure: "PPR_PC1", group: "PROBLEM_PARTICIPATION",
                 path: head + ["PRB|1"]),
            Site(version: v, msh9: "PPR^PC1^PPR_PC1", structure: "PPR_PC1", group: "GOAL_PARTICIPATION",
                 path: head + ["PRB|1", "GOL|1"]),
            Site(version: v, msh9: "PPP^PCB^PPP_PCB", structure: "PPP_PCB", group: "PATHWAY_PARTICIPATION",
                 path: head + ["PTH|1"]),
            Site(version: v, msh9: "PPP^PCB^PPP_PCB", structure: "PPP_PCB", group: "PROBLEM_PARTICIPATION",
                 path: head + ["PTH|1", "PRB|1"]),
            Site(version: v, msh9: "PPP^PCB^PPP_PCB", structure: "PPP_PCB", group: "GOAL_PARTICIPATION",
                 path: head + ["PTH|1", "PRB|1", "GOL|1"]),
            Site(version: v, msh9: "PPG^PCG^PPG_PCG", structure: "PPG_PCG", group: "PATHWAY_PARTICIPATION",
                 path: head + ["PTH|1"]),
            Site(version: v, msh9: "PPG^PCG^PPG_PCG", structure: "PPG_PCG", group: "GOAL_PARTICIPATION",
                 path: head + ["PTH|1", "GOL|1"]),
            Site(version: v, msh9: "PPG^PCG^PPG_PCG", structure: "PPG_PCG", group: "PROBLEM_PARTICIPATION",
                 path: head + ["PTH|1", "GOL|1", "PRB|1"]),
        ]
    }

    static let rol = "ROL|1|AD|PP^Primary Care Provider^HL70443"
    static let prt = "PRT|1|AD||PP^Primary Care Provider^HL70912"

    /// The structure findings for the site's path, then `group`.
    static func findings(_ site: Site, _ group: [String]) throws -> [IssueCode] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(site.msh9)|MSG00001|P|\(site.version)"]
                    + site.path + group).joined(separator: "\r")
        return Validator(options: options).validate(try Parser().parse(wire)).issues.map(\.code).filter(\.isMessageStructure)
    }

    @Test("PRT without ROL draws no structure finding", arguments: sites)
    func participationAlone(_ site: Site) throws {
        let found = try Self.findings(site, [Self.prt])
        #expect(found == [])
    }

    @Test("ROL and PRT together draw no structure finding", arguments: sites)
    func both(_ site: Site) throws {
        let found = try Self.findings(site, [Self.rol, Self.prt])
        #expect(found == [])
    }

    @Test("ROL without PRT draws the missing PRT the print requires", arguments: sites)
    func roleAlone(_ site: Site) throws {
        let found = try Self.findings(site, [Self.rol])
        #expect(found == [
            .messageStructureSegmentMissing(structure: site.structure, segmentID: "PRT", group: site.group),
        ])
    }

    @Test("Neither ROL nor PRT leaves the optional group out, with no finding", arguments: sites)
    func neither(_ site: Site) throws {
        let found = try Self.findings(site, [])
        #expect(found == [])
    }

    @Test("A second participation may send PRT alone", arguments: sites)
    func repeated(_ site: Site) throws {
        let found = try Self.findings(site, [Self.rol, Self.prt, "VAR|1", Self.prt, "VAR|2"])
        #expect(found == [])
    }

    /// The groups named `name` anywhere in `elements`.
    static func groups(_ name: String, in elements: [StructureElement]) -> [[StructureElement]] {
        elements.flatMap { element -> [[StructureElement]] in
            if case .group(name, _, _, let inner) = element { return [inner] + groups(name, in: inner) }
            return groups(name, in: element.children)
        }
    }

    @Test("Every v2.9 and 2.9.1 participation group reads [ROL] PRT [{VAR}]")
    func structureData() throws {
        let expected: [StructureElement] = [
            .segment("ROL", min: 0, max: 1), .segment("PRT", min: 1, max: 1), .segment("VAR", min: 0, max: nil),
        ]
        for site in Self.sites {
            let version = try #require(Version(rawValue: site.version))
            let structure = try #require(MessageStructureTable.structure(site.structure, version: version))
            let found = Self.groups(site.group, in: structure.elements)
            #expect(!found.isEmpty, "\(site.testDescription)")
            #expect(found.allSatisfy { $0 == expected }, "\(site.testDescription): \(found)")
        }
    }

    @Test("v2.7.1 and v2.8.2 keep the role groups as printed: ROL alone, required")
    func earlierVersions() throws {
        // v2.8.2 CH12 12.3.1 (p 8) and v2.7.1 12.3.1 (p 7) print GOAL_ROLE as ROL [{VAR}], with no status.
        for version in [Version.v2_7_1, .v2_8_2] {
            for id in ["PGL_PC6", "PPR_PC1", "PPP_PCB", "PPG_PCG"] {
                let structure = try #require(MessageStructureTable.structure(id, version: version), "\(id)")
                let roles = ["PATHWAY_ROLE", "GOAL_ROLE", "PROBLEM_ROLE"].flatMap {
                    Self.groups($0, in: structure.elements)
                }
                #expect(!roles.isEmpty, "\(id) v\(version.rawValue)")
                #expect(roles.allSatisfy { $0.first == .segment("ROL", min: 1, max: 1) }, "\(id) v\(version.rawValue)")
            }
        }
    }
}
