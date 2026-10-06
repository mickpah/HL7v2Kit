// ComponentLengthValidationTests.swift
// S1-1 (register section G): a component's normative length is checked. v2.7.1 and
// v2.8.2 print normative lengths (`m..n`, `x,y,z`) on components as well as fields
// (section 2.5.5.4), and "conformant messages SHALL have a length that lies within the
// boundaries specified" (v2.8.2 section 2.5.5.0). Bare, `n=` and `n#` cells are
// conformance lengths and are not checked; no version before v2.7 prints a normative
// component length.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Component length")
struct ComponentLengthValidationTests {

    func componentLengthIssues(_ wire: String, _ options: ValidationOptions = .default) throws -> [ValidationIssue] {
        try Validator(options: options).validate(Parser().parse(wire)).issues.filter {
            if case .componentLengthOutOfRange = $0.code { return true } else { return false }
        }
    }

    /// An MSH whose MSH-21 (Message Profile Identifier, EI) carries `profile`.
    func msh(_ version: String, profile: String, type: String = "ADT^A01^ADT_A01") -> String {
        "MSH|^~\\&|A|B|C|D|20240101120000||\(type)|M1|P|\(version)|||||||||\(profile)\r"
    }

    @Test("v2.8.2 EI.4 (1..6) with seven characters is reported at the component")
    func overRange() throws {
        let issues = try componentLengthIssues(msh("2.8.2", profile: "PROF^^1.2.3^ISOXXXX"))
        try #require(issues.count == 1)
        let issue = issues[0]
        #expect(issue.code == .componentLengthOutOfRange(length: "1..6", actual: 7))
        #expect(issue.severity == .warning)
        #expect(issue.location.segmentID == "MSH")
        #expect(issue.location.fieldIndex == 21)
        #expect(issue.location.componentIndex == 4)
        #expect(issue.location.subcomponentIndex == nil)
    }

    @Test("v2.7.1 EI.4 (1..6) is checked the same way")
    func v271() throws {
        let issues = try componentLengthIssues(msh("2.7.1", profile: "PROF^^1.2.3^ISOXXXX"))
        #expect(issues.map(\.code) == [.componentLengthOutOfRange(length: "1..6", actual: 7)])
    }

    @Test("A value within the range draws nothing")
    func withinRange() throws {
        #expect(try componentLengthIssues(msh("2.8.2", profile: "PROF^^1.2.3^ISO")).isEmpty)
        #expect(try componentLengthIssues(msh("2.8.2", profile: "PROF^^1.2.3^ABCDEF")).isEmpty)
    }

    @Test("The second repetition is checked and named in the message")
    func secondRepetition() throws {
        let issues = try componentLengthIssues(msh("2.8.2", profile: "PROF^^1.2.3^ISO~PROF2^^1.2.4^ISOXXXX"))
        try #require(issues.count == 1)
        #expect(issues[0].message.contains("repetition 2"))
    }

    @Test("A length list (MSG.3, 3,7) admits only the listed lengths")
    func lengthList() throws {
        #expect(try componentLengthIssues(msh("2.8.2", profile: "", type: "ADT^A01^ADT_A01")).isEmpty)
        let issues = try componentLengthIssues(msh("2.8.2", profile: "", type: "ADT^A01^ADT_A0"))
        #expect(issues.map(\.code) == [.componentLengthOutOfRange(length: "3,7", actual: 6)])
        #expect(issues.first?.location.fieldIndex == 9)
        #expect(issues.first?.location.componentIndex == 3)
    }

    @Test("Conformance lengths (EI.1 199=, EI.2 20=) are never checked")
    func conformanceLengthsIgnored() throws {
        let long = String(repeating: "A", count: 300)
        #expect(try componentLengthIssues(msh("2.8.2", profile: "\(long)^\(long)^1.2.3^ISO")).isEmpty)
    }

    @Test("No component length is checked before v2.7", arguments: ["2.3", "2.3.1", "2.4", "2.5.1", "2.6"])
    func preV27(version: String) throws {
        let profile = "PROF^^1.2.3^ISOXXXXXXXXXXX"
        let type = "ADT^A01^ADT_A01_TOO_LONG"
        #expect(try componentLengthIssues(msh(version, profile: profile, type: type)).isEmpty)
    }

    @Test("normativeLengthSeverity nil turns the check off; its severity is used")
    func severityOption() throws {
        let wire = msh("2.8.2", profile: "PROF^^1.2.3^ISOXXXX")
        var off = ValidationOptions.default
        off.normativeLengthSeverity = nil
        #expect(try componentLengthIssues(wire, off).isEmpty)
        var error = ValidationOptions.default
        error.normativeLengthSeverity = .error
        #expect(try componentLengthIssues(wire, error).map(\.severity) == [.error])
        #expect(try componentLengthIssues(wire, .lenient).isEmpty)
    }

