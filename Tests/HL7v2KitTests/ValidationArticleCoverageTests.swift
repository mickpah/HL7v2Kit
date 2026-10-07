// ValidationArticleCoverageTests.swift
// P13 S3-2: every IssueCode case is named in the Validation DocC article, so a new code cannot
// ship undocumented. The case names are read from the enum's source, and an exhaustive switch
// over the enum fails to compile when a case is added without this file being updated.

import Foundation
import Testing
import HL7v2Kit

@Suite("Validation article coverage")
struct ValidationArticleCoverageTests {
    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HL7v2KitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
    }

    /// The case names declared inside `public enum IssueCode { ... }`.
    private static func declaredCaseNames() throws -> [String] {
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/HL7v2Kit/Validation/ValidationIssue.swift"),
            encoding: .utf8)
        var inEnum = false
        var names: [String] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("public enum IssueCode") { inEnum = true; continue }
            if inEnum && line.hasPrefix("}") { break }
            guard inEnum, line.hasPrefix("    case ") else { continue }
            let name = line.dropFirst("    case ".count).prefix { $0.isLetter || $0.isNumber }
            names.append(String(name))
        }
        return names
    }

    /// One value of every case. The switch in `name(of:)` is exhaustive, so a new case stops
    /// this file compiling until it is named there and given a value here.
    private static let everyCode: [IssueCode] = [
        .requiredFieldMissing, .conditionalFieldMissing, .requiredComponentMissing,
        .fieldNotSupported, .cardinalityExceeded, .zSegmentPresent,
        .profileConstraintViolation(localeRule: ""), .profileMaximumExceeded(localeRule: ""),
        .conditionalComponentMissing, .conformanceConditionMissing,
        .segmentCardinalityBelowMinimum(segmentID: "", minCount: 0, actual: 0, groupScope: ""),
        .segmentCardinalityAboveMaximum(segmentID: "", maxCount: 0, actual: 0, groupScope: ""),
        .conditionalFieldProhibited, .pairedFieldMismatch(item: ""), .valueNotInTable(table: ""),
        .segmentNotInVersionGrammar, .segmentWithdrawnInVersion,
        .versionGrammarSubstituted(declared: .v2_8, validatedAs: .v2_8_2),
        .versionNotRecognised(wireValue: ""), .fieldLengthOutOfRange(length: "", actual: 0),
        .componentLengthOutOfRange(length: "", actual: 0), .componentNotSupported(optionality: ""),
        .extraComponentsInPrimitiveField, .extraComponentsInCompositeField,
        .valueFormatInvalid(dataType: ""),
        .messageStructureSegmentMissing(structure: "", segmentID: "", group: nil),
        .messageStructureSegmentUnexpected(structure: "", segmentID: ""),
        .messageStructureMismatch(declared: "", trigger: ""),
        .messageStructureNotModelled(structure: ""), .conditionNotEvaluated(fields: []),
    ]

    private static func name(of code: IssueCode) -> String {
        switch code {
        case .requiredFieldMissing: "requiredFieldMissing"
        case .conditionalFieldMissing: "conditionalFieldMissing"
        case .requiredComponentMissing: "requiredComponentMissing"
        case .fieldNotSupported: "fieldNotSupported"
        case .cardinalityExceeded: "cardinalityExceeded"
        case .zSegmentPresent: "zSegmentPresent"
        case .profileConstraintViolation: "profileConstraintViolation"
        case .profileMaximumExceeded: "profileMaximumExceeded"
        case .conditionalComponentMissing: "conditionalComponentMissing"
        case .conformanceConditionMissing: "conformanceConditionMissing"
        case .segmentCardinalityBelowMinimum: "segmentCardinalityBelowMinimum"
        case .segmentCardinalityAboveMaximum: "segmentCardinalityAboveMaximum"
        case .conditionalFieldProhibited: "conditionalFieldProhibited"
        case .pairedFieldMismatch: "pairedFieldMismatch"
        case .valueNotInTable: "valueNotInTable"
        case .segmentNotInVersionGrammar: "segmentNotInVersionGrammar"
        case .segmentWithdrawnInVersion: "segmentWithdrawnInVersion"
        case .versionGrammarSubstituted: "versionGrammarSubstituted"
        case .versionNotRecognised: "versionNotRecognised"
        case .fieldLengthOutOfRange: "fieldLengthOutOfRange"
        case .componentLengthOutOfRange: "componentLengthOutOfRange"
        case .componentNotSupported: "componentNotSupported"
        case .extraComponentsInPrimitiveField: "extraComponentsInPrimitiveField"
        case .extraComponentsInCompositeField: "extraComponentsInCompositeField"
        case .valueFormatInvalid: "valueFormatInvalid"
        case .messageStructureSegmentMissing: "messageStructureSegmentMissing"
        case .messageStructureSegmentUnexpected: "messageStructureSegmentUnexpected"
        case .messageStructureMismatch: "messageStructureMismatch"
        case .messageStructureNotModelled: "messageStructureNotModelled"
        case .conditionNotEvaluated: "conditionNotEvaluated"
        }
    }

    @Test("the case list read from the source matches the exhaustive switch")
    func sourceMatchesSwitch() throws {
        let declared = try Self.declaredCaseNames()
        #expect(declared.count == Self.everyCode.count)
        #expect(Set(declared) == Set(Self.everyCode.map(Self.name(of:))))
    }

    @Test("every IssueCode case is named in Validation.md")
    func everyCaseDocumented() throws {
        let article = try String(
            contentsOf: Self.root.appendingPathComponent("Sources/HL7v2Kit/HL7v2Kit.docc/Validation.md"),
            encoding: .utf8)
        let missing = try Self.declaredCaseNames().filter { !article.contains("IssueCode/\($0)") }
        #expect(missing.isEmpty, "Validation.md does not link these issue codes: \(missing)")
    }
}
