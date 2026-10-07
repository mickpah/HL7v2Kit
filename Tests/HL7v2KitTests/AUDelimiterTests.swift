// AUDelimiterTests.swift
// P12 S2-2 item 2: HL7au:000024.1 to .5, the delimiters, on MSH, FHS and BHS.
// AU ADRM-2021.1 Appendix 5: 000024.1 (p 440, Orders, Results, Referrals)
// "FHS, BHS, and MSH segments must specify the Field separator character
// as '|'"; 000024.2 (p 441, Orders, Results, Referrals) "... the Components
// separator character as '^'"; 000024.3, .4, .5 (p 441, Orders, Results)
// "... the Sub-components separator characters '&'", "... the repeat
// separator character as '~'", "... the escape separator character as '\'".

import Testing
@testable import HL7v2Kit

@Suite("AU delimiters on MSH, FHS and BHS (HL7au:000024)")
struct AUDelimiterTests {
    private func messageFindings(_ wire: String) throws -> [ValidationIssue] {
        let report = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(wire))
        return report.issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code { return rule.hasPrefix("HL7au:000024") }
            return false
        }
    }

    private func batchFindings(_ wire: String, locale: HL7Locale = .auLocalisation) throws -> [ValidationIssue] {
        let report = BatchValidator(locale: locale).validate(try BatchParser().parse(wire))
        return report.batchIssues.filter {
            if case .profileConstraintViolation(let rule) = $0.code { return rule.hasPrefix("HL7au:000024") }
            return false
        }
    }

    private func rule(_ issue: ValidationIssue?) -> String? {
        if case .profileConstraintViolation(let rule)? = issue?.code { return rule }
        return nil
    }

    private let oru = "MSH|^~\\&|LAB|FAC|GP|FAC|||ORU^R01^ORU_R01|M-ORU|P|2.4\rPID|1||1^^^H^MR\r"
    private let ref = "MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12^REF_I12|M-REF|P|2.4\rPID|1||X^^^F^MR\r"

    // MARK: MSH, the Referrals leg of 000024.2

    @Test("A REF whose MSH-2 component separator is not '^' fires HL7au:000024.2 at MSH-2.1")
    func refComponentSeparatorFires() throws {
        let issues = try messageFindings(
            "MSH|#~\\&|GP|CLINIC|SPEC|HOSP|20240101||REF#I12#REF_I12|MSG|P|2.4\rPID|1||X###F#MR\r")
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(issues.first?.location == IssueLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 2, componentIndex: 1))
        #expect(rule(issues.first)?.hasPrefix("HL7au:000024.2 ") == true)
    }

    @Test("A REF with '^' as component separator is silent, whatever its other encoding characters")
    func refComponentSeparatorSilent() throws {
        #expect(try messageFindings(ref).isEmpty)
        #expect(try messageFindings(
            "MSH|^~\\#|GP|CLINIC|SPEC|HOSP|20240101||REF^I12^REF_I12|MSG|P|2.4\rPID|1||X^^^F^MR\r").isEmpty)
    }

    // MARK: FHS and BHS

    @Test("A batch of ORU whose BHS-2 starts with another character fires at BHS-2")
    func bhsEncodingCharactersFireOnResults() throws {
        let issues = try batchFindings("BHS|#~\\&|APP\r" + oru + "BTS|1\r")
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(issues.first?.location == IssueLocation(segmentID: "BHS", segmentIndex: 1, fieldIndex: 2))
        #expect(rule(issues.first)?.hasPrefix("HL7au:000024.2/.3/.4/.5") == true)
    }

    @Test("An FHS of a results file with a wrong sub-component separator fires at FHS-2")
    func fhsEncodingCharactersFireOnResults() throws {
        let issues = try batchFindings("FHS|^~\\#|APP\rBHS|^~\\&|APP\r" + oru + "BTS|1\rFTS|1\r")
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(issues.first?.location == IssueLocation(segmentID: "FHS", segmentIndex: 1, fieldIndex: 2))
    }

    @Test("A BHS field separator other than '|' fires HL7au:000024.1 at BHS-1")
    func bhsFieldSeparatorFires() throws {
        let issues = try batchFindings("BHS!^~\\&!APP\r" + oru + "BTS|1\r")
        #expect(issues.contains { rule($0)?.hasPrefix("HL7au:000024.1 ") == true
            && $0.location == IssueLocation(segmentID: "BHS", segmentIndex: 1, fieldIndex: 1) },
                "got \(issues.map(\.message))")
    }

    @Test("A referral batch: only the component separator (000024.2) is checked")
    func referralBatchChecksComponentSeparatorOnly() throws {
        #expect(try batchFindings("BHS|^~\\#|APP\r" + ref + "BTS|1\r").isEmpty)
        let issues = try batchFindings("BHS|#~\\&|APP\r" + ref + "BTS|1\r")
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(rule(issues.first)?.hasPrefix("HL7au:000024.2 ") == true)
    }

    @Test("A conformant FHS and BHS are silent; the international locale is silent")
    func conformantEnvelopeSilent() throws {
        let good = "FHS|^~\\&|APP\rBHS|^~\\&|APP\r" + oru + "BTS|1\rFTS|1\r"
        #expect(try batchFindings(good).isEmpty)
        #expect(try batchFindings("BHS|#~\\&|APP\r" + oru + "BTS|1\r", locale: .international).isEmpty)
    }

    @Test("A batch of messages outside the points' scope (ADT) is silent")
    func outOfScopeBatchSilent() throws {
        let adt = "MSH|^~\\&|HIS|FAC|HOSP|FAC|||ADT^A01|M-ADT|P|2.4\rPID|1||1^^^H^MR\r"
        #expect(try batchFindings("BHS|#~\\&|APP\r" + adt + "BTS|1\r").isEmpty)
    }
}
