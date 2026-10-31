// PathSyntaxTests.swift
// P00 S2-1: the alternative path syntax puts the repetition in brackets after the field
// (`PID-3[2].1`) and allows `[*]` for every segment occurrence or every repetition. It
// resolves to the same Path values as the native form (`PID-3~2.1`); mixed forms are
// malformed, never guessed.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Alternative path syntax")
struct PathSyntaxTests {
    @Test("The bracketed repetition is the native one", arguments: [
        ("PID-3[2]", "PID-3~2"),
        ("PID-3[2].1", "PID-3~2.1"),
        ("PID-3[2].4.2", "PID-3~2.4.2"),
        ("PID-3[1]", "PID-3~1"),
        ("OBX[2]-5[1]", "OBX[2]-5~1"),
        ("ZAU[3]-2[4].1.1", "ZAU[3]-2~4.1.1"),
    ])
    func equivalentForms(_ alternative: String, _ native: String) throws {
        #expect(try Path(alternative) == Path(native))
    }

    @Test("Mixed, empty, zero, unclosed and unspellable forms are malformed", arguments: [
        "PID-3[2]~1", "PID-3~2[1]", "PID-3~*", "PID-3[0]", "PID-3[]", "PID-3[2",
        "PID-3[-1]", "PID-3[**]", "PID-3[*]~1", "PID[*", "PID[0]-3", "PID-3[2][3]",
    ])
    func rejected(_ input: String) {
        #expect(throws: PathError.self) { try Path(input) }
    }

    @Test("[*] marks every segment occurrence or every repetition")
    func wildcards() throws {
        let path = try Path("OBX[*]-5[*].3")
        #expect(path.segmentWildcard)
        #expect(path.repetitionWildcard)
        #expect(path.segmentIndex == nil)
        #expect(path.repetition == nil)
        #expect(path.component == 3)
        #expect(try Path("PID-3").segmentWildcard == false)
        #expect(try Path("PID-3").repetitionWildcard == false)
        #expect(try Path("PID-3[*]") != Path("PID-3"))
        #expect(Path(segmentID: "PID", field: 3).repetitionWildcard == false)
    }

    @Test("description writes the native form and reads back", arguments: [
        "PID-5", "PID-5.1", "PID-5.1.2", "PID-3~2.4", "OBX[2]-5", "OBX[*]-5", "PID-3[*].1", "OBX[*]-5[*].3.1",
    ])
    func descriptionRoundTrips(_ input: String) throws {
        let path = try Path(input)
        #expect(try Path(path.description) == path)
    }

    @Test("The alternative form is described in the native one; a repetition wildcard keeps its brackets")
    func alternativeDescribedNatively() throws {
        #expect(try Path("PID-3[2].1").description == "PID-3~2.1")
        #expect(try Path("OBX[2]-5[*].3").description == "OBX[2]-5[*].3")
        #expect(try Path("PID-5").description == "PID-5")
    }

    static let wire = "MSH|^~\\&|APP|FAC|||20260101||ORU^R01|C1|P|2.5.1\r"
        + "PID|1||A1~B2~C3\rOBX|1|NM|X||1\rOBX|2|NM|Y||2~3\rNTE|1\rOBX|3|NM|Z||4\r"

    @Test("values(at:) reads every occurrence and repetition, in document order")
    func valuesAt() throws {
        let m = try Parser().parse(Self.wire)
        #expect(m.values(at: try Path("OBX[*]-5")) == ["1", "2", "4"])
        #expect(m.values(at: try Path("OBX[*]-5[*]")) == ["1", "2", "3", "4"])
        #expect(m.values(at: try Path("OBX[2]-5[*]")) == ["2", "3"])
        #expect(m.values(at: try Path("PID-3[*]")) == ["A1", "B2", "C3"])
        #expect(m.values(at: try Path("PID-3[2]")) == ["B2"])
        #expect(m.values(at: try Path("PID-3~2")) == ["B2"])
        #expect(m.values(at: try Path("OBX[4]-5")).isEmpty)
        #expect(m.values(at: try Path("ZZZ[*]-1")).isEmpty)
    }

    @Test("The subscript reads the alternative form and returns nil for a wildcard")
    func subscriptForms() throws {
        let m = try Parser().parse(Self.wire)
        #expect(m["PID-3[2]"] == "B2")
        #expect(m["OBX[2]-5[2]"] == "3")
        #expect(m["PID-3[*]"] == nil)
        #expect(m["OBX[*]-5"] == nil)
    }

    @Test("A condition field reference takes no segment index, repetition or wildcard", arguments: [
        "PID-3[2]", "PID-3[*]", "OBX[*]-5", "PID-3~2", "OBX[2]-5",
    ])
    func conditionReferenceRejects(_ referent: String) {
        #expect(ConditionLanguage.fieldRef(referent) == nil)
    }

    @Test("A plain condition field reference still resolves")
    func conditionReferenceAccepts() throws {
        #expect(ConditionLanguage.fieldRef("PID-3.1") == (try Path("PID-3.1")))
    }
}
