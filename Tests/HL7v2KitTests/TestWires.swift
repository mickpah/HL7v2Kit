// TestWires.swift
// Shared canonical wire builders (R8 — the two headers below appeared
// verbatim 70+ times across the suites). Use these when the MSH content
// is NOT what's under test; suites exercising MSH itself (character
// encoding, multi-version detection, AU MSH-12/17/19 rules, batch
// envelopes) keep their headers inline by design.

enum TestWires {
    /// The canonical ADT^A01 v2.5.1 header.
    static let adtMSH = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r"

    /// The canonical ORU^R01 v2.5.1 header (LAB-sender twin).
    static let oruMSH = "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r"

    /// Canonical ADT^A01 wire: header + the given segment lines (each
    /// gains its `\r` terminator).
    static func adt(_ segments: String...) -> String {
        adtMSH + segments.map { $0 + "\r" }.joined()
    }

    /// Canonical ORU^R01 wire: header + the given segment lines.
    static func oru(_ segments: String...) -> String {
        oruMSH + segments.map { $0 + "\r" }.joined()
    }
}
