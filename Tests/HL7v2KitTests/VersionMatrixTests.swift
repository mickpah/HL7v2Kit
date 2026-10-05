// VersionMatrixTests.swift
// The MSH-12 version matrix (ADR-018): every MSH-12 shape either resolves to
// a version, is reported, or (under rejectUnknownVersion) throws. Split out of
// VersionHandlingTests.swift, which keeps the per-behaviour version tests.

import Testing
@testable import HL7v2Kit

@Suite("Version matrix")
struct VersionMatrixTests {

    /// The synthetic ADT^A01 the version-handling suite builds.
    func adt(version: String) -> String {
        VersionHandlingTests().adt(version: version)
    }

    enum VersionOutcome: Sendable {
        /// Resolves to a modelled version; no version issue.
        case quiet
        /// `2.8` or `2.7`: validated as v2.8.2 or v2.7.1, reported as info.
        case substituted
        /// No version resolves from VID.1 (payload: VID.1 as rendered):
        /// v2.5.1 fallback with a warning, or a throw under rejectUnknownVersion.
        case unresolved(String)
        /// Empty MSH-12: v2.5.1 fallback, reported by the required-field check.
        case emptyField
        /// A second repetition on the non-repeating MSH-12: the first one
        /// names the version and the repetition is reported.
        case repeated
    }

    struct VersionRow: Sendable, CustomTestStringConvertible {
        let wire: String
        let resolved: Version
        let outcome: VersionOutcome
        var testDescription: String { "MSH-12 '\(wire)'" }
    }

    static let versionRows: [VersionRow] = [
        VersionRow(wire: "2.4", resolved: .v2_4, outcome: .quiet),
        VersionRow(wire: "2.4^AUS&Australia&ISO3166_1", resolved: .v2_4, outcome: .quiet),
        VersionRow(wire: " 2.4 ", resolved: .v2_4, outcome: .quiet),
        VersionRow(wire: "2.8", resolved: .v2_8, outcome: .substituted),
        VersionRow(wire: "2.8^AUS", resolved: .v2_8, outcome: .substituted),
        VersionRow(wire: "2.8.2", resolved: .v2_8_2, outcome: .quiet),
        VersionRow(wire: "2.7.1", resolved: .v2_7_1, outcome: .quiet),
        VersionRow(wire: "2.7.1^AUS", resolved: .v2_7_1, outcome: .quiet),
        VersionRow(wire: "2.7", resolved: .v2_7, outcome: .substituted),
        VersionRow(wire: "2.7^AUS", resolved: .v2_7, outcome: .substituted),
        VersionRow(wire: "2.5", resolved: .v2_5_1, outcome: .unresolved("2.5")),
        VersionRow(wire: "2.2", resolved: .v2_5_1, outcome: .unresolved("2.2")),
        VersionRow(wire: "2.4\\S\\x", resolved: .v2_5_1, outcome: .unresolved("2.4^x")),
        VersionRow(wire: "", resolved: .v2_5_1, outcome: .emptyField),
        VersionRow(wire: "  ", resolved: .v2_5_1, outcome: .unresolved("")),
        VersionRow(wire: "2.4&X", resolved: .v2_5_1, outcome: .unresolved("2.4&X")),
        VersionRow(wire: "&2.4", resolved: .v2_5_1, outcome: .unresolved("&2.4")),
        VersionRow(wire: "^AUS&Australia&ISO3166_1", resolved: .v2_5_1, outcome: .unresolved("")),
        VersionRow(wire: "2.4~2.5", resolved: .v2_4, outcome: .repeated),
    ]

    static func parserOptions(_ mode: String) -> ParserOptions {
        switch mode {
        case "strict": return .strict
        case "rejectUnknownVersion": return ParserOptions(rejectUnknownVersion: true)
        default: return .default
        }
    }

    static func isVersionIssue(_ issue: ValidationIssue) -> Bool {
        switch issue.code {
        case .versionNotRecognised, .versionGrammarSubstituted: return true
        default: return false
        }
    }

    @Test("Every MSH-12 shape resolves, is reported, or throws; only an empty MSH-12 is left to the required-field check",
          arguments: versionRows, ["default", "strict", "rejectUnknownVersion"])
    func versionMatrix(_ row: VersionRow, _ mode: String) throws {
        let options = Self.parserOptions(mode)
        let wire = adt(version: row.wire)
        if case .unresolved(let vid1) = row.outcome, options.rejectUnknownVersion {
            #expect(throws: ParseError.unsupportedVersion(found: vid1)) {
                try Parser(options: options).parse(wire)
            }
            return
        }
        let message = try Parser(options: options).parse(wire)
        #expect(message.version == row.resolved)
        let report = Validator().validate(message)
        let versionIssues = report.issues.filter(Self.isVersionIssue)
        let msh12Codes = report.issues
            .filter { $0.location.segmentID == "MSH" && $0.location.fieldIndex == 12 }
            .map(\.code)
        switch row.outcome {
        case .quiet:
            #expect(message.version.grammarVersion == row.resolved)
            #expect(versionIssues.isEmpty)
        case .substituted:
            #expect(message.version == row.resolved)
            #expect(message.version.grammarVersion != row.resolved)
            #expect(versionIssues.map(\.code) == [.versionGrammarSubstituted(declared: row.resolved,
                                                                             validatedAs: row.resolved.grammarVersion)])
            #expect(versionIssues.first?.severity == .info)
        case .unresolved(let vid1):
            #expect(message.version.grammarVersion == .v2_5_1)
            #expect(versionIssues.map(\.code) == [.versionNotRecognised(wireValue: vid1)])
            #expect(versionIssues.first?.severity == .warning)
            #expect(versionIssues.first?.message.contains("v2.5.1") == true)
        case .emptyField:
            #expect(message.version.grammarVersion == .v2_5_1)
            #expect(versionIssues.isEmpty)
            #expect(msh12Codes == [.requiredFieldMissing])
        case .repeated:
            #expect(message.version.grammarVersion == .v2_4)
            #expect(versionIssues.isEmpty)
            #expect(msh12Codes == [.cardinalityExceeded])
        }
    }
}
