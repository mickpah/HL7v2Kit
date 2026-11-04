// EscapeSequenceCheckTests.swift
// 3.31.0 (G3): an escape sequence the message's version does not define, or an escape character
// with no closing one, is a warning (3007; v2.5.1 section 2.7, v2.3 and v2.3.1 2.9, v2.4 2.10).

import Foundation
import Testing
import HL7v2Kit

@Suite("Escape sequence check")
struct EscapeSequenceCheckTests {
    static func msh(_ version: String) -> String {
        #"MSH|^~\&|APP|FAC|||20260101||ADT^A01^ADT_A01|CTRL1|P|"# + version
    }

    /// The 3007 issues for a message of `version` whose body is `lines`.
    static func issues(_ lines: [String], version: String = "2.5.1",
                       options: ValidationOptions = .default) throws -> [ValidationIssue] {
        let message = try Parser().parse(([msh(version)] + lines).joined(separator: "\r") + "\r")
        return Validator(options: options).validate(message).issues.filter { $0.code == .escapeSequenceUndefined }
    }

    /// Runs the print defines: v2.5.1 sections 2.7.1 (F S T R E H N, X, Z), 2.7.2 (C, M),
    /// 2.7.5 (X hex pairs), 2.7.6 (formatting commands) and 2.7.7 (Z), and escaped text.
    static let defined: [String] = [
        #"\F\"#, #"\S\"#, #"\T\"#, #"\R\"#, #"\E\"#, #"\H\240*\N\"#, #"\X0D\"#, #"\X0D0A\"#,
        #"\XC3A9\"#, #"\Z1\"#, #"\ZLOCAL\"#, #"\C2842\"#, #"\M2442\"#, #"\M242844\"#,
        #"\.br\"#, #"\.fi\"#, #"\.nf\"#, #"\.ce\"#, #"\.sp\"#, #"\.sp 2\"#, #"\.sp+3\"#, #"\.in+4\"#,
        #"\.ti-4\"#, #"\.sk3\"#, #"\.in+4\\.ti-4\ 1. Text\.br\"#, #"C:\E\Users\E\me"#,
        #"\E\Q\E\"#, "plain text",
    ]

    @Test("A defined run draws nothing", arguments: defined)
    func definedRunIsSilent(_ value: String) throws {
        #expect(try Self.issues(["NTE|1||" + value]).isEmpty)
    }

