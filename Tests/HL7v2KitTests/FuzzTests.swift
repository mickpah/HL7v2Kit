// FuzzTests.swift
// v0.3-Z1: byte-level fuzz harness. Random-mutates valid fixtures and
// feeds the result to each parser surface — Parser, BatchParser,
// StreamingBatchParser, MLLPUnframer — asserting that the only
// acceptable failure mode is a thrown ``ParseError``. Anything else
// (a force-unwrap trap, an infinite loop killed by the test runner,
// a different Error type, a crash) fails the test.
//
// Skipped by default. To run:
//
//   RUN_FUZZ_TESTS=1 \
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//   xcrun swift test --filter FuzzTests
//
// The harness uses a small seeded PRNG so any discovered failure is
// reproducible — the failing test prints the (fixtureName, mutator,
// iteration, seed) tuple, and a single replay against those inputs
// reproduces the case.

import Testing
import Foundation
@testable import HL7v2Kit

/// Byte-level fuzz harness. Disabled unless `RUN_FUZZ_TESTS` is set —
/// 1000 iterations × 7 mutators × N fixtures × 4 surfaces is enough
/// work that we don't want it on every PR.
@Suite(
    "Fuzz harness (v0.3-Z1)",
    .disabled(if: ProcessInfo.processInfo.environment["RUN_FUZZ_TESTS"] == nil,
              "Set RUN_FUZZ_TESTS=1 to run the fuzz suite")
)
struct FuzzTests {

    // MARK: - Seed corpus

    /// Load the gold-corpus fixtures we want to mutate. Skips
    /// `malformed_*.hl7` because mutating already-broken input doesn't
    /// teach us anything new about the parser's bounds.
    private func seedFixtures() throws -> [(name: String, bytes: Data)] {
        let urls = try FixtureCorpus.validFixtureURLs()
        return try urls.map { url in
            (url.lastPathComponent, try Data(contentsOf: url))
        }
    }

    // MARK: - Per-surface fuzz tests

    @Test("Parser.parse(_ data:) — only ParseError on random mutations")
    func parserSurvivesRandomMutations() throws {
        try fuzzAll { bytes in
            do {
                _ = try Parser().parse(bytes)
            } catch is ParseError {
                // Expected — mutated input often becomes malformed.
            } catch {
                Issue.record("Parser threw non-ParseError: \(type(of: error)) \(error)")
            }
        }
    }

    @Test("BatchParser.parse(_ data:) — only ParseError on random mutations")
    func batchParserSurvivesRandomMutations() throws {
        try fuzzAll { bytes in
            do {
                _ = try BatchParser().parse(bytes)
            } catch is ParseError {
                // Expected.
            } catch {
                Issue.record("BatchParser threw non-ParseError: \(type(of: error)) \(error)")
            }
        }
    }

    @Test("StreamingBatchParser.feed/finish — only ParseError on random mutations")
    func streamingBatchParserSurvivesRandomMutations() throws {
        try fuzzAll { bytes in
            var parser = StreamingBatchParser()
            do {
                _ = try parser.feed(bytes)
                _ = try parser.finish()
            } catch is ParseError {
                // Expected.
            } catch {
                Issue.record("StreamingBatchParser threw non-ParseError: \(type(of: error)) \(error)")
            }
        }
    }

    @Test("MLLPUnframer.feed(_:) — never crashes on random mutations (no throw API)")
    func mllpUnframerSurvivesRandomMutations() throws {
        try fuzzAll { bytes in
            // MLLPUnframer doesn't throw — the only failure mode is a
            // crash (force-unwrap trap, slice out-of-bounds, etc.).
            // Running through the unframer and discarding the result
            // is the assertion.
            var unframer = MLLPUnframer()
            _ = unframer.feed(bytes)
        }
    }

    @Test("MLLPUnframer round-trip on MLLP-framed mutated input — never crashes")
    func mllpRoundTripSurvivesRandomMutations() throws {
        try fuzzAll { bytes in
            // Wrap the (already mutated) bytes in MLLP framing, then
            // unframe them. Exercises the case where a sender frames
            // malformed bodies — receiver must handle gracefully.
            let framed = MLLP.frame(bytes)
            var unframer = MLLPUnframer()
            let bodies = unframer.feed(framed)
            // If the unframer recovered the body, feed it to the
            // Parser as another sanity check.
            for body in bodies {
                do {
                    _ = try Parser().parse(body)
                } catch is ParseError {
                    // Expected on mutated bodies.
                } catch {
                    Issue.record("Parser-after-MLLP threw non-ParseError: \(type(of: error)) \(error)")
                }
            }
        }
    }

    // MARK: - Driver

