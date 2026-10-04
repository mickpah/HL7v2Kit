// PerformanceStructureTests.swift
// P8b-18: the message-structure check against the spec § 9.5 budgets.
//
// Skipped by default, like PerformanceTests. To run:
//
//   RUN_PERF_TESTS=1 \
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//   xcrun swift test --filter PerformanceStructureTests
//
// Each test prints one `PERF <scenario> <value>` line so the numbers can be
// compared between commits. Scenarios: the § 9.5 single-message and
// 1,000-message budgets with the structure check at `.warning` and off; the
// AU profile re-match (P8b-4a) on a REF^I12 carrying a few hundred segments
// the ADRM adds to the base v2.4 structure; and a 5,000-segment ORU^R01 on
// v2.5.1 and v2.8.2, whose group-span lookups (P8b-17) are the quadratic
// candidate. A long message has no § 9.5 row of its own: its budget is the
// single-message budget scaled by segment count (2 ms per 3-segment message).

import Testing
import Foundation
@testable import HL7v2Kit

@Suite(
    "Performance budget: message structures (spec § 9.5, P8b-18)",
    .disabled(if: ProcessInfo.processInfo.environment["RUN_PERF_TESTS"] == nil,
              "Set RUN_PERF_TESTS=1 to run the perf suite")
)
struct PerformanceStructureTests {

    private static let adt = """
    MSH|^~\\&|SYNTH_HIS|SYNTH_FAC|SYNTH_HIS|SYNTH_FAC|20240101120000||ADT^A01^ADT_A01|MSG00001|P|2.5.1\r\
    EVN||20240101120000\r\
    PID|1||SYN-0001^^^SYNTH_FAC^MR||Anderson^Alex^A||19800101|M\r\
    PV1|1|I|WARD1^ROOM2^BED3^SYNTH_HOSP|R|||DR12345678^Carter^Sam|||MED\r
    """

    private static func elapsed(_ block: () throws -> Void) rethrows -> TimeInterval {
        let start = Date()
        try block()
        return -start.timeIntervalSinceNow
    }

    private static func options(_ severity: IssueSeverity?) -> ValidationOptions {
        var options = ValidationOptions.default
        options.messageStructureSeverity = severity
        return options
    }

    /// Scaled budget for a long message: 2 ms per 3 segments (§ 9.5 single message).
    private static func budget(segments: Int) -> TimeInterval { Double(segments) / 3 * 0.002 }

    private static func structureFindings(_ report: ValidationReport) -> [ValidationIssue] {
        report.issues.filter {
            switch $0.code {
            case .messageStructureSegmentMissing, .messageStructureSegmentUnexpected,
                 .messageStructureMismatch, .messageStructureNotModelled: return true
            case .profileConstraintViolation(let rule): return rule == "HL7au:00060.1"
            default: return false
            }
        }
    }

    @Test("Validate 1 message warm under 2 ms, structure check at .warning and off",
          arguments: [.warning, nil] as [IssueSeverity?])
    func validateOne(severity: IssueSeverity?) throws {
        let message = try Parser().parse(Self.adt)
        let validator = Validator(options: Self.options(severity))
        #expect(Self.structureFindings(validator.validate(message)).isEmpty)
        for _ in 0..<100 { _ = validator.validate(message) }
        let runs = 200
        let total = Self.elapsed { for _ in 0..<runs { _ = validator.validate(message) } }
        let each = total / Double(runs)
        print("PERF validate-1-\(severity.map { "\($0)" } ?? "off") \(String(format: "%.4f", each * 1000)) ms")
        #expect(each < 0.002, "Validate took \(each * 1000) ms; budget 2 ms (spec § 9.5)")
    }

    @Test("Validate 1,000 messages under 10 s, structure check at .warning and off",
          arguments: [.warning, nil] as [IssueSeverity?])
    func validateThousand(severity: IssueSeverity?) throws {
        let message = try Parser().parse(Self.adt)
        let validator = Validator(options: Self.options(severity))
        let total = Self.elapsed { for _ in 0..<1000 { _ = validator.validate(message) } }
        print("PERF validate-1000-\(severity.map { "\($0)" } ?? "off") \(String(format: "%.4f", total)) s")
        #expect(total < 10.0, "1000 validations took \(total) s; budget 10 s (spec § 9.5)")
    }

