// ParsingTests.swift
// Structural parsing correctness.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Parsing")
struct ParsingTests {

    @Test("Empty input throws .emptyInput")
    func emptyInput() {
        #expect(throws: ParseError.emptyInput) {
            try Parser().parse("")
        }
    }

    @Test("Non-MSH first segment throws .missingMSH")
    func missingMSH() {
        let wire = "PID|1|||SMITH^JOHN\r"
        #expect(throws: ParseError.missingMSH) {
            try Parser().parse(wire)
        }
    }

    @Test("Default encoding characters are recognised")
    func defaultEncoding() throws {
        let wire = "MSH|^~\\&|APP|FAC|||||ADT^A01|MSG1|P|2.5.1\r"
        let m = try Parser().parse(wire)
        #expect(m.encodingCharacters == .default)
    }

    @Test("Version parsed from MSH-12")
    func versionFromMSH12() throws {
        let wire = "MSH|^~\\&|APP|FAC|||||ADT^A01|MSG1|P|2.5.1\r"
        let m = try Parser().parse(wire)
        #expect(m.version == .v2_5_1)
    }

    @Test("All four supported versions parse")
    func allVersions() throws {
        for v in Version.allCases {
            let wire = "MSH|^~\\&|APP|FAC|||||ADT^A01|MSG1|P|\(v.rawValue)\r"
            let m = try Parser().parse(wire)
            #expect(m.version == v, "Version \(v.rawValue) failed to parse")
        }
    }

    @Test("Z-segments parse as UnknownSegment")
    func zSegmentTolerance() throws {
        let wire = """
        MSH|^~\\&|APP|FAC|||||ADT^A01|MSG1|P|2.5.1\r\
        ZAU|1|EXTRA\r
        """
        let m = try Parser().parse(wire)
        #expect(m.segments.count == 2)
        if case .unknown(let z) = m.segments[1] {
            #expect(z.segmentID == "ZAU")
        } else {
            Issue.record("Expected ZAU to be an UnknownSegment")
        }
    }

    @Test("Segment count includes all non-empty lines")
    func segmentCount() throws {
        let wire = """
        MSH|^~\\&|APP|FAC|||||ADT^A01|MSG1|P|2.5.1\r\
        EVN|A01|20200101\r\
        PID|1||12345||SMITH^JOHN\r\
        PV1|1|I\r
        """
        let m = try Parser().parse(wire)
        #expect(m.segments.count == 4)
        #expect(m.segments.map(\.segmentID) == ["MSH", "EVN", "PID", "PV1"])
    }
}
