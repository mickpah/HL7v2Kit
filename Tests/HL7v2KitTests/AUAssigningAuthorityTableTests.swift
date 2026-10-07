// AUAssigningAuthorityTableTests.swift
// P12 S2-2 item 9: HL7au:00104.7.2.1 under a caller assertion. AU
// ADRM-2021.1 Appendix 5 p 473 (Senders, Referrals): "PRD-7 <type of ID
// number (IS)> must be valued from User-defined Table 0363 - Assigning
// Authority (see page 310)." The PRD-7 prose (p 334): "Table 0363 values may
// be extended to allow for secure messaging vendor assigning authorities."
// Which vendor authorities a site has agreed is not on the wire, so the
// caller declares them (`localTableExtensions["0363"]`) and asserts the
// table closed (`auAssigningAuthorityTable`); without the assertion the
// point stays silent, as the ADRM's own vendor rows (Medical-Objects, Argus)
// would otherwise fire.

import Testing
@testable import HL7v2Kit

@Suite("AU PRD-7.2 in Table 0363 under the caller's assertion (HL7au:00104.7.2.1)")
struct AUAssigningAuthorityTableTests {
    private func findings(identifiers: String, asserted: Bool, extensions: Set<String> = ["Medical-Objects"],
                          messageType: String = "REF^I12") throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|GP|FAC|SPEC|FAC|||\(messageType)|MSG00001|P|2.4\r"
            + "PRD|AP^Authoring Provider^HL70286|Doe^John\r"
            + "PRD|IR^Intended Recipient^HL70286|Smith^Alice|||||\(identifiers)\r"
            + "PID|1||X^^^F^MR\r"
            + "OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|REFER^Referral^L\r"
            + "OBX|1|ED|PDF^Display format in PDF^AUSPDI||src^application^pdf^Base64^AAAA|||||F\r"
        var options = ValidationOptions()
        options.auAssigningAuthorityTable = asserted
        options.localTableExtensions = ["0363": extensions]
        let message = try Parser(locale: .auLocalisation).parse(wire)
        return Validator(options: options, locale: .auLocalisation).validate(message).issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code {
                return rule.hasPrefix("HL7au:00104.7.2.1")
            }
            return false
        }
    }

    @Test("Asserted: an undeclared vendor authority fires at PRD-7.2")
    func undeclaredAuthorityFires() throws {
        let issues = try findings(identifiers: "X0012345^Argus^VDI", asserted: true)
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(issues.first?.location == IssueLocation(segmentID: "PRD", segmentIndex: 2, fieldIndex: 7, componentIndex: 2))
    }

    @Test("Asserted: a declared vendor authority and a printed one are silent")
    func declaredAndPrintedSilent() throws {
        #expect(try findings(identifiers: "JD455600041^Medical-Objects^VDI", asserted: true).isEmpty)
        #expect(try findings(identifiers: "049960CT^AUSHICPR^UPIN~0000000000001001^AUSHIC^NOI", asserted: true).isEmpty)
    }

    @Test("Asserted: each repetition is checked")
    func eachRepetition() throws {
        let issues = try findings(identifiers: "049960CT^AUSHICPR^UPIN~X0012345^Argus^VDI", asserted: true)
        #expect(issues.count == 1, "got \(issues.map(\.message))")
    }

    @Test("Not asserted: an undeclared vendor authority is silent")
    func unassertedSilent() throws {
        #expect(try findings(identifiers: "X0012345^Argus^VDI", asserted: false, extensions: []).isEmpty)
    }

    @Test("Asserted: outside Referrals the point does not apply")
    func outsideReferralsSilent() throws {
        #expect(try findings(identifiers: "X0012345^Argus^VDI", asserted: true, messageType: "ORU^R01").isEmpty)
    }
}