    @Test("An escape sequence is measured as the field check measures it")
    func escapes() throws {
        // `ISO\F\XX`: eight wire characters, six by the v2.8.2 section 2.7 count
        // (`\F\` is one), the same count FieldLengthRule applies to a field.
        #expect(try componentLengthIssues(msh("2.8.2", profile: "PROF^^1.2.3^ISO\\F\\XX")).isEmpty)
        let over = try componentLengthIssues(msh("2.8.2", profile: "PROF^^1.2.3^ISO\\F\\XXX"))
        #expect(over.map(\.code) == [.componentLengthOutOfRange(length: "1..6", actual: 7)])
    }

    @Test("The HL7 null has no length")
    func nullValue() throws {
        #expect(try componentLengthIssues(msh("2.8.2", profile: "PROF^^1.2.3^\"\"")).isEmpty)
    }

    @Test("Content after a primitive component's value is reported once, not measured")
    func extraSubcomponent() throws {
        // EI.4 `ISO&XXXXXX`: the recipient reads `ISO`; the subcomponent is
        // extraComponentsInPrimitiveField's report while that is at least as severe.
        #expect(try componentLengthIssues(msh("2.8.2", profile: "PROF^^1.2.3^ISO&XXXXXX")).isEmpty)
        var binding = ValidationOptions.default
        binding.normativeLengthSeverity = .error
        let issues = try componentLengthIssues(msh("2.8.2", profile: "PROF^^1.2.3^ISO&XXXXXX"), binding)
        #expect(issues.map(\.code) == [.componentLengthOutOfRange(length: "1..6", actual: 10)])
    }

    @Test("A value below the minimum is reported: v2.8.2 XAD.6 Country (3..3) with two characters")
    func belowMinimum() throws {
        let wire = msh("2.8.2", profile: "") + "PID|||123^^^H^MR||DOE^JOHN||||||1 Main St^^City^^^AU\r"
        let issues = try componentLengthIssues(wire)
        try #require(issues.count == 1)
        #expect(issues[0].code == .componentLengthOutOfRange(length: "3..3", actual: 2))
        #expect(issues[0].location.segmentID == "PID")
        #expect(issues[0].location.fieldIndex == 11)
        #expect(issues[0].location.componentIndex == 6)
        #expect(issues[0].location.subcomponentIndex == nil)
    }

    @Test("A present but empty component, and the HL7 null, draw nothing against a range with a minimum")
    func emptyAgainstMinimum() throws {
        let empty = msh("2.8.2", profile: "") + "PID|||123^^^H^MR||DOE^JOHN||||||1 Main St^^City^^^^H\r"
        #expect(try componentLengthIssues(empty).isEmpty)
        let null = msh("2.8.2", profile: "") + "PID|||123^^^H^MR||DOE^JOHN||||||1 Main St^^City^^^\"\"\r"
        #expect(try componentLengthIssues(null).isEmpty)
    }

    @Test("A composite field printing a range (v2.8.2 PRT-1 EI, 1..4) is not reported twice")
    func compositeFieldRange() throws {
        // Section 2.5.5.4: lengths "are not assigned for composite data types", so the
        // field's own 1..4 is not checked; EI.4 (1..6) is checked once, at the component.
        let wire = msh("2.8.2", profile: "") + "PRT|PROF^^1.2.3^ISOXXXX|UC\r"
        let all = try Validator().validate(Parser().parse(wire)).issues.filter { $0.location.segmentID == "PRT" }
        #expect(!all.contains { if case .fieldLengthOutOfRange = $0.code { true } else { false } })
        let components = all.filter { if case .componentLengthOutOfRange = $0.code { true } else { false } }
        try #require(components.count == 1)
        #expect(components[0].code == .componentLengthOutOfRange(length: "1..6", actual: 7))
        #expect(components[0].location.fieldIndex == 1)
        #expect(components[0].location.componentIndex == 4)
    }

    @Test("An n# conformance length (v2.8.2 XCN.3 Given Name, 30#) is ignored however long the value")
    func conformanceHashIgnored() throws {
        let long = String(repeating: "A", count: 500)
        let wire = msh("2.8.2", profile: "") + "PID|||123^^^H^MR||DOE^JOHN\rPV1|1|I|||||123^SMITH^\(long)\r"
        #expect(try componentLengthIssues(wire).isEmpty)
    }

