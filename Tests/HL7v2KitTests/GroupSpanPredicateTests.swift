// GroupSpanPredicateTests.swift
// P8b-17 (ADR-019 "Interaction with the existing ORC-group scoping"): the
// matched structure's group spans scope the group-dependent predicates
// (ORC/OBR peers, segment presence, paired fields) on complete versions; the
// ORC walk, or the former message-code gate, is the fallback.

import Testing
@testable import HL7v2Kit

@Suite("Group spans scope the group-dependent predicates (P8b-17)")
struct GroupSpanPredicateTests {
    static let versions = ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.7.1", "2.8.2"]

    /// The order structures whose groups place ORC and OBR, including the
    /// ones that print OBR before ORC in one group.
    static let orderStructures = ["OUL_R21", "OUL_R22", "OUL_R23", "OUL_R24", "OPU_R25", "OPL_O37",
                                  "OML_O33", "OML_O21", "ORU_R01", "ORM_O01"]

    static func version(_ raw: String) -> Version { Version(rawValue: raw)! }

    /// MSH-9 for a structure: its first printed trigger plus the structure ID.
    static func msh9(_ structure: MessageStructure) -> String {
        "\(structure.triggers.first ?? structure.id)^\(structure.id)"
    }

    /// A message conforming to `elements`: every required element once, and
    /// every optional element that contains an ORC or OBR, a repeating one
    /// twice. Each OBR carries its own placer and filler numbers; each ORC is
    /// `ORC|SC` with none, so every order's numbers are only in its OBR.
    static func skeleton(_ elements: [StructureElement]) -> [String] {
        let want: Set<String> = ["ORC", "OBR"]
        var out: [String] = []
        for element in elements {
            let wanted = !element.segmentIDs.isDisjoint(with: want)
            guard element.min > 0 || wanted else { continue }
            let times = wanted && element.max != 1 ? 2 : Swift.max(1, element.min)
            for _ in 0..<times {
                switch element {
                case .segment(let id, _, _):
                    out.append(id)
                case .group(_, _, _, let children):
                    out += skeleton(children)
                case .choice(_, _, _, let alternatives):
                    let pick = alternatives.first { !$0.segmentIDs.isDisjoint(with: want) } ?? alternatives[0]
                    out += skeleton([pick])
                case .slot:
                    // An order detail segment (S3-1); no committed structure has a slot yet.
                    out.append("RXO")
                }
            }
        }
        return out
    }

    static func wire(_ msh9: String, _ version: String, _ ids: [String],
                     orc: (Int) -> String = { _ in "ORC|SC" },
                     obr: (Int) -> String = { "OBR|\($0)|PON\($0)|FON\($0)" }) -> String {
        var orcs = 0, obrs = 0
        let body = ids.dropFirst().map { id -> String in
            switch id {
            case "ORC": orcs += 1; return orc(orcs)
            case "OBR": obrs += 1; return obr(obrs)
            default: return "\(id)|1"
            }
        }
        return TestWires.msh(msh9, version) + body.map { $0 + "\r" }.joined()
    }