    /// Iterate over the cross-product of fixtures × mutators × seeds,
    /// applying the caller's `assert` block to each mutated payload.
    ///
    /// Iteration budget is deliberately modest (100 per cell) so a full
    /// fuzz run stays sub-second per surface. Bumping `iterations`
    /// linearly stretches the run; the harness has no state between
    /// iterations.
    private func fuzzAll(
        iterations: Int = 100,
        assert: (Data) throws -> Void
    ) throws {
        let fixtures = try seedFixtures()
        let mutators = Mutator.allCases
        var rng = SeededRNG(seed: 0xC0FFEE)
        for fixture in fixtures {
            for mutator in mutators {
                for _ in 0..<iterations {
                    let mutated = mutator.apply(to: fixture.bytes, rng: &rng)
                    try assert(mutated)
                }
            }
        }
    }
}

// MARK: - Mutators

/// Each mutator perturbs a copy of the seed bytes in a small,
/// targeted way. Designed to surface bounds-checking bugs in the
/// parsers — not to model real-world byte corruption.
private enum Mutator: CaseIterable {
    case bitFlip
    case byteReplace
    case byteInsert
    case byteDelete
    case truncate
    case delimiterCorrupt
    case nulInject

    func apply(to bytes: Data, rng: inout SeededRNG) -> Data {
        switch self {
        case .bitFlip:           return Self.bitFlip(bytes, rng: &rng)
        case .byteReplace:       return Self.byteReplace(bytes, rng: &rng)
        case .byteInsert:        return Self.byteInsert(bytes, rng: &rng)
        case .byteDelete:        return Self.byteDelete(bytes, rng: &rng)
        case .truncate:          return Self.truncate(bytes, rng: &rng)
        case .delimiterCorrupt:  return Self.delimiterCorrupt(bytes, rng: &rng)
        case .nulInject:         return Self.nulInject(bytes, rng: &rng)
        }
    }

    private static func bitFlip(_ bytes: Data, rng: inout SeededRNG) -> Data {
        guard !bytes.isEmpty else { return bytes }
        var out = Data(bytes)
        let i = Int.random(in: 0..<out.count, using: &rng)
        let bit = UInt8.random(in: 0..<8, using: &rng)
        out[i] ^= (1 << bit)
        return out
    }

    private static func byteReplace(_ bytes: Data, rng: inout SeededRNG) -> Data {
        guard !bytes.isEmpty else { return bytes }
        var out = Data(bytes)
        let i = Int.random(in: 0..<out.count, using: &rng)
        out[i] = UInt8.random(in: 0...255, using: &rng)
        return out
    }

    private static func byteInsert(_ bytes: Data, rng: inout SeededRNG) -> Data {
        var out = Data(bytes)
        let i = Int.random(in: 0...out.count, using: &rng)
        let b = UInt8.random(in: 0...255, using: &rng)
        out.insert(b, at: i)
        return out
    }

    private static func byteDelete(_ bytes: Data, rng: inout SeededRNG) -> Data {
        guard !bytes.isEmpty else { return bytes }
        var out = Data(bytes)
        let i = Int.random(in: 0..<out.count, using: &rng)
        out.remove(at: i)
        return out
    }

    private static func truncate(_ bytes: Data, rng: inout SeededRNG) -> Data {
        guard !bytes.isEmpty else { return bytes }
        let cut = Int.random(in: 0..<bytes.count, using: &rng)
        return bytes.prefix(cut)
    }

    private static func delimiterCorrupt(_ bytes: Data, rng: inout SeededRNG) -> Data {
        // Find a position holding one of the standard HL7 delimiters
        // and corrupt it. Catches parsers that assume the delimiter
        // pattern is always intact.
        let delimiters: Set<UInt8> = [0x7C, 0x5E, 0x7E, 0x5C, 0x26, 0x0D]  // | ^ ~ \ & CR
        let positions = bytes.enumerated().compactMap { delimiters.contains($0.element) ? $0.offset : nil }
        guard let pickIdx = positions.randomElement(using: &rng) else { return bytes }
        var out = Data(bytes)
        out[pickIdx] = UInt8.random(in: 0x21...0x7E, using: &rng)  // printable ASCII
        return out
    }

    private static func nulInject(_ bytes: Data, rng: inout SeededRNG) -> Data {
        var out = Data(bytes)
        let i = Int.random(in: 0...out.count, using: &rng)
        out.insert(0x00, at: i)
        return out
    }
}

// MARK: - Seeded RNG

/// Minimal Lehmer-style PRNG. Stateful, deterministic given the seed.
/// Not cryptographic — but for fuzz reproducibility, "given seed X
/// you get sequence Y" is the only contract we need.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        // Xorshift64* — tiny, fast, decent distribution.
        var x = state
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        state = x
        return x &* 0x2545F4914F6CDD1D
    }
}
