// QueryEventTests.swift
// CH05 5.4 (5.3 on 2.9.1), "(events vary)": "Its default trigger event is K13. A standard or
// site-defined response may use this trigger event or may specify a unique trigger event value",
// and a site-defined value begins with Z. Printed from v2.4; v2.3 and v2.3.1 print neither the
// sentence nor these structures. RTB_K13 and RDY_K15 take any such event, a locally defined message
// is still never a mismatch (P8b-10), and the general messages keep what they do today.

import Testing
@testable import HL7v2Kit

@Suite("Query events that vary")
struct QueryEventTests {
    /// Every wire version; `2.7` and `2.8` read the grammars of v2.7.1 and v2.8.2.
    static let every = ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.7", "2.7.1", "2.8", "2.8.2", "2.9", "2.9.1"]
    /// The wire versions whose CH05 prints the sentence.
    static let printing = ["2.4", "2.5.1", "2.6", "2.7", "2.7.1", "2.8", "2.8.2", "2.9", "2.9.1"]

    private static func issues(_ msh9: String, _ version: String, _ body: [String] = []) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|\(version)"] + body).joined(separator: "\r")
        return Validator(options: options).validate(try Parser().parse(wire)).issues.filter(\.code.isMessageStructure)
    }

    private static func codes(_ msh9: String, _ version: String, _ body: [String] = []) throws -> [IssueCode] {
        try issues(msh9, version, body).map(\.code)
    }

    private static func missing(_ structure: String, _ segment: String) -> IssueCode {
        .messageStructureSegmentMissing(structure: structure, segmentID: segment, group: nil)
    }

    private static let rtb = ["MSA|AA|1", "QAK|1|OK", "QPD|Q1"]
    private static let rdy = ["MSA|AA|1", "QAK|1|OK", "QPD|Q1", "DSP|1"]

    // MARK: Pins: the general messages do not move

    // CH02 prints the general acknowledgment for every trigger, and v2.9 and 2.9.1 CH02 print bare
    // ACK^Z01 (Acknowledgment Choreography, 2.12.2 p 52 and 2.11.2 p 53).
    @Test("Bare ACK^Z01 is matched against ACK's body on every version", arguments: every)
    func bareACK(version: String) throws {
        #expect(try Self.codes("ACK^Z01", version, ["MSA|AA|1"]) == [])
        #expect(try Self.codes("ACK^Z01", version, []) == [Self.missing("ACK", "MSA")])
    }

    @Test("ACK^Z01^ACK is matched on every version", arguments: every)
    func declaredACK(version: String) throws {
        #expect(try Self.codes("ACK^Z01^ACK", version, ["MSA|AA|1"]) == [])
        #expect(try Self.codes("ACK^Z84^ACK", version, []) == [Self.missing("ACK", "MSA")])
    }

    @Test("ACK^Z01^ACK_Z01 stays a mismatch; v2.3 reads no MSH-9.3", arguments: every)
    func zStructureOnACK(version: String) throws {
        let found = try Self.codes("ACK^Z01^ACK_Z01", version, ["MSA|AA|1"])
        #expect(found == (version == "2.3" ? [] : [.messageStructureMismatch(declared: "ACK_Z01", trigger: "ACK^Z01")]))
    }

    @Test("A non-Z event under ACK is matched on every version", arguments: every)
    func nonZACK(version: String) throws {
        #expect(try Self.codes("ACK^A01", version, ["MSA|AA|1"]) == [])
        #expect(try Self.codes("ACK^A01^ACK", version, []) == [Self.missing("ACK", "MSA")])
    }

    // v2.3 and v2.3.1 fold MCF under its own code. v2.4 CH02 2.14.2 p 2-97 prints MCF^varies^ACK, so ACK
    // owns MCF^*: an owner whose ID is a general message, though not this code.
    @Test("Bare MCF^Z01 is matched to v2.4 and not modelled after", arguments: every)
    func bareMCF(version: String) throws {
        let owner = ["2.3": "MCF", "2.3.1": "MCF", "2.4": "ACK"][version]
        if let owner {
            #expect(try Self.codes("MCF^Z01", version, ["MSA|AA|1"]) == [])
            #expect(try Self.codes("MCF^Z01", version, []) == [Self.missing(owner, "MSA")])
        } else {
            #expect(try Self.codes("MCF^Z01", version, ["MSA|AA|1"]) == [.messageStructureNotModelled(structure: "MCF^Z01")])
        }
    }

    @Test("v2.3: a Z event under each code-alone owner is matched, with any MSH-9.3",
          arguments: ["ACK", "MCF", "EDR", "TBR", "ERP"])
    func v23Owners(code: String) throws {
        for msh9 in ["\(code)^Z01", "\(code)^Z01^\(code)", "\(code)^Z01^\(code)_Z01"] {
            #expect(try Self.codes(msh9, "2.3", []).first == Self.missing(code, "MSA"), "\(msh9)")
        }
    }

    @Test("Every CODE^* owner is a general message whose ID names no event, or RTB_K13 or RDY_K15", arguments: Version.allCases)
    func owners(version: Version) {
        let owners = MessageStructureTable.structures(for: version).values.filter { $0.triggers.contains { $0.hasSuffix("^*") } }
        let general = owners.filter { !$0.id.contains("_") }.map(\.id)
        #expect(Set(general).isSubset(of: ["ACK", "MCF", "EDR", "ERP", "TBR"]), "\(version): \(general)")
        #expect(general.contains("ACK"), "\(version)")
        #expect(owners.filter { $0.id.contains("_") }.allSatisfy { ["RTB_K13", "RDY_K15"].contains($0.id) }, "\(version)")
        #expect(MessageStructureTable.notModelled(for: version).values.allSatisfy { !$0.triggers.contains { $0.hasSuffix("^*") } }, "\(version)")
    }

    // MARK: Pins: a locally defined message

    // CH05 5.8.3.1 (5.9.3.1 to v2.9) prints RTB^Z92^RTB_K13, and 5.8.5 RDY^Z98^RDY_K15: a site's query keeps the structure under its own Z event.
    @Test("A Z event declaring RTB_K13 or RDY_K15 is matched against the body", arguments: printing)
    func zEventDeclaringPrinted(version: String) throws {
        #expect(try Self.codes("RTB^Z99^RTB_K13", version, Self.rtb) == [])
        #expect(try Self.codes("RTB^Z99^RTB_K13", version, []) == [Self.missing("RTB_K13", "QAK"), Self.missing("RTB_K13", "QPD")])
        #expect(try Self.codes("RDY^Z99^RDY_K15", version, Self.rdy) == [])
        #expect(try Self.codes("RDY^Z99^RDY_K15", version, ["QAK|1|OK", "QPD|Q1"]) == [Self.missing("RDY_K15", "MSA")])
    }

    @Test("RTB^Z99^RTB_Z99 and bare RTB^Z99 are not modelled, never a mismatch", arguments: printing)
    func locallyDefined(version: String) throws {
        for (msh9, name) in [("RTB^Z99^RTB_Z99", "RTB_Z99"), ("RTB^Z99", "RTB^Z99"), ("RDY^Z99^RDY_Z99", "RDY_Z99"), ("RDY^Z99", "RDY^Z99"),
                             ("RTB^Z74^RTB_Z74", "RTB_Z74"), ("RDY^Z80^RDY_Z80", "RDY_Z80"), ("RTB^Z78^RTB_R13", "RTB_R13"), ("RTB^Z76^RTB_R13", "RTB_R13")] {
            let found = try Self.issues(msh9, version, Self.rtb)
            #expect(found.map(\.code) == [.messageStructureNotModelled(structure: name)], "\(msh9): \(found.map(\.message))")
        }
    }

    @Test("No event is no query event: bare RTB is not modelled and RTB^^RTB_K13 a mismatch", arguments: printing)
    func noEvent(version: String) throws {
        #expect(try Self.codes("RTB", version, Self.rtb) == [.messageStructureNotModelled(structure: "RTB")])
        #expect(try Self.codes("RTB^^RTB_K13", version, Self.rtb) == [.messageStructureMismatch(declared: "RTB_K13", trigger: "RTB")])
    }

    // MARK: Pins: what the sentence does not reach

    @Test("v2.3 and v2.3.1 print neither the sentence nor the structures")
    func beforeTheSentence() throws {
        // v2.3 reads no MSH-9.3, so the trigger names the note; on v2.3.1 the Z event declares an ID that is not loaded.
        #expect(try Self.codes("RTB^Z99^RTB_K13", "2.3", Self.rtb) == [.messageStructureNotModelled(structure: "RTB^Z99")])
        #expect(try Self.codes("RTB^Z99^RTB_K13", "2.3.1", Self.rtb) == [.messageStructureNotModelled(structure: "RTB_K13")])
        #expect(try Self.codes("RDY^Z99^RDY_K15", "2.3", Self.rdy) == [.messageStructureNotModelled(structure: "RDY^Z99")])
        #expect(try Self.codes("RDY^Z99^RDY_K15", "2.3.1", Self.rdy) == [.messageStructureNotModelled(structure: "RDY_K15")])
        #expect(try Self.codes("RTB^K42^RTB_K13", "2.3", Self.rtb) == [.messageStructureNotModelled(structure: "RTB^K42")])
        #expect(try Self.codes("RTB^K42^RTB_K13", "2.3.1", Self.rtb) == [.messageStructureMismatch(declared: "RTB_K13", trigger: "RTB^K42")])
        #expect(try Self.codes("RDY^R41^RDY_K15", "2.3.1", Self.rdy) == [.messageStructureMismatch(declared: "RDY_K15", trigger: "RDY^R41")])
    }

    // CH05's route for a site-defined response is the default event or a Z event, and no print has this form. The owner
    // yields only a Z event, so a Z structure ID on any other event is a mismatch, as on the two lines that were one already.
    @Test("A Z structure ID on an event that is not a Z event is a mismatch",
          arguments: printing)
    func zStructureOnOtherEvent(version: String) throws {
        for (msh9, id, trigger) in [("RTB^K42^RTB_Z42", "RTB_Z42", "RTB^K42"), ("RTB^K99^RTB_Z99", "RTB_Z99", "RTB^K99"),
                                    ("RDY^R41^RDY_Z41", "RDY_Z41", "RDY^R41"), ("RTB^z99^RTB_Z99", "RTB_Z99", "RTB^z99"),
                                    ("RTB^K13^RTB_Z13", "RTB_Z13", "RTB^K13"), ("ADT^A01^ADT_Z01", "ADT_Z01", "ADT^A01")] {
            #expect(try Self.codes(msh9, version) == [.messageStructureMismatch(declared: id, trigger: trigger)], "\(msh9)")
        }
    }

    // No caption, no Table 0354 row and no Appendix A row: each ID appears only on an example's MSH line.
    // v2.4 CH05 pp 5-18, 5-59, CH04 pp 4-64, 4-65; v2.5.1 CH05 pp 5-15, 5-57, 5-58, CH04 p 4-94; v2.6 CH05 pp 14, 50.
    @Test("An ID only an example's MSH line prints stays a mismatch",
          arguments: [("RTB^R40^RTB_R40", "RTB_R40", "2.4"), ("RDY^R41^RDY_R15", "RDY_R15", "2.4"), ("RTB^X89^RTB_X89", "RTB_X89", "2.4"),
                      ("RTB^R40^RTB_R40", "RTB_R40", "2.5.1"), ("RDY^R41^RDY_R15", "RDY_R15", "2.5.1"), ("RDY^R15^RDY_R15", "RDY_R15", "2.5.1"), ("RTB^X89^RTB_X89", "RTB_X89", "2.5.1"),
                      ("RTB^R40^RTB_R40", "RTB_R40", "2.6"), ("RDY^R41^RDY_R15", "RDY_R15", "2.6"), ("RDY^R15^RDY_R15", "RDY_R15", "2.6")])
    func exampleOnlyIDs(c: (msh9: String, id: String, version: String)) throws {
        let trigger = c.msh9.split(separator: "^").prefix(2).joined(separator: "^")
        #expect(try Self.codes(c.msh9, c.version, Self.rtb) == [.messageStructureMismatch(declared: c.id, trigger: trigger)])
    }

    // 5.4.5 (5.3.5 on 2.9.1) prints Event Q17 and no such sentence; QSB_Q16 prints Event Q16 alone, and 5.7.3.1 (5.6.3.1 on 2.9.1) calls
    // the same subscription Z83; RSP_K61 is printed nowhere as a structure.
    @Test("QVR_Q17 keeps its one trigger, and the neighbours stay mismatches", arguments: printing)
    func neighbours(version: String) throws {
        #expect(try Self.codes("QVR^Q17^QVR_Q17", version) == [.messageStructureNotModelled(structure: "QVR_Q17")])
        #expect(try Self.codes("QVR^Q61^QVR_Q17", version) == [.messageStructureMismatch(declared: "QVR_Q17", trigger: "QVR^Q61")])
        #expect(try Self.codes("QSB^Q99^QSB_Q16", version) == [.messageStructureMismatch(declared: "QSB_Q16", trigger: "QSB^Q99")])
        #expect(try Self.codes("RSP^K61^RSP_K61", version) == [.messageStructureMismatch(declared: "RSP_K61", trigger: "RSP^K61")])
    }

    // MARK: A query event the print allows

    // CH05 prints RTB^K42^RTB_K13 on every version from v2.4 (2.9.1 pp 58, 90), and RDY^R41^RDY_K15 from v2.7.1 (2.9.1 p 61).
    // Its deferred response (2.9.1 p 58) prints no MSA, so RTB_K13 reads MSA as optional (DeferredQueryResponseTests).
    @Test("RTB^K42^RTB_K13 and RDY^R41^RDY_K15 draw no mismatch; the body is matched", arguments: printing)
    func namedEvent(version: String) throws {
        #expect(try Self.codes("RTB^K42^RTB_K13", version, Self.rtb) == [])
        #expect(try Self.codes("RTB^K42^RTB_K13", version, ["MSA|AA|1", "QPD|Q1"]) == [Self.missing("RTB_K13", "QAK")])
        #expect(try Self.codes("RDY^R41^RDY_K15", version, Self.rdy) == [])
        #expect(try Self.codes("RDY^R41^RDY_K15", version, ["QAK|1|OK", "QPD|Q1"]) == [Self.missing("RDY_K15", "MSA")])
    }

    @Test("The default events still resolve, with and without MSH-9.3", arguments: printing)
    func defaultEvents(version: String) throws {
        for msh9 in ["RTB^K13^RTB_K13", "RTB^K13"] { #expect(try Self.codes(msh9, version, Self.rtb) == [], "\(msh9)") }
        for msh9 in ["RDY^K15^RDY_K15", "RDY^K15"] { #expect(try Self.codes(msh9, version, Self.rdy) == [], "\(msh9)") }
    }

    @Test("Bare RTB^K42 and RDY^R41 resolve to the one structure under the code", arguments: printing)
    func bareNamedEvent(version: String) throws {
        #expect(try Self.codes("RTB^K42", version, Self.rtb) == [])
        #expect(try Self.codes("RTB^K42", version, ["MSA|AA|1", "QPD|Q1"]) == [Self.missing("RTB_K13", "QAK")])
        #expect(try Self.codes("RDY^R41", version, Self.rdy) == [])
        #expect(try Self.codes("RDY^R41", version, ["QAK|1|OK", "QPD|Q1"]) == [Self.missing("RDY_K15", "MSA")])
    }

    @Test("accepts and the table read the one rule", arguments: Version.allCases)
    func publicReaders(version: Version) throws {
        guard let rtb = MessageStructureTable.structure("RTB_K13", version: version),
              let rdy = MessageStructureTable.structure("RDY_K15", version: version) else {
            #expect(version.grammarVersion == .v2_3 || version.grammarVersion == .v2_3_1, "\(version)")
            return
        }
        #expect(rtb.triggers == ["RTB^*"] && rdy.triggers == ["RDY^*"], "\(version)")
        for event in ["K13", "K42", "R41"] {
            #expect(rtb.accepts(messageCode: "RTB", triggerEvent: event), "\(version) \(event)")
        }
        #expect(!rtb.accepts(messageCode: "RTB", triggerEvent: "Z99"), "\(version)")
        #expect(!rtb.accepts(messageCode: "RTB", triggerEvent: ""), "\(version)")
        #expect(!rtb.accepts(messageCode: "RDY", triggerEvent: "K15"), "\(version)")
        #expect(MessageStructureTable.structures(messageCode: "RDY", triggerEvent: "R41", version: version).map(\.id) == ["RDY_K15"])
        #expect(MessageStructureTable.structures(messageCode: "RDY", triggerEvent: "Z99", version: version).isEmpty)
        let ack = try #require(MessageStructureTable.structure("ACK", version: version))
        #expect(ack.accepts(messageCode: "ACK", triggerEvent: "Z01") && ack.accepts(messageCode: "ACK", triggerEvent: ""))
    }

    // No shipped entry holds CODE^*, so only a synthetic gap reaches the registered side of the predicate.
    @Test("A registered CODE^* reads the same rule: an ID naming an event takes no Z event and no empty one")
    func registeredWildcard() throws {
        let gaps = ["QQQ_K01": NotModelledStructure(triggers: ["QQQ^*"], reason: "an event-named template (synthetic)"),
                    "YYY": NotModelledStructure(triggers: ["YYY^*"], reason: "a general message (synthetic)")]
        func resolved(_ msh9: String) throws -> [ValidationIssue] {
            let message = try Parser().parse("MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|2.5.1")
            return Validator().resolveStructure(message, severity: .error, structures: [:], complete: [.v2_5_1], gaps: gaps).issues
        }
        let taken = try resolved("QQQ^K42")
        #expect(taken.map(\.code) == [.messageStructureNotModelled(structure: "QQQ^K42")])
        #expect(taken.first?.message.contains("under QQQ_K01") == true, "\(taken.map(\.message))")
        let local = try resolved("QQQ^Z99")
        #expect(local.map(\.code) == [.messageStructureNotModelled(structure: "QQQ^Z99")])
        #expect(local.first?.message.contains("QQQ_K01") == false, "\(local.map(\.message))")
        #expect(try resolved("QQQ^^QQQ_K01").map(\.code) == [.messageStructureMismatch(declared: "QQQ_K01", trigger: "QQQ")])
        #expect(try resolved("QQQ^K42^QQQ_K01").map(\.code) == [.messageStructureNotModelled(structure: "QQQ_K01")])
        let general = try resolved("YYY^Z99")
        #expect(general.first?.message.contains("under YYY") == true, "\(general.map(\.message))")
    }

    // MARK: The query templates, under the same sentence

    @Test("Each template's registration lists no events from v2.4, and QVR_Q17 keeps its one")
    func registeredTriggers() throws {
        for version in [Version.v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_8_2, .v2_9, .v2_9_1] {
            for id in ["QBP_Q11", "QBP_Q13", "QBP_Q15", "RSP_K11"] {
                #expect(try #require(MessageStructureTable.registration(id, version: version)).triggers.isEmpty, "\(version) \(id)")
            }
            #expect(try #require(MessageStructureTable.registration("QVR_Q17", version: version)).triggers == ["QVR^Q17"], "\(version)")
        }
    }

    // v2.4 CH05 prints QBP^Q40^QBP_Q13 (p 5-17), QBP^Q42^QBP_Q13 (p 5-56), QBP^Q41^QBP_Q15 (p 5-59), QBP^Q61^QBP_Q11 (p 5-60),
    // and CH03 QBP^Q24^QBP_Q11 and RSP^K24^RSP_K11 (p 3-58). Each template prints the sentence on every version from v2.4.
    @Test("A query template declared with a varying event is not modelled, never a mismatch", arguments: printing)
    func templates(version: String) throws {
        for (msh9, id) in [("QBP^Q61^QBP_Q11", "QBP_Q11"), ("QBP^Q24^QBP_Q11", "QBP_Q11"), ("QBP^Q40^QBP_Q13", "QBP_Q13"), ("QBP^Q42^QBP_Q13", "QBP_Q13"),
                           ("QBP^Q41^QBP_Q15", "QBP_Q15"), ("RSP^K61^RSP_K11", "RSP_K11"), ("RSP^K24^RSP_K11", "RSP_K11"),
                           ("QBP^Q11^QBP_Q11", "QBP_Q11"), ("QBP^Q13^QBP_Q13", "QBP_Q13"), ("QBP^Q15^QBP_Q15", "QBP_Q15"), ("RSP^K11^RSP_K11", "RSP_K11")] {
            let found = try Self.issues(msh9, version)
            #expect(found.map(\.code) == [.messageStructureNotModelled(structure: id)], "\(msh9): \(found.map(\.message))")
            #expect(found.first?.message.contains("template") == true, "\(msh9): \(found.map(\.message))")
        }
        for msh9 in ["QBP^Q11", "QBP^Q15", "RSP^K11"] {
            #expect(try Self.codes(msh9, version) == [.messageStructureNotModelled(structure: msh9)], "\(msh9)")
        }
    }
}
