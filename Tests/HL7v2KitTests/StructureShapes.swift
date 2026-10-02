// StructureShapes.swift
// Synthetic element trees shared by the determinism-lint tests and the
// reference-recogniser property test (ADR-019). Each is named after the
// shape it exercises; `all` lists every one, so the property test covers
// each shape the lint tests use.

@testable import HL7v2Kit

enum StructureShapes {
    private static func seg(_ id: String, _ min: Int, _ max: Int?) -> StructureElement {
        .segment(id, min: min, max: max)
    }

    /// ADR-019's example: a trailing NTE in a group, then a sibling NTE.
    static let trailingThenSibling: [StructureElement] = [
        seg("MSH", 1, 1),
        seg("OBR", 1, 1),
        .group("OBSERVATION", min: 0, max: nil, elements: [seg("OBX", 1, 1), seg("NTE", 0, nil)]),
        seg("NTE", 0, nil),
    ]

    /// The pre-v2.5 result shape `MSH OBR {[NTE]} {[OBX] {[NTE]}}`.
    static let preV25: [StructureElement] = [
        seg("MSH", 1, 1),
        seg("OBR", 1, 1),
        seg("NTE", 0, nil),
        .group("OBSERVATION", min: 0, max: nil, elements: [seg("OBX", 0, 1), seg("NTE", 0, nil)]),
    ]

    /// `MSH {G: [X] [{N}]}`: an all-optional unbounded group whose first
    /// child is optional and not repeating (fix round 1, ruling 3).
    static let allOptionalGroup: [StructureElement] = [
        seg("MSH", 1, 1),
        .group("G", min: 1, max: nil, elements: [seg("X", 0, 1), seg("N", 0, nil)]),
    ]

    /// `MSH {G: [A] [X] [{N}]}`: a nullable prefix that cannot begin with X.
    static let nullablePrefix: [StructureElement] = [
        seg("MSH", 1, 1),
        .group("G", min: 1, max: nil, elements: [seg("A", 0, 1), seg("X", 0, 1), seg("N", 0, nil)]),
    ]

    /// The reviewer's counter-example `MSH {G: X {Q: X Y}}`: Q's X reaches
    /// FIRST(G) only through G's required X, not through Q.
    static let counterExample: [StructureElement] = [
        seg("MSH", 1, 1),
        .group("G", min: 1, max: nil, elements: [
            seg("X", 1, 1),
            .group("Q", min: 1, max: nil, elements: [seg("X", 1, 1), seg("Y", 1, 1)]),
        ]),
    ]

    /// `MSH {G: [X] {Q: X Y}}`: the prefix is nullable but can begin with X.
    static let prefixBeginsWithSegment: [StructureElement] = [
        seg("MSH", 1, 1),
        .group("G", min: 1, max: nil, elements: [
            seg("X", 0, 1),
            .group("Q", min: 1, max: nil, elements: [seg("X", 1, 1), seg("Y", 1, 1)]),
        ]),
    ]

    /// A repeating group inside an enclosing group with a finite maximum.
    static let finiteEnclosing: [StructureElement] = [
        seg("MSH", 1, 1),
        .group("P", min: 1, max: 2, elements: [
            seg("H", 0, 1),
            .group("O", min: 1, max: nil, elements: [seg("A", 0, 1), seg("B", 1, 1)]),
        ]),
    ]

    /// FOLLOW must look past a nullable required group.
    static let nullableFollow: [StructureElement] = [
        seg("MSH", 1, 1),
        seg("X", 0, nil),
        .group("G", min: 1, max: 1, elements: [seg("Y", 0, 1)]),
        seg("X", 1, 1),
    ]

    /// A required group all of whose children are optional, then C.
    static let nullableGroup: [StructureElement] = [
        seg("MSH", 1, 1),
        .group("G", min: 1, max: 1, elements: [seg("A", 0, 1), seg("B", 0, 1)]),
        seg("C", 1, 1),
    ]

    static let all: [(name: String, elements: [StructureElement])] = [
        ("trailingThenSibling", trailingThenSibling), ("preV25", preV25),
        ("allOptionalGroup", allOptionalGroup), ("nullablePrefix", nullablePrefix),
        ("counterExample", counterExample), ("prefixBeginsWithSegment", prefixBeginsWithSegment),
        ("finiteEnclosing", finiteEnclosing), ("nullableFollow", nullableFollow),
        ("nullableGroup", nullableGroup),
    ]
}
