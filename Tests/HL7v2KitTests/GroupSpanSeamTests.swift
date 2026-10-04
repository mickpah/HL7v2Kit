// GroupSpanSeamTests.swift
// P8b-17 (ADR-019): spans from the exact matcher, group identity by position,
// and when the Validator uses spans, the ORC walk or the former gate.

import Testing
@testable import HL7v2Kit

@Suite("Group spans: exact-matcher spans and the seam (P8b-17)")
struct GroupSpanSeamTests {
    static func structure(_ elements: [StructureElement]) -> MessageStructure {
        MessageStructure(id: "T", version: "2.5.1", triggers: [], citation: "test", elements: elements)
    }

    static func describe(_ scoping: GroupScoping) -> String {
        switch scoping {
        case .walk: return "walk"
        case .spans: return "spans"
        case .gated(let fields): return "gated \(fields.sorted().joined(separator: ","))"
        }
    }

    static func scoping(_ wire: String, locale: HL7Locale = .international,
                        complete: Set<Version>? = nil) throws -> String {
        let message = try Parser(locale: locale).parse(wire)
        return describe(Validator(locale: locale).groupScoping(for: message, complete: complete))
    }

    static func conformant(_ id: String, _ version: String) throws -> (MessageStructure, String) {
        let structure = try #require(MessageStructureTable.structure(id, version: GroupSpanPredicateTests.version(version)))
        let wire = GroupSpanPredicateTests.wire(GroupSpanPredicateTests.msh9(structure), version,
                                                GroupSpanPredicateTests.skeleton(structure.elements))
        return (structure, wire)
    }

    @Test("Exact-matched order structures with OBR before ORC give spans on a conformant message",
          arguments: ["2.5.1 OUL_R24", "2.6 OUL_R24", "2.7.1 OUL_R24", "2.8.2 OUL_R24", "2.8.2 OUL_R22",
                      "2.8.2 OUL_R23", "2.8.2 OPU_R25", "2.6 OPL_O37", "2.7.1 OPL_O37", "2.8.2 OPL_O37"])
    func exactSpans(_ key: String) throws {
        let parts = key.split(separator: " ").map(String.init)
        let (structure, wire) = try Self.conformant(parts[1], parts[0])
        #expect(structure.requiresExactMatch, "\(key) is one-pass")
        let ids = try Parser().parse(wire).segments.map(\.segmentID)
        let match = ExactStructureMatcher(structure: structure).match(ids)
        #expect(match.findings.isEmpty && !match.spansWithheld && !match.spans.isEmpty, "\(key)")
        // Every ORC's peer OBR is in the ORC's own innermost group with an OBR.
        let index = GroupSpanIndex(spans: match.spans, segmentCount: ids.count)
        for orc in ids.indices where ids[orc] == "ORC" {
            let range = index.range(around: orc, containing: "OBR")
            #expect(range != 0..<ids.count && range.contains { ids[$0] == "OBR" }, "\(key) ORC at \(orc): \(range)")
        }
        #expect(try Self.scoping(wire) == "spans", "\(key)")
    }

    /// OML_O33 prints `SPECIMEN { SPM ... ORDER { ORC ... [OBSERVATION_REQUEST
    /// { OBR ... }] } }` (v2.5.1 CH04 4.4.10): the order sits inside its
    /// specimen, after the SPM.
    @Test("OML_O33 with SPM before ORC: each ORC/OBR pair is scoped to its own specimen's order",
          arguments: ["2.5.1", "2.6", "2.7.1", "2.8.2"])
    func omlO33SpecimenFirst(version: String) throws {
        let structure = try #require(MessageStructureTable.structure("OML_O33", version: GroupSpanPredicateTests.version(version)))
        #expect(structure.requiresExactMatch)
        let body = ["PID|1", "SPM|1", "ORC|SC|PON1|FON1", "OBR|1|PON1|FON1", "SPM|2", "ORC|SC|PON2|FON2", "OBR|2|XXX|FON2"]
        let wire = TestWires.msh("OML^O33^OML_O33", version) + body.map { $0 + "\r" }.joined()
        #expect(GroupSpanPredicateTests.structureFindings(try GroupSpanPredicateTests.issues(wire, structure: .warning)).isEmpty)
        #expect(try Self.scoping(wire) == "spans")
        #expect(GroupSpanPredicateTests.groupFindings(try GroupSpanPredicateTests.issues(wire)) == ["OBR[2]-2 mismatch 00216"])
    }

