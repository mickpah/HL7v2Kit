// AnonymiserTests.swift
// X1 task 4b: the Anonymiser library API. Under one key the same original value gives the
// same synthetic value in every message, so linkage across messages survives; the output
// keeps the input's shape, so it validates as the input did.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Anonymiser (library)")
struct AnonymiserTests {
    static func anonymised(_ wire: String, key: UInt64 = 7,
                           replacingIdentifier: (@Sendable (Anonymiser.Identifier) -> String)? = nil) throws -> Message {
        let input = try Parser().parse(wire)
        return try Parser().parse(Anonymiser(key: key, replacingIdentifier: replacingIdentifier).anonymise(input).serialize())
    }

    static func wire(control: String, _ segments: String...) -> String {
        (["MSH|^~\\&|LAB|FAC|EMR|FAC|20240101120000||ADT^A01^ADT_A01|\(control)|P|2.4"] + segments)
            .joined(separator: "\r") + "\r"
    }

    static let pid = "PID|1||MRN12345^^^HOSP^MR||MARKERFAM^MARKERGIV"

    @Test("Under one key the same value gives the same output in messages with different MSH-10")
    func sameValueSameOutputUnderOneKey() throws {
        let a = try Self.anonymised(Self.wire(control: "CTRL1", Self.pid))
        let b = try Self.anonymised(Self.wire(control: "CTRL2", Self.pid))
        #expect(a["PID-3.1"] == b["PID-3.1"] && a["PID-3.1"] != "MRN12345")
        #expect(a["PID-5.1"] == "Edwards" && a["PID-5.2"] == "Taylor")   // key 7, from the seed rule
        #expect(b["PID-5.1"] == "Edwards" && b["PID-5.2"] == "Taylor")
    }

    @Test("A different key gives a different name")
    func differentKeyDifferentOutput() throws {
        let eight = try Self.anonymised(Self.wire(control: "CTRL1", Self.pid), key: 8)
        #expect(eight["PID-5.1"] == "Jensen" && eight["PID-5.2"] == "Casey")
    }

    @Test("A covered segment stays typed, so typed access needs no re-parse (#12)")
    func coveredSegmentStaysTyped() throws {
        let input = try Parser().parse(Self.wire(control: "CTRL1", Self.pid))
        let output = Anonymiser(key: 7).anonymise(input)
        let pid = try #require(output.firstSegment(PID.self))
        #expect(pid.patientName?.familyName == "Edwards")   // key 7, as in sameValueSameOutputUnderOneKey
        let reparsed = try Parser().parse(output.serialize())
        #expect(output == reparsed)
    }

    @Test("The identifier seed is the shared FNV-1a value")
    func seedMatchesSharedLiteral() {
        #expect(anonymiserSeed(key: 42, kind: "identifier", original: "8003608166690503") == 13_496_976_630_852_856_219)
    }

