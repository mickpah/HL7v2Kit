// PathTests.swift
// Path string parsing.

import Foundation
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
        #expect(throws: (any Error).self) { try Path("PID-") }
        #expect(throws: (any Error).self) { try Path("OBX[3]-") }
        #expect(throws: (any Error).self) { try Path("[3]") }
        #expect(throws: (any Error).self) { try Path("PID-0") }      // no field is written with no field
        #expect(throws: (any Error).self) { try Path("PID.1") }
        #expect(throws: (any Error).self) { try Path("PID-5.") }
        #expect(throws: (any Error).self) { try Path("PID-5.1.2.3") }
        #expect(throws: (any Error).self) { try Path("PID[0]-5") }   // segment index must be >= 1
    }

    @Test("A path may name a segment alone: PID, OBX[3]", arguments: ["PID", "OBX[3]", "ZAU[2]", "OBX[*]"])
    func segmentOnlyPath(_ text: String) throws {
        let path = try Path(text)
        #expect(path.isSegmentOnly)
        #expect(path.field == 0)
        #expect(path.repetition == nil && path.component == nil && path.subcomponent == nil)
        #expect(path.description == text)
        #expect(try Path(path.description) == path)
        #expect(try !Path(text + "-1").isSegmentOnly)
    }

    @Test("The segment-only initialiser builds what the text parses to")
    func segmentOnlyInitialiser() throws {
        #expect(try Path(segmentID: "OBX", segmentIndex: 3) == Path("OBX[3]"))
        #expect(try Path(segmentID: "PID") == Path("PID"))
        #expect(Path(segmentID: "PID").isSegmentOnly)
    }

    @Test("A message resolves a path to its segment, with or without a field")
    func segmentAtPath() throws {
        let msh = "MSH|^~\\&|APP|FAC|||||ORU^R01|MSG1|P|2.5.1\rPID|1||12345\r"
        let two = try Parser().parse(msh + "OBX|1|ST|A||one\rOBX|2|ST|B||two\r")
        let three = try Parser().parse(msh + "OBX|1|ST|A||one\rOBX|2|ST|B||two\rOBX|3|ST|C||three\r")
        #expect(try three.segment(at: Path("OBX[3]"))?.field(1)?.stringValue == "3")
        #expect(try two.segment(at: Path("OBX[3]")) == nil)
        #expect(try three.segment(at: Path("PID"))?.segmentID == "PID")
        #expect(try three.segment(at: Path("OBX"))?.field(1)?.stringValue == "1")       // the first, as a field path reads
        #expect(try three.segment(at: Path("OBX[2]-5.1"))?.field(1)?.stringValue == "2")
        #expect(try three.segment(at: Path("OBX[*]")) == nil)
        #expect(try three.segment(at: Path("ZZZ")) == nil)
        #expect(try three.segment(at: Path("OBX[*]-5")) == nil)
    }

    @Test("A message gives the index in its segments of the segment a path names")
    func indexOfSegmentAtPath() throws {
        let msh = "MSH|^~\\&|APP|FAC|||||ORU^R01|MSG1|P|2.5.1\rPID|1||12345\r"
        let two = try Parser().parse(msh + "OBX|1|ST|A||one\rOBX|2|ST|B||two\r")
        let three = try Parser().parse(msh + "OBX|1|ST|A||one\rOBX|2|ST|B||two\rOBX|3|ST|C||three\r")
        #expect(try three.indexOfSegment(at: Path("OBX[3]")) == 4)
        #expect(try three.indexOfSegment(at: Path("OBX[3]-5.1")) == 4)
        #expect(try three.indexOfSegment(at: Path("OBX")) == 2)
        #expect(try three.indexOfSegment(at: Path("MSH")) == 0)
        #expect(try two.indexOfSegment(at: Path("OBX[3]")) == nil)
        #expect(try three.indexOfSegment(at: Path("OBX[*]")) == nil)
        #expect(try three.indexOfSegment(at: Path("ZZZ")) == nil)
        #expect(three.indexOfSegment(at: Path(segmentID: "OBX", segmentIndex: 0)) == nil)
    }

    @Test("In every fixture the index a path gives holds the segment the path names")
    func indexOfSegmentAgreesWithSegment() throws {
        for url in try FixtureCorpus.validFixtureURLs() {
            let message = try Parser().parse(Data(contentsOf: url))
            var seen: [String: Int] = [:]
            for (index, segment) in message.segments.enumerated() {
                seen[segment.segmentID, default: 0] += 1
                let path = Path(segmentID: segment.segmentID, segmentIndex: seen[segment.segmentID])
                #expect(message.indexOfSegment(at: path) == index, "\(url.lastPathComponent) \(path)")
                #expect(message.segment(at: path) == segment, "\(url.lastPathComponent) \(path)")
            }
        }
    }

    @Test("A segment-only path reads no value and cannot be edited")
    func segmentOnlyPathHoldsNoValue() throws {
        var message = try Parser().parse("MSH|^~\\&|APP|FAC|||||ADT^A01|MSG1|P|2.5.1\rPID|1||12345\r")
        let path = try Path("PID")
        #expect(message[path] == nil)
        #expect(message["PID"] == nil)
        #expect(message.values(at: path).isEmpty)
        #expect(message.values(at: try Path("PID[*]")).isEmpty)
        #expect(throws: MessageEditError.invalidPath(path)) { try message.set("X", at: path) }
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
        #expect(m["OBX[0]-5"] == nil)
    }
}
