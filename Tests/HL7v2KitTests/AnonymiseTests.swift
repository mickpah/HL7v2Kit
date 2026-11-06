// AnonymiseTests.swift
// The anonymiser is the only approved path for real-world-derived fixtures
// (Tests/Fixtures/README.md). A synthetic message holds a marker in every
// field a scrubbing rule covers; after scrubbing, no marker may survive.

import Foundation
import Testing
import HL7v2Kit
@testable import HL7v2KitAnonymise

@Suite("Anonymiser")
struct AnonymiseTests {
    /// Every field a scrubbing rule covers, as `SEG-n`.
    static let covered = [
        "MSH-3", "MSH-4", "MSH-5", "MSH-6",
        "PID-2", "PID-3", "PID-4", "PID-5", "PID-6", "PID-9", "PID-11", "PID-13", "PID-14",
        "PID-18", "PID-19", "PID-20",
        "PD1-4",
        "NK1-2", "NK1-4", "NK1-5", "NK1-6",
        "PV1-7", "PV1-8", "PV1-9", "PV1-17", "PV1-52",
        "IN1-16", "IN1-19",
        "ORC-10", "ORC-11", "ORC-12",
        "OBR-10", "OBR-16", "OBR-28", "OBR-32", "OBR-33", "OBR-34", "OBR-35",
        "OBX-5", "OBX-16",
        "NTE-3",
        "PID-21", "PID-23", "PID-40",
        "PD1-10",
        "NK1-12", "NK1-26", "NK1-30", "NK1-31", "NK1-32", "NK1-33", "NK1-37", "NK1-38", "NK1-40", "NK1-41",
        "IN1-36", "IN1-44", "IN1-49", "IN1-52",
        "GT1-2", "GT1-3", "GT1-4", "GT1-5", "GT1-6", "GT1-7", "GT1-12", "GT1-16", "GT1-17", "GT1-18",
        "GT1-19", "GT1-29", "GT1-42", "GT1-45", "GT1-46", "GT1-56",
    ]

    /// The value a covered field holds before scrubbing. Each is unique and none
    /// sits inside another (`ORIGPID2X` is not in `ORIGPID20X`).
    static func marker(_ field: String) -> String {
        "ORIG" + field.replacingOccurrences(of: "-", with: "") + "X"
    }

    /// One segment: a marker in each of its covered fields, `extra` values at
    /// their field numbers, every other field empty.
    static func segment(_ id: String, _ extra: [Int: String] = [:]) -> String {
        var values = extra
        for field in covered where field.hasPrefix(id + "-") {
            values[Int(field.dropFirst(id.count + 1))!] = marker(field)
        }
        let last = values.keys.max() ?? 0
        return ([id] + (1...last).map { values[$0] ?? "" }).joined(separator: "|")
    }

    static let wire = [
        "MSH|^~\\&|\(marker("MSH-3"))|\(marker("MSH-4"))|\(marker("MSH-5"))|\(marker("MSH-6"))|20240101120000||ORU^R01|CTRL0001|P|2.4",
        segment("PID", [1: "1", 7: "19800615", 29: "20200101"]),
        segment("PD1"),
        segment("NK1", [1: "1", 16: "19500101"]),
        segment("PV1", [1: "1", 2: "O"]),
        segment("IN1", [1: "1", 18: "19700101"]),
        segment("GT1", [1: "1", 8: "19700101", 24: "20200101"]),
        segment("ORC", [1: "NW"]),
        segment("OBR", [1: "1"]),
        segment("OBX", [1: "1", 2: "TX"]),
        segment("NTE", [1: "1"]),
    ].joined(separator: "\r") + "\r"

    static func scrubbed(_ wire: String) throws -> Message {
        let message = try Parser().parse(wire)
        return scrub(message, salt: deriveSalt(from: message))
    }

    @Test("Every covered field loses its original value", arguments: AnonymiseTests.covered)
    func coveredFieldScrubbed(_ field: String) throws {
        #expect(Self.wire.contains(Self.marker(field)))
        let out = String(decoding: try Self.scrubbed(Self.wire).serialize(), as: UTF8.self)
        #expect(!out.contains(Self.marker(field)))
    }

