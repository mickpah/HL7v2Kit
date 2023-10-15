// ComponentGrammarTests.swift
// v0.2-V2: component-level grammar in Validator. Each typed composite
// (XPN / CX / XAD) carries a `static let requiredComponents` list, and
// the validator emits `.requiredComponentMissing` when a populated
// composite is missing one of those components.
//
// The 48-fixture corpus is unaffected (every fixture that populates
// PID-5 / PID-3 / PID-11 also populates the family / id / street
// components). The corpus pin lives at the bottom.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Validator — component grammar (v0.2-V2)")
struct ComponentGrammarTests {

    // MARK: - XPN-1 (Family Name)

    @Test("PID-5 (XPN) populated without family name fires .requiredComponentMissing at PID[1]-5.1")
    func xpnFamilyNameMissing() throws {
        // PID-5 = ^John^A — given+middle present, family empty.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||^John^A||19800101|M\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let issue = try #require(report.errors.first { $0.code == .requiredComponentMissing && $0.location.fieldIndex == 5 })
        #expect(issue.location.segmentID == "PID")
        #expect(issue.location.componentIndex == 1)
        #expect(issue.location.pathDescription == "PID[1]-5.1")
        #expect(issue.message.contains("Family Name"))
        #expect(issue.message.contains("XPN"))
        #expect(issue.severity == .error)
    }

    @Test("PID-5 populated with family name → no .requiredComponentMissing")
    func xpnFamilyNamePresent() throws {
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        #expect(!report.errors.contains { $0.code == .requiredComponentMissing })
    }

    @Test("PID-5 empty entirely → required-field check fires, NOT component check")
    func xpnEmptyFieldHitsRequiredFieldNotComponent() throws {
        // PID-5 is R-optionality. Empty PID-5 produces .requiredFieldMissing,
        // not .requiredComponentMissing (the component check is skipped on
        // empty fields).
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR|||19800101|M\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let pid5Issues = report.errors.filter { $0.location.fieldIndex == 5 }
        #expect(pid5Issues.contains { $0.code == .requiredFieldMissing })
        #expect(!pid5Issues.contains { $0.code == .requiredComponentMissing })
    }

    // MARK: - CX-1 (ID Number)

    @Test("PID-3 (CX) populated without ID number fires .requiredComponentMissing at PID[1]-3.1")
    func cxIdMissing() throws {
        // PID-3 = ^4^M11^HOSP^MR — id empty, check digit + scheme + auth + type present.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||^4^M11^HOSP^MR||Smith^John||19800101|M\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let issue = try #require(report.errors.first { $0.code == .requiredComponentMissing && $0.location.fieldIndex == 3 })
        #expect(issue.location.componentIndex == 1)
        #expect(issue.location.pathDescription == "PID[1]-3.1")
        #expect(issue.message.contains("ID Number"))
        #expect(issue.message.contains("CX"))
    }

    @Test("PID-3 (CX, multi-rep) — each repetition is checked independently")
    func cxMultiRepEachChecked() throws {
        // PID-3 = 123456^^^HOSP^MR ~ ^^^MEDICARE^NI
        // Rep 1 has ID; rep 2 is missing it.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR~^^^MEDICARE^NI||Smith^John||19800101|M\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let cxIssues = report.errors.filter { $0.code == .requiredComponentMissing && $0.location.fieldIndex == 3 }
        // One issue — for the second repetition. Validator currently doesn't
        // disambiguate which repetition in the location; the pin documents
        // the count contract.
        #expect(cxIssues.count == 1)
    }

    // MARK: - XAD-1 (Street Address)

    @Test("PID-11 (XAD) populated without street address fires at PID[1]-11.1")
    func xadStreetMissing() throws {
        // Field map (counted pipe-by-pipe):
        //  1 setID=1, 2 empty, 3 ids=123456..., 4 empty, 5 name=Smith^John,
        //  6 empty, 7 DOB=19800101, 8 sex=M, 9 empty, 10 race=2106-3^White^HL70005,
        //  11 address=^Apt 5^Sydney^NSW^2000  ← street component empty.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||Smith^John||19800101|M||2106-3^White^HL70005|^Apt 5^Sydney^NSW^2000\r
        """
        let message = try Parser().parse(wire)
        // Sanity-check pipe count: PID-11.3 should be "Sydney".
        #expect(message["PID-11.3"] == "Sydney", "Wire mis-counted: XAD should land at PID-11")
        let report = Validator().validate(message)
        let issue = try #require(report.errors.first { $0.code == .requiredComponentMissing && $0.location.fieldIndex == 11 })
        #expect(issue.location.componentIndex == 1)
        #expect(issue.location.pathDescription == "PID[1]-11.1")
        #expect(issue.message.contains("Street Address"))
        #expect(issue.message.contains("XAD"))
    }

    // MARK: - Toggle behaviour

    @Test("checkComponentGrammar=false suppresses the component check")
    func toggleSuppresses() throws {
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||^John^A||19800101|M\r
        """
        let message = try Parser().parse(wire)
        let options = ValidationOptions(checkComponentGrammar: false)
        let report = Validator(options: options).validate(message)
        #expect(!report.errors.contains { $0.code == .requiredComponentMissing })
    }

    @Test(".lenient preset disables component-grammar enforcement")
    func lenientPresetDisables() throws {
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||^John^A||19800101|M\r
        """
        let message = try Parser().parse(wire)
        let report = Validator(options: .lenient).validate(message)
        #expect(!report.errors.contains { $0.code == .requiredComponentMissing })
    }

    @Test(".strict preset enables component-grammar enforcement")
    func strictPresetEnables() throws {
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||^John^A||19800101|M\r
        """
        let message = try Parser().parse(wire)
        let report = Validator(options: .strict).validate(message)
        #expect(report.errors.contains { $0.code == .requiredComponentMissing })
    }

    // MARK: - Composites without typed metadata

    @Test("Composites HL7v2Kit hasn't typed (CE / CWE / EI) are skipped silently")
    func untypedCompositesSkippedSilently() throws {
        // PID-10 (race) is CE-typed. CE doesn't yet have requiredComponents
        // metadata in HL7v2Kit, so an empty PID-10.1 with PID-10.2 populated
        // must NOT fire a component-grammar issue.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||Smith^John||19800101|M||^WhiteTextOnly\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let pid10Issues = report.errors.filter { $0.location.fieldIndex == 10 }
        #expect(!pid10Issues.contains { $0.code == .requiredComponentMissing })
    }

    // MARK: - Fixture corpus regression pin

    @Test("Fixture corpus is unaffected by component-grammar enforcement")
    func fixtureCorpusNoComponentErrors() throws {
        // Every gold-corpus fixture that populates an XPN / CX / XAD field
        // also populates the required component (family / id / street).
        // Pin so a future fixture addition that breaks this rule surfaces
        // here directly, alongside the existing
        // FixtureRoundTripTests.allValidProduceNonErrorReport check.
        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(at: fixturesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "hl7" }
            .filter { !$0.lastPathComponent.hasPrefix("malformed_") }
        #expect(!urls.isEmpty)
        for url in urls {
            let bytes = try Data(contentsOf: url)
            guard let message = try? Parser().parse(bytes) else { continue }
            let report = Validator().validate(message)
            let componentIssues = report.errors.filter { $0.code == .requiredComponentMissing }
            #expect(componentIssues.isEmpty,
                    "\(url.lastPathComponent) unexpectedly hit a component-grammar check: \(componentIssues.map(\.message))")
        }
    }
}
