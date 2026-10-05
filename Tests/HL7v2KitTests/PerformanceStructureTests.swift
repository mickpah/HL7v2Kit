// PerformanceStructureTests.swift
// P8b-18: the message-structure check against the spec § 9.5 budget, and
// derived scaling checks for long messages.
//
// Skipped by default, like PerformanceTests. To run (release build, the
// configuration the numbers in CHANGELOG and the register were taken in):
//
//   RUN_PERF_TESTS=1 \
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//   xcrun swift test -c release -Xswiftc -enable-testing --filter PerformanceStructureTests
//
// The spec rows are met in a release build. In a debug build the 1 KB message
// takes about 2.5 ms (P8b-18, best of three: 2.54 ms at `.warning`, 2.43 ms off),
// and took 2.35 ms with the check off (its default then) at 542f5cd, before the
// rollout, so the 2 ms row fails in debug whatever the structure check does.
//
// Each test prints one `PERF <scenario> ...` line so the numbers can be
// compared between commits. The suite is serialised: a timing taken while
// another test runs in parallel is meaningless.
//
// The spec § 9.5 budget is two rows, both for a 1 KB message with default
// options: "Validate 1 message (default options) < 2ms" and "Validate 1,000
// messages < 10s". Only `validateOne` and `validateThousand` test it, on a
// v2.5.1 ADT^A01 of about 1 KB (its byte size is asserted and printed), with
// the structure check at `.warning` (the `.default` preset) and off.
//
// § 9.5 prints no budget for a long message. The long-message tests (a
// 5,000-segment ORU^R01 on v2.5.1 and v2.8.2; the AU REF^I12 with 200 to 800
// ADRM-added segments) are derived scaling checks, not the spec budget: their
// limit is the 1 KB row scaled by byte size, 2 ms per KB (1 KB = 1,024 bytes).

import Testing
import Foundation
@testable import HL7v2Kit

@Suite(
    "Performance: message structures (spec § 9.5 budget and derived scaling checks, P8b-18)",
    .serialized,
    .disabled(if: ProcessInfo.processInfo.environment["RUN_PERF_TESTS"] == nil,
              "Set RUN_PERF_TESTS=1 to run the perf suite")
)
struct PerformanceStructureTests {

    /// A synthetic v2.5.1 ADT^A01 of about 1 KB (the § 9.5 message size) that
    /// the v2.5.1 ADT_A01 structure accepts: 11 segments.
    private static let adt = [
        "MSH|^~\\&|SYNTH_HIS|SYNTH_FAC|SYNTH_LAB|SYNTH_FAC|20240101120000||ADT^A01^ADT_A01|MSG00001|P|2.5.1|||AL|NE|AUS",
        "EVN||20240101120000|||OPER01^Operator^Olive|20240101115500",
        "PID|1||SYN-0001^^^SYNTH_FAC^MR~SYN-0002^^^SYNTH_AUTH^PI||Anderson^Alex^A^^Mx||19800101|M|||"
            + "45 Banksia St^^Surry Hills^NSW^2010^AU^H||^PRN^PH^^61^2^12345678|^WPN^PH^^61^2^87654321|EN|S||ACC-0001",
        "NK1|1|Anderson^Blair|SPO^Spouse^HL70063|45 Banksia St^^Surry Hills^NSW^2010^AU|^PRN^PH^^61^2^12345678||"
            + "EC^Emergency contact^HL70131",
        "PV1|1|I|WARD1^ROOM2^BED3^SYNTH_HOSP|R|||DR12345678^Carter^Sam^^^Dr|DR87654321^Nguyen^Lee^^^Dr||MED||||1|||"
            + "DR12345678^Carter^Sam^^^Dr|IP|VIS-0001|||||||||||||||||||||||||20240101120000",
        "PV2|||CHEST^Chest pain^L|||||20240105",
        "OBX|1|NM|8302-2^Body height^LN||172|cm^centimetre^UCUM|||||F",
        "OBX|2|NM|29463-7^Body weight^LN||70|kg^kilogram^UCUM|||||F",
        "AL1|1|DA|PEN^Penicillin^L|SV|Rash",
        "DG1|1||R07.4^Chest pain, unspecified^I10|||A",
        "GT1|1||Anderson^Alex^A||45 Banksia St^^Surry Hills^NSW^2010^AU|^PRN^PH^^61^2^12345678",
    ].joined(separator: "\r") + "\r"

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

    private static func label(_ severity: IssueSeverity?) -> String { severity.map { "\($0)" } ?? "off" }

    /// The derived scaling limit for a long message (not a spec budget): the
    /// § 9.5 1 KB row scaled by byte size, 2 ms per KB of 1,024 bytes.
    private static func derivedLimit(bytes: Int) -> TimeInterval { Double(bytes) / 1024 * 0.002 }

    /// One `PERF` line for a long message: time, bytes, segments, measured
    /// milliseconds per KB, and the derived limit.
    private static func report(_ scenario: String, seconds: TimeInterval, bytes: Int, segments: Int) {
        let perKB = seconds * 1000 / (Double(bytes) / 1024)
        print("PERF \(scenario) \(String(format: "%.4f", seconds)) s, \(bytes) bytes, \(segments) segments, "
              + "\(String(format: "%.3f", perKB)) ms/KB, derived limit \(String(format: "%.4f", derivedLimit(bytes: bytes))) s")
    }

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