    /// v2.5.1 to v2.8.2 OML_O33 PRIOR_RESULT prints `{ ORDER_PRIOR { [ORC] OBR
    /// ... } }` with nothing required before it, so an ORC and OBR after an
    /// order's OBR can be a prior result or the next order: the parses
    /// disagree, no spans, and OML is not a formerly gated code, so the walk.
    @Test("OML_O33 with prior results: the parses disagree, so the ORC walk",
          arguments: ["2.5.1", "2.6", "2.7.1", "2.8.2"])
    func omlO33PriorResultsAmbiguous(version: String) throws {
        let (structure, wire) = try Self.conformant("OML_O33", version)
        let ids = try Parser().parse(wire).segments.map(\.segmentID)
        #expect(ExactStructureMatcher(structure: structure).match(ids).spansWithheld)
        #expect(try Self.scoping(wire) == "walk")
    }

    @Test("OUL_R24: one ORDER span covers the OBR and the ORC after it")
    func oulR24OrderSpan() throws {
        let (structure, wire) = try Self.conformant("OUL_R24", "2.5.1")
        let ids = try Parser().parse(wire).segments.map(\.segmentID)
        let spans = ExactStructureMatcher(structure: structure).match(ids).spans.filter { $0.name == "ORDER" }
        let obrs = ids.indices.filter { ids[$0] == "OBR" }, orcs = ids.indices.filter { ids[$0] == "ORC" }
        #expect(spans.count == 2)
        for (span, (obr, orc)) in zip(spans, zip(obrs, orcs)) {
            #expect(span.indices.contains(obr) && span.indices.contains(orc) && obr < orc, "\(span)")
        }
    }

    /// `MSH [G1{A [B]}] [G2{B}]`: `MSH A B` is accepted with B in G1 or in G2.
    static let ambiguous: [StructureElement] = [
        .segment("MSH", min: 1, max: 1),
        .group("G1", min: 0, max: 1, elements: [.segment("A", min: 1, max: 1), .segment("B", min: 0, max: 1)]),
        .group("G2", min: 0, max: 1, elements: [.segment("B", min: 1, max: 1)]),
    ]

    @Test("When accepting parses place a segment in different groups, spans are withheld; the verdict is unchanged")
    func disagreeingParses() {
        let exact = ExactStructureMatcher(structure: Self.structure(Self.ambiguous))
        let both = exact.match(["MSH", "A", "B"])
        #expect(both.findings.isEmpty && both.spansWithheld && both.spans.isEmpty)
        #expect(Validator.spanIndex(both, segmentCount: 3) == nil)
        let one = exact.match(["MSH", "A"])
        #expect(!one.spansWithheld && one.spans.map(\.description) == ["G1 1...1"])
        #expect(exact.match(["MSH", "B"]).spans.map(\.description) == ["G2 1...1"])
        let rejected = exact.match(["MSH", "B", "A"])
        #expect(rejected.findings == [StructureFinding(kind: .unexpected, segmentID: "A", group: nil, index: 2)])
        #expect(!rejected.spansWithheld && rejected.spans.isEmpty)
    }

    @Test("A repeating group's occurrences are told apart by its entry, not its contents")
    func repeatingOccurrences() {
        let elements: [StructureElement] = [
            .segment("MSH", min: 1, max: 1),
            .group("G", min: 1, max: nil, elements: [.segment("A", min: 1, max: 1), .segment("B", min: 0, max: nil)]),
            .segment("A", min: 0, max: 1),
        ]
        // The last A is in a new G or the trailing [A]: withheld.
        #expect(ExactStructureMatcher(structure: Self.structure(elements)).match(["MSH", "A", "B", "A"]).spansWithheld)
        let two = ExactStructureMatcher(structure: Self.structure(elements)).match(["MSH", "A", "B", "A", "B"])
        #expect(two.spans.map(\.description) == ["G 1...2", "G 3...4"])
    }

