// QuickStart: one HL7 v2 message through HL7v2Kit, end to end.
//
// Run it from the repository root with `swift run QuickStart`. It builds a synthetic
// ORU^R01, parses it, reads three values, validates it twice, checks the round trip and
// builds the acknowledgement. A test (`Tests/HL7v2KitTests/QuickStartExampleTests.swift`)
// runs the same steps against the same message.

import Foundation
import HL7v2Kit

/// A synthetic v2.4 ORU^R01: one patient, one order, one result. Every value is invented;
/// the identifiers use the `SYN-` prefix and the facilities the `SYNTH_` prefix. PID-7 is
/// written with hyphens on purpose, so the validator has something to report.
let segments = [
    #"MSH|^~\&|SYNTH_LAB|SYNTH_PATH|SYNTH_EMR|SYNTH_CLINIC|20260101120000+1000||ORU^R01^ORU_R01|SYN-MSG-0001|P|2.4"#,
    #"PID|1||SYN-000123^^^SYNTH_PATH^MR||Synthetic^Alex^^^^^L||1980-01-01|F|||1 Example Street^^Sydney^NSW^2000^AUS||(02) 5550 1234^PRN^PH"#,
    #"PV1|1|O"#,
    #"OBR|1|SYN-ORD-0001|SYN-FIL-0001|2951-2^Sodium^LN|||20260101100000+1000|||||||||||||||20260101115000+1000||CH|F"#,
    #"OBX|1|NM|2951-2^Sodium^LN||140|mmol/L^mmol/L^UCUM|135-145|N|||F"#,
]

/// HL7 v2 ends every segment with a carriage return.
let wire = Data((segments.joined(separator: "\r") + "\r").utf8)

let message = try Parser().parse(wire)

print("== Read")
// Path lookups work for any field of any segment.
print("PID-5.1 family name: \(message["PID-5.1"] ?? "-")")
print("OBX-5 result value:  \(message["OBX-5"] ?? "-")")
// Typed accessors cover the segments HL7v2Kit generates structs for.
let givenName = message.firstSegment(PID.self)?.patientName?.givenName
print("PID typed given name: \(givenName ?? "-")")

/// Prints each issue under its severity: severity, code, location and message.
func printIssues(of report: ValidationReport) {
    let groups: [(String, [ValidationIssue])] = [
        ("error", report.errors), ("warning", report.warnings), ("info", report.infos),
    ]
    for (severity, issues) in groups where !issues.isEmpty {
        print("  \(severity) (\(issues.count))")
        for issue in issues {
            print("    \(issue.severity) \(issue.code) at \(issue.location.pathDescription): \(issue.message)")
        }
    }
}

/// One line of counts: validity, then issues per severity.
func summary(of report: ValidationReport) -> String {
    "valid: \(report.isValid), \(report.errors.count) error(s), "
        + "\(report.warnings.count) warning(s), \(report.infos.count) info"
}

print("\n== Validate (ValidationOptions.default, international rules)")
let report = Validator(options: .default).validate(message)
print(summary(of: report))
printIssues(of: report)

print("\n== Validate (ValidationOptions.strict, HL7Locale.auLocalisation)")
// The AU profile layers the ADRM-2021 rules over v2.4; strict makes structure findings errors.
let auReport = Validator(options: .strict, locale: .auLocalisation).validate(message)
print(summary(of: auReport))
print("issues: \(report.issues.count) under default, \(auReport.issues.count) here "
    + "(\(auReport.issues.count - report.issues.count) more)")

print("\n== Round trip")
let roundTripped = message.serialize() == wire
print("serialised bytes match the input: \(roundTripped)")

print("\n== Acknowledgement")
// The caller chooses the code; the builder echoes MSH-10 into MSA-2 and swaps the addresses.
let ack = try MessageBuilder.acknowledgment(
    to: message,
    code: .applicationAccept,
    messageControlID: "SYN-ACK-0001",
    dateTime: "20260101120005+1000"
)
let ackText = String(decoding: ack.serialize(), as: UTF8.self)
print(ackText.split(separator: "\r").joined(separator: "\n"))

if !roundTripped {
    FileHandle.standardError.write(Data("round trip failed\n".utf8))
    exit(1)
}
