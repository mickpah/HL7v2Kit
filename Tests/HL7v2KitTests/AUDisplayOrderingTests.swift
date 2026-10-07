// AUDisplayOrderingTests.swift
// P12 S2-2 item 7: HL7au:000008.1.5. AU ADRM-2021.1 Appendix 5 p 422
// (Senders, Results, Referrals): "The OBX display segment(s) must be the last
// in a set of OBX segments in each OBR/OBX group, with the exception of
// digital signature OBX(s) which may be after the display segments OBXs.
// (Display segments can be identified by having AUSPDI OBX-3 <name of coding
// system>)". The signature OBX is identified on p 438 (the HL7au:000010
// comment): "Digital signature OBX can identified by OBX-3 (CE) identifier
// component starting with "AUSETAV", and OBX-3 name of code system component
// "L"".

import Testing
@testable import HL7v2Kit

@Suite("AU display OBX last in its OBR/OBX group (HL7au:000008.1.5)")
struct AUDisplayOrderingTests {
    private static let atomic = "OBX|1|NM|718-7^Haemoglobin^LN||140|g/L|||||F\r"
    private static let display = "OBX|2|FT|PIT^Display format in PIT^AUSPDI||Haemoglobin 140 g/L||||||F\r"
    private static let signature = "OBX|3|ED|AUSETAV1^Digital signature^L||^application^octet-stream^Base64^AAAA||||||F\r"

    private func findings(messageType: String = "ORU^R01^ORU_R01", groups: [String]) throws -> [ValidationIssue] {
        var wire = "MSH|^~\\&|LAB|ACME Pathology|GP APP|Good Practice|20240101120000+1000||\(messageType)|MSG00001|P|2.4|||AL|NE|AUS|||en^English^ISO639\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
        for (index, obx) in groups.enumerated() {
            wire += "OBR|\(index + 1)||F\(index + 1)^ACME|FBC^Full blood count^L\r" + obx
        }
        let message = try Parser(locale: .auLocalisation).parse(wire)
        return Validator(locale: .auLocalisation).validate(message).issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code {
                return rule.hasPrefix("HL7au:000008.1.5")
            }
            return false
        }
    }

    @Test("Atomic, display, atomic fires once at the third OBX")
    func observationAfterDisplayFires() throws {
        let issues = try findings(groups: [Self.atomic + Self.display + Self.atomic])
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(issues.first?.location == IssueLocation(segmentID: "OBX", segmentIndex: 3))
    }

    @Test("Atomic, display, signature is silent")
    func signatureAfterDisplaySilent() throws {
        #expect(try findings(groups: [Self.atomic + Self.display + Self.signature]).isEmpty)
    }

    @Test("Display, signature, then an atomic OBX fires on the atomic (S2-3 pin)")
    func atomicAfterSignatureFires() throws {
        let issues = try findings(groups: [Self.display + Self.signature + Self.atomic])
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(issues.first?.location == IssueLocation(segmentID: "OBX", segmentIndex: 3))
    }

    @Test("A group with no display OBX is silent (HL7au:000008 reports the missing display)")
    func groupWithoutDisplaySilent() throws {
        #expect(try findings(groups: [Self.atomic + Self.atomic]).isEmpty)
    }

    @Test("Two groups each ending in a display OBX are silent")
    func twoOrderedGroupsSilent() throws {
        #expect(try findings(groups: [Self.atomic + Self.display, Self.atomic + Self.display]).isEmpty)
    }

    @Test("The second group's violation is reported in that group only")
    func secondGroupViolationFires() throws {
        let issues = try findings(groups: [Self.atomic + Self.display, Self.display + Self.atomic])
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(issues.first?.location == IssueLocation(segmentID: "OBX", segmentIndex: 4))
    }

    @Test("A REF with an observation after the display fires")
    func referralFires() throws {
        let wire = "MSH|^~\\&|GP APP|Good Practice|SPEC|Good Hospital|20240101120000+1000||REF^I12^REF_I12|MSG00002|P|2.4|||AL|NE|AUS|||en^English^ISO639\r"
            + "RF1||||||RN0001\r"
            + "PRD|RP|DOE^JANE\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
            + "OBR|1||F1^GOODPRAC|11488-4^Consult note^LN\r"
            + "OBX|1|ED|PDF^Display format in PDF^AUSPDI||^application^pdf^Base64^AAAA||||||F\r"
            + Self.atomic
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let issues = Validator(locale: .auLocalisation).validate(message).issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code { return rule.hasPrefix("HL7au:000008.1.5") }
            return false
        }
        #expect(issues.count == 1, "got \(issues.map(\.message))")
    }

    @Test("P12 S3-2: the count and ordering rules share one resolution per group, a miss included")
    func groupResolvedOnce() throws {
        let wire = "MSH|^~\\&|LAB|ACME|GP|GP|20240101120000+1000||ORU^R01^ORU_R01|M1|P|2.4\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
            + "OBR|1||F1^ACME|FBC^Full blood count^L\r" + Self.atomic + Self.display
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let validator = Validator(locale: .auLocalisation)
        var cache = Validator.GroupResolutionCache()
        var resolutions = 0
        for anchor in [2, 2, 1, 1] {
            let cached = validator.resolveGroup(scope: .obrObxGroup, anchorIndex: anchor, counted: "OBX",
                                                message: message, cache: &cache)
            _ = cache.group(scope: .obrObxGroup, anchorIndex: anchor, counted: "OBX") { resolutions += 1; return nil }
            let direct = validator.resolveGroup(scope: .obrObxGroup, anchorIndex: anchor, counted: "OBX", message: message)
            #expect(cached?.indices == direct?.indices)
        }
        #expect(resolutions == 0, "every lookup after the first per key is a cache hit")
    }

    @Test("An ORM is out of scope (the point names Results and Referrals)")
    func orderSilent() throws {
        #expect(try findings(messageType: "ORM^O01^ORM_O01", groups: [Self.display + Self.atomic]).isEmpty)
    }
}
