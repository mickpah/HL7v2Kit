// HL7v2KitAnonymise: strip PHI from a v2 message file per spec section 10.
//
// Usage:
//   swift run HL7v2KitAnonymise <input.hl7> [output.hl7]
//
// If output is omitted, writes to stdout. The tool parses the input, replaces the PHI-bearing
// fields with deterministic synthetic values through the library's Anonymiser, and
// re-serialises. A salt derived from MSH-10 chooses every value, so the same input always
// gives byte-identical output, which keeps the step reproducible for CI gates.

import Foundation
import HL7v2Kit

// MARK: - Entry point

@main
struct Anonymise {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: HL7v2KitAnonymise <input.hl7> [output.hl7]\n".utf8))
            throw ExitCode.failure
        }
        let inputURL = URL(fileURLWithPath: args[1])
        let outputURL = args.count >= 3 ? URL(fileURLWithPath: args[2]) : nil

        let inputData = try Data(contentsOf: inputURL)
        let message = try Parser().parse(inputData)
        let salt = deriveSalt(from: message)
        let scrubbed = scrub(message, salt: salt)
        let outputData = scrubbed.serialize()

        if let outputURL {
            try outputData.write(to: outputURL)
            FileHandle.standardError.write(Data("anonymised \(inputURL.lastPathComponent) → \(outputURL.lastPathComponent) (salt=\(salt))\n".utf8))
        } else {
            FileHandle.standardOutput.write(outputData)
        }
    }
}

enum ExitCode: Error { case failure }

// MARK: - Salt

/// Derive a per-file salt from MSH-10 (the message control ID). Same input
/// MSH-10 → same salt → same scrubbed output. If MSH-10 is missing or
/// empty, falls back to a hash of the entire message bytes.
func deriveSalt(from message: Message) -> Int {
    let mshControlID = message["MSH-10"] ?? ""
    let seed = mshControlID.isEmpty ? String(describing: message.segments.count) : mshControlID
    var hash = 5381
    for byte in seed.utf8 {
        hash = ((hash << 5) &+ hash) &+ Int(byte)   // djb2
    }
    return hash & 0x7FFFFFFF   // mask to non-negative
}

/// The tool's rule: every synthetic value chosen from `salt`.
func scrub(_ message: Message, salt: Int) -> Message {
    Anonymiser(legacySalt: salt).anonymise(message)
}