    /// A v2.4 REF^I12 the ADRM-2021 REF_I12 structure (pp 324 to 325) accepts,
    /// with `orders` ORC/RXO/RXR groups and `problems` PRB segments, none of
    /// which the base v2.4 REF_I12 places: each is a dropped base `unexpected`
    /// followed by one exact re-match of the base (P8b-4a).
    static func referral(orders: Int, problems: Int) -> String {
        var segments = [
            "MSH|^~\\&|SYNTH|SYNTH|SYNTH|SYNTH|20240101120000||REF^I12^REF_I12|MSG1|P|2.4",
            "RF1|A",
            "PRD|RP",
            "PID|1||SYN-0001^^^SYNTH_FAC^MR||Anderson^Alex",
            "PV1|1|O",
        ]
        for n in 1...orders { segments += ["ORC|NW|P\(n)", "RXO|DRUG^Name", "RXR|PO"] }
        for n in 1...problems { segments.append("PRB|AD|20240101|P\(n)^Problem") }
        return segments.joined(separator: "\r") + "\r"
    }

    @Test("AU REF^I12 with a few hundred ADRM-added segments: the profile re-match within the scaled budget",
          arguments: [(50, 50), (100, 100), (200, 200)])
    func auReferralRematch(orders: Int, problems: Int) throws {
        let wire = Self.referral(orders: orders, problems: problems)
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let validator = Validator(options: Self.options(.warning), locale: .auLocalisation)
        let structure = Self.structureFindings(validator.validate(message))
        #expect(structure.isEmpty, "the ADRM structure accepts the message: \(structure.prefix(3).map(\.message))")
        let total = Self.elapsed { _ = validator.validate(message) }
        let count = message.segments.count
        print("PERF au-ref-i12-\(count)seg-\(orders * 3 + problems)added \(String(format: "%.4f", total)) s")
        #expect(total < Self.budget(segments: count),
                "\(count) segments took \(total) s; scaled budget \(Self.budget(segments: count)) s")
    }

    /// An ORU^R01 of `orders` ORDER_OBSERVATION groups, each ORC, OBR and
    /// eight OBX: `orders * 10 + 2` segments.
    static func longResult(version: String, orders: Int) -> String {
        var segments = ["MSH|^~\\&|SYNTH|SYNTH|SYNTH|SYNTH|20240101120000||ORU^R01^ORU_R01|MSG1|P|\(version)",
                        "PID|1||SYN-0001^^^SYNTH_FAC^MR||Anderson^Alex"]
        for n in 1...orders {
            segments += ["ORC|RE|P\(n)|F\(n)", "OBR|\(n)|P\(n)|F\(n)|CODE^Name"]
            for k in 1...8 { segments.append("OBX|\(k)|NM|CODE\(k)^Name||5|mg|||||F") }
        }
        return segments.joined(separator: "\r") + "\r"
    }

    @Test("5,000-segment ORU^R01 on v2.5.1 and v2.8.2 within the scaled budget, structure check at .warning and off",
          arguments: ["2.5.1", "2.8.2"], [.warning, nil] as [IssueSeverity?])
    func longResultMessage(version: String, severity: IssueSeverity?) throws {
        let validator = Validator(options: Self.options(severity))
        var times: [Int: TimeInterval] = [:]
        for orders in [100, 500] {
            let message = try Parser().parse(Self.longResult(version: version, orders: orders))
            if severity != nil {
                let structure = Self.structureFindings(validator.validate(message))
                #expect(structure.isEmpty, "\(version): \(structure.prefix(3).map(\.message))")
            }
            times[orders] = Self.elapsed { _ = validator.validate(message) }
        }
        let count = 500 * 10 + 2
        let long = times[500] ?? 0
        let ratio = long / max(times[100] ?? 0, 1e-9)
        print("PERF oru-\(version)-\(count)seg-\(severity.map { "\($0)" } ?? "off") \(String(format: "%.4f", long)) s growth-x5 \(String(format: "%.1f", ratio))")
        #expect(long < Self.budget(segments: count),
                "\(count) segments took \(long) s; scaled budget \(Self.budget(segments: count)) s")
    }
}
