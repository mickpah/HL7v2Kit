// AUPRDVendorIdentifierTests.swift
// P12 S2-2 item 8: HL7au:00104.7.1.4 narrowed to the vendor authorities.
// AU ADRM-2021.1 p 334 (PRD-7): "Table 0363 values may be extended to allow
// for secure messaging vendor assigning authorities." and "Secure messaging
// vendor allocated identifiers must use "VDI" as the value for <other
// qualifying info (ST)>." The point (Appendix 5 p 473): "For a PRD-7 <ID
// number (ST)> the correct matching <type of ID number (IS)> and <other
// qualifying info (ST)> must be used as per table". A PRD-7.2 outside the six
// printed Table 0363 values (p 310) is a vendor authority, so PRD-7.3 = VDI.

import Testing
@testable import HL7v2Kit

@Suite("AU PRD-7 vendor authority qualifier (HL7au:00104.7.1.4)")
struct AUPRDVendorIdentifierTests {
    private func findings(identifiers: String, messageType: String = "REF^I12") throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|GP|FAC|SPEC|FAC|||\(messageType)|MSG00001|P|2.4\r"
            + "PRD|AP^Authoring Provider^HL70286|Doe^John\r"
            + "PRD|IR^Intended Recipient^HL70286|Smith^Alice|||||\(identifiers)\r"
            + "PID|1||X^^^F^MR\r"
            + "OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|REFER^Referral^L\r"
            + "OBX|1|ED|PDF^Display format in PDF^AUSPDI||src^application^pdf^Base64^AAAA|||||F\r"
        let message = try Parser(locale: .auLocalisation).parse(wire)
        return Validator(locale: .auLocalisation).validate(message).issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code {
                return rule.hasPrefix("HL7au:00104.7.1.4")
            }
            return false
        }
    }

    @Test("The ADRM's own vendor rows are silent")
    func printedVendorRowsSilent() throws {
        #expect(try findings(identifiers: "JD455600041^Medical-Objects^VDI").isEmpty)
        #expect(try findings(identifiers: "X0012345^Argus^VDI").isEmpty)
    }

    @Test("A vendor authority with a qualifier other than VDI fires at PRD-7.3")
    func vendorWithoutVDIFires() throws {
        let issues = try findings(identifiers: "JD455600041^Medical-Objects^UPIN")
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(issues.first?.location == IssueLocation(segmentID: "PRD", segmentIndex: 2, fieldIndex: 7, componentIndex: 3))
    }

    @Test("Each repetition pairs its own authority and qualifier")
    func perRepetition() throws {
        let issues = try findings(identifiers: "049960CT^AUSHICPR^UPIN~JD455600041^Medical-Objects^NPIO")
        #expect(issues.count == 1, "got \(issues.map(\.message))")
    }

    @Test("Printed 0363 authorities with no printed pair skip")
    func unpairedPrintedAuthoritiesSkip() throws {
        for authority in ["AUSDVA", "AUSNATA", "AUSLINK", "IHI"] {
            #expect(try findings(identifiers: "12345^\(authority)^NPI").isEmpty, "\(authority)")
        }
    }

    @Test("The printed pairs still hold")
    func printedPairsHold() throws {
        #expect(try findings(identifiers: "049960CT^AUSHICPR^UPIN").isEmpty)
        #expect(try findings(identifiers: "8003621566684455^AUSHIC^NOI").isEmpty)
        #expect(try findings(identifiers: "049960CT^AUSHICPR^VDI").count == 1)
    }

    @Test("An empty authority or qualifier skips")
    func emptySkips() throws {
        #expect(try findings(identifiers: "JD455600041^^UPIN").isEmpty)
        #expect(try findings(identifiers: "JD455600041^Medical-Objects").isEmpty)
    }
}