    static func issues(_ wire: String, structure: IssueSeverity? = nil,
                       locale: HL7Locale = .international) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = structure
        return Validator(options: options, locale: locale).validate(try Parser(locale: locale).parse(wire)).issues
    }

    /// The fields whose conditions read the ORC/OBR group peer.
    static let groupDependent: Set<String> = ["ORC-2", "ORC-3", "ORC-8", "OBR-2", "OBR-3", "OBR-29"]

    /// The group-dependent findings: a group-dependent conditional ORC or OBR
    /// field reported missing, or an ORC/OBR paired-field mismatch.
    static func groupFindings(_ issues: [ValidationIssue]) -> [String] {
        issues.compactMap { issue in
            switch issue.code {
            case .conditionalFieldMissing
                where groupDependent.contains("\(issue.location.segmentID)-\(issue.location.fieldIndex ?? 0)"):
                return "\(issue.location.pathDescription) missing"
            case .pairedFieldMismatch(let item):
                return "\(issue.location.pathDescription) mismatch \(item)"
            default:
                return nil
            }
        }.sorted()
    }

    static func structureFindings(_ issues: [ValidationIssue]) -> [String] {
        issues.compactMap { issue in
            switch issue.code {
            case .messageStructureSegmentMissing, .messageStructureSegmentUnexpected,
                 .messageStructureMismatch, .messageStructureNotModelled:
                return issue.message
            default:
                return nil
            }
        }
    }

    static var printed: [(String, String)] {
        versions.flatMap { v in
            orderStructures.compactMap { id in
                MessageStructureTable.structure(id, version: version(v)) == nil ? nil : (v, id)
            }
        }
    }

    // MARK: - R5 invariant: conformant messages draw nothing the print does not support

    @Test("A message conforming to its printed order structure draws no group-dependent finding",
          arguments: printed.map { "\($0.0) \($0.1)" })
    func conformantIsSilent(_ key: String) throws {
        let parts = key.split(separator: " ").map(String.init)
        let structure = try #require(MessageStructureTable.structure(parts[1], version: Self.version(parts[0])))
        let wire = Self.wire(Self.msh9(structure), parts[0], Self.skeleton(structure.elements))
        let all = try Self.issues(wire, structure: .warning)
        #expect(Self.structureFindings(all).isEmpty, "v\(key) does not conform: \(Self.structureFindings(all))")
        #expect(Self.groupFindings(all).isEmpty, "v\(key): \(Self.groupFindings(all))")
    }

    /// The other direction (fix round 1): each order's numbers only in its
    /// ORC, so every OBR must find its own group's ORC.
    @Test("A conforming OBR-first or nested order structure with the numbers only in each ORC draws nothing",
          arguments: printed.filter { ["OUL_R21", "OUL_R22", "OUL_R23", "OUL_R24", "OPU_R25", "OPL_O37"].contains($0.1) }
            .map { "\($0.0) \($0.1)" })
    func numbersInORCIsSilent(_ key: String) throws {
        let parts = key.split(separator: " ").map(String.init)
        let structure = try #require(MessageStructureTable.structure(parts[1], version: Self.version(parts[0])))
        let wire = Self.wire(Self.msh9(structure), parts[0], Self.skeleton(structure.elements),
                             orc: { "ORC|SC|PON\($0)|FON\($0)" }, obr: { "OBR|\($0)" })
        let all = try Self.issues(wire, structure: .warning)
        #expect(Self.structureFindings(all).isEmpty, "v\(key) does not conform: \(Self.structureFindings(all))")
        #expect(Self.groupFindings(all).isEmpty, "v\(key): \(Self.groupFindings(all))")
    }

    @Test("An ORC/OBR pair with different placer numbers in one OUL_R24 ORDER group is reported",
          arguments: ["2.5.1", "2.6", "2.7.1", "2.8.2"])
    func oulR24PairMismatch(version: String) throws {
        let structure = try #require(MessageStructureTable.structure("OUL_R24", version: Self.version(version)))
        let wire = Self.wire(Self.msh9(structure), version, Self.skeleton(structure.elements),
                             orc: { $0 == 2 ? "ORC|SC|XXX" : "ORC|SC" })
        #expect(Self.structureFindings(try Self.issues(wire, structure: .warning)).isEmpty)
        #expect(Self.groupFindings(try Self.issues(wire)) == ["OBR[2]-2 mismatch 00216"], "v\(version)")
    }

    /// A child order (ORC-1 = CH) whose parent is in neither ORC-8 nor OBR-29:
    /// v2.3 to v2.6 print both fields conditional on it (v2.5.1 CH04 4.5.1.8,
    /// 4.5.3.29). The first order is the child; the second is complete.
    @Test("A child order with ORC-1 = CH and no parent is reported in its own group",
          arguments: ["2.3 ORU_R01", "2.3.1 ORU_R01", "2.4 ORU_R01", "2.4 OUL_R21", "2.5.1 ORU_R01",
                      "2.5.1 OUL_R21", "2.5.1 OUL_R24", "2.6 ORU_R01", "2.6 OUL_R21", "2.6 OUL_R24"])
    func childOrderWithoutParent(_ key: String) throws {
        let parts = key.split(separator: " ").map(String.init)
        let structure = try #require(MessageStructureTable.structure(parts[1], version: Self.version(parts[0])))
        let wire = Self.wire(Self.msh9(structure), parts[0], Self.skeleton(structure.elements),
                             orc: { $0 == 1 ? "ORC|CH" : "ORC|SC" })
        #expect(Self.structureFindings(try Self.issues(wire, structure: .warning)).isEmpty)
        #expect(Self.groupFindings(try Self.issues(wire)) == ["OBR[1]-29 missing", "ORC[1]-8 missing"], "v\(key)")
    }

    /// v2.4 to v2.6 OUL_R21 prints `[ORC] OBR` (ORC before OBR in one
    /// ORDER_OBSERVATION): an order with no number in either segment breaks
    /// ORC-2/ORC-3 and OBR-2/OBR-3, which the former OUL gate never reported.
    @Test("OUL_R21: an order with no placer or filler number anywhere is reported",
          arguments: ["2.4", "2.5.1", "2.6"])
    func oulR21WithoutNumbers(version: String) throws {
        let structure = try #require(MessageStructureTable.structure("OUL_R21", version: Self.version(version)))
        let wire = Self.wire(Self.msh9(structure), version, Self.skeleton(structure.elements),
                             obr: { $0 == 1 ? "OBR|1" : "OBR|\($0)|PON\($0)|FON\($0)" })
        #expect(Self.structureFindings(try Self.issues(wire, structure: .warning)).isEmpty)
        #expect(Self.groupFindings(try Self.issues(wire))
                == ["OBR[1]-2 missing", "OBR[1]-3 missing", "ORC[1]-2 missing", "ORC[1]-3 missing"], "v\(version)")
    }

    // MARK: - Fallbacks: no spans

    /// ORU_R01: the first order has an ORC, the second none. The ORC walk
    /// pairs the second OBR with the first order's ORC, so the second OBR's
    /// `ORC absent` leg is missed; the ORDER_OBSERVATION group has no ORC.
    static func oruSecondOrderWithoutORC(_ version: String, extra: [String] = []) -> String {
        TestWires.msh("ORU^R01^ORU_R01", version) + (["PID|1", "ORC|RE|PON1|FON1", "OBR|1|PON1|FON1", "OBR|2"] + extra).map { $0 + "\r" }.joined()
    }

    @Test("ORU_R01 with no ORC in the second order: OBR-2 and OBR-3 are required there (spans)",
          arguments: ["2.5.1", "2.6", "2.7.1"])
    func oruSecondOrder(version: String) throws {
        let wire = Self.oruSecondOrderWithoutORC(version)
        #expect(Self.structureFindings(try Self.issues(wire, structure: .warning)).isEmpty)
        #expect(Self.groupFindings(try Self.issues(wire)) == ["OBR[2]-2 missing", "OBR[2]-3 missing"], "v\(version)")
    }

    @Test("The same ORU_R01 with a structure deviation uses the ORC walk: identical to BASE",
          arguments: ["2.5.1", "2.6", "2.7.1"])
    func oruSecondOrderDeviating(version: String) throws {
        let wire = Self.oruSecondOrderWithoutORC(version, extra: ["EVN|A01"])
        #expect(!Self.structureFindings(try Self.issues(wire, structure: .warning)).isEmpty)
        #expect(Self.groupFindings(try Self.issues(wire)).isEmpty, "v\(version)")
    }

    /// OUL_R24 prints `ORDER { OBR [ORC] ... }`; the ORC walk never sees the
    /// OBR before the ORC. With a deviation there are no spans, and the
    /// formerly gated message code keeps the gate's outcome.
    @Test("A deviating OUL_R24 keeps the former gate: the ORC is not read as an ORC with no OBR",
          arguments: ["2.5.1", "2.6", "2.7.1", "2.8.2"])
    func oulR24Deviating(version: String) throws {
        let structure = try #require(MessageStructureTable.structure("OUL_R24", version: Self.version(version)))
        let wire = Self.wire(Self.msh9(structure), version, Self.skeleton(structure.elements) + ["EVN"])
        #expect(!Self.structureFindings(try Self.issues(wire, structure: .warning)).isEmpty)
        #expect(Self.groupFindings(try Self.issues(wire)).isEmpty, "v\(version)")
    }

    /// v2.3.1 registers ORM_O01 as not modelled (an unexpandable placeholder):
    /// no spans, so the ORC walk, as at BASE.
    @Test("v2.3.1 ORM_O01 (registered as not modelled) uses the ORC walk")
    func notModelledUsesWalk() throws {
        let wire = TestWires.wire("ORM^O01", "2.3.1", "PID|1", "ORC|NW", "OBR|1", "ORC|CH|PON2|FON2")
        #expect(Self.groupFindings(try Self.issues(wire))
                == ["OBR[1]-2 missing", "OBR[1]-3 missing", "ORC[1]-2 missing", "ORC[1]-3 missing", "ORC[2]-8 missing"])
    }

    /// ADRM-2021 p 281 places OBX in the order status response, which the base
    /// v2.4 OSR_Q06 does not: the base match deviates, so the ORC walk is used
    /// whatever the AU profile accepts (ADR-019, P8b-17).
    @Test("An ADRM-conformant AU OSR_Q06 that deviates from the base uses the ORC walk")
    func auDeviationUsesWalk() throws {
        let wire = TestWires.wire("OSR^Q06^OSR_Q06", "2.4", "MSA|AA|1", "QRD|20240101|R|I|Q1|||1^RD|ALL|OS|",
                                  "PID|1", "ORC|SC", "OBR|1", "OBX|1", "CTI|1")
        let au = try Self.issues(wire, structure: .warning, locale: .auLocalisation)
        #expect(Self.structureFindings(au).filter { $0.contains("OSR_Q06") && !$0.contains("not checked") }.isEmpty)
        #expect(Self.groupFindings(try Self.issues(wire, locale: .auLocalisation))
                == ["OBR[1]-2 missing", "OBR[1]-3 missing", "ORC[1]-2 missing", "ORC[1]-3 missing"])
    }
}
