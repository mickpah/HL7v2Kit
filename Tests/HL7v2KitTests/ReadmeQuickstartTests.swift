// ReadmeQuickstartTests.swift
//
// This test pins the README's Quickstart code block. If the public API drifts
// (a method renamed, a return type changed, a property moved), this test stops
// compiling — caught at PR time long before a confused user copies the README
// into their project and finds it doesn't work.
//
// When the Quickstart changes in README.md, mirror the change here so the
// test stays a faithful executable copy.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("README quickstart")
struct ReadmeQuickstartTests {

    @Test("README Quickstart code block compiles and runs end-to-end")
    func quickstartCompiles() throws {
        // The Quickstart in README.md uses a placeholder `Data(/* ... */)`.
        // We substitute a synthetic ADT^A01 with a PID-7 DOB so the typed
        // accessor demonstration has something to return.
        let wireString = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M\r
        """
        let wire = Data(wireString.utf8)

        // ─── Quickstart code (mirror README.md) ───────────────────────────

        let message = try Parser().parse(wire)

        // Ad-hoc path access — works for any field.
        let patientFamilyName = message["PID-5.1"]

        // Typed accessors — for the segments HL7v2Kit ships dictionaries for.
        let pid = message.firstSegment(PID.self)
        let dob = pid?.dateTimeOfBirth                     // "19800101"
        let name = pid?.patientName                         // XPN? (typed composite view)
        let familyName = name?.familyName                   // "Smith"

        // MSH-18 character set is detected on parse and re-emitted on serialize.
        // UTF-8 / ASCII / 8859/1 currently supported; unrecognised declarations throw.
        let detectedCharset = message.characterEncoding     // .utf8 / .ascii / .iso8859_1

        // Round-trip — serialised bytes equal the input, including escape
        // sequences (\F\ \S\ \T\ \R\ \E\ \X..\) and the original charset.
        let rebuilt = message.serialize()
        assert(rebuilt == wire)

        // ─── End of mirrored Quickstart ───────────────────────────────────

        // Assertions that pin the example's documented expected values.
        // Drift in these is the README's "//" comments going stale, which
        // is the most likely failure mode after an API change.
        #expect(patientFamilyName == "Smith")
        #expect(dob == "19800101")
        #expect(familyName == "Smith")
        #expect(detectedCharset == .utf8)
        #expect(rebuilt == wire)
    }
}
