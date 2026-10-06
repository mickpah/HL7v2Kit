// ComponentDeprecationValidationTests.swift
// S1-2 (register section G): a populated component that its version's component table
// prints `B` ("left in for backward compatibility"), `X` (S1-5) or `W` ("withdrawn") draws
// `componentNotSupported` at `.warning` under `warnDeprecatedFields`, as a populated
// `B`, `X` or `W` field draws `fieldNotSupported`. The optionality legend applies to
// components from v2.5 (v2.8.2 CH02 section 2.5.3.5: "For version 2.5 and higher, the
// optionality ... of data type components are supplied in component tables"); v2.3 to
// v2.4 print no component optionality. A field already flagged is not re-flagged per
// component, and subcomponents are not checked.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Component deprecation")
struct ComponentDeprecationValidationTests {

    func issues(_ wire: String, _ options: ValidationOptions = .default) throws -> [ValidationIssue] {
        try Validator(options: options).validate(Parser().parse(wire)).issues
    }

    func componentIssues(_ wire: String, _ options: ValidationOptions = .default) throws -> [ValidationIssue] {
        try issues(wire, options).filter {
            if case .componentNotSupported = $0.code { return true } else { return false }
        }
    }

    /// An ADT^A01 on `version` with `pid` after `PID|1||123^^^H^MR||` and `pv1` after `PV1|1|I|`.
    func adt(_ version: String, pid: String = "Doe^John", pv1: String = "") -> String {
        "MSH|^~\\&|A|B|C|D|20240101120000||ADT^A01^ADT_A01|M1|P|\(version)\r"
            + "EVN||20240101120000\r"
            + "PID|1||123^^^H^MR||\(pid)\r"
            + "PV1|1|I|\(pv1)\r"
    }

    func at(_ segment: String, _ field: Int, _ component: Int) -> IssueLocation {
        IssueLocation(segmentID: segment, segmentIndex: 1, fieldIndex: field,
                      componentIndex: component, subcomponentIndex: nil)
    }

    @Test("v2.8.2 XCN.7 Degree (W) populated in PV1-7 is reported at the component")
    func withdrawnComponent() throws {
        let found = try componentIssues(adt("2.8.2", pv1: "||||123^Smith^John^^^^MD"))
        try #require(found.count == 1)
        #expect(found[0].code == .componentNotSupported(optionality: "W"))
        #expect(found[0].severity == .warning)
        #expect(found[0].location == at("PV1", 7, 7))
    }

    @Test("v2.8.2 XCN.8 Source Table (B) populated in PV1-7 is reported at the component")
    func backwardCompatibleComponent() throws {
        let found = try componentIssues(adt("2.8.2", pv1: "||||123^Smith^^^^^^SRC"))
        try #require(found.count == 1)
        #expect(found[0].code == .componentNotSupported(optionality: "B"))
        #expect(found[0].severity == .warning)
        #expect(found[0].location == at("PV1", 7, 8))
    }

    @Test("A withdrawn component in a second repetition is reported and names the repetition")
    func secondRepetition() throws {
        let found = try componentIssues(adt("2.8.2", pv1: "||||123^Smith~456^Jones^^^^^MD"))
        try #require(found.count == 1)
        #expect(found[0].location == at("PV1", 7, 7))
        #expect(found[0].message.contains("repetition 2"))
    }

    @Test("Empty B and W components, and populated R, O and C components, draw nothing")
    func emptyAndOtherCodes() throws {
        #expect(try componentIssues(adt("2.8.2", pv1: "||||123^Smith^John^^^^^^^^^^^^^^^^^^^^^^")).isEmpty)
        #expect(try componentIssues(adt("2.8.2", pid: "Doe^John^Q^Jr^Dr", pv1: "||||123^Smith^John^^^^^^ISO")).isEmpty)
    }

    @Test("The HL7 null in a withdrawn component is reported, as for a field")
    func hl7Null() throws {
        let found = try componentIssues(adt("2.8.2", pv1: "||||123^Smith^John^^^^\"\""))
        try #require(found.count == 1)
        #expect(found[0].location == at("PV1", 7, 7))
    }

    @Test("A field already flagged B is not re-flagged per component")
    func flaggedFieldNotWalked() throws {
        // v2.8.2 PV1-9 Consulting Doctor is printed B; XCN.7 inside it is W.
        let all = try issues(adt("2.8.2", pv1: "||||||123^Smith^John^^^^MD"))
        #expect(all.contains { $0.code == .fieldNotSupported && $0.location.fieldIndex == 9 })
        #expect(!all.contains { if case .componentNotSupported = $0.code { true } else { false } })
        // v2.8.2 PID-13 is printed B; XTN.1 inside it is W.
        let pid = try issues(adt("2.8.2", pid: "Doe^John||||||||555-1234"))
        #expect(pid.contains { $0.code == .fieldNotSupported && $0.location.fieldIndex == 13 })
        #expect(!pid.contains { if case .componentNotSupported = $0.code { true } else { false } })
    }

    @Test("v2.5.1 XPN.6 Degree (B) and v2.6 XTN.1 (W) are reported")
    func earlierVersions() throws {
        let v251 = try componentIssues(adt("2.5.1", pid: "Doe^John^^^^PhD"))
        try #require(v251.count == 1)
        #expect(v251[0].code == .componentNotSupported(optionality: "B"))
        #expect(v251[0].location == at("PID", 5, 6))
        let v26 = try componentIssues(adt("2.6", pid: "Doe^John||||||||555-1234"))
        try #require(v26.count == 1)
        #expect(v26[0].code == .componentNotSupported(optionality: "W"))
        #expect(v26[0].location == at("PID", 13, 1))
    }

    @Test("v2.3 to v2.4 print no component optionality and draw nothing", arguments: ["2.3", "2.3.1", "2.4"])
    func preV25(version: String) throws {
        #expect(try componentIssues(adt(version, pid: "Doe^John^^^^PhD", pv1: "||||123^Smith^John^^^^MD")).isEmpty)
    }

    @Test("warnDeprecatedFields off, or the lenient preset, draws nothing")
    func optionOff() throws {
        var options = ValidationOptions.default
        options.warnDeprecatedFields = false
        let wire = adt("2.8.2", pv1: "||||123^Smith^John^^^^MD")
        #expect(try componentIssues(wire, options).isEmpty)
        #expect(try componentIssues(wire, .lenient).isEmpty)
        #expect(try componentIssues(wire, .strict).count == 1)
    }

    @Test("A B subcomponent is not checked (v2.5.1 TS.2 inside XAD.13)")
    func subcomponentNotChecked() throws {
        let wire = adt("2.5.1", pid: "Doe^John||||||1 Main St^^City^^^^^^^^^^20200101&Y")
        #expect(try componentIssues(wire).isEmpty)
    }

    // S1-5: the optionality legend (v2.8.2 CH02 section 2.5.3.5, pp. 9-10) defines `X`
    // ("not used with this trigger event") beside `B` and `W`, and the same legend governs
    // component tables from v2.5. No extracted component table prints `X` today, so the
    // guard is pinned here directly: a component printed `X` is reported as the field is.
    @Test("The guard reports B, W and X and nothing else")
    func guardCodes() {
        #expect(Validator.componentDeprecationState(optionality: "B") == "kept for backward compatibility only (B)")
        #expect(Validator.componentDeprecationState(optionality: "W") == "withdrawn from the standard (W)")
        #expect(Validator.componentDeprecationState(optionality: "X") == "not supported (X)")
        for code in ["", "R", "RE", "O", "C"] {
            #expect(Validator.componentDeprecationState(optionality: code) == nil)
        }
    }
}
