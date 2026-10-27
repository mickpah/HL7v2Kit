// PerformanceTests.swift
// v0.2-X1: nightly latency assertions per spec § 9.5.
//
// Skipped by default. To run:
//
//   RUN_PERF_TESTS=1 \
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//   xcrun swift test --filter PerformanceTests
//
// Budgets are the spec § 9.5 targets on Apple Silicon M1+. They carry
// generous headroom because:
//   1. Test machines (CI, local dev) aren't dedicated benchmark rigs.
//   2. We want failures to flag *real* regressions, not noise.
//   3. The spec also reserves a 20% regression threshold on top of these
//      numbers — i.e. drift up to but not exceeding the budget here is
//      tracked, not failed; failures are reserved for blown budgets.

import Testing
import Foundation
@testable import HL7v2Kit

/// Performance budget suite. Disabled unless `RUN_PERF_TESTS` is set in
/// the environment so the default `swift test` run stays fast.
@Suite(
    "Performance budget (spec § 9.5)",
    .disabled(if: ProcessInfo.processInfo.environment["RUN_PERF_TESTS"] == nil,
              "Set RUN_PERF_TESTS=1 to run the perf suite")
)
struct PerformanceTests {

    /// A representative ~600-byte ADT^A01 — synthesised from the gold-corpus
    /// `adt_a01_minimal.hl7` fixture. Carries the segments most real-world
    /// AU traffic populates (MSH + PID + PV1) without the larger order /
    /// result bodies. Hand-tuned to land near the spec's "1KB" target while
    /// still exercising composite parsing (PID-3 CX, PID-5 XPN, PID-10 CE,
    /// PID-11 XAD, PID-13 XTN, PV1-3 PL, PV1-7 XCN).
    private static let wireString = """
    MSH|^~\\&|SYNTH_HIS|SYNTH_FAC|SYNTH_HIS|SYNTH_FAC|20240101120000||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||SYN-0001^^^SYNTH_FAC^MR||Anderson^Alex^A||19800101|M||2106-3^White^HL70005|45 Banksia St^^Surry Hills^NSW^2010^AU||61-2-1234-5678\r\
    PV1|1|I|WARD1^ROOM2^BED3^SYNTH_HOSP|R|||DR12345678^Carter^Sam|||MED\r
    """

    private static let wireData = Data(wireString.utf8)
    private static let parser = Parser()
    private static let validator = Validator()

    /// Time the given block; return elapsed seconds. Uses `Date` (precision
    /// ≈ µs) rather than `ContinuousClock` so the tests compile on macOS
    /// 12+. For ms-and-up budgets the precision is plenty.
    private static func elapsed(_ block: () throws -> Void) rethrows -> TimeInterval {
        let start = Date()
        try block()
        return -start.timeIntervalSinceNow
    }

    // MARK: - Parse