    @Test("The spec § 9.5 message is about 1 KB and the structure accepts it")
    func specMessageShape() throws {
        let bytes = Self.adt.utf8.count
        print("PERF spec-message \(bytes) bytes")
        #expect((900...1100).contains(bytes), "the § 9.5 rows are for a 1 KB message; this one is \(bytes) bytes")
        let message = try Parser().parse(Self.adt)
        #expect(Self.structureFindings(Validator(options: .default).validate(message)).isEmpty)
    }

    @Test("Spec § 9.5: validate 1 message (default options) under 2 ms warm, structure check at .warning and off",
          arguments: [.warning, nil] as [IssueSeverity?])
    func validateOne(severity: IssueSeverity?) throws {
        let message = try Parser().parse(Self.adt)
        let validator = Validator(options: Self.options(severity))
        for _ in 0..<100 { _ = validator.validate(message) }
        let runs = 200
        let total = Self.elapsed { for _ in 0..<runs { _ = validator.validate(message) } }
        let each = total / Double(runs)
        print("PERF validate-1-\(Self.label(severity)) \(String(format: "%.4f", each * 1000)) ms, \(Self.adt.utf8.count) bytes")
        #expect(each < 0.002, "Validate took \(each * 1000) ms; budget 2 ms (spec § 9.5)")
    }

    @Test("Spec § 9.5: validate 1,000 messages under 10 s, structure check at .warning and off",
          arguments: [.warning, nil] as [IssueSeverity?])
    func validateThousand(severity: IssueSeverity?) throws {
        let message = try Parser().parse(Self.adt)
        let validator = Validator(options: Self.options(severity))
        let total = Self.elapsed { for _ in 0..<1000 { _ = validator.validate(message) } }
        print("PERF validate-1000-\(Self.label(severity)) \(String(format: "%.4f", total)) s, \(Self.adt.utf8.count) bytes each")
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

    @Test("Derived scaling check (not a spec budget): AU REF^I12 with 200 to 800 ADRM-added segments",
          arguments: [(50, 50), (100, 100), (200, 200)])
    func auReferralRematch(orders: Int, problems: Int) throws {
        let wire = Self.referral(orders: orders, problems: problems)
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let validator = Validator(options: Self.options(.warning), locale: .auLocalisation)
        let structure = Self.structureFindings(validator.validate(message))
        #expect(structure.isEmpty, "the ADRM structure accepts the message: \(structure.prefix(3).map(\.message))")
        let total = Self.elapsed { _ = validator.validate(message) }
        let bytes = wire.utf8.count
        let count = message.segments.count
        Self.report("au-ref-i12-\(orders * 3 + problems)added", seconds: total, bytes: bytes, segments: count)
        // Known issue, registered: docs/design/permanent-limitations-register.md,
        // section E close-out addendum, row "AU REF^I12 validation time". Measured
        // (release, best of three): 7.9 to 40.3 ms for 200 to 800 added segments,
        // 2.59 to 3.35 ms per KB against the derived 2 ms per KB, and 6.9 to 36.8 ms
        // at 542f5cd, before the rollout. The time is in the AU profile's field-level
        // checks. When it is fixed this known issue stops matching and the test fails.
        withKnownIssue("AU REF^I12 over its derived scaling limit (register section E, AU REF^I12 validation time)") {
            #expect(total < Self.derivedLimit(bytes: bytes),
                    "\(count) segments (\(bytes) bytes) took \(total) s; derived limit \(Self.derivedLimit(bytes: bytes)) s")
        }
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

    @Test("Derived scaling check (not a spec budget): 5,000-segment ORU^R01 on v2.5.1 and v2.8.2, structure check at .warning and off",
          arguments: ["2.5.1", "2.8.2"], [.warning, nil] as [IssueSeverity?])
    func longResultMessage(version: String, severity: IssueSeverity?) throws {
        let validator = Validator(options: Self.options(severity))
        var times: [Int: TimeInterval] = [:]
        var bytes = 0
        for orders in [100, 500] {
            let wire = Self.longResult(version: version, orders: orders)
            let message = try Parser().parse(wire)
            if severity != nil {
                let structure = Self.structureFindings(validator.validate(message))
                #expect(structure.isEmpty, "\(version): \(structure.prefix(3).map(\.message))")
            }
            times[orders] = Self.elapsed { _ = validator.validate(message) }
            bytes = wire.utf8.count
        }
        let count = 500 * 10 + 2
        let long = times[500] ?? 0
        let ratio = long / max(times[100] ?? 0, 1e-9)
        Self.report("oru-\(version)-\(Self.label(severity)) growth-x5 \(String(format: "%.1f", ratio))",
                    seconds: long, bytes: bytes, segments: count)
        #expect(long < Self.derivedLimit(bytes: bytes),
                "\(count) segments (\(bytes) bytes) took \(long) s; derived limit \(Self.derivedLimit(bytes: bytes)) s")
    }
}