    /// Undefined or malformed runs on v2.5.1, with the sequence each message quotes (the first).
    static let undefined: [(value: String, sequence: String)] = [
        (#"\Q\"#, #"\Q\"#),
        (#"\X1\"#, #"\X1\"#),             // 2.7.5: pairs of hex digits
        (#"\XZZ\"#, #"\XZZ\"#),
        (#"\X\"#, #"\X\"#),               // one or more pairs
        (#"\C12\"#, #"\C12\"#),           // 2.7.2: two hex pairs
        (#"\M1234567\"#, #"\M1234567\"#), // two or three hex pairs
        (#"\.zz\"#, #"\.zz\"#),           // 2.7.6: not a formatting command
        (#"\Z\"#, #"\Z\"#),               // 2.7.7: Z and one or more characters
        (#"\Hx\"#, #"\Hx\"#),             // H takes no data
        (#"\.sp-3\"#, #"\.sp-3\"#),         // 2.7.6: a positive integer or absent
        (#"\\"#, #"\\"#),                 // 2.7.1: an escape code ID of one character
        (#"\ABC"#, #"\ABC"#),             // 2.7.1: no closing escape character
        (#"C:\Users\me"#, #"\Users\"#),
        (#"a\E\b\"#, #"\"#),              // the backslash closing \E\ opens nothing
        (#"\H\x\Q\y\N\"#, #"\Q\"#),
        (#"\Q\\W\"#, #"\Q\"#),            // one issue per value, quoting the first
    ]

    @Test("An undefined or unclosed run draws one warning at the field", arguments: undefined)
    func undefinedRunWarns(_ row: (value: String, sequence: String)) throws {
        let issues = try Self.issues(["NTE|1||" + row.value])
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.severity == .warning)
        #expect(issue.location == IssueLocation(segmentID: "NTE", segmentIndex: 1, fieldIndex: 3))
        #expect(issue.message == "Escape sequence \"\(row.sequence)\" is not defined by HL7 v2.5.1 (section 2.7)")
    }

    @Test("\\P\\ is defined from v2.7.1 (v2.7.1 section 2.5.5.2; v2.8.2 and v2.9 sections 2.7.1 and 2.7.2)",
          arguments: [("2.3", true), ("2.5.1", true), ("2.6", true), ("2.7", false), ("2.7.1", false),
                      ("2.8", false), ("2.8.2", false), ("2.9", false)])
    func truncationEscape(_ row: (version: String, warns: Bool)) throws {
        #expect(try !Self.issues([#"NTE|1||abcde\P\"#], version: row.version).isEmpty == row.warns)
    }

    @Test("\\P\\ on a version this package does not model is not reported",
          arguments: ["2.9.2", "2.8.1", "2.2", ""])
    func truncationEscapeUnmodelled(_ version: String) throws {
        #expect(try Self.issues([#"NTE|1||abcde\P\"#], version: version).isEmpty)
        #expect(try Self.issues([#"NTE|1||abcde\Q\"#], version: version).count == 1)
    }

    @Test("The message cites the version's own section", arguments: [
        ("2.3", "2.3", "2.9"), ("2.3.1", "2.3.1", "2.9"), ("2.4", "2.4", "2.10"), ("2.5.1", "2.5.1", "2.7"),
        ("2.6", "2.6", "2.7"), ("2.7.1", "2.7.1", "2.7"), ("2.7", "2.7.1", "2.7"), ("2.8.2", "2.8.2", "2.7"),
        ("2.9", "2.9", "2.7"),
    ])
    func sectionPerVersion(_ row: (declared: String, validatedAs: String, section: String)) throws {
        let issues = try Self.issues([#"NTE|1||\Q\"#], version: row.declared)
        #expect(issues.map(\.message)
                == [#"Escape sequence "\Q\" is not defined by HL7 v"# + "\(row.validatedAs) (section \(row.section))"])
    }

    @Test("Strict warns; lenient, or the severity set to nil, is silent; the severity is the option's")
    func presets() throws {
        #expect(ValidationOptions.default.escapeSequenceSeverity == .warning)
        #expect(ValidationOptions.strict.escapeSequenceSeverity == .warning)
        #expect(ValidationOptions.lenient.escapeSequenceSeverity == nil)
        #expect(try Self.issues([#"NTE|1||\Q\"#], options: .strict).map(\.severity) == [.warning])
        #expect(try Self.issues([#"NTE|1||\Q\"#], options: .lenient).isEmpty)
        var options = ValidationOptions.default
        options.escapeSequenceSeverity = .error
        #expect(try Self.issues([#"NTE|1||\Q\"#], options: options).map(\.severity) == [.error])
        options.escapeSequenceSeverity = nil
        #expect(try Self.issues([#"NTE|1||\Q\"#], options: options).isEmpty)
    }

    @Test("With valueExcerpts off the sequence is withheld")
    func excerptsOff() throws {
        var options = ValidationOptions.default
        options.valueExcerpts = false
        let issues = try Self.issues([#"NTE|1||\QZQX\"#], options: options)
        #expect(issues.map(\.message) == ["Escape sequence [value] is not defined by HL7 v2.5.1 (section 2.7)"])
    }

    @Test("MSH-1 and MSH-2 are never checked: MSH-2 holds a lone escape character")
    func delimitersNotChecked() throws {
        #expect(try Self.issues(["PID|1||MRN12345^^^H^MR||MARKER^ALEX"]).isEmpty)
        let truncation = "MSH|^~\\&#|APP|FAC|||20260101||ADT^A01^ADT_A01|CTRL1|P|2.7.1\rNTE|1||x\r"
        let message = try Parser().parse(truncation)
        #expect(!Validator().validate(message).issues.contains { $0.code == .escapeSequenceUndefined })
    }

    @Test("The message's own escape character delimits the runs")
    func ownEscapeCharacter() throws {
        let wire = "MSH|^~#&|APP|FAC|||20260101||ADT^A01^ADT_A01|CTRL1|P|2.5.1\rNTE|1||#Q# and \\Q\\\r"
        let message = try Parser().parse(wire)
        let issues = Validator().validate(message).issues.filter { $0.code == .escapeSequenceUndefined }
        #expect(issues.map(\.message) == [##"Escape sequence "#Q#" is not defined by HL7 v2.5.1 (section 2.7)"##])
    }

    @Test("The location names the component, the subcomponent and the occurrence")
    func locations() throws {
        let issues = try Self.issues([
            #"PID|1||MRN12345^^^H&\Q\&ISO^MR||MARKER^\Q\"#,
            "NTE|1||x",
            #"NTE|2||\Q\~\Q\"#,
            #"ZAU|\Q\"#,
        ])
        #expect(issues.map(\.location.pathDescription)
                == ["PID[1]-3.4.2", "PID[1]-5.2", "NTE[2]-3", "NTE[2]-3", "ZAU[1]-1"])
    }

    @Test("A value written in code: the encoder escapes an undefined run, but copies \\P\\ on every version",
          arguments: [("2.5.1", #"\Q\ \X41\ \H\x\N\ \.br\ \Z1\ \C2842\"#, false), ("2.5.1", #"\P\"#, true),
                      ("2.7.1", #"\P\"#, false)])
    func builtInCode(_ row: (version: String, value: String, warns: Bool)) throws {
        var message = try Parser().parse(Self.msh(row.version) + "\rNTE|1||x\r")
        try message.set(row.value, at: Path("NTE-3"))
        let issues = Validator().validate(message).issues.filter { $0.code == .escapeSequenceUndefined }
        #expect(!issues.isEmpty == row.warns)
        // What is reported is what serialize() writes: \Q\ goes out as \E\Q\E\, \P\ as itself.
        let written = String(decoding: message.serialize(), as: UTF8.self)
        #expect(written.contains(#"\E\Q\E\"#) == row.value.contains(#"\Q\"#))
        #expect(written.contains(#"NTE|1||\P\"#) == (row.value == #"\P\"#))
    }

    @Test("A BHS or FHS line in a message: fields 1 and 2 are skipped, the rest are read")
    func envelopeHeadersInAMessage() throws {
        let issues = try Self.issues([#"BHS|^~\&|APP|\Q\"#, #"FHS|^~\&|APP"#])
        #expect(issues.map(\.location.pathDescription) == ["BHS[1]-4"])
    }
}
