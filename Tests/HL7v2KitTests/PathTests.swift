// PathTests.swift
// Path string parsing.

import Testing
@testable import HL7v2Kit

@Suite("Path parsing")
struct PathTests {

    @Test("Simple field path: PID-5")
    func simpleField() throws {
        let p = try Path("PID-5")
        #expect(p.segmentID == "PID")
        #expect(p.segmentIndex == nil)
        #expect(p.field == 5)
        #expect(p.repetition == nil)
        #expect(p.component == nil)
        #expect(p.subcomponent == nil)
    }

    @Test("Field + component: PID-5.1")
    func fieldAndComponent() throws {
        let p = try Path("PID-5.1")
        #expect(p.segmentID == "PID")
        #expect(p.field == 5)
        #expect(p.component == 1)
        #expect(p.subcomponent == nil)
    }

    @Test("Full path with subcomponent: PID-5.1.2")
    func fullPath() throws {
        let p = try Path("PID-5.1.2")
        #expect(p.field == 5)
        #expect(p.component == 1)
        #expect(p.subcomponent == 2)
    }

    @Test("Repetition: PID-3~2")
    func repetition() throws {
        let p = try Path("PID-3~2")
        #expect(p.field == 3)
        #expect(p.repetition == 2)
        #expect(p.component == nil)
    }

    @Test("Repetition + component: PID-3~2.4")
    func repetitionAndComponent() throws {
        let p = try Path("PID-3~2.4")
        #expect(p.field == 3)
        #expect(p.repetition == 2)
        #expect(p.component == 4)
    }

    @Test("Segment index: OBX[2]-5")
    func segmentIndex() throws {
        let p = try Path("OBX[2]-5")
        #expect(p.segmentID == "OBX")
        #expect(p.segmentIndex == 2)
        #expect(p.field == 5)
    }

    @Test("Z-segments parse: ZAU-3")
    func zSegmentPath() throws {
        let p = try Path("ZAU-3")
        #expect(p.segmentID == "ZAU")
        #expect(p.field == 3)
    }

    @Test("Malformed paths throw")
    func malformedThrows() {
        #expect(throws: (any Error).self) { try Path("") }
        #expect(throws: (any Error).self) { try Path("PID") }
        #expect(throws: (any Error).self) { try Path("PID-") }
        #expect(throws: (any Error).self) { try Path("PID-5.") }
        #expect(throws: (any Error).self) { try Path("PID-5.1.2.3") }
        #expect(throws: (any Error).self) { try Path("PID[0]-5") }   // segment index must be >= 1
    }

    @Test("Subscript resolves path against message")
    func subscriptResolution() throws {
        let wire = "MSH|^~\\&|APP|FAC|||||ADT^A01|MSG1|P|2.5.1\rPID|1||12345||SMITH^JOHN^A||19700101|M\r"
        let m = try Parser().parse(wire)
        #expect(m["PID-5.1"] == "SMITH")
        #expect(m["PID-5.2"] == "JOHN")
        #expect(m["PID-5.3"] == "A")
        #expect(m["PID-7"] == "19700101")
        #expect(m["PID-8"] == "M")
        #expect(m["MSH-9.1"] == "ADT")
        #expect(m["MSH-9.2"] == "A01")
    }

    @Test("Subscript returns nil for out-of-range or non-existent paths")
    func subscriptNilCases() throws {
        let wire = "MSH|^~\\&|APP|FAC|||||ADT^A01|MSG1|P|2.5.1\rPID|1||12345||SMITH^JOHN\r"
        let m = try Parser().parse(wire)
        #expect(m["PID-99"] == nil)
        #expect(m["XYZ-1"] == nil)
        #expect(m["nonsense"] == nil)
    }

    @Test("P12 S3-2: the subscript reads the requested occurrence of a repeated segment")
    func subscriptOccurrence() throws {
        let wire = "MSH|^~\\&|APP|FAC|||||ORU^R01|MSG1|P|2.5.1\rPID|1\rOBR|1\r"
            + "OBX|1|NM|A||1\rOBX|2|NM|B||2\rNTE|1\rOBX|3|NM|C||3\r"
        let m = try Parser().parse(wire)
        #expect(m["MSH-9.1"] == "ORU")
        #expect(m["OBX-5"] == "1")
        #expect(m["OBX[1]-5"] == "1")
        #expect(m["OBX[2]-5"] == "2")
        #expect(m["OBX[3]-5"] == "3")
        #expect(m["OBX[4]-5"] == nil)
    }
}