    @Test("A numeric identifier becomes different digits of the same length")
    func numericIdentifierKeepsItsShape() throws {
        let wire = Self.wire.replacingOccurrences(of: Self.marker("PID-3"), with: "1234567")
        let id = try #require(try Self.scrubbed(wire)["PID-3.1"])
        #expect(id.count == 7)
        let allDigits = id.allSatisfy(\.isNumber)
        #expect(allDigits)
        #expect(id != "1234567")
    }

    @Test("A date of birth moves by one to four whole weeks, never by zero")
    func dateOfBirthMovesByWholeWeeks() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        func day(_ yyyymmdd: String) -> Date? {
            let digits = Array(yyyymmdd.prefix(8))
            guard digits.count == 8,
                  let year = Int(String(digits[0..<4])),
                  let month = Int(String(digits[4..<6])),
                  let day = Int(String(digits[6..<8])) else { return nil }
            return utc.date(from: DateComponents(year: year, month: month, day: day))
        }
        let original = try #require(day("19800615"))
        for salt in [0, 1, 2, 3, 4, 5, 6, 7, 30, 1_234_567, 0x7FFF_FFFF] {
            let shifted = try #require(day(scrubDOB("19800615", salt: salt)))
            let days = try #require(utc.dateComponents([.day], from: original, to: shifted).day)
            #expect(days != 0 && days % 7 == 0 && abs(days) <= 28, "salt \(salt) moved the date \(days) days")
        }
        let out = try Self.scrubbed(Self.wire)
        #expect(out["PID-7"] != "19800615")
        #expect(out["IN1-18"] != "19700101")
        for (path, original) in [("PID-29", "20200101"), ("NK1-16", "19500101"), ("GT1-8", "19700101"), ("GT1-24", "20200101")] {
            #expect(out[path] != original, "\(path)")
        }
    }

    @Test("A date with a degree-of-precision component is moved too")
    func dateWithPrecisionMoves() throws {
        let wire = Self.wire.replacingOccurrences(of: "|19800615|", with: "|19800615^D|")
        let out = try Self.scrubbed(wire)
        #expect(out["PID-7.1"] != "19800615")
        #expect(out["PID-7.2"] == "D")
    }

    @Test("TS.1's digits decide how it moves; the degree of precision is kept (v2.5.1 2.A.77.2)")
    func precisionComponentKept() throws {
        for (value, kept) in [("198006^L", false), ("1980^Y", true), ("19800615^Y", false), ("1980^D", true)] {
            let out = try Self.scrubbed(Self.wire.replacingOccurrences(of: "|19800615|", with: "|\(value)|"))
            let parts = value.split(separator: "^").map(String.init)
            #expect((out["PID-7.1"] == parts[0]) == kept && out["PID-7.1"]?.count == parts[0].count, "\(value)")
            #expect(out["PID-7.2"] == parts[1], "\(value)")
        }
    }

    @Test("A month value moves by as many whole months as a day moves weeks; a year, the null, empty and [REDACTED] are kept")
    func coarseDatesByPrecision() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let format = DateFormatter()
        format.calendar = utc
        format.timeZone = utc.timeZone
        format.dateFormat = "yyyyMMdd"
        let monthIndex = { (yyyymm: String) in Int(yyyymm.prefix(4)).flatMap { y in Int(yyyymm.suffix(2)).map { y * 12 + $0 } } }
        for salt in [0, 1, 2, 3, 4, 5, 6, 7, 30, 1_234_567, 0x7FFF_FFFF] {
            let from = try #require(format.date(from: "19800615"))
            let to = try #require(format.date(from: scrubDOB("19800615", salt: salt)))
            let weeks = try #require(utc.dateComponents([.day], from: from, to: to).day) / 7
            for original in ["198006", "202112", "202101"] {
                let moved = scrubDOB(original, salt: salt)
                let months = try #require(monthIndex(moved)) - (try #require(monthIndex(original)))
                #expect(moved.count == 6 && months == weeks && months != 0, "salt \(salt): \(original) became \(moved)")
            }
            // [REDACTED], what a value that is no date becomes, stays so on a second pass.
            for kept in ["1980", "1980+1000", "\"\"", "", "[REDACTED]"] { #expect(scrubDOB(kept, salt: salt) == kept, "salt \(salt)") }
            for malformed in ["SYNTEXT", "2021XX30", "1980-06-15", "15/06/1980", "UNKNOWNDATE", "20210230", "20210101+10"] {
                #expect(scrubDOB(malformed, salt: salt) == "[REDACTED]", "salt \(salt): \(malformed)")
            }
            // A DTM with a time or an offset moves as its day does, the tail kept.
            for tail in ["1230", "123045", "123045.1234", "+1000", "1230-0500", "123045.1-0000"] {
                #expect(scrubDOB("19800615" + tail, salt: salt) == scrubDOB("19800615", salt: salt) + tail, "salt \(salt)")
            }
        }
    }

    @Test("The same input gives byte-identical output")
    func sameInputSameOutput() throws {
        let first = try Self.scrubbed(Self.wire).serialize()
        let second = try Self.scrubbed(Self.wire).serialize()
        #expect(first == second)
    }

    @Test("The tool returns an exit status instead of trapping (#18)")
    func exitStatus() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("anonymise-exit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let tool = "HL7v2KitAnonymise"
        // The tool's status and the lines it sent to standard error.
        func run(_ args: [String]) -> (status: Int32, lines: [String]) {
            var lines: [String] = []
            let status = Anonymise.run(args, standardError: { lines.append($0) })
            return (status, lines)
        }

        let usage = run([tool])
        #expect(usage.status == 1)
        #expect(usage.lines == ["usage: HL7v2KitAnonymise <input.hl7> [output.hl7]\n"])

        let missing = run([tool, dir.appendingPathComponent("missing.hl7").path])
        #expect(missing.status == 1)
        #expect(missing.lines.count == 1)
        #expect(missing.lines.first?.hasPrefix("HL7v2KitAnonymise: ") == true)

        // Declared ASCII, holding byte E9: the byte parse path refuses it on every host (3.29.0).
        var bad = Data(#"MSH|^~\&|APP|FAC|||20260101||ADT^A01^ADT_A01|CTRL1|P|2.5.1||||||ASCII"#.utf8)
        bad.append(contentsOf: [0x0D] + Array("NTE|1||Caf".utf8) + [0xE9, 0x0D])
        let badURL = dir.appendingPathComponent("bad.hl7")
        try bad.write(to: badURL)
        let refused = run([tool, badURL.path, dir.appendingPathComponent("bad-out.hl7").path])
        #expect(refused.status == 1)
        #expect(refused.lines.count == 1)
        #expect(refused.lines.first?.hasPrefix("HL7v2KitAnonymise: ") == true)

        let oddURL = dir.appendingPathComponent("odd.hl7")
        let oddOut = dir.appendingPathComponent("odd-out.hl7")
        try Data("MSH|^~\\&|LAB|FAC|EMR|FAC|20240101120000||ADT^A01^ADT_A01|CTRL1|P|2.4\rPIDX|1||MRN12345^^^HOSP^MR||MARKERFAM^MARKERGIV\r".utf8)
            .write(to: oddURL)
        let odd = run([tool, oddURL.path, oddOut.path])
        #expect(odd.status == 1)                                                         // fails closed
        #expect(odd.lines == ["HL7v2KitAnonymise: segment ID 'PIDX' is not three characters; not anonymised\n"])
        #expect(!FileManager.default.fileExists(atPath: oddOut.path))

        let goodURL = dir.appendingPathComponent("good.hl7")
        let outURL = dir.appendingPathComponent("good-out.hl7")
        try Data("MSH|^~\\&|LAB|FAC|EMR|FAC|20240101120000||ADT^A01^ADT_A01|CTRL1|P|2.4\rPID|1||MRN12345^^^HOSP^MR||MARKERFAM^MARKERGIV\r".utf8)
            .write(to: goodURL)
        let good = run([tool, goodURL.path, outURL.path])
        #expect(good.status == 0)
        #expect(good.lines.count == 1)
        #expect(good.lines.first?.hasPrefix("anonymised good.hl7 \u{2192} good-out.hl7 (salt=") == true)
        #expect(FileManager.default.fileExists(atPath: outURL.path))
    }
}