    // S1-fix I1: a component table binds wherever its type is used ("If not specified, then
    // the information specified on the data type itself, if present, applies where the
    // data type is used", v2.8.2 CH02 section 2.5.5.4), a subcomponent included: HD.3
    // (1..6) inside CX.4.
    @Test("v2.8.2 HD.3 (1..6) inside CX.4 with seven characters is reported at the subcomponent")
    func subcomponentOverRange() throws {
        let wire = msh("2.8.2", profile: "") + "PID|||123^^^AUTH&1.2.3&ISOXXXX||DOE^JOHN\r"
        let issues = try componentLengthIssues(wire)
        try #require(issues.count == 1)
        #expect(issues[0].code == .componentLengthOutOfRange(length: "1..6", actual: 7))
        #expect(issues[0].severity == .warning)
        #expect(issues[0].location == IssueLocation(segmentID: "PID", segmentIndex: 1, fieldIndex: 3,
                                                    componentIndex: 4, subcomponentIndex: 3))
        #expect(issues[0].message.contains("Subcomponent PID[1]-3.4.3 ('Universal ID Type')"))
        #expect(issues[0].message.contains("component 4 ('Assigning Authority')"))
        #expect(issues[0].message.contains("repetition 1"))
        #expect(issues[0].message.contains("HD component table prints LEN 1..6"))
    }

    @Test("The subcomponent check reads v2.7.1 too, and names the repetition")
    func subcomponentSecondRepetitionV271() throws {
        let wire = msh("2.7.1", profile: "") + "PID|||1^^^A&1.2&ISO~2^^^A&1.2&ISOXXXX||DOE^JOHN\r"
        let issues = try componentLengthIssues(wire)
        try #require(issues.count == 1)
        #expect(issues[0].location.subcomponentIndex == 3)
        #expect(issues[0].message.contains("repetition 2"))
    }

    @Test("Empty subcomponents, the HL7 null and values within range draw nothing")
    func subcomponentSilent() throws {
        for cx in ["123^^^AUTH&1.2.3&ISO", "123^^^AUTH&1.2.3&", "123^^^AUTH", "123^^^&&\"\""] {
            let wire = msh("2.8.2", profile: "") + "PID|||\(cx)||DOE^JOHN\r"
            #expect(try componentLengthIssues(wire).isEmpty, "\(cx)")
        }
    }

    @Test("No subcomponent length is checked before v2.7", arguments: ["2.3", "2.3.1", "2.4", "2.5.1", "2.6"])
    func subcomponentPreV27(version: String) throws {
        let wire = msh(version, profile: "") + "PID|||123^^^AUTH&1.2.3&ISOXXXX||DOE^JOHN\r"
        #expect(try componentLengthIssues(wire).isEmpty)
    }

    @Test("normativeLengthSeverity governs the subcomponent check too")
    func subcomponentSeverity() throws {
        let wire = msh("2.8.2", profile: "") + "PID|||123^^^AUTH&1.2.3&ISOXXXX||DOE^JOHN\r"
        var options = ValidationOptions.default
        options.normativeLengthSeverity = nil
        #expect(try componentLengthIssues(wire, options).isEmpty)
        options.normativeLengthSeverity = .error
        #expect(try componentLengthIssues(wire, options).map(\.severity) == [.error])
    }

    // S1-5 (performance): the printed cells are parsed once and a field whose grammar has
    // nothing to check is skipped by key. The index must select exactly the components the
    // per-call parse selected: a range or list, never a maximum, on every grammar. S1-fix
    // I1: a grammar is also keyed when a composite component's own type has a checkable
    // component, which the pass reads at the subcomponent.
    @Test("The parsed-once index selects exactly the components a per-call parse would")
    func indexMatchesParse() {
        let versions = Set(Version.allCases.map(\.grammarVersion))
        #expect(Set(Validator.componentLengthRules.keys) == [.v2_7_1, .v2_8_2])
        func parsed(_ entry: ComponentGrammar, _ version: Version) -> FieldLengthRule? {
            guard let printed = entry.length, let rule = FieldLengthRule.parse(printed, version: version) else { return nil }
            if case .maximum = rule { return nil }
            return rule
        }
        func deprecated(_ entry: ComponentGrammar) -> Bool { ["B", "X", "W"].contains(entry.optionalityCode) }
        for version in versions {
            let grammars = DataTypeGrammarTable.grammars(for: version).merging(
                DataTypeGrammarTable.fieldGrammars(for: version)) { own, _ in own }
            for (key, grammar) in grammars {
                var anyCheckable = false
                var anyDeprecated = false
                for entry in grammar.components {
                    let indexed = entry.length.flatMap { Validator.componentLengthRules[version]?[$0] }
                    #expect(indexed == parsed(entry, version), "\(version) \(key).\(entry.index)")
                    let inner = Validator.componentGrammar(entry.dataType, version: version)?.components ?? []
                    anyCheckable = anyCheckable || parsed(entry, version) != nil
                        || inner.contains { parsed($0, version) != nil }
                    anyDeprecated = anyDeprecated || deprecated(entry) || inner.contains(where: deprecated)
                }
                #expect((Validator.componentLengthKeys[version]?.contains(key) ?? false) == anyCheckable,
                        "\(version) \(key)")
                #expect((Validator.componentDeprecationKeys[version]?.contains(key) ?? false) == anyDeprecated,
                        "\(version) \(key)")
            }
        }
    }

    // S1-fix M2: the indexes are built over the grammar versions `Version` defines, so a
    // grammar version added later is indexed rather than silently skipped.
    @Test("The component indexes cover every grammar version Version defines")
    func indexesCoverEveryGrammarVersion() {
        let versions = Set(Version.allCases.map(\.grammarVersion))
        #expect(Set(Validator.indexedGrammarVersions) == versions)
        #expect(Validator.indexedGrammarVersions.count == versions.count)
        #expect(Set(Validator.grammarKeys { _, _ in true }.keys) == versions)
    }
}