    @Test("The closure sees CX-1, CX-5, CX-4.1 and the seed, nil where absent, and its value is written")
    func identifierClosureSeesContext() throws {
        final class Seen: @unchecked Sendable { var calls: [Anonymiser.Identifier] = [] }
        let seen = Seen()
        let out = try Self.anonymised(
            Self.wire(control: "C1", "PID|1||8003608166690503^^^AUSHIC^NI~ABC123||FAM^GIV"), key: 42
        ) { identifier in
            seen.calls.append(identifier)
            return "REPLACED\(seen.calls.count)"
        }
        #expect(seen.calls == [
            Anonymiser.Identifier(value: "8003608166690503", typeCode: "NI", assigningAuthority: "AUSHIC",
                                  seed: 13_496_976_630_852_856_219),
            Anonymiser.Identifier(value: "ABC123", typeCode: nil, assigningAuthority: nil,
                                  seed: anonymiserSeed(key: 42, kind: "identifier", original: "ABC123")),
        ])
        #expect(out["PID-3.1"] == "REPLACED1" && out["PID-3~2.1"] == "REPLACED2")
        #expect(out["PID-3.4"] == "AUSHIC" && out["PID-3.5"] == "NI")
    }

    @Test("An identifier held in subcomponents is still replaced")
    func identifierInSubcomponentsReplaced() throws {
        let out = try Self.anonymised(Self.wire(control: "C1", "PID|1||MARKERA&MARKERB^^^H^MR||FAM"))
        #expect(!String(decoding: out.serialize(), as: UTF8.self).contains("MARKER"))
        #expect(out["PID-3.4"] == "H" && out["PID-3.5"] == "MR")
    }

    @Test("Every repetition is replaced, an escaped name round-trips")
    func repetitionsAndEscapes() throws {
        let out = try Self.anonymised(Self.wire(control: "C1", #"PID|1||1^^^H^MR||SMITH^JOHN~O\T\BRIEN^MARY"#))
        let bytes = out.serialize()
        let text = String(decoding: bytes, as: UTF8.self)
        for original in ["SMITH", "JOHN", "BRIEN", "MARY"] { #expect(!text.contains(original), "\(original)") }
        #expect(out["PID-5~2.1"] != nil)
        #expect(try Parser().parse(bytes).serialize() == bytes)
    }

    @Test("An empty or absent field or component stays empty: nothing is invented")
    func emptyStaysEmpty() throws {
        let wire = "MSH|^~\\&|LAB|FAC||FAC|20240101120000||ADT^A01^ADT_A01|C1|P|2.4\rPID|1||1^^^H^MR||FAM\rGT1|1||GUARFAM^GUARGIV|||\rNTE|1||\r"
        let out = try Parser().parse(Anonymiser(key: 7).anonymise(try Parser().parse(wire)).serialize())
        for path in ["MSH-5", "PID-5.2", "PID-13", "GT1-6", "NTE-3"] { #expect((out[path] ?? "").isEmpty, "\(path)") }
    }

    @Test("Type codes, authorities and use codes are kept")
    func shapeKept() throws {
        let out = try Self.anonymised(Self.wire(control: "C1",
            "PID|1||1^^^H^MR||FAM^GIV||||||1 Main St^^Town^NSW^2000^AU^H||^PRN^PH^^^^5551234",
            "PV1|1|O|||||1234567A^DOC^ANNE^^^DR^^^AUSHICPR^^^^PRN"))
        #expect(out["PID-3.4"] == "H" && out["PID-3.5"] == "MR")
        #expect(out["PID-11.6"] == "AU" && out["PID-11.7"] == "H" && out["PID-11.1"] != "1 Main St")
        #expect(out["PID-13.2"] == "PRN" && out["PID-13.3"] == "PH" && out["PID-13.7"] != "5551234")
        #expect(out["PV1-7.6"] == "DR" && out["PV1-7.9"] == "AUSHICPR" && out["PV1-7.13"] == "PRN")
        #expect(out["PV1-7.1"] != "1234567A")
    }

    @Test("Under a key, every covered field loses its original value", arguments: AnonymiseTests.covered)
    func coveredFieldScrubbedUnderAKey(_ field: String) throws {
        let out = Anonymiser(key: 7).anonymise(try Parser().parse(AnonymiseTests.wire)).serialize()
        #expect(!String(decoding: out, as: UTF8.self).contains(AnonymiseTests.marker(field)))
    }

    @Test("Key 42 output for two fixtures matches the committed baseline (every run, macOS and Linux)")
    func pinnedOutputForKey42() throws {
        var lines: [String] = []
        for name in ["adt_a01_with_insurance.hl7", "adt_a01_with_nk1.hl7"] {
            let message = try Parser().parse(Data(contentsOf: FixtureCorpus.fixtureURL(named: name)))
            lines.append("# \(name)")
            lines += String(decoding: Anonymiser(key: 42).anonymise(message).serialize(), as: UTF8.self)
                .split(separator: "\r", omittingEmptySubsequences: false).map(String.init)
        }
        try Baseline.check(lines, against: "anonymiser-key42.txt")
    }

    /// Findings the anonymiser changes by design, as `fixture|number@path`, with the reason.
    static let expectedChanges: [String: String] = [:]

    @Test("Each AU fixture validates the same after anonymising (strict, AU profile)")
    func outputValidatesLikeInput() throws {
        let validator = Validator(options: .strict, locale: .auLocalisation)
        func findings(_ message: Message) -> [String] {
            validator.validate(message).issues.map { "\($0.code.number)@\($0.location.pathDescription)" }.sorted()
        }
        for url in try FixtureCorpus.validFixtureURLs() where url.lastPathComponent.hasPrefix("au_") {
            let name = url.lastPathComponent
            let input = try Parser().parse(Data(contentsOf: url))
            let output = try Parser().parse(Anonymiser(key: 42).anonymise(input).serialize())
            let kept = { (finding: String) in Self.expectedChanges["\(name)|\(finding)"] == nil }
            #expect(findings(input).filter(kept) == findings(output).filter(kept), "\(name)")
        }
    }

    /// GSP, GSR and GSC (2.9.1 CH03 3.4.19 to 3.4.21, pages 220 to 228) with every field populated.
    /// GSP-7 and GSR-4 repeat, though the print does not let them, to show every repetition is replaced.
    static let genderSex = [
        "MSH|^~\\&|SYNTH_APP|TESTFAC|SYNTH_RCV|TESTFAC|20240301120000||ADT^A01^ADT_A01|CTRLGS01|P|2.9.1",
        "PID|1||SYN-0291^^^TESTFAC^MR||Testpatient^Sample||19000101|U",
        "GSP|1|U|SYN-GSP3^TESTFAC^2.999.1^ISO|76691-5^Gender identity^LN^^^^^^SYN-GSP4O|SYN-GSP5^SYN-GSP5T^L"
            + "|20210101^20210630|SYN-GSP7~SYN-GSP7R",
        "GSR|1|U|SYN-GSR3^TESTFAC|SYN-GSR4^SYN-GSR4T^L~SYN-GSR4R^^L|SYN-GSR5^SYN-GSR5T^L|SYN-GSR6^SYN-GSR6T^L"
            + "|SYN-GSR7^SYN-GSR7T^L|20210102120000|20210103^20210704|SYN-GSR10",
        "GSC|1|U|SYN-GSC3^TESTFAC|SYN-GSC4^SYN-GSC4T^L|20210105^20210706|OBR^1~ORC^1|OBX^1^5|SYN-GSC8",
    ].joined(separator: "\r") + "\r"

    /// The fields GSP, GSR and GSC keep: the set ID, the action code, and GSC-6 and GSC-7, which
    /// point at a place in the message (ERL, CH02A 2A.2.28, page 44).
    static let genderSexKept = ["GSP": [1, 2], "GSR": [1, 2], "GSC": [1, 2, 6, 7]]

    /// `genderSex` anonymised under key 7, or under the tool's rule with salt 41.
    static func genderSexAnonymised(keyed: Bool) throws -> String {
        let anonymiser = keyed ? Anonymiser(key: 7) : Anonymiser(legacySalt: 41)
        return String(decoding: anonymiser.anonymise(try Parser().parse(genderSex)).serialize(), as: UTF8.self)
    }

    @Test("GSP, GSR and GSC keep only the set ID, action code and pointers; every repetition of the rest is replaced",
          arguments: [true, false])
    func genderSexCovered(keyed: Bool) throws {
        let fields = { (wire: String) in
            wire.split(separator: "\r").map { $0.split(separator: "|", omittingEmptySubsequences: false).map(String.init) }
        }
        let text = try Self.genderSexAnonymised(keyed: keyed)
        let input = fields(Self.genderSex), output = fields(text)
        #expect(output.count == input.count)
        for (before, after) in zip(input, output) {
            guard let kept = Self.genderSexKept[before[0]] else { continue }
            #expect(after.count == before.count, "\(before[0]) field count")
            for n in 1..<min(before.count, after.count) {
                let label = "\(before[0])-\(n), keyed \(keyed)"
                if kept.contains(n) { #expect(after[n] == before[n], "\(label)"); continue }
                let was = before[n].split(separator: "~"), now = after[n].split(separator: "~")
                #expect(now.count == was.count, "\(label) repetitions")
                for (a, b) in zip(was, now) { #expect(!b.isEmpty && b != a, "\(label): \(b)") }
            }
        }
        for original in ["SYN-GS", "76691-5", "Gender identity", "20210101", "20210630", "20210102", "20210103",
                         "20210704", "20210105", "20210706"] {
            #expect(!text.contains(original), "\(original), keyed \(keyed)")
        }
    }

    @Test("A day-precision validity period (DR) moves both ends by one shift, so it keeps its order and length",
          arguments: [true, false])
    func validityPeriodMovesAsOne(keyed: Bool) throws {
        let out = try Parser().parse(Self.genderSexAnonymised(keyed: keyed))
        let format = DateFormatter()
        format.dateFormat = "yyyyMMdd"
        format.timeZone = TimeZone(identifier: "UTC")
        func days(_ start: String?, _ end: String?) throws -> Int {
            let from = try #require(format.date(from: start ?? ""))
            let to = try #require(format.date(from: end ?? ""))
            return Int(to.timeIntervalSince(from) / 86_400)
        }
        for (path, start, end) in [("GSP-6", "20210101", "20210630"), ("GSR-9", "20210103", "20210704"),
                                   ("GSC-5", "20210105", "20210706")] {
            #expect(out["\(path).1"] != start, "\(path)")
            #expect(try days(out["\(path).1"], out["\(path).2"]) == days(start, end), "\(path), keyed \(keyed)")
        }
    }

    @Test("Under a key an instance identifier (EI) keeps its assigning authority and is not given to the closure")
    func instanceIdentifierKeepsAuthority() throws {
        final class Seen: @unchecked Sendable { var values: [String] = [] }
        let seen = Seen()
        let out = try Self.anonymised(Self.genderSex) { identifier in
            seen.values.append(identifier.value)
            return "REPLACED"
        }
        #expect(seen.values == ["SYN-0291"])   // PID-3, a CX
        #expect(out["GSP-3.1"]?.hasPrefix("SYN-") == true && out["GSP-3.1"] != "SYN-GSP3")
        #expect(out["GSP-3.2"] == "TESTFAC" && out["GSP-3.3"] == "2.999.1" && out["GSP-3.4"] == "ISO")
        #expect(out["GSR-3.2"] == "TESTFAC" && out["GSC-3.2"] == "TESTFAC")
    }

    @Test("Under the tool's rule an instance identifier (EI) keeps its assigning authority too")
    func instanceIdentifierKeepsAuthorityUnderTheToolRule() throws {
        let out = try Parser().parse(Self.genderSexAnonymised(keyed: false))
        #expect(out["GSP-3.1"]?.hasPrefix("SYN-") == true && out["GSP-3.1"] != "SYN-GSP3")
        #expect(out["GSP-3.2"] == "TESTFAC" && out["GSP-3.3"] == "2.999.1" && out["GSP-3.4"] == "ISO")
        #expect(out["GSR-3.2"] == "TESTFAC" && out["GSC-3.2"] == "TESTFAC")
    }

    /// GSP-6 as written, for a GSP holding `range`, under key 7 or the tool's rule with salt 41.
    static func validityPeriod(_ range: String, keyed: Bool) throws -> String {
        let wire = String(genderSex.prefix { $0 != "\r" }) + "\rGSP|1|U|SYN-GSPA|SYN-GSPC^^L|SYN-GSPV^^L|\(range)\r"
        let anonymiser = keyed ? Anonymiser(key: 7) : Anonymiser(legacySalt: 41)
        let gsp = String(decoding: anonymiser.anonymise(try Parser().parse(wire)).serialize(), as: UTF8.self)
            .split(separator: "\r")[1]
        return String(gsp.split(separator: "|", omittingEmptySubsequences: false)[6])
    }

    @Test("A validity period with a missing or malformed end: what each rule writes")
    func validityPeriodEdges() throws {
        for (range, keyed, tool) in [
            ("20210101", "20201218", "20210115"),                               // no end: the start moves
            ("^20210630", "^20210707", "^20210714"),                            // no start: the end, by its own shift
            ("20210101^2021XX30", "[REDACTED]", "[REDACTED]"),                  // an end no DTM, whatever its length:
            ("20210101^SYNTEXT", "[REDACTED]", "[REDACTED]"),                   // the range replaced whole
        ] {
            #expect(try Self.validityPeriod(range, keyed: true) == keyed, "\(range), keyed")
            #expect(try Self.validityPeriod(range, keyed: false) == tool, "\(range), tool")
        }
    }

    // DTM may stop at the year or the month (CH02A 2A.2.22 p39). Key 7 moves a range from 202107 forward one
    // month, from 202101 or 202112 forward three; salt 41 moves every range forward two weeks or two months.
    @Test("A range moves both ends by one shift at its coarser end's precision, so it keeps its order")
    func validityPeriodCoarsePrecision() throws {
        // Each end's digits, the finer cut to the coarser's length, in order.
        func ordered(_ range: String) -> Bool {
            let ends = range.split(separator: "^").map { $0.prefix { $0.isNumber } }
            let n = min(ends[0].count, ends[1].count)
            return ends[0].prefix(n) <= ends[1].prefix(n)
        }
        for (range, keyed, tool) in [
            ("202107^202112", "202108^202201", "202109^202202"),        // month ends: one shift, the length kept
            ("202107^20210715", "202108^20210815", "202109^20210915"),  // a day end moves by the same months
            ("202101^20210131", "202104^20210430", "202103^20210331"),  // the 31st: the month's last day
            ("202112^20211231", "202203^20220331", "202202^20220228"),
            ("2021^20210105", "2021^2021", "2021^2021"),                // beside a year, the finer end cut to its year
            ("2021^2022", "2021^2022", "2021^2022"),                    // years are kept
        ] {
            #expect(try Self.validityPeriod(range, keyed: true) == keyed, "\(range), keyed")
            #expect(try Self.validityPeriod(range, keyed: false) == tool, "\(range), tool")
            #expect(ordered(keyed) && ordered(tool), "\(range)")
        }
    }

    /// A 2.9.1 or 2.4 message holding `value` in every date field the anonymiser covers; GSP, GSR and GSC on 2.9.1.
    static func everyDateField(_ value: String, version: String = "2.9.1") -> String {
        func segment(_ id: String, _ values: [Int: String]) -> String {
            ([id] + (1...(values.keys.max() ?? 1)).map { values[$0] ?? "" }).joined(separator: "|")
        }
        let v = value
        var segments = ["MSH|^~\\&|SYNTH_APP|TESTFAC|SYNTH_RCV|TESTFAC|20240301120000||ADT^A01^ADT_A01|CTRLDT01|P|\(version)",
                        segment("PID", [1: "1", 7: v, 29: v]), segment("NK1", [1: "1", 16: v])]
        if version == "2.9.1" {
            segments += [segment("GSP", [1: "1", 2: "U", 6: v]), segment("GSR", [1: "1", 2: "U", 8: v, 9: v]),
                         segment("GSC", [1: "1", 2: "U", 5: v])]
        }
        segments += [segment("GT1", [1: "1", 8: v, 24: v]), segment("IN1", [1: "1", 18: v])]
        return segments.joined(separator: "\r") + "\r"
    }

    static let dateFields = ["PID-7", "PID-29", "NK1-16", "IN1-18", "GT1-8", "GT1-24", "GSR-8",
                             "GSP-6.1", "GSR-9.1", "GSC-5.1"]

    @Test("A month value moves by whole months and keeps its precision, alike in every date field; a year is kept")
    func coarseDateInEveryField() throws {
        for (value, keyed, tool) in [
            ("198007", "198005", "198009"),                 // key 7: back two months; salt 41: forward two
            ("202107-0500", "202108-0500", "202109-0500"),  // the offset kept
            ("1980", "1980", "1980"), ("2021+1000", "2021+1000", "2021+1000"),
        ] {
            let input = try Parser().parse(Self.everyDateField(value))
            for (anonymiser, expected) in [(Anonymiser(key: 7), keyed), (Anonymiser(legacySalt: 41), tool)] {
                let out = try Parser().parse(anonymiser.anonymise(input).serialize())
                for path in Self.dateFields { #expect(out[path] == expected, "\(value) at \(path)") }
            }
        }
    }

    @Test("A value that is no DTM, of any length, becomes [REDACTED], and draws no finding the input did not")
    func malformedDateReplaced() throws {
        // Under eight characters, an ISO-style and a slashed date of birth, and text of eight or more.
        for (malformed, version) in ["SYNTEXT", "1980-06-15", "15/06/1980", "UNKNOWNDATE"].flatMap({ m in
            ["2.4", "2.9.1"].map { (m, $0) }
        }) {
            let input = try Parser().parse(Self.everyDateField(malformed, version: version))
            for anonymiser in [Anonymiser(key: 7), Anonymiser(legacySalt: 41)] {
                let output = try Parser().parse(anonymiser.anonymise(input).serialize())
                #expect(!String(decoding: output.serialize(), as: UTF8.self).contains(malformed), "\(malformed), \(version)")
                for path in Self.dateFields where version == "2.9.1" || !path.hasPrefix("GS") {
                    #expect(output[path] == "[REDACTED]", "\(malformed) at \(path), \(version)")
                }
                for locale in HL7Locale.allCases {
                    let validator = Validator(options: .strict, locale: locale)
                    let before = validator.validate(input).issues, after = validator.validate(output).issues
                    let formatAtPID7 = before.contains { issue in
                        guard case .valueFormatInvalid = issue.code else { return false }
                        return issue.location.segmentID == "PID" && issue.location.fieldIndex == 7
                    }
                    let key = { (issue: ValidationIssue) in "\(issue.code.number)@\(issue.location.pathDescription)" }
                    #expect(formatAtPID7, "\(malformed), \(version), \(locale): the input draws its format finding")
                    #expect(Set(after.map(key)).isSubset(of: Set(before.map(key))), "\(malformed), \(version), \(locale)")
                }
            }
        }
    }

    @Test("The HL7 null is kept in every date field")
    func nullDateKept() throws {
        let input = try Parser().parse(Self.everyDateField("\"\""))
        for anonymiser in [Anonymiser(key: 7), Anonymiser(legacySalt: 41)] {
            let out = try Parser().parse(anonymiser.anonymise(input).serialize())
            for path in Self.dateFields { #expect(out[path] == "\"\"", "\(path)") }
        }
    }

    @Test("No synthetic value depends on Swift's per-process hashing")
    func noProcessHashing() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/HL7v2Kit/Anonymiser")
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let source = try String(contentsOf: url, encoding: .utf8)
            #expect(!source.contains("Hasher") && !source.contains("hashValue"), "\(url.lastPathComponent)")
        }
    }
}
