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

    @Test("The same input gives byte-identical output")
    func sameInputSameOutput() throws {
        let first = try Self.scrubbed(Self.wire).serialize()
        let second = try Self.scrubbed(Self.wire).serialize()
        #expect(first == second)
    }
}
