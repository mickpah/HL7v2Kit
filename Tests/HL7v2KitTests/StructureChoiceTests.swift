// StructureChoiceTests.swift
// P8b-6 (ADR-019 amendment): the choice element `< A | B >`. Model
// properties, the public tree walker, the one-pass matcher on synthetic
// choice shapes, and the Validator end to end through a synthetic table.

import Testing
@testable import HL7v2Kit

@Suite("Structure choice element")
struct StructureChoiceTests {

    private static func seg(_ id: String, _ min: Int = 1, _ max: Int? = 1) -> StructureElement {
        .segment(id, min: min, max: max)
    }

    private func run(_ elements: [StructureElement], _ ids: [String]) -> StructureMatch {
        StructureMatcher(structure: MessageStructure(id: "T", version: "2.5.1", triggers: [], citation: "test",
                                                     elements: elements)).match(ids)
    }

    // MARK: - Model

    @Test("FIRST of a choice is the union of its alternatives' FIRST sets")
    func firstSet() {
        let choice = StructureElement.choice(nil, min: 1, max: 1, alternatives: [
            Self.seg("A"),
            .group("G", min: 1, max: 1, elements: [Self.seg("B", 0), Self.seg("C")]),
        ])
        #expect(choice.firstSet == ["A", "B", "C"])
    }

    @Test("A choice is nullable when its minimum is 0 or any alternative is nullable")
    func nullable() {
        #expect(!StructureElement.choice(nil, min: 1, max: 1, alternatives: [Self.seg("A"), Self.seg("B")]).isNullable)
        #expect(StructureElement.choice(nil, min: 0, max: 1, alternatives: [Self.seg("A"), Self.seg("B")]).isNullable)
        #expect(StructureElement.choice(nil, min: 1, max: 1, alternatives: [Self.seg("A"), Self.seg("B", 0)]).isNullable)
    }

    @Test("The head segment of a choice is its first alternative's head; the group name is the choice's name")
    func head() {
        let choice = StructureElement.choice("RES", min: 1, max: 1, alternatives: [
            .group("GA", min: 1, max: 1, elements: [Self.seg("NTE", 0), Self.seg("AIS")]),
            Self.seg("AIG"),
        ])
        #expect(choice.headSegmentID == "AIS")
        #expect(choice.groupName == "RES")
        #expect(StructureElement.choice(nil, min: 1, max: 1, alternatives: [Self.seg("A"), Self.seg("B")]).groupName == nil)
    }

    @Test("children and segmentIDs cover every case, so a walker never skips a choice")
    func walker() {
        let choice = StructureElement.choice(nil, min: 1, max: 1, alternatives: [
            Self.seg("OBR"), .group("G", min: 1, max: 1, elements: [Self.seg("RXO"), Self.seg("NTE", 0, nil)]),
        ])
        let group = StructureElement.group("ORDER", min: 1, max: nil, elements: [Self.seg("ORC"), choice])
        #expect(Self.seg("PID").children.isEmpty)
        #expect(Self.seg("PID").segmentIDs == ["PID"])
        #expect(group.children == [Self.seg("ORC"), choice])
        #expect(choice.children.count == 2)
        #expect(group.segmentIDs == ["ORC", "OBR", "RXO", "NTE"])
    }

    // MARK: - Matcher

    @Test("The matcher takes the alternative whose FIRST holds the segment")
    func takesAlternative() {
        #expect(run(StructureShapes.simpleChoice, ["MSH", "A", "C"]).findings.isEmpty)
        #expect(run(StructureShapes.simpleChoice, ["MSH", "B", "C"]).findings.isEmpty)
    }

    @Test("Neither alternative: the first alternative's head is missing")
    func neither() {
        #expect(run(StructureShapes.simpleChoice, ["MSH", "C"]).findings
            == [StructureFinding(kind: .missing, segmentID: "A", group: nil, index: 1)])
    }

    @Test("Both alternatives: the second is beyond the choice's maximum")
    func both() {
        #expect(run(StructureShapes.simpleChoice, ["MSH", "A", "B", "C"]).findings
            == [StructureFinding(kind: .exceededMaximum, segmentID: "B", group: nil, index: 2)])
    }

    @Test("A named choice opens a span like a group; an unnamed one opens none")
    func spans() {
        let named = run(StructureShapes.namedChoice, ["MSH", "B", "N", "A", "C"])
        #expect(named.findings.isEmpty)
        #expect(named.spans.map(\.description) == ["RES 1...2", "RES/GB 1...2", "RES 3...3", "RES/GA 3...3"])
        #expect(named.spans.map(\.parent) == [nil, 0, nil, 2])
        #expect(run(StructureShapes.repeatingChoice, ["MSH", "B", "B", "A", "C"]).spans.isEmpty)
    }

    @Test("A missing segment inside an alternative of a named choice names the alternative's group")
    func missingInside() {
        let elements: [StructureElement] = [
            Self.seg("MSH"),
            .choice("RES", min: 1, max: 1, alternatives: [
                .group("GA", min: 1, max: 1, elements: [Self.seg("A"), Self.seg("N")]), Self.seg("B"),
            ]),
        ]
        #expect(run(elements, ["MSH", "A"]).findings == [StructureFinding(kind: .missing, segmentID: "N", group: "GA", index: 2)])
        #expect(run(elements, ["MSH"]).findings == [StructureFinding(kind: .missing, segmentID: "A", group: "RES", index: 1)])
    }

    // MARK: - Validator end to end

    private static let table: [String: MessageStructure] = [
        "ZZZ_Z01": MessageStructure(id: "ZZZ_Z01", version: "2.5.1", triggers: ["ZZZ^Z01"], citation: "synthetic choice",
                                    elements: [
                                        Self.seg("MSH"), Self.seg("PID"),
                                        .choice(nil, min: 1, max: 1, alternatives: [Self.seg("OBR"), Self.seg("RXO")]),
                                        Self.seg("NTE", 0, nil),
                                    ]),
    ]

    private func issues(_ body: [String]) throws -> [IssueCode] {
        let message = try Parser().parse(MessageStructureValidationTests.wire("ZZZ^Z01^ZZZ_Z01", body))
        let validator = Validator()
        let resolved = validator.resolveStructure(message, severity: .error, structures: Self.table)
        let structure = try #require(resolved.structure)
        return validator.matchStructure(structure, message: message, severity: .error).map(\.code)
    }

    @Test("Validator: a message taking the second alternative is clean")
    func validatorSecond() throws {
        #expect(try issues([MessageStructureValidationTests.pid, "RXO|1", "NTE|1"]).isEmpty)
    }

    @Test("Validator: a message taking neither alternative misses the first alternative's head")
    func validatorNeither() throws {
        #expect(try issues([MessageStructureValidationTests.pid, "NTE|1"])
            == [.messageStructureSegmentMissing(structure: "ZZZ_Z01", segmentID: "OBR", group: nil)])
    }

    @Test("Validator: a message with both alternatives has the second unexpected")
    func validatorBoth() throws {
        #expect(try issues([MessageStructureValidationTests.pid, "OBR|1", "RXO|1"])
            == [.messageStructureSegmentUnexpected(structure: "ZZZ_Z01", segmentID: "RXO")])
    }
}