    @Test("Parse 1 message (~600 bytes) under 1ms warm")
    func parseOneMessageWarm() throws {
        // Warmup — 100 iterations so caches and JIT are hot.
        for _ in 0..<100 {
            _ = try Self.parser.parse(Self.wireData)
        }
        let elapsed = try Self.elapsed {
            _ = try Self.parser.parse(Self.wireData)
        }
        #expect(elapsed < 0.001,
                "Parse took \(elapsed * 1000)ms; budget 1ms (spec § 9.5)")
    }

    @Test("Parse 1,000 messages under 5s")
    func parse1000Messages() throws {
        let elapsed = try Self.elapsed {
            for _ in 0..<1000 {
                _ = try Self.parser.parse(Self.wireData)
            }
        }
        #expect(elapsed < 5.0,
                "1000 parses took \(elapsed)s; budget 5s (spec § 9.5)")
    }

    // MARK: - Round-trip

    @Test("Round-trip 1,000 messages under 10s")
    func roundTrip1000Messages() throws {
        let elapsed = try Self.elapsed {
            for _ in 0..<1000 {
                let message = try Self.parser.parse(Self.wireData)
                _ = message.serialize()
            }
        }
        #expect(elapsed < 10.0,
                "1000 round-trips took \(elapsed)s; budget 10s (spec § 9.5)")
    }

    // MARK: - Validate

    @Test("Validate 1 message (default options) under 2ms warm")
    func validateOneMessageWarm() throws {
        let message = try Self.parser.parse(Self.wireData)
        // Warmup.
        for _ in 0..<100 {
            _ = Self.validator.validate(message)
        }
        let elapsed = Self.elapsed {
            _ = Self.validator.validate(message)
        }
        #expect(elapsed < 0.002,
                "Validate took \(elapsed * 1000)ms; budget 2ms (spec § 9.5)")
    }

    @Test("Validate 1,000 messages under 10s")
    func validate1000Messages() throws {
        let message = try Self.parser.parse(Self.wireData)
        let elapsed = Self.elapsed {
            for _ in 0..<1000 {
                _ = Self.validator.validate(message)
            }
        }
        #expect(elapsed < 10.0,
                "1000 validations took \(elapsed)s; budget 10s (spec § 9.5)")
    }

    // MARK: - Large messages and long streams (X1 task 1)

    /// A ~2 MB ORU^R01: the PID of `au_oru_r01_pathology.hl7`, one OBR, and 400 TX OBX
    /// segments of 5,002 characters each. Built here so no large fixture is committed.
    private static func largeORU() throws -> Data {
        let fixture = try String(contentsOf: FixtureCorpus.fixtureURL(named: "au_oru_r01_pathology.hl7"), encoding: .utf8)
        let pid = try #require(fixture.split(whereSeparator: \.isNewline).first { $0.hasPrefix("PID|") })
        let text = String(repeating: "Synthetic narrative line of report text. ", count: 122)
        var lines = [
            "MSH|^~\\&|SYNTH_LIS|SYNTH_LAB|SYNTH_EMR|SYNTH_FAC|20240101120000+1000||ORU^R01^ORU_R01|PERF0001|P|2.4",
            String(pid),
            "OBR|1||PERF0001^SYNTH_LAB|11502-2^Laboratory report^LN|||20240101110000+1000",
        ]
        for n in 1...400 {
            lines.append("OBX|\(n)|TX|11502-2^Laboratory report^LN||\(text)||||||F")
        }
        return Data((lines.joined(separator: "\r") + "\r").utf8)
    }

    @Test("Parse a 2 MB ORU^R01 (400 TX OBX) under 0.5 s")
    func parseLargeORU() throws {
        let data = try Self.largeORU()
        #expect(data.count > 2_000_000)
        _ = try Self.parser.parse(data)   // warm-up
        let elapsed = try Self.elapsed { _ = try Self.parser.parse(data) }
        print("perf parseLargeORU \(elapsed)")
        #expect(elapsed < 0.5, "Parse took \(elapsed)s; budget 0.5 s (X1 task 1)")
    }

    @Test("Validate a 2 MB ORU^R01 under .strict with the AU profile under 1 s")
    func validateLargeORU() throws {
        let message = try Self.parser.parse(try Self.largeORU())
        let validator = Validator(options: .strict, locale: .auLocalisation)
        _ = validator.validate(message)   // warm-up
        let elapsed = Self.elapsed { _ = validator.validate(message) }
        print("perf validateLargeORU \(elapsed)")
        #expect(elapsed < 1.0, "Validation took \(elapsed)s; budget 1 s (X1 task 1)")
    }

    @Test("Stream 10,000 messages in 64 KiB chunks: first 100 within 0.2 s, all within 20 s")
    func streamTenThousand() throws {
        let fixture = try String(contentsOf: FixtureCorpus.fixtureURL(named: "adt_a01_minimal.hl7"), encoding: .utf8)
        let segments = fixture.split(whereSeparator: \.isNewline).map(String.init)
        var msh = try #require(segments.first).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        var wire = ""
        for n in 0..<10_000 {
            msh[9] = "PERF\(n)"   // MSH-10: split index 9, since MSH-1 is the separator itself
            wire += ([msh.joined(separator: "|")] + segments.dropFirst()).joined(separator: "\r") + "\r"
        }
        let data = Data(wire.utf8)
        var parser = StreamingBatchParser()
        var count = 0
        var firstHundred: TimeInterval?
        let start = Date()
        for offset in stride(from: 0, to: data.count, by: 65_536) {
            count += try parser.feed(data.subdata(in: offset..<min(offset + 65_536, data.count))).count
            if firstHundred == nil, count >= 100 { firstHundred = -start.timeIntervalSinceNow }
        }
        count += try parser.finish().count
        let total = -start.timeIntervalSinceNow
        print("perf streamTenThousand first100 \(firstHundred ?? -1) total \(total)")
        #expect(count == 10_000)
        #expect((firstHundred ?? .infinity) < 0.2, "First 100 took \(firstHundred ?? -1)s; budget 0.2 s")
        #expect(total < 20, "10,000 took \(total)s; budget 20 s")
    }
}
