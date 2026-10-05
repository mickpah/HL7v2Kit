// TestWires.swift
// Shared canonical wire builders (R8 — the two headers below appeared
// verbatim 70+ times across the suites). Use these when the MSH content
// is NOT what's under test; suites exercising MSH itself (character
// encoding, multi-version detection, AU MSH-12/17/19 rules, batch
// envelopes) keep their headers inline by design.

enum TestWires {
    /// The canonical ADT^A01 v2.5.1 header.
    static let adtMSH = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01^ADT_A01|MSG00001|P|2.5.1\r"

    /// The canonical ORU^R01 v2.5.1 header (LAB-sender twin).
    static let oruMSH = "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01^ORU_R01|MSG00001|P|2.5.1\r"

    /// Canonical ADT^A01 wire: header + the given segment lines (each
    /// gains its `\r` terminator).
    static func adt(_ segments: String...) -> String {
        adtMSH + segments.map { $0 + "\r" }.joined()
    }

    /// Canonical ORU^R01 wire: header + the given segment lines.
    static func oru(_ segments: String...) -> String {
        oruMSH + segments.map { $0 + "\r" }.joined()
    }

    /// MSH header for any message type and version. The P4 condition
    /// suites vary both, so neither canonical header above fits.
    static func msh(_ messageType: String, _ version: String) -> String {
        "MSH|^~\\&|SND|FAC|RCV|FAC|20260930120000||\(messageType)|MSG1|P|\(version)\r"
    }

    /// One segment line with the given 1-based field values; unlisted
    /// positions up to the highest listed one are empty. Removes the
    /// pipe-counting that the long positional wires need.
    static func segment(_ id: String, _ fields: [Int: String]) -> String {
        let last = fields.keys.max() ?? 0
        let values = last == 0 ? [] : (1...last).map { fields[$0] ?? "" }
        return ([id] + values).joined(separator: "|")
    }

    /// Header for `messageType` / `version` plus the given segment lines.
    static func wire(_ messageType: String, _ version: String, _ segments: String...) -> String {
        msh(messageType, version) + segments.map { $0 + "\r" }.joined()
    }
}