    /// Two sibling groups with one name (as v2.4 and v2.3.1 REF_I12 print
    /// PATIENT_VISIT twice): each span is its own group, by position.
    @Test("Sibling groups with the same name are told apart by position")
    func sameNameSiblings() {
        let elements: [StructureElement] = [
            .segment("MSH", min: 1, max: 1),
            .group("G", min: 0, max: 1, elements: [.segment("ORC", min: 1, max: 1), .segment("NTE", min: 0, max: 1)]),
            .group("G", min: 0, max: 1, elements: [.segment("OBR", min: 1, max: 1)]),
        ]
        let match = StructureMatcher(structure: Self.structure(elements)).match(["MSH", "ORC", "NTE", "OBR"])
        #expect(match.spans.map(\.position) == [[1], [2]])
        #expect(match.spans.map(\.members) == [["ORC", "NTE"], ["OBR"]])
        // The first G does not define OBR, so the ORC's OBR peer is looked for
        // at the top level, not in a G that merges both definitions.
        let index = GroupSpanIndex(spans: match.spans, segmentCount: 4)
        #expect(index.range(around: 1, containing: "OBR") == 0..<4)
        #expect(index.range(around: 1, containing: "NTE") == 1..<3)
        let exact = ExactStructureMatcher(structure: Self.structure(elements)).match(["MSH", "ORC", "NTE", "OBR"])
        #expect(exact.spans == match.spans)
    }

    @Test("The fallback keeps the former gate for its message codes and versions only")
    func fallbackTable() {
        let gated = "gated OBR-2,OBR-29,OBR-3,ORC-2,ORC-3,ORC-8"
        #expect(Self.describe(Validator.fallbackScoping(version: .v2_5_1, messageCode: "OUL")) == gated)
        #expect(Self.describe(Validator.fallbackScoping(version: .v2_5_1, messageCode: "OPU")) == "walk")
        #expect(Self.describe(Validator.fallbackScoping(version: .v2_6, messageCode: "OPL")) == gated)
        #expect(Self.describe(Validator.fallbackScoping(version: .v2_8_2, messageCode: "OPU")) == "gated OBR-2,OBR-3,ORC-2,ORC-3")
        #expect(Self.describe(Validator.fallbackScoping(version: .v2_7_1, messageCode: nil)) == "gated OBR-2,OBR-3,ORC-2,ORC-3")
        #expect(Self.describe(Validator.fallbackScoping(version: .v2_4, messageCode: "OUL")) == "walk")
        #expect(Self.describe(Validator.fallbackScoping(version: .v2_8_2, messageCode: "ORU")) == "walk")
    }

    @Test("Spans apply only on a complete version, to a modelled structure, with a clean base match")
    func whenSpansApply() throws {
        let (_, oul) = try Self.conformant("OUL_R24", "2.5.1")
        #expect(try Self.scoping(oul) == "spans")
        #expect(try Self.scoping(oul, complete: []) == "gated OBR-2,OBR-29,OBR-3,ORC-2,ORC-3,ORC-8")
        let oru = GroupSpanPredicateTests.oruSecondOrderWithoutORC("2.5.1")
        #expect(try Self.scoping(oru) == "spans")
        #expect(try Self.scoping(oru, complete: []) == "walk")
        #expect(try Self.scoping(GroupSpanPredicateTests.oruSecondOrderWithoutORC("2.5.1", extra: ["EVN|A01"])) == "walk")
        #expect(try Self.scoping(TestWires.wire("ORM^O01", "2.3.1", "PID|1", "ORC|NW", "OBR|1")) == "walk")
        // A lint-failing structure whose parses agree has spans (v2.4 ORU_R01).
        #expect(try Self.scoping(TestWires.wire("ORU^R01^ORU_R01", "2.4", "PID|1", "ORC|RE", "OBR|1", "OBX|1")) == "spans")
    }

    /// P8b-4a: the ADRM profile structure governs the base findings, but "no
    /// deviation" for spans is the base match before that.
    @Test("An AU message that deviates from the base structure gets no spans, whatever the ADRM accepts")
    func auUsesBaseMatch() throws {
        let wire = TestWires.wire("OSR^Q06^OSR_Q06", "2.4", "MSA|AA|1", "QRD|20240101|R|I|Q1|||1^RD|ALL|OS|",
                                  "PID|1", "ORC|SC", "OBR|1", "OBX|1", "CTI|1")
        #expect(try Self.scoping(wire, locale: .auLocalisation) == "walk")
        let clean = TestWires.wire("OSR^Q06^OSR_Q06", "2.4", "MSA|AA|1", "QRD|20240101|R|I|Q1|||1^RD|ALL|OS|",
                                   "PID|1", "ORC|SC", "OBR|1", "CTI|1")
        #expect(try Self.scoping(clean, locale: .auLocalisation) == "spans")
    }
}
