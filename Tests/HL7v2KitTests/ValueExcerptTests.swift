// ValueExcerptTests.swift
// X1 task 3: with ValidationOptions.valueExcerpts off, no issue message carries a value read
// from the message, whole or in part; on (the default), the value is quoted as before.

import Foundation
import Testing
import HL7v2Kit

@Suite("Value excerpts")
struct ValueExcerptTests {
    static let marker = "ZQXMARKERZQX"
    static let msh = "MSH|^~\\&|LAB|FAC|EMR|FAC|20240101120000||"

    /// The issue messages for `wire` under strict options.
    static func messages(_ wire: String, locale: HL7Locale, excerpts: Bool) throws -> [String] {
        var options = ValidationOptions.strict
        options.valueExcerpts = excerpts
        return Validator(options: options, locale: locale).validate(try Parser().parse(wire)).issues.map(\.message)
    }

    /// One wire per kind of value-quoting site, the marker in the offending value. The AU rows
    /// come from LocaleAUProfileTests.exactMessageRows.
    static let sites: [(site: String, wire: String, locale: HL7Locale)] = [
        ("value format", msh + "ADT^A01^ADT_A01|C1|P|2.5.1\rPID|1||1^^^H^MR||DOE^J||\(marker)\r", .international),
        ("field code table", msh + "ADT^A01^ADT_A01|C1|P|2.5.1|||\(marker)\r", .international),
        ("component code table", msh + "ADT^A01^ADT_A01|C1|\(marker)|2.5.1\r", .international),
        ("content after a primitive value", msh + "ADT^A01^ADT_A01|C1|P|2.5.1|||\(marker)^X\r", .international),
        ("paired fields", msh + "ORM^O01^ORM_O01|C1|P|2.5.1\rPID|1||1^^^H^MR||DOE^J\rORC|NW|\(marker)\rOBR|1|OTHER1\r", .international),
        ("AU value set", "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1|||AL|NE|\(marker)||en^English^ISO639\rPID|1||999999^^^HOSP^MR\r", .auLocalisation),
        ("AU components must differ", "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG|P|2.5.1\rOBR|1|PLACER^HOSP^1.2.3^ISO|FILLER^LAB^1.2.4^ISO|GLU^Glucose^\(marker)^GLU2^Glucose alt^\(marker)\r", .auLocalisation),
    ]

    @Test("On by default, and on, the site quotes the value", arguments: sites)
    func onQuotes(_ row: (site: String, wire: String, locale: HL7Locale)) throws {
        #expect(ValidationOptions.default.valueExcerpts && ValidationOptions.strict.valueExcerpts
                && ValidationOptions.lenient.valueExcerpts)
        let messages = try Self.messages(row.wire, locale: row.locale, excerpts: true)
        #expect(messages.contains { $0.contains("\"\(Self.marker)\"") }, "\(row.site): the site did not fire")
    }

    @Test("Off, the value is withheld whole as [value]", arguments: sites)
    func offWithholds(_ row: (site: String, wire: String, locale: HL7Locale)) throws {
        let messages = try Self.messages(row.wire, locale: row.locale, excerpts: false)
        #expect(!messages.contains { $0.contains("ZQX") }, "\(row.site): \(messages.filter { $0.contains("ZQX") })")
        #expect(messages.contains { $0.contains("[value]") }, "\(row.site)")
    }

    @Test("A value holding a quote mark, a delimiter or an escape is withheld whole")
    func awkwardValueWithheldWhole() throws {
        let wire = Self.msh + "ADT^A01^ADT_A01|C1|P|2.5.1\rPID|1||1^^^H^MR||DOE^J||ZQX\"A\\T\\B\\F\\C\r"
        let off = try Self.messages(wire, locale: .international, excerpts: false)
        #expect(!off.contains { $0.contains("ZQX") || $0.contains("B|C") || $0.contains("A&B") })
    }

    /// `message` with every populated value outside MSH replaced by `marker(n)`, serialised
    /// and re-parsed, as a receiver would see it.
    static func marked(_ message: Message, _ marker: (Int) -> String) throws -> Message {
        var n = 0
        let segments = message.segments.map { segment -> Segment in
            guard segment.segmentID != "MSH" else { return segment }
            let fields = segment.fields.enumerated().map { index, field -> Field in
                guard index > 0 else { return field }   // fields is indexed by field number
                return Field(repetitions: field.repetitions.map { repetition in
                    Repetition(components: repetition.components.map { component in
                        Component(subcomponents: component.subcomponents.map { sub in
                            guard !sub.value.isEmpty else { return sub }
                            n += 1
                            return Subcomponent(marker(n))
                        })
                    })
                })
            }
            return .unknown(UnknownSegment(segmentID: segment.segmentID, fields: fields))
        }
        let rebuilt = Message(version: message.version, encodingCharacters: message.encodingCharacters,
                              segments: segments, characterEncoding: message.characterEncoding)
        return try Parser().parse(rebuilt.serialize())
    }

    @Test("Off, no issue message over the marked corpus carries a marker")
    func markedCorpusSweep() throws {
        // Unique markers reach every value site; one shared marker also fires the uniqueness rules.
        let markers: [(String, (Int) -> String)] = [("unique", { "ZQX\($0)Q" }), ("shared", { _ in "ZQXSAMEQ" })]
        var options = ValidationOptions.strict
        options.valueExcerpts = false
        for url in try FixtureCorpus.validFixtureURLs() {
            let original = try Parser().parse(Data(contentsOf: url))
            for (kind, marker) in markers {
                let message = try Self.marked(original, marker)
                for locale in [HL7Locale.international, .auLocalisation] {
                    let leaks = Validator(options: options, locale: locale).validate(message).issues
                        .filter { $0.message.contains("ZQX") }
                        .map { "\($0.location.pathDescription): \($0.message)" }
                    #expect(leaks.isEmpty, "\(url.lastPathComponent), \(kind) markers, \(locale): \(leaks.prefix(3))")
                }
            }
        }
    }
}
